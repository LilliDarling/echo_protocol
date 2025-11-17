import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/user.dart';
import 'encryption.dart';
import 'secure_storage.dart';
import 'logger.dart';

/// Authentication service for user login/signup
/// Handles Firebase Auth, Google Sign-In, and encryption key generation
class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final EncryptionService _encryptionService;
  final SecureStorageService _secureStorage;

  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    EncryptionService? encryptionService,
    SecureStorageService? secureStorage,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance,
        _encryptionService = encryptionService ?? EncryptionService(),
        _secureStorage = secureStorage ?? SecureStorageService();

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  String? get currentUserId => _auth.currentUser?.uid;

  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      await credential.user?.updateDisplayName(displayName);

      final keyPair = await _generateAndStoreKeys(credential.user!.uid);

      await _createUserDocument(
        userId: credential.user!.uid,
        email: email,
        displayName: displayName,
        photoUrl: null,
        publicKey: keyPair['publicKey']!,
      );

      LoggerService.auth('Sign up successful', userId: credential.user!.uid);
      return credential;
    } on FirebaseAuthException catch (e) {
      LoggerService.error('Sign up failed: ${e.code}');
      throw _handleAuthException(e);
    }
  }

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      await _loadUserKeys(credential.user!.uid);
      await _updateLastActive(credential.user!.uid);

      LoggerService.auth('Sign in successful', userId: credential.user!.uid);
      return credential;
    } on FirebaseAuthException catch (e) {
      LoggerService.error('Sign in failed: ${e.code}');
      throw _handleAuthException(e);
    }
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
      final UserCredential userCredential;

      if (kIsWeb) {
        // Web: Use Firebase popup/redirect flow
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();

        // Optional: Add scopes if needed
        // googleProvider.addScope('https://www.googleapis.com/auth/contacts.readonly');

        // Optional: Set custom parameters
        // googleProvider.setCustomParameters({
        //   'login_hint': 'user@example.com'
        // });

        // Sign in with popup (or use signInWithRedirect for same-window flow)
        userCredential = await _auth.signInWithPopup(googleProvider);
      } else {
        // Mobile/Desktop: Use google_sign_in package
        final GoogleSignInAccount? googleUser = await GoogleSignIn.instance.authenticate();

        if (googleUser == null) {
          throw Exception('Google sign-in was cancelled');
        }

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
        final keyPair = await _generateAndStoreKeys(userCredential.user!.uid);

        await _createUserDocument(
          userId: userCredential.user!.uid,
          email: userCredential.user!.email!,
          displayName: userCredential.user!.displayName ?? 'User',
          photoUrl: userCredential.user!.photoURL,
          publicKey: keyPair['publicKey']!,
        );
      } else {
        await _loadUserKeys(userCredential.user!.uid);
        await _updateLastActive(userCredential.user!.uid);
      }

      LoggerService.auth('Google sign-in successful', userId: userCredential.user!.uid);
      return userCredential;
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
          // GoogleSignIn may not be available in test environment
          // Continue with Firebase sign out
        }
      }

      await _auth.signOut();

      LoggerService.auth('Sign out successful', userId: userId);

      // Optionally clear secure storage (keep keys for offline access)
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

  /// Rotate encryption keys for current user
  /// Generates new key pair and completely replaces old keys
  /// SECURITY: Old keys are overwritten - use only when no active conversations exist
  /// WARNING: This will invalidate all existing encrypted conversations
  Future<Map<String, String>> rotateEncryptionKeys() async {
    final user = currentUser;
    if (user == null) throw Exception('No user signed in');

    try {
      LoggerService.security('Key rotation initiated', {
        'userId': user.uid,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Get current public key fingerprint for audit logging
      final oldPublicKey = await _secureStorage.getPublicKey();
      final oldFingerprint = oldPublicKey != null
          ? _encryptionService.generateFingerprint(oldPublicKey)
          : 'none';

      // Generate new key pair with rotation metadata
      final rotationData = await _encryptionService.rotateKeys();

      // Replace old keys with new keys (overwrites existing keys)
      await _secureStorage.storePrivateKey(rotationData['privateKey'] as String);
      await _secureStorage.storePublicKey(rotationData['publicKey'] as String);

      // Update public key in Firestore with version tracking
      await _db.collection('users').doc(user.uid).update({
        'publicKey': rotationData['publicKey'],
        'publicKeyVersion': rotationData['version'],
        'publicKeyRotatedAt': rotationData['rotatedAt'],
        'publicKeyFingerprint': rotationData['fingerprint'],
      });

      LoggerService.security('Key rotation completed', {
        'userId': user.uid,
        'oldFingerprint': oldFingerprint,
        'newFingerprint': rotationData['fingerprint'],
        'version': rotationData['version'],
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

  /// Get the fingerprint of current user's public key
  /// Used for out-of-band verification with conversation partners
  Future<String?> getMyPublicKeyFingerprint() async {
    final publicKey = await _secureStorage.getPublicKey();
    if (publicKey == null) return null;

    return _encryptionService.generateFingerprint(publicKey);
  }

  /// Verify partner's public key fingerprint
  /// Returns true if the fingerprint matches the public key
  bool verifyPartnerFingerprint(String publicKey, String expectedFingerprint) {
    return _encryptionService.verifyFingerprint(publicKey, expectedFingerprint);
  }

  // Private helper methods

  /// Generate and store encryption keys for new user
  /// Returns the generated key pair to be stored in Firestore by caller
  Future<Map<String, String>> _generateAndStoreKeys(String userId) async {
    final keyPair = await _encryptionService.generateKeyPair();

    // Store private key locally (NEVER sync to cloud)
    await _secureStorage.storePrivateKey(keyPair['privateKey']!);
    await _secureStorage.storePublicKey(keyPair['publicKey']!);
    await _secureStorage.storeUserId(userId);

    return keyPair;
  }

  Future<void> _loadUserKeys(String userId) async {
    final privateKey = await _secureStorage.getPrivateKey();

    if (privateKey != null) {
      _encryptionService.setPrivateKey(privateKey);
      await _secureStorage.storeUserId(userId);
    } else {
      // Keys not found - might be a new device
      // User will need to link device or generate new keys
      throw Exception('Encryption keys not found on this device');
    }
  }

  Future<void> _createUserDocument({
    required String userId,
    required String email,
    required String displayName,
    String? photoUrl,
    required String publicKey,
  }) async {
    final userModel = UserModel(
      id: userId,
      name: displayName,
      avatar: photoUrl ?? '',
      createdAt: DateTime.now(),
      lastActive: DateTime.now(),
      preferences: UserPreferences.defaultPreferences,
    );

    await _db.collection('users').doc(userId).set({
      ...userModel.toJson(),
      'email': email,
      'publicKey': publicKey,
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

      // SECURITY: Don't distinguish between user-not-found and wrong-password
      // This prevents attackers from enumerating valid email addresses
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
