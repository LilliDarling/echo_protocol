import 'dart:async';
import '../../models/local/message.dart';
import '../../repositories/message_dao.dart';
import '../../repositories/conversation_dao.dart';
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
  final String _myUserId;

  MessageProcessor({
    required ProtocolService protocol,
    required MessageDao messageDao,
    required ConversationDao conversationDao,
    required String myUserId,
  })  : _protocol = protocol,
        _messageDao = messageDao,
        _conversationDao = conversationDao,
        _myUserId = myUserId;

  Future<ProcessedMessage?> processInboxMessage(InboxMessage inboxMessage) async {
    try {
      if (inboxMessage.isOutgoing) {
        return await _processOutgoingMessage(inboxMessage);
      }
      return await _processIncomingMessage(inboxMessage);
    } catch (e) {
      return null;
    }
  }

  Future<ProcessedMessage?> _processIncomingMessage(InboxMessage inboxMessage) async {
    if (inboxMessage.envelope == null) return null;

    final result = await _protocol.unsealEnvelope(
      envelope: inboxMessage.envelope!,
      myUserId: _myUserId,
    );

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

    await _messageDao.insert(localMessage);

    await _updateConversation(
      conversationId: conversationId,
      senderId: result.senderId,
      content: result.plaintext,
      timestamp: inboxMessage.deliveredAt,
    );

    return ProcessedMessage(
      messageId: inboxMessage.id,
      senderId: result.senderId,
      conversationId: conversationId,
      content: result.plaintext,
      timestamp: inboxMessage.deliveredAt,
    );
  }

  Future<ProcessedMessage?> _processOutgoingMessage(InboxMessage inboxMessage) async {
    if (inboxMessage.senderPayload == null || inboxMessage.recipientId == null) {
      return null;
    }

    final plaintext = await _protocol.decryptFromSelf(
      encryptedPayload: inboxMessage.senderPayload!,
    );

    final conversationId = _getConversationId(inboxMessage.recipientId!);
    final messageId = inboxMessage.id.replaceAll('_out', '');

    final existing = await _messageDao.getById(messageId);
    if (existing != null) {
      return null;
    }

    final localMessage = LocalMessage(
      id: messageId,
      conversationId: conversationId,
      senderId: _myUserId,
      senderUsername: '',
      content: plaintext,
      timestamp: inboxMessage.deliveredAt,
      type: LocalMessageType.text,
      status: LocalMessageStatus.sent,
      isOutgoing: true,
      createdAt: DateTime.now(),
    );

    await _messageDao.insert(localMessage);

    await _updateConversation(
      conversationId: conversationId,
      senderId: _myUserId,
      content: plaintext,
      timestamp: inboxMessage.deliveredAt,
      isOutgoing: true,
    );

    return ProcessedMessage(
      messageId: messageId,
      senderId: _myUserId,
      conversationId: conversationId,
      content: plaintext,
      timestamp: inboxMessage.deliveredAt,
    );
  }

  Future<void> _updateConversation({
    required String conversationId,
    required String senderId,
    required String content,
    required DateTime timestamp,
    bool isOutgoing = false,
  }) async {
    final existing = await _conversationDao.getById(conversationId);

    if (existing != null) {
      await _conversationDao.updateLastMessage(
        conversationId: conversationId,
        content: _truncatePreview(content),
        timestamp: timestamp,
      );
      if (!isOutgoing) {
        await _conversationDao.incrementUnreadCount(conversationId);
      }
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
