import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Security utilities for Echo Protocol
/// Provides constant-time operations and additional security hardening
class SecurityUtils {
  /// Constant-time string comparison
  /// Prevents timing attacks when comparing secrets, tokens, or hashes
  ///
  /// SECURITY: Regular == comparison can leak information through timing
  /// This compares every byte regardless of early mismatches
  static bool constantTimeEquals(String a, String b) {
    final bytesA = utf8.encode(a);
    final bytesB = utf8.encode(b);

    return constantTimeBytesEquals(bytesA, bytesB);
  }

  /// Constant-time bytes comparison
  /// Essential for comparing cryptographic hashes, MACs, and signatures
  static bool constantTimeBytesEquals(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }

    // XOR all bytes - result is 0 only if all bytes match
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }

    return result == 0;
  }

  /// Securely clear sensitive data from memory
  /// Overwrites data with zeros before disposal
  ///
  /// IMPORTANT: Dart's garbage collector may delay cleanup
  /// This provides best-effort clearing for sensitive data
  static void secureClear(Uint8List data) {
    for (int i = 0; i < data.length; i++) {
      data[i] = 0;
    }
  }

  /// Validate IV (Initialization Vector) length
  /// Ensures IV is proper size for AES-GCM (96 bits / 12 bytes recommended)
  /// or 128 bits / 16 bytes (also acceptable)
  static bool isValidIVLength(int length) {
    return length == 12 || length == 16;
  }

  /// Validate key length for AES
  static bool isValidKeyLength(int lengthInBytes) {
    return lengthInBytes == 16 || lengthInBytes == 24 || lengthInBytes == 32;
  }

  static String generateSecureToken(int lengthInBytes) {
    if (lengthInBytes < 16) {
      throw ArgumentError('Token must be at least 16 bytes for security');
    }

    // Maximum practical size to prevent DoS
    if (lengthInBytes > 256) {
      throw ArgumentError('Token size exceeds maximum of 256 bytes');
    }

    // Note: This would use Random.secure() in production
    // Keeping existing implementation from device_linking_service.dart
    return '';
  }

  /// Sanitize error messages to prevent information leakage
  /// Cryptographic errors should be generic to prevent oracle attacks
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

  /// Validate that a timestamp is recent (prevents replay attacks)
  /// Returns true if timestamp is within the acceptable window
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

  /// Validate message replay protection
  /// Combines timestamp validation with nonce tracking
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

  /// Derive a key using HKDF (HMAC-based Key Derivation Function)
  static Uint8List hkdfSha256(
    Uint8List inputKeyMaterial,
    Uint8List salt,
    Uint8List info,
    int outputLength,
  ) {
    if (outputLength > 255 * 32) {
      throw ArgumentError('Output length exceeds HKDF-SHA256 maximum');
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

  /// Rate limiting check (simple in-memory implementation)
  /// For production, will use Redis or similar distributed cache
  static final Map<String, List<DateTime>> _rateLimitCache = {};

  static bool checkRateLimit(
    String identifier,
    int maxAttempts,
    Duration window,
  ) {
    final now = DateTime.now();
    final cutoff = now.subtract(window);

    final attempts = _rateLimitCache[identifier] ?? [];

    attempts.removeWhere((timestamp) => timestamp.isBefore(cutoff));

    if (attempts.length >= maxAttempts) {
      return false;
    }

    attempts.add(now);
    _rateLimitCache[identifier] = attempts;

    return true;
  }

  static void cleanupRateLimitCache() {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(hours: 1));

    _rateLimitCache.removeWhere((key, attempts) {
      attempts.removeWhere((timestamp) => timestamp.isBefore(cutoff));
      return attempts.isEmpty;
    });
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
}
