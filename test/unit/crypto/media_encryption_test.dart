import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto_pkg;
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

  Future<RatchetSession> createAliceSession() async {
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

    return ratchet.initializeAsInitiator(
      x3dhResult: aliceX3dh,
      ourUserId: 'alice',
      theirUserId: 'bob',
      theirIdentityKey: bobIdentityPublic,
      theirRatchetPublicKey: bobSignedPrekeyPublic.publicKey,
    );
  }

  group('Media Chain Initialization', () {
    test('session starts without media chain', () async {
      final session = await createAliceSession();
      expect(session.mediaChainKey, isNull);
      expect(session.mediaKeyIndex, 0);
      expect(session.mediaKeys, isEmpty);
    });
  });

  group('Media Key Storage', () {
    test('stores and retrieves media keys', () async {
      final session = await createAliceSession();
      final testKey = Uint8List.fromList(List.generate(32, (i) => i));
      final mediaId = 'test-media-123';

      session.mediaKeys[mediaId] = testKey;
      expect(session.mediaKeys[mediaId], equals(testKey));
    });

    test('deletes media key securely', () async {
      final session = await createAliceSession();
      final testKey = Uint8List.fromList(List.generate(32, (i) => i));
      final mediaId = 'test-media-456';

      session.mediaKeys[mediaId] = testKey;
      session.deleteMediaKey(mediaId);

      expect(session.mediaKeys[mediaId], isNull);
    });
  });

  group('Session Serialization with Media', () {
    test('media fields survive serialization', () async {
      final session = await createAliceSession();
      session.mediaChainKey = Uint8List.fromList(List.generate(32, (i) => i));
      session.mediaKeyIndex = 5;
      session.mediaKeys['media-1'] = Uint8List.fromList(List.generate(32, (i) => i + 10));
      session.mediaKeys['media-2'] = Uint8List.fromList(List.generate(32, (i) => i + 20));

      final json = session.toJson();
      final restored = RatchetSession.fromJson(json);

      expect(restored.mediaChainKey, isNotNull);
      expect(restored.mediaKeyIndex, 5);
      expect(restored.mediaKeys.length, 2);
      expect(restored.mediaKeys['media-1'], isNotNull);
      expect(restored.mediaKeys['media-2'], isNotNull);
    });

    test('null media chain serializes correctly', () async {
      final session = await createAliceSession();
      expect(session.mediaChainKey, isNull);

      final json = session.toJson();
      final restored = RatchetSession.fromJson(json);

      expect(restored.mediaChainKey, isNull);
      expect(restored.mediaKeyIndex, 0);
      expect(restored.mediaKeys, isEmpty);
    });
  });

  group('Media Encryption Logic', () {
    Uint8List initializeMediaChain(RatchetSession session) {
      if (session.mediaChainKey != null) return session.mediaChainKey!;
      session.mediaChainKey = SecurityUtils.hkdfSha256(
        session.rootKey,
        Uint8List.fromList(utf8.encode('media-init')),
        Uint8List.fromList(utf8.encode('EchoProtocol-MediaChain-v1')),
        32,
      );
      session.mediaKeyIndex = 0;
      return session.mediaChainKey!;
    }

    Uint8List deriveMediaKey(RatchetSession session) {
      return SecurityUtils.hkdfSha256(
        session.mediaChainKey!,
        Uint8List.fromList([session.mediaKeyIndex & 0xFF]),
        Uint8List.fromList(utf8.encode('EchoProtocol-MediaKey-v1')),
        32,
      );
    }

    void advanceMediaChain(RatchetSession session) {
      final newChainKey = SecurityUtils.hkdfSha256(
        session.mediaChainKey!,
        Uint8List.fromList([0xFF]),
        Uint8List.fromList(utf8.encode('EchoProtocol-MediaChain-v1-advance')),
        32,
      );
      session.mediaChainKey = newChainKey;
      session.mediaKeyIndex++;
    }

    String generateMediaId(int index) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final data = '$timestamp:$index';
      final hash = crypto_pkg.sha256.convert(utf8.encode(data));
      return hash.toString().substring(0, 16);
    }

    Future<Uint8List> encryptMedia(Uint8List key, Uint8List plaintext, String mediaId) async {
      final aesGcm = AesGcm.with256bits();
      final secretKey = SecretKey(key);
      final nonce = SecurityUtils.generateSecureRandomBytes(12);
      final aad = utf8.encode('EchoMedia:$mediaId');

      final secretBox = await aesGcm.encrypt(
        plaintext,
        secretKey: secretKey,
        nonce: nonce,
        aad: aad,
      );

      return Uint8List.fromList([
        ...nonce,
        ...secretBox.cipherText,
        ...secretBox.mac.bytes,
      ]);
    }

    Future<Uint8List> decryptMedia(Uint8List key, Uint8List ciphertext, String mediaId) async {
      final aesGcm = AesGcm.with256bits();
      final nonce = ciphertext.sublist(0, 12);
      final ct = ciphertext.sublist(12, ciphertext.length - 16);
      final tag = ciphertext.sublist(ciphertext.length - 16);
      final aad = utf8.encode('EchoMedia:$mediaId');

      final secretKey = SecretKey(key);
      final secretBox = SecretBox(ct, nonce: nonce, mac: Mac(tag));

      return Uint8List.fromList(
        await aesGcm.decrypt(secretBox, secretKey: secretKey, aad: aad),
      );
    }

    test('encrypts and decrypts media content', () async {
      final session = await createAliceSession();
      initializeMediaChain(session);

      final mediaId = generateMediaId(session.mediaKeyIndex);
      final mediaKey = deriveMediaKey(session);
      session.mediaKeys[mediaId] = Uint8List.fromList(mediaKey);
      advanceMediaChain(session);

      final testData = Uint8List.fromList(utf8.encode('Test media content'));
      final encrypted = await encryptMedia(mediaKey, testData, mediaId);

      expect(encrypted, isNotEmpty);
      expect(encrypted.length, greaterThan(testData.length));

      final storedKey = session.mediaKeys[mediaId]!;
      final decrypted = await decryptMedia(storedKey, encrypted, mediaId);

      expect(utf8.decode(decrypted), 'Test media content');
    });

    test('each media file gets unique key', () async {
      final session = await createAliceSession();
      initializeMediaChain(session);

      final mediaId1 = generateMediaId(session.mediaKeyIndex);
      final mediaKey1 = deriveMediaKey(session);
      session.mediaKeys[mediaId1] = Uint8List.fromList(mediaKey1);
      advanceMediaChain(session);

      final mediaId2 = generateMediaId(session.mediaKeyIndex);
      final mediaKey2 = deriveMediaKey(session);
      session.mediaKeys[mediaId2] = Uint8List.fromList(mediaKey2);
      advanceMediaChain(session);

      expect(mediaId1, isNot(equals(mediaId2)));
      expect(
        SecurityUtils.constantTimeBytesEquals(
          session.mediaKeys[mediaId1]!,
          session.mediaKeys[mediaId2]!,
        ),
        false,
      );
    });

    test('media chain advances correctly', () async {
      final session = await createAliceSession();
      initializeMediaChain(session);

      expect(session.mediaKeyIndex, 0);

      advanceMediaChain(session);
      expect(session.mediaKeyIndex, 1);

      advanceMediaChain(session);
      expect(session.mediaKeyIndex, 2);
    });

    test('forward secure deletion removes key', () async {
      final session = await createAliceSession();
      initializeMediaChain(session);

      final mediaId = generateMediaId(session.mediaKeyIndex);
      final mediaKey = deriveMediaKey(session);
      session.mediaKeys[mediaId] = Uint8List.fromList(mediaKey);
      advanceMediaChain(session);

      expect(session.mediaKeys.containsKey(mediaId), true);

      session.deleteMediaKey(mediaId);
      expect(session.mediaKeys.containsKey(mediaId), false);
    });

    test('decryption fails with wrong key', () async {
      final session = await createAliceSession();
      initializeMediaChain(session);

      final mediaId = generateMediaId(session.mediaKeyIndex);
      final mediaKey = deriveMediaKey(session);

      final testData = Uint8List.fromList(utf8.encode('Secret media'));
      final encrypted = await encryptMedia(mediaKey, testData, mediaId);

      final wrongKey = Uint8List.fromList(List.generate(32, (i) => i));
      expect(
        () => decryptMedia(wrongKey, encrypted, mediaId),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('media key derived from chain key', () async {
      final session = await createAliceSession();
      initializeMediaChain(session);

      final chainKeyBefore = Uint8List.fromList(session.mediaChainKey!);
      final mediaKey = deriveMediaKey(session);

      expect(
        SecurityUtils.constantTimeBytesEquals(chainKeyBefore, session.mediaChainKey!),
        true,
      );
      expect(
        SecurityUtils.constantTimeBytesEquals(mediaKey, session.mediaChainKey!),
        false,
      );
    });

    test('chain key changes after advance', () async {
      final session = await createAliceSession();
      initializeMediaChain(session);

      final chainKeyBefore = Uint8List.fromList(session.mediaChainKey!);
      advanceMediaChain(session);

      expect(
        SecurityUtils.constantTimeBytesEquals(chainKeyBefore, session.mediaChainKey!),
        false,
      );
    });
  });
}
