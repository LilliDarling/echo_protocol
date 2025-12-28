import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../../utils/security.dart';
import 'identity_key.dart';

class SignedPrekey {
  final int id;
  final SimpleKeyPair keyPair;
  final Uint8List signature;
  final DateTime createdAt;
  final DateTime expiresAt;
  bool used;

  SignedPrekey._({
    required this.id,
    required this.keyPair,
    required this.signature,
    required this.createdAt,
    required this.expiresAt,
    this.used = false,
  });

  static Future<SignedPrekey> generate({
    required int id,
    required IdentityKeyPair identityKey,
    Duration validity = const Duration(days: 30),
  }) async {
    final x25519 = X25519();
    final keyPair = await x25519.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();

    final signature = await identityKey.sign(Uint8List.fromList(publicKey.bytes));
    final now = DateTime.now();

    return SignedPrekey._(
      id: id,
      keyPair: keyPair,
      signature: signature,
      createdAt: now,
      expiresAt: now.add(validity),
    );
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Future<SignedPrekeyPublic> toPublic() async {
    final publicKey = await keyPair.extractPublicKey();
    return SignedPrekeyPublic(
      id: id,
      publicKey: Uint8List.fromList(publicKey.bytes),
      signature: signature,
      expiresAt: expiresAt,
    );
  }

  Future<Map<String, String>> toSecureStorage() async {
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    return {
      'id': id.toString(),
      'private': base64Encode(privateBytes),
      'signature': base64Encode(signature),
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'used': used.toString(),
    };
  }

  static Future<SignedPrekey> fromSecureStorage(Map<String, String> data) async {
    final x25519 = X25519();
    final privateBytes = base64Decode(data['private']!);
    final keyPair = await x25519.newKeyPairFromSeed(privateBytes);

    return SignedPrekey._(
      id: int.parse(data['id']!),
      keyPair: keyPair,
      signature: base64Decode(data['signature']!),
      createdAt: DateTime.parse(data['createdAt']!),
      expiresAt: DateTime.parse(data['expiresAt']!),
      used: data['used'] == 'true',
    );
  }

  Future<void> dispose() async {
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    SecurityUtils.secureClear(Uint8List.fromList(privateBytes));
  }
}

class SignedPrekeyPublic {
  final int id;
  final Uint8List publicKey;
  final Uint8List signature;
  final DateTime expiresAt;

  SignedPrekeyPublic({
    required this.id,
    required this.publicKey,
    required this.signature,
    required this.expiresAt,
  });

  Future<bool> verify(Uint8List identityPublicKey) async {
    return IdentityPublicKey.verify(publicKey, signature, identityPublicKey);
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
    'id': id,
    'publicKey': base64Encode(publicKey),
    'signature': base64Encode(signature),
    'expiresAt': expiresAt.millisecondsSinceEpoch,
  };

  factory SignedPrekeyPublic.fromJson(Map<String, dynamic> json) => SignedPrekeyPublic(
    id: json['id'] as int,
    publicKey: base64Decode(json['publicKey'] as String),
    signature: base64Decode(json['signature'] as String),
    expiresAt: DateTime.fromMillisecondsSinceEpoch(json['expiresAt'] as int),
  );

  Uint8List toBytes() {
    final buffer = ByteData(4 + 32 + 64 + 8);
    buffer.setInt32(0, id, Endian.big);
    final bytes = Uint8List.view(buffer.buffer);
    bytes.setRange(4, 36, publicKey);
    bytes.setRange(36, 100, signature);
    buffer.setInt64(100, expiresAt.millisecondsSinceEpoch, Endian.big);
    return bytes;
  }

  factory SignedPrekeyPublic.fromBytes(Uint8List bytes) {
    final buffer = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
    return SignedPrekeyPublic(
      id: buffer.getInt32(0, Endian.big),
      publicKey: Uint8List.fromList(bytes.sublist(4, 36)),
      signature: Uint8List.fromList(bytes.sublist(36, 100)),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(buffer.getInt64(100, Endian.big)),
    );
  }
}

class OneTimePrekey {
  final int id;
  final SimpleKeyPair keyPair;
  final DateTime createdAt;
  bool consumed;

  OneTimePrekey._({
    required this.id,
    required this.keyPair,
    required this.createdAt,
    this.consumed = false,
  });

  static Future<OneTimePrekey> generate(int id) async {
    final x25519 = X25519();
    final keyPair = await x25519.newKeyPair();
    return OneTimePrekey._(
      id: id,
      keyPair: keyPair,
      createdAt: DateTime.now(),
    );
  }

  static Future<List<OneTimePrekey>> generateBatch(int startId, int count) async {
    final prekeys = <OneTimePrekey>[];
    for (int i = 0; i < count; i++) {
      prekeys.add(await generate(startId + i));
    }
    return prekeys;
  }

  Future<OneTimePrekeyPublic> toPublic() async {
    final publicKey = await keyPair.extractPublicKey();
    return OneTimePrekeyPublic(
      id: id,
      publicKey: Uint8List.fromList(publicKey.bytes),
    );
  }

  Future<Map<String, String>> toSecureStorage() async {
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    return {
      'id': id.toString(),
      'private': base64Encode(privateBytes),
      'createdAt': createdAt.toIso8601String(),
      'consumed': consumed.toString(),
    };
  }

  static Future<OneTimePrekey> fromSecureStorage(Map<String, String> data) async {
    final x25519 = X25519();
    final privateBytes = base64Decode(data['private']!);
    final keyPair = await x25519.newKeyPairFromSeed(privateBytes);

    return OneTimePrekey._(
      id: int.parse(data['id']!),
      keyPair: keyPair,
      createdAt: DateTime.parse(data['createdAt']!),
      consumed: data['consumed'] == 'true',
    );
  }

  Future<void> dispose() async {
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    SecurityUtils.secureClear(Uint8List.fromList(privateBytes));
  }
}

class OneTimePrekeyPublic {
  final int id;
  final Uint8List publicKey;

  OneTimePrekeyPublic({
    required this.id,
    required this.publicKey,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'publicKey': base64Encode(publicKey),
  };

  factory OneTimePrekeyPublic.fromJson(Map<String, dynamic> json) => OneTimePrekeyPublic(
    id: json['id'] as int,
    publicKey: base64Decode(json['publicKey'] as String),
  );

  Uint8List toBytes() {
    final bytes = Uint8List(4 + 32);
    final buffer = ByteData.view(bytes.buffer);
    buffer.setInt32(0, id, Endian.big);
    bytes.setRange(4, 36, publicKey);
    return bytes;
  }

  factory OneTimePrekeyPublic.fromBytes(Uint8List bytes) {
    final buffer = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
    return OneTimePrekeyPublic(
      id: buffer.getInt32(0, Endian.big),
      publicKey: Uint8List.fromList(bytes.sublist(4, 36)),
    );
  }
}

class PreKeyBundle {
  final IdentityPublicKey identityKey;
  final SignedPrekeyPublic signedPrekey;
  final OneTimePrekeyPublic? oneTimePrekey;
  final int registrationId;

  PreKeyBundle({
    required this.identityKey,
    required this.signedPrekey,
    this.oneTimePrekey,
    required this.registrationId,
  });

  Future<bool> validate() async {
    if (signedPrekey.isExpired) return false;
    return signedPrekey.verify(identityKey.ed25519PublicKey);
  }

  Map<String, dynamic> toJson() => {
    'identityKey': identityKey.toJson(),
    'signedPrekey': signedPrekey.toJson(),
    'oneTimePrekey': oneTimePrekey?.toJson(),
    'registrationId': registrationId,
  };

  factory PreKeyBundle.fromJson(Map<String, dynamic> json) => PreKeyBundle(
    identityKey: IdentityPublicKey.fromJson(json['identityKey'] as Map<String, dynamic>),
    signedPrekey: SignedPrekeyPublic.fromJson(json['signedPrekey'] as Map<String, dynamic>),
    oneTimePrekey: json['oneTimePrekey'] != null
        ? OneTimePrekeyPublic.fromJson(json['oneTimePrekey'] as Map<String, dynamic>)
        : null,
    registrationId: json['registrationId'] as int,
  );
}
