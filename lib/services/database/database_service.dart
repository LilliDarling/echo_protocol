import 'dart:convert';
import 'dart:typed_data';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../secure_storage.dart';
import '../../utils/security.dart';
import 'migrations.dart';

class DatabaseService {
  static DatabaseService? _instance;
  static Database? _database;
  static const String _dbName = 'echo_protocol.db';
  static const String _keySalt = 'echo-protocol-local-db-v1';
  static const String _keyInfo = 'sqlcipher-key';

  final SecureStorageService _secureStorage;

  DatabaseService._internal(this._secureStorage);

  factory DatabaseService({SecureStorageService? secureStorage}) {
    _instance ??= DatabaseService._internal(
      secureStorage ?? SecureStorageService(),
    );
    return _instance!;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    if (kIsWeb) {
      throw UnsupportedError('SQLCipher is not supported on web platform');
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    final key = await _getOrCreateDatabaseKey();

    return await openDatabase(
      path,
      version: DatabaseMigrations.currentVersion,
      password: key,
      onCreate: DatabaseMigrations.onCreate,
      onUpgrade: DatabaseMigrations.onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA secure_delete = ON');
        await db.execute('PRAGMA temp_store = MEMORY');
      },
    );
  }

  Future<String> _getOrCreateDatabaseKey() async {
    final existingKey = await _secureStorage.getDatabaseKey();
    if (existingKey != null) {
      return existingKey;
    }

    final keyBytes = SecurityUtils.generateSecureRandomBytes(32);
    final key = base64Encode(keyBytes);
    await _secureStorage.storeDatabaseKey(key);
    SecurityUtils.secureClear(keyBytes);

    return key;
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<void> deleteDatabase() async {
    await close();
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    await databaseFactory.deleteDatabase(path);
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('messages');
      await txn.delete('conversations');
      await txn.delete('blocked_users');
    });
  }

  static Future<void> resetInstance() async {
    if (_instance != null) {
      await _instance!.close();
      _instance = null;
      _database = null;
    }
  }

  Future<bool> verifyIntegrity() async {
    try {
      final db = await database;
      final result = await db.rawQuery('PRAGMA integrity_check');
      return result.isNotEmpty && result.first['integrity_check'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<void> initializeWithRecoveryPhrase(Uint8List phraseBytes) async {
    final derivedKey = SecurityUtils.hkdfSha256(
      phraseBytes,
      Uint8List.fromList(utf8.encode(_keySalt)),
      Uint8List.fromList(utf8.encode(_keyInfo)),
      32,
    );
    final key = base64Encode(derivedKey);
    await _secureStorage.storeDatabaseKey(key);
    SecurityUtils.secureClear(derivedKey);
  }

  Future<void> vacuum() async {
    final db = await database;
    await db.execute('VACUUM');
  }
}
