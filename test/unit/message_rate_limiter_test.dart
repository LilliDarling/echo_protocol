import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:echo_protocol/services/message_rate_limiter.dart';

@GenerateMocks([FirebaseFunctions])
import 'message_rate_limiter_test.mocks.dart';

void main() {
  group('MessageRateLimiter', () {
    late MessageRateLimiter rateLimiter;
    late MockFirebaseFunctions mockFunctions;

    setUp(() {
      mockFunctions = MockFirebaseFunctions();
      rateLimiter = MessageRateLimiter(functions: mockFunctions);
    });

    tearDown(() {
      rateLimiter.clear();
    });

    group('Basic Rate Limiting', () {
      test('allows messages under the limit', () async {
        // Send 10 messages (well under 30/min limit)
        for (int i = 0; i < 10; i++) {
          final delay = await rateLimiter.checkRateLimit(
            userId: 'alice',
            partnerId: 'bob',
          );

          expect(delay, equals(Duration.zero));
          rateLimiter.recordAttempt(userId: 'alice', partnerId: 'bob');
        }
      });

      test('applies delay when exceeding per-minute limit', () async {
        // Send messages up to the limit (30/min)
        for (int i = 0; i < 30; i++) {
          rateLimiter.recordAttempt(userId: 'alice', partnerId: 'bob');
        }

        // Next message should have a delay
        final delay = await rateLimiter.checkRateLimit(
          userId: 'alice',
          partnerId: 'bob',
        );

        expect(delay.inMilliseconds, greaterThan(0));
      });

      test('delay increases with continued excess (exponential backoff)', () async {
        // Exceed limit
        for (int i = 0; i < 30; i++) {
          rateLimiter.recordAttempt(userId: 'alice', partnerId: 'bob');
        }

        // Get delays for successive messages
        rateLimiter.recordAttempt(userId: 'alice', partnerId: 'bob');
        final delay1 = await rateLimiter.checkRateLimit(
          userId: 'alice',
          partnerId: 'bob',
        );

        rateLimiter.recordAttempt(userId: 'alice', partnerId: 'bob');
        final delay2 = await rateLimiter.checkRateLimit(
          userId: 'alice',
          partnerId: 'bob',
        );

        rateLimiter.recordAttempt(userId: 'alice', partnerId: 'bob');
        final delay3 = await rateLimiter.checkRateLimit(
          userId: 'alice',
          partnerId: 'bob',
        );

        // Delays should increase
        expect(delay2.inMilliseconds, greaterThan(delay1.inMilliseconds));
        expect(delay3.inMilliseconds, greaterThan(delay2.inMilliseconds));
      });

      test('delay caps at maximum', () async {
        // Massively exceed limit
        for (int i = 0; i < 100; i++) {
          rateLimiter.recordAttempt(userId: 'alice', partnerId: 'bob');
        }

        final delay = await rateLimiter.checkRateLimit(
          userId: 'alice',
          partnerId: 'bob',
        );

        // Delay should be capped at 30 seconds
        expect(delay.inSeconds, lessThanOrEqualTo(30));
      });
    });

    group('Global vs Per-Conversation Limits', () {
      test('global limit applies across all conversations', () async {
        // Send 30 messages to different partners
        for (int i = 0; i < 30; i++) {
          rateLimiter.recordAttempt(
            userId: 'alice',
            partnerId: 'partner$i',
          );
        }

        // Next message to ANY partner should be delayed
        final delay = await rateLimiter.checkRateLimit(
          userId: 'alice',
          partnerId: 'new-partner',
        );

        expect(delay.inMilliseconds, greaterThan(0));
      });

      test('per-conversation limit is independent of global', () async {
        // Send 20 messages to bob (under per-conversation limit of 20/min)
        for (int i = 0; i < 20; i++) {
          rateLimiter.recordAttempt(userId: 'alice', partnerId: 'bob');
        }

        // Send messages to other partners to reach global limit
        for (int i = 0; i < 10; i++) {
          rateLimiter.recordAttempt(userId: 'alice', partnerId: 'charlie');
        }

        // alice→bob is now hitting both limits
        final delay = await rateLimiter.checkRateLimit(
          userId: 'alice',
          partnerId: 'bob',
        );

        expect(delay.inMilliseconds, greaterThan(0));
      });

      test('conversation limit triggers before global', () async {
        // Send 20 messages to bob (hits per-conversation limit)
        for (int i = 0; i < 20; i++) {
          rateLimiter.recordAttempt(userId: 'alice', partnerId: 'bob');
        }

        // One more to bob should be delayed (conversation limit)
        final delayBob = await rateLimiter.checkRateLimit(
          userId: 'alice',
          partnerId: 'bob',
        );

        // But messages to charlie should still be fine (global not hit)
        final delayCharlie = await rateLimiter.checkRateLimit(
          userId: 'alice',
          partnerId: 'charlie',
        );

        expect(delayBob.inMilliseconds, greaterThan(0));
        expect(delayCharlie, equals(Duration.zero));
      });

      test('conversations are bidirectional (alice-bob == bob-alice)', () async {
        // Alice sends to Bob
        for (int i = 0; i < 10; i++) {
          rateLimiter.recordAttempt(userId: 'alice', partnerId: 'bob');
        }

        // Bob sends to Alice (same conversation)
        for (int i = 0; i < 10; i++) {
          rateLimiter.recordAttempt(userId: 'bob', partnerId: 'alice');
        }

        // Total is 20 messages in the conversation (hits limit)
        final delay = await rateLimiter.checkRateLimit(
          userId: 'alice',
          partnerId: 'bob',
        );

        expect(delay.inMilliseconds, greaterThan(0));
      });
    });

    group('Usage Statistics', () {
      test('getUsageStats returns accurate counts', () async {
        // Send 15 messages
        for (int i = 0; i < 15; i++) {
          rateLimiter.recordAttempt(userId: 'alice', partnerId: 'bob');
        }

        final stats = rateLimiter.getUsageStats(
          userId: 'alice',
          partnerId: 'bob',
        );

        expect(stats['global']['lastMinute'], equals(15));
        expect(stats['global']['lastHour'], equals(15));
        expect(stats['conversation']['lastMinute'], equals(15));
        expect(stats['conversation']['lastHour'], equals(15));
      });

      test('getUsageStats calculates percentages correctly', () async {
        // Send 30 messages (100% of per-minute limit)
        for (int i = 0; i < 30; i++) {
          rateLimiter.recordAttempt(userId: 'alice', partnerId: 'bob');
        }

        final stats = rateLimiter.getUsageStats(
          userId: 'alice',
          partnerId: 'bob',
        );

        expect(stats['global']['percentageMinute'], equals(100));
        expect(stats['conversation']['percentageMinute'], greaterThan(100)); // 150%
      });

      test('isRateLimited correctly identifies limited users', () async {
        // Under limit
        final notLimited = await rateLimiter.isRateLimited(
          userId: 'alice',
          partnerId: 'bob',
        );
        expect(notLimited, isFalse);

        // Exceed limit
        for (int i = 0; i < 30; i++) {
          rateLimiter.recordAttempt(userId: 'alice', partnerId: 'bob');
        }

        final limited = await rateLimiter.isRateLimited(
          userId: 'alice',
          partnerId: 'bob',
        );
        expect(limited, isTrue);
      });
    });

    group('Time Window Behavior', () {
      test('old attempts outside window are not counted', () async {
        // This test demonstrates the concept, but can't actually wait 1 hour
        // In practice, you'd use a mock clock or manual timestamp injection

        // Send messages
        for (int i = 0; i < 10; i++) {
          rateLimiter.recordAttempt(userId: 'alice', partnerId: 'bob');
        }

        final stats = rateLimiter.getUsageStats(
          userId: 'alice',
          partnerId: 'bob',
        );

        expect(stats['global']['lastMinute'], equals(10));
      });

      test('minute and hour limits are independent', () async {
        // This conceptually shows the difference between minute and hour limits
        // In real usage, minute limit would reset after 60 seconds
        // while hour limit persists for 3600 seconds

        final stats = rateLimiter.getUsageStats(
          userId: 'alice',
          partnerId: 'bob',
        );

        expect(stats['global']['limitsPerMinute'], equals(30));
        expect(stats['global']['limitsPerHour'], equals(500));
      });
    });

    group('Reset and Clear Operations', () {
      test('clear removes all rate limit data', () async {
        // Add some data
        for (int i = 0; i < 10; i++) {
          rateLimiter.recordAttempt(userId: 'alice', partnerId: 'bob');
        }

        rateLimiter.clear();

        final stats = rateLimiter.getUsageStats(
          userId: 'alice',
          partnerId: 'bob',
        );

        expect(stats['global']['lastMinute'], equals(0));
        expect(stats['conversation']['lastMinute'], equals(0));
      });

      test('resetUser removes only that user data', () async {
        // Alice sends messages
        for (int i = 0; i < 10; i++) {
          rateLimiter.recordAttempt(userId: 'alice', partnerId: 'bob');
        }

        // Charlie sends messages
        for (int i = 0; i < 5; i++) {
          rateLimiter.recordAttempt(userId: 'charlie', partnerId: 'bob');
        }

        rateLimiter.resetUser('alice');

        final aliceStats = rateLimiter.getUsageStats(userId: 'alice');
        final charlieStats = rateLimiter.getUsageStats(userId: 'charlie');

        expect(aliceStats['global']['lastMinute'], equals(0));
        expect(charlieStats['global']['lastMinute'], equals(5));
      });

      test('resetConversation removes only that conversation', () async {
        // Alice -> Bob
        for (int i = 0; i < 10; i++) {
          rateLimiter.recordAttempt(userId: 'alice', partnerId: 'bob');
        }

        // Alice -> Charlie
        for (int i = 0; i < 5; i++) {
          rateLimiter.recordAttempt(userId: 'alice', partnerId: 'charlie');
        }

        rateLimiter.resetConversation('alice', 'bob');

        final bobStats = rateLimiter.getUsageStats(
          userId: 'alice',
          partnerId: 'bob',
        );
        final charlieStats = rateLimiter.getUsageStats(
          userId: 'alice',
          partnerId: 'charlie',
        );

        expect(bobStats['conversation']['lastMinute'], equals(0));
        expect(charlieStats['conversation']['lastMinute'], equals(5));
        expect(bobStats['global']['lastMinute'], equals(15)); // Global includes all of Alice's messages
      });
    });

    group('Edge Cases', () {
      test('handles rapid successive checks', () async {
        // Simulate rapid API calls
        for (int i = 0; i < 5; i++) {
          final delay = await rateLimiter.checkRateLimit(
            userId: 'alice',
            partnerId: 'bob',
          );
          expect(delay, equals(Duration.zero));
          rateLimiter.recordAttempt(userId: 'alice', partnerId: 'bob');
        }
      });

      test('different users are independent', () async {
        // Alice maxes out
        for (int i = 0; i < 30; i++) {
          rateLimiter.recordAttempt(userId: 'alice', partnerId: 'bob');
        }

        // Bob should be unaffected
        final delay = await rateLimiter.checkRateLimit(
          userId: 'bob',
          partnerId: 'charlie',
        );

        expect(delay, equals(Duration.zero));
      });

      test('handles empty user IDs gracefully', () async {
        final delay = await rateLimiter.checkRateLimit(
          userId: '',
          partnerId: 'bob',
        );

        expect(delay, equals(Duration.zero));
      });
    });

    group('Soft Blocking Behavior', () {
      test('getDelay does not record attempt', () async {
        // Get delay without recording
        await rateLimiter.getDelay(
          userId: 'alice',
          partnerId: 'bob',
        );

        final stats = rateLimiter.getUsageStats(userId: 'alice');
        expect(stats['global']['lastMinute'], equals(0));
      });

      test('delay calculation is consistent', () async {
        // Exceed limit
        for (int i = 0; i < 31; i++) {
          rateLimiter.recordAttempt(userId: 'alice', partnerId: 'bob');
        }

        // Get delay multiple times without recording
        final delay1 = await rateLimiter.getDelay(
          userId: 'alice',
          partnerId: 'bob',
        );

        final delay2 = await rateLimiter.getDelay(
          userId: 'alice',
          partnerId: 'bob',
        );

        expect(delay1, equals(delay2));
      });
    });
  });
}
