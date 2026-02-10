import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';
import '../secure_storage.dart';
import '../../utils/security.dart';
import '../../models/local/conversation.dart';
import '../../models/local/message.dart';
import '../../models/local/blocked_user.dart';
import '../../repositories/conversation_dao.dart';
import '../../repositories/message_dao.dart';
import '../../repositories/blocked_user_dao.dart';
import 'converters.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Conversations, Messages, BlockedUsers],
  daos: [ConversationDao, MessageDao, BlockedUserDao],
)
class AppDatabase extends _$AppDatabase {
  static AppDatabase? _instance;
  static const String _dbName = 'echo_protocol.db';
  static const String _keySalt = 'echo-protocol-local-db-v1';
  static const String _keyInfo = 'sqlcipher-key';

  AppDatabase._(super.e);

  @override
  int get schemaVersion => 1;

  static Future<AppDatabase> instance({
    SecureStorageService? secureStorage,
  }) async {
    if (_instance != null) return _instance!;
    _instance = await _create(secureStorage: secureStorage);
    return _instance!;
  }

  static Future<AppDatabase> _create({
    SecureStorageService? secureStorage,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('SQLCipher is not supported on web platform');
    }

    final storage = secureStorage ?? SecureStorageService();
    final key = await _getOrCreateKey(storage);
    final dbPath = await _getDatabasePath();

    return AppDatabase._(
      NativeDatabase.createInBackground(
        File(dbPath),
        setup: (db) {
          db.execute("PRAGMA key = '${_escapeKey(key)}'");
          db.execute('PRAGMA cipher_memory_security = ON');
          db.execute('PRAGMA cipher_page_size = 4096');
          db.execute('PRAGMA foreign_keys = ON');
          db.execute('PRAGMA secure_delete = ON');
          db.execute('PRAGMA temp_store = MEMORY');
        },
      ),
    );
  }

  static String _escapeKey(String key) {
    return key.replaceAll("'", "''");
  }

  static Future<String> _getOrCreateKey(SecureStorageService storage) async {
    final existingKey = await storage.getDatabaseKey();
    if (existingKey != null) return existingKey;

    final keyBytes = SecurityUtils.generateSecureRandomBytes(32);
    final key = base64Encode(keyBytes);
    await storage.storeDatabaseKey(key);
    SecurityUtils.secureClear(keyBytes);

    return key;
  }

  static Future<String> _getDatabasePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, _dbName);
  }

  Future<bool> verifyIntegrity() async {
    try {
      final result = await customSelect('PRAGMA integrity_check').get();
      return result.isNotEmpty &&
          result.first.data['integrity_check'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<void> clearAllData() async {
    await transaction(() async {
      await delete(messages).go();
      await delete(conversations).go();
      await delete(blockedUsers).go();
    });
  }

  Future<void> initializeWithRecoveryPhrase(
    Uint8List phraseBytes, {
    SecureStorageService? secureStorage,
  }) async {
    final storage = secureStorage ?? SecureStorageService();
    final derivedKey = SecurityUtils.hkdfSha256(
      phraseBytes,
      Uint8List.fromList(utf8.encode(_keySalt)),
      Uint8List.fromList(utf8.encode(_keyInfo)),
      32,
    );
    final key = base64Encode(derivedKey);
    await storage.storeDatabaseKey(key);
    SecurityUtils.secureClear(derivedKey);
  }

  Future<void> vacuum() async {
    await customStatement('VACUUM');
  }

  Future<void> deleteDb() async {
    await close();
    final path = await _getDatabasePath();
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    _instance = null;
  }

  static Future<void> resetInstance() async {
    if (_instance != null) {
      await _instance!.close();
      _instance = null;
    }
  }

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      beforeOpen: (details) async {
        // Ensure SQLCipher is loaded on Android
        open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
      },
    );
  }
}
