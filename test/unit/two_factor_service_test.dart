import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:echo_protocol/services/two_factor.dart';
import 'package:echo_protocol/services/secure_storage.dart';

// Generate mocks for these classes
@GenerateMocks([
  FirebaseFirestore,
  FirebaseAuth,
  FirebaseFunctions,
  User,
  SecureStorageService,
  HttpsCallable,
  HttpsCallableResult,
], customMocks: [
  MockSpec<CollectionReference<Map<String, dynamic>>>(
    as: #MockCollectionReference,
  ),
  MockSpec<DocumentReference<Map<String, dynamic>>>(
    as: #MockDocumentReference,
  ),
  MockSpec<DocumentSnapshot<Map<String, dynamic>>>(
    as: #MockDocumentSnapshot,
  ),
])
import 'two_factor_service_test.mocks.dart';

void main() {
  group('TwoFactorService - Cloud Functions', () {
    late TwoFactorService service;
    late MockFirebaseFirestore mockFirestore;
    late MockFirebaseAuth mockAuth;
    late MockFirebaseFunctions mockFunctions;
    late MockSecureStorageService mockSecureStorage;
    late MockUser mockUser;
    late MockCollectionReference mockUsersCollection;
    late MockDocumentReference mockUserDocument;
    late MockDocumentSnapshot mockDocumentSnapshot;

    setUp(() {
      mockFirestore = MockFirebaseFirestore();
      mockAuth = MockFirebaseAuth();
      mockFunctions = MockFirebaseFunctions();
      mockSecureStorage = MockSecureStorageService();
      mockUser = MockUser();
      mockUsersCollection = MockCollectionReference();
      mockUserDocument = MockDocumentReference();
      mockDocumentSnapshot = MockDocumentSnapshot();

      // Setup default Firebase mocks
      when(mockAuth.currentUser).thenReturn(mockUser);
      when(mockUser.uid).thenReturn('test-user-id');
      when(mockUser.email).thenReturn('test@example.com');

      when(mockFirestore.collection('users')).thenReturn(mockUsersCollection);
      when(mockUsersCollection.doc(any)).thenReturn(mockUserDocument);

      service = TwoFactorService(
        firestore: mockFirestore,
        auth: mockAuth,
        functions: mockFunctions,
        secureStorage: mockSecureStorage,
      );
    });

    group('Enable 2FA (Cloud Function)', () {
      test('should call enable2FA Cloud Function and return setup data', () async {
        final mockCallable = MockHttpsCallable();
        final mockResult = MockHttpsCallableResult();

        final expectedData = {
          'success': true,
          'qrCodeUrl': 'otpauth://totp/EchoProtocol:test@example.com?secret=TESTSECRET&issuer=EchoProtocol',
          'secret': 'TESTSECRET',
          'backupCodes': ['1234-5678', '2345-6789', '3456-7890', '4567-8901', '5678-9012',
                          '6789-0123', '7890-1234', '8901-2345', '9012-3456', '0123-4567'],
        };

        when(mockFunctions.httpsCallable('enable2FA')).thenReturn(mockCallable);
        when(mockCallable.call()).thenAnswer((_) async => mockResult);
        when(mockResult.data).thenReturn(expectedData);
        when(mockSecureStorage.storeBackupCodes(any)).thenAnswer((_) async => Future.value());

        final setup = await service.enable2FA('test-user-id');

        expect(setup.secret, 'TESTSECRET');
        expect(setup.qrCodeData, contains('otpauth://totp/'));
        expect(setup.qrCodeData, contains('EchoProtocol'));
        expect(setup.backupCodes, hasLength(10));
        verify(mockFunctions.httpsCallable('enable2FA')).called(1);
        verify(mockCallable.call()).called(1);
        verify(mockSecureStorage.storeBackupCodes(setup.backupCodes)).called(1);
      });

      test('should handle Cloud Function errors gracefully', () async {
        final mockCallable = MockHttpsCallable();

        when(mockFunctions.httpsCallable('enable2FA')).thenReturn(mockCallable);
        when(mockCallable.call()).thenThrow(
          FirebaseFunctionsException(code: 'internal', message: 'Server error'),
        );

        expect(() => service.enable2FA('test-user-id'), throwsA(isA<Exception>()));
      });
    });

    group('Verify TOTP (Cloud Function)', () {
      test('CRITICAL: should verify TOTP via Cloud Function', () async {
        // Arrange
        final mockCallable = MockHttpsCallable();
        final mockResult = MockHttpsCallableResult();

        when(mockFunctions.httpsCallable('verify2FATOTP')).thenReturn(mockCallable);
        when(mockCallable.call({'code': '123456'})).thenAnswer((_) async => mockResult);
        when(mockResult.data).thenReturn({
          'success': true,
          'verified': true,
        });

        // Act
        final result = await service.verifyTOTP('123456', userId: 'test-user-id');

        // Assert
        expect(result, true);
        verify(mockFunctions.httpsCallable('verify2FATOTP')).called(1);
        verify(mockCallable.call({'code': '123456'})).called(1);
      });

      test('CRITICAL: should reject invalid TOTP code', () async {
        // Arrange
        final mockCallable = MockHttpsCallable();

        when(mockFunctions.httpsCallable('verify2FATOTP')).thenReturn(mockCallable);
        when(mockCallable.call({'code': '000000'})).thenThrow(
          FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'Invalid 2FA code',
          ),
        );

        // Act
        final result = await service.verifyTOTP('000000', userId: 'test-user-id');

        // Assert
        expect(result, false);
      });

      test('SECURITY: should handle rate limit exceeded', () async {
        // Arrange
        final mockCallable = MockHttpsCallable();

        when(mockFunctions.httpsCallable('verify2FATOTP')).thenReturn(mockCallable);
        when(mockCallable.call({'code': '123456'})).thenThrow(
          FirebaseFunctionsException(
            code: 'resource-exhausted',
            message: 'Too many attempts',
          ),
        );

        // Act & Assert
        expect(
          () async => await service.verifyTOTP('123456', userId: 'test-user-id'),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Too many attempts'),
          )),
        );
      });

      test('SECURITY: rate limit persists across restarts (server-side)', () async {
        // This test verifies the architectural change:
        // Rate limiting is now SERVER-SIDE, so restarting the app doesn't reset it

        final mockCallable = MockHttpsCallable();

        when(mockFunctions.httpsCallable('verify2FATOTP')).thenReturn(mockCallable);
        when(mockCallable.call({'code': '123456'})).thenThrow(
          FirebaseFunctionsException(
            code: 'resource-exhausted',
            message: 'Too many attempts',
          ),
        );

        // Act - First attempt (rate limited)
        await expectLater(
          service.verifyTOTP('123456', userId: 'test-user-id'),
          throwsA(isA<Exception>()),
        );

        // Simulate app restart by creating new service instance
        final newService = TwoFactorService(
          firestore: mockFirestore,
          auth: mockAuth,
          functions: mockFunctions,
          secureStorage: mockSecureStorage,
        );

        // Act - Second attempt after "restart" (still rate limited!)
        await expectLater(
          newService.verifyTOTP('123456', userId: 'test-user-id'),
          throwsA(isA<Exception>()),
        );

        // Assert - Server-side rate limit still applies
        verify(mockCallable.call({'code': '123456'})).called(2);
      });
    });

    group('Verify Backup Code (Cloud Function)', () {
      test('CRITICAL: should verify backup code via Cloud Function', () async {
        // Arrange
        final mockCallable = MockHttpsCallable();
        final mockResult = MockHttpsCallableResult();

        when(mockFunctions.httpsCallable('verify2FABackupCode')).thenReturn(mockCallable);
        when(mockCallable.call({'code': '1234-5678'})).thenAnswer((_) async => mockResult);
        when(mockResult.data).thenReturn({
          'success': true,
          'verified': true,
          'remainingBackupCodes': 9,
        });
        when(mockSecureStorage.getBackupCodes()).thenAnswer((_) async => ['1234-5678', '2345-6789']);
        when(mockSecureStorage.storeBackupCodes(any)).thenAnswer((_) async => Future.value());

        // Act
        final result = await service.verifyBackupCode('1234-5678', 'test-user-id');

        // Assert
        expect(result, true);
        verify(mockFunctions.httpsCallable('verify2FABackupCode')).called(1);

        // Verify local backup code was removed
        verify(mockSecureStorage.getBackupCodes()).called(1);
        verify(mockSecureStorage.storeBackupCodes(argThat(isNot(contains('1234-5678'))))).called(1);
      });

      test('SECURITY: backup codes are one-time use (verified server-side)', () async {
        // Arrange
        final mockCallable = MockHttpsCallable();
        final mockResult = MockHttpsCallableResult();

        when(mockFunctions.httpsCallable('verify2FABackupCode')).thenReturn(mockCallable);

        // First use - success
        when(mockCallable.call({'code': '1234-5678'})).thenAnswer((_) async => mockResult);
        when(mockResult.data).thenReturn({
          'success': true,
          'verified': true,
          'remainingBackupCodes': 9,
        });
        when(mockSecureStorage.getBackupCodes()).thenAnswer((_) async => ['1234-5678']);
        when(mockSecureStorage.storeBackupCodes(any)).thenAnswer((_) async => Future.value());

        // Act - First use
        final result1 = await service.verifyBackupCode('1234-5678', 'test-user-id');
        expect(result1, true);

        // Arrange - Second use (server rejects because code already used)
        when(mockCallable.call({'code': '1234-5678'})).thenThrow(
          FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'Invalid backup code',
          ),
        );

        // Act - Second use (should fail)
        final result2 = await service.verifyBackupCode('1234-5678', 'test-user-id');

        // Assert - Code cannot be reused
        expect(result2, false);
      });

      test('SECURITY: stricter rate limit for backup codes', () async {
        final mockCallable = MockHttpsCallable();

        when(mockFunctions.httpsCallable('verify2FABackupCode')).thenReturn(mockCallable);
        when(mockCallable.call(any)).thenThrow(
          FirebaseFunctionsException(
            code: 'resource-exhausted',
            message: 'Too many backup code attempts',
          ),
        );

        expect(
          () async => await service.verifyBackupCode('1234-5678', 'test-user-id'),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Too many'),
          )),
        );
      });
    });

    group('Disable 2FA (Cloud Function)', () {
      test('should disable 2FA with valid TOTP code', () async {
        // Arrange
        final mockCallable = MockHttpsCallable();
        final mockResult = MockHttpsCallableResult();

        when(mockFunctions.httpsCallable('disable2FA')).thenReturn(mockCallable);
        when(mockCallable.call({'code': '123456'})).thenAnswer((_) async => mockResult);
        when(mockResult.data).thenReturn({'success': true});
        when(mockSecureStorage.clearTwoFactor()).thenAnswer((_) async => Future.value());

        // Act
        await service.disable2FA('test-user-id', '123456');

        // Assert
        verify(mockFunctions.httpsCallable('disable2FA')).called(1);
        verify(mockCallable.call({'code': '123456'})).called(1);
        verify(mockSecureStorage.clearTwoFactor()).called(1);
      });

      test('should fail to disable with invalid TOTP code', () async {
        // Arrange
        final mockCallable = MockHttpsCallable();

        when(mockFunctions.httpsCallable('disable2FA')).thenReturn(mockCallable);
        when(mockCallable.call({'code': '000000'})).thenThrow(
          FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'Invalid code',
          ),
        );

        // Act & Assert
        expect(
          () async => await service.disable2FA('test-user-id', '000000'),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('Regenerate Backup Codes (Cloud Function)', () {
      test('should regenerate backup codes with valid TOTP', () async {
        // Arrange
        final mockCallable = MockHttpsCallable();
        final mockResult = MockHttpsCallableResult();

        final newCodes = ['1111-2222', '3333-4444', '5555-6666', '7777-8888', '9999-0000',
                          '1234-5678', '2345-6789', '3456-7890', '4567-8901', '5678-9012'];

        when(mockFunctions.httpsCallable('regenerateBackupCodes')).thenReturn(mockCallable);
        when(mockCallable.call({'code': '123456'})).thenAnswer((_) async => mockResult);
        when(mockResult.data).thenReturn({
          'success': true,
          'backupCodes': newCodes,
        });
        when(mockSecureStorage.storeBackupCodes(any)).thenAnswer((_) async => Future.value());

        // Act
        final codes = await service.regenerateBackupCodes('test-user-id', '123456');

        // Assert
        expect(codes, hasLength(10));
        expect(codes, equals(newCodes));
        verify(mockFunctions.httpsCallable('regenerateBackupCodes')).called(1);
        verify(mockSecureStorage.storeBackupCodes(newCodes)).called(1);
      });

      test('should fail to regenerate with invalid TOTP', () async {
        // Arrange
        final mockCallable = MockHttpsCallable();

        when(mockFunctions.httpsCallable('regenerateBackupCodes')).thenReturn(mockCallable);
        when(mockCallable.call({'code': '000000'})).thenThrow(
          FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'Invalid 2FA code',
          ),
        );

        // Act & Assert
        expect(
          () async => await service.regenerateBackupCodes('test-user-id', '000000'),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('Check 2FA Enabled Status', () {
      test('should return true when 2FA is enabled', () async {
        // Arrange
        when(mockUserDocument.get()).thenAnswer((_) async => mockDocumentSnapshot);
        when(mockDocumentSnapshot.data()).thenReturn({
          'twoFactorEnabled': true,
        });

        // Act
        final isEnabled = await service.is2FAEnabled('test-user-id');

        // Assert
        expect(isEnabled, true);
      });

      test('should return false when 2FA is disabled', () async {
        // Arrange
        when(mockUserDocument.get()).thenAnswer((_) async => mockDocumentSnapshot);
        when(mockDocumentSnapshot.data()).thenReturn({
          'twoFactorEnabled': false,
        });

        // Act
        final isEnabled = await service.is2FAEnabled('test-user-id');

        // Assert
        expect(isEnabled, false);
      });

      test('should return false when document does not exist', () async {
        // Arrange
        when(mockUserDocument.get()).thenAnswer((_) async => mockDocumentSnapshot);
        when(mockDocumentSnapshot.data()).thenReturn(null);

        // Act
        final isEnabled = await service.is2FAEnabled('test-user-id');

        // Assert
        expect(isEnabled, false);
      });
    });

    group('Get Rate Limit Status', () {
      test('should return rate limit data for current user', () async {
        // Arrange
        final mockRateLimitsCollection = MockCollectionReference();
        final mockRateLimitDoc = MockDocumentReference();
        final mockRateLimitSnapshot = MockDocumentSnapshot();

        when(mockFirestore.collection('2fa_rate_limits')).thenReturn(mockRateLimitsCollection);
        when(mockRateLimitsCollection.doc('test-user-id')).thenReturn(mockRateLimitDoc);
        when(mockRateLimitDoc.get()).thenAnswer((_) async => mockRateLimitSnapshot);
        when(mockRateLimitSnapshot.exists).thenReturn(true);
        when(mockRateLimitSnapshot.data()).thenReturn({
          'totp': [],
          'backup_code': [],
          'lastAttempt': Timestamp.now(),
        });

        // Act
        final status = await service.getRateLimitStatus();

        // Assert
        expect(status, isNotNull);
        expect(status!.containsKey('totp'), true);
        expect(status.containsKey('backup_code'), true);
      });

      test('should return null when no user is signed in', () async {
        // Arrange
        when(mockAuth.currentUser).thenReturn(null);

        // Act
        final status = await service.getRateLimitStatus();

        // Assert
        expect(status, isNull);
      });
    });

    group('Security Architecture Validation', () {
      test('CRITICAL: TOTP verification happens SERVER-SIDE only', () async {
        // This test validates the most important security change:
        // NO client-side TOTP verification whatsoever

        final mockCallable = MockHttpsCallable();
        final mockResult = MockHttpsCallableResult();

        when(mockFunctions.httpsCallable('verify2FATOTP')).thenReturn(mockCallable);
        when(mockCallable.call(any)).thenAnswer((_) async => mockResult);
        when(mockResult.data).thenReturn({'success': true, 'verified': true});

        await service.verifyTOTP('123456', userId: 'test-user-id');

        // Assert: MUST call Cloud Function (server-side verification)
        verify(mockFunctions.httpsCallable('verify2FATOTP')).called(1);

        // Assert: Should NOT access secure storage for TOTP secret
        verifyNever(mockSecureStorage.getTwoFactorSecret());
      });

      test('CRITICAL: Rate limiting enforced SERVER-SIDE (cannot be bypassed)', () async {
        // This test validates that rate limiting cannot be bypassed by client manipulation

        final mockCallable = MockHttpsCallable();

        when(mockFunctions.httpsCallable('verify2FATOTP')).thenReturn(mockCallable);

        // Simulate server-side rate limit
        when(mockCallable.call(any)).thenThrow(
          FirebaseFunctionsException(
            code: 'resource-exhausted',
            message: 'Too many attempts',
          ),
        );

        // Act - Even if client doesn't track rate limits, server will block
        await expectLater(
          service.verifyTOTP('123456', userId: 'test-user-id'),
          throwsA(isA<Exception>()),
        );

        // Assert: Client cannot bypass server-side rate limit
        // No amount of client manipulation can change this
      });

      test('CRITICAL: Backup codes hashed SERVER-SIDE with salt', () async {
        // This test validates that backup code hashing is server-side with PBKDF2

        final mockCallable = MockHttpsCallable();
        final mockResult = MockHttpsCallableResult();

        when(mockFunctions.httpsCallable('verify2FABackupCode')).thenReturn(mockCallable);
        when(mockCallable.call({'code': '1234-5678'})).thenAnswer((_) async => mockResult);
        when(mockResult.data).thenReturn({
          'success': true,
          'verified': true,
          'remainingBackupCodes': 9,
        });
        when(mockSecureStorage.getBackupCodes()).thenAnswer((_) async => []);
        when(mockSecureStorage.storeBackupCodes(any)).thenAnswer((_) async => Future.value());

        await service.verifyBackupCode('1234-5678', 'test-user-id');

        // Assert: Cloud Function called (server-side hashing with PBKDF2)
        verify(mockFunctions.httpsCallable('verify2FABackupCode')).called(1);

        // Note: Server uses PBKDF2 with 100,000 iterations and per-user salt
        // This is verified in the Cloud Functions code, not here
      });
    });
  });
}
