import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_protocol/services/encryption.dart';
import 'package:echo_protocol/utils/security.dart';

void main() {
  group('GCM Authentication Tag Validation', () {
    late EncryptionService aliceService;
    late EncryptionService bobService;

    setUp(() async {
      aliceService = EncryptionService();
      bobService = EncryptionService();

      final aliceKeys = await aliceService.generateKeyPair();
      final bobKeys = await bobService.generateKeyPair();

      aliceService.setPrivateKey(aliceKeys['privateKey']!);
      bobService.setPrivateKey(bobKeys['privateKey']!);

      aliceService.setPartnerPublicKey(bobKeys['publicKey']!);
      bobService.setPartnerPublicKey(aliceKeys['publicKey']!);
    });

    test('should reject ciphertext that is too short to contain auth tag', () {
      final tooShortCiphertext = 'invalidIV123456:${base64Encode([1, 2, 3, 4, 5])}';

      expect(
        () => aliceService.decryptMessage(tooShortCiphertext),
        throwsA(isA<Exception>()),
      );
    });

    test('should reject ciphertext with invalid auth tag', () {
      final plaintext = 'Test message';
      final encrypted = aliceService.encryptMessage(plaintext);

      final parts = encrypted.split(':');
      final iv = parts[0];
      final ciphertextBytes = base64Decode(parts[1]);

      ciphertextBytes[ciphertextBytes.length - 1] ^= 0xFF;

      final tamperedCiphertext = '$iv:${base64Encode(ciphertextBytes)}';

      expect(
        () => bobService.decryptMessage(tamperedCiphertext),
        throwsA(isA<Exception>()),
      );
    });

    test('should successfully decrypt message with valid auth tag', () {
      final plaintext = 'Valid message with proper authentication';
      final encrypted = aliceService.encryptMessage(plaintext);

      final decrypted = bobService.decryptMessage(encrypted);

      expect(decrypted, equals(plaintext));
    });

    test('validateGcmCiphertext should reject too-short ciphertext', () {
      final shortCiphertext = Uint8List.fromList([1, 2, 3, 4, 5]);

      expect(
        () => SecurityUtils.validateGcmCiphertext(shortCiphertext),
        throwsArgumentError,
      );
    });

    test('validateGcmCiphertext should accept valid length ciphertext', () {
      final validCiphertext = Uint8List.fromList(List.filled(32, 0));

      expect(
        () => SecurityUtils.validateGcmCiphertext(validCiphertext),
        returnsNormally,
      );
    });

    test('should reject file ciphertext too short for auth tag', () {
      final tooShortFile = Uint8List.fromList(List.filled(20, 0));

      expect(
        () => aliceService.decryptFile(tooShortFile),
        throwsA(isA<Exception>()),
      );
    });

    test('file decryption validates minimum length (IV + auth tag)', () {
      final plainFile = Uint8List.fromList(utf8.encode('Test file content'));
      final encryptedFile = aliceService.encryptFile(plainFile);

      expect(encryptedFile.length, greaterThan(32));
    });

    test('should successfully decrypt file with valid encryption', () {
      final plainFile = Uint8List.fromList(utf8.encode('Valid file content'));
      final encryptedFile = aliceService.encryptFile(plainFile);

      final decryptedFile = bobService.decryptFile(encryptedFile);

      expect(decryptedFile, equals(plainFile));
    });

    test('should validate minimum ciphertext length (16 bytes for GCM tag)', () {
      final exactlyTagLength = Uint8List.fromList(List.filled(16, 0));

      expect(
        () => SecurityUtils.validateGcmCiphertext(exactlyTagLength),
        returnsNormally,
      );
    });

    test('should reject ciphertext shorter than GCM tag', () {
      final belowTagLength = Uint8List.fromList(List.filled(15, 0));

      expect(
        () => SecurityUtils.validateGcmCiphertext(belowTagLength),
        throwsArgumentError,
      );
    });
  });
}
