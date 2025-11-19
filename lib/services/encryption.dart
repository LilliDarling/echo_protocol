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

  int? _currentKeyVersion;

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

  void setPrivateKey(String privateKeyPem, {int? keyVersion}) {
    _privateKey = _decodePrivateKey(privateKeyPem);
    _currentKeyVersion = keyVersion;

    final ecDomainParameters = _privateKey!.parameters as ECDomainParameters;
    final Q = ecDomainParameters.G * _privateKey!.d;
    _publicKey = ECPublicKey(Q, ecDomainParameters);
  }

  int? get currentKeyVersion => _currentKeyVersion;

  void setPartnerPublicKey(String publicKeyPem) {
    _partnerPublicKey = _decodePublicKey(publicKeyPem);
    _deriveSharedSecret();
  }

  void _deriveSharedSecret() {
    if (_privateKey == null || _partnerPublicKey == null) {
      throw Exception('Keys not initialized');
    }

    final sharedPoint = _partnerPublicKey!.Q! * _privateKey!.d!;

    final sharedSecretBytes = _encodeBigInt(sharedPoint!.x!.toBigInteger()!);

    // HKDF provides proper key derivation as used in Signal Protocol
    // Derive unique salt per conversation from both public keys
    // This ensures each conversation has a different encryption key
    // even if the ECDH shared secret were somehow reused
    final salt = _deriveSaltFromPublicKeys(_publicKey!, _partnerPublicKey!);
    final info = Uint8List.fromList(utf8.encode('message-encryption-key'));

    final derivedKey = SecurityUtils.hkdfSha256(
      Uint8List.fromList(sharedSecretBytes),
      salt,
      info,
      32,
    );

    _sharedSecret = encrypt.Key(derivedKey);
  }

  /// Derive a deterministic salt from both public keys
  /// Uses SHA-256 hash of concatenated public key coordinates
  /// Both parties will compute the same salt regardless of key order
  Uint8List _deriveSaltFromPublicKeys(ECPublicKey key1, ECPublicKey key2) {
    // Encode both public keys
    final key1X = _encodeBigInt(key1.Q!.x!.toBigInteger()!);
    final key1Y = _encodeBigInt(key1.Q!.y!.toBigInteger()!);
    final key2X = _encodeBigInt(key2.Q!.x!.toBigInteger()!);
    final key2Y = _encodeBigInt(key2.Q!.y!.toBigInteger()!);

    // Sort keys lexicographically to ensure both parties compute same salt
    // regardless of which key is "mine" vs "partner's"
    final keys = [
      Uint8List.fromList(key1X + key1Y),
      Uint8List.fromList(key2X + key2Y),
    ];
    keys.sort((a, b) {
      for (int i = 0; i < a.length && i < b.length; i++) {
        if (a[i] != b[i]) return a[i].compareTo(b[i]);
      }
      return a.length.compareTo(b.length);
    });

    // Hash the concatenation with domain separation
    final combined = Uint8List.fromList([
      ...utf8.encode('EchoProtocol-HKDF-Salt-v1:'),
      ...keys[0],
      ...keys[1],
    ]);

    final hash = sha256.convert(combined);
    return Uint8List.fromList(hash.bytes);
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

  String decryptMessage(String encryptedText) {
    if (_sharedSecret == null) {
      throw Exception('Decryption not initialized. Set partner public key first.');
    }

    try {
      final parts = encryptedText.split(':');
      if (parts.length != 2) {
        throw SecurityUtils.sanitizeDecryptionError('Invalid format');
      }

      final ivBytes = base64.decode(parts[0]);
      if (ivBytes.length != 16) {
        throw SecurityUtils.sanitizeDecryptionError('Invalid IV length');
      }

      final ciphertextBytes = base64.decode(parts[1]);
      SecurityUtils.validateGcmCiphertext(ciphertextBytes);

      final iv = encrypt.IV(Uint8List.fromList(ivBytes));
      final encrypted = encrypt.Encrypted(Uint8List.fromList(ciphertextBytes));

      final encrypter = encrypt.Encrypter(
        encrypt.AES(_sharedSecret!, mode: encrypt.AESMode.gcm),
      );

      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      throw SecurityUtils.sanitizeDecryptionError(e);
    }
  }

  String decryptMessageWithKeyVersions({
    required String encryptedText,
    required String myPrivateKeyPem,
    required String partnerPublicKeyPem,
  }) {
    try {
      final tempPrivateKey = _decodePrivateKey(myPrivateKeyPem);
      final tempPartnerPublicKey = _decodePublicKey(partnerPublicKeyPem);

      final sharedPoint = tempPartnerPublicKey.Q! * tempPrivateKey.d!;
      final sharedSecretBytes = _encodeBigInt(sharedPoint!.x!.toBigInteger()!);

      final ecDomainParameters = tempPrivateKey.parameters as ECDomainParameters;
      final Q = ecDomainParameters.G * tempPrivateKey.d;
      final tempPublicKey = ECPublicKey(Q, ecDomainParameters);

      final salt = _deriveSaltFromPublicKeys(tempPublicKey, tempPartnerPublicKey);
      final info = Uint8List.fromList(utf8.encode('message-encryption-key'));

      final derivedKey = SecurityUtils.hkdfSha256(
        Uint8List.fromList(sharedSecretBytes),
        salt,
        info,
        32,
      );

      final sharedSecret = encrypt.Key(derivedKey);

      final parts = encryptedText.split(':');
      if (parts.length != 2) {
        throw SecurityUtils.sanitizeDecryptionError('Invalid format');
      }

      final ivBytes = base64.decode(parts[0]);
      if (ivBytes.length != 16) {
        throw SecurityUtils.sanitizeDecryptionError('Invalid IV length');
      }

      final ciphertextBytes = base64.decode(parts[1]);
      SecurityUtils.validateGcmCiphertext(ciphertextBytes);

      final iv = encrypt.IV(Uint8List.fromList(ivBytes));
      final encrypted = encrypt.Encrypted(Uint8List.fromList(ciphertextBytes));

      final encrypter = encrypt.Encrypter(
        encrypt.AES(sharedSecret, mode: encrypt.AESMode.gcm),
      );

      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
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

    const int ivLength = 16;
    const int gcmTagLength = 16;

    if (encryptedData.length < ivLength + gcmTagLength) {
      throw SecurityUtils.sanitizeDecryptionError('Invalid encrypted file data');
    }

    final iv = encrypt.IV(encryptedData.sublist(0, ivLength));
    final ciphertextWithTag = encryptedData.sublist(ivLength);

    SecurityUtils.validateGcmCiphertext(ciphertextWithTag);

    final encrypter = encrypt.Encrypter(
      encrypt.AES(_sharedSecret!, mode: encrypt.AESMode.gcm, padding: null),
    );

    return Uint8List.fromList(
      encrypter.decryptBytes(
        encrypt.Encrypted(ciphertextWithTag),
        iv: iv,
      ),
    );
  }

  String hashValue(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  /// Generate a human-readable fingerprint from a public key
  /// Format: XXXX XXXX XXXX XXXX XXXX XXXX XXXX XXXX (32 hex chars, 8 groups of 4)
  /// Uses SHA-256 hash of the public key for consistency
  String generateFingerprint(String publicKeyPem) {
    // Hash the public key to get consistent 32-byte fingerprint
    final hash = sha256.convert(utf8.encode(publicKeyPem));
    final hashHex = hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    // Take first 32 hex characters (16 bytes) and format for readability
    final fingerprintHex = hashHex.substring(0, 32).toUpperCase();

    // Split into 8 groups of 4 characters for readability
    final groups = <String>[];
    for (int i = 0; i < fingerprintHex.length; i += 4) {
      groups.add(fingerprintHex.substring(i, i + 4));
    }

    return groups.join(' ');
  }

  /// Get fingerprint for current user's public key
  String? getMyFingerprint() {
    try {
      if (_publicKey == null) return null;
      final publicKeyPem = _encodePublicKey(_publicKey!);
      return generateFingerprint(publicKeyPem);
    } catch (e) {
      return null;
    }
  }

  /// Get fingerprint for partner's public key
  String? getPartnerFingerprint() {
    try {
      if (_partnerPublicKey == null) return null;
      final publicKeyPem = _encodePublicKey(_partnerPublicKey!);
      return generateFingerprint(publicKeyPem);
    } catch (e) {
      return null;
    }
  }

  /// Verify that a fingerprint matches a given public key
  /// Returns true if the fingerprint is valid for the public key
  bool verifyFingerprint(String publicKeyPem, String expectedFingerprint) {
    final actualFingerprint = generateFingerprint(publicKeyPem);

    // Normalize both fingerprints (remove spaces, convert to uppercase)
    final normalizedActual = actualFingerprint.replaceAll(' ', '').toUpperCase();
    final normalizedExpected = expectedFingerprint.replaceAll(' ', '').toUpperCase();

    // Use constant-time comparison to prevent timing attacks
    return SecurityUtils.constantTimeEquals(normalizedActual, normalizedExpected);
  }

  // Private helper methods for key encoding/decoding

  String _encodePublicKey(ECPublicKey publicKey) {
    final x = _encodeBigInt(publicKey.Q!.x!.toBigInteger()!);
    final y = _encodeBigInt(publicKey.Q!.y!.toBigInteger()!);

    final curveBytes = utf8.encode('secp256k1');
    final curveLength = curveBytes.length;

    final buffer = <int>[
      0x04,
      0x01,
      curveLength,
      ...curveBytes,
      x.length,
      ...x,
      y.length,
      ...y,
    ];

    return base64Encode(buffer);
  }

  String _encodePrivateKey(ECPrivateKey privateKey) {
    final d = _encodeBigInt(privateKey.d!);

    final curveBytes = utf8.encode('secp256k1');
    final curveLength = curveBytes.length;

    final buffer = <int>[
      0x04,
      0x01,
      curveLength,
      ...curveBytes,
      d.length,
      ...d,
    ];

    return base64Encode(buffer);
  }

  ECPublicKey _decodePublicKey(String encoded) {
    try {
      final buffer = base64Decode(encoded);

      if (buffer.isEmpty) {
        throw Exception('Invalid public key: empty');
      }

      if (buffer[0] == 0x7b) {
        final jsonStr = utf8.decode(buffer);
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        final x = _decodeBigInt(base64Decode(data['x']));
        final y = _decodeBigInt(base64Decode(data['y']));
        final ecDomainParameters = ECDomainParameters('secp256k1');
        final point = ecDomainParameters.curve.createPoint(x, y);
        return ECPublicKey(point, ecDomainParameters);
      }

      if (buffer[0] != 0x04) {
        throw Exception('Invalid public key format version');
      }

      if (buffer.length < 3) {
        throw Exception('Invalid public key: too short');
      }

      int offset = 1;
      final version = buffer[offset++];

      if (version != 0x01) {
        throw Exception('Unsupported public key version: $version');
      }

      final curveLength = buffer[offset++];
      if (offset + curveLength > buffer.length) {
        throw Exception('Invalid public key: curve name overflow');
      }

      final curveBytes = buffer.sublist(offset, offset + curveLength);
      final curveName = utf8.decode(curveBytes);
      offset += curveLength;

      if (curveName != 'secp256k1') {
        throw Exception('Unsupported curve: $curveName');
      }

      if (offset >= buffer.length) {
        throw Exception('Invalid public key: missing x coordinate');
      }

      final xLength = buffer[offset++];
      if (offset + xLength > buffer.length) {
        throw Exception('Invalid public key: x coordinate overflow');
      }

      final xBytes = buffer.sublist(offset, offset + xLength);
      offset += xLength;

      if (offset >= buffer.length) {
        throw Exception('Invalid public key: missing y coordinate');
      }

      final yLength = buffer[offset++];
      if (offset + yLength > buffer.length) {
        throw Exception('Invalid public key: y coordinate overflow');
      }

      final yBytes = buffer.sublist(offset, offset + yLength);

      final x = _decodeBigInt(xBytes);
      final y = _decodeBigInt(yBytes);

      final ecDomainParameters = ECDomainParameters('secp256k1');
      final point = ecDomainParameters.curve.createPoint(x, y);

      return ECPublicKey(point, ecDomainParameters);
    } catch (e) {
      throw Exception('Invalid public key format');
    }
  }

  ECPrivateKey _decodePrivateKey(String encoded) {
    try {
      final buffer = base64Decode(encoded);

      if (buffer.isEmpty) {
        throw Exception('Invalid private key: empty');
      }

      if (buffer[0] == 0x7b) {
        final jsonStr = utf8.decode(buffer);
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        final d = _decodeBigInt(base64Decode(data['d']));
        final ecDomainParameters = ECDomainParameters('secp256k1');
        return ECPrivateKey(d, ecDomainParameters);
      }

      if (buffer[0] != 0x04) {
        throw Exception('Invalid private key format version');
      }

      if (buffer.length < 3) {
        throw Exception('Invalid private key: too short');
      }

      int offset = 1;
      final version = buffer[offset++];

      if (version != 0x01) {
        throw Exception('Unsupported private key version: $version');
      }

      final curveLength = buffer[offset++];
      if (offset + curveLength > buffer.length) {
        throw Exception('Invalid private key: curve name overflow');
      }

      final curveBytes = buffer.sublist(offset, offset + curveLength);
      final curveName = utf8.decode(curveBytes);
      offset += curveLength;

      if (curveName != 'secp256k1') {
        throw Exception('Unsupported curve: $curveName');
      }

      if (offset >= buffer.length) {
        throw Exception('Invalid private key: missing d value');
      }

      final dLength = buffer[offset++];
      if (offset + dLength > buffer.length) {
        throw Exception('Invalid private key: d value overflow');
      }

      final dBytes = buffer.sublist(offset, offset + dLength);

      final d = _decodeBigInt(dBytes);
      final ecDomainParameters = ECDomainParameters('secp256k1');

      if (d <= BigInt.zero || d >= ecDomainParameters.n) {
        throw Exception('Invalid private key: d out of range');
      }

      return ECPrivateKey(d, ecDomainParameters);
    } catch (e) {
      throw Exception('Invalid private key format');
    }
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
    for (int i = 0; i < 24; i++) {
      seeds.add(random.nextInt(256));
    }

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final timestampBytes = ByteData(8)..setInt64(0, timestamp, Endian.big);
    seeds.addAll(timestampBytes.buffer.asUint8List());

    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }

  void clearKeys() {
    _privateKey = null;
    _publicKey = null;
    _partnerPublicKey = null;
    _sharedSecret = null;
  }

  /// Rotate user's key pair
  /// Generates a new key pair while preserving ability to decrypt old messages
  /// Returns map with both keys and metadata
  Future<Map<String, dynamic>> rotateKeys() async {
    final timestamp = DateTime.now();

    // Generate new key pair
    final newKeyPair = await generateKeyPair();

    // Return key rotation data with metadata
    return {
      'publicKey': newKeyPair['publicKey']!,
      'privateKey': newKeyPair['privateKey']!,
      'rotatedAt': timestamp.toIso8601String(),
      'fingerprint': generateFingerprint(newKeyPair['publicKey']!),
      'version': timestamp.millisecondsSinceEpoch ~/ 1000, // Unix timestamp as version
    };
  }

  /// Validate that a public key is structurally valid
  /// Returns true if the key can be decoded successfully
  bool isValidPublicKey(String publicKeyPem) {
    try {
      _decodePublicKey(publicKeyPem);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Validate that a private key is structurally valid
  /// Returns true if the key can be decoded successfully
  bool isValidPrivateKey(String privateKeyPem) {
    try {
      _decodePrivateKey(privateKeyPem);
      return true;
    } catch (e) {
      return false;
    }
  }
}
