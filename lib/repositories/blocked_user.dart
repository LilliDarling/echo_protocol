import 'package:sqflite_sqlcipher/sqflite.dart';
import '../services/database/database_service.dart';
import '../services/database/schema.dart';
import '../models/local/blocked_user.dart';

class BlockedUserRepository {
  final DatabaseService _databaseService;

  BlockedUserRepository({DatabaseService? databaseService})
      : _databaseService = databaseService ?? DatabaseService();

  Future<Database> get _db => _databaseService.database;

  Future<void> block(String userId, {String? reason}) async {
    final db = await _db;
    final blockedUser = LocalBlockedUser(
      userId: userId,
      blockedAt: DateTime.now(),
      reason: reason,
    );

    await db.insert(
      DatabaseSchema.blockedUsersTable,
      blockedUser.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> unblock(String userId) async {
    final db = await _db;
    await db.delete(
      DatabaseSchema.blockedUsersTable,
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  Future<bool> isBlocked(String userId) async {
    final db = await _db;
    final result = await db.query(
      DatabaseSchema.blockedUsersTable,
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  Future<LocalBlockedUser?> getByUserId(String userId) async {
    final db = await _db;
    final result = await db.query(
      DatabaseSchema.blockedUsersTable,
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return LocalBlockedUser.fromMap(result.first);
  }

  Future<List<LocalBlockedUser>> getAll() async {
    final db = await _db;
    final result = await db.query(
      DatabaseSchema.blockedUsersTable,
      orderBy: 'blocked_at DESC',
    );

    return result.map((map) => LocalBlockedUser.fromMap(map)).toList();
  }

  Future<int> getCount() async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM ${DatabaseSchema.blockedUsersTable}
    ''');

    return (result.first['count'] as int?) ?? 0;
  }
}
