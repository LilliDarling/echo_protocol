import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/user.dart';
import '../utils/validators.dart';
import 'encryption.dart';
import 'secure_storage.dart';
import 'logger.dart';
import 'recovery_phrase_service.dart';

/// Result of a sign-up operation that includes the recovery phrase.
class SignUpResult {
  final UserCredential credential;
  final String recoveryPhrase;

  SignUpResult({required this.credential, required this.recoveryPhrase});
}

/// Result of a sign-in operation.
class SignInResult {
  final UserCredential credential;
  final bool needsRecovery;

  SignInResult({required this.credential, this.needsRecovery = false});
}

class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final EncryptionService _encryptionService;
  final SecureStorageService _secureStorage;
  final RecoveryPhraseService _recoveryPhraseService;

  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    EncryptionService? encryptionService,
    SecureStorageService? secureStorage,
    RecoveryPhraseService? recoveryPhraseService,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance,
        _encryptionService = encryptionService ?? EncryptionService(),
        _secureStorage = secureStorage ?? SecureStorageService(),
        _recoveryPhraseService = recoveryPhraseService ?? RecoveryPhraseService();

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  String? get currentUserId => _auth.currentUser?.uid;

  Future<SignUpResult> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final nameValidation = Validators.validateDisplayName(displayName);
      if (nameValidation != null) {
        throw Exception(nameValidation);
      }

      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final sanitizedName = displayName.trim();
      await credential.user?.updateDisplayName(sanitizedName);

      final keyResult = await _generateAndStoreKeys(credential.user!.uid);

      await _createUserDocument(
        userId: credential.user!.uid,
        email: email,
        displayName: displayName,
        photoUrl: null,
        publicKey: keyResult['publicKey']!,
      );

      LoggerService.auth('Sign up successful', userId: credential.user!.uid);
      return SignUpResult(
        credential: credential,
        recoveryPhrase: keyResult['mnemonic']!,
      );
    } on FirebaseAuthException catch (e) {
      LoggerService.error('Sign up failed: ${e.code}');
      throw _handleAuthException(e);
    }
  }

  Future<SignInResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final needsRecovery = !await _tryLoadUserKeys(credential.user!.uid);
      if (!needsRecovery) {
        await _updateLastActive(credential.user!.uid);
      }

      LoggerService.auth('Sign in successful', userId: credential.user!.uid);
      return SignInResult(credential: credential, needsRecovery: needsRecovery);
    } on FirebaseAuthException catch (e) {
      LoggerService.error('Sign in failed: ${e.code}');
      throw _handleAuthException(e);
    }
  }

  /// Sign in with Google. Returns SignUpResult for new users (with recovery phrase)
  /// or SignInResult for existing users.
  Future<dynamic> signInWithGoogle() async {
    try {
      final UserCredential userCredential;

      if (kIsWeb) {
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        userCredential = await _auth.signInWithPopup(googleProvider);
      } else {
        final GoogleSignInAccount googleUser = await GoogleSignIn.instance.authenticate();
        final GoogleSignInAuthentication googleAuth = googleUser.authentication;

        if (googleAuth.idToken == null) {
          throw Exception('Failed to get ID token from Google Sign-In');
        }

        final credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );

        userCredential = await _auth.signInWithCredential(credential);
      }

      final isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;

      if (isNewUser) {
        final keyResult = await _generateAndStoreKeys(userCredential.user!.uid);

        await _createUserDocument(
          userId: userCredential.user!.uid,
          email: userCredential.user!.email!,
          displayName: userCredential.user!.displayName ?? 'User',
          photoUrl: userCredential.user!.photoURL,
          publicKey: keyResult['publicKey']!,
        );

        LoggerService.auth('Google sign-up successful', userId: userCredential.user!.uid);
        return SignUpResult(
          credential: userCredential,
          recoveryPhrase: keyResult['mnemonic']!,
        );
      } else {
        final needsRecovery = !await _tryLoadUserKeys(userCredential.user!.uid);
        if (!needsRecovery) {
          await _updateLastActive(userCredential.user!.uid);
        }

        LoggerService.auth('Google sign-in successful', userId: userCredential.user!.uid);
        return SignInResult(credential: userCredential, needsRecovery: needsRecovery);
      }
    } on FirebaseAuthException catch (e) {
      LoggerService.error('Google sign-in failed: ${e.code}');
      throw _handleAuthException(e);
    } catch (e) {
      LoggerService.error('Google sign-in failed');
      throw Exception('Failed to sign in with Google');
    }
  }

  Future<void> signOut() async {
    try {
      final userId = currentUserId;

      _encryptionService.clearKeys();

      if (!kIsWeb) {
        try {
          await GoogleSignIn.instance.signOut();
        } catch (e) {
          // Continue with Firebase sign out
        }
      }

      await _auth.signOut();

      LoggerService.auth('Sign out successful', userId: userId);
      await _secureStorage.clearAll();
    } catch (e) {
      LoggerService.error('Sign out failed');
      throw Exception('Failed to sign out');
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  Future<bool> hasEncryptionKeys() async {
    return await _secureStorage.hasEncryptionKeys();
  }

  Future<void> reauthenticateWithPassword(String password) async {
    final user = currentUser;
    if (user?.email == null) {
      throw Exception('No user signed in');
    }

    final credential = EmailAuthProvider.credential(
      email: user!.email!,
      password: password,
    );

    await user.reauthenticateWithCredential(credential);
  }

  Future<void> updateProfile({
    String? displayName,
    String? photoURL,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('No user signed in');

    if (displayName != null) {
      await user.updateDisplayName(displayName);
      await _db.collection('users').doc(user.uid).update({
        'name': displayName,
      });
    }

    if (photoURL != null) {
      await user.updatePhotoURL(photoURL);
      await _db.collection('users').doc(user.uid).update({
        'avatar': photoURL,
      });
    }
  }

  Future<void> deleteAccount(String password) async {
    final user = currentUser;
    if (user == null) throw Exception('No user signed in');

    try {
      await reauthenticateWithPassword(password);

      await _db.collection('users').doc(user.uid).delete();

      await _secureStorage.clearAll();

      await user.delete();
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  Future<Map<String, String>> rotateEncryptionKeys() async {
    final user = currentUser;
    if (user == null) throw Exception('No user signed in');

    try {
      final oldPublicKey = await _secureStorage.getPublicKey();
      final oldPrivateKey = await _secureStorage.getPrivateKey();
      final oldVersion = await _secureStorage.getCurrentKeyVersion();
      final oldFingerprint = oldPublicKey != null
          ? _encryptionService.generateFingerprint(oldPublicKey)
          : 'none';

      final rotationData = await _encryptionService.rotateKeys();
      final newVersion = rotationData['version'] as int;

      if (oldPublicKey != null && oldPrivateKey != null && oldVersion != null) {
        await _secureStorage.storeArchivedKeyPair(
          version: oldVersion,
          publicKey: oldPublicKey,
          privateKey: oldPrivateKey,
        );

        await _db.collection('users').doc(user.uid)
            .collection('keyHistory').doc(oldVersion.toString()).set({
          'publicKey': oldPublicKey,
          'version': oldVersion,
          'fingerprint': oldFingerprint,
          'archivedAt': DateTime.now().toIso8601String(),
        });
      }

      await _secureStorage.storePrivateKey(rotationData['privateKey'] as String);
      await _secureStorage.storePublicKey(rotationData['publicKey'] as String);
      await _secureStorage.storeCurrentKeyVersion(newVersion);

      await _db.collection('users').doc(user.uid).update({
        'publicKey': rotationData['publicKey'],
        'publicKeyVersion': newVersion,
        'publicKeyRotatedAt': rotationData['rotatedAt'],
        'publicKeyFingerprint': rotationData['fingerprint'],
      });

      return {
        'publicKey': rotationData['publicKey'] as String,
        'fingerprint': rotationData['fingerprint'] as String,
      };
    } catch (e) {
      LoggerService.error('Key rotation failed');
      throw Exception('Failed to rotate encryption keys');
    }
  }

  Future<String?> getMyPublicKeyFingerprint() async {
    final publicKey = await _secureStorage.getPublicKey();
    if (publicKey == null) return null;

    return _encryptionService.generateFingerprint(publicKey);
  }

  bool verifyPartnerFingerprint(String publicKey, String expectedFingerprint) {
    return _encryptionService.verifyFingerprint(publicKey, expectedFingerprint);
  }

  /// Generate keys from a new mnemonic and store them.
  /// Returns map with 'publicKey', 'privateKey', and 'mnemonic'.
  Future<Map<String, String>> _generateAndStoreKeys(String userId) async {
    // Generate new recovery phrase
    final mnemonic = _recoveryPhraseService.generateMnemonic();

    // Derive seed from mnemonic
    final seed = _recoveryPhraseService.deriveSeedFromMnemonic(mnemonic);

    // Generate keys from seed (deterministic)
    final keyPair = await _encryptionService.generateKeyPairFromSeed(seed);

    // Use deterministic version based on public key
    final keyVersion = _recoveryPhraseService.deriveKeyVersion(keyPair['publicKey']!);

    await _secureStorage.storePrivateKey(keyPair['privateKey']!);
    await _secureStorage.storePublicKey(keyPair['publicKey']!);
    await _secureStorage.storeCurrentKeyVersion(keyVersion);
    await _secureStorage.storeUserId(userId);

    return {
      'publicKey': keyPair['publicKey']!,
      'privateKey': keyPair['privateKey']!,
      'mnemonic': mnemonic,
    };
  }

  /// Try to load user keys from secure storage.
  /// Returns true if keys were loaded, false if recovery is needed.
  Future<bool> _tryLoadUserKeys(String userId) async {
    final privateKey = await _secureStorage.getPrivateKey();

    if (privateKey != null) {
      final keyVersion = await _secureStorage.getCurrentKeyVersion();
      _encryptionService.setPrivateKey(privateKey, keyVersion: keyVersion);
      await _secureStorage.storeUserId(userId);
      return true;
    }

    return false;
  }

  /// Recover keys using a recovery phrase.
  /// Validates that the derived public key matches what's stored in Firestore.
  Future<void> recoverWithPhrase(String mnemonic) async {
    final user = currentUser;
    if (user == null) throw Exception('No user signed in');

    // Validate mnemonic format
    if (!_recoveryPhraseService.validateMnemonic(mnemonic)) {
      throw Exception('Invalid recovery phrase');
    }

    // Derive keys from mnemonic
    final seed = _recoveryPhraseService.deriveSeedFromMnemonic(mnemonic);
    final keyPair = await _encryptionService.generateKeyPairFromSeed(seed);

    // Get the expected public key from Firestore
    final userDoc = await _db.collection('users').doc(user.uid).get();
    final storedPublicKey = userDoc.data()?['publicKey'] as String?;

    if (storedPublicKey == null) {
      throw Exception('User account not found');
    }

    // Verify the derived public key matches
    if (keyPair['publicKey'] != storedPublicKey) {
      throw Exception('Recovery phrase does not match this account');
    }

    // Keys match - store them
    final keyVersion = _recoveryPhraseService.deriveKeyVersion(keyPair['publicKey']!);

    await _secureStorage.storePrivateKey(keyPair['privateKey']!);
    await _secureStorage.storePublicKey(keyPair['publicKey']!);
    await _secureStorage.storeCurrentKeyVersion(keyVersion);
    await _secureStorage.storeUserId(user.uid);

    _encryptionService.setPrivateKey(keyPair['privateKey']!, keyVersion: keyVersion);

    await _updateLastActive(user.uid);
    LoggerService.auth('Recovery successful', userId: user.uid);
  }

  Future<void> _createUserDocument({
    required String userId,
    required String email,
    required String displayName,
    String? photoUrl,
    required String publicKey,
  }) async {
    final now = DateTime.now();
    final initialVersion = now.millisecondsSinceEpoch ~/ 1000;
    final fingerprint = _encryptionService.generateFingerprint(publicKey);

    final userModel = UserModel(
      id: userId,
      name: displayName,
      avatar: photoUrl ?? '',
      createdAt: now,
      lastActive: now,
      preferences: UserPreferences.defaultPreferences,
    );

    await _db.collection('users').doc(userId).set({
      ...userModel.toJson(),
      'email': email,
      'publicKey': publicKey,
      'publicKeyVersion': initialVersion,
      'publicKeyRotatedAt': now.toIso8601String(),
      'publicKeyFingerprint': fingerprint,
      'linkedDevices': [],
    });
  }

  Future<void> _updateLastActive(String userId) async {
    await _db.collection('users').doc(userId).update({
      'lastActive': FieldValue.serverTimestamp(),
    });
  }

  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'The password provided is too weak.';
      case 'email-already-in-use':
        return 'An account already exists for this email.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled.';

      case 'user-not-found':
      case 'wrong-password':
        return 'Invalid credentials. Please check and try again.';

      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return 'Authentication failed: ${e.message}';
    }
  }
}
