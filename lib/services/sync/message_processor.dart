import 'dart:async';
import '../../models/local/conversation.dart';
import '../../models/local/message.dart';
import '../../repositories/message_dao.dart';
import '../../repositories/conversation_dao.dart';
import '../../repositories/blocked_user_dao.dart';
import '../crypto/protocol_service.dart';
import 'inbox_listener.dart';

class ProcessedMessage {
  final String messageId;
  final String senderId;
  final String conversationId;
  final String content;
  final DateTime timestamp;
  final LocalMessageType type;

  ProcessedMessage({
    required this.messageId,
    required this.senderId,
    required this.conversationId,
    required this.content,
    required this.timestamp,
    this.type = LocalMessageType.text,
  });
}

class MessageProcessor {
  final ProtocolService _protocol;
  final MessageDao _messageDao;
  final ConversationDao _conversationDao;
  final BlockedUserDao _blockedUserDao;
  final String _myUserId;

  MessageProcessor({
    required ProtocolService protocol,
    required MessageDao messageDao,
    required ConversationDao conversationDao,
    required BlockedUserDao blockedUserDao,
    required String myUserId,
  })  : _protocol = protocol,
        _messageDao = messageDao,
        _conversationDao = conversationDao,
        _blockedUserDao = blockedUserDao,
        _myUserId = myUserId;

  Future<ProcessedMessage?> processInboxMessage(InboxMessage inboxMessage) async {
    try {
      return await _processIncomingMessage(inboxMessage);
    } catch (e) {
      return null;
    }
  }

  Future<ProcessedMessage?> _processIncomingMessage(InboxMessage inboxMessage) async {
    final existing = await _messageDao.getById(inboxMessage.id);
    if (existing != null) {
      return ProcessedMessage(
        messageId: existing.id,
        senderId: existing.senderId,
        conversationId: existing.conversationId,
        content: existing.content,
        timestamp: existing.timestamp,
      );
    }

    final result = await _protocol.unsealEnvelope(
      envelope: inboxMessage.envelope,
      myUserId: _myUserId,
    );

    if (await _blockedUserDao.isBlocked(result.senderId)) {
      return null;
    }

    final conversationId = _getConversationId(result.senderId);

    final localMessage = LocalMessage(
      id: inboxMessage.id,
      conversationId: conversationId,
      senderId: result.senderId,
      senderUsername: '',
      content: result.plaintext,
      timestamp: inboxMessage.deliveredAt,
      type: LocalMessageType.text,
      status: LocalMessageStatus.delivered,
      isOutgoing: false,
      createdAt: DateTime.now(),
    );

    await _messageDao.transaction(() async {
      await _messageDao.insert(localMessage);
      await _updateConversation(
        conversationId: conversationId,
        partnerId: result.senderId,
        content: result.plaintext,
        timestamp: inboxMessage.deliveredAt,
      );
    });

    return ProcessedMessage(
      messageId: inboxMessage.id,
      senderId: result.senderId,
      conversationId: conversationId,
      content: result.plaintext,
      timestamp: inboxMessage.deliveredAt,
    );
  }

  Future<void> _updateConversation({
    required String conversationId,
    required String partnerId,
    required String content,
    required DateTime timestamp,
  }) async {
    final existing = await _conversationDao.getById(conversationId);

    if (existing != null) {
      await _conversationDao.updateLastMessage(
        conversationId: conversationId,
        content: _truncatePreview(content),
        timestamp: timestamp,
      );
      await _conversationDao.incrementUnreadCount(conversationId);
    } else {
      final now = DateTime.now();
      await _conversationDao.insert(LocalConversation(
        id: conversationId,
        recipientId: partnerId,
        recipientUsername: '',
        recipientPublicKey: '',
        lastMessageContent: _truncatePreview(content),
        lastMessageAt: timestamp,
        unreadCount: 1,
        createdAt: now,
        updatedAt: now,
      ));
    }
  }

  String _getConversationId(String partnerId) {
    final ids = [_myUserId, partnerId]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  String _truncatePreview(String content, {int maxLength = 100}) {
    if (content.length <= maxLength) return content;
    return '${content.substring(0, maxLength)}...';
  }
}
