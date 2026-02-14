import 'package:drift/drift.dart';
import '../services/database/app_database.dart';
import '../services/database/tables.dart';
import '../models/local/message.dart';

part 'message_dao.g.dart';

@DriftAccessor(tables: [Messages])
class MessageDao extends DatabaseAccessor<AppDatabase>
    with _$MessageDaoMixin {
  MessageDao(super.db);

  MessagesCompanion _toCompanion(LocalMessage m) {
    return MessagesCompanion.insert(
      id: m.id,
      conversationId: m.conversationId,
      senderId: m.senderId,
      senderUsername: m.senderUsername,
      content: m.content,
      timestamp: m.timestamp,
      type: Value(m.type),
      status: Value(m.status),
      mediaId: Value(m.mediaId),
      mediaKey: Value(m.mediaKey),
      thumbnailPath: Value(m.thumbnailPath),
      isOutgoing: Value(m.isOutgoing),
      createdAt: m.createdAt,
      syncedToVault: Value(m.syncedToVault),
    );
  }

  Future<void> insert(LocalMessage message) async {
    await into(messages).insert(
      _toCompanion(message),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<void> insertBatch(List<LocalMessage> messageList) async {
    if (messageList.isEmpty) return;
    await batch((b) {
      b.insertAll(
        messages,
        messageList.map(_toCompanion).toList(),
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<void> updateMessage(LocalMessage message) async {
    await (update(messages)..where((t) => t.id.equals(message.id)))
        .write(_toCompanion(message));
  }

  Future<void> deleteMessage(String id) async {
    await (delete(messages)..where((t) => t.id.equals(id))).go();
  }

  Future<void> deleteByConversation(String conversationId) async {
    await (delete(messages)
          ..where((t) => t.conversationId.equals(conversationId)))
        .go();
  }

  Future<LocalMessage?> getById(String id) {
    return (select(messages)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<List<LocalMessage>> getByConversation(
    String conversationId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final result = await (select(messages)
          ..where((t) => t.conversationId.equals(conversationId))
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
          ..limit(limit, offset: offset))
        .get();
    return result.reversed.toList();
  }

  Future<List<LocalMessage>> getMessagesBefore(
    String conversationId,
    DateTime before, {
    int limit = 50,
  }) async {
    final result = await (select(messages)
          ..where((t) =>
              t.conversationId.equals(conversationId) &
              t.timestamp.isSmallerThan(
                  Variable(before.millisecondsSinceEpoch)))
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
          ..limit(limit))
        .get();
    return result.reversed.toList();
  }

  Future<List<LocalMessage>> getMessagesAfter(
    String conversationId,
    DateTime after,
  ) {
    return (select(messages)
          ..where((t) =>
              t.conversationId.equals(conversationId) &
              t.timestamp.isBiggerThan(
                  Variable(after.millisecondsSinceEpoch)))
          ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]))
        .get();
  }

  Future<LocalMessage?> getLatestMessage(String conversationId) {
    return (select(messages)
          ..where((t) => t.conversationId.equals(conversationId))
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> updateStatus(String id, LocalMessageStatus status) async {
    await (update(messages)..where((t) => t.id.equals(id))).write(
      MessagesCompanion(status: Value(status)),
    );
  }

  Future<void> markAsSynced(String id) async {
    await (update(messages)..where((t) => t.id.equals(id))).write(
      const MessagesCompanion(syncedToVault: Value(true)),
    );
  }

  Future<void> markBatchAsSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    await (update(messages)..where((t) => t.id.isIn(ids))).write(
      const MessagesCompanion(syncedToVault: Value(true)),
    );
  }

  Future<List<LocalMessage>> getUnsyncedMessages({int limit = 100}) {
    return (select(messages)
          ..where((t) => t.syncedToVault.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.timestamp)])
          ..limit(limit))
        .get();
  }

  Future<int> getMessageCount(String conversationId) async {
    final count = countAll();
    final query = selectOnly(messages)
      ..addColumns([count])
      ..where(messages.conversationId.equals(conversationId));
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  Future<void> deleteOlderThan(DateTime cutoff) async {
    await (delete(messages)
          ..where((t) => t.timestamp.isSmallerThan(
              Variable(cutoff.millisecondsSinceEpoch))))
        .go();
  }

  Future<int> deleteOlderThanInConversation(
    String conversationId,
    DateTime cutoff,
  ) async {
    return await (delete(messages)
          ..where((t) =>
              t.conversationId.equals(conversationId) &
              t.timestamp.isSmallerThan(
                  Variable(cutoff.millisecondsSinceEpoch))))
        .go();
  }

  Stream<List<LocalMessage>> watchConversation(String conversationId) {
    return (select(messages)
          ..where((t) => t.conversationId.equals(conversationId))
          ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]))
        .watch();
  }
}
