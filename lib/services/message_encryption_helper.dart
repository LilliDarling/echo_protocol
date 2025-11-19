import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/echo.dart';
import 'encryption.dart';
import 'secure_storage.dart';

class MessageEncryptionHelper {
  final EncryptionService _encryptionService;
  final SecureStorageService _secureStorage;
  final FirebaseFirestore _db;

  MessageEncryptionHelper({
    required EncryptionService encryptionService,
    required SecureStorageService secureStorage,
    FirebaseFirestore? firestore,
  })  : _encryptionService = encryptionService,
        _secureStorage = secureStorage,
        _db = firestore ?? FirebaseFirestore.instance;

  Future<Map<String, dynamic>> encryptMessage({
    required String plaintext,
    required String partnerId,
  }) async {
    final myKeyVersion = await _secureStorage.getCurrentKeyVersion();
    if (myKeyVersion == null) {
      throw Exception('Current key version not found');
    }

    final partnerDoc = await _db.collection('users').doc(partnerId).get();
    final partnerKeyVersion = partnerDoc.data()?['publicKeyVersion'] as int?;
    if (partnerKeyVersion == null) {
      throw Exception('Partner key version not found');
    }

    final encryptedContent = _encryptionService.encryptMessage(plaintext);

    return {
      'content': encryptedContent,
      'senderKeyVersion': myKeyVersion,
      'recipientKeyVersion': partnerKeyVersion,
    };
  }

  Future<String> decryptMessage({
    required EchoModel message,
    required String myUserId,
    required String partnerId,
  }) async {
    final bool isSender = message.senderId == myUserId;
    final int myKeyVersionNeeded = isSender
        ? message.senderKeyVersion
        : message.recipientKeyVersion;
    final int partnerKeyVersionNeeded = isSender
        ? message.recipientKeyVersion
        : message.senderKeyVersion;

    try {
      final currentKeyVersion = await _secureStorage.getCurrentKeyVersion();
      if (currentKeyVersion == myKeyVersionNeeded) {
        return _encryptionService.decryptMessage(message.content);
      }
    } catch (e) {
      // Fall through to archived keys
    }

    return await _decryptWithArchivedKeys(
      encryptedContent: message.content,
      myKeyVersion: myKeyVersionNeeded,
      partnerId: partnerId,
      partnerKeyVersion: partnerKeyVersionNeeded,
    );
  }

  Future<String> _decryptWithArchivedKeys({
    required String encryptedContent,
    required int myKeyVersion,
    required String partnerId,
    required int partnerKeyVersion,
  }) async {
    final myPrivateKey = await _secureStorage.getArchivedPrivateKey(myKeyVersion);
    if (myPrivateKey == null) {
      throw Exception('Archived private key not found for version $myKeyVersion');
    }

    String? partnerPublicKey;

    try {
      final partnerKeyDoc = await _db
          .collection('users')
          .doc(partnerId)
          .collection('keyHistory')
          .doc(partnerKeyVersion.toString())
          .get();

      partnerPublicKey = partnerKeyDoc.data()?['publicKey'] as String?;
    } catch (e) {
      // Try current key
    }

    if (partnerPublicKey == null) {
      final partnerDoc = await _db.collection('users').doc(partnerId).get();
      final currentVersion = partnerDoc.data()?['publicKeyVersion'] as int?;

      if (currentVersion == partnerKeyVersion) {
        partnerPublicKey = partnerDoc.data()?['publicKey'] as String?;
      }
    }

    if (partnerPublicKey == null) {
      throw Exception('Partner public key not found for version $partnerKeyVersion');
    }

    return _encryptionService.decryptMessageWithKeyVersions(
      encryptedText: encryptedContent,
      myPrivateKeyPem: myPrivateKey,
      partnerPublicKeyPem: partnerPublicKey,
    );
  }

  Future<String> decryptMessageWithFallback({
    required String encryptedContent,
    required String partnerId,
  }) async {
    try {
      return _encryptionService.decryptMessage(encryptedContent);
    } catch (e) {
      // Try archived keys
    }

    final myArchivedVersions = await _secureStorage.getArchivedKeyVersions();

    final partnerDoc = await _db.collection('users').doc(partnerId).get();
    final partnerCurrentKey = partnerDoc.data()?['publicKey'] as String?;

    final partnerKeyHistoryDocs = await _db
        .collection('users')
        .doc(partnerId)
        .collection('keyHistory')
        .get();

    final partnerArchivedKeys = <int, String>{};
    for (final doc in partnerKeyHistoryDocs.docs) {
      final version = int.tryParse(doc.id);
      final key = doc.data()['publicKey'] as String?;
      if (version != null && key != null) {
        partnerArchivedKeys[version] = key;
      }
    }

    for (final myVersion in myArchivedVersions) {
      final myPrivateKey = await _secureStorage.getArchivedPrivateKey(myVersion);
      if (myPrivateKey == null) continue;

      if (partnerCurrentKey != null) {
        try {
          return _encryptionService.decryptMessageWithKeyVersions(
            encryptedText: encryptedContent,
            myPrivateKeyPem: myPrivateKey,
            partnerPublicKeyPem: partnerCurrentKey,
          );
        } catch (e) {
          // Try next
        }
      }

      for (final partnerKey in partnerArchivedKeys.values) {
        try {
          return _encryptionService.decryptMessageWithKeyVersions(
            encryptedText: encryptedContent,
            myPrivateKeyPem: myPrivateKey,
            partnerPublicKeyPem: partnerKey,
          );
        } catch (e) {
          // Try next
        }
      }
    }

    throw Exception('Failed to decrypt message with any available key combination');
  }
}
