import 'dart:typed_data';
import '../models/echo.dart';
import '../models/crypto/sealed_envelope.dart';
import 'crypto/protocol_service.dart';
import 'replay_protection.dart';
import 'message_rate_limiter.dart';

class MessageEncryptionHelper {
  final ProtocolService _protocolService;
  final ReplayProtectionService? _replayProtection;
  final MessageRateLimiter? _rateLimiter;

  MessageEncryptionHelper({
    ProtocolService? protocolService,
    ReplayProtectionService? replayProtection,
    MessageRateLimiter? rateLimiter,
  })  : _protocolService = protocolService ?? ProtocolService(),
        _replayProtection = replayProtection,
        _rateLimiter = rateLimiter;

  Future<Map<String, dynamic>> encryptMessage({
    required String plaintext,
    required String partnerId,
    required String senderId,
    int senderKeyVersion = 1,
    int recipientKeyVersion = 1,
  }) async {
    if (_rateLimiter != null) {
      final delay = await _rateLimiter.checkRateLimit(
        userId: senderId,
        partnerId: partnerId,
      );

      if (delay > Duration.zero) {
        await Future.delayed(delay);
      }

      _rateLimiter.recordAttempt(
        userId: senderId,
        partnerId: partnerId,
      );
    }

    final result = await _protocolService.encryptForSending(
      plaintext: plaintext,
      recipientId: partnerId,
      senderId: senderId,
    );

    int sequenceNumber = 0;
    if (_replayProtection != null) {
      sequenceNumber = await _replayProtection.getNextSequenceNumber(senderId, partnerId);
    }

    return {
      'content': result['content'],
      'encryptionVersion': result['encryptionVersion'],
      'sequenceNumber': sequenceNumber,
      'senderKeyVersion': result['senderKeyVersion'] ?? senderKeyVersion,
      'recipientKeyVersion': result['recipientKeyVersion'] ?? recipientKeyVersion,
    };
  }

  Future<String> decryptMessage({
    required EchoModel message,
    required String myUserId,
    required String partnerId,
    bool skipReplayValidation = false,
  }) async {
    if (_replayProtection != null && !skipReplayValidation && message.recipientId == myUserId) {
      await _replayProtection.validateMessage(
        messageId: message.id,
        senderId: message.senderId,
        recipientId: message.recipientId,
        sequenceNumber: message.sequenceNumber,
        timestamp: message.timestamp,
      );
    }

    return _protocolService.decryptMessage(
      encryptedContent: message.content,
      senderId: message.senderId,
      myUserId: myUserId,
    );
  }

  Future<SealedEnvelope> createSealedEnvelope({
    required String plaintext,
    required String senderId,
    required String recipientId,
    required Uint8List recipientPublicKey,
  }) async {
    if (_rateLimiter != null) {
      final delay = await _rateLimiter.checkRateLimit(
        userId: senderId,
        partnerId: recipientId,
      );

      if (delay > Duration.zero) {
        await Future.delayed(delay);
      }

      _rateLimiter.recordAttempt(
        userId: senderId,
        partnerId: recipientId,
      );
    }

    return _protocolService.sealEnvelope(
      plaintext: plaintext,
      senderId: senderId,
      recipientId: recipientId,
      recipientPublicKey: recipientPublicKey,
    );
  }

  Future<({String senderId, String plaintext})> openSealedEnvelope({
    required SealedEnvelope envelope,
    required String myUserId,
  }) async {
    if (envelope.isExpired) {
      throw Exception('Envelope has expired');
    }

    return _protocolService.unsealEnvelope(
      envelope: envelope,
      myUserId: myUserId,
    );
  }
}
