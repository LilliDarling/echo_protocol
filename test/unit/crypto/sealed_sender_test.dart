import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:echo_protocol/models/crypto/sender_certificate.dart';
import 'package:echo_protocol/models/crypto/sealed_envelope.dart';
import 'package:echo_protocol/utils/security.dart';

void main() {
  group('SenderCertificate', () {
    late SimpleKeyPair aliceSigningKey;
    late Uint8List alicePublicKey;

    setUp(() async {
      final ed25519 = Ed25519();
      aliceSigningKey = await ed25519.newKeyPair();
      final publicKey = await aliceSigningKey.extractPublicKey();
      alicePublicKey = Uint8List.fromList(publicKey.bytes);
    });

    test('creates valid certificate with signature', () async {
      final cert = await SenderCertificate.create(
        senderId: 'alice123',
        senderPublicKey: alicePublicKey,
        signingKeyPair: aliceSigningKey,
      );

      expect(cert.senderId, 'alice123');
      expect(cert.senderPublicKey, alicePublicKey);
      expect(cert.signature.length, 64);
      expect(cert.timestamp, isPositive);
    });

    test('verifies valid certificate', () async {
      final cert = await SenderCertificate.create(
        senderId: 'alice123',
        senderPublicKey: alicePublicKey,
        signingKeyPair: aliceSigningKey,
      );

      final isValid = await cert.verify();
      expect(isValid, true);
    });

    test('rejects certificate with wrong public key', () async {
      final cert = await SenderCertificate.create(
        senderId: 'alice123',
        senderPublicKey: alicePublicKey,
        signingKeyPair: aliceSigningKey,
      );

      final ed25519 = Ed25519();
      final eveKeyPair = await ed25519.newKeyPair();
      final evePublicKey = await eveKeyPair.extractPublicKey();

      final tamperedCert = SenderCertificate(
        senderId: cert.senderId,
        senderPublicKey: Uint8List.fromList(evePublicKey.bytes),
        timestamp: cert.timestamp,
        signature: cert.signature,
      );

      final isValid = await tamperedCert.verify();
      expect(isValid, false);
    });

    test('rejects certificate with tampered senderId', () async {
      final cert = await SenderCertificate.create(
        senderId: 'alice123',
        senderPublicKey: alicePublicKey,
        signingKeyPair: aliceSigningKey,
      );

      final tamperedCert = SenderCertificate(
        senderId: 'eve666',
        senderPublicKey: cert.senderPublicKey,
        timestamp: cert.timestamp,
        signature: cert.signature,
      );

      final isValid = await tamperedCert.verify();
      expect(isValid, false);
    });

    test('rejects certificate with tampered timestamp', () async {
      final cert = await SenderCertificate.create(
        senderId: 'alice123',
        senderPublicKey: alicePublicKey,
        signingKeyPair: aliceSigningKey,
      );

      final tamperedCert = SenderCertificate(
        senderId: cert.senderId,
        senderPublicKey: cert.senderPublicKey,
        timestamp: cert.timestamp + 1000,
        signature: cert.signature,
      );

      final isValid = await tamperedCert.verify();
      expect(isValid, false);
    });

    test('rejects certificate with corrupted signature', () async {
      final cert = await SenderCertificate.create(
        senderId: 'alice123',
        senderPublicKey: alicePublicKey,
        signingKeyPair: aliceSigningKey,
      );

      final corruptedSig = Uint8List.fromList(cert.signature);
      corruptedSig[0] ^= 0xFF;

      final tamperedCert = SenderCertificate(
        senderId: cert.senderId,
        senderPublicKey: cert.senderPublicKey,
        timestamp: cert.timestamp,
        signature: corruptedSig,
      );

      final isValid = await tamperedCert.verify();
      expect(isValid, false);
    });

    test('serializes and deserializes correctly', () async {
      final cert = await SenderCertificate.create(
        senderId: 'alice123',
        senderPublicKey: alicePublicKey,
        signingKeyPair: aliceSigningKey,
      );

      final bytes = cert.toBytes();
      final restored = SenderCertificate.fromBytes(bytes);

      expect(restored.senderId, cert.senderId);
      expect(restored.timestamp, cert.timestamp);
      expect(
        SecurityUtils.constantTimeBytesEquals(restored.senderPublicKey, cert.senderPublicKey),
        true,
      );
      expect(
        SecurityUtils.constantTimeBytesEquals(restored.signature, cert.signature),
        true,
      );

      final isValid = await restored.verify();
      expect(isValid, true);
    });
  });

  group('SealedEnvelope', () {
    late SimpleKeyPair aliceSigningKey;
    late Uint8List aliceEd25519PublicKey;
    late SimpleKeyPair bobX25519KeyPair;
    late Uint8List bobX25519PublicKey;

    setUp(() async {
      final ed25519 = Ed25519();
      final x25519 = X25519();

      aliceSigningKey = await ed25519.newKeyPair();
      final alicePub = await aliceSigningKey.extractPublicKey();
      aliceEd25519PublicKey = Uint8List.fromList(alicePub.bytes);

      bobX25519KeyPair = await x25519.newKeyPair();
      final bobPub = await bobX25519KeyPair.extractPublicKey();
      bobX25519PublicKey = Uint8List.fromList(bobPub.bytes);
    });

    test('seals and unseals message correctly', () async {
      final message = Uint8List.fromList(utf8.encode('Hello, Bob!'));

      final envelope = await SealedEnvelope.seal(
        senderId: 'alice123',
        recipientId: 'bob456',
        recipientPublicKey: bobX25519PublicKey,
        encryptedMessage: message,
        senderSigningKey: aliceSigningKey,
        senderPublicKey: aliceEd25519PublicKey,
      );

      expect(envelope.recipientId, 'bob456');
      expect(envelope.encryptedPayload.isNotEmpty, true);
      expect(envelope.ephemeralPublicKey.length, 32);
      expect(envelope.isExpired, false);

      final unsealed = await envelope.unseal(recipientKeyPair: bobX25519KeyPair);

      expect(unsealed.senderId, 'alice123');
      expect(
        SecurityUtils.constantTimeBytesEquals(unsealed.encryptedMessage, message),
        true,
      );
    });

    test('unsealing fails with wrong recipient key', () async {
      final message = Uint8List.fromList(utf8.encode('Secret message'));

      final envelope = await SealedEnvelope.seal(
        senderId: 'alice123',
        recipientId: 'bob456',
        recipientPublicKey: bobX25519PublicKey,
        encryptedMessage: message,
        senderSigningKey: aliceSigningKey,
        senderPublicKey: aliceEd25519PublicKey,
      );

      final x25519 = X25519();
      final eveKeyPair = await x25519.newKeyPair();

      expect(
        () => envelope.unseal(recipientKeyPair: eveKeyPair),
        throwsA(anything),
      );
    });

    test('detects tampered payload', () async {
      final message = Uint8List.fromList(utf8.encode('Original message'));

      final envelope = await SealedEnvelope.seal(
        senderId: 'alice123',
        recipientId: 'bob456',
        recipientPublicKey: bobX25519PublicKey,
        encryptedMessage: message,
        senderSigningKey: aliceSigningKey,
        senderPublicKey: aliceEd25519PublicKey,
      );

      final tamperedPayload = Uint8List.fromList(envelope.encryptedPayload);
      tamperedPayload[20] ^= 0xFF;

      final tamperedEnvelope = SealedEnvelope(
        recipientId: envelope.recipientId,
        encryptedPayload: tamperedPayload,
        ephemeralPublicKey: envelope.ephemeralPublicKey,
        timestamp: envelope.timestamp,
        expireAt: envelope.expireAt,
      );

      expect(
        () => tamperedEnvelope.unseal(recipientKeyPair: bobX25519KeyPair),
        throwsA(anything),
      );
    });

    test('detects tampered ephemeral key', () async {
      final message = Uint8List.fromList(utf8.encode('Secret'));

      final envelope = await SealedEnvelope.seal(
        senderId: 'alice123',
        recipientId: 'bob456',
        recipientPublicKey: bobX25519PublicKey,
        encryptedMessage: message,
        senderSigningKey: aliceSigningKey,
        senderPublicKey: aliceEd25519PublicKey,
      );

      final tamperedEphemeral = Uint8List.fromList(envelope.ephemeralPublicKey);
      tamperedEphemeral[0] ^= 0xFF;

      final tamperedEnvelope = SealedEnvelope(
        recipientId: envelope.recipientId,
        encryptedPayload: envelope.encryptedPayload,
        ephemeralPublicKey: tamperedEphemeral,
        timestamp: envelope.timestamp,
        expireAt: envelope.expireAt,
      );

      expect(
        () => tamperedEnvelope.unseal(recipientKeyPair: bobX25519KeyPair),
        throwsA(anything),
      );
    });

    test('each seal produces different ciphertext (randomized)', () async {
      final message = Uint8List.fromList(utf8.encode('Same message'));

      final envelope1 = await SealedEnvelope.seal(
        senderId: 'alice123',
        recipientId: 'bob456',
        recipientPublicKey: bobX25519PublicKey,
        encryptedMessage: message,
        senderSigningKey: aliceSigningKey,
        senderPublicKey: aliceEd25519PublicKey,
      );

      final envelope2 = await SealedEnvelope.seal(
        senderId: 'alice123',
        recipientId: 'bob456',
        recipientPublicKey: bobX25519PublicKey,
        encryptedMessage: message,
        senderSigningKey: aliceSigningKey,
        senderPublicKey: aliceEd25519PublicKey,
      );

      expect(
        SecurityUtils.constantTimeBytesEquals(
          envelope1.encryptedPayload,
          envelope2.encryptedPayload,
        ),
        false,
      );

      expect(
        SecurityUtils.constantTimeBytesEquals(
          envelope1.ephemeralPublicKey,
          envelope2.ephemeralPublicKey,
        ),
        false,
      );
    });

    test('serializes and deserializes via JSON', () async {
      final message = Uint8List.fromList(utf8.encode('Test message'));

      final envelope = await SealedEnvelope.seal(
        senderId: 'alice123',
        recipientId: 'bob456',
        recipientPublicKey: bobX25519PublicKey,
        encryptedMessage: message,
        senderSigningKey: aliceSigningKey,
        senderPublicKey: aliceEd25519PublicKey,
      );

      final json = envelope.toJson();
      final restored = SealedEnvelope.fromJson(json);

      expect(restored.recipientId, envelope.recipientId);
      expect(restored.timestamp, envelope.timestamp);
      expect(restored.expireAt, envelope.expireAt);

      final unsealed = await restored.unseal(recipientKeyPair: bobX25519KeyPair);
      expect(unsealed.senderId, 'alice123');
    });

    test('expiration is detected', () async {
      final message = Uint8List.fromList(utf8.encode('Test'));

      final envelope = await SealedEnvelope.seal(
        senderId: 'alice123',
        recipientId: 'bob456',
        recipientPublicKey: bobX25519PublicKey,
        encryptedMessage: message,
        senderSigningKey: aliceSigningKey,
        senderPublicKey: aliceEd25519PublicKey,
      );

      expect(envelope.isExpired, false);

      final expiredEnvelope = SealedEnvelope(
        recipientId: envelope.recipientId,
        encryptedPayload: envelope.encryptedPayload,
        ephemeralPublicKey: envelope.ephemeralPublicKey,
        timestamp: envelope.timestamp,
        expireAt: DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
      );

      expect(expiredEnvelope.isExpired, true);
    });

    test('sender cannot forge certificate for another identity', () async {
      final ed25519 = Ed25519();
      final eveSigningKey = await ed25519.newKeyPair();
      final evePub = await eveSigningKey.extractPublicKey();
      final evePublicKey = Uint8List.fromList(evePub.bytes);

      final message = Uint8List.fromList(utf8.encode('Forged message'));

      final forgedEnvelope = await SealedEnvelope.seal(
        senderId: 'alice123',
        recipientId: 'bob456',
        recipientPublicKey: bobX25519PublicKey,
        encryptedMessage: message,
        senderSigningKey: eveSigningKey,
        senderPublicKey: evePublicKey,
      );

      final unsealed = await forgedEnvelope.unseal(recipientKeyPair: bobX25519KeyPair);

      expect(unsealed.senderId, 'alice123');
      expect(
        SecurityUtils.constantTimeBytesEquals(unsealed.senderPublicKey, evePublicKey),
        true,
      );
      expect(
        SecurityUtils.constantTimeBytesEquals(unsealed.senderPublicKey, aliceEd25519PublicKey),
        false,
      );
    });
  });

  group('Sealed Sender Security Properties', () {
    test('server cannot determine sender from envelope', () async {
      final ed25519 = Ed25519();
      final x25519 = X25519();

      final aliceSigningKey = await ed25519.newKeyPair();
      final alicePub = await aliceSigningKey.extractPublicKey();

      final bobKeyPair = await x25519.newKeyPair();
      final bobPub = await bobKeyPair.extractPublicKey();

      final envelope = await SealedEnvelope.seal(
        senderId: 'alice_secret_id',
        recipientId: 'bob456',
        recipientPublicKey: Uint8List.fromList(bobPub.bytes),
        encryptedMessage: Uint8List.fromList(utf8.encode('Secret')),
        senderSigningKey: aliceSigningKey,
        senderPublicKey: Uint8List.fromList(alicePub.bytes),
      );

      final json = envelope.toJson();

      expect(json.containsKey('recipientId'), true);
      expect(json['recipientId'], 'bob456');

      final payloadStr = json['payload'] as String;
      expect(payloadStr.contains('alice'), false);

      final ephemeralStr = json['ephemeralKey'] as String;
      final ephemeralBytes = base64Decode(ephemeralStr);
      expect(
        SecurityUtils.constantTimeBytesEquals(
          ephemeralBytes,
          Uint8List.fromList(alicePub.bytes),
        ),
        false,
      );
    });
  });
}
