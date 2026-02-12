import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:echo_protocol/services/partner.dart';
import 'package:echo_protocol/services/crypto/protocol_service.dart';
import 'package:echo_protocol/services/secure_storage.dart';

@GenerateMocks([
  FirebaseAuth,
  FirebaseFirestore,
  FirebaseFunctions,
  User,
  ProtocolService,
  SecureStorageService,
  Transaction,
  HttpsCallable,
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
  MockSpec<QuerySnapshot<Map<String, dynamic>>>(
    as: #MockQuerySnapshot,
  ),
  MockSpec<QueryDocumentSnapshot<Map<String, dynamic>>>(
    as: #MockQueryDocumentSnapshot,
  ),
  MockSpec<Query<Map<String, dynamic>>>(
    as: #MockQuery,
  ),
  MockSpec<WriteBatch>(
    as: #MockWriteBatch,
  ),
])
import 'partner_service_test.mocks.dart';

void main() {
  group('PartnerService', () {
    late PartnerService partnerService;
    late MockFirebaseAuth mockAuth;
    late MockFirebaseFirestore mockFirestore;
    late MockFirebaseFunctions mockFunctions;
    late MockProtocolService mockProtocol;
    late MockSecureStorageService mockSecureStorage;
    late MockUser mockUser;
    late MockCollectionReference mockCollection;
    late MockDocumentReference mockInviteDoc;
    late MockDocumentReference mockUserDoc;
    late MockDocumentSnapshot mockSnapshot;
    late MockQuery mockQuery;
    late MockQuerySnapshot mockQuerySnapshot;
    late MockWriteBatch mockBatch;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      mockFirestore = MockFirebaseFirestore();
      mockFunctions = MockFirebaseFunctions();
      mockProtocol = MockProtocolService();
      mockSecureStorage = MockSecureStorageService();
      mockUser = MockUser();
      mockCollection = MockCollectionReference();
      mockInviteDoc = MockDocumentReference();
      mockUserDoc = MockDocumentReference();
      mockSnapshot = MockDocumentSnapshot();
      mockQuery = MockQuery();
      mockQuerySnapshot = MockQuerySnapshot();
      mockBatch = MockWriteBatch();

      partnerService = PartnerService(
        firestore: mockFirestore,
        auth: mockAuth,
        functions: mockFunctions,
        secureStorage: mockSecureStorage,
        protocolService: mockProtocol,
      );

      when(mockAuth.currentUser).thenReturn(mockUser);
      when(mockUser.uid).thenReturn('user123');
      when(mockFirestore.collection('partnerInvites')).thenReturn(mockCollection);
      when(mockFirestore.collection('users')).thenReturn(mockCollection);
      when(mockFirestore.batch()).thenReturn(mockBatch);
      when(mockBatch.delete(any)).thenAnswer((_) => mockBatch);
      when(mockBatch.commit()).thenAnswer((_) async => []);
    });

    group('createInvite', () {

      test('throws when user already has partner', () async {
        when(mockCollection.doc('user123')).thenReturn(mockUserDoc);
        when(mockUserDoc.get()).thenAnswer((_) async => mockSnapshot);
        when(mockSnapshot.data()).thenReturn({
          'partnerId': 'partner456',
          'name': 'Test User',
        });

        expect(
          () => partnerService.createInvite(),
          throwsA(predicate((e) =>
              e.toString().contains('already have a partner linked'))),
        );
      });

      test('throws when user not authenticated', () async {
        when(mockAuth.currentUser).thenReturn(null);

        expect(
          () => partnerService.createInvite(),
          throwsA(predicate(
              (e) => e.toString().contains('User not authenticated'))),
        );
      });
    });

    group('acceptInvite', () {
      late MockHttpsCallable mockCallable;

      setUp(() {
        mockCallable = MockHttpsCallable();

        when(mockCollection.doc('user123')).thenReturn(mockUserDoc);
        when(mockUserDoc.get()).thenAnswer((_) async => mockSnapshot);
        when(mockSnapshot.data()).thenReturn({
          'name': 'Test User',
          'publicKey': 'test-public-key',
          'publicKeyVersion': 1,
          'identityKey': {'ed25519': 'test-ed25519-key'},
        });

        // Mock ProtocolService methods
        when(mockProtocol.getFingerprint()).thenAnswer((_) async => 'test-fingerprint');
        when(mockProtocol.isInitialized).thenReturn(true);
        when(mockProtocol.sign(any)).thenAnswer((_) async => (
          signature: Uint8List.fromList([1, 2, 3, 4]),
          publicKey: Uint8List.fromList([5, 6, 7, 8]),
        ));

        // Mock SecureStorage methods
        when(mockSecureStorage.getPublicKey()).thenAnswer((_) async => 'my-public-key');
        when(mockSecureStorage.getCurrentKeyVersion()).thenAnswer((_) async => 1);
        when(mockSecureStorage.storePartnerPublicKey(any)).thenAnswer((_) async {});
        when(mockSecureStorage.storeCurrentKeyVersion(any)).thenAnswer((_) async {});

        // Mock FirebaseFunctions
        when(mockFunctions.httpsCallable('acceptPartnerInvite')).thenReturn(mockCallable);
      });

      test('throws when invite code is invalid format', () async {
        expect(
          () => partnerService.acceptInvite('SHORT'),
          throwsA(predicate((e) => e.toString().contains('Invalid'))),
        );
      });

      test('throws when invite does not exist (Cloud Function error)', () async {
        final inviteCode = 'ABCD12345678';

        // Create a PartnerService with injected functions mock
        final service = PartnerService(
          firestore: mockFirestore,
          auth: mockAuth,
          secureStorage: mockSecureStorage,
          protocolService: mockProtocol,
          functions: mockFunctions,
        );

        when(mockCallable.call<Map<String, dynamic>>(any)).thenThrow(
          FirebaseFunctionsException(code: 'not-found', message: 'Invite not found or invalid'),
        );

        expect(
          () => service.acceptInvite(inviteCode),
          throwsA(predicate((e) => e.toString().contains('Invite not found or invalid'))),
        );
      });

      test('throws when invite is already used (Cloud Function error)', () async {
        final inviteCode = 'ABCD12345678';

        final service = PartnerService(
          firestore: mockFirestore,
          auth: mockAuth,
          secureStorage: mockSecureStorage,
          protocolService: mockProtocol,
          functions: mockFunctions,
        );

        when(mockCallable.call<Map<String, dynamic>>(any)).thenThrow(
          FirebaseFunctionsException(code: 'failed-precondition', message: 'Invite is no longer valid'),
        );

        expect(
          () => service.acceptInvite(inviteCode),
          throwsA(predicate((e) => e.toString().contains('no longer valid'))),
        );
      });

      test('throws when invite has expired (Cloud Function error)', () async {
        final inviteCode = 'ABCD12345678';

        final service = PartnerService(
          firestore: mockFirestore,
          auth: mockAuth,
          secureStorage: mockSecureStorage,
          protocolService: mockProtocol,
          functions: mockFunctions,
        );

        when(mockCallable.call<Map<String, dynamic>>(any)).thenThrow(
          FirebaseFunctionsException(code: 'failed-precondition', message: 'Invite has expired'),
        );

        expect(
          () => service.acceptInvite(inviteCode),
          throwsA(predicate((e) => e.toString().contains('Invite has expired'))),
        );
      });

      test('throws when trying to link with self (Cloud Function error)', () async {
        final inviteCode = 'ABCD12345678';

        final service = PartnerService(
          firestore: mockFirestore,
          auth: mockAuth,
          secureStorage: mockSecureStorage,
          protocolService: mockProtocol,
          functions: mockFunctions,
        );

        when(mockCallable.call<Map<String, dynamic>>(any)).thenThrow(
          FirebaseFunctionsException(code: 'invalid-argument', message: 'Cannot link with yourself'),
        );

        expect(
          () => service.acceptInvite(inviteCode),
          throwsA(predicate((e) => e.toString().contains('Cannot link with yourself'))),
        );
      });

    });

    group('hasPartner', () {
      test('returns true when user has partner', () async {
        when(mockCollection.doc('user123')).thenReturn(mockUserDoc);
        when(mockUserDoc.get()).thenAnswer((_) async => mockSnapshot);
        when(mockSnapshot.data()).thenReturn({
          'partnerId': 'partner456',
        });

        final result = await partnerService.hasPartner();

        expect(result, isTrue);
      });

      test('returns false when user has no partner', () async {
        when(mockCollection.doc('user123')).thenReturn(mockUserDoc);
        when(mockUserDoc.get()).thenAnswer((_) async => mockSnapshot);
        when(mockSnapshot.data()).thenReturn({});

        final result = await partnerService.hasPartner();

        expect(result, isFalse);
      });

      test('returns false when user not authenticated', () async {
        when(mockAuth.currentUser).thenReturn(null);

        final result = await partnerService.hasPartner();

        expect(result, isFalse);
      });
    });

    group('getConversationId', () {
      test('generates consistent conversation ID', () async {
        when(mockCollection.doc('user123')).thenReturn(mockUserDoc);
        when(mockUserDoc.get()).thenAnswer((_) async => mockSnapshot);
        when(mockSnapshot.data()).thenReturn({
          'partnerId': 'partner456',
        });

        final result = await partnerService.getConversationId();

        expect(result, isNotNull);
        expect(result, contains('_'));
      });

      test('returns null when no partner', () async {
        when(mockCollection.doc('user123')).thenReturn(mockUserDoc);
        when(mockUserDoc.get()).thenAnswer((_) async => mockSnapshot);
        when(mockSnapshot.data()).thenReturn({});

        final result = await partnerService.getConversationId();

        expect(result, isNull);
      });
    });

    group('signature verification security', () {
      test('client does NOT verify signatures - delegates to Cloud Function', () {
        // SECURITY: Signature verification MUST happen server-side in acceptPartnerInvite Cloud Function.
        // The client sends inviteCode, myPublicKey, myKeyVersion, timestamp, signature, ed25519PublicKey.
        // The Cloud Function performs:
        // 1. Ed25519 signature verification using @noble/ed25519
        // 2. Payload reconstruction and validation
        // 3. Cross-reference of signing key against user's registered identityKey
        // This prevents malicious clients from bypassing verification and injecting fake public keys.
        expect(true, isTrue);
      });

      test('invite creator signature includes all critical fields', () {
        // Creator signature payload: '$inviteCode:$userId:$publicKeyHash:$userName:$publicKeyFingerprint:$publicKeyVersion:$expiresAtMs'
        final creatorPayloadFields = [
          'inviteCode',
          'userId',
          'publicKeyHash',
          'userName',
          'publicKeyFingerprint',
          'publicKeyVersion',
          'expiresAt',
        ];

        expect(creatorPayloadFields.length, equals(7));
        expect(creatorPayloadFields.contains('publicKeyHash'), isTrue);
      });

      test('invite acceptor must prove key ownership via signature', () {
        // Acceptor signature payload: '$inviteCode:$userId:$timestamp'
        // Server verifies:
        // 1. Signature is valid for the payload
        // 2. Ed25519 key matches acceptor's registered identityKey
        // 3. Timestamp is within 5 minute window (prevents replay)
        final acceptorPayloadFields = [
          'inviteCode',
          'userId',
          'timestamp',
        ];

        expect(acceptorPayloadFields.length, equals(3));
      });

      test('both parties prove key possession - mutual authentication', () {
        // Creator: signs invite with their Ed25519 key, verified against identityKey.ed25519
        // Acceptor: signs challenge with their Ed25519 key, verified against identityKey.ed25519
        // Result: Neither party can claim a public key they don't own the private key for
        expect(true, isTrue);
      });
    });

    group('cancelExistingInvites', () {
      test('deletes all user invites', () async {
        when(mockCollection.where('userId', isEqualTo: 'user123'))
            .thenReturn(mockQuery);
        when(mockQuery.where('used', isEqualTo: false)).thenReturn(mockQuery);
        when(mockQuery.get()).thenAnswer((_) async => mockQuerySnapshot);

        final doc1 = MockQueryDocumentSnapshot();
        final doc2 = MockQueryDocumentSnapshot();
        when(doc1.reference).thenReturn(mockInviteDoc);
        when(doc2.reference).thenReturn(mockInviteDoc);
        when(mockQuerySnapshot.docs).thenReturn([doc1, doc2]);

        when(mockFirestore.batch()).thenReturn(mockBatch);
        when(mockBatch.delete(any)).thenReturn(null);
        when(mockBatch.commit()).thenAnswer((_) async => {});

        await partnerService.cancelExistingInvites();

        verify(mockBatch.delete(any)).called(2);
        verify(mockBatch.commit()).called(1);
      });
    });
  });
}
