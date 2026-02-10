import 'package:flutter_test/flutter_test.dart';
import 'package:echo_protocol/models/local/message.dart';
import 'package:echo_protocol/models/local/conversation.dart';
import 'package:echo_protocol/models/local/blocked_user.dart';

void main() {
  group('LocalMessage', () {
    test('serializes and deserializes correctly', () {
      final now = DateTime.now();
      final message = LocalMessage(
        id: 'msg123',
        conversationId: 'conv456',
        senderId: 'user789',
        senderUsername: 'alice',
        content: 'Hello, world!',
        timestamp: now,
        type: LocalMessageType.text,
        status: LocalMessageStatus.sent,
        mediaId: 'media001',
        mediaKey: 'key123',
        thumbnailPath: '/path/to/thumb.jpg',
        isOutgoing: true,
        createdAt: now,
        syncedToVault: false,
      );

      final map = message.toMap();
      final restored = LocalMessage.fromMap(map);

      expect(restored.id, message.id);
      expect(restored.conversationId, message.conversationId);
      expect(restored.senderId, message.senderId);
      expect(restored.senderUsername, message.senderUsername);
      expect(restored.content, message.content);
      expect(restored.type, message.type);
      expect(restored.status, message.status);
      expect(restored.mediaId, message.mediaId);
      expect(restored.mediaKey, message.mediaKey);
      expect(restored.thumbnailPath, message.thumbnailPath);
      expect(restored.isOutgoing, message.isOutgoing);
      expect(restored.syncedToVault, message.syncedToVault);
    });

    test('handles all message types', () {
      for (final type in LocalMessageType.values) {
        final message = LocalMessage(
          id: 'msg',
          conversationId: 'conv',
          senderId: 'user',
          senderUsername: 'name',
          content: 'content',
          timestamp: DateTime.now(),
          type: type,
          status: LocalMessageStatus.sent,
          isOutgoing: true,
          createdAt: DateTime.now(),
        );

        final map = message.toMap();
        final restored = LocalMessage.fromMap(map);

        expect(restored.type, type);
      }
    });

    test('handles all message statuses', () {
      for (final status in LocalMessageStatus.values) {
        final message = LocalMessage(
          id: 'msg',
          conversationId: 'conv',
          senderId: 'user',
          senderUsername: 'name',
          content: 'content',
          timestamp: DateTime.now(),
          type: LocalMessageType.text,
          status: status,
          isOutgoing: true,
          createdAt: DateTime.now(),
        );

        final map = message.toMap();
        final restored = LocalMessage.fromMap(map);

        expect(restored.status, status);
      }
    });

    test('handles null optional fields', () {
      final message = LocalMessage(
        id: 'msg',
        conversationId: 'conv',
        senderId: 'user',
        senderUsername: 'name',
        content: 'content',
        timestamp: DateTime.now(),
        isOutgoing: false,
        createdAt: DateTime.now(),
      );

      final map = message.toMap();
      final restored = LocalMessage.fromMap(map);

      expect(restored.mediaId, isNull);
      expect(restored.mediaKey, isNull);
      expect(restored.thumbnailPath, isNull);
    });

    test('copyWith preserves unchanged fields', () {
      final original = LocalMessage(
        id: 'msg',
        conversationId: 'conv',
        senderId: 'user',
        senderUsername: 'name',
        content: 'original content',
        timestamp: DateTime.now(),
        status: LocalMessageStatus.pending,
        isOutgoing: true,
        createdAt: DateTime.now(),
      );

      final updated = original.copyWith(
        status: LocalMessageStatus.sent,
        content: 'updated content',
      );

      expect(updated.id, original.id);
      expect(updated.conversationId, original.conversationId);
      expect(updated.senderId, original.senderId);
      expect(updated.status, LocalMessageStatus.sent);
      expect(updated.content, 'updated content');
    });

    test('fromString handles unknown type gracefully', () {
      final type = LocalMessageType.fromString('unknown_type');
      expect(type, LocalMessageType.text);
    });

    test('fromString handles unknown status gracefully', () {
      final status = LocalMessageStatus.fromString('unknown_status');
      expect(status, LocalMessageStatus.sent);
    });
  });

  group('LocalConversation', () {
    test('serializes and deserializes correctly', () {
      final now = DateTime.now();
      final conversation = LocalConversation(
        id: 'conv123',
        recipientId: 'user456',
        recipientUsername: 'bob',
        recipientPublicKey: 'publickey123',
        lastMessageContent: 'Hello!',
        lastMessageAt: now,
        unreadCount: 5,
        createdAt: now,
        updatedAt: now,
      );

      final map = conversation.toMap();
      final restored = LocalConversation.fromMap(map);

      expect(restored.id, conversation.id);
      expect(restored.recipientId, conversation.recipientId);
      expect(restored.recipientUsername, conversation.recipientUsername);
      expect(restored.recipientPublicKey, conversation.recipientPublicKey);
      expect(restored.lastMessageContent, conversation.lastMessageContent);
      expect(restored.unreadCount, conversation.unreadCount);
    });

    test('handles null lastMessage fields', () {
      final now = DateTime.now();
      final conversation = LocalConversation(
        id: 'conv123',
        recipientId: 'user456',
        recipientUsername: 'bob',
        recipientPublicKey: 'publickey123',
        createdAt: now,
        updatedAt: now,
      );

      final map = conversation.toMap();
      final restored = LocalConversation.fromMap(map);

      expect(restored.lastMessageContent, isNull);
      expect(restored.lastMessageAt, isNull);
      expect(restored.unreadCount, 0);
    });

    test('copyWith preserves unchanged fields', () {
      final now = DateTime.now();
      final original = LocalConversation(
        id: 'conv123',
        recipientId: 'user456',
        recipientUsername: 'bob',
        recipientPublicKey: 'key',
        unreadCount: 0,
        createdAt: now,
        updatedAt: now,
      );

      final updated = original.copyWith(
        unreadCount: 10,
        lastMessageContent: 'New message',
      );

      expect(updated.id, original.id);
      expect(updated.recipientId, original.recipientId);
      expect(updated.unreadCount, 10);
      expect(updated.lastMessageContent, 'New message');
    });
  });

  group('LocalBlockedUser', () {
    test('serializes and deserializes correctly', () {
      final now = DateTime.now();
      final blocked = LocalBlockedUser(
        userId: 'user123',
        blockedAt: now,
        reason: 'Spam',
      );

      final map = blocked.toMap();
      final restored = LocalBlockedUser.fromMap(map);

      expect(restored.userId, blocked.userId);
      expect(restored.reason, blocked.reason);
    });

    test('handles null reason', () {
      final blocked = LocalBlockedUser(
        userId: 'user123',
        blockedAt: DateTime.now(),
      );

      final map = blocked.toMap();
      final restored = LocalBlockedUser.fromMap(map);

      expect(restored.userId, 'user123');
      expect(restored.reason, isNull);
    });
  });

  group('Database Schema Security', () {
    test('message content is stored as plaintext in local DB (intended)', () {
      final message = LocalMessage(
        id: 'msg',
        conversationId: 'conv',
        senderId: 'user',
        senderUsername: 'name',
        content: 'This is decrypted plaintext',
        timestamp: DateTime.now(),
        isOutgoing: true,
        createdAt: DateTime.now(),
      );

      final map = message.toMap();

      expect(map['content'], 'This is decrypted plaintext');
    });

    test('boolean fields serialize as integers for SQLite', () {
      final message = LocalMessage(
        id: 'msg',
        conversationId: 'conv',
        senderId: 'user',
        senderUsername: 'name',
        content: 'content',
        timestamp: DateTime.now(),
        isOutgoing: true,
        syncedToVault: true,
        createdAt: DateTime.now(),
      );

      final map = message.toMap();

      expect(map['is_outgoing'], 1);
      expect(map['synced_to_vault'], 1);

      final messageOut = LocalMessage(
        id: 'msg',
        conversationId: 'conv',
        senderId: 'user',
        senderUsername: 'name',
        content: 'content',
        timestamp: DateTime.now(),
        isOutgoing: false,
        syncedToVault: false,
        createdAt: DateTime.now(),
      );

      final mapOut = messageOut.toMap();

      expect(mapOut['is_outgoing'], 0);
      expect(mapOut['synced_to_vault'], 0);
    });

    test('timestamps serialize as milliseconds for SQLite', () {
      final timestamp = DateTime(2024, 1, 15, 12, 30, 45);
      final message = LocalMessage(
        id: 'msg',
        conversationId: 'conv',
        senderId: 'user',
        senderUsername: 'name',
        content: 'content',
        timestamp: timestamp,
        isOutgoing: true,
        createdAt: timestamp,
      );

      final map = message.toMap();

      expect(map['timestamp'], timestamp.millisecondsSinceEpoch);
      expect(map['created_at'], timestamp.millisecondsSinceEpoch);
    });
  });
}
