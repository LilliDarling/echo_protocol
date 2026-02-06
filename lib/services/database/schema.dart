class DatabaseSchema {
  static const String conversationsTable = 'conversations';
  static const String messagesTable = 'messages';
  static const String blockedUsersTable = 'blocked_users';

  static const String createConversationsTable = '''
    CREATE TABLE $conversationsTable (
      id TEXT PRIMARY KEY,
      recipient_id TEXT NOT NULL,
      recipient_username TEXT NOT NULL,
      recipient_public_key TEXT NOT NULL,
      last_message_content TEXT,
      last_message_at INTEGER,
      unread_count INTEGER DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''';

  static const String createMessagesTable = '''
    CREATE TABLE $messagesTable (
      id TEXT PRIMARY KEY,
      conversation_id TEXT NOT NULL,
      sender_id TEXT NOT NULL,
      sender_username TEXT NOT NULL,
      content TEXT NOT NULL,
      timestamp INTEGER NOT NULL,
      type TEXT NOT NULL DEFAULT 'text',
      status TEXT NOT NULL DEFAULT 'sent',
      media_id TEXT,
      media_key TEXT,
      thumbnail_path TEXT,
      is_outgoing INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      synced_to_vault INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (conversation_id) REFERENCES $conversationsTable(id) ON DELETE CASCADE
    )
  ''';

  static const String createBlockedUsersTable = '''
    CREATE TABLE $blockedUsersTable (
      user_id TEXT PRIMARY KEY,
      blocked_at INTEGER NOT NULL,
      reason TEXT
    )
  ''';

  static const String createMessagesConversationIndex = '''
    CREATE INDEX idx_messages_conversation ON $messagesTable(conversation_id)
  ''';

  static const String createMessagesTimestampIndex = '''
    CREATE INDEX idx_messages_timestamp ON $messagesTable(timestamp)
  ''';

  static const String createConversationsUpdatedIndex = '''
    CREATE INDEX idx_conversations_updated ON $conversationsTable(updated_at)
  ''';

  static List<String> get createStatements => [
    createConversationsTable,
    createMessagesTable,
    createBlockedUsersTable,
    createMessagesConversationIndex,
    createMessagesTimestampIndex,
    createConversationsUpdatedIndex,
  ];
}
