import 'package:drift/drift.dart';
import '../services/database/app_database.dart';
import '../services/database/tables.dart';
import '../models/local/conversation.dart';

part 'conversation_dao.g.dart';

@DriftAccessor(tables: [Conversations])
class ConversationDao extends DatabaseAccessor<AppDatabase>
    with _$ConversationDaoMixin {
  ConversationDao(super.db);

  Future<void> insert(LocalConversation conversation) async {
    await into(conversations).insert(
      ConversationsCompanion.insert(
        id: conversation.id,
        recipientId: conversation.recipientId,
        recipientUsername: conversation.recipientUsername,
        recipientPublicKey: conversation.recipientPublicKey,
        lastMessageContent: Value(conversation.lastMessageContent),
        lastMessageAt: Value(conversation.lastMessageAt),
        unreadCount: Value(conversation.unreadCount),
        createdAt: conversation.createdAt,
        updatedAt: conversation.updatedAt,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<void> updateConversation(LocalConversation conversation) async {
    await (update(conversations)
          ..where((t) => t.id.equals(conversation.id)))
        .write(
      ConversationsCompanion(
        recipientId: Value(conversation.recipientId),
        recipientUsername: Value(conversation.recipientUsername),
        recipientPublicKey: Value(conversation.recipientPublicKey),
        lastMessageContent: Value(conversation.lastMessageContent),
        lastMessageAt: Value(conversation.lastMessageAt),
        unreadCount: Value(conversation.unreadCount),
        updatedAt: Value(conversation.updatedAt),
      ),
    );
  }

  Future<void> deleteConversation(String id) async {
    await (delete(conversations)..where((t) => t.id.equals(id))).go();
  }

  Future<LocalConversation?> getById(String id) {
    return (select(conversations)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<LocalConversation?> getByRecipientId(String recipientId) {
    return (select(conversations)
          ..where((t) => t.recipientId.equals(recipientId)))
        .getSingleOrNull();
  }

  Future<List<LocalConversation>> getAll() {
    return (select(conversations)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
  }

  Stream<List<LocalConversation>> watchAll() {
    return (select(conversations)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .watch();
  }

  Future<void> updateLastMessage({
    required String conversationId,
    required String content,
    required DateTime timestamp,
  }) async {
    await (update(conversations)
          ..where((t) => t.id.equals(conversationId)))
        .write(
      ConversationsCompanion(
        lastMessageContent: Value(content),
        lastMessageAt: Value(timestamp),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> incrementUnreadCount(String conversationId) async {
    await customUpdate(
      'UPDATE conversations SET unread_count = unread_count + 1, '
      'updated_at = ? WHERE id = ?',
      variables: [
        Variable.withInt(DateTime.now().millisecondsSinceEpoch),
        Variable.withString(conversationId),
      ],
      updates: {conversations},
    );
  }

  Future<void> resetUnreadCount(String conversationId) async {
    await (update(conversations)
          ..where((t) => t.id.equals(conversationId)))
        .write(
      ConversationsCompanion(
        unreadCount: const Value(0),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> getTotalUnreadCount() async {
    final result = await customSelect(
      'SELECT SUM(unread_count) as total FROM conversations',
    ).getSingle();
    return result.data['total'] as int? ?? 0;
  }
}
