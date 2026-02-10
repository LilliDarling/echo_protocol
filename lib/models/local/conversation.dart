class LocalConversation {
  final String id;
  final String recipientId;
  final String recipientUsername;
  final String recipientPublicKey;
  final String? lastMessageContent;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  LocalConversation({
    required this.id,
    required this.recipientId,
    required this.recipientUsername,
    required this.recipientPublicKey,
    this.lastMessageContent,
    this.lastMessageAt,
    this.unreadCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LocalConversation.fromMap(Map<String, dynamic> map) {
    return LocalConversation(
      id: map['id'] as String,
      recipientId: map['recipient_id'] as String,
      recipientUsername: map['recipient_username'] as String,
      recipientPublicKey: map['recipient_public_key'] as String,
      lastMessageContent: map['last_message_content'] as String?,
      lastMessageAt: map['last_message_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_message_at'] as int)
          : null,
      unreadCount: (map['unread_count'] as int?) ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'recipient_id': recipientId,
      'recipient_username': recipientUsername,
      'recipient_public_key': recipientPublicKey,
      'last_message_content': lastMessageContent,
      'last_message_at': lastMessageAt?.millisecondsSinceEpoch,
      'unread_count': unreadCount,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  LocalConversation copyWith({
    String? id,
    String? recipientId,
    String? recipientUsername,
    String? recipientPublicKey,
    String? lastMessageContent,
    DateTime? lastMessageAt,
    int? unreadCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LocalConversation(
      id: id ?? this.id,
      recipientId: recipientId ?? this.recipientId,
      recipientUsername: recipientUsername ?? this.recipientUsername,
      recipientPublicKey: recipientPublicKey ?? this.recipientPublicKey,
      lastMessageContent: lastMessageContent ?? this.lastMessageContent,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
