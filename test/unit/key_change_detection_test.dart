import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:echo_protocol/services/partner.dart';
import 'package:echo_protocol/services/secure_storage.dart';
import 'package:echo_protocol/services/crypto/protocol_service.dart';
import 'package:echo_protocol/models/key_change_event.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

@GenerateMocks([
  FirebaseFirestore,
  FirebaseAuth,
  FirebaseFunctions,
  SecureStorageService,
  ProtocolService,
  User,
])
import 'key_change_detection_test.mocks.dart';

void main() {
  late PartnerService partnerService;
  late MockFirebaseFirestore mockFirestore;
  late MockFirebaseAuth mockAuth;
  late MockFirebaseFunctions mockFunctions;
  late MockSecureStorageService mockSecureStorage;
  late MockProtocolService mockProtocol;
  late MockUser mockUser;

  setUp(() {
    mockFirestore = MockFirebaseFirestore();
    mockAuth = MockFirebaseAuth();
    mockFunctions = MockFirebaseFunctions();
    mockSecureStorage = MockSecureStorageService();
    mockProtocol = MockProtocolService();
    mockUser = MockUser();

    when(mockAuth.currentUser).thenReturn(mockUser);
    when(mockUser.uid).thenReturn('test-user-id');

    partnerService = PartnerService(
      firestore: mockFirestore,
      auth: mockAuth,
      functions: mockFunctions,
      secureStorage: mockSecureStorage,
      protocolService: mockProtocol,
    );
  });

  group('computeFingerprint', () {
    test('generates consistent fingerprint for same key', () {
      const publicKey = 'test-public-key-123';

      final fingerprint1 = partnerService.computeFingerprint(publicKey);
      final fingerprint2 = partnerService.computeFingerprint(publicKey);

      expect(fingerprint1, equals(fingerprint2));
    });

    test('generates different fingerprints for different keys', () {
      const key1 = 'public-key-one';
      const key2 = 'public-key-two';

      final fingerprint1 = partnerService.computeFingerprint(key1);
      final fingerprint2 = partnerService.computeFingerprint(key2);

      expect(fingerprint1, isNot(equals(fingerprint2)));
    });

    test('fingerprint format is 8 groups of 4 hex chars', () {
      const publicKey = 'any-public-key';

      final fingerprint = partnerService.computeFingerprint(publicKey);
      final parts = fingerprint.split(' ');

      expect(parts.length, equals(8));
      for (final part in parts) {
        expect(part.length, equals(4));
        expect(RegExp(r'^[0-9A-F]+$').hasMatch(part), isTrue);
      }
    });
  });

  group('checkPartnerKeyChange', () {
    test('returns firstKey when no trusted fingerprint exists', () async {
      const publicKey = 'new-partner-key';

      when(mockSecureStorage.getTrustedFingerprint())
          .thenAnswer((_) async => null);

      final result = await partnerService.checkPartnerKeyChange(publicKey);

      expect(result.status, equals(KeyChangeStatus.firstKey));
      expect(result.previousFingerprint, isNull);
      expect(result.currentFingerprint, isNotEmpty);
    });

    test('returns noChange when fingerprint matches', () async {
      const publicKey = 'existing-partner-key';
      final expectedFingerprint = partnerService.computeFingerprint(publicKey);

      when(mockSecureStorage.getTrustedFingerprint())
          .thenAnswer((_) async => expectedFingerprint);

      final result = await partnerService.checkPartnerKeyChange(publicKey);

      expect(result.status, equals(KeyChangeStatus.noChange));
      expect(result.previousFingerprint, equals(expectedFingerprint));
      expect(result.currentFingerprint, equals(expectedFingerprint));
    });

    test('returns changed when fingerprint differs', () async {
      const oldKey = 'old-partner-key';
      const newKey = 'new-partner-key';
      final oldFingerprint = partnerService.computeFingerprint(oldKey);
      final newFingerprint = partnerService.computeFingerprint(newKey);

      when(mockSecureStorage.getTrustedFingerprint())
          .thenAnswer((_) async => oldFingerprint);

      final result = await partnerService.checkPartnerKeyChange(newKey);

      expect(result.status, equals(KeyChangeStatus.changed));
      expect(result.previousFingerprint, equals(oldFingerprint));
      expect(result.currentFingerprint, equals(newFingerprint));
    });
  });

  group('trustCurrentKey', () {
    test('stores fingerprint in secure storage', () async {
      const publicKey = 'partner-public-key';
      final expectedFingerprint = partnerService.computeFingerprint(publicKey);

      when(mockSecureStorage.storeTrustedFingerprint(any))
          .thenAnswer((_) async {});

      await partnerService.trustCurrentKey(publicKey);

      verify(mockSecureStorage.storeTrustedFingerprint(expectedFingerprint)).called(1);
    });
  });

  group('KeyChangeEvent', () {
    test('toFirestore and fromFirestore are consistent', () {
      final original = KeyChangeEvent(
        id: 'test-id',
        visibleId: 'ABC12345',
        detectedAt: DateTime(2024, 1, 15, 10, 30),
        previousFingerprint: 'OLD1 OLD2 OLD3 OLD4 OLD5 OLD6 OLD7 OLD8',
        newFingerprint: 'NEW1 NEW2 NEW3 NEW4 NEW5 NEW6 NEW7 NEW8',
        acknowledged: true,
        acknowledgedAt: DateTime(2024, 1, 15, 11, 0),
      );

      final firestoreData = original.toFirestore();

      expect(firestoreData['visibleId'], equals('ABC12345'));
      expect(firestoreData['previousFingerprint'], equals(original.previousFingerprint));
      expect(firestoreData['newFingerprint'], equals(original.newFingerprint));
      expect(firestoreData['acknowledged'], isTrue);
    });

    test('copyWith preserves unmodified fields', () {
      final original = KeyChangeEvent(
        id: 'test-id',
        visibleId: 'ABC12345',
        detectedAt: DateTime(2024, 1, 15),
        previousFingerprint: 'OLD',
        newFingerprint: 'NEW',
      );

      final updated = original.copyWith(acknowledged: true);

      expect(updated.id, equals(original.id));
      expect(updated.visibleId, equals(original.visibleId));
      expect(updated.previousFingerprint, equals(original.previousFingerprint));
      expect(updated.newFingerprint, equals(original.newFingerprint));
      expect(updated.acknowledged, isTrue);
    });
  });

  group('KeyChangeResult', () {
    test('firstKey status indicates new partner', () {
      final result = KeyChangeResult(
        status: KeyChangeStatus.firstKey,
        currentFingerprint: 'SOME FINGERPRINT',
      );

      expect(result.status, equals(KeyChangeStatus.firstKey));
      expect(result.previousFingerprint, isNull);
    });

    test('changed status includes both fingerprints', () {
      final result = KeyChangeResult(
        status: KeyChangeStatus.changed,
        previousFingerprint: 'OLD',
        currentFingerprint: 'NEW',
      );

      expect(result.status, equals(KeyChangeStatus.changed));
      expect(result.previousFingerprint, isNotNull);
      expect(result.currentFingerprint, isNotNull);
      expect(result.previousFingerprint, isNot(equals(result.currentFingerprint)));
    });
  });
}
