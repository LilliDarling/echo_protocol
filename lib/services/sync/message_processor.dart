import 'dart:async';
import '../../models/local/message.dart';
import '../../repositories/message.dart';
import '../../repositories/conversation.dart';
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
  final MessageRepository _messageRepo;
  final ConversationRepository _conversationRepo;
  final String _myUserId;

  MessageProcessor({
    required ProtocolService protocol,
    required MessageRepository messageRepository,
    required ConversationRepository conversationRepository,
    required String myUserId,
  })  : _protocol = protocol,
        _messageRepo = messageRepository,
        _conversationRepo = conversationRepository,
        _myUserId = myUserId;

  Future<ProcessedMessage?> processInboxMessage(InboxMessage inboxMessage) async {
    try {
      final result = await _protocol.unsealEnvelope(
        envelope: inboxMessage.envelope,
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

      await _messageRepo.insert(localMessage);

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
    } catch (e) {
      return null;
    }
  }

  Future<void> _updateConversation({
    required String conversationId,
    required String senderId,
    required String content,
    required DateTime timestamp,
  }) async {
    final existing = await _conversationRepo.getById(conversationId);

    if (existing != null) {
      await _conversationRepo.updateLastMessage(
        conversationId: conversationId,
        content: _truncatePreview(content),
        timestamp: timestamp,
      );
      await _conversationRepo.incrementUnreadCount(conversationId);
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
