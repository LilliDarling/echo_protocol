import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'secure_storage.dart';
import '../utils/logger.dart';

class TwoFactorService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final SecureStorageService _secureStorage;
  final FirebaseFunctions _functions;

  TwoFactorService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    SecureStorageService? secureStorage,
    FirebaseFunctions? functions,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _secureStorage = secureStorage ?? SecureStorageService(),
        _functions = functions ?? FirebaseFunctions.instance;

  Future<TwoFactorSetup> enable2FA(String userId) async {
    try {
      final callable = _functions.httpsCallable('enable2FA');
      final result = await callable.call();
      final data = result.data as Map<String, dynamic>;

      final backupCodes = List<String>.from(data['backupCodes'] as List);
      await _secureStorage.storeBackupCodes(backupCodes);

      LoggerService.auth('2FA setup complete');

      return TwoFactorSetup(
        secret: data['secret'] as String,
        qrCodeData: data['qrCodeUrl'] as String,
        backupCodes: backupCodes,
      );
    } on FirebaseFunctionsException catch (e) {
      LoggerService.error('2FA setup failed');
      throw _handleFunctionsException(e);
    } catch (e) {
      throw Exception('Failed to enable 2FA: $e');
    }
  }

  Future<bool> verifyTOTP(String code, {String? userId}) async {
    userId ??= _auth.currentUser?.uid;
    if (userId == null) return false;

    try {
      final callable = _functions.httpsCallable('verify2FATOTP');
      final result = await callable.call({'code': code});
      final data = result.data as Map<String, dynamic>;
      final verified = data['verified'] as bool? ?? false;

      if (verified) {
        LoggerService.auth('2FA verified');
      }

      return verified;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        throw Exception(e.message ?? 'Too many attempts. Try again later.');
      } else if (e.code == 'permission-denied') {
        return false;
      }
      throw _handleFunctionsException(e);
    }
  }

  Future<bool> verifyBackupCode(String code, String userId) async {
    try {
      final callable = _functions.httpsCallable('verify2FABackupCode');
      final result = await callable.call({'code': code});
      final data = result.data as Map<String, dynamic>;
      final verified = data['verified'] as bool? ?? false;

      if (verified) {
        final localCodes = await _secureStorage.getBackupCodes() ?? [];
        localCodes.remove(code);
        localCodes.removeWhere((c) => c.replaceAll('-', '') == code.replaceAll('-', ''));
        await _secureStorage.storeBackupCodes(localCodes);
        LoggerService.auth('Backup code verified');
      }

      return verified;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        throw Exception(e.message ?? 'Too many attempts. Try again later.');
      } else if (e.code == 'permission-denied') {
        return false;
      }
      throw _handleFunctionsException(e);
    }
  }

  Future<void> disable2FA(String userId, String totpCode) async {
    try {
      final callable = _functions.httpsCallable('disable2FA');
      await callable.call({'code': totpCode});
      await _secureStorage.clearTwoFactor();
      LoggerService.auth('2FA disabled');
    } on FirebaseFunctionsException catch (e) {
      throw _handleFunctionsException(e);
    }
  }

  Future<List<String>> regenerateBackupCodes(String userId, String totpCode) async {
    try {
      final callable = _functions.httpsCallable('regenerateBackupCodes');
      final result = await callable.call({'code': totpCode});
      final data = result.data as Map<String, dynamic>;
      final backupCodes = List<String>.from(data['backupCodes'] as List);

      await _secureStorage.storeBackupCodes(backupCodes);
      LoggerService.auth('Backup codes regenerated');

      return backupCodes;
    } on FirebaseFunctionsException catch (e) {
      throw _handleFunctionsException(e);
    }
  }

  Future<bool> is2FAEnabled(String userId) async {
    try {
      final userDoc = await _db.collection('users').doc(userId).get();
      return userDoc.data()?['twoFactorEnabled'] as bool? ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getRateLimitStatus() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final doc = await _db.collection('2fa_rate_limits').doc(user.uid).get();
      return doc.exists ? doc.data() : null;
    } catch (e) {
      return null;
    }
  }

  Exception _handleFunctionsException(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return Exception('You must be signed in to use 2FA');
      case 'permission-denied':
        return Exception('Invalid 2FA code');
      case 'resource-exhausted':
        return Exception('Too many attempts. Please try again later.');
      case 'failed-precondition':
        return Exception(e.message ?? '2FA is not properly configured');
      case 'not-found':
        return Exception('2FA secret not found. Please re-enable 2FA.');
      case 'invalid-argument':
        return Exception(e.message ?? 'Invalid input');
      case 'internal':
        return Exception('Server error. Please try again later.');
      default:
        return Exception(e.message ?? 'An error occurred');
    }
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
