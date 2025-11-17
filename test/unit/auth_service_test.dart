import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:echo_protocol/services/auth.dart';
import 'package:echo_protocol/services/encryption.dart';
import 'package:echo_protocol/services/secure_storage.dart';
import 'package:echo_protocol/utils/validators.dart';

// Generate mocks for these classes
@GenerateMocks([
  FirebaseAuth,
  FirebaseFirestore,
  UserCredential,
  User,
  EncryptionService,
  SecureStorageService,
], customMocks: [
  MockSpec<CollectionReference<Map<String, dynamic>>>(
    as: #MockCollectionReference,
  ),
  MockSpec<DocumentReference<Map<String, dynamic>>>(
    as: #MockDocumentReference,
  ),
])
import 'auth_service_test.mocks.dart';

void main() {
  group('AuthService', () {
    late AuthService authService;
    late MockFirebaseAuth mockAuth;
    late MockFirebaseFirestore mockFirestore;
    late MockEncryptionService mockEncryption;
    late MockSecureStorageService mockSecureStorage;
    late MockUserCredential mockUserCredential;
    late MockUser mockUser;
    late MockCollectionReference mockCollection;
    late MockDocumentReference mockDocument;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      mockFirestore = MockFirebaseFirestore();
      mockEncryption = MockEncryptionService();
      mockSecureStorage = MockSecureStorageService();
      mockUserCredential = MockUserCredential();
      mockUser = MockUser();
      mockCollection = MockCollectionReference();
      mockDocument = MockDocumentReference();

      authService = AuthService(
        auth: mockAuth,
        firestore: mockFirestore,
        encryptionService: mockEncryption,
        secureStorage: mockSecureStorage,
      );
    });

    group('Password Security', () {
      test('SECURITY: Must reject passwords shorter than 12 characters', () {
        final weakPasswords = [
          'Short1!',      // 7 chars
          'Pass123!',     // 8 chars
          'MyPass1!',     // 8 chars
          '12345678!A',   // 11 chars
        ];

        for (final password in weakPasswords) {
          final result = Validators.validatePassword(password);
          expect(result, isNotNull,
            reason: 'Password "$password" (${password.length} chars) MUST be rejected');
          expect(result!.toLowerCase(), contains('12'),
            reason: 'Error must mention 12 character minimum');
        }
      });

      test('SECURITY: Must require uppercase letter', () {
        final noUppercase = [
          'alllowercase1!',
          'password123!@#',
          'securepass456!',
        ];

        for (final password in noUppercase) {
          final result = Validators.validatePassword(password);
          expect(result, isNotNull,
            reason: 'Password without uppercase MUST be rejected');
          expect(result!.toLowerCase(), contains('uppercase'),
            reason: 'Error must mention uppercase requirement');
        }
      });

      test('SECURITY: Must require lowercase letter', () {
        final noLowercase = [
          'ALLUPPERCASE1!',
          'PASSWORD123!@#',
          'SECUREPASS456!',
        ];

        for (final password in noLowercase) {
          final result = Validators.validatePassword(password);
          expect(result, isNotNull,
            reason: 'Password without lowercase MUST be rejected');
          expect(result!.toLowerCase(), contains('lowercase'),
            reason: 'Error must mention lowercase requirement');
        }
      });

      test('SECURITY: Must require at least one number', () {
        final noNumbers = [
          'NoNumbersHere!',
          'SecurePassword!@#',
          'ValidPassword!!',
        ];

        for (final password in noNumbers) {
          final result = Validators.validatePassword(password);
          expect(result, isNotNull,
            reason: 'Password without numbers MUST be rejected');
          expect(result!.toLowerCase(), contains('number'),
            reason: 'Error must mention number requirement');
        }
      });

      test('SECURITY: Must require special characters', () {
        final noSpecial = [
          'NoSpecial123',
          'Password1234',
          'SecurePass567',
        ];

        for (final password in noSpecial) {
          final result = Validators.validatePassword(password);
          expect(result, isNotNull,
            reason: 'Password without special chars MUST be rejected');
          expect(result!.toLowerCase(), contains('special'),
            reason: 'Error must mention special character requirement');
        }
      });

      test('SECURITY: Must reject common passwords', () {
        final commonPasswords = [
          'Password123!',  // Contains 'password123!'
          'Admin123456!',  // Contains 'admin123456!'
          'Welcome12345!', // Contains 'welcome12345'
        ];

        for (final password in commonPasswords) {
          final result = Validators.validatePassword(password);
          expect(result, isNotNull,
            reason: 'Common password "$password" MUST be rejected');
          expect(result!.toLowerCase(), contains('common'),
            reason: 'Error must mention common password');
        }
      });

      test('SECURITY: Must reject sequential characters', () {
        final sequential = [
          'Z!Abcd789#Yz',      // Contains 'abcd' (4+ sequential)
          'H!Efgh901#Mn',      // Contains 'efgh' (4+ sequential)
          'K!2345Zyx#Qb',      // Contains '2345' (4+ sequential)
        ];

        for (final password in sequential) {
          final result = Validators.validatePassword(password);
          expect(result, isNotNull,
            reason: 'Sequential password "$password" MUST be rejected');
          expect(result!.toLowerCase(), contains('sequential'),
            reason: 'Error must mention sequential characters');
        }
      });

      test('SECURITY: Must reject repeated characters', () {
        final repeated = [
          'Zx!aaaa789#BC',     // 'aaaa' (4 repeated lowercase 'a')
          'Hf!1111111#MN',     // '1111111' (7 repeated)
          'Kb!Xtttt90#QZ',     // 'tttt' (4 repeated)
        ];

        for (final password in repeated) {
          final result = Validators.validatePassword(password);
          expect(result, isNotNull,
            reason: 'Password with repeated chars "$password" MUST be rejected');
          expect(result!.toLowerCase(), contains('repeated'),
            reason: 'Error must mention repeated characters');
        }
      });

      test('SECURITY: Must enforce maximum length (DoS prevention)', () {
        // 129 character password (over limit)
        final tooLong = 'A' * 128 + 'a1!';

        final result = Validators.validatePassword(tooLong);
        expect(result, isNotNull,
          reason: 'Password over 128 chars MUST be rejected (DoS prevention)');
        expect(result!.toLowerCase(), contains('128'),
          reason: 'Error must mention 128 character maximum');
      });

      test('SECURITY: Must accept strong valid passwords', () {
        final validPasswords = [
          'MySecure@Pa55w0rd',   // No common words
          'C0mpl3x!Secur1ty',    // No common words
          'Str0ng#F0rtres5!',    // No common words
          '!Br@v0Zulu789!',      // No common words, no sequences
        ];

        for (final password in validPasswords) {
          final result = Validators.validatePassword(password);
          expect(result, isNull,
            reason: 'Valid strong password "$password" should be accepted');
        }
      });
    });

    group('Email Security', () {
      test('SECURITY: Must reject SQL injection attempts', () {
        final sqlInjections = [
          "test@example.com'; DROP TABLE users; --",
          'admin@site.com" OR "1"="1',
          "user@test.com'; DELETE FROM auth; --",
        ];

        for (final email in sqlInjections) {
          final result = Validators.validateEmail(email);
          expect(result, isNotNull,
            reason: 'SQL injection "$email" MUST be rejected');
        }
      });

      test('SECURITY: Must reject XSS attempts', () {
        final xssAttempts = [
          'test@example.com<script>alert(1)</script>',
          'user@test.com<img src=x onerror=alert(1)>',
          'admin@site.com<svg/onload=alert(1)>',
        ];

        for (final email in xssAttempts) {
          final result = Validators.validateEmail(email);
          expect(result, isNotNull,
            reason: 'XSS attempt "$email" MUST be rejected');
          // Error message should mention invalid OR valid (but reject the email)
          expect(result!.toLowerCase(), anyOf(contains('invalid'), contains('valid')),
            reason: 'Error must indicate email is not valid');
        }
      });

      test('SECURITY: Must reject NoSQL injection attempts', () {
        final nosqlInjections = [
          r'test@example.com{$ne: null}',
          r'admin@site.com{$gt: ""}',
          r'user@test.com{"$regex": ".*"}',
        ];

        for (final email in nosqlInjections) {
          final result = Validators.validateEmail(email);
          expect(result, isNotNull,
            reason: 'NoSQL injection "$email" MUST be rejected');
        }
      });

      test('SECURITY: Must reject emails with dangerous characters', () {
        final dangerousChars = [
          'test@example.com;',
          'user@test.com(',
          'admin@site.com)',
          'test@example.com{',
          'user@test.com}',
          'admin@site.com[',
          'test@example.com]',
          'user@test.com\\',
        ];

        for (final email in dangerousChars) {
          final result = Validators.validateEmail(email);
          expect(result, isNotNull,
            reason: 'Email with dangerous char "$email" MUST be rejected');
        }
      });

      test('SECURITY: Must enforce maximum email length (DoS prevention)', () {
        // 255 character email (over RFC limit of 254)
        // 'a' * 240 + '@example.com' = 240 + 12 = 252 chars (under limit)
        // Need 255 chars to exceed limit
        final tooLong = 'a' * 243 + '@example.com'; // 243 + 12 = 255 chars

        final result = Validators.validateEmail(tooLong);
        expect(result, isNotNull,
          reason: 'Email over 254 chars MUST be rejected (DoS prevention)');
        expect(result!.toLowerCase(), contains('long'),
          reason: 'Error must mention length limit');
      });

      test('SECURITY: Must trim whitespace to prevent bypass', () {
        final withWhitespace = '  test@example.com  ';

        // Should trim and validate
        final result = Validators.validateEmail(withWhitespace);
        expect(result, isNull,
          reason: 'Valid email with whitespace should be trimmed and accepted');
      });

      test('SECURITY: Must reject multiple @ symbols', () {
        final multipleAt = [
          'test@@example.com',
          'user@test@example.com',
          '@@example.com',
        ];

        for (final email in multipleAt) {
          final result = Validators.validateEmail(email);
          expect(result, isNotNull,
            reason: 'Email with multiple @ "$email" MUST be rejected');
        }
      });

      test('SECURITY: Must reject consecutive dots', () {
        final consecutiveDots = [
          'test..user@example.com',
          'user@example..com',
          'test...@example.com',
        ];

        for (final email in consecutiveDots) {
          final result = Validators.validateEmail(email);
          expect(result, isNotNull,
            reason: 'Email with consecutive dots "$email" MUST be rejected');
        }
      });

      test('SECURITY: Must validate proper domain format', () {
        final invalidDomains = [
          'test@',
          'test@example',  // No TLD
          'test@.com',
          '@example.com',
        ];

        for (final email in invalidDomains) {
          final result = Validators.validateEmail(email);
          expect(result, isNotNull,
            reason: 'Email with invalid domain "$email" MUST be rejected');
        }
      });

      test('SECURITY: Must accept valid emails', () {
        final validEmails = [
          'user@example.com',
          'test.user@example.co.uk',
          'admin+tag@site.org',
          'user_name@test-domain.com',
        ];

        for (final email in validEmails) {
          final result = Validators.validateEmail(email);
          expect(result, isNull,
            reason: 'Valid email "$email" should be accepted');
        }
      });
    });

    group('Encryption Key Security', () {
      test('SECURITY: Private keys MUST be stored locally, NEVER in Firestore', () async {
        // Arrange
        const userId = 'user123';
        const publicKey = 'public_key_base64';
        const privateKey = 'private_key_base64';

        when(mockAuth.createUserWithEmailAndPassword(
          email: anyNamed('email'),
          password: anyNamed('password'),
        )).thenAnswer((_) async => mockUserCredential);

        when(mockUserCredential.user).thenReturn(mockUser);
        when(mockUser.uid).thenReturn(userId);
        when(mockUser.updateDisplayName(any)).thenAnswer((_) async {});

        when(mockEncryption.generateKeyPair()).thenAnswer(
          (_) async => {'publicKey': publicKey, 'privateKey': privateKey},
        );

        when(mockSecureStorage.storePrivateKey(privateKey))
            .thenAnswer((_) async {});
        when(mockSecureStorage.storePublicKey(publicKey))
            .thenAnswer((_) async {});
        when(mockSecureStorage.storeUserId(userId))
            .thenAnswer((_) async {});

        when(mockFirestore.collection('users')).thenReturn(mockCollection);
        when(mockCollection.doc(userId)).thenReturn(mockDocument);

        // Capture what's sent to Firestore
        Map<String, dynamic>? firestoreData;
        when(mockDocument.set(any)).thenAnswer((invocation) {
          firestoreData = invocation.positionalArguments[0] as Map<String, dynamic>;
          return Future.value();
        });

        // Act
        await authService.signUpWithEmail(
          email: 'test@example.com',
          password: 'ValidPass123!',
          displayName: 'Test User',
        );

        // Assert - CRITICAL SECURITY CHECK
        expect(firestoreData, isNotNull);
        expect(firestoreData!.containsKey('privateKey'), false,
          reason: 'CRITICAL: Private key MUST NEVER be sent to Firestore');
        expect(firestoreData!.containsKey('publicKey'), true,
          reason: 'Public key should be in Firestore');
        expect(firestoreData!['publicKey'], equals(publicKey));

        // Verify private key was stored locally
        verify(mockSecureStorage.storePrivateKey(privateKey)).called(1);
      });

      test('SECURITY: Private key MUST be stored in secure storage on signup', () async {
        // Arrange
        const userId = 'user123';
        const publicKey = 'public_key_base64';
        const privateKey = 'private_key_base64';

        when(mockAuth.createUserWithEmailAndPassword(
          email: anyNamed('email'),
          password: anyNamed('password'),
        )).thenAnswer((_) async => mockUserCredential);

        when(mockUserCredential.user).thenReturn(mockUser);
        when(mockUser.uid).thenReturn(userId);
        when(mockUser.updateDisplayName(any)).thenAnswer((_) async {});

        when(mockEncryption.generateKeyPair()).thenAnswer(
          (_) async => {'publicKey': publicKey, 'privateKey': privateKey},
        );

        when(mockSecureStorage.storePrivateKey(any))
            .thenAnswer((_) async {});
        when(mockSecureStorage.storePublicKey(any))
            .thenAnswer((_) async {});
        when(mockSecureStorage.storeUserId(any))
            .thenAnswer((_) async {});

        when(mockFirestore.collection('users')).thenReturn(mockCollection);
        when(mockCollection.doc(userId)).thenReturn(mockDocument);
        when(mockDocument.set(any)).thenAnswer((_) async {});

        // Act
        await authService.signUpWithEmail(
          email: 'test@example.com',
          password: 'ValidPass123!',
          displayName: 'Test User',
        );

        // Assert - Verify secure storage was called with exact key
        verify(mockSecureStorage.storePrivateKey(privateKey)).called(1);
        verify(mockSecureStorage.storePublicKey(publicKey)).called(1);
        verify(mockSecureStorage.storeUserId(userId)).called(1);
      });

      test('SECURITY: Encryption keys MUST be generated for every new user', () async {
        // Arrange
        const userId = 'user123';

        when(mockAuth.createUserWithEmailAndPassword(
          email: anyNamed('email'),
          password: anyNamed('password'),
        )).thenAnswer((_) async => mockUserCredential);

        when(mockUserCredential.user).thenReturn(mockUser);
        when(mockUser.uid).thenReturn(userId);
        when(mockUser.updateDisplayName(any)).thenAnswer((_) async {});

        when(mockEncryption.generateKeyPair()).thenAnswer(
          (_) async => {'publicKey': 'pub', 'privateKey': 'priv'},
        );

        when(mockSecureStorage.storePrivateKey(any))
            .thenAnswer((_) async {});
        when(mockSecureStorage.storePublicKey(any))
            .thenAnswer((_) async {});
        when(mockSecureStorage.storeUserId(any))
            .thenAnswer((_) async {});

        when(mockFirestore.collection('users')).thenReturn(mockCollection);
        when(mockCollection.doc(userId)).thenReturn(mockDocument);
        when(mockDocument.set(any)).thenAnswer((_) async {});

        // Act
        await authService.signUpWithEmail(
          email: 'test@example.com',
          password: 'ValidPass123!',
          displayName: 'Test User',
        );

        // Assert - MUST generate keys
        verify(mockEncryption.generateKeyPair()).called(1);
      });

      test('SECURITY: Sign in MUST load keys from secure storage, not Firestore', () async {
        // Arrange
        const userId = 'user123';
        const privateKey = 'stored_private_key';

        when(mockAuth.signInWithEmailAndPassword(
          email: anyNamed('email'),
          password: anyNamed('password'),
        )).thenAnswer((_) async => mockUserCredential);

        when(mockUserCredential.user).thenReturn(mockUser);
        when(mockUser.uid).thenReturn(userId);

        when(mockSecureStorage.getPrivateKey())
            .thenAnswer((_) async => privateKey);
        when(mockSecureStorage.storeUserId(userId))
            .thenAnswer((_) async {});

        when(mockFirestore.collection('users')).thenReturn(mockCollection);
        when(mockCollection.doc(userId)).thenReturn(mockDocument);
        when(mockDocument.update(any)).thenAnswer((_) async {});

        // Act
        await authService.signInWithEmail(
          email: 'test@example.com',
          password: 'ValidPass123!',
        );

        // Assert - Keys MUST come from secure storage
        verify(mockSecureStorage.getPrivateKey()).called(1);
        verify(mockEncryption.setPrivateKey(privateKey)).called(1);

        // Verify we did NOT fetch from Firestore
        verifyNever(mockDocument.get());
      });

      test('SECURITY: Sign out MUST clear encryption keys from memory', () async {
        // Arrange
        when(mockAuth.currentUser).thenReturn(mockUser);
        when(mockUser.uid).thenReturn('test-user-id');
        when(mockEncryption.clearKeys()).thenReturn(null);
        when(mockAuth.signOut()).thenAnswer((_) async {});

        // Act
        await authService.signOut();

        // Assert - Keys MUST be cleared
        verify(mockEncryption.clearKeys()).called(1);
      });

      test('SECURITY: Failed signup MUST NOT leave orphaned keys', () async {
        // Arrange
        when(mockAuth.createUserWithEmailAndPassword(
          email: anyNamed('email'),
          password: anyNamed('password'),
        )).thenThrow(FirebaseAuthException(
          code: 'email-already-in-use',
        ));

        // Act & Assert
        expect(
          () async => await authService.signUpWithEmail(
            email: 'existing@example.com',
            password: 'ValidPass123!',
            displayName: 'Test',
          ),
          throwsA(isA<String>()),
        );

        // Verify keys were NOT generated
        verifyNever(mockEncryption.generateKeyPair());
        verifyNever(mockSecureStorage.storePrivateKey(any));
      });
    });

    group('Error Handling Security', () {
      test('SECURITY: Error messages MUST NOT leak user existence', () async {
        // Arrange
        when(mockAuth.signInWithEmailAndPassword(
          email: anyNamed('email'),
          password: anyNamed('password'),
        )).thenThrow(FirebaseAuthException(
          code: 'user-not-found',
          message: 'No user record',
        ));

        // Act & Assert
        try {
          await authService.signInWithEmail(
            email: 'nonexistent@example.com',
            password: 'AnyPass123!',
          );
          fail('Should have thrown');
        } catch (e) {
          final errorMsg = e.toString();
          // Error should be generic
          expect(errorMsg, isNot(contains('exists')),
            reason: 'Should not reveal if user exists');
          expect(errorMsg, isNot(contains('registered')),
            reason: 'Should not reveal registration status');
        }
      });

      test('SECURITY: Wrong password error MUST be generic', () async {
        // Arrange
        when(mockAuth.signInWithEmailAndPassword(
          email: anyNamed('email'),
          password: anyNamed('password'),
        )).thenThrow(FirebaseAuthException(
          code: 'wrong-password',
          message: 'Wrong password',
        ));

        // Act & Assert
        try {
          await authService.signInWithEmail(
            email: 'user@example.com',
            password: 'WrongPass123!',
          );
          fail('Should have thrown');
        } catch (e) {
          final errorMsg = e.toString();
          // Should not distinguish between wrong password and wrong email
          expect(errorMsg, isNot(contains('password')),
            reason: 'Should not reveal that password was wrong specifically');
        }
      });

      test('SECURITY: Network errors MUST be sanitized', () async {
        // Arrange
        when(mockAuth.signInWithEmailAndPassword(
          email: anyNamed('email'),
          password: anyNamed('password'),
        )).thenThrow(FirebaseAuthException(
          code: 'network-request-failed',
          message: 'Network error',
        ));

        // Act & Assert
        try {
          await authService.signInWithEmail(
            email: 'user@example.com',
            password: 'ValidPass123!',
          );
          fail('Should have thrown');
        } catch (e) {
          final errorMsg = e.toString();
          // Should mention network but not internal details
          expect(errorMsg.toLowerCase(), contains('network'),
            reason: 'Should indicate network issue');
          expect(errorMsg, isNot(contains('firebase')),
            reason: 'Should not leak implementation details');
        }
      });
    });

    group('Rate Limiting Security', () {
      test('SECURITY: Too many requests MUST be blocked', () async {
        // Arrange
        when(mockAuth.signInWithEmailAndPassword(
          email: anyNamed('email'),
          password: anyNamed('password'),
        )).thenThrow(FirebaseAuthException(
          code: 'too-many-requests',
          message: 'Too many attempts',
        ));

        // Act & Assert
        try {
          await authService.signInWithEmail(
            email: 'user@example.com',
            password: 'AnyPass123!',
          );
          fail('Should have thrown');
        } catch (e) {
          final errorMsg = e.toString();
          expect(errorMsg.toLowerCase(), contains('many'),
            reason: 'Should indicate rate limiting');
          expect(errorMsg.toLowerCase(), anyOf(contains('try'), contains('later')),
            reason: 'Should suggest trying later');
        }
      });
    });
  });
}
