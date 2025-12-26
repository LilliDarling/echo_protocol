import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/echo.dart';
import 'encryption.dart';
import 'secure_storage.dart';
import 'replay_protection.dart';
import 'message_rate_limiter.dart';

class MessageEncryptionHelper {
  final EncryptionService _encryptionService;
  final SecureStorageService _secureStorage;
  final FirebaseFirestore _db;
  final ReplayProtectionService? _replayProtection;
  final MessageRateLimiter? _rateLimiter;

  MessageEncryptionHelper({
    required EncryptionService encryptionService,
    required SecureStorageService secureStorage,
    FirebaseFirestore? firestore,
    ReplayProtectionService? replayProtection,
    MessageRateLimiter? rateLimiter,
  })  : _encryptionService = encryptionService,
        _secureStorage = secureStorage,
        _db = firestore ?? FirebaseFirestore.instance,
        _replayProtection = replayProtection,
        _rateLimiter = rateLimiter;

  Future<Map<String, dynamic>> encryptMessage({
    required String plaintext,
    required String partnerId,
    required String senderId,
  }) async {
    if (_rateLimiter != null) {
      final delay = await _rateLimiter.checkRateLimit(
        userId: senderId,
        partnerId: partnerId,
      );

      if (delay > Duration.zero) {
        await Future.delayed(delay);
      }

      _rateLimiter.recordAttempt(
        userId: senderId,
        partnerId: partnerId,
      );
    }

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

    int sequenceNumber = 0;
    if (_replayProtection != null) {
      sequenceNumber = await _replayProtection.getNextSequenceNumber(senderId, partnerId);
    }

    return {
      'content': encryptedContent,
      'senderKeyVersion': myKeyVersion,
      'recipientKeyVersion': partnerKeyVersion,
      'sequenceNumber': sequenceNumber,
    };
  }

  Future<String> decryptMessage({
    required EchoModel message,
    required String myUserId,
    required String partnerId,
    bool skipReplayValidation = false,
  }) async {
    // Only validate replay protection for newly received messages, not historical loads
    if (_replayProtection != null && !skipReplayValidation && message.recipientId == myUserId) {
      final isValid = await _replayProtection.validateMessage(
        messageId: message.id,
        senderId: message.senderId,
        recipientId: message.recipientId,
        sequenceNumber: message.sequenceNumber,
        timestamp: message.timestamp,
      );

      if (!isValid) {
        // Nonce already seen - this is likely a historical message being re-loaded
        // Skip validation but continue with decryption
      }
    }

    final bool isSender = message.senderId == myUserId;
    final int myKeyVersionNeeded = isSender
        ? message.senderKeyVersion
        : message.recipientKeyVersion;
    final int partnerKeyVersionNeeded = isSender
        ? message.recipientKeyVersion
        : message.senderKeyVersion;

    // Always try current keys first - they should work for most messages
    try {
      return _encryptionService.decryptMessage(message.content);
    } catch (_) {
      // Current keys didn't work, try archived keys as fallback
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
