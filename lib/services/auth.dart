import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/user.dart';
import '../utils/validators.dart';
import 'crypto/protocol_service.dart';
import 'secure_storage.dart';
import '../utils/logger.dart';

class SignUpResult {
  final UserCredential credential;
  final String recoveryPhrase;

  SignUpResult({required this.credential, required this.recoveryPhrase});
}

class SignInResult {
  final UserCredential credential;
  final bool needsRecovery;

  SignInResult({required this.credential, this.needsRecovery = false});
}

class LinkAccountResult {
  final UserCredential credential;
  final bool success;

  LinkAccountResult({required this.credential, required this.success});
}

class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final ProtocolService _protocolService;
  final SecureStorageService _secureStorage;

  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    ProtocolService? protocolService,
    SecureStorageService? secureStorage,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance,
        _protocolService = protocolService ?? ProtocolService(),
        _secureStorage = secureStorage ?? SecureStorageService();

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  String? get currentUserId => _auth.currentUser?.uid;

  static const String _syntheticEmailDomain = 'echo-protocol.local';

  String _toAuthEmail(String usernameOrEmail) {
    if (usernameOrEmail.contains('@')) {
      return usernameOrEmail;
    }
    return '${usernameOrEmail.toLowerCase()}@$_syntheticEmailDomain';
  }

  bool _isSyntheticEmail(String? email) {
    return email != null && email.endsWith('@$_syntheticEmailDomain');
  }

  String? get currentUserEmail {
    final email = currentUser?.email;
    if (_isSyntheticEmail(email)) return null;
    return email;
  }

  Future<SignUpResult> signUp({
    required String username,
    required String password,
    String? email,
  }) async {
    try {
      final usernameValidation = Validators.validateUsername(username);
      if (usernameValidation != null) {
        throw Exception(usernameValidation);
      }

      final authEmail = email?.isNotEmpty == true ? email! : _toAuthEmail(username);
      final hasRealEmail = email?.isNotEmpty == true;

      final credential = await _auth.createUserWithEmailAndPassword(
        email: authEmail,
        password: password,
      );

      final sanitizedName = username.trim();
      await credential.user?.updateDisplayName(sanitizedName);

      await _secureStorage.storeUserId(credential.user!.uid);

      final mnemonic = await _protocolService.generateRecoveryPhrase();
      await _protocolService.initialize(recoveryPhrase: mnemonic);
      final fingerprint = await _protocolService.getFingerprint();
      final publicKey = await _protocolService.getPublicKey();

      if (publicKey != null) {
        await _secureStorage.storePublicKey(publicKey);
      }

      await _createUserDocument(
        userId: credential.user!.uid,
        email: hasRealEmail ? authEmail : '',
        username: username,
        displayName: username,
        photoUrl: null,
        publicKey: publicKey ?? '',
        fingerprint: fingerprint ?? '',
      );

      await _protocolService.uploadPreKeys();

      await _secureStorage.storePendingRecoveryPhrase(mnemonic);

      LoggerService.auth('Sign up complete');
      return SignUpResult(
        credential: credential,
        recoveryPhrase: mnemonic,
      );
    } on FirebaseAuthException catch (e) {
      LoggerService.error('Sign up failed');
      throw _handleAuthException(e);
    }
  }

  Future<SignInResult> signIn({
    required String usernameOrEmail,
    required String password,
  }) async {
    try {
      final authEmail = _toAuthEmail(usernameOrEmail);

      final credential = await _auth.signInWithEmailAndPassword(
        email: authEmail,
        password: password,
      );

      final needsRecovery = !await _tryLoadUserKeys(credential.user!.uid);

      LoggerService.auth('Sign in complete');
      return SignInResult(credential: credential, needsRecovery: needsRecovery);
    } on FirebaseAuthException catch (e) {
      LoggerService.error('Sign in failed');
      throw _handleAuthException(e);
    }
  }

  Future<dynamic> signInWithGoogle() async {
    try {
      final UserCredential userCredential;

      if (kIsWeb) {
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        userCredential = await _auth.signInWithPopup(googleProvider);
      } else {
        final GoogleSignInAccount googleUser =
            await GoogleSignIn.instance.authenticate();
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
        await _secureStorage.storeUserId(userCredential.user!.uid);

        final mnemonic = await _protocolService.generateRecoveryPhrase();
        await _protocolService.initialize(recoveryPhrase: mnemonic);
        final fingerprint = await _protocolService.getFingerprint();
        final publicKey = await _protocolService.getPublicKey();

        if (publicKey != null) {
          await _secureStorage.storePublicKey(publicKey);
        }

        final email = userCredential.user!.email!;
        final generatedUsername = email.split('@').first;

        await _createUserDocument(
          userId: userCredential.user!.uid,
          email: email,
          username: generatedUsername,
          displayName: generatedUsername,
          photoUrl: null,
          publicKey: publicKey ?? '',
          fingerprint: fingerprint ?? '',
        );

        await _protocolService.uploadPreKeys();

        await _secureStorage.storePendingRecoveryPhrase(mnemonic);

        LoggerService.auth('Google sign-up complete');
        return SignUpResult(
          credential: userCredential,
          recoveryPhrase: mnemonic,
        );
      } else {
        final needsRecovery = !await _tryLoadUserKeys(userCredential.user!.uid);

        LoggerService.auth('Google sign-in complete');
        return SignInResult(credential: userCredential, needsRecovery: needsRecovery);
      }
    } on FirebaseAuthException catch (e) {
      LoggerService.error('Google sign-in failed');
      throw _handleAuthException(e);
    } catch (e) {
      LoggerService.error('Google sign-in failed');
      throw Exception('Failed to sign in with Google');
    }
  }

  Future<void> signOut() async {
    if (!kIsWeb) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }

    await _auth.signOut();
    LoggerService.auth('Sign out complete');
  }

  Future<LinkAccountResult> linkGoogleAccount() async {
    final user = currentUser;
    if (user == null) throw Exception('No user signed in');

    try {
      final AuthCredential googleCredential;

      if (kIsWeb) {
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        final result = await user.linkWithPopup(googleProvider);
        LoggerService.auth('Account link complete');
        return LinkAccountResult(credential: result, success: true);
      } else {
        final GoogleSignInAccount googleUser =
            await GoogleSignIn.instance.authenticate();
        final GoogleSignInAuthentication googleAuth = googleUser.authentication;

        if (googleAuth.idToken == null) {
          throw Exception('Authentication failed');
        }

        googleCredential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );
      }

      final result = await user.linkWithCredential(googleCredential);

      if (result.user?.email != null && user.email == null) {
        await _db.collection('users').doc(user.uid).update({
          'email': result.user!.email,
        });
      }

      LoggerService.auth('Account link complete');
      return LinkAccountResult(credential: result, success: true);
    } on FirebaseAuthException catch (e) {
      LoggerService.error('Account link failed');
      if (e.code == 'credential-already-in-use') {
        throw Exception('This account is already linked to another user');
      }
      if (e.code == 'provider-already-linked') {
        throw Exception('A Google account is already linked');
      }
      throw _handleAuthException(e);
    } catch (e) {
      LoggerService.error('Account link failed');
      throw Exception('Failed to link account');
    }
  }

  List<String> getLinkedProviders() {
    final user = currentUser;
    if (user == null) return [];
    return user.providerData.map((info) => info.providerId).toList();
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

  Future<void> reauthenticateWithGoogle() async {
    final user = currentUser;
    if (user == null) throw Exception('No user signed in');

    try {
      if (kIsWeb) {
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        await user.reauthenticateWithPopup(googleProvider);
      } else {
        final GoogleSignInAccount googleUser =
            await GoogleSignIn.instance.authenticate();
        final GoogleSignInAuthentication googleAuth = googleUser.authentication;

        if (googleAuth.idToken == null) {
          throw Exception('Authentication failed');
        }

        final credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );

        await user.reauthenticateWithCredential(credential);
      }
    } catch (e) {
      LoggerService.error('Re-authentication failed');
      throw Exception('Re-authentication failed');
    }
  }

  bool get canReauthenticateWithPassword {
    final providers = getLinkedProviders();
    return providers.contains('password');
  }

  bool get canReauthenticateWithGoogle {
    final providers = getLinkedProviders();
    return providers.contains('google.com');
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

  Future<void> deleteAccount({String? password, bool useGoogle = false}) async {
    final user = currentUser;
    if (user == null) throw Exception('No user signed in');

    try {
      if (useGoogle && canReauthenticateWithGoogle) {
        await reauthenticateWithGoogle();
      } else if (password != null && canReauthenticateWithPassword) {
        await reauthenticateWithPassword(password);
      } else {
        throw Exception('Re-authentication required');
      }

      await _db.collection('users').doc(user.uid).delete();

      await _secureStorage.clearAll();

      await user.delete();
      LoggerService.auth('Account deleted');
    } on FirebaseAuthException catch (e) {
      LoggerService.error('Account deletion failed');
      throw _handleAuthException(e);
    }
  }

  Future<String?> getMyPublicKeyFingerprint() async {
    return _protocolService.getFingerprint();
  }

  Future<String?> getPartnerFingerprint(String partnerId) async {
    return _protocolService.getPartnerFingerprint(partnerId);
  }

  Future<bool> _tryLoadUserKeys(String userId) async {
    final storedUserId = await _secureStorage.getUserId();

    if (storedUserId != null && storedUserId != userId) {
      await _secureStorage.clearEncryptionKeys();
      _protocolService.dispose();
      return false;
    }

    try {
      await _protocolService.initializeFromStorage();
      await _secureStorage.storeUserId(userId);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> recoverWithPhrase(String mnemonic) async {
    final user = currentUser;
    if (user == null) throw Exception('No user signed in');

    await _protocolService.initialize(recoveryPhrase: mnemonic);

    final derivedFingerprint = await _protocolService.getFingerprint();

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final storedFingerprint = userDoc.data()?['publicKey'] as String?;

    if (storedFingerprint == null) {
      throw Exception('User account not found');
    }

    if (derivedFingerprint != storedFingerprint) {
      _protocolService.dispose();
      throw Exception('Recovery phrase does not match this account');
    }

    await _secureStorage.storeUserId(user.uid);
    LoggerService.auth('Recovery complete');
  }

  Future<void> _createUserDocument({
    required String userId,
    required String email,
    required String username,
    required String displayName,
    String? photoUrl,
    required String publicKey,
    required String fingerprint,
  }) async {
    final now = DateTime.now();
    final dayOnly = DateTime.utc(now.year, now.month, now.day);
    const initialVersion = 1;

    final userModel = UserModel(
      id: userId,
      username: username,
      name: displayName,
      avatar: photoUrl ?? '',
      createdAt: dayOnly,
      preferences: UserPreferences.defaultPreferences,
    );

    await _db.collection('users').doc(userId).set({
      ...userModel.toJson(),
      'email': email,
      'publicKey': publicKey,
      'publicKeyVersion': initialVersion,
      'publicKeyFingerprint': fingerprint,
      'linkedDevices': [],
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
