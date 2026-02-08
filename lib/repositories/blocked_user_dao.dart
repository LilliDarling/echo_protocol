import 'package:drift/drift.dart';
import '../services/database/app_database.dart';
import '../services/database/tables.dart';
import '../models/local/blocked_user.dart';

part 'blocked_user_dao.g.dart';

@DriftAccessor(tables: [BlockedUsers])
class BlockedUserDao extends DatabaseAccessor<AppDatabase>
    with _$BlockedUserDaoMixin {
  BlockedUserDao(super.db);

  Future<void> block(String userId, {String? reason}) async {
    await into(blockedUsers).insert(
      BlockedUsersCompanion.insert(
        userId: userId,
        blockedAt: DateTime.now(),
        reason: Value(reason),
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<void> unblock(String userId) async {
    await (delete(blockedUsers)..where((t) => t.userId.equals(userId))).go();
  }

  Future<bool> isBlocked(String userId) async {
    final result = await (select(blockedUsers)
          ..where((t) => t.userId.equals(userId))
          ..limit(1))
        .getSingleOrNull();
    return result != null;
  }

  Future<LocalBlockedUser?> getByUserId(String userId) {
    return (select(blockedUsers)..where((t) => t.userId.equals(userId)))
        .getSingleOrNull();
  }

  Future<List<LocalBlockedUser>> getAll() {
    return (select(blockedUsers)
          ..orderBy([(t) => OrderingTerm.desc(t.blockedAt)]))
        .get();
  }

  Future<int> getCount() async {
    final count = countAll();
    final query = selectOnly(blockedUsers)..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }
}
