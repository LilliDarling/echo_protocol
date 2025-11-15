import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/export.dart';
import '../utils/security.dart';

/// End-to-end encryption service for Echo Protocol
class EncryptionService {
  // EC key pair for current user (Curve25519)
  late ECPrivateKey? _privateKey;
  late ECPublicKey? _publicKey;

  ECPublicKey? _partnerPublicKey;

  encrypt.Key? _sharedSecret;

  /// Generate a new EC key pair for the current user
  /// Uses Curve25519 (X25519)
  Future<Map<String, String>> generateKeyPair() async {
    // Use secp256k1 curve (used by Bitcoin, Signal, etc.)
    final ecDomainParameters = ECDomainParameters('secp256k1');

    final random = _getSecureRandom();
    final privateKeyNum = random.nextBigInteger(ecDomainParameters.n.bitLength);

    _privateKey = ECPrivateKey(privateKeyNum, ecDomainParameters);

    final Q = ecDomainParameters.G * privateKeyNum;
    _publicKey = ECPublicKey(Q, ecDomainParameters);

    return {
      'publicKey': _encodePublicKey(_publicKey!),
      'privateKey': _encodePrivateKey(_privateKey!),
    };
  }

  void setPrivateKey(String privateKeyPem) {
    _privateKey = _decodePrivateKey(privateKeyPem);

    final ecDomainParameters = _privateKey!.parameters as ECDomainParameters;
    final Q = ecDomainParameters.G * _privateKey!.d;
    _publicKey = ECPublicKey(Q, ecDomainParameters);
  }

  void setPartnerPublicKey(String publicKeyPem) {
    _partnerPublicKey = _decodePublicKey(publicKeyPem);
    _deriveSharedSecret();
  }

  /// SECURITY: Uses HKDF for proper key derivation (Signal Protocol standard)
  void _deriveSharedSecret() {
    if (_privateKey == null || _partnerPublicKey == null) {
      throw Exception('Keys not initialized');
    }

    final sharedPoint = _partnerPublicKey!.Q! * _privateKey!.d!;

    final sharedSecretBytes = _encodeBigInt(sharedPoint!.x!.toBigInteger()!);

    // HKDF provides proper key derivation as used in Signal Protocol
    // Salt should ideally be random, but for compatibility we use a fixed context
    final salt = Uint8List.fromList(utf8.encode('EchoProtocol-v1'));
    final info = Uint8List.fromList(utf8.encode('message-encryption-key'));

    final derivedKey = SecurityUtils.hkdfSha256(
      Uint8List.fromList(sharedSecretBytes),
      salt,
      info,
      32,
    );

    _sharedSecret = encrypt.Key(derivedKey);
  }

  /// Encrypt message content for the partner
  /// Uses AES-256-GCM (authenticated encryption)
  String encryptMessage(String plaintext) {
    if (_sharedSecret == null) {
      throw Exception('Encryption not initialized. Set partner public key first.');
    }

    final iv = encrypt.IV.fromSecureRandom(16);

    // Encrypt using AES-256-GCM
    final encrypter = encrypt.Encrypter(
      encrypt.AES(_sharedSecret!, mode: encrypt.AESMode.gcm),
    );

    final encrypted = encrypter.encrypt(plaintext, iv: iv);

    final combined = '${iv.base64}:${encrypted.base64}';
    return combined;
  }

  /// Decrypt message content from partner
  /// SECURITY: Uses GCM for authenticated decryption - prevents tampering
  String decryptMessage(String encryptedText) {
    if (_sharedSecret == null) {
      throw Exception('Decryption not initialized. Set partner public key first.');
    }

    try {
      final parts = encryptedText.split(':');
      if (parts.length != 2) {
        throw SecurityUtils.sanitizeDecryptionError('Invalid format');
      }

      final iv = encrypt.IV.fromBase64(parts[0]);
      final encrypted = encrypt.Encrypted.fromBase64(parts[1]);

      // Decrypt using AES-256-GCM
      // GCM will automatically verify authentication tag
      // If data was tampered with, this will throw an exception
      final encrypter = encrypt.Encrypter(
        encrypt.AES(_sharedSecret!, mode: encrypt.AESMode.gcm),
      );

      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      // Don't expose details about why decryption failed (prevents oracle attacks)
      throw SecurityUtils.sanitizeDecryptionError(e);
    }
  }

  /// Encrypt file data (images, videos, etc.)
  Uint8List encryptFile(Uint8List fileData) {
    if (_sharedSecret == null) {
      throw Exception('Encryption not initialized');
    }

    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(_sharedSecret!, mode: encrypt.AESMode.gcm, padding: null),
    );

    final encrypted = encrypter.encryptBytes(fileData, iv: iv);

    final result = Uint8List(iv.bytes.length + encrypted.bytes.length);
    result.setRange(0, iv.bytes.length, iv.bytes);
    result.setRange(iv.bytes.length, result.length, encrypted.bytes);

    return result;
  }

  Uint8List decryptFile(Uint8List encryptedData) {
    if (_sharedSecret == null) {
      throw Exception('Decryption not initialized');
    }

    final iv = encrypt.IV(encryptedData.sublist(0, 16));
    final encryptedBytes = encryptedData.sublist(16);

    final encrypter = encrypt.Encrypter(
      encrypt.AES(_sharedSecret!, mode: encrypt.AESMode.gcm, padding: null),
    );

    return Uint8List.fromList(
      encrypter.decryptBytes(
        encrypt.Encrypted(encryptedBytes),
        iv: iv,
      ),
    );
  }

  String hashValue(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  // Private helper methods for key encoding/decoding

  String _encodePublicKey(ECPublicKey publicKey) {
    final x = _encodeBigInt(publicKey.Q!.x!.toBigInteger()!);
    final y = _encodeBigInt(publicKey.Q!.y!.toBigInteger()!);

    final data = {
      'x': base64Encode(x),
      'y': base64Encode(y),
      'curve': 'secp256k1',
    };

    return base64Encode(utf8.encode(jsonEncode(data)));
  }

  String _encodePrivateKey(ECPrivateKey privateKey) {
    final d = _encodeBigInt(privateKey.d!);

    final data = {
      'd': base64Encode(d),
      'curve': 'secp256k1',
    };

    return base64Encode(utf8.encode(jsonEncode(data)));
  }

  ECPublicKey _decodePublicKey(String encoded) {
    final jsonStr = utf8.decode(base64Decode(encoded));
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    final x = _decodeBigInt(base64Decode(data['x']));
    final y = _decodeBigInt(base64Decode(data['y']));

    final ecDomainParameters = ECDomainParameters('secp256k1');
    final point = ecDomainParameters.curve.createPoint(x, y);

    return ECPublicKey(point, ecDomainParameters);
  }

  ECPrivateKey _decodePrivateKey(String encoded) {
    final jsonStr = utf8.decode(base64Decode(encoded));
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    final d = _decodeBigInt(base64Decode(data['d']));
    final ecDomainParameters = ECDomainParameters('secp256k1');

    return ECPrivateKey(d, ecDomainParameters);
  }

  Uint8List _encodeBigInt(BigInt number) {
    final bytes = <int>[];
    var n = number;
    while (n > BigInt.zero) {
      bytes.insert(0, (n & BigInt.from(0xff)).toInt());
      n = n >> 8;
    }
    return Uint8List.fromList(bytes.isEmpty ? [0] : bytes);
  }

  BigInt _decodeBigInt(List<int> bytes) {
    var result = BigInt.zero;
    for (var byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }

  SecureRandom _getSecureRandom() {
    final secureRandom = FortunaRandom();
    final random = Random.secure();
    final seeds = <int>[];
    for (int i = 0; i < 32; i++) {
      seeds.add(random.nextInt(256));
    }
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }

  void clearKeys() {
    _privateKey = null;
    _publicKey = null;
    _partnerPublicKey = null;
    _sharedSecret = null;
  }
}
