import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';

class MessageRateLimiter {
  final FirebaseFunctions _functions;

  MessageRateLimiter({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;
  static const int _maxMessagesPerMinute = 30;
  static const int _maxMessagesPerHour = 500;
  static const int _maxConversationMessagesPerMinute = 20;
  static const int _maxConversationMessagesPerHour = 300;
  static const Duration _minDelay = Duration(milliseconds: 100);
  static const Duration _maxDelay = Duration(seconds: 30);
  static const double _backoffMultiplier = 1.5;

  final Map<String, List<DateTime>> _globalAttempts = {};
  final Map<String, List<DateTime>> _conversationAttempts = {};
  DateTime? _lastCleanup;

  Future<Duration> checkRateLimit({
    required String userId,
    required String partnerId,
  }) async {
    _periodicCleanup();

    final now = DateTime.now();
    final globalKey = 'user_$userId';
    final conversationKey = _getConversationKey(userId, partnerId);

    final globalDelay = _checkLimit(
      key: globalKey,
      storage: _globalAttempts,
      now: now,
      maxPerMinute: _maxMessagesPerMinute,
      maxPerHour: _maxMessagesPerHour,
    );

    final conversationDelay = _checkLimit(
      key: conversationKey,
      storage: _conversationAttempts,
      now: now,
      maxPerMinute: _maxConversationMessagesPerMinute,
      maxPerHour: _maxConversationMessagesPerHour,
    );

    return globalDelay > conversationDelay ? globalDelay : conversationDelay;
  }

  void recordAttempt({
    required String userId,
    required String partnerId,
  }) {
    final now = DateTime.now();
    final globalKey = 'user_$userId';
    final conversationKey = _getConversationKey(userId, partnerId);

    final globalAttempts = _globalAttempts[globalKey] ?? [];
    globalAttempts.add(now);
    _globalAttempts[globalKey] = globalAttempts;

    final conversationAttempts = _conversationAttempts[conversationKey] ?? [];
    conversationAttempts.add(now);
    _conversationAttempts[conversationKey] = conversationAttempts;
  }
  Duration _checkLimit({
    required String key,
    required Map<String, List<DateTime>> storage,
    required DateTime now,
    required int maxPerMinute,
    required int maxPerHour,
  }) {
    final attempts = storage[key] ?? [];
    final hourCutoff = now.subtract(const Duration(hours: 1));
    attempts.removeWhere((timestamp) => timestamp.isBefore(hourCutoff));
    storage[key] = attempts;

    final minuteCutoff = now.subtract(const Duration(minutes: 1));
    final attemptsInMinute = attempts.where((t) => t.isAfter(minuteCutoff)).length;
    final attemptsInHour = attempts.length;

    Duration delay = Duration.zero;

    if (attemptsInMinute >= maxPerMinute) {
      final excess = attemptsInMinute - maxPerMinute + 1;
      delay = _calculateBackoffDelay(excess);
    }

    if (attemptsInHour >= maxPerHour) {
      final excess = attemptsInHour - maxPerHour + 1;
      final hourDelay = _calculateBackoffDelay(excess * 2);
      if (hourDelay > delay) {
        delay = hourDelay;
      }
    }

    return delay;
  }

  Duration _calculateBackoffDelay(int excessCount) {
    final delayMs = _minDelay.inMilliseconds *
                    pow(_backoffMultiplier, excessCount - 1);
    final cappedDelayMs = min(delayMs.toInt(), _maxDelay.inMilliseconds);
    return Duration(milliseconds: cappedDelayMs);
  }

  String _getConversationKey(String userId1, String userId2) {
    final ids = [userId1, userId2]..sort();
    return 'conv_${ids[0]}_${ids[1]}';
  }
  Map<String, dynamic> getUsageStats({
    required String userId,
    String? partnerId,
  }) {
    final now = DateTime.now();
    final globalKey = 'user_$userId';

    final globalAttempts = _globalAttempts[globalKey] ?? [];
    final minuteCutoff = now.subtract(const Duration(minutes: 1));
    final hourCutoff = now.subtract(const Duration(hours: 1));

    final globalMinute = globalAttempts.where((t) => t.isAfter(minuteCutoff)).length;
    final globalHour = globalAttempts.where((t) => t.isAfter(hourCutoff)).length;

    final stats = {
      'global': {
        'lastMinute': globalMinute,
        'lastHour': globalHour,
        'limitsPerMinute': _maxMessagesPerMinute,
        'limitsPerHour': _maxMessagesPerHour,
        'percentageMinute': (globalMinute / _maxMessagesPerMinute * 100).toInt(),
        'percentageHour': (globalHour / _maxMessagesPerHour * 100).toInt(),
      },
    };

    if (partnerId != null) {
      final conversationKey = _getConversationKey(userId, partnerId);
      final conversationAttempts = _conversationAttempts[conversationKey] ?? [];

      final convMinute = conversationAttempts.where((t) => t.isAfter(minuteCutoff)).length;
      final convHour = conversationAttempts.where((t) => t.isAfter(hourCutoff)).length;

      stats['conversation'] = {
        'lastMinute': convMinute,
        'lastHour': convHour,
        'limitsPerMinute': _maxConversationMessagesPerMinute,
        'limitsPerHour': _maxConversationMessagesPerHour,
        'percentageMinute': (convMinute / _maxConversationMessagesPerMinute * 100).toInt(),
        'percentageHour': (convHour / _maxConversationMessagesPerHour * 100).toInt(),
      };
    }

    return stats;
  }

  Future<bool> isRateLimited({
    required String userId,
    required String partnerId,
  }) async {
    final delay = await checkRateLimit(userId: userId, partnerId: partnerId);
    return delay > Duration.zero;
  }

  Future<Duration> getDelay({
    required String userId,
    required String partnerId,
  }) async {
    return checkRateLimit(userId: userId, partnerId: partnerId);
  }

  void _periodicCleanup() {
    final now = DateTime.now();

    if (_lastCleanup == null ||
        now.difference(_lastCleanup!) > const Duration(minutes: 10)) {
      _cleanup();
      _lastCleanup = now;
    }
  }

  void _cleanup() {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(hours: 1));

    _globalAttempts.removeWhere((key, attempts) {
      attempts.removeWhere((timestamp) => timestamp.isBefore(cutoff));
      return attempts.isEmpty;
    });

    _conversationAttempts.removeWhere((key, attempts) {
      attempts.removeWhere((timestamp) => timestamp.isBefore(cutoff));
      return attempts.isEmpty;
    });
  }

  void clear() {
    _globalAttempts.clear();
    _conversationAttempts.clear();
    _lastCleanup = null;
  }

  void resetUser(String userId) {
    final globalKey = 'user_$userId';
    _globalAttempts.remove(globalKey);
    _conversationAttempts.removeWhere((key, _) => key.contains(userId));
  }

  void resetConversation(String userId, String partnerId) {
    final conversationKey = _getConversationKey(userId, partnerId);
    _conversationAttempts.remove(conversationKey);
  }

  Future<MessageRateLimitResult> checkServerRateLimit({
    required String conversationId,
    required String recipientId,
  }) async {
    try {
      final callable = _functions.httpsCallable('checkMessageRateLimit');
      final result = await callable.call({
        'conversationId': conversationId,
        'recipientId': recipientId,
      });

      final data = result.data as Map<String, dynamic>;
      return MessageRateLimitResult(
        allowed: data['allowed'] as bool? ?? false,
        retryAfterMs: data['retryAfterMs'] as int?,
        remainingMinute: data['remainingMinute'] as int?,
        remainingHour: data['remainingHour'] as int?,
      );
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        return MessageRateLimitResult(
          allowed: false,
          retryAfterMs: 60000,
        );
      }
      rethrow;
    }
  }
}

class MessageRateLimitResult {
  final bool allowed;
  final int? retryAfterMs;
  final int? remainingMinute;
  final int? remainingHour;

  MessageRateLimitResult({
    required this.allowed,
    this.retryAfterMs,
    this.remainingMinute,
    this.remainingHour,
  });

  Duration get retryAfter =>
      retryAfterMs != null ? Duration(milliseconds: retryAfterMs!) : Duration.zero;
}
