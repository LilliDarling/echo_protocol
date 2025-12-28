import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:cryptography/cryptography.dart' as crypto;

class SecurityUtils {
  static bool constantTimeEquals(String a, String b) {
    final bytesA = utf8.encode(a);
    final bytesB = utf8.encode(b);

    return constantTimeBytesEquals(bytesA, bytesB);
  }

  static bool constantTimeBytesEquals(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }

    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }

    return result == 0;
  }

  static void secureClear(Uint8List data) {
    if (data.isEmpty) return;

    final random = Random.secure();
    for (int i = 0; i < data.length; i++) {
      data[i] = random.nextInt(256);
    }

    for (int i = 0; i < data.length; i++) {
      data[i] = 0;
    }

    for (int i = 0; i < data.length; i++) {
      data[i] = 0xFF;
    }

    for (int i = 0; i < data.length; i++) {
      data[i] = 0;
    }
  }

  static void secureClearAll(List<Uint8List> buffers) {
    for (final buffer in buffers) {
      secureClear(buffer);
    }
  }

  static bool isValidIVLength(int length) {
    return length == 12 || length == 16;
  }

  static bool isValidKeyLength(int lengthInBytes) {
    return lengthInBytes == 16 || lengthInBytes == 24 || lengthInBytes == 32;
  }

  static String sanitizeError(String error) {
    final sensitivePatterns = [
      'key',
      'private',
      'secret',
      'token',
      'password',
      'credential',
    ];

    final lowerError = error.toLowerCase();
    for (final pattern in sensitivePatterns) {
      if (lowerError.contains(pattern)) {
        return 'Authentication failed';
      }
    }

    return error;
  }

  static bool isTimestampValid(
    DateTime timestamp, {
    Duration maxAge = const Duration(minutes: 5),
  }) {
    final now = DateTime.now();
    final age = now.difference(timestamp);

    if (age.isNegative) {
      return age.abs() < const Duration(minutes: 2);
    }

    return age <= maxAge;
  }

  static Future<bool> isMessageReplayProtected(
    String messageId,
    DateTime timestamp,
    Set<String> usedNonces,
  ) async {
    if (!isTimestampValid(timestamp)) {
      return false;
    }

    if (usedNonces.contains(messageId)) {
      return false;
    }

    return true;
  }

  static bool isSequenceValid(int messageSequence, int lastSeenSequence) {
    return messageSequence > lastSeenSequence;
  }

  static bool isMessageValid({
    required DateTime timestamp,
    required int sequenceNumber,
    required int lastSequenceNumber,
    Duration maxAge = const Duration(hours: 1),
  }) {
    if (!isTimestampValid(timestamp, maxAge: maxAge)) {
      return false;
    }

    if (!isSequenceValid(sequenceNumber, lastSequenceNumber)) {
      return false;
    }

    return true;
  }

  static Uint8List hkdfSha256(
    Uint8List inputKeyMaterial,
    Uint8List salt,
    Uint8List info,
    int outputLength,
  ) {
    if (outputLength > 255 * 32) {
      throw ArgumentError('Output length exceeds HKDF-SHA256 maximum');
    }

    if (inputKeyMaterial.isEmpty) {
      throw ArgumentError('Input key material cannot be empty');
    }

    final hmacExtract = Hmac(sha256, salt);
    final prk = Uint8List.fromList(hmacExtract.convert(inputKeyMaterial).bytes);

    final hashLen = 32;
    final n = (outputLength / hashLen).ceil();
    final okm = <int>[];
    var t = <int>[];

    for (var i = 1; i <= n; i++) {
      final hmacExpand = Hmac(sha256, prk);
      final data = [...t, ...info, i];
      t = hmacExpand.convert(data).bytes;
      okm.addAll(t);
    }

    return Uint8List.fromList(okm.sublist(0, outputLength));
  }

  static Exception sanitizeDecryptionError(Object error) {
    return Exception('Failed to decrypt message');
  }

  static final Map<String, List<DateTime>> _rateLimitCache = {};
  static DateTime? _lastCleanup;

  static bool checkRateLimit(
    String identifier,
    int maxAttempts,
    Duration window,
  ) {
    final now = DateTime.now();
    final cutoff = now.subtract(window);

    _periodicCleanup();

    final attempts = _rateLimitCache[identifier] ?? [];

    attempts.removeWhere((timestamp) => timestamp.isBefore(cutoff));

    if (attempts.length >= maxAttempts) {
      return false;
    }

    attempts.add(now);
    _rateLimitCache[identifier] = attempts;

    return true;
  }

  static int getFailedAttempts(String identifier, Duration window) {
    final now = DateTime.now();
    final cutoff = now.subtract(window);

    final attempts = _rateLimitCache[identifier] ?? [];
    attempts.removeWhere((timestamp) => timestamp.isBefore(cutoff));

    return attempts.length;
  }

  static void _periodicCleanup() {
    final now = DateTime.now();

    if (_lastCleanup == null ||
        now.difference(_lastCleanup!) > const Duration(minutes: 10)) {
      cleanupRateLimitCache();
      _lastCleanup = now;
    }
  }

  static void cleanupRateLimitCache() {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(hours: 1));

    _rateLimitCache.removeWhere((key, attempts) {
      attempts.removeWhere((timestamp) => timestamp.isBefore(cutoff));
      return attempts.isEmpty;
    });
  }

  static void clearRateLimitCache() {
    _rateLimitCache.clear();
    _lastCleanup = null;
  }

  static SecureRandom getSecureRandom() {
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

  static Uint8List generateSecureRandomBytes(int length) {
    final secureRandom = getSecureRandom();
    return secureRandom.nextBytes(length);
  }

  static void validateEncryptionParams({
    required int keyLength,
    required int ivLength,
    required String mode,
  }) {
    if (!isValidKeyLength(keyLength)) {
      throw ArgumentError(
        'Invalid key length: $keyLength bytes. Must be 16, 24, or 32 bytes.',
      );
    }

    if (!isValidIVLength(ivLength)) {
      throw ArgumentError(
        'Invalid IV length: $ivLength bytes. Must be 12 or 16 bytes.',
      );
    }

    if (mode.toLowerCase() != 'gcm') {
      throw ArgumentError(
        'Insecure encryption mode: $mode. Only GCM mode is allowed.',
      );
    }
  }

  static void validateGcmCiphertext(List<int> ciphertext) {
    const int gcmTagLength = 16;

    if (ciphertext.length < gcmTagLength) {
      throw ArgumentError(
        'Invalid ciphertext: too short to contain GCM authentication tag',
      );
    }
  }

  static Future<Uint8List> argon2idDerive({
    required String passphrase,
    required Uint8List salt,
    int outputLength = 32,
    int memory = 65536,
    int iterations = 3,
    int parallelism = 4,
  }) async {
    if (salt.length < 16) {
      throw ArgumentError('Salt must be at least 16 bytes');
    }

    final argon2id = crypto.Argon2id(
      memory: memory,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: outputLength,
    );

    final passphraseBytes = utf8.encode(passphrase);
    final result = await argon2id.deriveKey(
      secretKey: crypto.SecretKey(passphraseBytes),
      nonce: salt,
    );

    final keyBytes = await result.extractBytes();
    return Uint8List.fromList(keyBytes);
  }

  static bool isHighEntropySeed(Uint8List seed) {
    if (seed.length < 32) return false;

    final uniqueBytes = seed.toSet();
    return uniqueBytes.length > seed.length * 0.7;
  }
}
