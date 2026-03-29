import 'dart:convert';
import 'dart:typed_data';
import '../local/message.dart';

class VaultChunkConversation {
  final String conversationId;
  final String recipientId;
  final String recipientUsername;
  final String recipientPublicKey;
  final List<LocalMessage> messages;

  VaultChunkConversation({
    required this.conversationId,
    required this.recipientId,
    required this.recipientUsername,
    required this.recipientPublicKey,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
        'conversationId': conversationId,
        'recipientId': recipientId,
        'recipientUsername': recipientUsername,
        'recipientPublicKey': recipientPublicKey,
        'messages': messages.map((m) => m.toMap()).toList(),
      };

  factory VaultChunkConversation.fromJson(Map<String, dynamic> json) {
    return VaultChunkConversation(
      conversationId: json['conversationId'] as String,
      recipientId: json['recipientId'] as String,
      recipientUsername: json['recipientUsername'] as String,
      recipientPublicKey: json['recipientPublicKey'] as String,
      messages: (json['messages'] as List)
          .map((m) => LocalMessage.fromMap(m as Map<String, dynamic>))
          .toList(),
    );
  }
}

class VaultChunk {
  final String chunkId;
  final int chunkIndex;
  final DateTime startTimestamp;
  final DateTime endTimestamp;
  final List<VaultChunkConversation> conversations;
  final int version;

  static const int currentVersion = 1;

  VaultChunk({
    required this.chunkId,
    required this.chunkIndex,
    required this.startTimestamp,
    required this.endTimestamp,
    required this.conversations,
    this.version = currentVersion,
  });

  int get messageCount =>
      conversations.fold(0, (sum, c) => sum + c.messages.length);

  Map<String, dynamic> toJson() => {
        'chunkId': chunkId,
        'chunkIndex': chunkIndex,
        'startTimestamp': startTimestamp.millisecondsSinceEpoch,
        'endTimestamp': endTimestamp.millisecondsSinceEpoch,
        'conversations': conversations.map((c) => c.toJson()).toList(),
        'version': version,
      };

  factory VaultChunk.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 1;

    if (version > currentVersion) {
      throw FormatException(
        'Vault chunk version $version is not supported by this app version '
        '(max supported: $currentVersion). Update the app to read this data.',
      );
    }

    return VaultChunk(
      chunkId: json['chunkId'] as String,
      chunkIndex: json['chunkIndex'] as int,
      startTimestamp:
          DateTime.fromMillisecondsSinceEpoch(json['startTimestamp'] as int),
      endTimestamp:
          DateTime.fromMillisecondsSinceEpoch(json['endTimestamp'] as int),
      conversations: (json['conversations'] as List)
          .map((c) =>
              VaultChunkConversation.fromJson(c as Map<String, dynamic>))
          .toList(),
      version: currentVersion,
    );
  }

  Uint8List serialize() {
    return Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
  }

  static VaultChunk deserialize(Uint8List bytes) {
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return VaultChunk.fromJson(json);
  }
}
