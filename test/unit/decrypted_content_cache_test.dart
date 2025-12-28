import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:echo_protocol/utils/decrypted_content_cache.dart';
import 'package:echo_protocol/services/secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DecryptedContentCacheService', () {
    late DecryptedContentCacheService cacheService;
    late SecureStorageService secureStorage;
    late Directory tempDir;

    setUp(() async {
      // Set up mock secure storage
      FlutterSecureStorage.setMockInitialValues({});

      // Create temp directory for tests
      tempDir = await Directory.systemTemp.createTemp('cache_test_');

      secureStorage = SecureStorageService();
      cacheService = DecryptedContentCacheService(secureStorage: secureStorage);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('In-memory cache operations', () {
      test('put and get work correctly', () {
        cacheService.put('msg-1', 'Hello World');
        cacheService.put('msg-2', 'Another message');

        expect(cacheService.get('msg-1'), equals('Hello World'));
        expect(cacheService.get('msg-2'), equals('Another message'));
      });

      test('get returns null for non-existent key', () {
        expect(cacheService.get('non-existent'), isNull);
      });

      test('contains returns correct values', () {
        cacheService.put('msg-1', 'Hello');

        expect(cacheService.contains('msg-1'), isTrue);
        expect(cacheService.contains('msg-2'), isFalse);
      });

      test('remove removes entry from cache', () {
        cacheService.put('msg-1', 'Hello');
        expect(cacheService.contains('msg-1'), isTrue);

        cacheService.remove('msg-1');
        expect(cacheService.contains('msg-1'), isFalse);
        expect(cacheService.get('msg-1'), isNull);
      });

      test('getAll returns unmodifiable map', () {
        cacheService.put('msg-1', 'Hello');
        cacheService.put('msg-2', 'World');

        final all = cacheService.getAll();
        expect(all.length, equals(2));
        expect(all['msg-1'], equals('Hello'));
        expect(all['msg-2'], equals('World'));

        // Should be unmodifiable
        expect(() => all['msg-3'] = 'Test', throwsUnsupportedError);
      });

      test('put overwrites existing value', () {
        cacheService.put('msg-1', 'Original');
        expect(cacheService.get('msg-1'), equals('Original'));

        cacheService.put('msg-1', 'Updated');
        expect(cacheService.get('msg-1'), equals('Updated'));
      });

      test('handles empty string values', () {
        cacheService.put('msg-1', '');
        expect(cacheService.get('msg-1'), equals(''));
        expect(cacheService.contains('msg-1'), isTrue);
      });
    });

    group('Unicode and special characters', () {
      test('handles unicode content correctly', () {
        cacheService.put('msg-1', 'Hello 世界 🌍');
        cacheService.put('msg-2', 'Привет мир');
        cacheService.put('msg-3', '日本語テスト');

        expect(cacheService.get('msg-1'), equals('Hello 世界 🌍'));
        expect(cacheService.get('msg-2'), equals('Привет мир'));
        expect(cacheService.get('msg-3'), equals('日本語テスト'));
      });

      test('handles special JSON characters correctly', () {
        cacheService.put('msg-1', 'Quote: "Hello"');
        cacheService.put('msg-2', 'Backslash: \\path\\to\\file');
        cacheService.put('msg-3', 'Newline:\nTab:\t');

        expect(cacheService.get('msg-1'), equals('Quote: "Hello"'));
        expect(cacheService.get('msg-2'), equals('Backslash: \\path\\to\\file'));
        expect(cacheService.get('msg-3'), equals('Newline:\nTab:\t'));
      });

      test('handles emoji correctly', () {
        cacheService.put('msg-1', '❤️ 💕 😀 🎉');
        expect(cacheService.get('msg-1'), equals('❤️ 💕 😀 🎉'));
      });
    });

    group('Large content handling', () {
      test('handles large number of messages', () {
        // Add 1000 messages
        for (int i = 0; i < 1000; i++) {
          cacheService.put('msg-$i', 'Message content number $i');
        }

        // Verify all messages are stored
        expect(cacheService.getAll().length, equals(1000));
        expect(cacheService.get('msg-0'), equals('Message content number 0'));
        expect(cacheService.get('msg-999'), equals('Message content number 999'));
      });

      test('handles large message content', () {
        // Create a large message (100KB)
        final largeContent = 'A' * 100000;
        cacheService.put('msg-large', largeContent);

        expect(cacheService.get('msg-large'), equals(largeContent));
        expect(cacheService.get('msg-large')!.length, equals(100000));
      });
    });

    group('Concurrent operations', () {
      test('multiple rapid puts work correctly', () {
        for (int i = 0; i < 100; i++) {
          cacheService.put('msg-$i', 'Value $i');
        }

        for (int i = 0; i < 100; i++) {
          expect(cacheService.get('msg-$i'), equals('Value $i'));
        }
      });

      test('interleaved put and remove work correctly', () {
        cacheService.put('msg-1', 'First');
        cacheService.put('msg-2', 'Second');
        cacheService.remove('msg-1');
        cacheService.put('msg-3', 'Third');
        cacheService.remove('msg-2');
        cacheService.put('msg-1', 'First Again');

        expect(cacheService.contains('msg-1'), isTrue);
        expect(cacheService.contains('msg-2'), isFalse);
        expect(cacheService.contains('msg-3'), isTrue);
        expect(cacheService.get('msg-1'), equals('First Again'));
      });
    });
  });

  group('SecureStorageService cache key methods', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    // These tests require Firebase Auth to be initialized because
    // SecureStorageService uses FirebaseAuth.instance internally.
    // Skip until proper Firebase mocking is added.
    test('storeCacheKey and getCacheKey work correctly', () async {
      final secureStorage = SecureStorageService();

      await secureStorage.storeCacheKey('test-key-base64');
      final retrieved = await secureStorage.getCacheKey();

      expect(retrieved, equals('test-key-base64'));
    }, skip: 'Requires Firebase Auth mock');

    test('deleteCacheKey removes the key', () async {
      final secureStorage = SecureStorageService();

      await secureStorage.storeCacheKey('test-key-base64');
      expect(await secureStorage.getCacheKey(), isNotNull);

      await secureStorage.deleteCacheKey();
      expect(await secureStorage.getCacheKey(), isNull);
    }, skip: 'Requires Firebase Auth mock');

    test('getCacheKey returns null when no key stored', () async {
      final secureStorage = SecureStorageService();

      final key = await secureStorage.getCacheKey();
      expect(key, isNull);
    }, skip: 'Requires Firebase Auth mock');

    test('storeCacheKey overwrites existing key', () async {
      final secureStorage = SecureStorageService();

      await secureStorage.storeCacheKey('first-key');
      expect(await secureStorage.getCacheKey(), equals('first-key'));

      await secureStorage.storeCacheKey('second-key');
      expect(await secureStorage.getCacheKey(), equals('second-key'));
    }, skip: 'Requires Firebase Auth mock');

    test('handles base64 encoded keys correctly', () async {
      final secureStorage = SecureStorageService();

      // Generate a valid base64 key (32 bytes = 256 bits)
      final keyBytes = List.generate(32, (i) => i);
      final base64Key = base64.encode(keyBytes);

      await secureStorage.storeCacheKey(base64Key);
      final retrieved = await secureStorage.getCacheKey();

      expect(retrieved, equals(base64Key));

      // Verify it decodes back correctly
      final decodedBytes = base64.decode(retrieved!);
      expect(decodedBytes.length, equals(32));
    }, skip: 'Requires Firebase Auth mock');
  });

  group('Cache service initialization', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('new instance starts with empty cache', () {
      final secureStorage = SecureStorageService();
      final cacheService = DecryptedContentCacheService(
        secureStorage: secureStorage,
      );

      expect(cacheService.getAll().isEmpty, isTrue);
    });

    test('multiple instances share same secure storage', () async {
      final secureStorage = SecureStorageService();

      final cache1 = DecryptedContentCacheService(secureStorage: secureStorage);
      final cache2 = DecryptedContentCacheService(secureStorage: secureStorage);

      // Add to first instance
      cache1.put('msg-1', 'Hello');

      // Second instance has separate memory cache
      expect(cache2.contains('msg-1'), isFalse);

      // But they share the same secure storage for the encryption key
      await secureStorage.storeCacheKey('shared-key');
      expect(await secureStorage.getCacheKey(), equals('shared-key'));
    }, skip: 'Requires Firebase Auth mock');
  });

  group('Edge cases', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('handles message IDs with special characters', () {
      final secureStorage = SecureStorageService();
      final cacheService = DecryptedContentCacheService(
        secureStorage: secureStorage,
      );

      cacheService.put('msg:with:colons', 'Content 1');
      cacheService.put('msg/with/slashes', 'Content 2');
      cacheService.put('msg-with-dashes', 'Content 3');
      cacheService.put('msg_with_underscores', 'Content 4');

      expect(cacheService.get('msg:with:colons'), equals('Content 1'));
      expect(cacheService.get('msg/with/slashes'), equals('Content 2'));
      expect(cacheService.get('msg-with-dashes'), equals('Content 3'));
      expect(cacheService.get('msg_with_underscores'), equals('Content 4'));
    });

    test('handles null-like string values', () {
      final secureStorage = SecureStorageService();
      final cacheService = DecryptedContentCacheService(
        secureStorage: secureStorage,
      );

      cacheService.put('msg-1', 'null');
      cacheService.put('msg-2', 'undefined');
      cacheService.put('msg-3', 'None');

      expect(cacheService.get('msg-1'), equals('null'));
      expect(cacheService.get('msg-2'), equals('undefined'));
      expect(cacheService.get('msg-3'), equals('None'));
    });

    test('remove non-existent key does not throw', () {
      final secureStorage = SecureStorageService();
      final cacheService = DecryptedContentCacheService(
        secureStorage: secureStorage,
      );

      // Should not throw
      cacheService.remove('non-existent');
      expect(cacheService.contains('non-existent'), isFalse);
    });
  });
}
