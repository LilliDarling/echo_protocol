import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class SenderCertificate {
  static const Duration defaultMaxAge = Duration(hours: 24);
  static const Duration defaultMaxClockSkew = Duration(minutes: 5);

  final String senderId;
  final Uint8List senderPublicKey;
  final int timestamp;
  final Uint8List signature;

  SenderCertificate({
    required this.senderId,
    required this.senderPublicKey,
    required this.timestamp,
    required this.signature,
  });

  static Future<SenderCertificate> create({
    required String senderId,
    required Uint8List senderPublicKey,
    required SimpleKeyPair signingKeyPair,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final dataToSign = _buildSigningData(senderId, senderPublicKey, timestamp);

    final ed25519 = Ed25519();
    final sig = await ed25519.sign(dataToSign, keyPair: signingKeyPair);

    return SenderCertificate(
      senderId: senderId,
      senderPublicKey: senderPublicKey,
      timestamp: timestamp,
      signature: Uint8List.fromList(sig.bytes),
    );
  }

  static Uint8List _buildSigningData(String senderId, Uint8List publicKey, int timestamp) {
    final senderIdBytes = utf8.encode(senderId);
    final timestampBytes = ByteData(8)..setInt64(0, timestamp, Endian.big);

    return Uint8List.fromList([
      ...utf8.encode('SenderCertificate-v1'),
      senderIdBytes.length,
      ...senderIdBytes,
      ...publicKey,
      ...timestampBytes.buffer.asUint8List(),
    ]);
  }

  Future<bool> verify({
    Duration maxAge = defaultMaxAge,
    Duration maxClockSkew = defaultMaxClockSkew,
  }) async {
    if (!_isTimestampValid(maxAge: maxAge, maxClockSkew: maxClockSkew)) return false;

    final dataToVerify = _buildSigningData(senderId, senderPublicKey, timestamp);

    try {
      final ed25519 = Ed25519();
      final sig = Signature(
        signature,
        publicKey: SimplePublicKey(senderPublicKey, type: KeyPairType.ed25519),
      );
      return await ed25519.verify(dataToVerify, signature: sig);
    } on ArgumentError {
      // Malformed key/signature bytes or truncated input data
      return false;
    }
  }

  bool _isTimestampValid({
    required Duration maxAge,
    required Duration maxClockSkew,
  }) {
    final certTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final age = now.difference(certTime);

    if (age.isNegative && age.abs() > maxClockSkew) {
      return false;
    }
    return age < maxAge;
  }

  Uint8List toBytes() {
    final senderIdBytes = utf8.encode(senderId);
    final timestampBytes = ByteData(8)..setInt64(0, timestamp, Endian.big);

    return Uint8List.fromList([
      senderIdBytes.length,
      ...senderIdBytes,
      ...senderPublicKey,
      ...timestampBytes.buffer.asUint8List(),
      ...signature,
    ]);
  }

  factory SenderCertificate.fromBytes(Uint8List bytes) {
    int offset = 0;

    final senderIdLen = bytes[offset++];
    final senderId = utf8.decode(bytes.sublist(offset, offset + senderIdLen));
    offset += senderIdLen;

    final senderPublicKey = Uint8List.fromList(bytes.sublist(offset, offset + 32));
    offset += 32;

    final timestampBytes = ByteData.sublistView(bytes, offset, offset + 8);
    final timestamp = timestampBytes.getInt64(0, Endian.big);
    offset += 8;

    final signature = Uint8List.fromList(bytes.sublist(offset, offset + 64));

    return SenderCertificate(
      senderId: senderId,
      senderPublicKey: senderPublicKey,
      timestamp: timestamp,
      signature: signature,
    );
  }
}
