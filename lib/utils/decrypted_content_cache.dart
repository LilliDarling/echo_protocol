import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';
import '../services/secure_storage.dart';
import 'security.dart';

class DecryptedContentCacheService {
  final SecureStorageService _secureStorage;
  final Map<String, String> _cache = {};
  final List<String> _accessOrder = [];

  static const String _cacheSubdir = 'message_cache';
  static const String _cacheFileName = 'decrypted_content.enc';
  static const int _cacheVersion = 1;
  static const int _maxCacheSize = 1000;

  DecryptedContentCacheService({
    required SecureStorageService secureStorage,
  }) : _secureStorage = secureStorage;

  String? get(String messageId) {
    final value = _cache[messageId];
    if (value != null) {
      _accessOrder.remove(messageId);
      _accessOrder.add(messageId);
    }
    return value;
  }

  bool contains(String messageId) => _cache.containsKey(messageId);

  void put(String messageId, String decryptedContent) {
    if (_cache.containsKey(messageId)) {
      _accessOrder.remove(messageId);
    } else if (_cache.length >= _maxCacheSize) {
      final oldest = _accessOrder.removeAt(0);
      _cache.remove(oldest);
    }
    _cache[messageId] = decryptedContent;
    _accessOrder.add(messageId);
  }

  Map<String, String> get _memoryCache => _cache;

  Map<String, String> getAll() => Map.unmodifiable(_memoryCache);

  Future<void> loadFromDisk() async {
    try {
      final cacheFile = await _getCacheFile();
      if (!await cacheFile.exists()) {
        return;
      }

      final encryptedBytes = await cacheFile.readAsBytes();
      if (encryptedBytes.isEmpty) {
        return;
      }

      final cacheKey = await _getCacheKey();
      if (cacheKey == null) {
        await _deleteCacheFile();
        return;
      }

      final decryptedJson = _decryptCacheData(encryptedBytes, cacheKey);
      if (decryptedJson == null) {
        await _deleteCacheFile();
        return;
      }

      final cacheData = json.decode(decryptedJson) as Map<String, dynamic>;
      final version = cacheData['version'] as int? ?? 0;

      if (version != _cacheVersion) {
        await _deleteCacheFile();
        return;
      }

      final content = cacheData['content'] as Map<String, dynamic>? ?? {};

      if (content.values.any((v) => v == '[Unable to decrypt message]')) {
        await _deleteCacheFile();
        return;
      }

      final entries = content.entries.toList();
      final startIdx = entries.length > _maxCacheSize ? entries.length - _maxCacheSize : 0;
      for (var i = startIdx; i < entries.length; i++) {
        final key = entries[i].key;
        _cache[key] = entries[i].value.toString();
        _accessOrder.add(key);
      }
    } catch (e) {
      await _deleteCacheFile();
    }
  }

  Future<void> saveToDisk() async {
    if (_memoryCache.isEmpty) {
      return;
    }

    try {
      final cacheKey = await _getOrCreateCacheKey();

      final successfulCache = Map<String, String>.fromEntries(
        _memoryCache.entries.where((e) => e.value != '[Unable to decrypt message]'),
      );

      if (successfulCache.isEmpty) {
        return;
      }

      final cacheData = {
        'version': _cacheVersion,
        'timestamp': DateTime.now().toIso8601String(),
        'content': successfulCache,
      };

      final jsonData = json.encode(cacheData);
      final encryptedBytes = _encryptCacheData(jsonData, cacheKey);

      final cacheFile = await _getCacheFile();
      await cacheFile.parent.create(recursive: true);
      await cacheFile.writeAsBytes(encryptedBytes);
    } catch (e) {
      // Cache is optional optimization
    }
  }

  Future<void> clearAll() async {
    _cache.clear();
    _accessOrder.clear();
    await _deleteCacheFile();
    await _secureStorage.deleteCacheKey();
  }

  void remove(String messageId) {
    _cache.remove(messageId);
    _accessOrder.remove(messageId);
  }

  Future<Map<String, dynamic>> getStats() async {
    final cacheFile = await _getCacheFile();
    int diskSize = 0;
    if (await cacheFile.exists()) {
      diskSize = await cacheFile.length();
    }

    return {
      'memoryEntries': _memoryCache.length,
      'diskSizeBytes': diskSize,
    };
  }

  Future<File> _getCacheFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    return File('${appDir.path}/$_cacheSubdir/$_cacheFileName');
  }

  Future<void> _deleteCacheFile() async {
    final cacheFile = await _getCacheFile();
    if (await cacheFile.exists()) {
      await cacheFile.delete();
    }
  }

  Future<Uint8List?> _getCacheKey() async {
    final keyBase64 = await _secureStorage.getCacheKey();
    if (keyBase64 == null) return null;
    return base64.decode(keyBase64);
  }

  Future<Uint8List> _getOrCreateCacheKey() async {
    final existing = await _getCacheKey();
    if (existing != null) return existing;

    final key = SecurityUtils.generateSecureRandomBytes(32);
    await _secureStorage.storeCacheKey(base64.encode(key));
    return key;
  }

  Uint8List _encryptCacheData(String plaintext, Uint8List key) {
    final iv = SecurityUtils.generateSecureRandomBytes(12);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          128,
          iv,
          Uint8List(0),
        ),
      );

    final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));
    final ciphertext = cipher.process(plaintextBytes);

    final result = Uint8List(iv.length + ciphertext.length);
    result.setAll(0, iv);
    result.setAll(iv.length, ciphertext);
    return result;
  }

  String? _decryptCacheData(Uint8List encryptedData, Uint8List key) {
    try {
      if (encryptedData.length < 12) return null;

      final iv = encryptedData.sublist(0, 12);
      final ciphertext = encryptedData.sublist(12);

      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(
            KeyParameter(key),
            128,
            iv,
            Uint8List(0),
          ),
        );

      final plaintext = cipher.process(ciphertext);
      return utf8.decode(plaintext);
    } catch (e) {
      return null;
    }
  }
}
