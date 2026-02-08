import 'package:drift/drift.dart';
import '../../models/local/conversation.dart';
import '../../models/local/message.dart';
import '../../models/local/blocked_user.dart';
import 'converters.dart';

@UseRowClass(LocalConversation)
@TableIndex(name: 'idx_conversations_updated', columns: {#updatedAt})
class Conversations extends Table {
  TextColumn get id => text()();
  TextColumn get recipientId => text().named('recipient_id')();
  TextColumn get recipientUsername => text().named('recipient_username')();
  TextColumn get recipientPublicKey => text().named('recipient_public_key')();
  TextColumn get lastMessageContent =>
      text().named('last_message_content').nullable()();
  IntColumn get lastMessageAt => integer()
      .named('last_message_at')
      .nullable()
      .map(const EpochDateTimeConverter())();
  IntColumn get unreadCount =>
      integer().named('unread_count').withDefault(const Constant(0))();
  IntColumn get createdAt =>
      integer().named('created_at').map(const EpochDateTimeConverter())();
  IntColumn get updatedAt =>
      integer().named('updated_at').map(const EpochDateTimeConverter())();

  @override
  Set<Column> get primaryKey => {id};

  @override
  String get tableName => 'conversations';
}

@UseRowClass(LocalMessage)
@TableIndex(name: 'idx_messages_conversation', columns: {#conversationId})
@TableIndex(name: 'idx_messages_timestamp', columns: {#timestamp})
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId =>
      text().named('conversation_id').references(Conversations, #id)();
  TextColumn get senderId => text().named('sender_id')();
  TextColumn get senderUsername => text().named('sender_username')();
  TextColumn get content => text()();
  IntColumn get timestamp =>
      integer().map(const EpochDateTimeConverter())();
  TextColumn get type => text()
      .withDefault(const Constant('text'))
      .map(const MessageTypeConverter())();
  TextColumn get status => text()
      .withDefault(const Constant('sent'))
      .map(const MessageStatusConverter())();
  TextColumn get mediaId => text().named('media_id').nullable()();
  TextColumn get mediaKey => text().named('media_key').nullable()();
  TextColumn get thumbnailPath =>
      text().named('thumbnail_path').nullable()();
  BoolColumn get isOutgoing =>
      boolean().named('is_outgoing').withDefault(const Constant(false))();
  IntColumn get createdAt =>
      integer().named('created_at').map(const EpochDateTimeConverter())();
  BoolColumn get syncedToVault => boolean()
      .named('synced_to_vault')
      .withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  String get tableName => 'messages';
}

@UseRowClass(LocalBlockedUser)
class BlockedUsers extends Table {
  TextColumn get userId => text().named('user_id')();
  IntColumn get blockedAt =>
      integer().named('blocked_at').map(const EpochDateTimeConverter())();
  TextColumn get reason => text().nullable()();

  @override
  Set<Column> get primaryKey => {userId};

  @override
  String get tableName => 'blocked_users';
}
