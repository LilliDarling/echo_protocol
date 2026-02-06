import 'dart:async';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../services/database/database_service.dart';
import '../services/database/schema.dart';
import '../models/local/conversation.dart';

class ConversationRepository {
  final DatabaseService _databaseService;

  ConversationRepository({DatabaseService? databaseService})
      : _databaseService = databaseService ?? DatabaseService();

  Future<Database> get _db => _databaseService.database;

  Future<void> insert(LocalConversation conversation) async {
    final db = await _db;
    await db.insert(
      DatabaseSchema.conversationsTable,
      conversation.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> update(LocalConversation conversation) async {
    final db = await _db;
    await db.update(
      DatabaseSchema.conversationsTable,
      conversation.toMap(),
      where: 'id = ?',
      whereArgs: [conversation.id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.delete(
      DatabaseSchema.conversationsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<LocalConversation?> getById(String id) async {
    final db = await _db;
    final result = await db.query(
      DatabaseSchema.conversationsTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return LocalConversation.fromMap(result.first);
  }

  Future<LocalConversation?> getByRecipientId(String recipientId) async {
    final db = await _db;
    final result = await db.query(
      DatabaseSchema.conversationsTable,
      where: 'recipient_id = ?',
      whereArgs: [recipientId],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return LocalConversation.fromMap(result.first);
  }

  Future<List<LocalConversation>> getAll() async {
    final db = await _db;
    final result = await db.query(
      DatabaseSchema.conversationsTable,
      orderBy: 'updated_at DESC',
    );

    return result.map((map) => LocalConversation.fromMap(map)).toList();
  }

  Future<void> updateLastMessage({
    required String conversationId,
    required String content,
    required DateTime timestamp,
  }) async {
    final db = await _db;
    await db.update(
      DatabaseSchema.conversationsTable,
      {
        'last_message_content': content,
        'last_message_at': timestamp.millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<void> incrementUnreadCount(String conversationId) async {
    final db = await _db;
    await db.rawUpdate('''
      UPDATE ${DatabaseSchema.conversationsTable}
      SET unread_count = unread_count + 1, updated_at = ?
      WHERE id = ?
    ''', [DateTime.now().millisecondsSinceEpoch, conversationId]);
  }

  Future<void> resetUnreadCount(String conversationId) async {
    final db = await _db;
    await db.update(
      DatabaseSchema.conversationsTable,
      {
        'unread_count': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<int> getTotalUnreadCount() async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT SUM(unread_count) as total FROM ${DatabaseSchema.conversationsTable}
    ''');

    return (result.first['total'] as int?) ?? 0;
  }

  Stream<List<LocalConversation>> watchAll() {
    final controller = StreamController<List<LocalConversation>>();

    () async {
      final conversations = await getAll();
      controller.add(conversations);
    }();

    return controller.stream;
  }
}
