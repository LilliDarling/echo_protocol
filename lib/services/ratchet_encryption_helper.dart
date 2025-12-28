import '../models/echo.dart';
import 'crypto/protocol_service.dart';
import 'message_rate_limiter.dart';

class RatchetEncryptionHelper {
  final ProtocolService _protocolService;
  final MessageRateLimiter? _rateLimiter;

  RatchetEncryptionHelper({
    ProtocolService? protocolService,
    MessageRateLimiter? rateLimiter,
  })  : _protocolService = protocolService ?? ProtocolService(),
        _rateLimiter = rateLimiter;

  Future<Map<String, dynamic>> encryptMessage({
    required String plaintext,
    required String partnerId,
    required String senderId,
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

    return _protocolService.encryptForSending(
      plaintext: plaintext,
      recipientId: partnerId,
      senderId: senderId,
    );
  }

  Future<String> decryptMessage({
    required EchoModel message,
    required String myUserId,
    required String partnerId,
  }) async {
    return _protocolService.decryptMessage(
      encryptedContent: message.content,
      senderId: message.senderId,
      myUserId: myUserId,
    );
  }

  Future<String?> getMyFingerprint() async {
    return _protocolService.getFingerprint();
  }

  Future<String?> getPartnerFingerprint(String partnerId) async {
    return _protocolService.getPartnerFingerprint(partnerId);
  }

  Future<bool> hasSession(String partnerId, String myUserId) async {
    return _protocolService.hasActiveSession(partnerId, myUserId);
  }
}
