import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class ReplayProtectionService {
  static const String _sequencePrefix = 'msg_seq_';
  static const String _noncePrefix = 'msg_nonce_';
  static const Duration _nonceExpiry = Duration(hours: 1);

  final SharedPreferences _prefs;

  ReplayProtectionService(this._prefs);

  String _getConversationId(String userId1, String userId2) {
    final ids = [userId1, userId2]..sort();
    return ids.join('_');
  }

  Future<int> getLastSequenceNumber(String senderId, String recipientId) async {
    final conversationId = _getConversationId(senderId, recipientId);
    final key = '$_sequencePrefix$conversationId';
    return _prefs.getInt(key) ?? 0;
  }

  Future<void> updateSequenceNumber(
    String senderId,
    String recipientId,
    int sequenceNumber,
  ) async {
    final conversationId = _getConversationId(senderId, recipientId);
    final key = '$_sequencePrefix$conversationId';
    await _prefs.setInt(key, sequenceNumber);
  }

  Future<bool> isNonceValid(
    String messageId,
    DateTime timestamp,
  ) async {
    final now = DateTime.now();
    final age = now.difference(timestamp);

    if (age > _nonceExpiry || age.isNegative && age.abs() > const Duration(minutes: 2)) {
      return false;
    }

    final key = '$_noncePrefix$messageId';
    final existingData = _prefs.getString(key);

    if (existingData != null) {
      return false;
    }

    final nonceData = jsonEncode({
      'timestamp': timestamp.toIso8601String(),
      'stored': now.toIso8601String(),
    });
    await _prefs.setString(key, nonceData);

    return true;
  }

  Future<bool> validateMessage({
    required String messageId,
    required String senderId,
    required String recipientId,
    required int sequenceNumber,
    required DateTime timestamp,
  }) async {
    final nonceValid = await isNonceValid(messageId, timestamp);
    if (!nonceValid) {
      return false;
    }

    final lastSeq = await getLastSequenceNumber(senderId, recipientId);

    if (sequenceNumber <= lastSeq) {
      return false;
    }

    await updateSequenceNumber(senderId, recipientId, sequenceNumber);
    return true;
  }

  Future<void> cleanupExpiredNonces() async {
    final now = DateTime.now();
    final keys = _prefs.getKeys();

    for (final key in keys) {
      if (key.startsWith(_noncePrefix)) {
        final data = _prefs.getString(key);
        if (data != null) {
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final stored = DateTime.parse(json['stored'] as String);

            if (now.difference(stored) > _nonceExpiry) {
              await _prefs.remove(key);
            }
          } catch (e) {
            await _prefs.remove(key);
          }
        }
      }
    }
  }

  Future<int> getNextSequenceNumber(String senderId, String recipientId) async {
    final lastSeq = await getLastSequenceNumber(senderId, recipientId);
    final nextSeq = lastSeq + 1;
    await updateSequenceNumber(senderId, recipientId, nextSeq);
    return nextSeq;
  }

  Future<void> resetConversation(String senderId, String recipientId) async {
    final conversationId = _getConversationId(senderId, recipientId);
    final key = '$_sequencePrefix$conversationId';
    await _prefs.remove(key);
  }
}
