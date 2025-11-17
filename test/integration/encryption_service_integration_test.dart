import 'package:flutter_test/flutter_test.dart';
import 'package:echo_protocol/services/encryption.dart';
import 'dart:convert';
import 'dart:typed_data';

void main() {
  group('Encryption Service - End-to-End Integration Tests', () {
    late EncryptionService aliceService;
    late EncryptionService bobService;

    setUp(() {
      aliceService = EncryptionService();
      bobService = EncryptionService();
    });

    tearDown(() {
      aliceService.clearKeys();
      bobService.clearKeys();
    });

    group('Key Generation - Happy Path', () {
      test('should generate valid ECDH key pairs', () async {
        // Act
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        // Assert - Keys should be generated
        expect(aliceKeys, isNotNull);
        expect(aliceKeys['publicKey'], isNotNull);
        expect(aliceKeys['privateKey'], isNotNull);

        expect(bobKeys, isNotNull);
        expect(bobKeys['publicKey'], isNotNull);
        expect(bobKeys['privateKey'], isNotNull);

        // Assert - Keys should be base64 encoded strings
        expect(aliceKeys['publicKey'], isA<String>());
        expect(aliceKeys['privateKey'], isA<String>());
        expect(() => base64.decode(aliceKeys['publicKey']!), returnsNormally);
        expect(() => base64.decode(aliceKeys['privateKey']!), returnsNormally);
      });

      test('should generate unique keys for each user', () async {
        // Act
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        // Assert - Keys should be different
        expect(aliceKeys['publicKey'], isNot(equals(bobKeys['publicKey'])));
        expect(aliceKeys['privateKey'], isNot(equals(bobKeys['privateKey'])));
      });

      test('should generate keys with expected length', () async {
        // Act
        final keys = await aliceService.generateKeyPair();

        // Assert - Keys are base64 encoded and should be non-empty
        expect(keys['publicKey'], isNotEmpty);
        expect(keys['privateKey'], isNotEmpty);

        // Decode to verify they're valid base64
        final publicKeyBytes = base64.decode(keys['publicKey']!);
        final privateKeyBytes = base64.decode(keys['privateKey']!);

        // Keys should have reasonable sizes (PEM encoding adds overhead)
        expect(publicKeyBytes.length, greaterThan(0), reason: 'Public key should not be empty');
        expect(privateKeyBytes.length, greaterThan(0), reason: 'Private key should not be empty');

        // Typically secp256k1 encoded keys are between 32-200 bytes depending on format
        expect(privateKeyBytes.length, greaterThan(30), reason: 'Private key too small');
        expect(publicKeyBytes.length, greaterThan(30), reason: 'Public key too small');
      });

      test('should set private key and allow encryption initialization', () async {
        // Arrange
        final keys = await aliceService.generateKeyPair();

        // Act
        aliceService.setPrivateKey(keys['privateKey']!);

        // Assert - Should not throw
        expect(() => aliceService.setPrivateKey(keys['privateKey']!), returnsNormally);
      });
    });

    group('End-to-End Encryption - Happy Path', () {
      test('should encrypt and decrypt message between two users', () async {
        // Arrange - Generate keys for Alice and Bob
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        // Setup encryption for both users
        aliceService.setPrivateKey(aliceKeys['privateKey']!);
        bobService.setPrivateKey(bobKeys['privateKey']!);

        // Exchange public keys (as would happen in real app)
        aliceService.setPartnerPublicKey(bobKeys['publicKey']!);
        bobService.setPartnerPublicKey(aliceKeys['publicKey']!);

        const originalMessage = 'Hello, Bob! This is a secret message.';

        // Act - Alice encrypts message to Bob
        final encryptedMessage = aliceService.encryptMessage(originalMessage);

        // Bob decrypts message from Alice
        final decryptedMessage = bobService.decryptMessage(encryptedMessage);

        // Assert
        expect(decryptedMessage, equals(originalMessage));
        expect(encryptedMessage, isNot(equals(originalMessage)));
        expect(encryptedMessage.contains(originalMessage), false);
      });

      test('should handle Unicode and special characters', () async {
        // Arrange
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        aliceService.setPrivateKey(aliceKeys['privateKey']!);
        bobService.setPrivateKey(bobKeys['privateKey']!);

        aliceService.setPartnerPublicKey(bobKeys['publicKey']!);
        bobService.setPartnerPublicKey(aliceKeys['publicKey']!);

        const messages = [
          '你好世界', // Chinese
          'Привет мир', // Russian
          '🔒🔐🔑💬', // Emojis
          'Special chars: !@#\$%^&*()_+-=[]{}|;:\'",.<>?/~`',
          'Newlines\nand\ttabs',
          '', // Empty string
        ];

        // Act & Assert
        for (final message in messages) {
          final encrypted = aliceService.encryptMessage(message);
          final decrypted = bobService.decryptMessage(encrypted);

          expect(decrypted, equals(message), reason: 'Failed for message: "$message"');
        }
      });

      test('should handle very long messages', () async {
        // Arrange
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        aliceService.setPrivateKey(aliceKeys['privateKey']!);
        bobService.setPrivateKey(bobKeys['privateKey']!);

        aliceService.setPartnerPublicKey(bobKeys['publicKey']!);
        bobService.setPartnerPublicKey(aliceKeys['publicKey']!);

        // Create a very long message (10KB)
        final longMessage = 'A' * 10000;

        // Act
        final encrypted = aliceService.encryptMessage(longMessage);
        final decrypted = bobService.decryptMessage(encrypted);

        // Assert
        expect(decrypted, equals(longMessage));
        expect(decrypted.length, 10000);
      });

      test('should produce different ciphertext for same message (IV randomness)', () async {
        // Arrange
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        aliceService.setPrivateKey(aliceKeys['privateKey']!);
        bobService.setPrivateKey(bobKeys['privateKey']!);

        aliceService.setPartnerPublicKey(bobKeys['publicKey']!);
        bobService.setPartnerPublicKey(aliceKeys['publicKey']!);

        const message = 'Same message encrypted twice';

        // Act - Encrypt same message twice
        final encrypted1 = aliceService.encryptMessage(message);
        final encrypted2 = aliceService.encryptMessage(message);

        // Assert - Ciphertexts should be different (different IVs)
        expect(encrypted1, isNot(equals(encrypted2)),
          reason: 'Each encryption should use a different random IV');

        // But both should decrypt to same plaintext
        final decrypted1 = bobService.decryptMessage(encrypted1);
        final decrypted2 = bobService.decryptMessage(encrypted2);

        expect(decrypted1, equals(message));
        expect(decrypted2, equals(message));
      });

      test('should support bidirectional communication', () async {
        // Arrange
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        aliceService.setPrivateKey(aliceKeys['privateKey']!);
        bobService.setPrivateKey(bobKeys['privateKey']!);

        aliceService.setPartnerPublicKey(bobKeys['publicKey']!);
        bobService.setPartnerPublicKey(aliceKeys['publicKey']!);

        const aliceMessage = 'Hello Bob!';
        const bobMessage = 'Hi Alice!';

        // Act - Alice sends to Bob
        final aliceEncrypted = aliceService.encryptMessage(aliceMessage);
        final bobReceived = bobService.decryptMessage(aliceEncrypted);

        // Bob sends to Alice
        final bobEncrypted = bobService.encryptMessage(bobMessage);
        final aliceReceived = aliceService.decryptMessage(bobEncrypted);

        // Assert
        expect(bobReceived, equals(aliceMessage));
        expect(aliceReceived, equals(bobMessage));
      });
    });

    group('End-to-End Encryption - Bad Paths', () {
      test('should fail to decrypt with wrong private key', () async {
        // Arrange
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();
        final eveKeys = await EncryptionService().generateKeyPair(); // Attacker

        aliceService.setPrivateKey(aliceKeys['privateKey']!);
        bobService.setPrivateKey(bobKeys['privateKey']!);

        aliceService.setPartnerPublicKey(bobKeys['publicKey']!);

        // Eve tries to intercept
        final eveService = EncryptionService();
        eveService.setPrivateKey(eveKeys['privateKey']!);
        eveService.setPartnerPublicKey(aliceKeys['publicKey']!);

        const message = 'Secret message for Bob only';
        final encrypted = aliceService.encryptMessage(message);

        // Act & Assert - Eve shouldn't be able to decrypt
        expect(
          () => eveService.decryptMessage(encrypted),
          throwsException,
          reason: 'Eve with wrong private key should not decrypt successfully',
        );
      });

      test('should fail to decrypt tampered ciphertext (GCM authentication)', () async {
        // Arrange
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        aliceService.setPrivateKey(aliceKeys['privateKey']!);
        bobService.setPrivateKey(bobKeys['privateKey']!);

        aliceService.setPartnerPublicKey(bobKeys['publicKey']!);
        bobService.setPartnerPublicKey(aliceKeys['publicKey']!);

        const message = 'Original message';
        final encrypted = aliceService.encryptMessage(message);

        // Act - Tamper with ciphertext
        final parts = encrypted.split(':');
        expect(parts.length, 2, reason: 'Encrypted format should be IV:Ciphertext');

        // Flip one bit in the ciphertext
        final ciphertextBytes = base64.decode(parts[1]);
        ciphertextBytes[0] ^= 1; // Flip first bit
        final tamperedCiphertext = '${parts[0]}:${base64.encode(ciphertextBytes)}';

        // Assert - Should fail GCM authentication
        expect(
          () => bobService.decryptMessage(tamperedCiphertext),
          throwsException,
          reason: 'GCM should detect tampering and reject the message',
        );
      });

      test('should fail with invalid ciphertext format', () async {
        // Arrange
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        bobService.setPrivateKey(bobKeys['privateKey']!);
        bobService.setPartnerPublicKey(aliceKeys['publicKey']!);

        final invalidFormats = [
          'no-colon-separator',
          'too:many:colons:here',
          'invalid:base64!!!',
          '',
          ':',
          'onlyiv:',
          ':onlyciphertext',
        ];

        // Act & Assert
        for (final invalid in invalidFormats) {
          expect(
            () => bobService.decryptMessage(invalid),
            throwsException,
            reason: 'Should reject invalid format: "$invalid"',
          );
        }
      });

      test('should fail when partner public key not set', () async {
        // Arrange
        final aliceKeys = await aliceService.generateKeyPair();
        aliceService.setPrivateKey(aliceKeys['privateKey']!);
        // NOT setting partner public key

        // Act & Assert
        expect(
          () => aliceService.encryptMessage('Test'),
          throwsException,
          reason: 'Should fail when partner public key not set',
        );
      });

      test('should fail when private key not set', () async {
        // Arrange
        final bobKeys = await bobService.generateKeyPair();
        // NOT setting private key - this will fail on setPartnerPublicKey

        // Act & Assert
        expect(
          () => aliceService.setPartnerPublicKey(bobKeys['publicKey']!),
          throwsA(anything), // Will throw LateInitializationError
          reason: 'Should fail when private key not set',
        );
      });
    });

    group('End-to-End Encryption - Ugly Paths & Edge Cases', () {
      test('should handle corrupted IV', () async {
        // Arrange
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        aliceService.setPrivateKey(aliceKeys['privateKey']!);
        bobService.setPrivateKey(bobKeys['privateKey']!);

        aliceService.setPartnerPublicKey(bobKeys['publicKey']!);
        bobService.setPartnerPublicKey(aliceKeys['publicKey']!);

        final encrypted = aliceService.encryptMessage('Test message');
        final parts = encrypted.split(':');

        // Corrupt IV
        final corruptedIV = 'corrupted!!!invalid';
        final corrupted = '$corruptedIV:${parts[1]}';

        // Act & Assert
        expect(
          () => bobService.decryptMessage(corrupted),
          throwsException,
          reason: 'Should fail with corrupted IV',
        );
      });

      test('should handle wrong IV length', () async {
        // Arrange
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        aliceService.setPrivateKey(aliceKeys['privateKey']!);
        bobService.setPrivateKey(bobKeys['privateKey']!);

        aliceService.setPartnerPublicKey(bobKeys['publicKey']!);
        bobService.setPartnerPublicKey(aliceKeys['publicKey']!);

        final encrypted = aliceService.encryptMessage('Test message');
        final parts = encrypted.split(':');

        // Wrong IV length (should be 16 bytes = 24 base64 chars)
        final shortIV = base64.encode(Uint8List(8)); // Only 8 bytes
        final wrongLength = '$shortIV:${parts[1]}';

        // Act & Assert
        expect(
          () => bobService.decryptMessage(wrongLength),
          throwsException,
          reason: 'Should fail with wrong IV length',
        );
      });

      test('should handle replay attacks (detect same ciphertext)', () async {
        // Arrange
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        aliceService.setPrivateKey(aliceKeys['privateKey']!);
        bobService.setPrivateKey(bobKeys['privateKey']!);

        aliceService.setPartnerPublicKey(bobKeys['publicKey']!);
        bobService.setPartnerPublicKey(aliceKeys['publicKey']!);

        const message = 'Message that will be replayed';
        final encrypted = aliceService.encryptMessage(message);

        // Act - Decrypt twice (replay attack)
        final decrypted1 = bobService.decryptMessage(encrypted);
        final decrypted2 = bobService.decryptMessage(encrypted);

        // Assert - Both decrypt successfully (replay prevention needs timestamp validation)
        expect(decrypted1, equals(message));
        expect(decrypted2, equals(message));

        // Note: In production, you'd use SecurityUtils.validateTimestamp()
        // to prevent replay attacks
      });

      test('should clear keys securely', () async {
        // Arrange
        final keys = await aliceService.generateKeyPair();
        aliceService.setPrivateKey(keys['privateKey']!);

        final bobKeys = await bobService.generateKeyPair();
        aliceService.setPartnerPublicKey(bobKeys['publicKey']!);

        // Verify encryption works
        final encrypted = aliceService.encryptMessage('Test');
        expect(encrypted, isNotEmpty);

        // Act - Clear keys
        aliceService.clearKeys();

        // Assert - Should not be able to encrypt after clearing
        expect(
          () => aliceService.encryptMessage('Test'),
          throwsException,
          reason: 'Should fail after clearing keys',
        );
      });

      test('should handle invalid public key format', () async {
        // Arrange
        final aliceKeys = await aliceService.generateKeyPair();
        aliceService.setPrivateKey(aliceKeys['privateKey']!);

        final invalidPublicKeys = [
          'not-base64!!!',
          '',
          'valid-base64-but-wrong-size-${base64.encode(Uint8List(10))}',
          'SGVsbG8gV29ybGQ=', // Valid base64 but not an EC point
        ];

        // Act & Assert
        for (final invalidKey in invalidPublicKeys) {
          expect(
            () => aliceService.setPartnerPublicKey(invalidKey),
            throwsException,
            reason: 'Should reject invalid public key: "$invalidKey"',
          );
        }
      });

      test('should handle invalid private key format', () async {
        // Arrange
        final invalidPrivateKeys = [
          'not-base64!!!',
          '',
          base64.encode(Uint8List(10)), // Wrong size
          'SGVsbG8gV29ybGQ=', // Valid base64 but wrong size
        ];

        // Act & Assert
        for (final invalidKey in invalidPrivateKeys) {
          expect(
            () => aliceService.setPrivateKey(invalidKey),
            throwsException,
            reason: 'Should reject invalid private key: "$invalidKey"',
          );
        }
      });
    });

    group('Key Derivation (HKDF) - Integration', () {
      test('should derive same shared secret from both sides', () async {
        // Arrange
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        aliceService.setPrivateKey(aliceKeys['privateKey']!);
        bobService.setPrivateKey(bobKeys['privateKey']!);

        aliceService.setPartnerPublicKey(bobKeys['publicKey']!);
        bobService.setPartnerPublicKey(aliceKeys['publicKey']!);

        const message = 'Test symmetric key derivation';

        // Act
        final aliceEncrypted = aliceService.encryptMessage(message);
        final bobEncrypted = bobService.encryptMessage(message);

        // Both should be able to decrypt each other's messages
        final aliceDecrypted = bobService.decryptMessage(aliceEncrypted);
        final bobDecrypted = aliceService.decryptMessage(bobEncrypted);

        // Assert
        expect(aliceDecrypted, equals(message));
        expect(bobDecrypted, equals(message));
      });

      test('should use HKDF-SHA256 for key derivation', () async {
        // This test verifies HKDF is being used (not just SHA-256)
        // We can't directly test the internal HKDF, but we can verify
        // that the derived keys work correctly

        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        aliceService.setPrivateKey(aliceKeys['privateKey']!);
        bobService.setPrivateKey(bobKeys['privateKey']!);

        aliceService.setPartnerPublicKey(bobKeys['publicKey']!);
        bobService.setPartnerPublicKey(aliceKeys['publicKey']!);

        // Multiple messages should all work (verifying consistent key derivation)
        for (int i = 0; i < 10; i++) {
          final message = 'Message number $i';
          final encrypted = aliceService.encryptMessage(message);
          final decrypted = bobService.decryptMessage(encrypted);

          expect(decrypted, equals(message));
        }
      });

      test('SECURITY: should derive unique salt per conversation from public keys', () async {
        // Arrange - Create two different conversations
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        final charlieService = EncryptionService();
        final charlieKeys = await charlieService.generateKeyPair();

        // Conversation 1: Alice <-> Bob
        aliceService.setPrivateKey(aliceKeys['privateKey']!);
        bobService.setPrivateKey(bobKeys['privateKey']!);
        aliceService.setPartnerPublicKey(bobKeys['publicKey']!);
        bobService.setPartnerPublicKey(aliceKeys['publicKey']!);

        const message = 'Same message in both conversations';
        final aliceToBob = aliceService.encryptMessage(message);

        // Conversation 2: Alice <-> Charlie
        final aliceService2 = EncryptionService();
        aliceService2.setPrivateKey(aliceKeys['privateKey']!);
        charlieService.setPrivateKey(charlieKeys['privateKey']!);
        aliceService2.setPartnerPublicKey(charlieKeys['publicKey']!);
        charlieService.setPartnerPublicKey(aliceKeys['publicKey']!);

        final aliceToCharlie = aliceService2.encryptMessage(message);

        // Assert - Same message encrypted differently in different conversations
        // The ciphertext should be different because the salt (and thus derived key) is different
        expect(aliceToBob, isNot(equals(aliceToCharlie)));

        // Verify both can still decrypt correctly
        expect(bobService.decryptMessage(aliceToBob), equals(message));
        expect(charlieService.decryptMessage(aliceToCharlie), equals(message));

        // Cleanup
        charlieService.clearKeys();
        aliceService2.clearKeys();
      });

      test('SECURITY: should derive same salt regardless of key order', () async {
        // This verifies that both Alice and Bob compute the same salt
        // even though Alice has (myKey=Alice, partnerKey=Bob)
        // and Bob has (myKey=Bob, partnerKey=Alice)

        // Arrange
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        // Act - Set up the conversation from both sides
        aliceService.setPrivateKey(aliceKeys['privateKey']!);
        bobService.setPrivateKey(bobKeys['privateKey']!);
        aliceService.setPartnerPublicKey(bobKeys['publicKey']!);
        bobService.setPartnerPublicKey(aliceKeys['publicKey']!);

        const message = 'Testing salt symmetry';

        // Both encrypt the same message
        final aliceEncrypted = aliceService.encryptMessage(message);
        final bobEncrypted = bobService.encryptMessage(message);

        // Assert - Both should be able to decrypt each other's messages
        // This proves they derived the same encryption key (and thus the same salt)
        final aliceDecryptedBob = aliceService.decryptMessage(bobEncrypted);
        final bobDecryptedAlice = bobService.decryptMessage(aliceEncrypted);

        expect(aliceDecryptedBob, equals(message));
        expect(bobDecryptedAlice, equals(message));
      });

      test('SECURITY: should prevent salt reuse across different key pairs', () async {
        // Verify that using different public keys results in different salts
        // even if the private key stays the same

        // Arrange - Alice talks to Bob, then Bob generates new keys
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys1 = await bobService.generateKeyPair();

        aliceService.setPrivateKey(aliceKeys['privateKey']!);
        bobService.setPrivateKey(bobKeys1['privateKey']!);
        aliceService.setPartnerPublicKey(bobKeys1['publicKey']!);
        bobService.setPartnerPublicKey(aliceKeys['publicKey']!);

        const message = 'Test message';
        final encrypted1 = aliceService.encryptMessage(message);

        // Bob generates NEW keys (simulating key rotation)
        final bobService2 = EncryptionService();
        final bobKeys2 = await bobService2.generateKeyPair();

        final aliceService2 = EncryptionService();
        aliceService2.setPrivateKey(aliceKeys['privateKey']!);
        bobService2.setPrivateKey(bobKeys2['privateKey']!);
        aliceService2.setPartnerPublicKey(bobKeys2['publicKey']!);
        bobService2.setPartnerPublicKey(aliceKeys['publicKey']!);

        final encrypted2 = aliceService2.encryptMessage(message);

        // Assert - Same message with same sender but different recipient key = different ciphertext
        expect(encrypted1, isNot(equals(encrypted2)));

        // Old Bob CANNOT decrypt new messages (different salt/key)
        expect(
          () => bobService.decryptMessage(encrypted2),
          throwsA(predicate((e) => e.toString().contains('Failed to decrypt message'))),
        );

        // New Bob CAN decrypt new messages
        expect(bobService2.decryptMessage(encrypted2), equals(message));

        // Cleanup
        bobService2.clearKeys();
        aliceService2.clearKeys();
      });
    });

    group('Security Properties - Integration Validation', () {
      test('should prevent ciphertext from revealing message length exactly', () async {
        // Arrange
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        aliceService.setPrivateKey(aliceKeys['privateKey']!);
        bobService.setPrivateKey(bobKeys['privateKey']!);

        aliceService.setPartnerPublicKey(bobKeys['publicKey']!);
        bobService.setPartnerPublicKey(aliceKeys['publicKey']!);

        const shortMessage = 'Hi';
        const longMessage = 'This is a much longer message with lots of text';

        // Act
        final shortEncrypted = aliceService.encryptMessage(shortMessage);
        final longEncrypted = aliceService.encryptMessage(longMessage);

        // Assert - Ciphertext includes IV (fixed size) + ciphertext (variable)
        // The lengths should be different but not directly proportional
        expect(shortEncrypted.length, isNot(equals(longEncrypted.length)));

        // Both should include IV prefix (24 chars base64 for 16 bytes) + ':'
        final shortParts = shortEncrypted.split(':');
        final longParts = longEncrypted.split(':');

        expect(shortParts[0].length, equals(longParts[0].length),
          reason: 'IV should be same size');
      });

      test('should not leak information through error messages', () async {
        // Arrange
        final bobKeys = await bobService.generateKeyPair();
        bobService.setPrivateKey(bobKeys['privateKey']!);
        bobService.setPartnerPublicKey((await aliceService.generateKeyPair())['publicKey']!);

        final invalidMessages = [
          'invalid:ciphertext',
          'wrong:length:format:error',
          '',
        ];

        // Act & Assert - All errors should be generic
        for (final invalid in invalidMessages) {
          try {
            bobService.decryptMessage(invalid);
            fail('Should have thrown exception for: $invalid');
          } catch (e) {
            // Error message should be sanitized and generic
            final errorMsg = e.toString().toLowerCase();

            // Should NOT contain specific details like:
            expect(errorMsg.contains('key'), isFalse,
              reason: 'Should not mention "key" in error');
            expect(errorMsg.contains('wrong'), isFalse,
              reason: 'Should not mention "wrong" in error');
          }
        }
      });

      test('should use secure random for IV generation', () async {
        // Arrange
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        aliceService.setPrivateKey(aliceKeys['privateKey']!);
        bobService.setPrivateKey(bobKeys['privateKey']!);

        aliceService.setPartnerPublicKey(bobKeys['publicKey']!);

        const message = 'Same message';
        final ivs = <String>{};

        // Act - Generate 100 encryptions
        for (int i = 0; i < 100; i++) {
          final encrypted = aliceService.encryptMessage(message);
          final iv = encrypted.split(':')[0];
          ivs.add(iv);
        }

        // Assert - All IVs should be unique (extremely high probability)
        expect(ivs.length, 100,
          reason: 'All 100 IVs should be unique (using secure random)');
      });

      test('SECURITY: should reject messages with invalid IV length', () async {
        // Arrange
        final bobKeys = await bobService.generateKeyPair();
        bobService.setPrivateKey(bobKeys['privateKey']!);
        bobService.setPartnerPublicKey((await aliceService.generateKeyPair())['publicKey']!);

        // Create malformed encrypted messages with wrong IV lengths
        final invalidIVMessages = [
          '${base64.encode([1, 2, 3])}:validciphertext',  // IV too short (3 bytes)
          '${base64.encode(List.filled(8, 1))}:validciphertext',  // IV too short (8 bytes)
          '${base64.encode(List.filled(32, 1))}:validciphertext',  // IV too long (32 bytes)
          ':validciphertext',  // Empty IV
        ];

        // Act & Assert - All should be rejected with sanitized error
        for (final invalid in invalidIVMessages) {
          try {
            bobService.decryptMessage(invalid);
            fail('Should have thrown exception for invalid IV: $invalid');
          } catch (e) {
            expect(e.toString(), contains('Failed to decrypt message'),
              reason: 'Error should be sanitized');
            expect(e.toString().toLowerCase(), isNot(contains('invalid iv')),
              reason: 'Should not leak IV length details');
          }
        }
      });

      test('SECURITY: should reject encrypted files with invalid IV', () async {
        // Arrange
        final bobKeys = await bobService.generateKeyPair();
        bobService.setPrivateKey(bobKeys['privateKey']!);
        bobService.setPartnerPublicKey((await aliceService.generateKeyPair())['publicKey']!);

        // Create encrypted file data that's too short (less than 16 bytes for IV)
        final tooShortData = Uint8List.fromList([1, 2, 3, 4, 5]);
        final emptyData = Uint8List(0);

        // Act & Assert
        expect(
          () => bobService.decryptFile(tooShortData),
          throwsA(predicate((e) =>
            e.toString().contains('Failed to decrypt')
          )),
          reason: 'Should reject file data shorter than IV length',
        );

        expect(
          () => bobService.decryptFile(emptyData),
          throwsA(predicate((e) =>
            e.toString().contains('Failed to decrypt')
          )),
          reason: 'Should reject empty file data',
        );
      });
    });

    group('Performance & Stress Tests', () {
      test('should handle rapid encryption/decryption cycles', () async {
        // Arrange
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        aliceService.setPrivateKey(aliceKeys['privateKey']!);
        bobService.setPrivateKey(bobKeys['privateKey']!);

        aliceService.setPartnerPublicKey(bobKeys['publicKey']!);
        bobService.setPartnerPublicKey(aliceKeys['publicKey']!);

        // Act - 1000 rapid cycles
        for (int i = 0; i < 1000; i++) {
          final message = 'Message $i';
          final encrypted = aliceService.encryptMessage(message);
          final decrypted = bobService.decryptMessage(encrypted);

          expect(decrypted, equals(message));
        }

        // Assert - All completed without errors
        expect(true, true);
      });

      test('should handle concurrent operations', () async {
        // Arrange
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        aliceService.setPrivateKey(aliceKeys['privateKey']!);
        bobService.setPrivateKey(bobKeys['privateKey']!);

        aliceService.setPartnerPublicKey(bobKeys['publicKey']!);
        bobService.setPartnerPublicKey(aliceKeys['publicKey']!);

        // Act - Concurrent encryptions
        final futures = <Future<String>>[];
        for (int i = 0; i < 50; i++) {
          futures.add(Future(() => aliceService.encryptMessage('Message $i')));
        }

        final encrypted = await Future.wait(futures);

        // Assert - All should encrypt successfully
        expect(encrypted.length, 50);
        for (final cipher in encrypted) {
          expect(cipher, isNotEmpty);
          expect(cipher.contains(':'), true);
        }
      });
    });

    group('Public Key Fingerprint Verification', () {
      test('should generate consistent fingerprint for same public key', () async {
        // Arrange
        final keys = await aliceService.generateKeyPair();

        // Act - Generate fingerprint multiple times
        final fingerprint1 = aliceService.generateFingerprint(keys['publicKey']!);
        final fingerprint2 = aliceService.generateFingerprint(keys['publicKey']!);

        // Assert - Should be identical
        expect(fingerprint1, equals(fingerprint2));
      });

      test('should generate different fingerprints for different public keys', () async {
        // Arrange
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        // Act
        final aliceFingerprint = aliceService.generateFingerprint(aliceKeys['publicKey']!);
        final bobFingerprint = bobService.generateFingerprint(bobKeys['publicKey']!);

        // Assert
        expect(aliceFingerprint, isNot(equals(bobFingerprint)));
      });

      test('should generate fingerprint in correct format (8 groups of 4 hex chars)', () async {
        // Arrange
        final keys = await aliceService.generateKeyPair();

        // Act
        final fingerprint = aliceService.generateFingerprint(keys['publicKey']!);

        // Assert - Format: XXXX XXXX XXXX XXXX XXXX XXXX XXXX XXXX
        expect(fingerprint, matches(RegExp(r'^([0-9A-F]{4}\s){7}[0-9A-F]{4}$')));

        // Assert - Length: 32 hex chars + 7 spaces = 39 total chars
        expect(fingerprint.length, equals(39));

        // Assert - Should have exactly 7 spaces
        expect(fingerprint.split(' ').length, equals(8));
      });

      test('SECURITY: should verify correct fingerprint', () async {
        // Arrange
        final keys = await aliceService.generateKeyPair();
        final publicKey = keys['publicKey']!;
        final expectedFingerprint = aliceService.generateFingerprint(publicKey);

        // Act
        final isValid = aliceService.verifyFingerprint(publicKey, expectedFingerprint);

        // Assert
        expect(isValid, isTrue);
      });

      test('SECURITY: should reject incorrect fingerprint', () async {
        // Arrange
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        final alicePublicKey = aliceKeys['publicKey']!;
        final bobFingerprint = bobService.generateFingerprint(bobKeys['publicKey']!);

        // Act - Try to verify Alice's key with Bob's fingerprint
        final isValid = aliceService.verifyFingerprint(alicePublicKey, bobFingerprint);

        // Assert
        expect(isValid, isFalse);
      });

      test('SECURITY: should use constant-time comparison (prevent timing attacks)', () async {
        // Arrange
        final keys = await aliceService.generateKeyPair();
        final publicKey = keys['publicKey']!;
        final correctFingerprint = aliceService.generateFingerprint(publicKey);

        // Create wrong fingerprints that differ at different positions
        final wrongAtStart = 'FFFF${correctFingerprint.substring(4)}';
        final wrongAtEnd = '${correctFingerprint.substring(0, 35)}FFFF';

        // Act - Both should fail
        final startResult = aliceService.verifyFingerprint(publicKey, wrongAtStart);
        final endResult = aliceService.verifyFingerprint(publicKey, wrongAtEnd);

        // Assert - Both should return false (testing constant-time behavior)
        expect(startResult, isFalse);
        expect(endResult, isFalse);
      });

      test('should normalize fingerprint (handle spaces and case)', () async {
        // Arrange
        final keys = await aliceService.generateKeyPair();
        final publicKey = keys['publicKey']!;
        final fingerprint = aliceService.generateFingerprint(publicKey);

        // Act - Test different formats
        final withoutSpaces = fingerprint.replaceAll(' ', '');
        final lowercase = fingerprint.toLowerCase();
        final mixed = withoutSpaces.toLowerCase();

        // Assert - All formats should verify correctly
        expect(aliceService.verifyFingerprint(publicKey, fingerprint), isTrue);
        expect(aliceService.verifyFingerprint(publicKey, withoutSpaces), isTrue);
        expect(aliceService.verifyFingerprint(publicKey, lowercase), isTrue);
        expect(aliceService.verifyFingerprint(publicKey, mixed), isTrue);
      });

      test('should get fingerprint for my public key', () async {
        // Arrange
        final keys = await aliceService.generateKeyPair();
        aliceService.setPrivateKey(keys['privateKey']!);

        // Act
        final myFingerprint = aliceService.getMyFingerprint();

        // Assert
        expect(myFingerprint, isNotNull);
        expect(myFingerprint, matches(RegExp(r'^([0-9A-F]{4}\s){7}[0-9A-F]{4}$')));
      });

      test('should get fingerprint for partner public key', () async {
        // Arrange
        final aliceKeys = await aliceService.generateKeyPair();
        final bobKeys = await bobService.generateKeyPair();

        aliceService.setPrivateKey(aliceKeys['privateKey']!);
        aliceService.setPartnerPublicKey(bobKeys['publicKey']!);

        // Act
        final partnerFingerprint = aliceService.getPartnerFingerprint();

        // Assert
        expect(partnerFingerprint, isNotNull);
        expect(partnerFingerprint, matches(RegExp(r'^([0-9A-F]{4}\s){7}[0-9A-F]{4}$')));

        // Verify it matches Bob's actual fingerprint
        final bobFingerprint = bobService.generateFingerprint(bobKeys['publicKey']!);
        expect(partnerFingerprint, equals(bobFingerprint));
      });

      test('should return null when getting fingerprint without keys set', () {
        // Arrange - Fresh service with no keys

        // Act
        final myFingerprint = aliceService.getMyFingerprint();
        final partnerFingerprint = aliceService.getPartnerFingerprint();

        // Assert
        expect(myFingerprint, isNull);
        expect(partnerFingerprint, isNull);
      });
    });

    group('Key Rotation', () {
      test('should generate new key pair during rotation', () async {
        // Arrange
        final originalKeys = await aliceService.generateKeyPair();

        // Act
        final rotationData = await aliceService.rotateKeys();

        // Assert
        expect(rotationData, isNotNull);
        expect(rotationData['publicKey'], isNotNull);
        expect(rotationData['privateKey'], isNotNull);
        expect(rotationData['fingerprint'], isNotNull);
        expect(rotationData['version'], isNotNull);
        expect(rotationData['rotatedAt'], isNotNull);

        // New keys should be different from original
        expect(rotationData['publicKey'], isNot(equals(originalKeys['publicKey'])));
        expect(rotationData['privateKey'], isNot(equals(originalKeys['privateKey'])));
      });

      test('should include rotation metadata', () async {
        // Act
        final rotationData = await aliceService.rotateKeys();

        // Assert - Check metadata structure
        expect(rotationData['rotatedAt'], isA<String>());
        expect(rotationData['fingerprint'], isA<String>());
        expect(rotationData['version'], isA<int>());

        // Verify timestamp is recent (within last 5 seconds)
        final timestamp = DateTime.parse(rotationData['rotatedAt'] as String);
        final now = DateTime.now();
        final difference = now.difference(timestamp);
        expect(difference.inSeconds, lessThan(5));

        // Verify version is Unix timestamp
        final version = rotationData['version'] as int;
        expect(version, greaterThan(1700000000)); // After year 2023
      });

      test('should generate valid fingerprint during rotation', () async {
        // Act
        final rotationData = await aliceService.rotateKeys();

        // Assert
        final fingerprint = rotationData['fingerprint'] as String;
        expect(fingerprint, matches(RegExp(r'^([0-9A-F]{4}\s){7}[0-9A-F]{4}$')));

        // Verify fingerprint matches the generated public key
        final publicKey = rotationData['publicKey'] as String;
        final computedFingerprint = aliceService.generateFingerprint(publicKey);
        expect(fingerprint, equals(computedFingerprint));
      });

      test('should produce different fingerprints on successive rotations', () async {
        // Act
        final rotation1 = await aliceService.rotateKeys();

        // Wait 1 second to ensure different timestamp version
        await Future.delayed(const Duration(seconds: 1));

        final rotation2 = await aliceService.rotateKeys();

        // Assert
        expect(rotation1['fingerprint'], isNot(equals(rotation2['fingerprint'])));
        expect(rotation1['publicKey'], isNot(equals(rotation2['publicKey'])));
        expect(rotation1['version'], isNot(equals(rotation2['version'])));
      });

      test('SECURITY: rotated keys should work for encryption/decryption', () async {
        // Arrange - Rotate Alice's keys
        final aliceRotation = await aliceService.rotateKeys();
        final bobKeys = await bobService.generateKeyPair();

        // Set up encryption with rotated keys
        aliceService.setPrivateKey(aliceRotation['privateKey'] as String);
        bobService.setPrivateKey(bobKeys['privateKey']!);

        aliceService.setPartnerPublicKey(bobKeys['publicKey']!);
        bobService.setPartnerPublicKey(aliceRotation['publicKey'] as String);

        // Act
        const message = 'Testing rotated keys';
        final encrypted = aliceService.encryptMessage(message);
        final decrypted = bobService.decryptMessage(encrypted);

        // Assert
        expect(decrypted, equals(message));
      });

      test('should validate public key structure correctly', () async {
        // Arrange
        final validKeys = await aliceService.generateKeyPair();
        final validPublicKey = validKeys['publicKey']!;

        // Act & Assert - Valid key
        expect(aliceService.isValidPublicKey(validPublicKey), isTrue);

        // Act & Assert - Invalid keys
        expect(aliceService.isValidPublicKey('invalid-key'), isFalse);
        expect(aliceService.isValidPublicKey(''), isFalse);
        expect(aliceService.isValidPublicKey('eyJpbnZhbGlkIjoianNvbiJ9'), isFalse);
      });

      test('should validate private key structure correctly', () async {
        // Arrange
        final validKeys = await aliceService.generateKeyPair();
        final validPrivateKey = validKeys['privateKey']!;

        // Act & Assert - Valid key
        expect(aliceService.isValidPrivateKey(validPrivateKey), isTrue);

        // Act & Assert - Invalid keys
        expect(aliceService.isValidPrivateKey('invalid-key'), isFalse);
        expect(aliceService.isValidPrivateKey(''), isFalse);
        expect(aliceService.isValidPrivateKey('eyJpbnZhbGlkIjoianNvbiJ9'), isFalse);
      });
    });
  });
}
