import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../../models/crypto/identity_key.dart';
import '../../models/crypto/prekey.dart';
import '../../utils/security.dart';

class X3DHResult {
  final Uint8List rootKey;
  final Uint8List chainKey;
  final Uint8List associatedData;
  final Uint8List? ephemeralPublicKey;
  final int signedPrekeyId;
  final int? oneTimePrekeyId;

  X3DHResult({
    required this.rootKey,
    required this.chainKey,
    required this.associatedData,
    this.ephemeralPublicKey,
    required this.signedPrekeyId,
    this.oneTimePrekeyId,
  });

  void dispose() {
    SecurityUtils.secureClear(rootKey);
    SecurityUtils.secureClear(chainKey);
  }
}

class X3DHService {
  static const String _kdfInfo = 'EchoProtocol-X3DH-v1';
  static const int _derivedKeyLength = 64;

  final X25519 _x25519 = X25519();

  Future<IdentityKeyPair> generateIdentityKeyPair({Uint8List? seed}) async {
    if (seed != null) {
      return IdentityKeyPair.fromSeed(seed);
    }
    return IdentityKeyPair.generate();
  }

  Future<SignedPrekey> generateSignedPrekey({
    required IdentityKeyPair identityKey,
    required int id,
    Duration validity = const Duration(days: 30),
  }) async {
    return SignedPrekey.generate(
      id: id,
      identityKey: identityKey,
      validity: validity,
    );
  }

  Future<List<OneTimePrekey>> generateOneTimePrekeys({
    required int startId,
    required int count,
  }) async {
    return OneTimePrekey.generateBatch(startId, count);
  }

  Future<X3DHResult> initiateSession({
    required IdentityKeyPair ourIdentityKey,
    required PreKeyBundle theirBundle,
  }) async {
    final isValid = await theirBundle.validate();
    if (!isValid) {
      throw Exception('Session initialization failed');
    }

    final ephemeralKeyPair = await _x25519.newKeyPair();
    final ephemeralPublic = await ephemeralKeyPair.extractPublicKey();
    final ephemeralPrivate = await ephemeralKeyPair.extractPrivateKeyBytes();

    final ourIdentityPrivate = await ourIdentityKey.x25519KeyPair.extractPrivateKeyBytes();

    final dh1 = await _computeDH(
      Uint8List.fromList(ourIdentityPrivate),
      theirBundle.signedPrekey.publicKey,
    );

    final dh2 = await _computeDH(
      Uint8List.fromList(ephemeralPrivate),
      theirBundle.identityKey.x25519PublicKey,
    );

    final dh3 = await _computeDH(
      Uint8List.fromList(ephemeralPrivate),
      theirBundle.signedPrekey.publicKey,
    );

    Uint8List? dh4;
    if (theirBundle.oneTimePrekey != null) {
      dh4 = await _computeDH(
        Uint8List.fromList(ephemeralPrivate),
        theirBundle.oneTimePrekey!.publicKey,
      );
    }

    final dhConcat = _concatenateDH(dh1, dh2, dh3, dh4);
    final ourIdentityPublic = await ourIdentityKey.toPublicKey();
    final ad = _generateAssociatedData(ourIdentityPublic, theirBundle.identityKey);

    final derivedKeys = _deriveKeys(dhConcat, ad);

    SecurityUtils.secureClear(Uint8List.fromList(ourIdentityPrivate));
    SecurityUtils.secureClear(Uint8List.fromList(ephemeralPrivate));
    SecurityUtils.secureClear(dh1);
    SecurityUtils.secureClear(dh2);
    SecurityUtils.secureClear(dh3);
    if (dh4 != null) SecurityUtils.secureClear(dh4);
    SecurityUtils.secureClear(dhConcat);

    return X3DHResult(
      rootKey: derivedKeys.rootKey,
      chainKey: derivedKeys.chainKey,
      associatedData: ad,
      ephemeralPublicKey: Uint8List.fromList(ephemeralPublic.bytes),
      signedPrekeyId: theirBundle.signedPrekey.id,
      oneTimePrekeyId: theirBundle.oneTimePrekey?.id,
    );
  }

  Future<X3DHResult> respondToSession({
    required IdentityKeyPair ourIdentityKey,
    required Uint8List theirIdentityPublicKey,
    required Uint8List theirEphemeralPublicKey,
    required SignedPrekey ourSignedPrekey,
    OneTimePrekey? ourOneTimePrekey,
  }) async {
    final ourIdentityPrivate = await ourIdentityKey.x25519KeyPair.extractPrivateKeyBytes();
    final signedPrekeyPrivate = await ourSignedPrekey.keyPair.extractPrivateKeyBytes();

    final dh1 = await _computeDH(
      Uint8List.fromList(signedPrekeyPrivate),
      theirIdentityPublicKey,
    );

    final dh2 = await _computeDH(
      Uint8List.fromList(ourIdentityPrivate),
      theirEphemeralPublicKey,
    );

    final dh3 = await _computeDH(
      Uint8List.fromList(signedPrekeyPrivate),
      theirEphemeralPublicKey,
    );

    Uint8List? dh4;
    if (ourOneTimePrekey != null) {
      final otpPrivate = await ourOneTimePrekey.keyPair.extractPrivateKeyBytes();
      dh4 = await _computeDH(
        Uint8List.fromList(otpPrivate),
        theirEphemeralPublicKey,
      );
      SecurityUtils.secureClear(Uint8List.fromList(otpPrivate));
    }

    final dhConcat = _concatenateDH(dh1, dh2, dh3, dh4);
    final ourIdentityPublic = await ourIdentityKey.toPublicKey();
    final ad = _generateAssociatedDataFromBytes(
      theirIdentityPublicKey,
      ourIdentityPublic.x25519PublicKey,
    );

    final derivedKeys = _deriveKeys(dhConcat, ad);

    SecurityUtils.secureClear(Uint8List.fromList(ourIdentityPrivate));
    SecurityUtils.secureClear(Uint8List.fromList(signedPrekeyPrivate));
    SecurityUtils.secureClear(dh1);
    SecurityUtils.secureClear(dh2);
    SecurityUtils.secureClear(dh3);
    if (dh4 != null) SecurityUtils.secureClear(dh4);
    SecurityUtils.secureClear(dhConcat);

    return X3DHResult(
      rootKey: derivedKeys.rootKey,
      chainKey: derivedKeys.chainKey,
      associatedData: ad,
      signedPrekeyId: ourSignedPrekey.id,
      oneTimePrekeyId: ourOneTimePrekey?.id,
    );
  }

  Future<Uint8List> _computeDH(Uint8List privateKey, Uint8List publicKey) async {
    final keyPair = await _x25519.newKeyPairFromSeed(privateKey);
    final remotePublic = SimplePublicKey(publicKey, type: KeyPairType.x25519);
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: remotePublic,
    );
    return Uint8List.fromList(await sharedSecret.extractBytes());
  }

  Uint8List _concatenateDH(Uint8List dh1, Uint8List dh2, Uint8List dh3, Uint8List? dh4) {
    final totalLen = 32 + 32 + 32 + (dh4 != null ? 32 : 0);
    final result = Uint8List(totalLen);
    result.setRange(0, 32, dh1);
    result.setRange(32, 64, dh2);
    result.setRange(64, 96, dh3);
    if (dh4 != null) {
      result.setRange(96, 128, dh4);
    }
    return result;
  }

  Uint8List _generateAssociatedData(IdentityPublicKey initiator, IdentityPublicKey responder) {
    return _generateAssociatedDataFromBytes(
      initiator.x25519PublicKey,
      responder.x25519PublicKey,
    );
  }

  Uint8List _generateAssociatedDataFromBytes(Uint8List initiatorX25519, Uint8List responderX25519) {
    final sorted = _sortKeys(initiatorX25519, responderX25519);

    return Uint8List.fromList([
      ...utf8.encode('EchoAAD-v1'),
      ...sorted.first,
      ...sorted.second,
    ]);
  }

  ({Uint8List first, Uint8List second}) _sortKeys(Uint8List a, Uint8List b) {
    for (int i = 0; i < a.length && i < b.length; i++) {
      if (a[i] < b[i]) return (first: a, second: b);
      if (a[i] > b[i]) return (first: b, second: a);
    }
    return (first: a, second: b);
  }

  ({Uint8List rootKey, Uint8List chainKey}) _deriveKeys(Uint8List dhConcat, Uint8List ad) {
    final derived = SecurityUtils.hkdfSha256(
      dhConcat,
      ad,
      Uint8List.fromList(utf8.encode(_kdfInfo)),
      _derivedKeyLength,
    );

    return (
      rootKey: Uint8List.fromList(derived.sublist(0, 32)),
      chainKey: Uint8List.fromList(derived.sublist(32, 64)),
    );
  }

  Future<bool> verifySignedPrekey({
    required SignedPrekeyPublic prekey,
    required Uint8List identityPublicKey,
  }) async {
    return prekey.verify(identityPublicKey);
  }
}
