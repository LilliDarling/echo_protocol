import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_protocol/models/local/message.dart';
import 'package:echo_protocol/models/vault/vault_chunk.dart';
import 'package:echo_protocol/models/vault/vault_metadata.dart';
import 'package:echo_protocol/models/vault/retention_settings.dart';

LocalMessage _makeMessage({
  required String id,
  required String conversationId,
  LocalMessageType type = LocalMessageType.text,
  String? mediaId,
  String? mediaKey,
  DateTime? timestamp,
}) {
  final ts = timestamp ?? DateTime(2025, 1, 15, 12, 0);
  return LocalMessage(
    id: id,
    conversationId: conversationId,
    senderId: 'user_sender',
    senderUsername: 'sender',
    content: 'Hello world',
    timestamp: ts,
    type: type,
    status: LocalMessageStatus.sent,
    mediaId: mediaId,
    mediaKey: mediaKey,
    isOutgoing: true,
    createdAt: ts,
  );
}

void main() {
  group('VaultChunkConversation', () {
    test('serializes and deserializes correctly', () {
      final conv = VaultChunkConversation(
        conversationId: 'alice_bob',
        recipientId: 'bob',
        recipientUsername: 'bob_user',
        recipientPublicKey: 'publickey123',
        messages: [
          _makeMessage(id: 'msg1', conversationId: 'alice_bob'),
          _makeMessage(id: 'msg2', conversationId: 'alice_bob'),
        ],
      );

      final json = conv.toJson();
      final restored = VaultChunkConversation.fromJson(json);

      expect(restored.conversationId, 'alice_bob');
      expect(restored.recipientId, 'bob');
      expect(restored.recipientUsername, 'bob_user');
      expect(restored.recipientPublicKey, 'publickey123');
      expect(restored.messages.length, 2);
      expect(restored.messages[0].id, 'msg1');
      expect(restored.messages[1].id, 'msg2');
    });

    test('handles messages with media fields', () {
      final conv = VaultChunkConversation(
        conversationId: 'conv1',
        recipientId: 'user2',
        recipientUsername: 'user2_name',
        recipientPublicKey: 'pk',
        messages: [
          _makeMessage(
            id: 'media_msg',
            conversationId: 'conv1',
            type: LocalMessageType.image,
            mediaId: 'media_001',
            mediaKey: 'key_base64',
          ),
        ],
      );

      final json = conv.toJson();
      final restored = VaultChunkConversation.fromJson(json);

      expect(restored.messages[0].type, LocalMessageType.image);
      expect(restored.messages[0].mediaId, 'media_001');
      expect(restored.messages[0].mediaKey, 'key_base64');
    });
  });

  group('VaultChunk', () {
    VaultChunk makeChunk({
      int messageCount1 = 2,
      int messageCount2 = 1,
    }) {
      return VaultChunk(
        chunkId: 'chunk_abc123',
        chunkIndex: 5,
        startTimestamp: DateTime(2025, 1, 15, 10, 0),
        endTimestamp: DateTime(2025, 1, 15, 18, 0),
        conversations: [
          VaultChunkConversation(
            conversationId: 'conv_a',
            recipientId: 'user_a',
            recipientUsername: 'alice',
            recipientPublicKey: 'pk_a',
            messages: List.generate(
              messageCount1,
              (i) => _makeMessage(id: 'a_$i', conversationId: 'conv_a'),
            ),
          ),
          VaultChunkConversation(
            conversationId: 'conv_b',
            recipientId: 'user_b',
            recipientUsername: 'bob',
            recipientPublicKey: 'pk_b',
            messages: List.generate(
              messageCount2,
              (i) => _makeMessage(id: 'b_$i', conversationId: 'conv_b'),
            ),
          ),
        ],
        checksum: 'abc123',
      );
    }

    test('serialize and deserialize round-trip', () {
      final chunk = makeChunk();
      final bytes = chunk.serialize();
      final restored = VaultChunk.deserialize(bytes);

      expect(restored.chunkId, chunk.chunkId);
      expect(restored.chunkIndex, chunk.chunkIndex);
      expect(restored.startTimestamp, chunk.startTimestamp);
      expect(restored.endTimestamp, chunk.endTimestamp);
      expect(restored.checksum, chunk.checksum);
      expect(restored.version, VaultChunk.currentVersion);
      expect(restored.conversations.length, 2);
      expect(restored.conversations[0].messages.length, 2);
      expect(restored.conversations[1].messages.length, 1);
    });

    test('messageCount sums across all conversations', () {
      final chunk = makeChunk(messageCount1: 3, messageCount2: 7);
      expect(chunk.messageCount, 10);
    });

    test('messageCount is zero for empty conversations', () {
      final chunk = VaultChunk(
        chunkId: 'empty',
        chunkIndex: 0,
        startTimestamp: DateTime(2025, 1, 1),
        endTimestamp: DateTime(2025, 1, 1),
        conversations: [],
        checksum: '',
      );
      expect(chunk.messageCount, 0);
    });

    test('fromJson defaults version to 1 when missing', () {
      final json = {
        'chunkId': 'test',
        'chunkIndex': 0,
        'startTimestamp': DateTime(2025, 1, 1).millisecondsSinceEpoch,
        'endTimestamp': DateTime(2025, 1, 1).millisecondsSinceEpoch,
        'conversations': <Map<String, dynamic>>[],
        'checksum': 'abc',
        // version intentionally omitted
      };

      final chunk = VaultChunk.fromJson(json);
      expect(chunk.version, 1);
    });

    test('serialization preserves all message types', () {
      for (final type in LocalMessageType.values) {
        final chunk = VaultChunk(
          chunkId: 'type_test',
          chunkIndex: 0,
          startTimestamp: DateTime(2025, 1, 1),
          endTimestamp: DateTime(2025, 1, 1),
          conversations: [
            VaultChunkConversation(
              conversationId: 'conv',
              recipientId: 'r',
              recipientUsername: 'ru',
              recipientPublicKey: 'pk',
              messages: [
                _makeMessage(id: 'msg_$type', conversationId: 'conv', type: type),
              ],
            ),
          ],
          checksum: '',
        );

        final bytes = chunk.serialize();
        final restored = VaultChunk.deserialize(bytes);
        expect(restored.conversations[0].messages[0].type, type);
      }
    });

    test('serialization preserves message status', () {
      for (final status in LocalMessageStatus.values) {
        final msg = LocalMessage(
          id: 'status_$status',
          conversationId: 'conv',
          senderId: 'sender',
          senderUsername: 'sender_name',
          content: 'test',
          timestamp: DateTime(2025, 1, 1),
          status: status,
          isOutgoing: false,
          createdAt: DateTime(2025, 1, 1),
        );

        final chunk = VaultChunk(
          chunkId: 'status_test',
          chunkIndex: 0,
          startTimestamp: DateTime(2025, 1, 1),
          endTimestamp: DateTime(2025, 1, 1),
          conversations: [
            VaultChunkConversation(
              conversationId: 'conv',
              recipientId: 'r',
              recipientUsername: 'ru',
              recipientPublicKey: 'pk',
              messages: [msg],
            ),
          ],
          checksum: '',
        );

        final bytes = chunk.serialize();
        final restored = VaultChunk.deserialize(bytes);
        expect(restored.conversations[0].messages[0].status, status);
      }
    });

    test('serialized bytes are valid UTF-8 JSON', () {
      final chunk = makeChunk();
      final bytes = chunk.serialize();
      final jsonStr = utf8.decode(bytes);
      final parsed = jsonDecode(jsonStr);
      expect(parsed, isA<Map<String, dynamic>>());
    });
  });

  group('VaultChunkMetadata', () {
    test('Firestore round-trip', () {
      final meta = VaultChunkMetadata(
        chunkId: 'chunk_xyz',
        chunkIndex: 3,
        startTimestamp: DateTime(2025, 1, 10),
        endTimestamp: DateTime(2025, 1, 11),
        messageCount: 150,
        compressedSize: 45000,
        checksum: 'sha256hex',
        storagePath: 'vault_chunks/user123/chunk_xyz.bin',
        uploadedAt: DateTime(2025, 1, 11, 12, 0),
      );

      final firestoreData = meta.toFirestore();
      final restored = VaultChunkMetadata.fromFirestore(firestoreData);

      expect(restored.chunkId, meta.chunkId);
      expect(restored.chunkIndex, meta.chunkIndex);
      expect(restored.startTimestamp, meta.startTimestamp);
      expect(restored.endTimestamp, meta.endTimestamp);
      expect(restored.messageCount, meta.messageCount);
      expect(restored.compressedSize, meta.compressedSize);
      expect(restored.checksum, meta.checksum);
      expect(restored.storagePath, meta.storagePath);
      expect(restored.uploadedAt, meta.uploadedAt);
    });
  });

  group('RetentionSettings', () {
    test('defaults to smart policy', () {
      const settings = RetentionSettings();
      expect(settings.policy, RetentionPolicy.smart);
    });

    test('JSON round-trip', () {
      const settings = RetentionSettings(policy: RetentionPolicy.minimal);
      final json = settings.toJson();
      final restored = RetentionSettings.fromJson(json);
      expect(restored.policy, RetentionPolicy.minimal);
    });

    test('fromJson defaults to smart for unknown policy', () {
      final settings = RetentionSettings.fromJson({'policy': 'unknown'});
      expect(settings.policy, RetentionPolicy.smart);
    });

    test('fromJson defaults to smart for missing policy', () {
      final settings = RetentionSettings.fromJson({});
      expect(settings.policy, RetentionPolicy.smart);
    });

    test('includeMedia returns false only for messagesOnly', () {
      expect(
        const RetentionSettings(policy: RetentionPolicy.everything).includeMedia,
        isTrue,
      );
      expect(
        const RetentionSettings(policy: RetentionPolicy.smart).includeMedia,
        isTrue,
      );
      expect(
        const RetentionSettings(policy: RetentionPolicy.minimal).includeMedia,
        isTrue,
      );
      expect(
        const RetentionSettings(policy: RetentionPolicy.messagesOnly).includeMedia,
        isFalse,
      );
    });

    test('mediaExpiry returns correct durations', () {
      expect(RetentionPolicy.everything.mediaExpiry, isNull);
      expect(RetentionPolicy.smart.mediaExpiry, const Duration(days: 365));
      expect(RetentionPolicy.minimal.mediaExpiry, const Duration(days: 30));
      expect(RetentionPolicy.messagesOnly.mediaExpiry, Duration.zero);
    });

    test('all RetentionPolicy values have string values', () {
      for (final policy in RetentionPolicy.values) {
        expect(policy.value, isNotEmpty);
        expect(RetentionPolicy.fromString(policy.value), policy);
      }
    });
  });
}
