import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_protocol/models/crypto/prekey.dart';
import 'package:echo_protocol/models/crypto/ratchet_session.dart';
import 'package:echo_protocol/services/crypto/x3dh_service.dart';
import 'package:echo_protocol/services/crypto/double_ratchet_service.dart';
import 'package:echo_protocol/utils/security.dart';

void main() {
  late X3DHService x3dh;
  late DoubleRatchetService ratchet;

  setUp(() {
    x3dh = X3DHService();
    ratchet = DoubleRatchetService();
  });

  Future<(RatchetSession, RatchetSession)> createSessionPair() async {
    final aliceIdentity = await x3dh.generateIdentityKeyPair();
    final bobIdentity = await x3dh.generateIdentityKeyPair();

    final bobSignedPrekey = await x3dh.generateSignedPrekey(
      identityKey: bobIdentity,
      id: 1,
    );
    final bobOtpList = await x3dh.generateOneTimePrekeys(startId: 1, count: 1);

    final bobIdentityPublic = await bobIdentity.toPublicKey();
    final bobSignedPrekeyPublic = await bobSignedPrekey.toPublic();
    final bobOtpPublic = await bobOtpList[0].toPublic();

    final bundle = PreKeyBundle(
      identityKey: bobIdentityPublic,
      signedPrekey: bobSignedPrekeyPublic,
      oneTimePrekey: bobOtpPublic,
      registrationId: 1,
    );

    final aliceX3dh = await x3dh.initiateSession(
      ourIdentityKey: aliceIdentity,
      theirBundle: bundle,
    );

    final aliceSession = await ratchet.initializeAsInitiator(
      x3dhResult: aliceX3dh,
      ourUserId: 'alice',
      theirUserId: 'bob',
      theirIdentityKey: bobIdentityPublic,
      theirRatchetPublicKey: bobSignedPrekeyPublic.publicKey,
    );

    final aliceIdentityPublic = await aliceIdentity.toPublicKey();

    final bobX3dh = await x3dh.respondToSession(
      ourIdentityKey: bobIdentity,
      theirIdentityPublicKey: aliceIdentityPublic.x25519PublicKey,
      theirEphemeralPublicKey: aliceX3dh.ephemeralPublicKey!,
      ourSignedPrekey: bobSignedPrekey,
      ourOneTimePrekey: bobOtpList[0],
    );

    final bobSession = await ratchet.initializeAsResponder(
      x3dhResult: bobX3dh,
      ourUserId: 'bob',
      theirUserId: 'alice',
      theirIdentityKey: aliceIdentityPublic,
      ourSignedPrekey: bobSignedPrekey,
    );

    return (aliceSession, bobSession);
  }

  group('Double Ratchet Encryption', () {
    test('encrypts and decrypts single message', () async {
      final (aliceSession, bobSession) = await createSessionPair();

      final plaintext = Uint8List.fromList(utf8.encode('Hello Bob!'));
      final message = await ratchet.encrypt(session: aliceSession, plaintext: plaintext);

      final decrypted = await ratchet.decrypt(session: bobSession, message: message);

      expect(utf8.decode(decrypted), 'Hello Bob!');
    });

    test('handles bidirectional conversation', () async {
      final (aliceSession, bobSession) = await createSessionPair();

      final msg1Plain = Uint8List.fromList(utf8.encode('Hello Bob!'));
      final msg1 = await ratchet.encrypt(session: aliceSession, plaintext: msg1Plain);
      final dec1 = await ratchet.decrypt(session: bobSession, message: msg1);
      expect(utf8.decode(dec1), 'Hello Bob!');

      final msg2Plain = Uint8List.fromList(utf8.encode('Hello Alice!'));
      final msg2 = await ratchet.encrypt(session: bobSession, plaintext: msg2Plain);
      final dec2 = await ratchet.decrypt(session: aliceSession, message: msg2);
      expect(utf8.decode(dec2), 'Hello Alice!');

      final msg3Plain = Uint8List.fromList(utf8.encode('How are you?'));
      final msg3 = await ratchet.encrypt(session: aliceSession, plaintext: msg3Plain);
      final dec3 = await ratchet.decrypt(session: bobSession, message: msg3);
      expect(utf8.decode(dec3), 'How are you?');
    });

    test('each message has unique key', () async {
      final (aliceSession, bobSession) = await createSessionPair();

      final msg1 = await ratchet.encrypt(
        session: aliceSession,
        plaintext: Uint8List.fromList(utf8.encode('Message 1')),
      );
      final msg2 = await ratchet.encrypt(
        session: aliceSession,
        plaintext: Uint8List.fromList(utf8.encode('Message 2')),
      );

      expect(msg1.messageIndex, 0);
      expect(msg2.messageIndex, 1);
      expect(
        SecurityUtils.constantTimeBytesEquals(msg1.ciphertext, msg2.ciphertext),
        false,
      );
    });
  });

  group('Out-of-Order Messages', () {
    test('handles out-of-order delivery', () async {
      final (aliceSession, bobSession) = await createSessionPair();

      final msg1 = await ratchet.encrypt(
        session: aliceSession,
        plaintext: Uint8List.fromList(utf8.encode('Message 1')),
      );
      final msg2 = await ratchet.encrypt(
        session: aliceSession,
        plaintext: Uint8List.fromList(utf8.encode('Message 2')),
      );
      final msg3 = await ratchet.encrypt(
        session: aliceSession,
        plaintext: Uint8List.fromList(utf8.encode('Message 3')),
      );

      final dec3 = await ratchet.decrypt(session: bobSession, message: msg3);
      expect(utf8.decode(dec3), 'Message 3');
      expect(bobSession.skippedKeysCount, 2);

      final dec1 = await ratchet.decrypt(session: bobSession, message: msg1);
      expect(utf8.decode(dec1), 'Message 1');
      expect(bobSession.skippedKeysCount, 1);

      final dec2 = await ratchet.decrypt(session: bobSession, message: msg2);
      expect(utf8.decode(dec2), 'Message 2');
      expect(bobSession.skippedKeysCount, 0);
    });
  });

  group('Session Serialization', () {
    test('session survives serialization', () async {
      final (aliceSession, _) = await createSessionPair();

      final msg1 = await ratchet.encrypt(
        session: aliceSession,
        plaintext: Uint8List.fromList(utf8.encode('Test message')),
      );

      final json = aliceSession.toJson();
      final restored = RatchetSession.fromJson(json);

      expect(restored.sessionId, aliceSession.sessionId);
      expect(restored.sendingChain?.messageIndex, aliceSession.sendingChain?.messageIndex);
      expect(
        SecurityUtils.constantTimeBytesEquals(
          restored.rootKey,
          aliceSession.rootKey,
        ),
        true,
      );

      final msg2 = await ratchet.encrypt(
        session: restored,
        plaintext: Uint8List.fromList(utf8.encode('After restore')),
      );

      expect(msg2.messageIndex, msg1.messageIndex + 1);
    });
  });

  group('Security Limits', () {
    test('enforces max skipped keys limit', () async {
      final identityKey = await x3dh.generateIdentityKeyPair();
      final identityPublicKey = await identityKey.toPublicKey();
      final session = RatchetSession(
        sessionId: 'test',
        ourUserId: 'alice',
        theirUserId: 'bob',
        theirIdentityKey: identityPublicKey,
        rootKey: Uint8List(32),
        createdAt: DateTime.now(),
        lastActivityAt: DateTime.now(),
        isInitiator: true,
      );

      expect(session.canSkipMessages(1000), true);
      expect(session.canSkipMessages(1001), false);
    });

    test('cleans up expired skipped keys', () async {
      final (aliceSession, bobSession) = await createSessionPair();

      await ratchet.encrypt(
        session: aliceSession,
        plaintext: Uint8List.fromList(utf8.encode('Message 1')),
      );
      final msg2 = await ratchet.encrypt(
        session: aliceSession,
        plaintext: Uint8List.fromList(utf8.encode('Message 2')),
      );
      await ratchet.encrypt(
        session: aliceSession,
        plaintext: Uint8List.fromList(utf8.encode('Message 3')),
      );

      await ratchet.decrypt(session: bobSession, message: msg2);

      expect(bobSession.skippedKeysCount, 1);

      ratchet.cleanupExpiredSkippedKeys(bobSession);

      expect(bobSession.skippedKeysCount, 1);
    });
  });
}
