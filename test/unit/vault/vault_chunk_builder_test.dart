import 'package:flutter_test/flutter_test.dart';
import 'package:echo_protocol/models/local/message.dart';
import 'package:echo_protocol/models/local/conversation.dart';
import 'package:echo_protocol/services/vault/vault_chunk_builder.dart';

LocalMessage _makeMsg({
  required String id,
  required String conversationId,
  required DateTime timestamp,
  String content = 'Hello',
}) {
  return LocalMessage(
    id: id,
    conversationId: conversationId,
    senderId: 'sender',
    senderUsername: 'sender_name',
    content: content,
    timestamp: timestamp,
    isOutgoing: true,
    createdAt: timestamp,
  );
}

Map<String, LocalConversation> _makeConvMap(Set<String> convIds) {
  final map = <String, LocalConversation>{};
  for (final id in convIds) {
    map[id] = LocalConversation(
      id: id,
      recipientId: 'recipient_$id',
      recipientUsername: 'user_$id',
      recipientPublicKey: 'pk_$id',
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
    );
  }
  return map;
}

void main() {
  group('VaultChunkBuilder', () {
    test('empty messages returns empty chunks', () {
      final chunks = VaultChunkBuilder.buildChunks(
        messages: [],
        conversationMap: {},
        startingIndex: 0,
      );
      expect(chunks, isEmpty);
    });

    test('single message produces one chunk', () {
      final messages = [
        _makeMsg(
          id: 'msg1',
          conversationId: 'conv1',
          timestamp: DateTime(2025, 1, 15, 12, 0),
        ),
      ];

      final chunks = VaultChunkBuilder.buildChunks(
        messages: messages,
        conversationMap: _makeConvMap({'conv1'}),
        startingIndex: 0,
      );

      expect(chunks.length, 1);
      expect(chunks[0].chunkIndex, 0);
      expect(chunks[0].messageCount, 1);
    });

    test('exactly 500 messages fits in one chunk', () {
      final base = DateTime(2025, 1, 15, 12, 0);
      final messages = List.generate(
        500,
        (i) => _makeMsg(
          id: 'msg_$i',
          conversationId: 'conv1',
          timestamp: base.add(Duration(seconds: i)),
        ),
      );

      final chunks = VaultChunkBuilder.buildChunks(
        messages: messages,
        conversationMap: _makeConvMap({'conv1'}),
        startingIndex: 0,
      );

      expect(chunks.length, 1);
      expect(chunks[0].messageCount, 500);
    });

    test('501 messages splits into 2 chunks', () {
      final base = DateTime(2025, 1, 15, 12, 0);
      final messages = List.generate(
        501,
        (i) => _makeMsg(
          id: 'msg_$i',
          conversationId: 'conv1',
          timestamp: base.add(Duration(seconds: i)),
        ),
      );

      final chunks = VaultChunkBuilder.buildChunks(
        messages: messages,
        conversationMap: _makeConvMap({'conv1'}),
        startingIndex: 0,
      );

      expect(chunks.length, 2);
      expect(chunks[0].messageCount, 500);
      expect(chunks[1].messageCount, 1);
    });

    test('messages spanning >24h split at time boundary', () {
      final messages = [
        _makeMsg(
          id: 'msg1',
          conversationId: 'conv1',
          timestamp: DateTime(2025, 1, 15, 10, 0),
        ),
        _makeMsg(
          id: 'msg2',
          conversationId: 'conv1',
          timestamp: DateTime(2025, 1, 15, 23, 0),
        ),
        // This one is >24h after msg1
        _makeMsg(
          id: 'msg3',
          conversationId: 'conv1',
          timestamp: DateTime(2025, 1, 16, 11, 0),
        ),
      ];

      final chunks = VaultChunkBuilder.buildChunks(
        messages: messages,
        conversationMap: _makeConvMap({'conv1'}),
        startingIndex: 0,
      );

      expect(chunks.length, 2);
      expect(chunks[0].messageCount, 2);
      expect(chunks[1].messageCount, 1);
    });

    test('messages are sorted by timestamp within chunk', () {
      // Provide messages out of order
      final messages = [
        _makeMsg(
          id: 'msg3',
          conversationId: 'conv1',
          timestamp: DateTime(2025, 1, 15, 15, 0),
        ),
        _makeMsg(
          id: 'msg1',
          conversationId: 'conv1',
          timestamp: DateTime(2025, 1, 15, 10, 0),
        ),
        _makeMsg(
          id: 'msg2',
          conversationId: 'conv1',
          timestamp: DateTime(2025, 1, 15, 12, 0),
        ),
      ];

      final chunks = VaultChunkBuilder.buildChunks(
        messages: messages,
        conversationMap: _makeConvMap({'conv1'}),
        startingIndex: 0,
      );

      expect(chunks.length, 1);
      final msgIds = chunks[0]
          .conversations[0]
          .messages
          .map((m) => m.id)
          .toList();
      expect(msgIds, ['msg1', 'msg2', 'msg3']);
    });

    test('groups messages by conversation within chunk', () {
      final base = DateTime(2025, 1, 15, 12, 0);
      final messages = [
        _makeMsg(id: 'a1', conversationId: 'conv_a', timestamp: base),
        _makeMsg(
          id: 'b1',
          conversationId: 'conv_b',
          timestamp: base.add(const Duration(minutes: 1)),
        ),
        _makeMsg(
          id: 'a2',
          conversationId: 'conv_a',
          timestamp: base.add(const Duration(minutes: 2)),
        ),
      ];

      final chunks = VaultChunkBuilder.buildChunks(
        messages: messages,
        conversationMap: _makeConvMap({'conv_a', 'conv_b'}),
        startingIndex: 0,
      );

      expect(chunks.length, 1);
      expect(chunks[0].conversations.length, 2);

      final convA = chunks[0]
          .conversations
          .firstWhere((c) => c.conversationId == 'conv_a');
      final convB = chunks[0]
          .conversations
          .firstWhere((c) => c.conversationId == 'conv_b');

      expect(convA.messages.length, 2);
      expect(convB.messages.length, 1);
    });

    test('chunk IDs are unique across chunks', () {
      final base = DateTime(2025, 1, 15, 12, 0);
      final messages = List.generate(
        1001,
        (i) => _makeMsg(
          id: 'msg_$i',
          conversationId: 'conv1',
          timestamp: base.add(Duration(seconds: i)),
        ),
      );

      final chunks = VaultChunkBuilder.buildChunks(
        messages: messages,
        conversationMap: _makeConvMap({'conv1'}),
        startingIndex: 0,
      );

      final chunkIds = chunks.map((c) => c.chunkId).toSet();
      expect(chunkIds.length, chunks.length);
    });

    test('startingIndex is respected for chunk indices', () {
      final base = DateTime(2025, 1, 15, 12, 0);
      final messages = List.generate(
        1001,
        (i) => _makeMsg(
          id: 'msg_$i',
          conversationId: 'conv1',
          timestamp: base.add(Duration(seconds: i)),
        ),
      );

      final chunks = VaultChunkBuilder.buildChunks(
        messages: messages,
        conversationMap: _makeConvMap({'conv1'}),
        startingIndex: 10,
      );

      expect(chunks[0].chunkIndex, 10);
      expect(chunks[1].chunkIndex, 11);
      expect(chunks[2].chunkIndex, 12);
    });

    test('chunk timestamps reflect first and last message', () {
      final messages = [
        _makeMsg(
          id: 'msg1',
          conversationId: 'conv1',
          timestamp: DateTime(2025, 1, 15, 10, 0),
        ),
        _makeMsg(
          id: 'msg2',
          conversationId: 'conv1',
          timestamp: DateTime(2025, 1, 15, 14, 0),
        ),
        _makeMsg(
          id: 'msg3',
          conversationId: 'conv1',
          timestamp: DateTime(2025, 1, 15, 18, 0),
        ),
      ];

      final chunks = VaultChunkBuilder.buildChunks(
        messages: messages,
        conversationMap: _makeConvMap({'conv1'}),
        startingIndex: 0,
      );

      expect(chunks[0].startTimestamp, DateTime(2025, 1, 15, 10, 0));
      expect(chunks[0].endTimestamp, DateTime(2025, 1, 15, 18, 0));
    });

    test('conversation metadata is populated from conversationMap', () {
      final messages = [
        _makeMsg(
          id: 'msg1',
          conversationId: 'conv1',
          timestamp: DateTime(2025, 1, 15, 12, 0),
        ),
      ];

      final chunks = VaultChunkBuilder.buildChunks(
        messages: messages,
        conversationMap: _makeConvMap({'conv1'}),
        startingIndex: 0,
      );

      final conv = chunks[0].conversations[0];
      expect(conv.recipientId, 'recipient_conv1');
      expect(conv.recipientUsername, 'user_conv1');
      expect(conv.recipientPublicKey, 'pk_conv1');
    });

    test('checksum is non-empty', () {
      final messages = [
        _makeMsg(
          id: 'msg1',
          conversationId: 'conv1',
          timestamp: DateTime(2025, 1, 15, 12, 0),
        ),
      ];

      final chunks = VaultChunkBuilder.buildChunks(
        messages: messages,
        conversationMap: _makeConvMap({'conv1'}),
        startingIndex: 0,
      );

      expect(chunks[0].checksum, isNotEmpty);
      expect(chunks[0].checksum.length, 64); // SHA-256 hex
    });

    test('large messages trigger size-based splitting', () {
      final base = DateTime(2025, 1, 15, 12, 0);
      // Each message: 200 + 10000*2 = 20200 bytes estimated
      // 120 messages * 20200 = 2,424,000 > 2MB (2,097,152)
      final messages = List.generate(
        120,
        (i) => _makeMsg(
          id: 'msg_$i',
          conversationId: 'conv1',
          timestamp: base.add(Duration(seconds: i)),
          content: 'x' * 10000,
        ),
      );

      final chunks = VaultChunkBuilder.buildChunks(
        messages: messages,
        conversationMap: _makeConvMap({'conv1'}),
        startingIndex: 0,
      );

      // Should split due to size before hitting 500 message limit
      expect(chunks.length, greaterThan(1));

      // All messages accounted for
      final totalMessages =
          chunks.fold(0, (sum, c) => sum + c.messageCount);
      expect(totalMessages, 120);
    });
  });
}
