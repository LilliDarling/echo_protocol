import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto_pkg;
import '../../utils/security.dart';
import '../secure_storage.dart';

class VaultEncryptionService {
  final AesGcm _aesGcm = AesGcm.with256bits();
  final SecureStorageService _storage;

  VaultEncryptionService({SecureStorageService? storage})
      : _storage = storage ?? SecureStorageService();

  Future<Uint8List?> _loadVaultKey() async {
    final encoded = await _storage.getVaultKey();
    if (encoded == null) return null;
    return base64Decode(encoded);
  }

  Future<Uint8List> encryptChunk({
    required Uint8List plaintext,
    required String chunkId,
  }) async {
    final vaultKey = await _loadVaultKey();
    if (vaultKey == null) throw Exception('Vault key not available');

    try {
      final compressed = Uint8List.fromList(
        ZLibCodec().encode(plaintext),
      );

      final secretKey = SecretKey(vaultKey);
      final nonce = SecurityUtils.generateSecureRandomBytes(12);
      final aad = utf8.encode('EchoVault:$chunkId');

      final secretBox = await _aesGcm.encrypt(
        compressed,
        secretKey: secretKey,
        nonce: nonce,
        aad: aad,
      );

      return Uint8List.fromList([
        ...nonce,
        ...secretBox.cipherText,
        ...secretBox.mac.bytes,
      ]);
    } finally {
      SecurityUtils.secureClear(vaultKey);
    }
  }

  Future<Uint8List> decryptChunk({
    required Uint8List encrypted,
    required String chunkId,
  }) async {
    if (encrypted.length < 28) {
      throw Exception('Invalid vault chunk data');
    }

    final vaultKey = await _loadVaultKey();
    if (vaultKey == null) throw Exception('Vault key not available');

    try {
      final nonce = encrypted.sublist(0, 12);
      final ct = encrypted.sublist(12, encrypted.length - 16);
      final tag = encrypted.sublist(encrypted.length - 16);
      final aad = utf8.encode('EchoVault:$chunkId');

      final secretKey = SecretKey(vaultKey);
      final secretBox = SecretBox(ct, nonce: nonce, mac: Mac(tag));

      final compressed = await _aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
        aad: aad,
      );

      return Uint8List.fromList(
        ZLibCodec().decode(compressed),
      );
    } finally {
      SecurityUtils.secureClear(vaultKey);
    }
  }

  Future<bool> get isVaultKeyAvailable async {
    final key = await _storage.getVaultKey();
    return key != null;
  }

  static String computeChecksum(Uint8List data) {
    return crypto_pkg.sha256.convert(data).toString();
  }
}
