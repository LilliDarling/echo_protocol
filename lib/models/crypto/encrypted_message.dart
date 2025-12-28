import 'dart:convert';
import 'dart:typed_data';

enum MessageType {
  whisper(1),
  preKey(2),
  keyConfirmation(3);

  final int value;
  const MessageType(this.value);

  static MessageType fromValue(int value) {
    return MessageType.values.firstWhere((t) => t.value == value);
  }
}

class EncryptedMessage {
  static const int currentVersion = 1;

  final MessageType type;
  final int version;
  final Uint8List senderRatchetKey;
  final int previousChainLength;
  final int messageIndex;
  final Uint8List ciphertext;

  EncryptedMessage({
    required this.type,
    this.version = currentVersion,
    required this.senderRatchetKey,
    required this.previousChainLength,
    required this.messageIndex,
    required this.ciphertext,
  });

  Uint8List toBytes() {
    final ctLen = ciphertext.length;
    final bytes = Uint8List(4 + 32 + 4 + 4 + 4 + ctLen);
    final buffer = ByteData.view(bytes.buffer);

    buffer.setUint8(0, type.value);
    buffer.setUint8(1, version);
    buffer.setUint16(2, 0, Endian.big);
    bytes.setRange(4, 36, senderRatchetKey);
    buffer.setInt32(36, previousChainLength, Endian.big);
    buffer.setInt32(40, messageIndex, Endian.big);
    buffer.setInt32(44, ctLen, Endian.big);
    bytes.setRange(48, 48 + ctLen, ciphertext);

    return bytes;
  }

  factory EncryptedMessage.fromBytes(Uint8List bytes) {
    final buffer = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);

    final type = MessageType.fromValue(buffer.getUint8(0));
    final version = buffer.getUint8(1);
    final senderRatchetKey = Uint8List.fromList(bytes.sublist(4, 36));
    final previousChainLength = buffer.getInt32(36, Endian.big);
    final messageIndex = buffer.getInt32(40, Endian.big);
    final ctLen = buffer.getInt32(44, Endian.big);
    final ciphertext = Uint8List.fromList(bytes.sublist(48, 48 + ctLen));

    return EncryptedMessage(
      type: type,
      version: version,
      senderRatchetKey: senderRatchetKey,
      previousChainLength: previousChainLength,
      messageIndex: messageIndex,
      ciphertext: ciphertext,
    );
  }

  String toBase64() => base64Encode(toBytes());

  factory EncryptedMessage.fromBase64(String encoded) {
    return EncryptedMessage.fromBytes(base64Decode(encoded));
  }

  Map<String, dynamic> toJson() => {
    'type': type.value,
    'version': version,
    'senderRatchetKey': base64Encode(senderRatchetKey),
    'previousChainLength': previousChainLength,
    'messageIndex': messageIndex,
    'ciphertext': base64Encode(ciphertext),
  };

  factory EncryptedMessage.fromJson(Map<String, dynamic> json) => EncryptedMessage(
    type: MessageType.fromValue(json['type'] as int),
    version: json['version'] as int,
    senderRatchetKey: base64Decode(json['senderRatchetKey'] as String),
    previousChainLength: json['previousChainLength'] as int,
    messageIndex: json['messageIndex'] as int,
    ciphertext: base64Decode(json['ciphertext'] as String),
  );
}

class PreKeyMessage {
  static const int currentVersion = 2;

  final int version;
  final Uint8List senderIdentityKeyEd25519;
  final Uint8List senderIdentityKeyX25519;
  final Uint8List ephemeralKey;
  final int signedPrekeyId;
  final int? oneTimePrekeyId;
  final EncryptedMessage innerMessage;

  PreKeyMessage({
    this.version = currentVersion,
    required this.senderIdentityKeyEd25519,
    required this.senderIdentityKeyX25519,
    required this.ephemeralKey,
    required this.signedPrekeyId,
    this.oneTimePrekeyId,
    required this.innerMessage,
  });

  Uint8List toBytes() {
    final innerBytes = innerMessage.toBytes();
    final bytes = Uint8List(4 + 32 + 32 + 32 + 4 + 4 + 4 + innerBytes.length);
    final buffer = ByteData.view(bytes.buffer);

    buffer.setUint8(0, MessageType.preKey.value);
    buffer.setUint8(1, version);
    buffer.setUint16(2, 0, Endian.big);
    bytes.setRange(4, 36, senderIdentityKeyEd25519);
    bytes.setRange(36, 68, senderIdentityKeyX25519);
    bytes.setRange(68, 100, ephemeralKey);
    buffer.setInt32(100, signedPrekeyId, Endian.big);
    buffer.setInt32(104, oneTimePrekeyId ?? 0, Endian.big);
    buffer.setInt32(108, innerBytes.length, Endian.big);
    bytes.setRange(112, 112 + innerBytes.length, innerBytes);

    return bytes;
  }

  factory PreKeyMessage.fromBytes(Uint8List bytes) {
    final buffer = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
    final version = buffer.getUint8(1);

    if (version != currentVersion) {
      throw ArgumentError('Unsupported PreKeyMessage version: $version');
    }

    final senderIdentityKeyEd25519 = Uint8List.fromList(bytes.sublist(4, 36));
    final senderIdentityKeyX25519 = Uint8List.fromList(bytes.sublist(36, 68));
    final ephemeralKey = Uint8List.fromList(bytes.sublist(68, 100));
    final signedPrekeyId = buffer.getInt32(100, Endian.big);
    final oneTimePrekeyIdValue = buffer.getInt32(104, Endian.big);
    final innerLen = buffer.getInt32(108, Endian.big);
    final innerBytes = Uint8List.fromList(bytes.sublist(112, 112 + innerLen));

    return PreKeyMessage(
      version: version,
      senderIdentityKeyEd25519: senderIdentityKeyEd25519,
      senderIdentityKeyX25519: senderIdentityKeyX25519,
      ephemeralKey: ephemeralKey,
      signedPrekeyId: signedPrekeyId,
      oneTimePrekeyId: oneTimePrekeyIdValue == 0 ? null : oneTimePrekeyIdValue,
      innerMessage: EncryptedMessage.fromBytes(innerBytes),
    );
  }

  String toBase64() => base64Encode(toBytes());

  factory PreKeyMessage.fromBase64(String encoded) {
    return PreKeyMessage.fromBytes(base64Decode(encoded));
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'senderIdentityKeyEd25519': base64Encode(senderIdentityKeyEd25519),
    'senderIdentityKeyX25519': base64Encode(senderIdentityKeyX25519),
    'ephemeralKey': base64Encode(ephemeralKey),
    'signedPrekeyId': signedPrekeyId,
    'oneTimePrekeyId': oneTimePrekeyId,
    'innerMessage': innerMessage.toJson(),
  };

  factory PreKeyMessage.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int;

    if (version != currentVersion) {
      throw ArgumentError('Unsupported PreKeyMessage version: $version');
    }

    return PreKeyMessage(
      version: version,
      senderIdentityKeyEd25519: base64Decode(json['senderIdentityKeyEd25519'] as String),
      senderIdentityKeyX25519: base64Decode(json['senderIdentityKeyX25519'] as String),
      ephemeralKey: base64Decode(json['ephemeralKey'] as String),
      signedPrekeyId: json['signedPrekeyId'] as int,
      oneTimePrekeyId: json['oneTimePrekeyId'] as int?,
      innerMessage: EncryptedMessage.fromJson(json['innerMessage'] as Map<String, dynamic>),
    );
  }

  static bool isPreKeyMessage(Uint8List bytes) {
    if (bytes.isEmpty) return false;
    return bytes[0] == MessageType.preKey.value;
  }

  static bool isPreKeyMessageBase64(String encoded) {
    try {
      final bytes = base64Decode(encoded);
      return isPreKeyMessage(bytes);
    } catch (_) {
      return false;
    }
  }
}
