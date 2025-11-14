import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/user_model.dart';
import 'encryption_service.dart';
import 'secure_storage_service.dart';
import 'logger_service.dart';

/// Authentication service for user login/signup
/// Handles Firebase Auth, Google Sign-In, and encryption key generation
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final EncryptionService _encryptionService = EncryptionService();
  final SecureStorageService _secureStorage = SecureStorageService();

  /// Get current user
  User? get currentUser => _auth.currentUser;

  /// Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Get current user ID
  String? get currentUserId => _auth.currentUser?.uid;

  /// Sign up with email and password
  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      LoggerService.auth('Sign up attempt', userId: email);

      // Create Firebase Auth account
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update display name
      await credential.user?.updateDisplayName(displayName);

      // Generate encryption keys for this user
      final keyPair = await _generateAndStoreKeys(credential.user!.uid);

      // Create user document in Firestore
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
      LoggerService.error('Sign up failed', e);
      throw _handleAuthException(e);
    }
  }

  /// Sign in with email and password
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      LoggerService.auth('Sign in attempt', userId: email);

      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Load encryption keys if they exist
      await _loadUserKeys(credential.user!.uid);

      // Update last active
      await _updateLastActive(credential.user!.uid);

      LoggerService.auth('Sign in successful', userId: credential.user!.uid);
      return credential;
    } on FirebaseAuthException catch (e) {
      LoggerService.error('Sign in failed', e);
      throw _handleAuthException(e);
    }
  }

  /// Sign in with Google
  Future<UserCredential> signInWithGoogle() async {
    try {
      LoggerService.auth('Google sign-in attempt');

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
        // Trigger the authentication flow
        final GoogleSignInAccount? googleUser = await GoogleSignIn.instance.authenticate();

        if (googleUser == null) {
          throw Exception('Google sign-in was cancelled');
        }

        // Obtain the auth details from the request
        final GoogleSignInAuthentication googleAuth = googleUser.authentication;

        if (googleAuth.idToken == null) {
          throw Exception('Failed to get ID token from Google Sign-In');
        }

        // Create a new credential
        final credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );

        // Once signed in, return the UserCredential
        userCredential = await _auth.signInWithCredential(credential);
      }

      // Check if this is a new user
      final isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;

      if (isNewUser) {
        LoggerService.auth('New Google user, creating account', userId: userCredential.user!.uid);

        // Generate encryption keys for new user (fast with EC!)
        final keyPair = await _generateAndStoreKeys(userCredential.user!.uid);

        // Create user document with public key
        await _createUserDocument(
          userId: userCredential.user!.uid,
          email: userCredential.user!.email!,
          displayName: userCredential.user!.displayName ?? 'User',
          photoUrl: userCredential.user!.photoURL,
          publicKey: keyPair['publicKey']!,
        );
      } else {
        LoggerService.auth('Existing Google user, loading keys', userId: userCredential.user!.uid);

        // Load existing keys
        await _loadUserKeys(userCredential.user!.uid);

        // Update last active
        await _updateLastActive(userCredential.user!.uid);
      }

      LoggerService.auth('Google sign-in successful', userId: userCredential.user!.uid);
      return userCredential;
    } on FirebaseAuthException catch (e) {
      LoggerService.error('Google sign-in Firebase error', e);
      throw _handleAuthException(e);
    } catch (e) {
      LoggerService.error('Google sign-in failed', e);
      throw Exception('Failed to sign in with Google: $e');
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      final userId = currentUserId;
      LoggerService.auth('Sign out', userId: userId);

      // Clear local encryption keys
      _encryptionService.clearKeys();

      // Sign out from Google if signed in (mobile/desktop only)
      if (!kIsWeb) {
        await GoogleSignIn.instance.signOut();
      }

      // Sign out from Firebase
      await _auth.signOut();

      LoggerService.auth('Sign out successful', userId: userId);

      // Optionally clear secure storage (keep keys for offline access)
      // await _secureStorage.clearAll();
    } catch (e) {
      LoggerService.error('Sign out failed', e);
      throw Exception('Failed to sign out: $e');
    }
  }

  /// Reset password
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Check if user has encryption keys set up
  Future<bool> hasEncryptionKeys() async {
    return await _secureStorage.hasEncryptionKeys();
  }

  /// Re-authenticate user (for sensitive operations)
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

  /// Update user profile
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

  /// Delete account
  Future<void> deleteAccount(String password) async {
    final user = currentUser;
    if (user == null) throw Exception('No user signed in');

    try {
      // Re-authenticate before deletion
      await reauthenticateWithPassword(password);

      // Delete user data from Firestore
      await _db.collection('users').doc(user.uid).delete();

      // Clear local storage
      await _secureStorage.clearAll();

      // Delete Firebase Auth account
      await user.delete();
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Private helper methods

  /// Generate and store encryption keys for new user
  /// Returns the generated key pair to be stored in Firestore by caller
  Future<Map<String, String>> _generateAndStoreKeys(String userId) async {
    LoggerService.encryption('Generating EC key pair');

    // Generate EC key pair (fast - takes milliseconds!)
    final keyPair = await _encryptionService.generateKeyPair();

    // Store private key locally (NEVER sync to cloud)
    await _secureStorage.storePrivateKey(keyPair['privateKey']!);
    await _secureStorage.storePublicKey(keyPair['publicKey']!);
    await _secureStorage.storeUserId(userId);

    LoggerService.encryption('EC key pair generated and stored', success: true);

    return keyPair;
  }

  /// Load user's encryption keys from local storage
  Future<void> _loadUserKeys(String userId) async {
    LoggerService.encryption('Loading encryption keys');

    final privateKey = await _secureStorage.getPrivateKey();

    if (privateKey != null) {
      _encryptionService.setPrivateKey(privateKey);
      await _secureStorage.storeUserId(userId);
      LoggerService.encryption('Keys loaded successfully', success: true);
    } else {
      // Keys not found - might be a new device
      // User will need to link device or generate new keys
      LoggerService.warning('Encryption keys not found on this device');
      throw Exception('Encryption keys not found on this device');
    }
  }

  /// Create user document in Firestore
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

  /// Update last active timestamp
  Future<void> _updateLastActive(String userId) async {
    await _db.collection('users').doc(userId).update({
      'lastActive': FieldValue.serverTimestamp(),
    });
  }

  /// Handle Firebase Auth exceptions
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
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
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
