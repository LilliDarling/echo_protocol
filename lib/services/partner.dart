import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'secure_storage.dart';
import 'crypto/protocol_service.dart';
import '../utils/security.dart';

class PartnerService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final SecureStorageService _secureStorage;
  final ProtocolService _protocolService;

  PartnerService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    SecureStorageService? secureStorage,
    ProtocolService? protocolService,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _secureStorage = secureStorage ?? SecureStorageService(),
        _protocolService = protocolService ?? ProtocolService();

  static const int _inviteCodeLength = 12;
  static const Duration _inviteExpiry = Duration(hours: 24);

  static const int _maxInviteCreationsPerHour = 5;
  static const int _maxInviteAcceptAttemptsPerHour = 10;
  static const Duration _rateLimitWindow = Duration(hours: 1);

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(
      _inviteCodeLength,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  Future<({String signature, String ed25519PublicKey, String publicKeyHash})> _generateInviteSignature({
    required String inviteCode,
    required String userId,
    required String publicKey,
    required String userName,
    required String publicKeyFingerprint,
    required int publicKeyVersion,
    required DateTime expiresAt,
  }) async {
    if (!_protocolService.isInitialized) {
      throw Exception('Encryption keys not available');
    }

    final publicKeyHash = sha256.convert(utf8.encode(publicKey)).toString();

    final payload = '$inviteCode:$userId:$publicKeyHash:$userName:$publicKeyFingerprint:$publicKeyVersion:${expiresAt.millisecondsSinceEpoch}';
    final payloadBytes = Uint8List.fromList(utf8.encode(payload));

    final result = await _protocolService.sign(payloadBytes);

    return (
      signature: base64Encode(result.signature),
      ed25519PublicKey: base64Encode(result.publicKey),
      publicKeyHash: publicKeyHash,
    );
  }

  Future<String> createInvite() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final rateLimitKey = 'invite_create_${user.uid}';
    if (!SecurityUtils.checkRateLimit(
      rateLimitKey,
      _maxInviteCreationsPerHour,
      _rateLimitWindow,
    )) {
      throw Exception('Too many invite attempts. Please try again later.');
    }

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final existingPartnerId = userDoc.data()?['partnerId'] as String?;
    if (existingPartnerId != null) {
      throw Exception('You already have a partner linked');
    }

    await cancelExistingInvites();

    String inviteCode;
    bool codeExists = true;
    int attempts = 0;
    const maxAttempts = 10;

    do {
      inviteCode = _generateInviteCode();
      final existing = await _db
          .collection('partnerInvites')
          .doc(inviteCode)
          .get();
      codeExists = existing.exists;
      attempts++;
    } while (codeExists && attempts < maxAttempts);

    if (codeExists) {
      throw Exception('Failed to generate unique invite code');
    }

    var publicKey = await _secureStorage.getPublicKey();
    if (publicKey == null) {
      final storedPublicKey = userDoc.data()?['publicKey'] as String?;
      if (storedPublicKey != null) {
        publicKey = storedPublicKey;
        await _secureStorage.storePublicKey(storedPublicKey);
      } else {
        throw Exception('Public key not found. Please sign out and sign in again.');
      }
    }

    final userName = userDoc.data()?['name'] as String? ?? 'Unknown';

    final storedVersion = userDoc.data()?['publicKeyVersion'];
    int publicKeyVersion;
    if (storedVersion is int) {
      publicKeyVersion = storedVersion;
    } else if (storedVersion is String) {
      publicKeyVersion = int.tryParse(storedVersion) ?? 1;
    } else {
      publicKeyVersion = 1;
    }

    final now = DateTime.now();
    final expiresAt = now.add(_inviteExpiry);

    final fingerprint = await _protocolService.getFingerprint() ?? publicKey;

    final signatureResult = await _generateInviteSignature(
      inviteCode: inviteCode,
      userId: user.uid,
      publicKey: publicKey,
      userName: userName,
      publicKeyFingerprint: fingerprint,
      publicKeyVersion: publicKeyVersion,
      expiresAt: expiresAt,
    );

    await _db.collection('partnerInvites').doc(inviteCode).set({
      'userId': user.uid,
      'userName': userName,
      'publicKey': publicKey,
      'publicKeyHash': signatureResult.publicKeyHash,
      'publicKeyVersion': publicKeyVersion,
      'publicKeyFingerprint': fingerprint,
      'ed25519PublicKey': signatureResult.ed25519PublicKey,
      'signature': signatureResult.signature,
      'signatureVersion': 4,
      'createdAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'used': false,
    });

    return inviteCode;
  }

  Future<void> cancelExistingInvites() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final existingInvites = await _db
        .collection('partnerInvites')
        .where('userId', isEqualTo: user.uid)
        .where('used', isEqualTo: false)
        .get();

    final batch = _db.batch();
    for (final doc in existingInvites.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<PartnerInfo> acceptInvite(String inviteCode) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final rateLimitKey = 'invite_accept_${user.uid}';
    if (!SecurityUtils.checkRateLimit(
      rateLimitKey,
      _maxInviteAcceptAttemptsPerHour,
      _rateLimitWindow,
    )) {
      throw Exception('Too many attempts. Please try again later.');
    }

    final normalizedCode = inviteCode.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');

    if (normalizedCode.length != _inviteCodeLength ||
        !RegExp(r'^[A-Z0-9]+$').hasMatch(normalizedCode)) {
      throw Exception('Invalid invite code');
    }

    var myPublicKey = await _secureStorage.getPublicKey();
    var myKeyVersion = await _secureStorage.getCurrentKeyVersion();

    if (myPublicKey == null || myKeyVersion == null) {
      final userDoc = await _db.collection('users').doc(user.uid).get();
      final userData = userDoc.data();

      if (myPublicKey == null) {
        final storedPublicKey = userData?['publicKey'] as String?;
        if (storedPublicKey != null) {
          myPublicKey = storedPublicKey;
          await _secureStorage.storePublicKey(storedPublicKey);
        } else {
          throw Exception('Authentication error. Please sign out and sign in again.');
        }
      }

      if (myKeyVersion == null) {
        final storedVersion = userData?['publicKeyVersion'];
        if (storedVersion is int) {
          myKeyVersion = storedVersion;
        } else if (storedVersion is String) {
          myKeyVersion = int.tryParse(storedVersion) ?? 1;
        } else {
          myKeyVersion = 1;
        }
        await _secureStorage.storeCurrentKeyVersion(myKeyVersion);
      }
    }

    final functions = FirebaseFunctions.instance;
    final callable = functions.httpsCallable('acceptPartnerInvite');

    try {
      final result = await callable.call<Map<String, dynamic>>({
        'inviteCode': normalizedCode,
        'myPublicKey': myPublicKey,
        'myKeyVersion': myKeyVersion,
      });

      final data = result.data;
      final partnerId = data['partnerId'] as String;
      final partnerName = data['partnerName'] as String;
      final partnerPublicKey = data['partnerPublicKey'] as String;
      final partnerKeyVersion = data['partnerKeyVersion'] as int;
      final partnerFingerprint = data['partnerFingerprint'] as String?;

      await _secureStorage.storePartnerPublicKey(partnerPublicKey);

      return PartnerInfo(
        id: partnerId,
        name: partnerName,
        publicKey: partnerPublicKey,
        keyVersion: partnerKeyVersion,
        fingerprint: partnerFingerprint ?? partnerPublicKey,
        isNewlyLinked: true,
      );
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Failed to accept invite');
    }
  }

  String _generateConversationId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  Future<PartnerInfo?> getPartner({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final getOptions = forceRefresh
        ? const GetOptions(source: Source.server)
        : null;

    final userDoc = getOptions != null
        ? await _db.collection('users').doc(user.uid).get(getOptions)
        : await _db.collection('users').doc(user.uid).get();
    final partnerId = userDoc.data()?['partnerId'] as String?;

    if (partnerId == null) return null;

    final partnerDoc = getOptions != null
        ? await _db.collection('users').doc(partnerId).get(getOptions)
        : await _db.collection('users').doc(partnerId).get();
    if (!partnerDoc.exists) return null;

    final partnerData = partnerDoc.data()!;

    final storedKeyVersion = partnerData['publicKeyVersion'];
    int keyVersion;
    if (storedKeyVersion is int) {
      keyVersion = storedKeyVersion;
    } else if (storedKeyVersion is String) {
      keyVersion = int.tryParse(storedKeyVersion) ?? 1;
    } else {
      keyVersion = 1;
    }

    final publicKey = partnerData['publicKey'] as String?;
    if (publicKey == null) return null;

    return PartnerInfo(
      id: partnerId,
      name: partnerData['name'] as String? ?? 'Partner',
      avatar: partnerData['avatar'] as String?,
      publicKey: publicKey,
      keyVersion: keyVersion,
      lastActive: (partnerData['lastActive'] as Timestamp?)?.toDate(),
    );
  }

  Future<bool> hasPartner() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final userDoc = await _db.collection('users').doc(user.uid).get();
    return userDoc.data()?['partnerId'] != null;
  }

  Future<String?> getConversationId() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final partnerId = userDoc.data()?['partnerId'] as String?;

    if (partnerId == null) return null;

    return _generateConversationId(user.uid, partnerId);
  }

  Stream<PartnerInfo?> partnerStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(null);

    return _db
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .asyncMap((userDoc) async {
      final partnerId = userDoc.data()?['partnerId'] as String?;
      if (partnerId == null) return null;

      final partnerDoc = await _db.collection('users').doc(partnerId).get();
      if (!partnerDoc.exists) return null;

      final partnerData = partnerDoc.data()!;
      return PartnerInfo(
        id: partnerId,
        name: partnerData['name'] as String? ?? 'Partner',
        avatar: partnerData['avatar'] as String?,
        publicKey: partnerData['publicKey'] as String,
        keyVersion: partnerData['publicKeyVersion'] as int? ?? 1,
        lastActive: (partnerData['lastActive'] as Timestamp?)?.toDate(),
      );
    });
  }

  Future<void> unlinkPartner() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final partnerId = userDoc.data()?['partnerId'] as String?;

    if (partnerId == null) {
      throw Exception('No partner linked');
    }

    await _secureStorage.storePartnerPublicKey('');

    final batch = _db.batch();
    batch.update(_db.collection('users').doc(user.uid), {
      'partnerId': FieldValue.delete(),
      'partnerIdHash': FieldValue.delete(),
      'partnerPublicKey': FieldValue.delete(),
      'partnerKeyVersion': FieldValue.delete(),
      'partnerLinkedAt': FieldValue.delete(),
    });

    batch.update(_db.collection('users').doc(partnerId), {
      'partnerId': FieldValue.delete(),
      'partnerIdHash': FieldValue.delete(),
      'partnerPublicKey': FieldValue.delete(),
      'partnerKeyVersion': FieldValue.delete(),
      'partnerLinkedAt': FieldValue.delete(),
    });

    await batch.commit();
  }

  Future<void> initializePartnerEncryption() async {
    final user = _auth.currentUser;
    if (user == null) return;

    if (!_protocolService.isInitialized) {
      try {
        await _protocolService.initializeFromStorage();
      } catch (e) {
        return;
      }
    }

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final partnerPublicKey = userDoc.data()?['partnerPublicKey'] as String?;

    if (partnerPublicKey != null) {
      await _secureStorage.storePartnerPublicKey(partnerPublicKey);
    }
  }

  Future<bool> checkAndUpdatePartnerKey() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final partnerId = userDoc.data()?['partnerId'] as String?;
    final storedKeyVersion = userDoc.data()?['partnerKeyVersion'] as int?;

    if (partnerId == null) return false;

    final partnerDoc = await _db.collection('users').doc(partnerId).get();
    final currentKeyVersion = partnerDoc.data()?['publicKeyVersion'] as int?;
    final currentPublicKey = partnerDoc.data()?['publicKey'] as String?;

    if (currentKeyVersion != null &&
        storedKeyVersion != null &&
        currentKeyVersion > storedKeyVersion &&
        currentPublicKey != null) {
      await _db.collection('users').doc(user.uid).update({
        'partnerPublicKey': currentPublicKey,
        'partnerKeyVersion': currentKeyVersion,
      });

      await _secureStorage.storePartnerPublicKey(currentPublicKey);

      return true;
    }

    return false;
  }
}

class PartnerInfo {
  final String id;
  final String name;
  final String? avatar;
  final String publicKey;
  final int keyVersion;
  final DateTime? lastActive;
  final String? fingerprint;
  final bool isNewlyLinked;

  PartnerInfo({
    required this.id,
    required this.name,
    this.avatar,
    required this.publicKey,
    required this.keyVersion,
    this.lastActive,
    this.fingerprint,
    this.isNewlyLinked = false,
  });

  bool get isOnline {
    if (lastActive == null) return false;
    return DateTime.now().difference(lastActive!).inMinutes < 5;
  }

  PartnerInfo copyWithVerificationShown() {
    return PartnerInfo(
      id: id,
      name: name,
      avatar: avatar,
      publicKey: publicKey,
      keyVersion: keyVersion,
      lastActive: lastActive,
      fingerprint: fingerprint,
      isNewlyLinked: false,
    );
  }
}
