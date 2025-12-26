import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:mockito/annotations.dart';
import 'package:echo_protocol/services/replay_protection.dart';
import 'package:echo_protocol/utils/security.dart';

@GenerateMocks([FirebaseFunctions])
import 'replay_protection_test.mocks.dart';

void main() {
  group('ReplayProtectionService', () {
    late ReplayProtectionService replayProtection;
    late FakeFirebaseFirestore fakeFirestore;
    late MockFirebaseFunctions mockFunctions;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      mockFunctions = MockFirebaseFunctions();
      replayProtection = ReplayProtectionService(
        userId: 'test-user',
        firestore: fakeFirestore,
        functions: mockFunctions,
      );
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
      expect(seq1B, equals(1));
      expect(seq2A, equals(2));
    });

    test('conversation ID is bidirectional (alice-bob == bob-alice)', () async {
      final seqAB = await replayProtection.getNextSequenceNumber('alice', 'bob');
      final seqBA = await replayProtection.getNextSequenceNumber('bob', 'alice');

      expect(seqAB, equals(1));
      expect(seqBA, equals(2));
    });

    test('isNonceValid rejects duplicate nonces (replay attack)', () async {
      final now = DateTime.now();
      final messageId = 'msg-123';

      final valid1 = await replayProtection.isNonceValid(messageId, now);
      expect(valid1, isTrue);

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

      final valid1 = await replayProtection.validateMessage(
        messageId: 'msg-1',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 1,
        timestamp: now,
      );
      expect(valid1, isTrue);

      final valid2 = await replayProtection.validateMessage(
        messageId: 'msg-1',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 2,
        timestamp: now,
      );
      expect(valid2, isFalse);
    });

    test('validateMessage rejects non-advancing sequence numbers', () async {
      final now = DateTime.now();

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

      final valid = await replayProtection.validateMessage(
        messageId: 'msg-3',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 1,
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

    test('resetConversation clears sequence state', () async {
      await replayProtection.getNextSequenceNumber('alice', 'bob');
      await replayProtection.getNextSequenceNumber('alice', 'bob');
      final lastSeq = await replayProtection.getLastSequenceNumber('alice', 'bob');
      expect(lastSeq, equals(2));

      await replayProtection.resetConversation('alice', 'bob');

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
      expect(SecurityUtils.isSequenceValid(1, 1), isFalse);
      expect(SecurityUtils.isSequenceValid(1, 2), isFalse);
      expect(SecurityUtils.isSequenceValid(5, 10), isFalse);
    });

    test('isMessageValid checks timestamp and sequence', () {
      final now = DateTime.now();

      expect(
        SecurityUtils.isMessageValid(
          timestamp: now,
          sequenceNumber: 2,
          lastSequenceNumber: 1,
        ),
        isTrue,
      );

      expect(
        SecurityUtils.isMessageValid(
          timestamp: now.subtract(const Duration(hours: 2)),
          sequenceNumber: 2,
          lastSequenceNumber: 1,
        ),
        isFalse,
      );

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

      expect(
        SecurityUtils.isMessageValid(
          timestamp: timestamp,
          sequenceNumber: 2,
          lastSequenceNumber: 1,
        ),
        isTrue,
      );

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
    late FakeFirebaseFirestore fakeFirestore;
    late MockFirebaseFunctions mockFunctions;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      mockFunctions = MockFirebaseFunctions();
      replayProtection = ReplayProtectionService(
        userId: 'test-user',
        firestore: fakeFirestore,
        functions: mockFunctions,
      );
    });

    test('scenario: attacker intercepts and replays message', () async {
      final now = DateTime.now();

      final legitimate = await replayProtection.validateMessage(
        messageId: 'msg-original',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 1,
        timestamp: now,
      );
      expect(legitimate, isTrue);

      final replay = await replayProtection.validateMessage(
        messageId: 'msg-original',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 1,
        timestamp: now,
      );
      expect(replay, isFalse, reason: 'Replay attack should be detected');
    });

    test('scenario: attacker tries to reorder messages', () async {
      final now = DateTime.now();

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

      final reordered = await replayProtection.validateMessage(
        messageId: 'msg-2-replayed',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 2,
        timestamp: now,
      );

      expect(reordered, isFalse, reason: 'Out-of-order message should be rejected');
    });

    test('scenario: attacker crafts new message with old sequence', () async {
      final now = DateTime.now();

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

      final crafted = await replayProtection.validateMessage(
        messageId: 'msg-crafted',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 1,
        timestamp: now,
      );

      expect(crafted, isFalse, reason: 'Message with old sequence should be rejected');
    });

    test('scenario: attacker delays message beyond time window', () async {
      final old = DateTime.now().subtract(const Duration(hours: 2));

      final delayed = await replayProtection.validateMessage(
        messageId: 'msg-delayed',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 1,
        timestamp: old,
      );

      expect(delayed, isFalse, reason: 'Message outside time window should be rejected');
    });

    test('scenario: cross-device sync prevents replay on new device', () async {
      final now = DateTime.now();

      final device1 = ReplayProtectionService(
        userId: 'bob',
        firestore: fakeFirestore,
        functions: mockFunctions,
      );
      await device1.validateMessage(
        messageId: 'msg-1',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 1,
        timestamp: now,
      );

      final device2 = ReplayProtectionService(
        userId: 'bob',
        firestore: fakeFirestore,
        functions: mockFunctions,
      );
      final replayOnNewDevice = await device2.validateMessage(
        messageId: 'msg-1',
        senderId: 'alice',
        recipientId: 'bob',
        sequenceNumber: 1,
        timestamp: now,
      );

      expect(replayOnNewDevice, isFalse, reason: 'Replay on new device should be blocked via Firestore sync');
    });
  });
}
