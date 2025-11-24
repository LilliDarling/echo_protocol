import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:echo_protocol/services/partner_service.dart';
import 'package:echo_protocol/services/encryption.dart';
import 'package:echo_protocol/services/secure_storage.dart';

@GenerateMocks([
  FirebaseAuth,
  FirebaseFirestore,
  User,
  EncryptionService,
  SecureStorageService,
  Transaction,
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
    late MockEncryptionService mockEncryption;
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
      mockEncryption = MockEncryptionService();
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
        secureStorage: mockSecureStorage,
        encryptionService: mockEncryption,
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
      setUp(() {
        when(mockCollection.doc('user123')).thenReturn(mockUserDoc);
        when(mockUserDoc.get()).thenAnswer((_) async => mockSnapshot);
        when(mockSnapshot.data()).thenReturn({
          'name': 'Test User',
        });
      });

      test('throws when invite code is invalid format', () async {
        expect(
          () => partnerService.acceptInvite('SHORT'),
          throwsA(predicate((e) => e.toString().contains('Invalid'))),
        );
      });

      test('throws when invite does not exist', () async {
        final inviteCode = 'ABCD1234';

        when(mockCollection.doc(inviteCode)).thenReturn(mockInviteDoc);
        when(mockInviteDoc.get()).thenAnswer((_) async => mockSnapshot);
        when(mockSnapshot.exists).thenReturn(false);

        expect(
          () => partnerService.acceptInvite(inviteCode),
          throwsA(predicate((e) => e.toString().contains('Invalid'))),
        );
      });

      test('throws when invite is already used', () async {
        final inviteCode = 'ABCD1234';

        when(mockCollection.doc(inviteCode)).thenReturn(mockInviteDoc);
        when(mockInviteDoc.get()).thenAnswer((_) async => mockSnapshot);
        when(mockSnapshot.exists).thenReturn(true);
        when(mockSnapshot.data()).thenReturn({
          'used': true,
          'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 1))),
        });

        expect(
          () => partnerService.acceptInvite(inviteCode),
          throwsA(predicate((e) => e.toString().contains('no longer valid'))),
        );
      });

      test('throws when invite has expired', () async {
        final inviteCode = 'ABCD1234';
        final expiredTime = DateTime.now().subtract(const Duration(hours: 1));

        when(mockCollection.doc(inviteCode)).thenReturn(mockInviteDoc);
        when(mockInviteDoc.get()).thenAnswer((_) async => mockSnapshot);
        when(mockSnapshot.exists).thenReturn(true);
        when(mockSnapshot.data()).thenReturn({
          'used': false,
          'expiresAt': Timestamp.fromDate(expiredTime),
        });

        expect(
          () => partnerService.acceptInvite(inviteCode),
          throwsA(predicate((e) => e.toString().contains('no longer valid'))),
        );
      });

      test('throws when trying to link with self', () async {
        final inviteCode = 'ABCD1234';
        final expiresAt = DateTime.now().add(const Duration(hours: 1));

        when(mockCollection.doc(inviteCode)).thenReturn(mockInviteDoc);
        when(mockInviteDoc.get()).thenAnswer((_) async => mockSnapshot);
        when(mockSnapshot.exists).thenReturn(true);
        when(mockSnapshot.data()).thenReturn({
          'userId': 'user123',
          'used': false,
          'expiresAt': Timestamp.fromDate(expiresAt),
        });

        expect(
          () => partnerService.acceptInvite(inviteCode),
          throwsA(predicate((e) => e.toString().contains('Invalid'))),
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
