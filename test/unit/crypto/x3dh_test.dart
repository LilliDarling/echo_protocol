import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_protocol/models/crypto/prekey.dart';
import 'package:echo_protocol/services/crypto/x3dh_service.dart';
import 'package:echo_protocol/utils/security.dart';

void main() {
  late X3DHService x3dh;

  setUp(() {
    x3dh = X3DHService();
  });

  group('Identity Key Generation', () {
    test('generates random identity key pair', () async {
      final keyPair = await x3dh.generateIdentityKeyPair();

      expect(keyPair, isNotNull);
      final publicKey = await keyPair.toPublicKey();
      expect(publicKey.ed25519PublicKey.length, 32);
      expect(publicKey.x25519PublicKey.length, 32);
    });

    test('generates deterministic key from seed', () async {
      final seed = Uint8List.fromList(List.generate(32, (i) => i));

      final keyPair1 = await x3dh.generateIdentityKeyPair(seed: seed);
      final keyPair2 = await x3dh.generateIdentityKeyPair(seed: seed);

      final pub1 = await keyPair1.toPublicKey();
      final pub2 = await keyPair2.toPublicKey();

      expect(
        SecurityUtils.constantTimeBytesEquals(pub1.ed25519PublicKey, pub2.ed25519PublicKey),
        true,
      );
      expect(
        SecurityUtils.constantTimeBytesEquals(pub1.x25519PublicKey, pub2.x25519PublicKey),
        true,
      );
    });

    test('different seeds produce different keys', () async {
      final seed1 = Uint8List.fromList(List.generate(32, (i) => i));
      final seed2 = Uint8List.fromList(List.generate(32, (i) => i + 1));

      final keyPair1 = await x3dh.generateIdentityKeyPair(seed: seed1);
      final keyPair2 = await x3dh.generateIdentityKeyPair(seed: seed2);

      final pub1 = await keyPair1.toPublicKey();
      final pub2 = await keyPair2.toPublicKey();

      expect(
        SecurityUtils.constantTimeBytesEquals(pub1.ed25519PublicKey, pub2.ed25519PublicKey),
        false,
      );
    });
  });

  group('Signed Prekey', () {
    test('generates signed prekey with valid signature', () async {
      final identityKey = await x3dh.generateIdentityKeyPair();
      final signedPrekey = await x3dh.generateSignedPrekey(
        identityKey: identityKey,
        id: 1,
      );

      expect(signedPrekey.id, 1);
      expect(signedPrekey.isExpired, false);

      final publicPrekey = await signedPrekey.toPublic();
      final identityPublic = await identityKey.toPublicKey();

      final isValid = await publicPrekey.verify(identityPublic.ed25519PublicKey);
      expect(isValid, true);
    });

    test('expired prekey is detected', () async {
      final identityKey = await x3dh.generateIdentityKeyPair();
      final signedPrekey = await x3dh.generateSignedPrekey(
        identityKey: identityKey,
        id: 1,
        validity: Duration.zero,
      );

      await Future.delayed(const Duration(milliseconds: 10));
      expect(signedPrekey.isExpired, true);
    });
  });

  group('One-Time Prekeys', () {
    test('generates batch of one-time prekeys', () async {
      final prekeys = await x3dh.generateOneTimePrekeys(startId: 1, count: 10);

      expect(prekeys.length, 10);
      for (int i = 0; i < 10; i++) {
        expect(prekeys[i].id, i + 1);
      }
    });
  });

  group('X3DH Key Agreement', () {
    test('initiator and responder derive same shared secret', () async {
      final aliceIdentity = await x3dh.generateIdentityKeyPair();
      final bobIdentity = await x3dh.generateIdentityKeyPair();

      final bobSignedPrekey = await x3dh.generateSignedPrekey(
        identityKey: bobIdentity,
        id: 1,
      );
      final bobOneTimePrekeys = await x3dh.generateOneTimePrekeys(startId: 1, count: 1);

      final bobIdentityPublic = await bobIdentity.toPublicKey();
      final bobSignedPrekeyPublic = await bobSignedPrekey.toPublic();
      final bobOtpPublic = await bobOneTimePrekeys[0].toPublic();

      final bundle = PreKeyBundle(
        identityKey: bobIdentityPublic,
        signedPrekey: bobSignedPrekeyPublic,
        oneTimePrekey: bobOtpPublic,
        registrationId: 1,
      );

      final aliceResult = await x3dh.initiateSession(
        ourIdentityKey: aliceIdentity,
        theirBundle: bundle,
      );

      expect(aliceResult.rootKey.length, 32);
      expect(aliceResult.chainKey.length, 32);
      expect(aliceResult.ephemeralPublicKey, isNotNull);

      final aliceIdentityPublic = await aliceIdentity.toPublicKey();

      final bobResult = await x3dh.respondToSession(
        ourIdentityKey: bobIdentity,
        theirIdentityPublicKey: aliceIdentityPublic.x25519PublicKey,
        theirEphemeralPublicKey: aliceResult.ephemeralPublicKey!,
        ourSignedPrekey: bobSignedPrekey,
        ourOneTimePrekey: bobOneTimePrekeys[0],
      );

      expect(
        SecurityUtils.constantTimeBytesEquals(aliceResult.rootKey, bobResult.rootKey),
        true,
      );
      expect(
        SecurityUtils.constantTimeBytesEquals(aliceResult.chainKey, bobResult.chainKey),
        true,
      );
    });

    test('works without one-time prekey', () async {
      final aliceIdentity = await x3dh.generateIdentityKeyPair();
      final bobIdentity = await x3dh.generateIdentityKeyPair();

      final bobSignedPrekey = await x3dh.generateSignedPrekey(
        identityKey: bobIdentity,
        id: 1,
      );

      final bobIdentityPublic = await bobIdentity.toPublicKey();
      final bobSignedPrekeyPublic = await bobSignedPrekey.toPublic();

      final bundle = PreKeyBundle(
        identityKey: bobIdentityPublic,
        signedPrekey: bobSignedPrekeyPublic,
        oneTimePrekey: null,
        registrationId: 1,
      );

      final aliceResult = await x3dh.initiateSession(
        ourIdentityKey: aliceIdentity,
        theirBundle: bundle,
      );

      expect(aliceResult.rootKey.length, 32);
      expect(aliceResult.oneTimePrekeyId, isNull);
    });

    test('rejects invalid prekey signature', () async {
      final aliceIdentity = await x3dh.generateIdentityKeyPair();
      final bobIdentity = await x3dh.generateIdentityKeyPair();
      final eveIdentity = await x3dh.generateIdentityKeyPair();

      final eveFakeSignedPrekey = await x3dh.generateSignedPrekey(
        identityKey: eveIdentity,
        id: 1,
      );

      final bobIdentityPublic = await bobIdentity.toPublicKey();
      final eveFakePublic = await eveFakeSignedPrekey.toPublic();

      final bundle = PreKeyBundle(
        identityKey: bobIdentityPublic,
        signedPrekey: eveFakePublic,
        registrationId: 1,
      );

      expect(
        () => x3dh.initiateSession(ourIdentityKey: aliceIdentity, theirBundle: bundle),
        throwsException,
      );
    });
  });
}
