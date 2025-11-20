import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:echo_protocol/services/replay_protection_service.dart';
import 'package:echo_protocol/utils/security.dart';

void main() {
  group('ReplayProtectionService', () {
    late ReplayProtectionService replayProtection;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      replayProtection = ReplayProtectionService(prefs);
    });

    test('getNextSequenceNumber increments correctly', () async {
      final seq1 = await replayProtection.getNextSequenceNumber('user1', 'user2');
      final seq2 = await replayProtection.getNextSequenceNumber('user1', 'user2');
      final seq3 = await replayProtection.getNextSequenceNumber('user1', 'user2');

      expect(seq1, equals(1));
      expect(seq2, equals(2));
      expect(seq3, equals(3));
    });

    test('sequence numbers are independent per conversation', () async {
      final seq1A = await replayProtection.getNextSequenceNumber('alice', 'bob');
      final seq1B = await replayProtection.getNextSequenceNumber('alice', 'charlie');
      final seq2A = await replayProtection.getNextSequenceNumber('alice', 'bob');

      expect(seq1A, equals(1));
      expect(seq1B, equals(1)); // Different conversation, starts at 1
      expect(seq2A, equals(2));
    });

    test('conversation ID is bidirectional (alice-bob == bob-alice)', () async {
      final seqAB = await replayProtection.getNextSequenceNumber('alice', 'bob');
      final seqBA = await replayProtection.getNextSequenceNumber('bob', 'alice');

      // Both should be 1 and 2 because they're the same conversation
      expect(seqAB, equals(1));
      expect(seqBA, equals(2));
    });

    test('isNonceValid rejects duplicate nonces (replay attack)', () async {
      final now = DateTime.now();
      final messageId = 'msg-123';

      // First time - should be valid
      final valid1 = await replayProtection.isNonceValid(messageId, now);
      expect(valid1, isTrue);

      // Second time with same ID - should be invalid (replay)
      final valid2 = await replayProtection.isNonceValid(messageId, now);
      expect(valid2, isFalse);
    });

    test('isNonceValid rejects messages outside time window', () async {
      final tooOld = DateTime.now().subtract(const Duration(hours: 2));
      final tooFuture = DateTime.now().add(const Duration(minutes: 5));

      final validOld = await replayProtection.isNonceValid('msg-old', tooOld);
      final validFuture = await replayProtection.isNonceValid('msg-future', tooFuture);

      expect(validOld, isFalse);
      expect(validFuture, isFalse);
    });

    test('isNonceValid accepts messages within time window', () async {
      final recent = DateTime.now().subtract(const Duration(minutes: 30));
      final valid = await replayProtection.isNonceValid('msg-recent', recent);

      expect(valid, isTrue);
    });

    test('validateMessage rejects duplicate messages', () async {
      final now = DateTime.now();

      // First message
      final valid1 = await replayProtection.validateMessage(
        messageId: 'msg-1',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 1,
        timestamp: now,
      );
      expect(valid1, isTrue);

      // Replay attack - same message ID
      final valid2 = await replayProtection.validateMessage(
        messageId: 'msg-1', // Same ID
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 2,
        timestamp: now,
      );
      expect(valid2, isFalse);
    });

    test('validateMessage rejects non-advancing sequence numbers', () async {
      final now = DateTime.now();

      // Send messages in order
      await replayProtection.validateMessage(
        messageId: 'msg-1',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 1,
        timestamp: now,
      );

      await replayProtection.validateMessage(
        messageId: 'msg-2',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 2,
        timestamp: now,
      );

      // Try to send old sequence number (replay or out-of-order)
      final valid = await replayProtection.validateMessage(
        messageId: 'msg-3',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 1, // Old sequence
        timestamp: now,
      );

      expect(valid, isFalse);
    });

    test('validateMessage accepts valid sequence progression', () async {
      final now = DateTime.now();

      for (int i = 1; i <= 5; i++) {
        final valid = await replayProtection.validateMessage(
          messageId: 'msg-$i',
          senderId: 'alice',
          recipientId: 'bob',
          sequenceNumber: i,
          timestamp: now,
        );
        expect(valid, isTrue, reason: 'Sequence $i should be valid');
      }
    });

    test('cleanupExpiredNonces removes old nonces', () async {
      final old = DateTime.now().subtract(const Duration(hours: 2));
      final recent = DateTime.now();

      // Add old and recent nonces
      await replayProtection.isNonceValid('msg-old', old);
      await replayProtection.isNonceValid('msg-recent', recent);

      // Clean up
      await replayProtection.cleanupExpiredNonces();

      // Old nonce should be gone, can be reused
      final validOld = await replayProtection.isNonceValid('msg-old', DateTime.now());
      expect(validOld, isTrue); // Can reuse because it was cleaned up

      // Recent nonce should still exist, cannot be reused
      final validRecent = await replayProtection.isNonceValid('msg-recent', DateTime.now());
      expect(validRecent, isFalse); // Still tracked
    });

    test('resetConversation clears sequence state', () async {
      // Build up sequence
      await replayProtection.getNextSequenceNumber('alice', 'bob');
      await replayProtection.getNextSequenceNumber('alice', 'bob');
      final lastSeq = await replayProtection.getLastSequenceNumber('alice', 'bob');
      expect(lastSeq, equals(2));

      // Reset
      await replayProtection.resetConversation('alice', 'bob');

      // Should start from 0 again
      final newSeq = await replayProtection.getLastSequenceNumber('alice', 'bob');
      expect(newSeq, equals(0));
    });
  });

  group('SecurityUtils sequence validation', () {
    test('isSequenceValid accepts advancing sequences', () {
      expect(SecurityUtils.isSequenceValid(2, 1), isTrue);
      expect(SecurityUtils.isSequenceValid(100, 99), isTrue);
      expect(SecurityUtils.isSequenceValid(1, 0), isTrue);
    });

    test('isSequenceValid rejects non-advancing sequences', () {
      expect(SecurityUtils.isSequenceValid(1, 1), isFalse); // Equal
      expect(SecurityUtils.isSequenceValid(1, 2), isFalse); // Going backwards
      expect(SecurityUtils.isSequenceValid(5, 10), isFalse);
    });

    test('isMessageValid checks timestamp and sequence', () {
      final now = DateTime.now();

      // Valid message
      expect(
        SecurityUtils.isMessageValid(
          timestamp: now,
          sequenceNumber: 2,
          lastSequenceNumber: 1,
        ),
        isTrue,
      );

      // Invalid timestamp (too old)
      expect(
        SecurityUtils.isMessageValid(
          timestamp: now.subtract(const Duration(hours: 2)),
          sequenceNumber: 2,
          lastSequenceNumber: 1,
        ),
        isFalse,
      );

      // Invalid sequence (not advancing)
      expect(
        SecurityUtils.isMessageValid(
          timestamp: now,
          sequenceNumber: 1,
          lastSequenceNumber: 1,
        ),
        isFalse,
      );
    });

    test('isMessageValid respects custom maxAge', () {
      final timestamp = DateTime.now().subtract(const Duration(minutes: 45));

      // Should fail with default 1 hour window (but this is within it)
      expect(
        SecurityUtils.isMessageValid(
          timestamp: timestamp,
          sequenceNumber: 2,
          lastSequenceNumber: 1,
        ),
        isTrue,
      );

      // Should fail with 30 minute window
      expect(
        SecurityUtils.isMessageValid(
          timestamp: timestamp,
          sequenceNumber: 2,
          lastSequenceNumber: 1,
          maxAge: const Duration(minutes: 30),
        ),
        isFalse,
      );
    });
  });

  group('Replay attack scenarios', () {
    late ReplayProtectionService replayProtection;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      replayProtection = ReplayProtectionService(prefs);
    });

    test('scenario: attacker intercepts and replays message', () async {
      final now = DateTime.now();

      // Alice sends legitimate message
      final legitimate = await replayProtection.validateMessage(
        messageId: 'msg-original',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 1,
        timestamp: now,
      );
      expect(legitimate, isTrue);

      // Attacker intercepts and tries to replay exact message
      final replay = await replayProtection.validateMessage(
        messageId: 'msg-original', // Same ID
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 1,
        timestamp: now,
      );
      expect(replay, isFalse, reason: 'Replay attack should be detected');
    });

    test('scenario: attacker tries to reorder messages', () async {
      final now = DateTime.now();

      // Alice sends messages 1, 2, 3
      await replayProtection.validateMessage(
        messageId: 'msg-1',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 1,
        timestamp: now,
      );

      await replayProtection.validateMessage(
        messageId: 'msg-2',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 2,
        timestamp: now,
      );

      await replayProtection.validateMessage(
        messageId: 'msg-3',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 3,
        timestamp: now,
      );

      // Attacker tries to deliver message 2 again (reorder attack)
      final reordered = await replayProtection.validateMessage(
        messageId: 'msg-2-replayed',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 2, // Old sequence number
        timestamp: now,
      );

      expect(reordered, isFalse, reason: 'Out-of-order message should be rejected');
    });

    test('scenario: attacker crafts new message with old sequence', () async {
      final now = DateTime.now();

      // Legitimate message flow
      await replayProtection.validateMessage(
        messageId: 'msg-1',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 1,
        timestamp: now,
      );

      await replayProtection.validateMessage(
        messageId: 'msg-2',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 2,
        timestamp: now,
      );

      // Attacker crafts new message with old sequence number
      final crafted = await replayProtection.validateMessage(
        messageId: 'msg-crafted', // New ID
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 1, // Old sequence
        timestamp: now,
      );

      expect(crafted, isFalse, reason: 'Message with old sequence should be rejected');
    });

    test('scenario: attacker delays message beyond time window', () async {
      final old = DateTime.now().subtract(const Duration(hours: 2));

      // Attacker delivers old intercepted message
      final delayed = await replayProtection.validateMessage(
        messageId: 'msg-delayed',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 1,
        timestamp: old,
      );

      expect(delayed, isFalse, reason: 'Message outside time window should be rejected');
    });
  });
}
