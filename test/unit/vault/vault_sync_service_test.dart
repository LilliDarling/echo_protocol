import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:echo_protocol/models/local/message.dart';
import 'package:echo_protocol/models/local/conversation.dart';
import 'package:echo_protocol/models/vault/vault_chunk.dart';
import 'package:echo_protocol/models/vault/vault_metadata.dart';
import 'package:echo_protocol/repositories/message_dao.dart';
import 'package:echo_protocol/repositories/conversation_dao.dart';
import 'package:echo_protocol/services/vault/vault_storage_service.dart';
import 'package:echo_protocol/services/vault/vault_sync_service.dart';

@GenerateNiceMocks([
  MockSpec<FirebaseAuth>(),
  MockSpec<VaultStorageService>(),
  MockSpec<MessageDao>(),
  MockSpec<ConversationDao>(),
  MockSpec<User>(),
])
import 'vault_sync_service_test.mocks.dart';

LocalMessage _makeMsg({
  required String id,
  required String conversationId,
  DateTime? timestamp,
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
  );
}

void main() {
  group('VaultSyncService', () {
    late MockFirebaseAuth mockAuth;
    late MockVaultStorageService mockStorage;
    late MockMessageDao mockMessageDao;
    late MockConversationDao mockConversationDao;
    late MockUser mockUser;
    late VaultSyncService service;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      mockStorage = MockVaultStorageService();
      mockMessageDao = MockMessageDao();
      mockConversationDao = MockConversationDao();
      mockUser = MockUser();

      when(mockAuth.currentUser).thenReturn(mockUser);
      when(mockUser.uid).thenReturn('user123');

      service = VaultSyncService.forTesting(
        auth: mockAuth,
        storageService: mockStorage,
        messageDao: mockMessageDao,
        conversationDao: mockConversationDao,
      );
    });

    group('uploadUnsyncedMessages', () {
      test('returns 0 when no unsynced messages', () async {
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
        when(mockMessageDao.getUnsyncedMessages(limit: 2000))
            .thenAnswer((_) async => []);

        final states = <VaultSyncState>[];
        service.stateStream.listen(states.add);

        await service.uploadUnsyncedMessages();
        await Future.delayed(Duration.zero);

        expect(states, [VaultSyncState.uploading, VaultSyncState.idle]);
      });

      test('transitions state to error on failure', () async {
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
    });

    group('concurrency guard', () {
      test('second upload returns 0 while first is in progress', () async {
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
