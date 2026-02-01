import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:echo_protocol/services/auto_delete.dart';

@GenerateMocks([
  FirebaseFirestore,
  FirebaseStorage,
  Reference,
], customMocks: [
  MockSpec<CollectionReference<Map<String, dynamic>>>(
    as: #MockCollectionReference,
  ),
  MockSpec<DocumentReference<Map<String, dynamic>>>(
    as: #MockDocumentReference,
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
import 'auto_delete_service_test.mocks.dart';

void main() {
  group('AutoDeleteService', () {
    late AutoDeleteService service;
    late MockFirebaseFirestore mockFirestore;
    late MockFirebaseStorage mockStorage;
    late MockCollectionReference mockConversationsCollection;
    late MockDocumentReference mockConversationDoc;
    late MockCollectionReference mockMessagesCollection;
    late MockQuery mockQuery;
    late MockWriteBatch mockBatch;
    late MockReference mockStorageRef;

    setUp(() {
      mockFirestore = MockFirebaseFirestore();
      mockStorage = MockFirebaseStorage();
      mockConversationsCollection = MockCollectionReference();
      mockConversationDoc = MockDocumentReference();
      mockMessagesCollection = MockCollectionReference();
      mockQuery = MockQuery();
      mockBatch = MockWriteBatch();
      mockStorageRef = MockReference();

      service = AutoDeleteService(
        firestore: mockFirestore,
        storage: mockStorage,
      );

      when(mockFirestore.collection('conversations')).thenReturn(mockConversationsCollection);
      when(mockConversationsCollection.doc(any)).thenReturn(mockConversationDoc);
      when(mockConversationDoc.collection('messages')).thenReturn(mockMessagesCollection);
      when(mockFirestore.batch()).thenReturn(mockBatch);
      when(mockBatch.delete(any)).thenReturn(null);
      when(mockBatch.commit()).thenAnswer((_) async => []);
      when(mockStorage.refFromURL(any)).thenReturn(mockStorageRef);
      when(mockStorageRef.delete()).thenAnswer((_) async {});
    });

    group('autoDeleteDays validation', () {
      test('returns 0 when autoDeleteDays is 0 (disabled)', () async {
        final result = await service.deleteOldMessages(
          conversationId: 'conv123',
          userId: 'user123',
          autoDeleteDays: 0,
        );

        expect(result, equals(0));
        verifyNever(mockFirestore.collection(any));
      });

      test('returns 0 when autoDeleteDays is negative', () async {
        final result = await service.deleteOldMessages(
          conversationId: 'conv123',
          userId: 'user123',
          autoDeleteDays: -1,
        );

        expect(result, equals(0));
        verifyNever(mockFirestore.collection(any));
      });
    });

    group('message deletion', () {
      test('deletes messages older than cutoff date', () async {
        final oldTimestamp = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 10)),
        );

        final mockDoc = MockQueryDocumentSnapshot();
        final mockDocRef = MockDocumentReference();
        final mockQuerySnapshot = MockQuerySnapshot();
        final mockEmptySnapshot = MockQuerySnapshot();

        when(mockMessagesCollection.where('timestamp', isLessThan: anyNamed('isLessThan')))
            .thenReturn(mockQuery);
        when(mockQuery.limit(any)).thenReturn(mockQuery);

        var callCount = 0;
        when(mockQuery.get()).thenAnswer((_) async {
          callCount++;
          return callCount == 1 ? mockQuerySnapshot : mockEmptySnapshot;
        });

        when(mockQuerySnapshot.docs).thenReturn([mockDoc]);
        when(mockEmptySnapshot.docs).thenReturn([]);
        when(mockDoc.reference).thenReturn(mockDocRef);
        when(mockDoc.data()).thenReturn({
          'timestamp': oldTimestamp,
          'content': 'old message',
        });

        final result = await service.deleteOldMessages(
          conversationId: 'conv123',
          userId: 'user123',
          autoDeleteDays: 7,
        );

        expect(result, equals(1));
        verify(mockBatch.delete(mockDocRef)).called(1);
        verify(mockBatch.commit()).called(1);
      });

      test('does not delete messages when none are older than cutoff', () async {
        final mockEmptySnapshot = MockQuerySnapshot();

        when(mockMessagesCollection.where('timestamp', isLessThan: anyNamed('isLessThan')))
            .thenReturn(mockQuery);
        when(mockQuery.limit(any)).thenReturn(mockQuery);
        when(mockQuery.get()).thenAnswer((_) async => mockEmptySnapshot);
        when(mockEmptySnapshot.docs).thenReturn([]);

        final result = await service.deleteOldMessages(
          conversationId: 'conv123',
          userId: 'user123',
          autoDeleteDays: 7,
        );

        expect(result, equals(0));
        verifyNever(mockBatch.delete(any));
        verifyNever(mockBatch.commit());
      });

      test('deletes multiple old messages in batch', () async {
        final oldTimestamp = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 15)),
        );

        final mockDoc1 = MockQueryDocumentSnapshot();
        final mockDoc2 = MockQueryDocumentSnapshot();
        final mockDoc3 = MockQueryDocumentSnapshot();
        final mockDocRef1 = MockDocumentReference();
        final mockDocRef2 = MockDocumentReference();
        final mockDocRef3 = MockDocumentReference();
        final mockQuerySnapshot = MockQuerySnapshot();
        final mockEmptySnapshot = MockQuerySnapshot();

        when(mockMessagesCollection.where('timestamp', isLessThan: anyNamed('isLessThan')))
            .thenReturn(mockQuery);
        when(mockQuery.limit(any)).thenReturn(mockQuery);

        var callCount = 0;
        when(mockQuery.get()).thenAnswer((_) async {
          callCount++;
          return callCount == 1 ? mockQuerySnapshot : mockEmptySnapshot;
        });

        when(mockQuerySnapshot.docs).thenReturn([mockDoc1, mockDoc2, mockDoc3]);
        when(mockEmptySnapshot.docs).thenReturn([]);
        when(mockDoc1.reference).thenReturn(mockDocRef1);
        when(mockDoc2.reference).thenReturn(mockDocRef2);
        when(mockDoc3.reference).thenReturn(mockDocRef3);
        when(mockDoc1.data()).thenReturn({'timestamp': oldTimestamp});
        when(mockDoc2.data()).thenReturn({'timestamp': oldTimestamp});
        when(mockDoc3.data()).thenReturn({'timestamp': oldTimestamp});

        final result = await service.deleteOldMessages(
          conversationId: 'conv123',
          userId: 'user123',
          autoDeleteDays: 7,
        );

        expect(result, equals(3));
        verify(mockBatch.delete(mockDocRef1)).called(1);
        verify(mockBatch.delete(mockDocRef2)).called(1);
        verify(mockBatch.delete(mockDocRef3)).called(1);
      });
    });

    group('media deletion', () {
      test('deletes associated media files when message has fileUrl', () async {
        final oldTimestamp = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 10)),
        );

        final mockDoc = MockQueryDocumentSnapshot();
        final mockDocRef = MockDocumentReference();
        final mockQuerySnapshot = MockQuerySnapshot();
        final mockEmptySnapshot = MockQuerySnapshot();

        when(mockMessagesCollection.where('timestamp', isLessThan: anyNamed('isLessThan')))
            .thenReturn(mockQuery);
        when(mockQuery.limit(any)).thenReturn(mockQuery);

        var callCount = 0;
        when(mockQuery.get()).thenAnswer((_) async {
          callCount++;
          return callCount == 1 ? mockQuerySnapshot : mockEmptySnapshot;
        });

        when(mockQuerySnapshot.docs).thenReturn([mockDoc]);
        when(mockEmptySnapshot.docs).thenReturn([]);
        when(mockDoc.reference).thenReturn(mockDocRef);
        when(mockDoc.data()).thenReturn({
          'timestamp': oldTimestamp,
          'metadata': {
            'fileUrl': 'gs://bucket/image.jpg',
          },
        });

        await service.deleteOldMessages(
          conversationId: 'conv123',
          userId: 'user123',
          autoDeleteDays: 7,
        );

        verify(mockStorage.refFromURL('gs://bucket/image.jpg')).called(1);
        verify(mockStorageRef.delete()).called(1);
      });

      test('deletes both fileUrl and thumbnailUrl when present', () async {
        final oldTimestamp = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 10)),
        );

        final mockDoc = MockQueryDocumentSnapshot();
        final mockDocRef = MockDocumentReference();
        final mockQuerySnapshot = MockQuerySnapshot();
        final mockEmptySnapshot = MockQuerySnapshot();

        when(mockMessagesCollection.where('timestamp', isLessThan: anyNamed('isLessThan')))
            .thenReturn(mockQuery);
        when(mockQuery.limit(any)).thenReturn(mockQuery);

        var callCount = 0;
        when(mockQuery.get()).thenAnswer((_) async {
          callCount++;
          return callCount == 1 ? mockQuerySnapshot : mockEmptySnapshot;
        });

        when(mockQuerySnapshot.docs).thenReturn([mockDoc]);
        when(mockEmptySnapshot.docs).thenReturn([]);
        when(mockDoc.reference).thenReturn(mockDocRef);
        when(mockDoc.data()).thenReturn({
          'timestamp': oldTimestamp,
          'metadata': {
            'fileUrl': 'gs://bucket/video.mp4',
            'thumbnailUrl': 'gs://bucket/thumb.jpg',
          },
        });

        await service.deleteOldMessages(
          conversationId: 'conv123',
          userId: 'user123',
          autoDeleteDays: 7,
        );

        verify(mockStorage.refFromURL('gs://bucket/video.mp4')).called(1);
        verify(mockStorage.refFromURL('gs://bucket/thumb.jpg')).called(1);
      });

      test('does not attempt to delete empty media URLs', () async {
        final oldTimestamp = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 10)),
        );

        final mockDoc = MockQueryDocumentSnapshot();
        final mockDocRef = MockDocumentReference();
        final mockQuerySnapshot = MockQuerySnapshot();
        final mockEmptySnapshot = MockQuerySnapshot();

        when(mockMessagesCollection.where('timestamp', isLessThan: anyNamed('isLessThan')))
            .thenReturn(mockQuery);
        when(mockQuery.limit(any)).thenReturn(mockQuery);

        var callCount = 0;
        when(mockQuery.get()).thenAnswer((_) async {
          callCount++;
          return callCount == 1 ? mockQuerySnapshot : mockEmptySnapshot;
        });

        when(mockQuerySnapshot.docs).thenReturn([mockDoc]);
        when(mockEmptySnapshot.docs).thenReturn([]);
        when(mockDoc.reference).thenReturn(mockDocRef);
        when(mockDoc.data()).thenReturn({
          'timestamp': oldTimestamp,
          'metadata': {
            'fileUrl': '',
            'thumbnailUrl': '',
          },
        });

        await service.deleteOldMessages(
          conversationId: 'conv123',
          userId: 'user123',
          autoDeleteDays: 7,
        );

        verifyNever(mockStorage.refFromURL(any));
      });

      test('continues deletion even if media delete fails', () async {
        final oldTimestamp = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 10)),
        );

        final mockDoc = MockQueryDocumentSnapshot();
        final mockDocRef = MockDocumentReference();
        final mockQuerySnapshot = MockQuerySnapshot();
        final mockEmptySnapshot = MockQuerySnapshot();

        when(mockMessagesCollection.where('timestamp', isLessThan: anyNamed('isLessThan')))
            .thenReturn(mockQuery);
        when(mockQuery.limit(any)).thenReturn(mockQuery);

        var callCount = 0;
        when(mockQuery.get()).thenAnswer((_) async {
          callCount++;
          return callCount == 1 ? mockQuerySnapshot : mockEmptySnapshot;
        });

        when(mockQuerySnapshot.docs).thenReturn([mockDoc]);
        when(mockEmptySnapshot.docs).thenReturn([]);
        when(mockDoc.reference).thenReturn(mockDocRef);
        when(mockDoc.data()).thenReturn({
          'timestamp': oldTimestamp,
          'metadata': {
            'fileUrl': 'gs://bucket/image.jpg',
          },
        });

        when(mockStorageRef.delete()).thenThrow(Exception('Storage error'));

        final result = await service.deleteOldMessages(
          conversationId: 'conv123',
          userId: 'user123',
          autoDeleteDays: 7,
        );

        expect(result, equals(1));
        verify(mockBatch.delete(mockDocRef)).called(1);
      });
    });

    group('text-only messages', () {
      test('deletes messages without metadata field', () async {
        final oldTimestamp = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 10)),
        );

        final mockDoc = MockQueryDocumentSnapshot();
        final mockDocRef = MockDocumentReference();
        final mockQuerySnapshot = MockQuerySnapshot();
        final mockEmptySnapshot = MockQuerySnapshot();

        when(mockMessagesCollection.where('timestamp', isLessThan: anyNamed('isLessThan')))
            .thenReturn(mockQuery);
        when(mockQuery.limit(any)).thenReturn(mockQuery);

        var callCount = 0;
        when(mockQuery.get()).thenAnswer((_) async {
          callCount++;
          return callCount == 1 ? mockQuerySnapshot : mockEmptySnapshot;
        });

        when(mockQuerySnapshot.docs).thenReturn([mockDoc]);
        when(mockEmptySnapshot.docs).thenReturn([]);
        when(mockDoc.reference).thenReturn(mockDocRef);
        when(mockDoc.data()).thenReturn({
          'timestamp': oldTimestamp,
          'content': 'just text, no media',
        });

        final result = await service.deleteOldMessages(
          conversationId: 'conv123',
          userId: 'user123',
          autoDeleteDays: 7,
        );

        expect(result, equals(1));
        verify(mockBatch.delete(mockDocRef)).called(1);
        verifyNever(mockStorage.refFromURL(any));
      });
    });

    group('cutoff calculation', () {
      test('uses correct cutoff for 7 days', () async {
        final mockEmptySnapshot = MockQuerySnapshot();

        when(mockMessagesCollection.where('timestamp', isLessThan: anyNamed('isLessThan')))
            .thenReturn(mockQuery);
        when(mockQuery.limit(any)).thenReturn(mockQuery);
        when(mockQuery.get()).thenAnswer((_) async => mockEmptySnapshot);
        when(mockEmptySnapshot.docs).thenReturn([]);

        await service.deleteOldMessages(
          conversationId: 'conv123',
          userId: 'user123',
          autoDeleteDays: 7,
        );

        final captured = verify(
          mockMessagesCollection.where('timestamp', isLessThan: captureAnyNamed('isLessThan')),
        ).captured;

        expect(captured.length, equals(1));
        final cutoffTimestamp = captured.first as Timestamp;
        final cutoffDate = cutoffTimestamp.toDate();
        final expectedCutoff = DateTime.now().subtract(const Duration(days: 7));

        expect(
          cutoffDate.difference(expectedCutoff).inMinutes.abs(),
          lessThan(1),
        );
      });

      test('uses correct cutoff for 30 days', () async {
        final mockEmptySnapshot = MockQuerySnapshot();

        when(mockMessagesCollection.where('timestamp', isLessThan: anyNamed('isLessThan')))
            .thenReturn(mockQuery);
        when(mockQuery.limit(any)).thenReturn(mockQuery);
        when(mockQuery.get()).thenAnswer((_) async => mockEmptySnapshot);
        when(mockEmptySnapshot.docs).thenReturn([]);

        await service.deleteOldMessages(
          conversationId: 'conv123',
          userId: 'user123',
          autoDeleteDays: 30,
        );

        final captured = verify(
          mockMessagesCollection.where('timestamp', isLessThan: captureAnyNamed('isLessThan')),
        ).captured;

        expect(captured.length, equals(1));
        final cutoffTimestamp = captured.first as Timestamp;
        final cutoffDate = cutoffTimestamp.toDate();
        final expectedCutoff = DateTime.now().subtract(const Duration(days: 30));

        expect(
          cutoffDate.difference(expectedCutoff).inMinutes.abs(),
          lessThan(1),
        );
      });
    });

    group('deletion scope security', () {
      test('only queries within the specified conversation', () async {
        final mockEmptySnapshot = MockQuerySnapshot();

        when(mockMessagesCollection.where('timestamp', isLessThan: anyNamed('isLessThan')))
            .thenReturn(mockQuery);
        when(mockQuery.limit(any)).thenReturn(mockQuery);
        when(mockQuery.get()).thenAnswer((_) async => mockEmptySnapshot);
        when(mockEmptySnapshot.docs).thenReturn([]);

        await service.deleteOldMessages(
          conversationId: 'specific-conv-id',
          userId: 'user123',
          autoDeleteDays: 7,
        );

        verify(mockConversationsCollection.doc('specific-conv-id')).called(1);
      });

      test('does not access other conversations', () async {
        final mockEmptySnapshot = MockQuerySnapshot();

        when(mockMessagesCollection.where('timestamp', isLessThan: anyNamed('isLessThan')))
            .thenReturn(mockQuery);
        when(mockQuery.limit(any)).thenReturn(mockQuery);
        when(mockQuery.get()).thenAnswer((_) async => mockEmptySnapshot);
        when(mockEmptySnapshot.docs).thenReturn([]);

        await service.deleteOldMessages(
          conversationId: 'conv-A',
          userId: 'user123',
          autoDeleteDays: 7,
        );

        verifyNever(mockConversationsCollection.doc('conv-B'));
        verifyNever(mockConversationsCollection.doc('conv-C'));
      });
    });
  });
}
