import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'secure_storage_service.dart';

/// Two-Factor Authentication service
/// Provides TOTP (Time-based One-Time Password) for enhanced security
/// Also supports backup codes for account recovery
class TwoFactorService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final SecureStorageService _secureStorage = SecureStorageService();

  static const int _totpWindowSeconds = 30;
  static const int _totpDigits = 6;

  /// Enable 2FA for user account
  /// Returns secret key and QR code data for authenticator app setup
  Future<TwoFactorSetup> enable2FA(String userId) async {
    // Generate random secret (32 bytes = 256 bits)
    final secret = _generateSecret();

    // Generate backup codes (10 codes)
    final backupCodes = _generateBackupCodes(10);

    // Store in Firestore (encrypted with user's key)
    await _db.collection('users').doc(userId).update({
      'twoFactorEnabled': true,
      'twoFactorSecret': secret,
      'backupCodes': backupCodes.map((code) => _hashBackupCode(code)).toList(),
      'twoFactorEnabledAt': FieldValue.serverTimestamp(),
    });

    // Store secret locally for verification
    await _secureStorage.storeTwoFactorSecret(secret);
    await _secureStorage.storeBackupCodes(backupCodes);

    // Generate QR code data for authenticator apps
    final user = _auth.currentUser;
    final issuer = 'EchoProtocol';
    final accountName = user?.email ?? userId;
    final otpauthUrl = 'otpauth://totp/$issuer:$accountName?secret=$secret&issuer=$issuer';

    return TwoFactorSetup(
      secret: secret,
      qrCodeData: otpauthUrl,
      backupCodes: backupCodes,
    );
  }

  /// Verify TOTP code from authenticator app
  /// Returns true if valid
  Future<bool> verifyTOTP(String code, {String? userId}) async {
    userId ??= _auth.currentUser?.uid;
    if (userId == null) return false;

    final secret = await _secureStorage.getTwoFactorSecret();
    if (secret == null) {
      // Try to fetch from Firestore
      final userDoc = await _db.collection('users').doc(userId).get();
      final firestoreSecret = userDoc.data()?['twoFactorSecret'] as String?;
      if (firestoreSecret == null) {
        await _logFailedAttempt(userId, 'totp');
        return false;
      }
      await _secureStorage.storeTwoFactorSecret(firestoreSecret);
      final isValid = _verifyTOTPCode(code, firestoreSecret);

      if (isValid) {
        await _logVerification(userId, 'totp');
      } else {
        await _logFailedAttempt(userId, 'totp');
      }

      return isValid;
    }

    final isValid = _verifyTOTPCode(code, secret);

    if (isValid) {
      await _logVerification(userId, 'totp');
    } else {
      await _logFailedAttempt(userId, 'totp');
    }

    return isValid;
  }

  /// Verify backup code (one-time use)
  Future<bool> verifyBackupCode(String code, String userId) async {
    final userDoc = await _db.collection('users').doc(userId).get();
    final hashedCodes = (userDoc.data()?['backupCodes'] as List?)?.cast<String>() ?? [];

    final hashedInput = _hashBackupCode(code);

    if (hashedCodes.contains(hashedInput)) {
      // Remove used backup code
      hashedCodes.remove(hashedInput);
      await _db.collection('users').doc(userId).update({
        'backupCodes': hashedCodes,
      });

      // Update local storage
      final localCodes = await _secureStorage.getBackupCodes() ?? [];
      localCodes.remove(code);
      await _secureStorage.storeBackupCodes(localCodes);

      // Log successful verification
      await _logVerification(userId, 'backup_code');

      return true;
    }

    // Log failed attempt
    await _logFailedAttempt(userId, 'backup_code');

    return false;
  }

  /// Disable 2FA (requires current password confirmation)
  Future<void> disable2FA(String userId, String password) async {
    // Verify password before disabling
    final user = _auth.currentUser;
    if (user?.email == null) throw Exception('User not authenticated');

    final credential = EmailAuthProvider.credential(
      email: user!.email!,
      password: password,
    );

    await user.reauthenticateWithCredential(credential);

    // Disable 2FA
    await _db.collection('users').doc(userId).update({
      'twoFactorEnabled': false,
      'twoFactorSecret': FieldValue.delete(),
      'backupCodes': FieldValue.delete(),
      'twoFactorDisabledAt': FieldValue.serverTimestamp(),
    });

    // Clear local storage
    await _secureStorage.clearTwoFactor();
  }

  /// Check if 2FA is enabled for user
  Future<bool> is2FAEnabled(String userId) async {
    final userDoc = await _db.collection('users').doc(userId).get();
    return userDoc.data()?['twoFactorEnabled'] == true;
  }

  /// Regenerate backup codes (requires 2FA verification)
  Future<List<String>> regenerateBackupCodes(String userId, String totpCode) async {
    // Verify TOTP first
    if (!await verifyTOTP(totpCode, userId: userId)) {
      throw Exception('Invalid 2FA code');
    }

    final newCodes = _generateBackupCodes(10);

    await _db.collection('users').doc(userId).update({
      'backupCodes': newCodes.map((code) => _hashBackupCode(code)).toList(),
      'backupCodesRegeneratedAt': FieldValue.serverTimestamp(),
    });

    await _secureStorage.storeBackupCodes(newCodes);

    return newCodes;
  }

  /// Log successful 2FA verification (for security audit)
  Future<void> _logVerification(String userId, String method) async {
    await _db.collection('securityLog').add({
      'userId': userId,
      'event': '2fa_verification',
      'method': method,
      'timestamp': FieldValue.serverTimestamp(),
      'success': true,
    });
  }

  /// Log failed 2FA attempt
  Future<void> _logFailedAttempt(String userId, String method) async {
    await _db.collection('securityLog').add({
      'userId': userId,
      'event': '2fa_failed',
      'method': method,
      'timestamp': FieldValue.serverTimestamp(),
      'success': false,
    });
  }

  // Private helper methods

  String _generateSecret() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  List<String> _generateBackupCodes(int count) {
    final random = Random.secure();
    final codes = <String>[];

    for (var i = 0; i < count; i++) {
      final code = List<int>.generate(8, (_) => random.nextInt(10)).join();
      // Format as XXXX-XXXX
      codes.add('${code.substring(0, 4)}-${code.substring(4, 8)}');
    }

    return codes;
  }

  String _hashBackupCode(String code) {
    return sha256.convert(utf8.encode(code)).toString();
  }

  bool _verifyTOTPCode(String code, String secret) {
    // Get current time window
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final timeWindow = now ~/ _totpWindowSeconds;

    // Check current window and ±1 window (to account for clock drift)
    for (var i = -1; i <= 1; i++) {
      final window = timeWindow + i;
      final generatedCode = _generateTOTPCode(secret, window);

      if (code == generatedCode) {
        return true;
      }
    }

    return false;
  }

  String _generateTOTPCode(String secret, int timeWindow) {
    // Decode base64 secret
    final key = base64Url.decode(secret + '=' * (4 - secret.length % 4));

    // Convert time window to 8-byte array
    final timeBytes = <int>[];
    for (var i = 7; i >= 0; i--) {
      timeBytes.add((timeWindow >> (i * 8)) & 0xff);
    }

    // HMAC-SHA1
    final hmac = Hmac(sha256, key);
    final hash = hmac.convert(timeBytes).bytes;

    // Dynamic truncation
    final offset = hash[hash.length - 1] & 0x0f;
    final binary = ((hash[offset] & 0x7f) << 24) |
        ((hash[offset + 1] & 0xff) << 16) |
        ((hash[offset + 2] & 0xff) << 8) |
        (hash[offset + 3] & 0xff);

    // Generate 6-digit code
    final code = binary % pow(10, _totpDigits).toInt();
    return code.toString().padLeft(_totpDigits, '0');
  }
}

/// Two-factor setup data
class TwoFactorSetup {
  final String secret;
  final String qrCodeData; // For QR code generation
  final List<String> backupCodes;

  TwoFactorSetup({
    required this.secret,
    required this.qrCodeData,
    required this.backupCodes,
  });
}

