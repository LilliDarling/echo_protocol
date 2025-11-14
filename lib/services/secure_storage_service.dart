import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage service for sensitive data
/// Uses platform-specific secure storage (Keychain on iOS, KeyStore on Android)
/// Private keys NEVER leave the device and are stored encrypted
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
    webOptions: WebOptions(
      dbName: 'echo_protocol_secure_storage',
      publicKey: 'echo_protocol_public_key',
    ),
  );

  // Storage keys
  static const String _privateKeyKey = 'user_private_key';
  static const String _publicKeyKey = 'user_public_key';
  static const String _partnerPublicKeyKey = 'partner_public_key';
  static const String _userIdKey = 'user_id';
  static const String _sessionKeyKey = 'session_key';

  /// Store user's private key (NEVER sync this to cloud)
  Future<void> storePrivateKey(String privateKey) async {
    await _storage.write(
      key: _privateKeyKey,
      value: privateKey,
    );
  }

  /// Retrieve user's private key
  Future<String?> getPrivateKey() async {
    return await _storage.read(key: _privateKeyKey);
  }

  /// Store user's public key (for convenience, also stored in Firestore)
  Future<void> storePublicKey(String publicKey) async {
    await _storage.write(
      key: _publicKeyKey,
      value: publicKey,
    );
  }

  /// Retrieve user's public key
  Future<String?> getPublicKey() async {
    return await _storage.read(key: _publicKeyKey);
  }

  /// Store partner's public key
  Future<void> storePartnerPublicKey(String partnerPublicKey) async {
    await _storage.write(
      key: _partnerPublicKeyKey,
      value: partnerPublicKey,
    );
  }

  /// Retrieve partner's public key
  Future<String?> getPartnerPublicKey() async {
    return await _storage.read(key: _partnerPublicKeyKey);
  }

  /// Store user ID
  Future<void> storeUserId(String userId) async {
    await _storage.write(
      key: _userIdKey,
      value: userId,
    );
  }

  /// Retrieve user ID
  Future<String?> getUserId() async {
    return await _storage.read(key: _userIdKey);
  }

  /// Store session key
  Future<void> storeSessionKey(String sessionKey) async {
    await _storage.write(
      key: _sessionKeyKey,
      value: sessionKey,
    );
  }

  /// Retrieve session key
  Future<String?> getSessionKey() async {
    return await _storage.read(key: _sessionKeyKey);
  }

  /// Clear all stored data (on logout)
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  /// Check if user has encryption keys stored
  Future<bool> hasEncryptionKeys() async {
    final privateKey = await getPrivateKey();
    final publicKey = await getPublicKey();
    return privateKey != null && publicKey != null;
  }

  /// Check if partner public key is stored
  Future<bool> hasPartnerKey() async {
    final partnerKey = await getPartnerPublicKey();
    return partnerKey != null;
  }

  /// Store 2FA secret
  Future<void> storeTwoFactorSecret(String secret) async {
    await _storage.write(key: 'totp_secret', value: secret);
  }

  /// Get 2FA secret
  Future<String?> getTwoFactorSecret() async {
    return await _storage.read(key: 'totp_secret');
  }

  /// Store backup codes
  Future<void> storeBackupCodes(List<String> codes) async {
    await _storage.write(key: 'backup_codes', value: codes.join(','));
  }

  /// Get backup codes
  Future<List<String>?> getBackupCodes() async {
    final stored = await _storage.read(key: 'backup_codes');
    return stored?.split(',');
  }

  /// Clear 2FA data
  Future<void> clearTwoFactor() async {
    await _storage.delete(key: 'totp_secret');
    await _storage.delete(key: 'backup_codes');
  }

  /// Store device ID
  Future<void> storeDeviceId(String deviceId) async {
    await _storage.write(key: 'device_id', value: deviceId);
  }

  /// Get device ID
  Future<String?> getDeviceId() async {
    return await _storage.read(key: 'device_id');
  }
}
