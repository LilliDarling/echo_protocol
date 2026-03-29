import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto_pkg;
import '../../models/local/message.dart';
import '../../models/local/conversation.dart';
import '../../models/vault/vault_chunk.dart';
import '../../utils/security.dart';

class VaultChunkBuilder {
  static const int maxMessages = 500;
  static const int maxBytes = 2 * 1024 * 1024; // 2MB
  static const Duration maxTimeSpan = Duration(hours: 24);

  static List<VaultChunk> buildChunks({
    required List<LocalMessage> messages,
    required Map<String, LocalConversation> conversationMap,
    required int startingIndex,
  }) {
    if (messages.isEmpty) return [];

    final sorted = List<LocalMessage>.from(messages)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final chunks = <VaultChunk>[];
    var currentMessages = <LocalMessage>[];
    var currentSize = 0;
    DateTime? windowStart;

    for (final message in sorted) {
      windowStart ??= message.timestamp;

      final msgSize = _measureMessageSize(message);

      final wouldExceedMessages = currentMessages.length + 1 > maxMessages;
      final wouldExceedSize = currentSize + msgSize > maxBytes;
      final wouldExceedTime =
          message.timestamp.difference(windowStart) > maxTimeSpan;

      if (currentMessages.isNotEmpty &&
          (wouldExceedMessages || wouldExceedSize || wouldExceedTime)) {
        chunks.add(_buildSingleChunk(
          messages: currentMessages,
          conversationMap: conversationMap,
          chunkIndex: startingIndex + chunks.length,
        ));
        currentMessages = [];
        currentSize = 0;
        windowStart = message.timestamp;
      }

      currentMessages.add(message);
      currentSize += msgSize;
    }

    if (currentMessages.isNotEmpty) {
      chunks.add(_buildSingleChunk(
        messages: currentMessages,
        conversationMap: conversationMap,
        chunkIndex: startingIndex + chunks.length,
      ));
    }

    return chunks;
  }

  static VaultChunk _buildSingleChunk({
    required List<LocalMessage> messages,
    required Map<String, LocalConversation> conversationMap,
    required int chunkIndex,
  }) {
    final grouped = <String, List<LocalMessage>>{};
    for (final msg in messages) {
      grouped.putIfAbsent(msg.conversationId, () => []).add(msg);
    }

    final conversations = grouped.entries.map((entry) {
      final conv = conversationMap[entry.key];
      return VaultChunkConversation(
        conversationId: entry.key,
        recipientId: conv?.recipientId ?? '',
        recipientUsername: conv?.recipientUsername ?? '',
        recipientPublicKey: conv?.recipientPublicKey ?? '',
        messages: entry.value,
      );
    }).toList();

    final chunkId = _generateChunkId(chunkIndex);

    return VaultChunk(
      chunkId: chunkId,
      chunkIndex: chunkIndex,
      startTimestamp: messages.first.timestamp,
      endTimestamp: messages.last.timestamp,
      conversations: conversations,
    );
  }

  static String _generateChunkId(int index) {
    final randomBytes = SecurityUtils.generateSecureRandomBytes(8);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final input = '$timestamp:$index:${base64Encode(randomBytes)}';
    return crypto_pkg.sha256
        .convert(utf8.encode(input))
        .toString()
        .substring(0, 24);
  }

  static int _measureMessageSize(LocalMessage message) {
    return utf8.encode(jsonEncode(message.toMap())).length;
  }
}
