import 'dart:async';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../services/database/database_service.dart';
import '../services/database/schema.dart';
import '../models/local/message.dart';

class MessageRepository {
  final DatabaseService _databaseService;

  MessageRepository({DatabaseService? databaseService})
      : _databaseService = databaseService ?? DatabaseService();

  Future<Database> get _db => _databaseService.database;

  Future<void> insert(LocalMessage message) async {
    final db = await _db;
    await db.insert(
      DatabaseSchema.messagesTable,
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertBatch(List<LocalMessage> messages) async {
    if (messages.isEmpty) return;

    final db = await _db;
    final batch = db.batch();

    for (final message in messages) {
      batch.insert(
        DatabaseSchema.messagesTable,
        message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<void> update(LocalMessage message) async {
    final db = await _db;
    await db.update(
      DatabaseSchema.messagesTable,
      message.toMap(),
      where: 'id = ?',
      whereArgs: [message.id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.delete(
      DatabaseSchema.messagesTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteByConversation(String conversationId) async {
    final db = await _db;
    await db.delete(
      DatabaseSchema.messagesTable,
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<LocalMessage?> getById(String id) async {
    final db = await _db;
    final result = await db.query(
      DatabaseSchema.messagesTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return LocalMessage.fromMap(result.first);
  }

  Future<List<LocalMessage>> getByConversation(
    String conversationId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _db;
    final result = await db.query(
      DatabaseSchema.messagesTable,
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );

    return result.map((map) => LocalMessage.fromMap(map)).toList().reversed.toList();
  }

  Future<List<LocalMessage>> getMessagesBefore(
    String conversationId,
    DateTime before, {
    int limit = 50,
  }) async {
    final db = await _db;
    final result = await db.query(
      DatabaseSchema.messagesTable,
      where: 'conversation_id = ? AND timestamp < ?',
      whereArgs: [conversationId, before.millisecondsSinceEpoch],
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    return result.map((map) => LocalMessage.fromMap(map)).toList().reversed.toList();
  }

  Future<List<LocalMessage>> getMessagesAfter(
    String conversationId,
    DateTime after,
  ) async {
    final db = await _db;
    final result = await db.query(
      DatabaseSchema.messagesTable,
      where: 'conversation_id = ? AND timestamp > ?',
      whereArgs: [conversationId, after.millisecondsSinceEpoch],
      orderBy: 'timestamp ASC',
    );

    return result.map((map) => LocalMessage.fromMap(map)).toList();
  }

  Future<LocalMessage?> getLatestMessage(String conversationId) async {
    final db = await _db;
    final result = await db.query(
      DatabaseSchema.messagesTable,
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );

    if (result.isEmpty) return null;
    return LocalMessage.fromMap(result.first);
  }

  Future<void> updateStatus(String id, LocalMessageStatus status) async {
    final db = await _db;
    await db.update(
      DatabaseSchema.messagesTable,
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markAsSynced(String id) async {
    final db = await _db;
    await db.update(
      DatabaseSchema.messagesTable,
      {'synced_to_vault': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<LocalMessage>> getUnsyncedMessages({int limit = 100}) async {
    final db = await _db;
    final result = await db.query(
      DatabaseSchema.messagesTable,
      where: 'synced_to_vault = 0',
      orderBy: 'timestamp ASC',
      limit: limit,
    );

    return result.map((map) => LocalMessage.fromMap(map)).toList();
  }

  Future<int> getMessageCount(String conversationId) async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM ${DatabaseSchema.messagesTable}
      WHERE conversation_id = ?
    ''', [conversationId]);

    return (result.first['count'] as int?) ?? 0;
  }

  Future<void> deleteOlderThan(DateTime cutoff) async {
    final db = await _db;
    await db.delete(
      DatabaseSchema.messagesTable,
      where: 'timestamp < ?',
      whereArgs: [cutoff.millisecondsSinceEpoch],
    );
  }

  Stream<List<LocalMessage>> watchConversation(String conversationId) {
    final controller = StreamController<List<LocalMessage>>();

    () async {
      final messages = await getByConversation(conversationId);
      controller.add(messages);
    }();

    return controller.stream;
  }
}
