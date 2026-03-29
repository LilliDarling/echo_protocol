import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:echo_protocol/services/secure_storage.dart';
import 'package:echo_protocol/services/vault/vault_encryption_service.dart';
import 'package:echo_protocol/utils/security.dart';

@GenerateMocks([SecureStorageService])
import 'vault_encryption_service_test.mocks.dart';

void main() {
  group('VaultEncryptionService', () {
    late VaultEncryptionService service;
    late MockSecureStorageService mockStorage;
    late String vaultKeyBase64;

    setUp(() {
      mockStorage = MockSecureStorageService();
      service = VaultEncryptionService(storage: mockStorage);

      final vaultKey = SecurityUtils.generateSecureRandomBytes(32);
      vaultKeyBase64 = base64Encode(vaultKey);
    });

    group('encryptChunk', () {
      test('encrypts and produces output larger than nonce+mac overhead', () async {
        when(mockStorage.getVaultKey())
            .thenAnswer((_) async => vaultKeyBase64);

        final plaintext =
            Uint8List.fromList(utf8.encode('{"messages": "test data"}'));
        final encrypted = await service.encryptChunk(
          plaintext: plaintext,
          chunkId: 'chunk_001',
        );

        // Must be at least nonce(12) + mac(16) = 28 bytes
        expect(encrypted.length, greaterThanOrEqualTo(28));
      });

      test('throws when vault key is not available', () async {
        when(mockStorage.getVaultKey()).thenAnswer((_) async => null);

        expect(
          () => service.encryptChunk(
            plaintext: Uint8List.fromList([1, 2, 3]),
            chunkId: 'chunk_001',
          ),
          throwsA(predicate(
              (e) => e.toString().contains('Vault key not available'))),
        );
      });

      test('different nonces produce different ciphertext', () async {
        when(mockStorage.getVaultKey())
            .thenAnswer((_) async => vaultKeyBase64);

        final plaintext =
            Uint8List.fromList(utf8.encode('same plaintext data'));
        final enc1 = await service.encryptChunk(
          plaintext: plaintext,
          chunkId: 'chunk_001',
        );
        final enc2 = await service.encryptChunk(
          plaintext: plaintext,
          chunkId: 'chunk_001',
        );

        // Nonces should differ (first 12 bytes)
        final nonce1 = enc1.sublist(0, 12);
        final nonce2 = enc2.sublist(0, 12);
        expect(
          SecurityUtils.constantTimeBytesEquals(nonce1, nonce2),
          isFalse,
        );
      });
    });

    group('decryptChunk', () {
      test('round-trip encrypt then decrypt restores original data', () async {
        when(mockStorage.getVaultKey())
            .thenAnswer((_) async => vaultKeyBase64);

        final original = Uint8List.fromList(
          utf8.encode('{"conversations": [], "chunkIndex": 1}'),
        );

        final encrypted = await service.encryptChunk(
          plaintext: original,
          chunkId: 'chunk_042',
        );

        final decrypted = await service.decryptChunk(
          encrypted: encrypted,
          chunkId: 'chunk_042',
        );

        expect(utf8.decode(decrypted), utf8.decode(original));
      });

      test('fails with wrong chunkId (AAD mismatch)', () async {
        when(mockStorage.getVaultKey())
            .thenAnswer((_) async => vaultKeyBase64);

        final plaintext = Uint8List.fromList(utf8.encode('secret data'));
        final encrypted = await service.encryptChunk(
          plaintext: plaintext,
          chunkId: 'chunk_correct',
        );

        expect(
          () => service.decryptChunk(
            encrypted: encrypted,
            chunkId: 'chunk_wrong',
          ),
          throwsA(anything),
        );
      });

      test('throws on data shorter than minimum length', () async {
        when(mockStorage.getVaultKey())
            .thenAnswer((_) async => vaultKeyBase64);

        expect(
          () => service.decryptChunk(
            encrypted: Uint8List.fromList([1, 2, 3]),
            chunkId: 'chunk_001',
          ),
          throwsA(predicate(
              (e) => e.toString().contains('Invalid vault chunk data'))),
        );
      });

      test('throws when vault key is not available', () async {
        when(mockStorage.getVaultKey()).thenAnswer((_) async => null);

        expect(
          () => service.decryptChunk(
            encrypted: Uint8List(30),
            chunkId: 'chunk_001',
          ),
          throwsA(predicate(
              (e) => e.toString().contains('Vault key not available'))),
        );
      });
    });

    group('compression', () {
      test('gzip compression reduces size for repetitive data', () async {
        when(mockStorage.getVaultKey())
            .thenAnswer((_) async => vaultKeyBase64);

        // Create highly compressible data
        final repeated = 'a' * 10000;
        final plaintext = Uint8List.fromList(utf8.encode(repeated));

        final encrypted = await service.encryptChunk(
          plaintext: plaintext,
          chunkId: 'chunk_compress',
        );

        // Encrypted output should be much smaller than plaintext due to gzip
        // (28 bytes overhead for nonce+mac, but gzip should compress 10000 'a's heavily)
        expect(encrypted.length, lessThan(plaintext.length));
      });
    });

    group('computeChecksum', () {
      test('produces consistent SHA-256 hex string', () {
        final data = Uint8List.fromList(utf8.encode('test data'));
        final checksum1 = VaultEncryptionService.computeChecksum(data);
        final checksum2 = VaultEncryptionService.computeChecksum(data);

        expect(checksum1, checksum2);
        expect(checksum1.length, 64); // SHA-256 hex is 64 chars
      });

      test('different data produces different checksums', () {
        final data1 = Uint8List.fromList(utf8.encode('data one'));
        final data2 = Uint8List.fromList(utf8.encode('data two'));

        expect(
          VaultEncryptionService.computeChecksum(data1),
          isNot(VaultEncryptionService.computeChecksum(data2)),
        );
      });
    });

    group('isVaultKeyAvailable', () {
      test('returns true when vault key is stored', () async {
        when(mockStorage.getVaultKey())
            .thenAnswer((_) async => vaultKeyBase64);

        expect(await service.isVaultKeyAvailable, isTrue);
      });

      test('returns false when vault key is not stored', () async {
        when(mockStorage.getVaultKey()).thenAnswer((_) async => null);

        expect(await service.isVaultKeyAvailable, isFalse);
      });
    });
  });
}
