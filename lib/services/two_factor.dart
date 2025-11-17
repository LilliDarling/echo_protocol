import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:base32/base32.dart';
import 'secure_storage.dart';

class TwoFactorService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final SecureStorageService _secureStorage;

  static const int _totpWindowSeconds = 30;
  static const int _totpDigits = 6;

  TwoFactorService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    SecureStorageService? secureStorage,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _secureStorage = secureStorage ?? SecureStorageService();

  Future<TwoFactorSetup> enable2FA(String userId) async {
    final secret = _generateSecret();

    final backupCodes = _generateBackupCodes(10);

    await _db.collection('users').doc(userId).update({
      'twoFactorEnabled': true,
      'backupCodes': backupCodes.map((code) => _hashBackupCode(code)).toList(),
      'twoFactorEnabledAt': FieldValue.serverTimestamp(),
    });

    await _secureStorage.storeTwoFactorSecret(secret);
    await _secureStorage.storeBackupCodes(backupCodes);

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

  Future<bool> verifyTOTP(String code, {String? userId}) async {
    userId ??= _auth.currentUser?.uid;
    if (userId == null) return false;

    final secret = await _secureStorage.getTwoFactorSecret();
    if (secret == null) {
      await _logFailedAttempt(userId, 'totp_no_secret');
      throw Exception('2FA not set up on this device. Please use a backup code or contact support.');
    }

    final isValid = _verifyTOTPCode(code, secret);

    if (isValid) {
      await _logVerification(userId, 'totp');
    } else {
      await _logFailedAttempt(userId, 'totp');
    }

    return isValid;
  }

  Future<bool> verifyBackupCode(String code, String userId) async {
    final userDoc = await _db.collection('users').doc(userId).get();
    final hashedCodes = (userDoc.data()?['backupCodes'] as List?)?.cast<String>() ?? [];

    final hashedInput = _hashBackupCode(code);

    if (hashedCodes.contains(hashedInput)) {
      hashedCodes.remove(hashedInput);
      await _db.collection('users').doc(userId).update({
        'backupCodes': hashedCodes,
      });

      final localCodes = await _secureStorage.getBackupCodes() ?? [];
      localCodes.remove(code);
      await _secureStorage.storeBackupCodes(localCodes);

      await _logVerification(userId, 'backup_code');

      return true;
    }

    await _logFailedAttempt(userId, 'backup_code');

    return false;
  }

  Future<void> disable2FA(String userId, String password) async {
    final user = _auth.currentUser;
    if (user?.email == null) throw Exception('User not authenticated');

    final credential = EmailAuthProvider.credential(
      email: user!.email!,
      password: password,
    );

    await user.reauthenticateWithCredential(credential);

    await _db.collection('users').doc(userId).update({
      'twoFactorEnabled': false,
      'backupCodes': FieldValue.delete(),
      'twoFactorDisabledAt': FieldValue.serverTimestamp(),
    });

    await _secureStorage.clearTwoFactor();
  }

  Future<bool> is2FAEnabled(String userId) async {
    final userDoc = await _db.collection('users').doc(userId).get();
    return userDoc.data()?['twoFactorEnabled'] == true;
  }

  Future<List<String>> regenerateBackupCodes(String userId, String totpCode) async {
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

  Future<void> _logVerification(String userId, String method) async {
    await _db.collection('securityLog').add({
      'userId': userId,
      'event': '2fa_verification',
      'method': method,
      'timestamp': FieldValue.serverTimestamp(),
      'success': true,
    });
  }

  Future<void> _logFailedAttempt(String userId, String method) async {
    await _db.collection('securityLog').add({
      'userId': userId,
      'event': '2fa_failed',
      'method': method,
      'timestamp': FieldValue.serverTimestamp(),
      'success': false,
    });
  }

  String _generateSecret() {
    final random = Random.secure();
    final bytes = List<int>.generate(20, (_) => random.nextInt(256));
    return base32.encode(Uint8List.fromList(bytes));
  }

  List<String> _generateBackupCodes(int count) {
    final random = Random.secure();
    final codes = <String>[];

    for (var i = 0; i < count; i++) {
      final code = List<int>.generate(8, (_) => random.nextInt(10)).join();
      codes.add('${code.substring(0, 4)}-${code.substring(4, 8)}');
    }

    return codes;
  }

  String _hashBackupCode(String code) {
    return sha256.convert(utf8.encode(code)).toString();
  }

  bool _verifyTOTPCode(String code, String secret) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final timeWindow = now ~/ _totpWindowSeconds;

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
    final key = base32.decode(secret);

    final timeBytes = <int>[];
    for (var i = 7; i >= 0; i--) {
      timeBytes.add((timeWindow >> (i * 8)) & 0xff);
    }

    final hmac = Hmac(sha1, key);
    final hash = hmac.convert(timeBytes).bytes;

    final offset = hash[hash.length - 1] & 0x0f;
    final binary = ((hash[offset] & 0x7f) << 24) |
        ((hash[offset + 1] & 0xff) << 16) |
        ((hash[offset + 2] & 0xff) << 8) |
        (hash[offset + 3] & 0xff);

    final code = binary % pow(10, _totpDigits).toInt();
    return code.toString().padLeft(_totpDigits, '0');
  }
}

class TwoFactorSetup {
  final String secret;
  final String qrCodeData;
  final List<String> backupCodes;

  TwoFactorSetup({
    required this.secret,
    required this.qrCodeData,
    required this.backupCodes,
  });
}

