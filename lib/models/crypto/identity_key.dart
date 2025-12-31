import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart';
import '../../utils/security.dart';

class IdentityKeyPair {
  final SimpleKeyPair ed25519KeyPair;
  final SimpleKeyPair x25519KeyPair;
  final DateTime createdAt;

  IdentityKeyPair._({
    required this.ed25519KeyPair,
    required this.x25519KeyPair,
    required this.createdAt,
  });

  static Future<IdentityKeyPair> generate() async {
    final ed25519 = Ed25519();
    final x25519 = X25519();

    final edKeyPair = await ed25519.newKeyPair();
    final xKeyPair = await x25519.newKeyPair();

    return IdentityKeyPair._(
      ed25519KeyPair: edKeyPair,
      x25519KeyPair: xKeyPair,
      createdAt: DateTime.now(),
    );
  }

  /// For low-entropy passphrases, use [fromPassphrase] instead.
  static Future<IdentityKeyPair> fromSeed(Uint8List seed) async {
    if (!SecurityUtils.isHighEntropySeed(seed)) {
      throw ArgumentError(
        'Seed appears to be low entropy. Use fromPassphrase() for user passphrases.',
      );
    }

    return _deriveFromMasterSeed(seed);
  }

  static Future<IdentityKeyPair> fromPassphrase(
    String passphrase, {
    Uint8List? salt,
  }) async {
    final derivationSalt = salt ?? SecurityUtils.generateSecureRandomBytes(32);

    final masterSeed = await SecurityUtils.argon2idDerive(
      passphrase: passphrase,
      salt: derivationSalt,
      outputLength: 64,
      memory: 65536,
      iterations: 3,
      parallelism: 4,
    );

    final result = await _deriveFromMasterSeed(masterSeed);
    SecurityUtils.secureClear(masterSeed);
    return result;
  }

  static Future<IdentityKeyPair> _deriveFromMasterSeed(Uint8List seed) async {
    final ed25519Seed = SecurityUtils.hkdfSha256(
      seed,
      Uint8List.fromList(utf8.encode('EchoProtocol-Identity-v1')),
      Uint8List.fromList(utf8.encode('ed25519-signing-key')),
      32,
    );

    final x25519Seed = SecurityUtils.hkdfSha256(
      seed,
      Uint8List.fromList(utf8.encode('EchoProtocol-Identity-v1')),
      Uint8List.fromList(utf8.encode('x25519-agreement-key')),
      32,
    );

    final ed25519 = Ed25519();
    final x25519 = X25519();

    final edKeyPair = await ed25519.newKeyPairFromSeed(ed25519Seed);
    final xKeyPair = await x25519.newKeyPairFromSeed(x25519Seed);

    SecurityUtils.secureClear(ed25519Seed);
    SecurityUtils.secureClear(x25519Seed);

    return IdentityKeyPair._(
      ed25519KeyPair: edKeyPair,
      x25519KeyPair: xKeyPair,
      createdAt: DateTime.now(),
    );
  }

  Future<String> get keyId async {
    final edPublic = await ed25519KeyPair.extractPublicKey();
    final bytes = Uint8List.fromList(edPublic.bytes);
    final hash = sha256.convert(bytes);
    return hash.bytes.sublist(0, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<Uint8List> sign(Uint8List data) async {
    final ed25519 = Ed25519();
    final signature = await ed25519.sign(data, keyPair: ed25519KeyPair);
    return Uint8List.fromList(signature.bytes);
  }

  Future<IdentityPublicKey> toPublicKey() async {
    final edPublic = await ed25519KeyPair.extractPublicKey();
    final xPublic = await x25519KeyPair.extractPublicKey();
    final id = await keyId;

    return IdentityPublicKey(
      ed25519PublicKey: Uint8List.fromList(edPublic.bytes),
      x25519PublicKey: Uint8List.fromList(xPublic.bytes),
      keyId: id,
    );
  }

  Future<Map<String, String>> toSecureStorage() async {
    final edPrivate = await ed25519KeyPair.extractPrivateKeyBytes();
    final xPrivate = await x25519KeyPair.extractPrivateKeyBytes();
    final id = await keyId;

    return {
      'ed25519Private': base64Encode(edPrivate),
      'x25519Private': base64Encode(xPrivate),
      'keyId': id,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static Future<IdentityKeyPair> fromSecureStorage(Map<String, String> data) async {
    final ed25519Bytes = base64Decode(data['ed25519Private']!);
    final x25519Bytes = base64Decode(data['x25519Private']!);

    final ed25519 = Ed25519();
    final x25519 = X25519();

    final edKeyPair = await ed25519.newKeyPairFromSeed(ed25519Bytes);
    final xKeyPair = await x25519.newKeyPairFromSeed(x25519Bytes);

    return IdentityKeyPair._(
      ed25519KeyPair: edKeyPair,
      x25519KeyPair: xKeyPair,
      createdAt: DateTime.parse(data['createdAt']!),
    );
  }

  Future<void> dispose() async {
    final edPrivate = await ed25519KeyPair.extractPrivateKeyBytes();
    final xPrivate = await x25519KeyPair.extractPrivateKeyBytes();
    SecurityUtils.secureClear(Uint8List.fromList(edPrivate));
    SecurityUtils.secureClear(Uint8List.fromList(xPrivate));
  }
}

class IdentityPublicKey {
  final Uint8List ed25519PublicKey;
  final Uint8List x25519PublicKey;
  final String keyId;

  IdentityPublicKey({
    required this.ed25519PublicKey,
    required this.x25519PublicKey,
    required this.keyId,
  });

  static Future<bool> verify(Uint8List data, Uint8List signature, Uint8List publicKey) async {
    final ed25519 = Ed25519();
    final sig = Signature(signature, publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519));
    return ed25519.verify(data, signature: sig);
  }

  String get fingerprint {
    final combined = Uint8List.fromList([...ed25519PublicKey, ...x25519PublicKey]);
    final hash = sha256.convert(combined);
    final hex = hash.bytes.sublist(0, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    return List.generate(8, (i) => hex.substring(i * 4, i * 4 + 4)).join(' ');
  }

  Map<String, dynamic> toJson() => {
    'ed25519': base64Encode(ed25519PublicKey),
    'x25519': base64Encode(x25519PublicKey),
    'keyId': keyId,
  };

  factory IdentityPublicKey.fromJson(Map<String, dynamic> json) {
    final ed25519 = json['ed25519'];
    final x25519 = json['x25519'];
    final keyId = json['keyId'];

    if (ed25519 == null || x25519 == null || keyId == null) {
      throw Exception('Invalid identity key data - missing required fields');
    }

    return IdentityPublicKey(
      ed25519PublicKey: base64Decode(ed25519 as String),
      x25519PublicKey: base64Decode(x25519 as String),
      keyId: keyId as String,
    );
  }

  Uint8List toBytes() {
    final keyIdBytes = utf8.encode(keyId);
    return Uint8List.fromList([
      keyIdBytes.length,
      ...keyIdBytes,
      ...ed25519PublicKey,
      ...x25519PublicKey,
    ]);
  }

  factory IdentityPublicKey.fromBytes(Uint8List bytes) {
    int offset = 0;
    final keyIdLen = bytes[offset++];
    final keyId = utf8.decode(bytes.sublist(offset, offset + keyIdLen));
    offset += keyIdLen;
    final ed25519 = bytes.sublist(offset, offset + 32);
    offset += 32;
    final x25519 = bytes.sublist(offset, offset + 32);

    return IdentityPublicKey(
      ed25519PublicKey: Uint8List.fromList(ed25519),
      x25519PublicKey: Uint8List.fromList(x25519),
      keyId: keyId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is IdentityPublicKey &&
      SecurityUtils.constantTimeBytesEquals(ed25519PublicKey, other.ed25519PublicKey) &&
      SecurityUtils.constantTimeBytesEquals(x25519PublicKey, other.x25519PublicKey);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(ed25519PublicKey),
    Object.hashAll(x25519PublicKey),
  );
}
