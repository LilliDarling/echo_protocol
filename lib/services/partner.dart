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
import '../models/key_change_event.dart';

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

    final identityKey = userDoc.data()?['identityKey'];
    if (identityKey == null || identityKey['ed25519'] == null) {
      if (!_protocolService.isInitialized) {
        throw Exception('Encryption not initialized. Please sign out and sign in again.');
      }
      await _protocolService.uploadPreKeys();
      final refreshedDoc = await _db.collection('users').doc(user.uid).get();
      if (refreshedDoc.data()?['identityKey']?['ed25519'] == null) {
        throw Exception('Failed to register identity key. Please try again.');
      }
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

  Future<({String signature, String ed25519PublicKey})> _generateAcceptSignature({
    required String inviteCode,
    required String userId,
    required int timestamp,
  }) async {
    if (!_protocolService.isInitialized) {
      throw Exception('Encryption keys not available');
    }

    final payload = '$inviteCode:$userId:$timestamp';
    final payloadBytes = Uint8List.fromList(utf8.encode(payload));
    final result = await _protocolService.sign(payloadBytes);

    return (
      signature: base64Encode(result.signature),
      ed25519PublicKey: base64Encode(result.publicKey),
    );
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

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final userData = userDoc.data();

    final identityKey = userData?['identityKey'];
    if (identityKey == null || identityKey['ed25519'] == null) {
      if (!_protocolService.isInitialized) {
        throw Exception('Encryption not initialized. Please sign out and sign in again.');
      }
      await _protocolService.uploadPreKeys();
      final refreshedDoc = await _db.collection('users').doc(user.uid).get();
      if (refreshedDoc.data()?['identityKey']?['ed25519'] == null) {
        throw Exception('Failed to register identity key. Please try again.');
      }
    }

    var myPublicKey = await _secureStorage.getPublicKey();
    var myKeyVersion = await _secureStorage.getCurrentKeyVersion();

    if (myPublicKey == null || myKeyVersion == null) {

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

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final signatureResult = await _generateAcceptSignature(
      inviteCode: normalizedCode,
      userId: user.uid,
      timestamp: timestamp,
    );

    final functions = FirebaseFunctions.instance;
    final callable = functions.httpsCallable('acceptPartnerInvite');

    try {
      final result = await callable.call<Map<String, dynamic>>({
        'inviteCode': normalizedCode,
        'myPublicKey': myPublicKey,
        'myKeyVersion': myKeyVersion,
        'timestamp': timestamp,
        'signature': signatureResult.signature,
        'ed25519PublicKey': signatureResult.ed25519PublicKey,
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

  String computeFingerprint(String publicKey) {
    final bytes = utf8.encode(publicKey);
    final hash = sha256.convert(bytes);
    final hex = hash.toString().toUpperCase();
    final chunks = <String>[];
    for (var i = 0; i < hex.length && chunks.length < 8; i += 4) {
      chunks.add(hex.substring(i, i + 4));
    }
    return chunks.join(' ');
  }

  Future<KeyChangeResult> checkPartnerKeyChange(String currentPublicKey) async {
    final currentFingerprint = computeFingerprint(currentPublicKey);
    final trustedFingerprint = await _secureStorage.getTrustedFingerprint();

    if (trustedFingerprint == null) {
      return KeyChangeResult(
        status: KeyChangeStatus.firstKey,
        currentFingerprint: currentFingerprint,
      );
    }

    if (trustedFingerprint != currentFingerprint) {
      return KeyChangeResult(
        status: KeyChangeStatus.changed,
        previousFingerprint: trustedFingerprint,
        currentFingerprint: currentFingerprint,
      );
    }

    return KeyChangeResult(
      status: KeyChangeStatus.noChange,
      previousFingerprint: trustedFingerprint,
      currentFingerprint: currentFingerprint,
    );
  }

  Future<KeyChangeEvent?> logKeyChangeEvent({
    required String previousFingerprint,
    required String newFingerprint,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final random = Random.secure();
    final visibleId = List.generate(8, (_) => random.nextInt(16).toRadixString(16)).join().toUpperCase();

    final event = KeyChangeEvent(
      id: '',
      visibleId: visibleId,
      detectedAt: DateTime.now(),
      previousFingerprint: previousFingerprint,
      newFingerprint: newFingerprint,
    );

    final docRef = await _db
        .collection('users')
        .doc(user.uid)
        .collection('key_change_events')
        .add(event.toFirestore());

    return KeyChangeEvent(
      id: docRef.id,
      visibleId: visibleId,
      detectedAt: event.detectedAt,
      previousFingerprint: previousFingerprint,
      newFingerprint: newFingerprint,
    );
  }

  Future<void> acknowledgeKeyChange(String eventId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _db
        .collection('users')
        .doc(user.uid)
        .collection('key_change_events')
        .doc(eventId)
        .update({
      'acknowledged': true,
      'acknowledgedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> trustCurrentKey(String publicKey) async {
    final fingerprint = computeFingerprint(publicKey);
    await _secureStorage.storeTrustedFingerprint(fingerprint);
  }

  Future<List<KeyChangeEvent>> getKeyChangeHistory() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    final snapshot = await _db
        .collection('users')
        .doc(user.uid)
        .collection('key_change_events')
        .orderBy('detectedAt', descending: true)
        .limit(50)
        .get();

    return snapshot.docs.map((doc) => KeyChangeEvent.fromFirestore(doc)).toList();
  }

  Future<KeyChangeEvent?> getUnacknowledgedKeyChange() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final snapshot = await _db
        .collection('users')
        .doc(user.uid)
        .collection('key_change_events')
        .where('acknowledged', isEqualTo: false)
        .orderBy('detectedAt', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return KeyChangeEvent.fromFirestore(snapshot.docs.first);
  }
}

class PartnerInfo {
  final String id;
  final String name;
  final String? avatar;
  final String publicKey;
  final int keyVersion;
  final String? fingerprint;
  final bool isNewlyLinked;

  PartnerInfo({
    required this.id,
    required this.name,
    this.avatar,
    required this.publicKey,
    required this.keyVersion,
    this.fingerprint,
    this.isNewlyLinked = false,
  });

  PartnerInfo copyWithVerificationShown() {
    return PartnerInfo(
      id: id,
      name: name,
      avatar: avatar,
      publicKey: publicKey,
      keyVersion: keyVersion,
      fingerprint: fingerprint,
      isNewlyLinked: false,
    );
  }
}
