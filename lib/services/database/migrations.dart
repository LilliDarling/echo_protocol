import 'package:sqflite_sqlcipher/sqflite.dart';
import 'schema.dart';

typedef Migration = Future<void> Function(Database db);

class DatabaseMigrations {
  static const int currentVersion = 1;

  static final Map<int, Migration> _migrations = {
    1: _migrateV1,
  };

  static Future<void> onCreate(Database db, int version) async {
    for (final statement in DatabaseSchema.createStatements) {
      await db.execute(statement);
    }
  }

  static Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    for (int v = oldVersion + 1; v <= newVersion; v++) {
      final migration = _migrations[v];
      if (migration != null) {
        await migration(db);
      }
    }
  }

  static Future<void> _migrateV1(Database db) async {
    // Initial schema - no migration needed
  }
}
