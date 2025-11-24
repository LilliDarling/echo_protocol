import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'secure_storage.dart';
import 'encryption.dart';
import '../utils/security.dart';

/// Service for managing partner relationships
/// Partners connect via invite codes/QR codes for secure 1-to-1 messaging
class PartnerService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final SecureStorageService _secureStorage;
  final EncryptionService _encryptionService;

  PartnerService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    SecureStorageService? secureStorage,
    EncryptionService? encryptionService,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _secureStorage = secureStorage ?? SecureStorageService(),
        _encryptionService = encryptionService ?? EncryptionService();

  static const int _inviteCodeLength = 8;
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

  /// Generate cryptographic signature for invite integrity
  Future<String> _generateInviteSignature({
    required String inviteCode,
    required String userId,
    required String publicKey,
    required DateTime expiresAt,
  }) async {
    final privateKey = await _secureStorage.getPrivateKey();
    if (privateKey == null) {
      throw Exception('Key not available');
    }

    final payload = '$inviteCode:$userId:${publicKey.substring(0, 32)}:${expiresAt.millisecondsSinceEpoch}';
    final privateKeyBytes = base64.decode(privateKey);
    final derivedKey = SecurityUtils.hkdfSha256(
      Uint8List.fromList(privateKeyBytes),
      Uint8List.fromList(utf8.encode('invite-signature-key')),
      Uint8List.fromList(utf8.encode('PartnerInviteSignature-v1')),
      32,
    );

    final hmac = Hmac(sha256, derivedKey);
    final digest = hmac.convert(utf8.encode(payload));

    return digest.toString();
  }

  bool _verifyInviteSignature({
    required String inviteCode,
    required String userId,
    required String publicKey,
    required DateTime expiresAt,
    required String signature,
  }) {
    if (inviteCode.isEmpty || userId.isEmpty || publicKey.length < 32) {
      return false;
    }

    if (signature.length != 64 || !RegExp(r'^[a-fA-F0-9]+$').hasMatch(signature)) {
      return false;
    }

    final now = DateTime.now();
    final minTime = now.subtract(const Duration(days: 30));
    final maxTime = now.add(const Duration(days: 2));
    if (expiresAt.isBefore(minTime) || expiresAt.isAfter(maxTime)) {
      return false;
    }

    return true;
  }

  /// Create an invite for a potential partner
  /// Returns the invite code that can be shared via QR or text
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

    // Check if user already has a partner
    final userDoc = await _db.collection('users').doc(user.uid).get();
    final existingPartnerId = userDoc.data()?['partnerId'] as String?;
    if (existingPartnerId != null) {
      throw Exception('You already have a partner linked');
    }

    // Cancel any existing invites
    await cancelExistingInvites();

    // Generate unique code
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

    // Get user's public key
    final publicKey = await _secureStorage.getPublicKey();
    if (publicKey == null) {
      throw Exception('Public key not found');
    }

    // Get user's name for display
    final userName = userDoc.data()?['name'] as String? ?? 'Unknown';
    final publicKeyVersion = userDoc.data()?['publicKeyVersion'] as int? ?? 1;

    // Create invite document
    final now = DateTime.now();
    final expiresAt = now.add(_inviteExpiry);

    // Generate signature for integrity verification
    final signature = await _generateInviteSignature(
      inviteCode: inviteCode,
      userId: user.uid,
      publicKey: publicKey,
      expiresAt: expiresAt,
    );

    // Generate fingerprint for out-of-band verification
    final fingerprint = _encryptionService.generateFingerprint(publicKey);

    await _db.collection('partnerInvites').doc(inviteCode).set({
      'userId': user.uid,
      'userName': userName,
      'publicKey': publicKey,
      'publicKeyVersion': publicKeyVersion,
      'publicKeyFingerprint': fingerprint,
      'signature': signature,
      'createdAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'used': false,
    });

    return inviteCode;
  }

  /// Cancel any existing invites created by the current user
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

  /// Accept an invite from a partner
  /// This establishes the bidirectional partner relationship
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

    // Normalize code (uppercase, remove spaces, dashes)
    final normalizedCode = inviteCode.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');

    if (normalizedCode.length != _inviteCodeLength ||
        !RegExp(r'^[A-Z0-9]+$').hasMatch(normalizedCode)) {
      throw Exception('Invalid invite code');
    }

    // Check if user already has a partner
    final userDoc = await _db.collection('users').doc(user.uid).get();
    final existingPartnerId = userDoc.data()?['partnerId'] as String?;
    if (existingPartnerId != null) {
      throw Exception('You already have a partner linked');
    }

    // Get invite document
    final inviteDoc = await _db
        .collection('partnerInvites')
        .doc(normalizedCode)
        .get();

    if (!inviteDoc.exists) {
      throw Exception('Invalid invite code');
    }

    final inviteData = inviteDoc.data()!;

    if (inviteData['used'] == true) {
      throw Exception('This invite code is no longer valid');
    }

    final expiresAt = (inviteData['expiresAt'] as Timestamp).toDate();
    if (DateTime.now().isAfter(expiresAt)) {
      throw Exception('This invite code is no longer valid');
    }

    final partnerId = inviteData['userId'] as String;
    if (partnerId == user.uid) {
      throw Exception('Invalid operation');
    }

    // Get partner's public key from invite
    final partnerPublicKey = inviteData['publicKey'] as String;
    final partnerKeyVersion = inviteData['publicKeyVersion'] as int? ?? 1;
    final partnerName = inviteData['userName'] as String? ?? 'Partner';
    final storedFingerprint = inviteData['publicKeyFingerprint'] as String?;
    final storedSignature = inviteData['signature'] as String?;

    if (!_encryptionService.isValidPublicKey(partnerPublicKey)) {
      throw Exception('Invalid invite data');
    }

    if (storedFingerprint != null) {
      final computedFingerprint = _encryptionService.generateFingerprint(partnerPublicKey);
      if (!SecurityUtils.constantTimeEquals(
        storedFingerprint.replaceAll(' ', ''),
        computedFingerprint.replaceAll(' ', ''),
      )) {
        throw Exception('Invalid invite data');
      }
    }

    if (storedSignature != null && !_verifyInviteSignature(
      inviteCode: normalizedCode,
      userId: partnerId,
      publicKey: partnerPublicKey,
      expiresAt: expiresAt,
      signature: storedSignature,
    )) {
      throw Exception('Invalid invite data');
    }

    final partnerDoc = await _db.collection('users').doc(partnerId).get();
    if (!partnerDoc.exists) {
      throw Exception('Partner not found');
    }
    final partnerExistingPartner = partnerDoc.data()?['partnerId'] as String?;
    if (partnerExistingPartner != null) {
      throw Exception('This user is already linked');
    }

    final myPublicKey = await _secureStorage.getPublicKey();
    if (myPublicKey == null) {
      throw Exception('Authentication error');
    }

    final myKeyVersion = await _secureStorage.getCurrentKeyVersion() ?? 1;

    await _secureStorage.storePartnerPublicKey(partnerPublicKey);
    _encryptionService.setPartnerPublicKey(partnerPublicKey);
    await _db.runTransaction((transaction) async {
      transaction.update(inviteDoc.reference, {
        'used': true,
        'usedAt': FieldValue.serverTimestamp(),
        'usedBy': user.uid,
      });

      transaction.update(_db.collection('users').doc(user.uid), {
        'partnerId': partnerId,
        'partnerPublicKey': partnerPublicKey,
        'partnerKeyVersion': partnerKeyVersion,
        'partnerLinkedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(_db.collection('users').doc(partnerId), {
        'partnerId': user.uid,
        'partnerPublicKey': myPublicKey,
        'partnerKeyVersion': myKeyVersion,
        'partnerLinkedAt': FieldValue.serverTimestamp(),
      });

      final conversationId = _generateConversationId(user.uid, partnerId);
      transaction.set(_db.collection('conversations').doc(conversationId), {
        'participants': [user.uid, partnerId],
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessage': null,
        'unreadCount': {
          user.uid: 0,
          partnerId: 0,
        },
      });
    });

    final partnerFingerprint = _encryptionService.generateFingerprint(partnerPublicKey);

    return PartnerInfo(
      id: partnerId,
      name: partnerName,
      publicKey: partnerPublicKey,
      keyVersion: partnerKeyVersion,
      fingerprint: partnerFingerprint,
      isNewlyLinked: true,
    );
  }

  String _generateConversationId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  /// Get the current user's partner info
  Future<PartnerInfo?> getPartner() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final userDoc = await _db.collection('users').doc(user.uid).get();
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
  }

  /// Check if current user has a partner linked
  Future<bool> hasPartner() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final userDoc = await _db.collection('users').doc(user.uid).get();
    return userDoc.data()?['partnerId'] != null;
  }

  /// Get the conversation ID for the current user and their partner
  Future<String?> getConversationId() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final partnerId = userDoc.data()?['partnerId'] as String?;

    if (partnerId == null) return null;

    return _generateConversationId(user.uid, partnerId);
  }

  /// Stream of partner info for real-time updates
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
      'partnerPublicKey': FieldValue.delete(),
      'partnerKeyVersion': FieldValue.delete(),
      'partnerLinkedAt': FieldValue.delete(),
    });

    batch.update(_db.collection('users').doc(partnerId), {
      'partnerId': FieldValue.delete(),
      'partnerPublicKey': FieldValue.delete(),
      'partnerKeyVersion': FieldValue.delete(),
      'partnerLinkedAt': FieldValue.delete(),
    });

    await batch.commit();
  }

  Future<void> initializePartnerEncryption() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final partnerPublicKey = userDoc.data()?['partnerPublicKey'] as String?;

    if (partnerPublicKey != null) {
      await _secureStorage.storePartnerPublicKey(partnerPublicKey);
      _encryptionService.setPartnerPublicKey(partnerPublicKey);
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
      _encryptionService.setPartnerPublicKey(currentPublicKey);

      return true;
    }

    return false;
  }
}

/// Partner information model
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
