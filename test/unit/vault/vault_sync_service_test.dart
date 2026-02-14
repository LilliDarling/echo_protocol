import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:echo_protocol/models/local/message.dart';
import 'package:echo_protocol/models/local/conversation.dart';
import 'package:echo_protocol/models/vault/vault_chunk.dart';
import 'package:echo_protocol/models/vault/vault_metadata.dart';
import 'package:echo_protocol/repositories/message_dao.dart';
import 'package:echo_protocol/repositories/conversation_dao.dart';
import 'package:echo_protocol/services/secure_storage.dart';
import 'package:echo_protocol/services/vault/vault_media_service.dart';
import 'package:echo_protocol/services/vault/vault_storage_service.dart';
import 'package:echo_protocol/services/vault/vault_sync_service.dart';

@GenerateNiceMocks([
  MockSpec<FirebaseAuth>(),
  MockSpec<FirebaseFirestore>(),
  MockSpec<FirebaseStorage>(),
  MockSpec<VaultStorageService>(),
  MockSpec<VaultMediaService>(),
  MockSpec<SecureStorageService>(),
  MockSpec<MessageDao>(),
  MockSpec<ConversationDao>(),
  MockSpec<User>(),
])
import 'vault_sync_service_test.mocks.dart';

LocalMessage _makeMsg({
  required String id,
  required String conversationId,
  DateTime? timestamp,
  String? mediaId,
  String? mediaKey,
}) {
  final ts = timestamp ?? DateTime(2025, 1, 15, 12, 0);
  return LocalMessage(
    id: id,
    conversationId: conversationId,
    senderId: 'sender',
    senderUsername: 'sender_name',
    content: 'Hello vault',
    timestamp: ts,
    isOutgoing: true,
    createdAt: ts,
    mediaId: mediaId,
    mediaKey: mediaKey,
  );
}

void main() {
  group('VaultSyncService', () {
    late MockFirebaseAuth mockAuth;
    late MockFirebaseFirestore mockFirestore;
    late MockFirebaseStorage mockFirebaseStorage;
    late MockVaultStorageService mockStorage;
    late MockVaultMediaService mockMediaService;
    late MockSecureStorageService mockSecureStorage;
    late MockMessageDao mockMessageDao;
    late MockConversationDao mockConversationDao;
    late MockUser mockUser;
    late VaultSyncService service;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      mockFirestore = MockFirebaseFirestore();
      mockFirebaseStorage = MockFirebaseStorage();
      mockStorage = MockVaultStorageService();
      mockMediaService = MockVaultMediaService();
      mockSecureStorage = MockSecureStorageService();
      mockMessageDao = MockMessageDao();
      mockConversationDao = MockConversationDao();
      mockUser = MockUser();

      when(mockAuth.currentUser).thenReturn(mockUser);
      when(mockUser.uid).thenReturn('user123');
      when(mockSecureStorage.getLastSyncedChunkIndex())
          .thenAnswer((_) async => -1);

      service = VaultSyncService.forTesting(
        auth: mockAuth,
        firestore: mockFirestore,
        firebaseStorage: mockFirebaseStorage,
        storageService: mockStorage,
        mediaService: mockMediaService,
        secureStorage: mockSecureStorage,
        messageDao: mockMessageDao,
        conversationDao: mockConversationDao,
      );
    });

    group('uploadUnsyncedMessages', () {
      test('returns 0 when no unsynced messages', () async {
        when(mockStorage.getLatestChunkIndex('user123'))
            .thenAnswer((_) async => -1);
        when(mockMessageDao.getUnsyncedMessages(limit: 2000))
            .thenAnswer((_) async => []);

        final result = await service.uploadUnsyncedMessages();

        expect(result, 0);
        verify(mockMessageDao.getUnsyncedMessages(limit: 2000)).called(1);
        verifyNever(mockStorage.uploadChunk(
          userId: anyNamed('userId'),
          chunk: anyNamed('chunk'),
        ));
      });

      test('uploads chunks and marks messages as synced', () async {
        final messages = [
          _makeMsg(id: 'msg1', conversationId: 'conv1'),
          _makeMsg(id: 'msg2', conversationId: 'conv1'),
        ];

        final conversation = LocalConversation(
          id: 'conv1',
          recipientId: 'recipient1',
          recipientUsername: 'user1',
          recipientPublicKey: 'pk1',
          createdAt: DateTime(2025, 1, 1),
          updatedAt: DateTime(2025, 1, 1),
        );

        when(mockMessageDao.getUnsyncedMessages(limit: 2000))
            .thenAnswer((_) async => messages);
        when(mockConversationDao.getById('conv1'))
            .thenAnswer((_) async => conversation);
        when(mockStorage.getLatestChunkIndex('user123'))
            .thenAnswer((_) async => -1);
        when(mockStorage.uploadChunk(
          userId: anyNamed('userId'),
          chunk: anyNamed('chunk'),
        )).thenAnswer((_) async => VaultChunkMetadata(
              chunkId: 'chunk_0',
              chunkIndex: 0,
              startTimestamp: DateTime(2025, 1, 15),
              endTimestamp: DateTime(2025, 1, 15),
              messageCount: 2,
              compressedSize: 100,
              checksum: 'cs',
              storagePath: 'path',
              uploadedAt: DateTime.now(),
            ));

        final result = await service.uploadUnsyncedMessages();

        expect(result, 2);
        verify(mockStorage.uploadChunk(
          userId: 'user123',
          chunk: anyNamed('chunk'),
        )).called(1);
        verify(mockMessageDao.markBatchAsSynced(['msg1', 'msg2'])).called(1);
      });

      test('uses correct starting index from latest chunk', () async {
        final messages = [
          _makeMsg(id: 'msg1', conversationId: 'conv1'),
        ];

        when(mockMessageDao.getUnsyncedMessages(limit: 2000))
            .thenAnswer((_) async => messages);
        when(mockConversationDao.getById('conv1')).thenAnswer(
            (_) async => LocalConversation(
                  id: 'conv1',
                  recipientId: 'r1',
                  recipientUsername: 'u1',
                  recipientPublicKey: 'pk1',
                  createdAt: DateTime(2025, 1, 1),
                  updatedAt: DateTime(2025, 1, 1),
                ));
        when(mockStorage.getLatestChunkIndex('user123'))
            .thenAnswer((_) async => 5);
        when(mockStorage.uploadChunk(
          userId: anyNamed('userId'),
          chunk: anyNamed('chunk'),
        )).thenAnswer((_) async => VaultChunkMetadata(
              chunkId: 'chunk_6',
              chunkIndex: 6,
              startTimestamp: DateTime(2025, 1, 15),
              endTimestamp: DateTime(2025, 1, 15),
              messageCount: 1,
              compressedSize: 50,
              checksum: 'cs',
              storagePath: 'path',
              uploadedAt: DateTime.now(),
            ));

        await service.uploadUnsyncedMessages();

        final captured = verify(mockStorage.uploadChunk(
          userId: 'user123',
          chunk: captureAnyNamed('chunk'),
        )).captured;

        final uploadedChunk = captured.first as VaultChunk;
        expect(uploadedChunk.chunkIndex, 6);
      });

      test('throws when not authenticated', () async {
        when(mockAuth.currentUser).thenReturn(null);

        expect(
          () => service.uploadUnsyncedMessages(),
          throwsA(predicate((e) => e.toString().contains('Not authenticated'))),
        );
      });

      test('transitions state correctly on success', () async {
        when(mockStorage.getLatestChunkIndex('user123'))
            .thenAnswer((_) async => -1);
        when(mockMessageDao.getUnsyncedMessages(limit: 2000))
            .thenAnswer((_) async => []);

        final states = <VaultSyncState>[];
        service.stateStream.listen(states.add);

        await service.uploadUnsyncedMessages();
        await Future.delayed(Duration.zero);

        expect(states, [VaultSyncState.uploading, VaultSyncState.idle]);
      });

      test('transitions state to error on failure', () async {
        when(mockStorage.getLatestChunkIndex('user123'))
            .thenAnswer((_) async => -1);
        when(mockMessageDao.getUnsyncedMessages(limit: 2000))
            .thenThrow(Exception('DB error'));

        final states = <VaultSyncState>[];
        service.stateStream.listen(states.add);

        await expectLater(
          () => service.uploadUnsyncedMessages(),
          throwsA(isA<Exception>()),
        );

        await Future.delayed(Duration.zero);
        expect(states, [VaultSyncState.uploading, VaultSyncState.error]);
        expect(service.error, contains('DB error'));
      });

      test('updates last synced chunk index after upload', () async {
        final messages = [
          _makeMsg(id: 'msg1', conversationId: 'conv1'),
        ];

        when(mockMessageDao.getUnsyncedMessages(limit: 2000))
            .thenAnswer((_) async => messages);
        when(mockConversationDao.getById('conv1')).thenAnswer(
            (_) async => LocalConversation(
                  id: 'conv1',
                  recipientId: 'r1',
                  recipientUsername: 'u1',
                  recipientPublicKey: 'pk1',
                  createdAt: DateTime(2025, 1, 1),
                  updatedAt: DateTime(2025, 1, 1),
                ));
        when(mockStorage.getLatestChunkIndex('user123'))
            .thenAnswer((_) async => 2);
        when(mockStorage.uploadChunk(
          userId: anyNamed('userId'),
          chunk: anyNamed('chunk'),
        )).thenAnswer((_) async => VaultChunkMetadata(
              chunkId: 'chunk_3',
              chunkIndex: 3,
              startTimestamp: DateTime(2025, 1, 15),
              endTimestamp: DateTime(2025, 1, 15),
              messageCount: 1,
              compressedSize: 50,
              checksum: 'cs',
              storagePath: 'path',
              uploadedAt: DateTime.now(),
            ));

        await service.uploadUnsyncedMessages();

        verify(mockSecureStorage.storeLastSyncedChunkIndex(3)).called(1);
      });

      test('downloads newer chunks from other devices before uploading',
          () async {
        // Server has chunk index 5, but local is at -1
        when(mockSecureStorage.getLastSyncedChunkIndex())
            .thenAnswer((_) async => -1);

        // First call returns 5 (conflict detected), second call returns 5 (after merge)
        var callCount = 0;
        when(mockStorage.getLatestChunkIndex('user123')).thenAnswer((_) async {
          callCount++;
          return 5;
        });

        // downloadAndMerge will be called - set up for it to find no new chunks
        // (after the _isSyncing guard is released)
        when(mockStorage.listChunks(userId: 'user123'))
            .thenAnswer((_) async => []);
        when(mockStorage.listChunks(userId: 'user123', afterIndex: -1))
            .thenAnswer((_) async => []);

        when(mockMessageDao.getUnsyncedMessages(limit: 2000))
            .thenAnswer((_) async => []);

        await service.uploadUnsyncedMessages();

        // Verify getLatestChunkIndex was called (conflict check)
        verify(mockStorage.getLatestChunkIndex('user123')).called(greaterThan(0));
      });
    });

    group('downloadAndMerge', () {
      test('returns 0 when no chunks exist', () async {
        when(mockStorage.listChunks(userId: 'user123'))
            .thenAnswer((_) async => []);

        final result = await service.downloadAndMerge();

        expect(result, 0);
      });

      test('downloads chunks and merges conversations and messages', () async {
        final metadata = VaultChunkMetadata(
          chunkId: 'chunk_0',
          chunkIndex: 0,
          startTimestamp: DateTime(2025, 1, 15),
          endTimestamp: DateTime(2025, 1, 15),
          messageCount: 2,
          compressedSize: 100,
          checksum: 'cs',
          storagePath: 'path',
          uploadedAt: DateTime.now(),
        );

        final messages = [
          _makeMsg(id: 'msg1', conversationId: 'conv1'),
          _makeMsg(id: 'msg2', conversationId: 'conv1'),
        ];

        final chunk = VaultChunk(
          chunkId: 'chunk_0',
          chunkIndex: 0,
          startTimestamp: DateTime(2025, 1, 15),
          endTimestamp: DateTime(2025, 1, 15),
          conversations: [
            VaultChunkConversation(
              conversationId: 'conv1',
              recipientId: 'recipient1',
              recipientUsername: 'user1',
              recipientPublicKey: 'pk1',
              messages: messages,
            ),
          ],
          checksum: 'cs',
        );

        when(mockStorage.listChunks(userId: 'user123'))
            .thenAnswer((_) async => [metadata]);
        when(mockStorage.downloadChunk(
          userId: 'user123',
          metadata: metadata,
        )).thenAnswer((_) async => chunk);
        when(mockConversationDao.getById('conv1'))
            .thenAnswer((_) async => null);

        final result = await service.downloadAndMerge();

        expect(result, 2);
        verify(mockConversationDao.insert(any)).called(1);
        verify(mockMessageDao.insertBatch(messages)).called(1);
      });

      test('does not re-insert existing conversations', () async {
        final metadata = VaultChunkMetadata(
          chunkId: 'chunk_0',
          chunkIndex: 0,
          startTimestamp: DateTime(2025, 1, 15),
          endTimestamp: DateTime(2025, 1, 15),
          messageCount: 1,
          compressedSize: 50,
          checksum: 'cs',
          storagePath: 'path',
          uploadedAt: DateTime.now(),
        );

        final chunk = VaultChunk(
          chunkId: 'chunk_0',
          chunkIndex: 0,
          startTimestamp: DateTime(2025, 1, 15),
          endTimestamp: DateTime(2025, 1, 15),
          conversations: [
            VaultChunkConversation(
              conversationId: 'conv1',
              recipientId: 'recipient1',
              recipientUsername: 'user1',
              recipientPublicKey: 'pk1',
              messages: [_makeMsg(id: 'msg1', conversationId: 'conv1')],
            ),
          ],
          checksum: 'cs',
        );

        final existingConversation = LocalConversation(
          id: 'conv1',
          recipientId: 'recipient1',
          recipientUsername: 'user1',
          recipientPublicKey: 'pk1',
          createdAt: DateTime(2025, 1, 1),
          updatedAt: DateTime(2025, 1, 1),
        );

        when(mockStorage.listChunks(userId: 'user123'))
            .thenAnswer((_) async => [metadata]);
        when(mockStorage.downloadChunk(
          userId: 'user123',
          metadata: metadata,
        )).thenAnswer((_) async => chunk);
        when(mockConversationDao.getById('conv1'))
            .thenAnswer((_) async => existingConversation);

        await service.downloadAndMerge();

        verifyNever(mockConversationDao.insert(any));
        verify(mockMessageDao.insertBatch(any)).called(1);
      });

      test('throws when not authenticated', () async {
        when(mockAuth.currentUser).thenReturn(null);

        expect(
          () => service.downloadAndMerge(),
          throwsA(predicate((e) => e.toString().contains('Not authenticated'))),
        );
      });

      test('uses incremental sync with afterIndex', () async {
        when(mockSecureStorage.getLastSyncedChunkIndex())
            .thenAnswer((_) async => 3);

        final metadata = VaultChunkMetadata(
          chunkId: 'chunk_4',
          chunkIndex: 4,
          startTimestamp: DateTime(2025, 1, 16),
          endTimestamp: DateTime(2025, 1, 16),
          messageCount: 1,
          compressedSize: 50,
          checksum: 'cs',
          storagePath: 'path',
          uploadedAt: DateTime.now(),
        );

        final chunk = VaultChunk(
          chunkId: 'chunk_4',
          chunkIndex: 4,
          startTimestamp: DateTime(2025, 1, 16),
          endTimestamp: DateTime(2025, 1, 16),
          conversations: [
            VaultChunkConversation(
              conversationId: 'conv1',
              recipientId: 'r1',
              recipientUsername: 'u1',
              recipientPublicKey: 'pk1',
              messages: [_makeMsg(id: 'msg1', conversationId: 'conv1')],
            ),
          ],
          checksum: 'cs',
        );

        when(mockStorage.listChunks(userId: 'user123', afterIndex: 3))
            .thenAnswer((_) async => [metadata]);
        when(mockStorage.downloadChunk(userId: 'user123', metadata: metadata))
            .thenAnswer((_) async => chunk);
        when(mockConversationDao.getById('conv1'))
            .thenAnswer((_) async => null);

        final result = await service.downloadAndMerge();

        expect(result, 1);
        verify(mockStorage.listChunks(userId: 'user123', afterIndex: 3))
            .called(1);
        verify(mockSecureStorage.storeLastSyncedChunkIndex(4)).called(1);
      });

      test('updates last synced chunk index after download', () async {
        final metadata = VaultChunkMetadata(
          chunkId: 'chunk_7',
          chunkIndex: 7,
          startTimestamp: DateTime(2025, 1, 15),
          endTimestamp: DateTime(2025, 1, 15),
          messageCount: 1,
          compressedSize: 50,
          checksum: 'cs',
          storagePath: 'path',
          uploadedAt: DateTime.now(),
        );

        final chunk = VaultChunk(
          chunkId: 'chunk_7',
          chunkIndex: 7,
          startTimestamp: DateTime(2025, 1, 15),
          endTimestamp: DateTime(2025, 1, 15),
          conversations: [
            VaultChunkConversation(
              conversationId: 'conv1',
              recipientId: 'r1',
              recipientUsername: 'u1',
              recipientPublicKey: 'pk1',
              messages: [_makeMsg(id: 'msg1', conversationId: 'conv1')],
            ),
          ],
          checksum: 'cs',
        );

        when(mockStorage.listChunks(userId: 'user123'))
            .thenAnswer((_) async => [metadata]);
        when(mockStorage.downloadChunk(userId: 'user123', metadata: metadata))
            .thenAnswer((_) async => chunk);
        when(mockConversationDao.getById('conv1'))
            .thenAnswer((_) async => null);

        await service.downloadAndMerge();

        verify(mockSecureStorage.storeLastSyncedChunkIndex(7)).called(1);
      });
    });

    group('concurrency guard', () {
      test('second upload returns 0 while first is in progress', () async {
        when(mockStorage.getLatestChunkIndex('user123'))
            .thenAnswer((_) async => -1);

        final completer = Completer<List<LocalMessage>>();
        when(mockMessageDao.getUnsyncedMessages(limit: 2000))
            .thenAnswer((_) => completer.future);

        final firstCall = service.uploadUnsyncedMessages();
        final secondResult = await service.uploadUnsyncedMessages();

        expect(secondResult, 0);

        completer.complete([]);
        await firstCall;
      });

      test('second download returns 0 while first is in progress', () async {
        final completer = Completer<List<VaultChunkMetadata>>();
        when(mockStorage.listChunks(userId: 'user123'))
            .thenAnswer((_) => completer.future);

        final firstCall = service.downloadAndMerge();
        final secondResult = await service.downloadAndMerge();

        expect(secondResult, 0);

        completer.complete([]);
        await firstCall;
      });
    });

    group('shouldUpload', () {
      test('returns true when unsynced messages exist', () async {
        when(mockMessageDao.getUnsyncedMessages(limit: 1))
            .thenAnswer((_) async => [
                  _makeMsg(id: 'msg1', conversationId: 'conv1'),
                ]);

        final result = await service.shouldUpload();
        expect(result, isTrue);
      });

      test('returns false when no unsynced messages', () async {
        when(mockMessageDao.getUnsyncedMessages(limit: 1))
            .thenAnswer((_) async => []);

        final result = await service.shouldUpload();
        expect(result, isFalse);
      });
    });
  });
}
