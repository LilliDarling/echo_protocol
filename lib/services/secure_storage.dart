import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
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
      return 'limited';
    }
    return 'hardware';
  }

  static const String _privateKeyKey = 'user_private_key';
  static const String _publicKeyKey = 'user_public_key';
  static const String _partnerPublicKeyKey = 'partner_public_key';
  static const String _userIdKey = 'user_id';
  static const String _sessionKeyKey = 'session_key';

  Future<void> storePrivateKey(String privateKey) async {
    await _storage.write(
      key: _privateKeyKey,
      value: privateKey,
    );
  }

  Future<String?> getPrivateKey() async {
    return await _storage.read(key: _privateKeyKey);
  }

  Future<void> storePublicKey(String publicKey) async {
    await _storage.write(
      key: _publicKeyKey,
      value: publicKey,
    );
  }

  Future<String?> getPublicKey() async {
    return await _storage.read(key: _publicKeyKey);
  }

  Future<void> storePartnerPublicKey(String partnerPublicKey) async {
    await _storage.write(
      key: _partnerPublicKeyKey,
      value: partnerPublicKey,
    );
  }

  Future<String?> getPartnerPublicKey() async {
    return await _storage.read(key: _partnerPublicKeyKey);
  }

  Future<void> storeUserId(String userId) async {
    await _storage.write(
      key: _userIdKey,
      value: userId,
    );
  }

  Future<String?> getUserId() async {
    return await _storage.read(key: _userIdKey);
  }

  Future<void> storeSessionKey(String sessionKey) async {
    await _storage.write(
      key: _sessionKeyKey,
      value: sessionKey,
    );
  }

  Future<String?> getSessionKey() async {
    return await _storage.read(key: _sessionKeyKey);
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  Future<bool> hasEncryptionKeys() async {
    final privateKey = await getPrivateKey();
    final publicKey = await getPublicKey();
    return privateKey != null && publicKey != null;
  }

  Future<bool> hasPartnerKey() async {
    final partnerKey = await getPartnerPublicKey();
    return partnerKey != null;
  }

  Future<void> storeTwoFactorSecret(String secret) async {
    await _storage.write(key: 'totp_secret', value: secret);
  }

  Future<String?> getTwoFactorSecret() async {
    return await _storage.read(key: 'totp_secret');
  }

  Future<void> storeBackupCodes(List<String> codes) async {
    await _storage.write(key: 'backup_codes', value: codes.join(','));
  }

  Future<List<String>?> getBackupCodes() async {
    final stored = await _storage.read(key: 'backup_codes');
    return stored?.split(',');
  }

  Future<void> clearTwoFactor() async {
    await _storage.delete(key: 'totp_secret');
    await _storage.delete(key: 'backup_codes');
  }

  Future<void> storeDeviceId(String deviceId) async {
    await _storage.write(key: 'device_id', value: deviceId);
  }

  Future<String?> getDeviceId() async {
    return await _storage.read(key: 'device_id');
  }

  Future<void> storeArchivedKeyPair({
    required int version,
    required String publicKey,
    required String privateKey,
  }) async {
    await _storage.write(
      key: 'archived_public_key_$version',
      value: publicKey,
    );
    await _storage.write(
      key: 'archived_private_key_$version',
      value: privateKey,
    );
  }

  Future<String?> getArchivedPrivateKey(int version) async {
    return await _storage.read(key: 'archived_private_key_$version');
  }

  Future<String?> getArchivedPublicKey(int version) async {
    return await _storage.read(key: 'archived_public_key_$version');
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
    await _storage.write(
      key: 'current_key_version',
      value: version.toString(),
    );
  }

  Future<int?> getCurrentKeyVersion() async {
    final versionStr = await _storage.read(key: 'current_key_version');
    return versionStr != null ? int.tryParse(versionStr) : null;
  }

  static const String _cacheKeyKey = 'decrypted_content_cache_key';

  Future<void> storeCacheKey(String cacheKey) async {
    await _storage.write(key: _cacheKeyKey, value: cacheKey);
  }

  Future<String?> getCacheKey() async {
    return await _storage.read(key: _cacheKeyKey);
  }

  Future<void> deleteCacheKey() async {
    await _storage.delete(key: _cacheKeyKey);
  }

  static Map<String, dynamic> getSecurityInfo() {
    return {
      'platform': kIsWeb ? 'web' : 'native',
      'securityLevel': securityLevel,
      'storageType': kIsWeb ? 'IndexedDB' : 'Hardware-backed Keystore',
      'warnings': kIsWeb
          ? [
              'Web storage is less secure than native apps',
              'Data may be vulnerable to browser-based attacks',
              'For maximum security, use the mobile app',
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
}
