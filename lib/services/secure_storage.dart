import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/security.dart';

class _WebEncryptionLayer {
  static const String _webSaltStorageKey = '_web_device_salt_v2';
  static Uint8List? _cachedKey;
  static String? _cachedUserId;
  static final AesGcm _aesGcm = AesGcm.with256bits();

  static Future<Uint8List> _deriveKey(
    FlutterSecureStorage storage,
    String userId,
  ) async {
    if (_cachedKey != null && _cachedUserId == userId) {
      return _cachedKey!;
    }

    String? storedSalt = await storage.read(key: _webSaltStorageKey);
    Uint8List deviceSalt;
    if (storedSalt != null) {
      deviceSalt = base64Decode(storedSalt);
    } else {
      deviceSalt = SecurityUtils.generateSecureRandomBytes(32);
      await storage.write(key: _webSaltStorageKey, value: base64Encode(deviceSalt));
    }

    final userIdBytes = utf8.encode(userId);
    final ikm = Uint8List.fromList([...deviceSalt, ...userIdBytes]);

    _cachedKey = SecurityUtils.hkdfSha256(
      ikm,
      Uint8List.fromList(utf8.encode('EchoProtocol-WebStorage-v2')),
      Uint8List.fromList(utf8.encode('aes-256-gcm-key')),
      32,
    );
    _cachedUserId = userId;

    SecurityUtils.secureClear(ikm);
    return _cachedKey!;
  }

  static Future<String> encrypt(
    String value,
    FlutterSecureStorage storage,
    String? userId,
  ) async {
    if (!kIsWeb) return value;

    if (userId == null) {
      throw Exception('Authentication required for secure storage');
    }

    final key = await _deriveKey(storage, userId);
    final secretKey = SecretKey(key);
    final nonce = SecurityUtils.generateSecureRandomBytes(12);

    final plaintext = utf8.encode(value);
    final secretBox = await _aesGcm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
    );

    final combined = Uint8List.fromList([
      ...nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
    return base64Encode(combined);
  }

  static Future<String?> decrypt(
    String? encrypted,
    FlutterSecureStorage storage,
    String? userId,
  ) async {
    if (encrypted == null) return null;
    if (!kIsWeb) return encrypted;

    if (userId == null) {
      return null;
    }

    try {
      final key = await _deriveKey(storage, userId);
      final secretKey = SecretKey(key);
      final combined = base64Decode(encrypted);

      if (combined.length < 28) return null;

      final nonce = combined.sublist(0, 12);
      final ciphertext = combined.sublist(12, combined.length - 16);
      final mac = combined.sublist(combined.length - 16);

      final secretBox = SecretBox(
        ciphertext,
        nonce: nonce,
        mac: Mac(mac),
      );

      final plaintext = await _aesGcm.decrypt(secretBox, secretKey: secretKey);
      return utf8.decode(plaintext);
    } catch (_) {
      return null;
    }
  }

  static void clearCache() {
    if (_cachedKey != null) {
      SecurityUtils.secureClear(_cachedKey!);
      _cachedKey = null;
    }
    _cachedUserId = null;
  }
}

class SecureStorageService {
  final FirebaseAuth _auth;

  SecureStorageService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
    webOptions: WebOptions(
      dbName: 'echo_protocol_secure',
      publicKey: 'echo_protocol_key',
    ),
  );

  static bool get isWebPlatform => kIsWeb;

  static String get securityLevel {
    if (kIsWeb) {
      return 'encrypted';
    }
    return 'hardware';
  }

  String? get _currentUserId => _auth.currentUser?.uid;

  Future<void> _secureWrite(String key, String value) async {
    final encryptedValue = await _WebEncryptionLayer.encrypt(
      value,
      _storage,
      _currentUserId,
    );
    await _storage.write(key: key, value: encryptedValue);
  }

  Future<String?> _secureRead(String key) async {
    final encrypted = await _storage.read(key: key);
    return _WebEncryptionLayer.decrypt(encrypted, _storage, _currentUserId);
  }

  Future<void> _secureDelete(String key) async {
    await _storage.delete(key: key);
  }

  static const String _privateKeyKey = 'user_private_key';
  static const String _publicKeyKey = 'user_public_key';
  static const String _partnerPublicKeyKey = 'partner_public_key';
  static const String _userIdKey = 'user_id';
  static const String _sessionKeyKey = 'session_key';

  Future<void> storePrivateKey(String privateKey) async {
    await _secureWrite(_privateKeyKey, privateKey);
  }

  Future<String?> getPrivateKey() async {
    return await _secureRead(_privateKeyKey);
  }

  Future<void> storePublicKey(String publicKey) async {
    await _secureWrite(_publicKeyKey, publicKey);
  }

  Future<String?> getPublicKey() async {
    return await _secureRead(_publicKeyKey);
  }

  Future<void> storePartnerPublicKey(String partnerPublicKey) async {
    await _secureWrite(_partnerPublicKeyKey, partnerPublicKey);
  }

  Future<String?> getPartnerPublicKey() async {
    return await _secureRead(_partnerPublicKeyKey);
  }

  Future<void> storeUserId(String userId) async {
    await _secureWrite(_userIdKey, userId);
  }

  Future<String?> getUserId() async {
    return await _secureRead(_userIdKey);
  }

  Future<void> storeSessionKey(String sessionKey) async {
    await _secureWrite(_sessionKeyKey, sessionKey);
  }

  Future<String?> getSessionKey() async {
    return await _secureRead(_sessionKeyKey);
  }

  void clearSessionCache() {
    _WebEncryptionLayer.clearCache();
  }

  Future<void> clearAll() async {
    _WebEncryptionLayer.clearCache();
    await _storage.deleteAll();
  }

  Future<bool> hasEncryptionKeys() async {
    final privateKey = await getPrivateKey();
    final publicKey = await getPublicKey();
    return privateKey != null && publicKey != null;
  }

  Future<void> clearEncryptionKeys() async {
    await _secureDelete(_privateKeyKey);
    await _secureDelete(_publicKeyKey);
    await _secureDelete(_partnerPublicKeyKey);
    await _secureDelete(_userIdKey);
    await _secureDelete('current_key_version');
    await _secureDelete(_vaultKeyKey);
    await _secureDelete(_lastSyncedChunkIndexKey);
  }

  Future<bool> hasPartnerKey() async {
    final partnerKey = await getPartnerPublicKey();
    return partnerKey != null;
  }

  static const String _trustedFingerprintKey = 'trusted_partner_fingerprint';
  static const String _fingerprintAcknowledgedKey = 'fingerprint_acknowledged';

  Future<void> storeTrustedFingerprint(String fingerprint) async {
    await _secureWrite(_trustedFingerprintKey, fingerprint);
    await _secureWrite(_fingerprintAcknowledgedKey, 'true');
  }

  Future<String?> getTrustedFingerprint() async {
    return await _secureRead(_trustedFingerprintKey);
  }

  Future<bool> isFingerprintAcknowledged() async {
    final value = await _secureRead(_fingerprintAcknowledgedKey);
    return value == 'true';
  }

  Future<void> clearFingerprintAcknowledgment() async {
    await _secureDelete(_fingerprintAcknowledgedKey);
  }

  Future<void> clearTrustedFingerprint() async {
    await _secureDelete(_trustedFingerprintKey);
    await _secureDelete(_fingerprintAcknowledgedKey);
  }

  Future<void> storeTwoFactorSecret(String secret) async {
    await _secureWrite('totp_secret', secret);
  }

  Future<String?> getTwoFactorSecret() async {
    return await _secureRead('totp_secret');
  }

  Future<void> storeBackupCodes(List<String> codes) async {
    await _secureWrite('backup_codes', codes.join(','));
  }

  Future<List<String>?> getBackupCodes() async {
    final stored = await _secureRead('backup_codes');
    return stored?.split(',');
  }

  Future<void> clearTwoFactor() async {
    await _secureDelete('totp_secret');
    await _secureDelete('backup_codes');
  }

  Future<void> storeDeviceId(String deviceId) async {
    await _secureWrite('device_id', deviceId);
  }

  Future<String?> getDeviceId() async {
    return await _secureRead('device_id');
  }

  Future<void> storeArchivedKeyPair({
    required int version,
    required String publicKey,
    required String privateKey,
  }) async {
    await _secureWrite('archived_public_key_$version', publicKey);
    await _secureWrite('archived_private_key_$version', privateKey);
  }

  Future<String?> getArchivedPrivateKey(int version) async {
    return await _secureRead('archived_private_key_$version');
  }

  Future<String?> getArchivedPublicKey(int version) async {
    return await _secureRead('archived_public_key_$version');
  }

  Future<List<int>> getArchivedKeyVersions() async {
    final allKeys = await _storage.readAll();
    final versions = <int>{};

    for (final key in allKeys.keys) {
      if (key.startsWith('archived_private_key_')) {
        final versionStr = key.replaceFirst('archived_private_key_', '');
        final version = int.tryParse(versionStr);
        if (version != null) {
          versions.add(version);
        }
      }
    }

    return versions.toList()..sort();
  }

  Future<void> storeCurrentKeyVersion(int version) async {
    await _secureWrite('current_key_version', version.toString());
  }

  Future<int?> getCurrentKeyVersion() async {
    final versionStr = await _secureRead('current_key_version');
    return versionStr != null ? int.tryParse(versionStr) : null;
  }

  static const String _cacheKeyKey = 'decrypted_content_cache_key';
  static const String _pendingRecoveryPhraseKey = 'pending_recovery_phrase';

  Future<void> storePendingRecoveryPhrase(String phrase) async {
    await _secureWrite(_pendingRecoveryPhraseKey, phrase);
  }

  Future<String?> getPendingRecoveryPhrase() async {
    return await _secureRead(_pendingRecoveryPhraseKey);
  }

  Future<void> clearPendingRecoveryPhrase() async {
    await _secureDelete(_pendingRecoveryPhraseKey);
  }

  Future<void> storeCacheKey(String cacheKey) async {
    await _secureWrite(_cacheKeyKey, cacheKey);
  }

  Future<String?> getCacheKey() async {
    return await _secureRead(_cacheKeyKey);
  }

  Future<void> deleteCacheKey() async {
    await _secureDelete(_cacheKeyKey);
  }

  static const String _lastSyncedChunkIndexKey = 'vault_last_synced_chunk_index';

  Future<int> getLastSyncedChunkIndex() async {
    final value = await _secureRead(_lastSyncedChunkIndexKey);
    return value != null ? int.tryParse(value) ?? -1 : -1;
  }

  Future<void> storeLastSyncedChunkIndex(int index) async {
    await _secureWrite(_lastSyncedChunkIndexKey, index.toString());
  }

  Future<void> deleteLastSyncedChunkIndex() async {
    await _secureDelete(_lastSyncedChunkIndexKey);
  }

  static const String _vaultKeyKey = 'vault_encryption_key';

  Future<void> storeVaultKey(String key) async {
    await _secureWrite(_vaultKeyKey, key);
  }

  Future<String?> getVaultKey() async {
    return await _secureRead(_vaultKeyKey);
  }

  Future<void> deleteVaultKey() async {
    await _secureDelete(_vaultKeyKey);
  }

  static const String _databaseKeyKey = 'database_encryption_key';

  Future<void> storeDatabaseKey(String key) async {
    await _secureWrite(_databaseKeyKey, key);
  }

  Future<String?> getDatabaseKey() async {
    return await _secureRead(_databaseKeyKey);
  }

  Future<void> deleteDatabaseKey() async {
    await _secureDelete(_databaseKeyKey);
  }

  static const String _sequenceCountersKey = 'inbox_sequence_counters';

  Future<void> storeSequenceCounters(String json) async {
    await _secureWrite(_sequenceCountersKey, json);
  }

  Future<String?> getSequenceCounters() async {
    return await _secureRead(_sequenceCountersKey);
  }

  static Map<String, dynamic> getSecurityInfo() {
    return {
      'platform': kIsWeb ? 'web' : 'native',
      'securityLevel': securityLevel,
      'storageType': kIsWeb
          ? 'Auth-bound encrypted IndexedDB'
          : 'Hardware-backed Keystore',
      'warnings': kIsWeb
          ? [
              'Web storage uses AES-256-GCM with auth-derived keys',
              'Encryption key requires active authentication',
              'For maximum security, use the mobile app with hardware keystore',
            ]
          : <String>[],
    };
  }

  static String? checkSecurityRequirements({
    bool requireHardwareSecurity = false,
  }) {
    if (requireHardwareSecurity && kIsWeb) {
      return 'This operation requires hardware-backed security. '
          'Please use the mobile app for this feature.';
    }
    return null;
  }

  static const Duration _twoFaSessionTimeout = Duration(hours: 24);

  Future<bool> get2FASessionVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final idTokenResult = await user.getIdTokenResult();
    final claims = idTokenResult.claims;
    if (claims == null) return false;

    final verifiedAt = claims['twoFactorVerifiedAt'] as int?;
    if (verifiedAt == null) return false;

    final verifiedTime = DateTime.fromMillisecondsSinceEpoch(verifiedAt);
    final isExpired = DateTime.now().difference(verifiedTime) >= _twoFaSessionTimeout;

    return !isExpired;
  }

  Future<void> refresh2FASession() async {
    final user = _auth.currentUser;
    if (user != null) {
      await user.getIdToken(true);
    }
  }

  Future<Duration?> get2FASessionTimeRemaining() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final idTokenResult = await user.getIdTokenResult();
    final claims = idTokenResult.claims;
    if (claims == null) return null;

    final verifiedAt = claims['twoFactorVerifiedAt'] as int?;
    if (verifiedAt == null) return null;

    final verifiedTime = DateTime.fromMillisecondsSinceEpoch(verifiedAt);
    final elapsed = DateTime.now().difference(verifiedTime);

    if (elapsed >= _twoFaSessionTimeout) return null;

    return _twoFaSessionTimeout - elapsed;
  }
}
