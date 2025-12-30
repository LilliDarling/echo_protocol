import 'dart:convert';
import 'dart:typed_data';
import 'package:bip39/bip39.dart' as bip39;
import '../../models/crypto/identity_key.dart';
import '../secure_storage.dart';
import 'session_manager.dart';
import 'media_encryption.dart';

class ProtocolService {
  static final ProtocolService _instance = ProtocolService._internal();
  factory ProtocolService() => _instance;
  ProtocolService._internal() {
    _mediaService = MediaEncryptionService(sessionManager: _sessionManager);
  }

  final SessionManager _sessionManager = SessionManager();
  final SecureStorageService _storage = SecureStorageService();
  late final MediaEncryptionService _mediaService;

  IdentityKeyPair? _identityKey;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> initialize({String? recoveryPhrase}) async {
    if (_initialized) return;

    Uint8List? seed;
    if (recoveryPhrase != null && bip39.validateMnemonic(recoveryPhrase)) {
      seed = Uint8List.fromList(bip39.mnemonicToSeed(recoveryPhrase));
    }

    _identityKey = await _sessionManager.getOrCreateIdentityKey(seed: seed);
    _initialized = true;
  }

  Future<void> initializeFromStorage() async {
    if (_initialized) return;

    _identityKey = await _sessionManager.loadIdentityKey();
    if (_identityKey == null) {
      throw Exception('Encryption keys not available');
    }
    _initialized = true;
  }

  Future<String> generateRecoveryPhrase() async {
    return bip39.generateMnemonic(strength: 128);
  }

  Future<void> setupKeys(String recoveryPhrase) async {
    if (!bip39.validateMnemonic(recoveryPhrase)) {
      throw Exception('Key recovery failed');
    }

    final seed = Uint8List.fromList(bip39.mnemonicToSeed(recoveryPhrase));
    _identityKey = await _sessionManager.getOrCreateIdentityKey(seed: seed);

    final signedPrekey = await _sessionManager.getOrCreateSignedPrekey(_identityKey!);
    final oneTimePrekeys = await _sessionManager.generateAndSaveOneTimePrekeys(count: 50);

    await _sessionManager.uploadPreKeys(
      identityKey: _identityKey!,
      signedPrekey: signedPrekey,
      oneTimePrekeys: oneTimePrekeys,
    );

    _initialized = true;
  }

  Future<void> replenishPreKeysIfNeeded() async {
    _ensureInitialized();
    await _sessionManager.replenishPreKeysIfNeeded(identityKey: _identityKey!);
  }

  Future<void> uploadPreKeys() async {
    _ensureInitialized();
    final signedPrekey = await _sessionManager.getOrCreateSignedPrekey(_identityKey!);
    final oneTimePrekeys = await _sessionManager.generateAndSaveOneTimePrekeys(count: 50);
    await _sessionManager.uploadPreKeys(
      identityKey: _identityKey!,
      signedPrekey: signedPrekey,
      oneTimePrekeys: oneTimePrekeys,
    );
  }

  Future<String> encryptMessage({
    required String plaintext,
    required String recipientId,
    required String senderId,
  }) async {
    _ensureInitialized();

    final messageBytes = await _sessionManager.encrypt(
      recipientId: recipientId,
      ourUserId: senderId,
      plaintext: Uint8List.fromList(utf8.encode(plaintext)),
      ourIdentityKey: _identityKey!,
    );

    return messageBytes.toBase64();
  }

  Future<String> decryptMessage({
    required String encryptedContent,
    required String senderId,
    required String myUserId,
  }) async {
    _ensureInitialized();

    final messageBytes = base64Decode(encryptedContent);
    final plaintext = await _sessionManager.decrypt(
      senderId: senderId,
      ourUserId: myUserId,
      messageBytes: messageBytes,
      ourIdentityKey: _identityKey!,
    );

    return utf8.decode(plaintext);
  }

  Future<Map<String, dynamic>> encryptForSending({
    required String plaintext,
    required String recipientId,
    required String senderId,
  }) async {
    final encryptedContent = await encryptMessage(
      plaintext: plaintext,
      recipientId: recipientId,
      senderId: senderId,
    );

    return {
      'content': encryptedContent,
      'encryptionVersion': 2,
    };
  }

  Future<bool> hasActiveSession(String recipientId, String ourUserId) async {
    return _sessionManager.hasActiveSession(recipientId, ourUserId);
  }

  Future<String?> getFingerprint() async {
    _ensureInitialized();
    final publicKey = await _identityKey!.toPublicKey();
    return publicKey.fingerprint;
  }

  Future<String?> getPublicKey() async {
    _ensureInitialized();
    final publicKey = await _identityKey!.toPublicKey();
    return base64Encode(publicKey.toBytes());
  }

  Future<({Uint8List signature, Uint8List publicKey})> sign(Uint8List data) async {
    _ensureInitialized();
    final signature = await _identityKey!.sign(data);
    final publicKey = await _identityKey!.toPublicKey();
    return (signature: signature, publicKey: publicKey.ed25519PublicKey);
  }

  Future<String?> getPartnerFingerprint(String partnerId) async {
    final userId = await _storage.getUserId();
    if (userId == null) return null;

    final session = await _sessionManager.getSession(partnerId, userId);
    return session?.theirIdentityKey.fingerprint;
  }

  Future<void> deleteSession(String recipientId, String ourUserId) async {
    final sessionId = '${[ourUserId, recipientId]..sort()}';
    await _sessionManager.deleteSession(sessionId.replaceAll('[', '').replaceAll(']', '').replaceAll(', ', '_'));
  }

  Future<void> cleanupSessions() async {
    await _sessionManager.cleanupAllSessions();
  }

  Future<({Uint8List encrypted, String mediaId})> encryptMedia({
    required Uint8List plainBytes,
    required String recipientId,
    required String senderId,
  }) async {
    _ensureInitialized();
    return _mediaService.encryptMedia(
      plainBytes: plainBytes,
      recipientId: recipientId,
      senderId: senderId,
    );
  }

  Future<Uint8List> decryptMedia({
    required Uint8List encryptedBytes,
    required String mediaId,
    required String senderId,
    required String myUserId,
  }) async {
    _ensureInitialized();
    return _mediaService.decryptMedia(
      encryptedBytes: encryptedBytes,
      mediaId: mediaId,
      senderId: senderId,
      myUserId: myUserId,
    );
  }

  Future<void> deleteMedia({
    required String mediaId,
    required String recipientId,
    required String senderId,
  }) async {
    return _mediaService.deleteMedia(
      mediaId: mediaId,
      recipientId: recipientId,
      senderId: senderId,
    );
  }

  Future<String> downloadAndDecryptMedia({
    required String encryptedUrl,
    required String mediaId,
    required String senderId,
    required String myUserId,
    required bool isVideo,
  }) async {
    _ensureInitialized();
    return _mediaService.downloadAndDecrypt(
      encryptedUrl: encryptedUrl,
      mediaId: mediaId,
      senderId: senderId,
      myUserId: myUserId,
      isVideo: isVideo,
    );
  }

  Future<void> clearMediaCache() => _mediaService.clearCache();

  Future<int> getMediaCacheSize() => _mediaService.getCacheSize();

  void _ensureInitialized() {
    if (!_initialized || _identityKey == null) {
      throw Exception('Encryption not available');
    }
  }

  void dispose() {
    _sessionManager.dispose();
    _identityKey?.dispose();
    _identityKey = null;
    _initialized = false;
  }
}
