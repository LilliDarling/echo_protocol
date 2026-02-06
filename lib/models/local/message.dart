enum LocalMessageType {
  text,
  image,
  video,
  voice,
  link,
  gif;

  static LocalMessageType fromString(String value) {
    return LocalMessageType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => LocalMessageType.text,
    );
  }
}

enum LocalMessageStatus {
  pending,
  failed,
  sent,
  delivered,
  read;

  static LocalMessageStatus fromString(String value) {
    return LocalMessageStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => LocalMessageStatus.sent,
    );
  }
}

class LocalMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String senderUsername;
  final String content;
  final DateTime timestamp;
  final LocalMessageType type;
  final LocalMessageStatus status;
  final String? mediaId;
  final String? mediaKey;
  final String? thumbnailPath;
  final bool isOutgoing;
  final DateTime createdAt;
  final bool syncedToVault;

  LocalMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderUsername,
    required this.content,
    required this.timestamp,
    this.type = LocalMessageType.text,
    this.status = LocalMessageStatus.sent,
    this.mediaId,
    this.mediaKey,
    this.thumbnailPath,
    required this.isOutgoing,
    required this.createdAt,
    this.syncedToVault = false,
  });

  factory LocalMessage.fromMap(Map<String, dynamic> map) {
    return LocalMessage(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      senderId: map['sender_id'] as String,
      senderUsername: map['sender_username'] as String,
      content: map['content'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      type: LocalMessageType.fromString(map['type'] as String),
      status: LocalMessageStatus.fromString(map['status'] as String),
      mediaId: map['media_id'] as String?,
      mediaKey: map['media_key'] as String?,
      thumbnailPath: map['thumbnail_path'] as String?,
      isOutgoing: (map['is_outgoing'] as int) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      syncedToVault: (map['synced_to_vault'] as int) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'sender_username': senderUsername,
      'content': content,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'type': type.name,
      'status': status.name,
      'media_id': mediaId,
      'media_key': mediaKey,
      'thumbnail_path': thumbnailPath,
      'is_outgoing': isOutgoing ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'synced_to_vault': syncedToVault ? 1 : 0,
    };
  }

  LocalMessage copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? senderUsername,
    String? content,
    DateTime? timestamp,
    LocalMessageType? type,
    LocalMessageStatus? status,
    String? mediaId,
    String? mediaKey,
    String? thumbnailPath,
    bool? isOutgoing,
    DateTime? createdAt,
    bool? syncedToVault,
  }) {
    return LocalMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      senderUsername: senderUsername ?? this.senderUsername,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      status: status ?? this.status,
      mediaId: mediaId ?? this.mediaId,
      mediaKey: mediaKey ?? this.mediaKey,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      createdAt: createdAt ?? this.createdAt,
      syncedToVault: syncedToVault ?? this.syncedToVault,
    );
  }
}
