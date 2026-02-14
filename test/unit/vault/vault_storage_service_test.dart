import 'dart:typed_data';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:echo_protocol/models/local/message.dart';
import 'package:echo_protocol/models/vault/vault_chunk.dart';
import 'package:echo_protocol/models/vault/vault_metadata.dart';
import 'package:echo_protocol/services/vault/vault_encryption_service.dart';
import 'package:echo_protocol/services/vault/vault_storage_service.dart';

@GenerateNiceMocks([
  MockSpec<VaultEncryptionService>(),
  MockSpec<Reference>(),
])
import 'vault_storage_service_test.mocks.dart';

VaultChunk _makeChunk({int chunkIndex = 0}) {
  final msg = LocalMessage(
    id: 'msg_1',
    conversationId: 'conv1',
    senderId: 'sender',
    senderUsername: 'sender_name',
    content: 'Hello vault',
    timestamp: DateTime(2025, 1, 15, 12, 0),
    isOutgoing: true,
    createdAt: DateTime(2025, 1, 15, 12, 0),
  );

  final chunk = VaultChunk(
    chunkId: 'chunk_test_$chunkIndex',
    chunkIndex: chunkIndex,
    startTimestamp: DateTime(2025, 1, 15, 12, 0),
    endTimestamp: DateTime(2025, 1, 15, 13, 0),
    conversations: [
      VaultChunkConversation(
        conversationId: 'conv1',
        recipientId: 'recipient',
        recipientUsername: 'recipient_name',
        recipientPublicKey: 'pk',
        messages: [msg],
      ),
    ],
    checksum: '',
  );

  final serialized = chunk.serialize();
  final checksum = VaultEncryptionService.computeChecksum(serialized);

  return VaultChunk(
    chunkId: chunk.chunkId,
    chunkIndex: chunk.chunkIndex,
    startTimestamp: chunk.startTimestamp,
    endTimestamp: chunk.endTimestamp,
    conversations: chunk.conversations,
    checksum: checksum,
  );
}

void main() {
  group('VaultStorageService', () {
    late FakeFirebaseFirestore fakeFirestore;
    late MockVaultEncryptionService mockEncryption;
    late MockReference mockRef;
    late MockReference mockChildRef;
    late VaultStorageService service;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      mockEncryption = MockVaultEncryptionService();
      mockRef = MockReference();
      mockChildRef = MockReference();

      // Only used for download tests; upload tests use Firestore directly
      final mockStorage = _FakeFirebaseStorage(mockRef);

      when(mockRef.child(any)).thenReturn(mockChildRef);

      service = VaultStorageService(
        firestore: fakeFirestore,
        storage: mockStorage,
        encryption: mockEncryption,
      );
    });

    group('listChunks', () {
      test('returns chunks ordered by chunkIndex', () async {
        for (var i = 2; i >= 0; i--) {
          final meta = VaultChunkMetadata(
            chunkId: 'chunk_$i',
            chunkIndex: i,
            startTimestamp: DateTime(2025, 1, 15),
            endTimestamp: DateTime(2025, 1, 15),
            messageCount: 10,
            compressedSize: 500,
            checksum: 'cs_$i',
            storagePath: 'path/$i',
            uploadedAt: DateTime(2025, 1, 15),
          );

          await fakeFirestore
              .collection('vaults')
              .doc('user123')
              .collection('chunks')
              .doc('chunk_$i')
              .set(meta.toFirestore());
        }

        final result = await service.listChunks(userId: 'user123');

        expect(result.length, 3);
        expect(result[0].chunkIndex, 0);
        expect(result[1].chunkIndex, 1);
        expect(result[2].chunkIndex, 2);
      });

      test('afterIndex filters correctly', () async {
        for (var i = 0; i < 5; i++) {
          final meta = VaultChunkMetadata(
            chunkId: 'chunk_$i',
            chunkIndex: i,
            startTimestamp: DateTime(2025, 1, 15),
            endTimestamp: DateTime(2025, 1, 15),
            messageCount: 10,
            compressedSize: 500,
            checksum: 'cs_$i',
            storagePath: 'path/$i',
            uploadedAt: DateTime(2025, 1, 15),
          );

          await fakeFirestore
              .collection('vaults')
              .doc('user123')
              .collection('chunks')
              .doc('chunk_$i')
              .set(meta.toFirestore());
        }

        final result =
            await service.listChunks(userId: 'user123', afterIndex: 2);

        expect(result.length, 2);
        expect(result[0].chunkIndex, 3);
        expect(result[1].chunkIndex, 4);
      });

      test('returns empty list when no chunks exist', () async {
        final result = await service.listChunks(userId: 'user123');
        expect(result, isEmpty);
      });
    });

    group('getLatestChunkIndex', () {
      test('returns -1 when no chunks exist', () async {
        final result = await service.getLatestChunkIndex('user123');
        expect(result, -1);
      });

      test('returns highest chunkIndex', () async {
        for (var i = 0; i < 3; i++) {
          await fakeFirestore
              .collection('vaults')
              .doc('user123')
              .collection('chunks')
              .doc('chunk_$i')
              .set({
            'chunkId': 'chunk_$i',
            'chunkIndex': i,
            'startTimestamp': 0,
            'endTimestamp': 0,
            'messageCount': 10,
            'compressedSize': 500,
            'checksum': 'cs',
            'storagePath': 'path',
            'uploadedAt': 0,
          });
        }

        final result = await service.getLatestChunkIndex('user123');
        expect(result, 2);
      });
    });

    group('downloadChunk', () {
      test('decrypts and verifies checksum', () async {
        final chunk = _makeChunk();
        final serialized = chunk.serialize();
        final fakeEncrypted = Uint8List.fromList([1, 2, 3]);

        when(mockChildRef.getData(any))
            .thenAnswer((_) async => fakeEncrypted);

        when(mockEncryption.decryptChunk(
          encrypted: anyNamed('encrypted'),
          chunkId: anyNamed('chunkId'),
        )).thenAnswer((_) async => serialized);

        final metadata = VaultChunkMetadata(
          chunkId: chunk.chunkId,
          chunkIndex: chunk.chunkIndex,
          startTimestamp: chunk.startTimestamp,
          endTimestamp: chunk.endTimestamp,
          messageCount: chunk.messageCount,
          compressedSize: fakeEncrypted.length,
          checksum: chunk.checksum,
          storagePath: 'vault_chunks/user123/${chunk.chunkId}.bin',
          uploadedAt: DateTime.now(),
        );

        final result = await service.downloadChunk(
          userId: 'user123',
          metadata: metadata,
        );

        expect(result.chunkId, chunk.chunkId);
        expect(result.messageCount, chunk.messageCount);
        verify(mockEncryption.decryptChunk(
          encrypted: anyNamed('encrypted'),
          chunkId: anyNamed('chunkId'),
        )).called(1);
      });

      test('throws on checksum mismatch', () async {
        final chunk = _makeChunk();
        final serialized = chunk.serialize();

        when(mockChildRef.getData(any))
            .thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));

        when(mockEncryption.decryptChunk(
          encrypted: anyNamed('encrypted'),
          chunkId: anyNamed('chunkId'),
        )).thenAnswer((_) async => serialized);

        final metadata = VaultChunkMetadata(
          chunkId: chunk.chunkId,
          chunkIndex: chunk.chunkIndex,
          startTimestamp: chunk.startTimestamp,
          endTimestamp: chunk.endTimestamp,
          messageCount: chunk.messageCount,
          compressedSize: 100,
          checksum: 'wrong_checksum',
          storagePath: 'path',
          uploadedAt: DateTime.now(),
        );

        expect(
          () => service.downloadChunk(
            userId: 'user123',
            metadata: metadata,
          ),
          throwsA(predicate(
              (e) => e.toString().contains('integrity check failed'))),
        );
      });

      test('throws when storage returns null', () async {
        when(mockChildRef.getData(any)).thenAnswer((_) async => null);

        final metadata = VaultChunkMetadata(
          chunkId: 'chunk1',
          chunkIndex: 0,
          startTimestamp: DateTime(2025, 1, 1),
          endTimestamp: DateTime(2025, 1, 1),
          messageCount: 1,
          compressedSize: 100,
          checksum: 'cs',
          storagePath: 'path',
          uploadedAt: DateTime.now(),
        );

        expect(
          () => service.downloadChunk(
            userId: 'user123',
            metadata: metadata,
          ),
          throwsA(predicate(
              (e) => e.toString().contains('not found in storage'))),
        );
      });
    });
  });
}

/// Minimal fake that just returns the mock reference for child() calls.
class _FakeFirebaseStorage extends Fake implements FirebaseStorage {
  final Reference _rootRef;
  _FakeFirebaseStorage(this._rootRef);

  @override
  Reference ref([String? path]) => _rootRef;
}
