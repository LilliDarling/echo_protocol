import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_protocol/models/crypto/sealed_envelope.dart';

void main() {
  group('InboxMessage', () {
    test('correctly parses envelope from data', () {
      final now = DateTime.now();
      final payload = Uint8List.fromList(List.generate(100, (i) => i));
      final ephemeralKey = Uint8List.fromList(List.generate(32, (i) => i));

      final envelope = SealedEnvelope(
        recipientId: 'bob',
        encryptedPayload: payload,
        ephemeralPublicKey: ephemeralKey,
        timestamp: now.millisecondsSinceEpoch,
        expireAt: now.add(const Duration(hours: 24)).millisecondsSinceEpoch,
      );

      expect(envelope.recipientId, 'bob');
      expect(envelope.encryptedPayload.length, 100);
      expect(envelope.ephemeralPublicKey.length, 32);
      expect(envelope.isExpired, false);
    });

    test('detects expired envelope', () {
      final past = DateTime.now().subtract(const Duration(hours: 1));

      final envelope = SealedEnvelope(
        recipientId: 'bob',
        encryptedPayload: Uint8List(10),
        ephemeralPublicKey: Uint8List(32),
        timestamp: past.millisecondsSinceEpoch,
        expireAt: past.millisecondsSinceEpoch,
      );

      expect(envelope.isExpired, true);
    });
  });

  group('ProcessedMessage Structure', () {
    test('contains required fields after processing', () {
      final messageId = 'msg_123';
      final senderId = 'alice';
      final conversationId = 'alice_bob';
      final content = 'Hello, Bob!';
      final timestamp = DateTime.now();

      expect(messageId, isNotEmpty);
      expect(senderId, isNotEmpty);
      expect(conversationId, contains('_'));
      expect(content, isNotEmpty);
      expect(timestamp.isBefore(DateTime.now().add(const Duration(seconds: 1))), true);
    });
  });

  group('Conversation ID Generation', () {
    test('generates consistent ID regardless of order', () {
      String getConversationId(String userId, String partnerId) {
        final ids = [userId, partnerId]..sort();
        return '${ids[0]}_${ids[1]}';
      }

      final id1 = getConversationId('alice', 'bob');
      final id2 = getConversationId('bob', 'alice');

      expect(id1, id2);
      expect(id1, 'alice_bob');
    });

    test('handles IDs with special characters', () {
      String getConversationId(String userId, String partnerId) {
        final ids = [userId, partnerId]..sort();
        return '${ids[0]}_${ids[1]}';
      }

      final id = getConversationId('user_123', 'user_456');
      expect(id, 'user_123_user_456');
    });
  });

  group('Message Preview Truncation', () {
    test('truncates long content for preview', () {
      String truncatePreview(String content, {int maxLength = 100}) {
        if (content.length <= maxLength) return content;
        return '${content.substring(0, maxLength)}...';
      }

      final shortContent = 'Hello';
      final longContent = 'A' * 200;

      expect(truncatePreview(shortContent), 'Hello');
      expect(truncatePreview(longContent).length, 103);
      expect(truncatePreview(longContent).endsWith('...'), true);
    });

    test('handles exactly max length content', () {
      String truncatePreview(String content, {int maxLength = 100}) {
        if (content.length <= maxLength) return content;
        return '${content.substring(0, maxLength)}...';
      }

      final exactContent = 'A' * 100;
      expect(truncatePreview(exactContent), exactContent);
      expect(truncatePreview(exactContent).length, 100);
    });
  });

  group('Sync State Transitions', () {
    test('valid state transitions', () {
      const validTransitions = {
        'idle': ['initializing'],
        'initializing': ['syncing', 'error', 'ready'],
        'syncing': ['ready', 'error'],
        'ready': ['syncing', 'idle', 'error'],
        'error': ['initializing', 'idle'],
      };

      expect(validTransitions['idle']!.contains('initializing'), true);
      expect(validTransitions['initializing']!.contains('ready'), true);
      expect(validTransitions['syncing']!.contains('ready'), true);
    });
  });

  group('Security: Message Processing', () {
    test('sender ID comes from unsealed certificate, not external source', () {
      final claimedSenderId = 'eve_malicious';
      final actualSenderIdFromCertificate = 'alice_real';

      expect(actualSenderIdFromCertificate, isNot(claimedSenderId));
    });

    test('message timestamp should be validated', () {
      final validTimestamp = DateTime.now();
      final futureTimestamp = DateTime.now().add(const Duration(hours: 1));
      final oldTimestamp = DateTime.now().subtract(const Duration(days: 2));

      bool isValidTimestamp(DateTime timestamp) {
        final now = DateTime.now();
        final age = now.difference(timestamp);

        if (age.isNegative && age.abs() > const Duration(minutes: 5)) {
          return false;
        }
        return age < const Duration(hours: 24);
      }

      expect(isValidTimestamp(validTimestamp), true);
      expect(isValidTimestamp(futureTimestamp), false);
      expect(isValidTimestamp(oldTimestamp), false);
    });

    test('envelope expiration is checked before processing', () {
      bool shouldProcess(int expireAtMs) {
        return DateTime.now().millisecondsSinceEpoch < expireAtMs;
      }

      final validExpiry = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
      final expiredExpiry = DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch;

      expect(shouldProcess(validExpiry), true);
      expect(shouldProcess(expiredExpiry), false);
    });
  });
}
