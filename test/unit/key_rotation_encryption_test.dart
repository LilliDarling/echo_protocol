import 'package:flutter_test/flutter_test.dart';
import 'package:echo_protocol/services/encryption.dart';

/// Unit test for key rotation encryption compatibility
/// Tests that the encryption service can decrypt messages with different key versions
void main() {
  group('Key Rotation Encryption Compatibility', () {
    late EncryptionService aliceService;
    late EncryptionService bobService;

    setUp(() {
      aliceService = EncryptionService();
      bobService = EncryptionService();
    });

    test('decryptMessageWithKeyVersions works with historical keys', () async {
      // Alice and Bob generate initial keys
      final aliceKeys1 = await aliceService.generateKeyPair();
      final bobKeys = await bobService.generateKeyPair();

      // Set up encryption with initial keys
      aliceService.setPrivateKey(aliceKeys1['privateKey']!, keyVersion: 1);
      aliceService.setPartnerPublicKey(bobKeys['publicKey']!);

      // Alice encrypts a message
      const originalMessage = 'Secret message before rotation';
      final encryptedMessage = aliceService.encryptMessage(originalMessage);

      // Bob can decrypt with the same key version
      bobService.setPrivateKey(bobKeys['privateKey']!, keyVersion: 1);
      bobService.setPartnerPublicKey(aliceKeys1['publicKey']!);
      final decrypted1 = bobService.decryptMessage(encryptedMessage);
      expect(decrypted1, equals(originalMessage));

      // Alice rotates her keys
      final aliceKeys2 = await aliceService.generateKeyPair();
      aliceService.setPrivateKey(aliceKeys2['privateKey']!, keyVersion: 2);

      // Bob can still decrypt the old message using the archived public key
      final decrypted2 = bobService.decryptMessageWithKeyVersions(
        encryptedText: encryptedMessage,
        myPrivateKeyPem: bobKeys['privateKey']!,
        partnerPublicKeyPem: aliceKeys1['publicKey']!, // Old public key
      );

      expect(decrypted2, equals(originalMessage));
    });

    test('decryptMessageWithKeyVersions maintains encryption security', () async {
      final aliceKeys = await aliceService.generateKeyPair();
      final bobKeys = await bobService.generateKeyPair();
      final charlieKeys = await EncryptionService().generateKeyPair();

      aliceService.setPrivateKey(aliceKeys['privateKey']!, keyVersion: 1);
      aliceService.setPartnerPublicKey(bobKeys['publicKey']!);

      const message = 'Private message';
      final encrypted = aliceService.encryptMessage(message);

      // Bob can decrypt
      final decryptedByBob = bobService.decryptMessageWithKeyVersions(
        encryptedText: encrypted,
        myPrivateKeyPem: bobKeys['privateKey']!,
        partnerPublicKeyPem: aliceKeys['publicKey']!,
      );
      expect(decryptedByBob, equals(message));

      // Charlie cannot decrypt (wrong keys)
      expect(
        () => bobService.decryptMessageWithKeyVersions(
          encryptedText: encrypted,
          myPrivateKeyPem: charlieKeys['privateKey']!,
          partnerPublicKeyPem: aliceKeys['publicKey']!,
        ),
        throwsException,
      );
    });

    test('Multiple key rotations preserve all message history', () async {
      final bobKeys = await bobService.generateKeyPair();
      final messages = <String, String>{};

      // Version 1
      final aliceKeys1 = await aliceService.generateKeyPair();
      aliceService.setPrivateKey(aliceKeys1['privateKey']!, keyVersion: 1);
      aliceService.setPartnerPublicKey(bobKeys['publicKey']!);

      const msg1 = 'Message 1';
      messages[aliceKeys1['publicKey']!] = aliceService.encryptMessage(msg1);

      // Version 2
      final aliceKeys2 = await aliceService.generateKeyPair();
      aliceService.setPrivateKey(aliceKeys2['privateKey']!, keyVersion: 2);
      aliceService.setPartnerPublicKey(bobKeys['publicKey']!);

      const msg2 = 'Message 2';
      messages[aliceKeys2['publicKey']!] = aliceService.encryptMessage(msg2);

      // Version 3
      final aliceKeys3 = await aliceService.generateKeyPair();
      aliceService.setPrivateKey(aliceKeys3['privateKey']!, keyVersion: 3);
      aliceService.setPartnerPublicKey(bobKeys['publicKey']!);

      const msg3 = 'Message 3';
      messages[aliceKeys3['publicKey']!] = aliceService.encryptMessage(msg3);

      // Bob can decrypt all messages with respective key versions
      final dec1 = bobService.decryptMessageWithKeyVersions(
        encryptedText: messages[aliceKeys1['publicKey']!]!,
        myPrivateKeyPem: bobKeys['privateKey']!,
        partnerPublicKeyPem: aliceKeys1['publicKey']!,
      );
      expect(dec1, equals(msg1));

      final dec2 = bobService.decryptMessageWithKeyVersions(
        encryptedText: messages[aliceKeys2['publicKey']!]!,
        myPrivateKeyPem: bobKeys['privateKey']!,
        partnerPublicKeyPem: aliceKeys2['publicKey']!,
      );
      expect(dec2, equals(msg2));

      final dec3 = bobService.decryptMessageWithKeyVersions(
        encryptedText: messages[aliceKeys3['publicKey']!]!,
        myPrivateKeyPem: bobKeys['privateKey']!,
        partnerPublicKeyPem: aliceKeys3['publicKey']!,
      );
      expect(dec3, equals(msg3));
    });

    test('Cross-version decryption fails as expected', () async {
      final bobKeys = await bobService.generateKeyPair();

      final aliceKeys1 = await aliceService.generateKeyPair();
      aliceService.setPrivateKey(aliceKeys1['privateKey']!, keyVersion: 1);
      aliceService.setPartnerPublicKey(bobKeys['publicKey']!);
      final encrypted1 = aliceService.encryptMessage('Message 1');

      final aliceKeys2 = await aliceService.generateKeyPair();

      // Trying to decrypt message encrypted with v1 using v2 public key should fail
      expect(
        () => bobService.decryptMessageWithKeyVersions(
          encryptedText: encrypted1,
          myPrivateKeyPem: bobKeys['privateKey']!,
          partnerPublicKeyPem: aliceKeys2['publicKey']!, // Wrong version!
        ),
        throwsException,
      );
    });

    test('currentKeyVersion property tracks version correctly', () async {
      final keys = await aliceService.generateKeyPair();

      // Set with version 1
      aliceService.setPrivateKey(keys['privateKey']!, keyVersion: 1);
      expect(aliceService.currentKeyVersion, equals(1));

      // Set with version 2
      aliceService.setPrivateKey(keys['privateKey']!, keyVersion: 2);
      expect(aliceService.currentKeyVersion, equals(2));

      // Set without version
      aliceService.setPrivateKey(keys['privateKey']!);
      expect(aliceService.currentKeyVersion, isNull);
    });
  });
}
