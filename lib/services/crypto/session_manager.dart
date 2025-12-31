import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../models/crypto/identity_key.dart';
import '../../models/crypto/prekey.dart';
import '../../models/crypto/ratchet_session.dart';
import '../../models/crypto/encrypted_message.dart';
import '../../utils/security.dart';
import '../secure_storage.dart';
import 'x3dh_service.dart';
import 'double_ratchet_service.dart';

class _SessionLock {
  Completer<void>? _completer;

  Future<void> acquire() async {
    while (_completer != null) {
      await _completer!.future;
    }
    _completer = Completer<void>();
  }

  void release() {
    final completer = _completer;
    _completer = null;
    completer?.complete();
  }

  bool get isLocked => _completer != null;
}

class _ProtectedSessionCache {
  final Map<String, String> _scrambledSessions = {};
  Uint8List? _scrambleKey;

  _ProtectedSessionCache() {
    _rotateScrambleKey();
  }

  void _rotateScrambleKey() {
    if (_scrambleKey != null) {
      SecurityUtils.secureClear(_scrambleKey!);
    }
    _scrambleKey = SecurityUtils.generateSecureRandomBytes(32);
  }

  void put(String sessionId, RatchetSession session) {
    final json = jsonEncode(session.toJson());
    final bytes = Uint8List.fromList(utf8.encode(json));
    final scrambled = _xorScramble(bytes);
    _scrambledSessions[sessionId] = base64Encode(scrambled);
  }

  RatchetSession? get(String sessionId) {
    final scrambled = _scrambledSessions[sessionId];
    if (scrambled == null) return null;

    try {
      final bytes = base64Decode(scrambled);
      final unscrambled = _xorScramble(bytes);
      final json = utf8.decode(unscrambled);
      return RatchetSession.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      _scrambledSessions.remove(sessionId);
      return null;
    }
  }

  bool containsKey(String sessionId) => _scrambledSessions.containsKey(sessionId);

  void remove(String sessionId) {
    _scrambledSessions.remove(sessionId);
  }

  void clear() {
    _scrambledSessions.clear();
    _rotateScrambleKey();
  }

  Uint8List _xorScramble(Uint8List data) {
    final result = Uint8List(data.length);
    for (int i = 0; i < data.length; i++) {
      result[i] = data[i] ^ _scrambleKey![i % _scrambleKey!.length];
    }
    return result;
  }

  Iterable<String> get keys => _scrambledSessions.keys;

  void dispose() {
    _scrambledSessions.clear();
    if (_scrambleKey != null) {
      SecurityUtils.secureClear(_scrambleKey!);
      _scrambleKey = null;
    }
  }
}

class SessionManager {
  final X3DHService _x3dh = X3DHService();
  final DoubleRatchetService _ratchet = DoubleRatchetService();
  final SecureStorageService _storage = SecureStorageService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  final _ProtectedSessionCache _sessionCache = _ProtectedSessionCache();
  final Map<String, _SessionLock> _sessionLocks = {};

  _SessionLock _getLock(String sessionId) {
    return _sessionLocks.putIfAbsent(sessionId, () => _SessionLock());
  }

  static const String _identityKeyPrefix = 'identity_';
  static const String _signedPrekeyPrefix = 'signed_prekey_';
  static const String _otpPrefix = 'otp_';
  static const String _sessionPrefix = 'session_';
  static const String _sessionIdsKey = 'session_ids';
  static const String _nextOtpIdKey = 'next_otp_id';
  static const String _currentSpkIdKey = 'current_spk_id';

  Future<IdentityKeyPair?> loadIdentityKey() async {
    final data = await _loadPrefixedData(_identityKeyPrefix);
    if (data.isEmpty) return null;
    return IdentityKeyPair.fromSecureStorage(data);
  }

  Future<void> saveIdentityKey(IdentityKeyPair identityKey) async {
    final data = await identityKey.toSecureStorage();
    await _savePrefixedData(_identityKeyPrefix, data);
  }

  Future<IdentityKeyPair> getOrCreateIdentityKey({Uint8List? seed}) async {
    final existing = await loadIdentityKey();
    if (existing != null) return existing;

    final identityKey = await _x3dh.generateIdentityKeyPair(seed: seed);
    await saveIdentityKey(identityKey);
    return identityKey;
  }

  Future<SignedPrekey?> loadCurrentSignedPrekey() async {
    final currentId = await _getInt(_currentSpkIdKey);
    if (currentId == null) return null;

    final data = await _loadPrefixedData('$_signedPrekeyPrefix$currentId');
    if (data.isEmpty) return null;
    return SignedPrekey.fromSecureStorage(data);
  }

  Future<void> saveSignedPrekey(SignedPrekey prekey) async {
    final data = await prekey.toSecureStorage();
    await _savePrefixedData('$_signedPrekeyPrefix${prekey.id}', data);
    await _setInt(_currentSpkIdKey, prekey.id);
  }

  Future<SignedPrekey> getOrCreateSignedPrekey(IdentityKeyPair identityKey) async {
    final existing = await loadCurrentSignedPrekey();
    if (existing != null && !existing.isExpired) return existing;

    final nextId = (await _getInt(_currentSpkIdKey) ?? 0) + 1;
    final prekey = await _x3dh.generateSignedPrekey(
      identityKey: identityKey,
      id: nextId,
    );
    await saveSignedPrekey(prekey);
    return prekey;
  }

  Future<OneTimePrekey?> loadOneTimePrekey(int id) async {
    final data = await _loadPrefixedData('$_otpPrefix$id');
    if (data.isEmpty) return null;
    return OneTimePrekey.fromSecureStorage(data);
  }

  Future<void> _deleteOneTimePrekey(int id) async {
    await _deletePrefixedData('$_otpPrefix$id');
  }

  Future<void> saveOneTimePrekeys(List<OneTimePrekey> prekeys) async {
    for (final prekey in prekeys) {
      final data = await prekey.toSecureStorage();
      await _savePrefixedData('$_otpPrefix${prekey.id}', data);
    }
    if (prekeys.isNotEmpty) {
      final maxId = prekeys.map((p) => p.id).reduce((a, b) => a > b ? a : b);
      await _setInt(_nextOtpIdKey, maxId + 1);
    }
  }

  Future<List<OneTimePrekey>> generateAndSaveOneTimePrekeys({int count = 50}) async {
    final startId = await _getInt(_nextOtpIdKey) ?? 1;
    final prekeys = await _x3dh.generateOneTimePrekeys(startId: startId, count: count);
    await saveOneTimePrekeys(prekeys);
    return prekeys;
  }

  Future<RatchetSession?> loadSession(String sessionId) async {
    if (_sessionCache.containsKey(sessionId)) {
      return _sessionCache.get(sessionId);
    }

    final data = await _loadPrefixedData('$_sessionPrefix$sessionId');
    if (data.isEmpty) return null;

    final session = RatchetSession.fromSecureStorage(data);
    _sessionCache.put(sessionId, session);
    return session;
  }

  Future<void> saveSession(RatchetSession session) async {
    _sessionCache.put(session.sessionId, session);
    final data = await session.toSecureStorage();
    await _savePrefixedData('$_sessionPrefix${session.sessionId}', data);

    final ids = await _getSessionIds();
    if (!ids.contains(session.sessionId)) {
      ids.add(session.sessionId);
      await _setSessionIds(ids);
    }
  }

  Future<void> deleteSession(String sessionId) async {
    final session = _sessionCache.get(sessionId);
    session?.dispose();
    _sessionCache.remove(sessionId);
    _sessionLocks.remove(sessionId);
    await _deletePrefixedData('$_sessionPrefix$sessionId');

    final ids = await _getSessionIds();
    ids.remove(sessionId);
    await _setSessionIds(ids);
  }

  Future<bool> hasActiveSession(String recipientId, String ourUserId) async {
    final sessionId = RatchetSession.generateSessionId(ourUserId, recipientId);
    final session = await loadSession(sessionId);
    return session != null && session.state == SessionState.active;
  }

  Future<RatchetSession?> getSession(String recipientId, String ourUserId) async {
    final sessionId = RatchetSession.generateSessionId(ourUserId, recipientId);
    return loadSession(sessionId);
  }

  Future<({RatchetSession session, PreKeyMessage message})> createSession({
    required String recipientId,
    required String ourUserId,
    required IdentityKeyPair ourIdentityKey,
    required Uint8List initialPlaintext,
  }) async {
    final bundle = await fetchPreKeyBundle(recipientId);

    final x3dhResult = await _x3dh.initiateSession(
      ourIdentityKey: ourIdentityKey,
      theirBundle: bundle,
    );

    final session = await _ratchet.initializeAsInitiator(
      x3dhResult: x3dhResult,
      ourUserId: ourUserId,
      theirUserId: recipientId,
      theirIdentityKey: bundle.identityKey,
      theirRatchetPublicKey: bundle.signedPrekey.publicKey,
    );

    final innerMessage = await _ratchet.encrypt(
      session: session,
      plaintext: initialPlaintext,
    );

    final ourIdentityPublic = await ourIdentityKey.toPublicKey();
    final preKeyMessage = PreKeyMessage(
      senderIdentityKeyEd25519: ourIdentityPublic.ed25519PublicKey,
      senderIdentityKeyX25519: ourIdentityPublic.x25519PublicKey,
      ephemeralKey: x3dhResult.ephemeralPublicKey!,
      signedPrekeyId: x3dhResult.signedPrekeyId,
      oneTimePrekeyId: x3dhResult.oneTimePrekeyId,
      innerMessage: innerMessage,
    );

    await saveSession(session);
    x3dhResult.dispose();

    return (session: session, message: preKeyMessage);
  }

  Future<({RatchetSession session, Uint8List plaintext})> acceptSession({
    required PreKeyMessage preKeyMessage,
    required String senderId,
    required String ourUserId,
    required IdentityKeyPair ourIdentityKey,
  }) async {
    final signedPrekey = await loadCurrentSignedPrekey();
    if (signedPrekey == null) {
      throw Exception('Session initialization failed');
    }

    OneTimePrekey? oneTimePrekey;
    if (preKeyMessage.oneTimePrekeyId != null) {
      oneTimePrekey = await loadOneTimePrekey(preKeyMessage.oneTimePrekeyId!);
      if (oneTimePrekey != null) {
        oneTimePrekey.consumed = true;
        await _deleteOneTimePrekey(preKeyMessage.oneTimePrekeyId!);
      }
    }

    final x3dhResult = await _x3dh.respondToSession(
      ourIdentityKey: ourIdentityKey,
      theirIdentityPublicKey: preKeyMessage.senderIdentityKeyX25519,
      theirEphemeralPublicKey: preKeyMessage.ephemeralKey,
      ourSignedPrekey: signedPrekey,
      ourOneTimePrekey: oneTimePrekey,
    );

    final theirIdentity = IdentityPublicKey(
      ed25519PublicKey: preKeyMessage.senderIdentityKeyEd25519,
      x25519PublicKey: preKeyMessage.senderIdentityKeyX25519,
      keyId: '',
    );

    final session = await _ratchet.initializeAsResponder(
      x3dhResult: x3dhResult,
      ourUserId: ourUserId,
      theirUserId: senderId,
      theirIdentityKey: theirIdentity,
      ourSignedPrekey: signedPrekey,
    );

    session.theirRatchetPublicKey = preKeyMessage.innerMessage.senderRatchetKey;

    final plaintext = await _ratchet.decrypt(
      session: session,
      message: preKeyMessage.innerMessage,
    );

    await saveSession(session);
    x3dhResult.dispose();

    return (session: session, plaintext: plaintext);
  }

  Future<EncryptedMessage> encrypt({
    required String recipientId,
    required String ourUserId,
    required Uint8List plaintext,
    required IdentityKeyPair ourIdentityKey,
  }) async {
    final sessionId = RatchetSession.generateSessionId(ourUserId, recipientId);
    final lock = _getLock(sessionId);

    await lock.acquire();
    try {
      var session = await getSession(recipientId, ourUserId);

      if (session == null) {
        final result = await createSession(
          recipientId: recipientId,
          ourUserId: ourUserId,
          ourIdentityKey: ourIdentityKey,
          initialPlaintext: plaintext,
        );
        return EncryptedMessage.fromBytes(result.message.toBytes());
      }

      final message = await _ratchet.encrypt(session: session, plaintext: plaintext);
      await saveSession(session);
      return message;
    } finally {
      lock.release();
    }
  }

  Future<Uint8List> decrypt({
    required String senderId,
    required String ourUserId,
    required Uint8List messageBytes,
    required IdentityKeyPair ourIdentityKey,
  }) async {
    final sessionId = RatchetSession.generateSessionId(ourUserId, senderId);
    final lock = _getLock(sessionId);

    await lock.acquire();
    try {
      if (PreKeyMessage.isPreKeyMessage(messageBytes)) {
        final preKeyMessage = PreKeyMessage.fromBytes(messageBytes);
        final result = await acceptSession(
          preKeyMessage: preKeyMessage,
          senderId: senderId,
          ourUserId: ourUserId,
          ourIdentityKey: ourIdentityKey,
        );
        return result.plaintext;
      }

      final session = await getSession(senderId, ourUserId);
      if (session == null) {
        throw Exception('Decryption failed');
      }

      final message = EncryptedMessage.fromBytes(messageBytes);
      final plaintext = await _ratchet.decrypt(session: session, message: message);
      await saveSession(session);
      return plaintext;
    } finally {
      lock.release();
    }
  }

  Future<PreKeyBundle> fetchPreKeyBundle(String recipientId) async {
    try {
      final result = await _functions.httpsCallable('getPreKeyBundle').call({
        'recipientId': recipientId,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      return PreKeyBundle.fromJson(data);
    } catch (e) {
      throw Exception(
        'Failed to fetch prekey bundle: Cloud Function unavailable. '
        'Cannot establish secure session without atomic OTP claim.',
      );
    }
  }

  Future<void> uploadPreKeys({
    required IdentityKeyPair identityKey,
    required SignedPrekey signedPrekey,
    required List<OneTimePrekey> oneTimePrekeys,
  }) async {
    final identityPublic = await identityKey.toPublicKey();
    final signedPrekeyPublic = await signedPrekey.toPublic();
    final otpPublics = await Future.wait(oneTimePrekeys.map((p) => p.toPublic()));

    try {
      await _functions.httpsCallable('uploadPreKeys').call({
        'identityKey': identityPublic.toJson(),
        'signedPrekey': signedPrekeyPublic.toJson(),
        'oneTimePrekeys': otpPublics.map((p) => p.toJson()).toList(),
      });
    } catch (e) {
      final userId = await _storage.getUserId();
      if (userId == null) throw Exception('User not authenticated');

      await _db.collection('users').doc(userId).set({
        'identityKey': identityPublic.toJson(),
        'signedPrekey': signedPrekeyPublic.toJson(),
        'registrationId': DateTime.now().millisecondsSinceEpoch % 65536,
      }, SetOptions(merge: true));

      final batch = _db.batch();
      for (final otp in otpPublics) {
        batch.set(
          _db.collection('users').doc(userId).collection('oneTimePrekeys').doc(otp.id.toString()),
          otp.toJson(),
        );
      }
      await batch.commit();
    }
  }

  Future<void> replenishPreKeysIfNeeded({
    required IdentityKeyPair identityKey,
    int threshold = 10,
    int batchSize = 50,
  }) async {
    try {
      final result = await _functions.httpsCallable('checkPreKeyCount').call({});
      final data = result.data as Map<String, dynamic>;
      final count = data['oneTimePrekeyCount'] as int;

      if (count >= threshold) return;

      final newPrekeys = await generateAndSaveOneTimePrekeys(count: batchSize);
      final signedPrekey = await getOrCreateSignedPrekey(identityKey);

      await uploadPreKeys(
        identityKey: identityKey,
        signedPrekey: signedPrekey,
        oneTimePrekeys: newPrekeys,
      );
    } catch (_) {
      final newPrekeys = await generateAndSaveOneTimePrekeys(count: batchSize);
      final signedPrekey = await getOrCreateSignedPrekey(identityKey);

      await uploadPreKeys(
        identityKey: identityKey,
        signedPrekey: signedPrekey,
        oneTimePrekeys: newPrekeys,
      );
    }
  }

  Future<void> cleanupAllSessions() async {
    for (final id in _sessionCache.keys.toList()) {
      final session = _sessionCache.get(id);
      if (session != null) {
        _ratchet.cleanupExpiredSkippedKeys(session);
        _sessionCache.put(id, session);
      }
    }

    final ids = await _getSessionIds();
    for (final id in ids) {
      if (!_sessionCache.containsKey(id)) {
        final session = await loadSession(id);
        if (session != null) {
          _ratchet.cleanupExpiredSkippedKeys(session);
          await saveSession(session);
        }
      }
    }
  }

  void dispose() {
    for (final id in _sessionCache.keys.toList()) {
      final session = _sessionCache.get(id);
      session?.dispose();
    }
    _sessionCache.dispose();
    _sessionLocks.clear();
  }

  Future<Map<String, String>> _loadPrefixedData(String prefix) async {
    final result = <String, String>{};
    final stored = await _getString(prefix);
    if (stored != null) {
      final decoded = jsonDecode(stored) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        result[entry.key] = entry.value as String;
      }
    }
    return result;
  }

  Future<void> _savePrefixedData(String prefix, Map<String, String> data) async {
    await _setString(prefix, jsonEncode(data));
  }

  Future<void> _deletePrefixedData(String prefix) async {
    await _deleteString(prefix);
  }

  Future<String?> _getString(String key) async {
    final allData = await FlutterSecureStorage().readAll();
    return allData[key];
  }

  Future<void> _setString(String key, String value) async {
    await const FlutterSecureStorage().write(key: key, value: value);
  }

  Future<void> _deleteString(String key) async {
    await const FlutterSecureStorage().delete(key: key);
  }

  Future<int?> _getInt(String key) async {
    final str = await _getString(key);
    return str != null ? int.tryParse(str) : null;
  }

  Future<void> _setInt(String key, int value) async {
    await _setString(key, value.toString());
  }

  Future<List<String>> _getSessionIds() async {
    final str = await _getString(_sessionIdsKey);
    if (str == null) return [];
    return (jsonDecode(str) as List).cast<String>();
  }

  Future<void> _setSessionIds(List<String> ids) async {
    await _setString(_sessionIdsKey, jsonEncode(ids));
  }
}
