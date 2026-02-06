import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../../utils/security.dart';
import 'sender_certificate.dart';

class SealedEnvelope {
  final String recipientId;
  final Uint8List encryptedPayload;
  final Uint8List ephemeralPublicKey;
  final int timestamp;
  final int expireAt;

  static const int _defaultTtlHours = 24;

  SealedEnvelope({
    required this.recipientId,
    required this.encryptedPayload,
    required this.ephemeralPublicKey,
    required this.timestamp,
    required this.expireAt,
  });

  static Future<SealedEnvelope> seal({
    required String senderId,
    required String recipientId,
    required Uint8List recipientPublicKey,
    required Uint8List encryptedMessage,
    required SimpleKeyPair senderSigningKey,
    required Uint8List senderPublicKey,
  }) async {
    final certificate = await SenderCertificate.create(
      senderId: senderId,
      senderPublicKey: senderPublicKey,
      signingKeyPair: senderSigningKey,
    );

    final innerPayload = _buildInnerPayload(certificate, encryptedMessage);

    final x25519 = X25519();
    final ephemeralKeyPair = await x25519.newKeyPair();
    final ephemeralPublicKey = await ephemeralKeyPair.extractPublicKey();

    final recipientKey = SimplePublicKey(recipientPublicKey, type: KeyPairType.x25519);
    final sharedSecret = await x25519.sharedSecretKey(
      keyPair: ephemeralKeyPair,
      remotePublicKey: recipientKey,
    );
    final sharedSecretBytes = await sharedSecret.extractBytes();

    final encryptionKey = SecurityUtils.hkdfSha256(
      Uint8List.fromList(sharedSecretBytes),
      Uint8List.fromList(utf8.encode('SealedSender-v1')),
      Uint8List.fromList([...ephemeralPublicKey.bytes, ...recipientPublicKey]),
      32,
    );

    final aesGcm = AesGcm.with256bits();
    final nonce = SecurityUtils.generateSecureRandomBytes(12);
    final secretBox = await aesGcm.encrypt(
      innerPayload,
      secretKey: SecretKey(encryptionKey),
      nonce: nonce,
    );

    final encryptedPayload = Uint8List.fromList([
      ...nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);

    SecurityUtils.secureClear(Uint8List.fromList(sharedSecretBytes));
    SecurityUtils.secureClear(encryptionKey);

    final now = DateTime.now();
    return SealedEnvelope(
      recipientId: recipientId,
      encryptedPayload: encryptedPayload,
      ephemeralPublicKey: Uint8List.fromList(ephemeralPublicKey.bytes),
      timestamp: now.millisecondsSinceEpoch,
      expireAt: now.add(Duration(hours: _defaultTtlHours)).millisecondsSinceEpoch,
    );
  }

  static Uint8List _buildInnerPayload(SenderCertificate cert, Uint8List message) {
    final certBytes = cert.toBytes();
    final certLenBytes = ByteData(2)..setUint16(0, certBytes.length, Endian.big);

    return Uint8List.fromList([
      ...certLenBytes.buffer.asUint8List(),
      ...certBytes,
      ...message,
    ]);
  }

  Future<UnsealedContent> unseal({
    required SimpleKeyPair recipientKeyPair,
  }) async {
    final x25519 = X25519();

    final ephemeralKey = SimplePublicKey(ephemeralPublicKey, type: KeyPairType.x25519);
    final sharedSecret = await x25519.sharedSecretKey(
      keyPair: recipientKeyPair,
      remotePublicKey: ephemeralKey,
    );
    final sharedSecretBytes = await sharedSecret.extractBytes();

    final recipientPublicKey = await recipientKeyPair.extractPublicKey();
    final decryptionKey = SecurityUtils.hkdfSha256(
      Uint8List.fromList(sharedSecretBytes),
      Uint8List.fromList(utf8.encode('SealedSender-v1')),
      Uint8List.fromList([...ephemeralPublicKey, ...recipientPublicKey.bytes]),
      32,
    );

    final nonce = encryptedPayload.sublist(0, 12);
    final ciphertext = encryptedPayload.sublist(12, encryptedPayload.length - 16);
    final mac = encryptedPayload.sublist(encryptedPayload.length - 16);

    final aesGcm = AesGcm.with256bits();
    final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(mac));

    final innerPayload = await aesGcm.decrypt(
      secretBox,
      secretKey: SecretKey(decryptionKey),
    );

    SecurityUtils.secureClear(Uint8List.fromList(sharedSecretBytes));
    SecurityUtils.secureClear(decryptionKey);

    final innerBytes = Uint8List.fromList(innerPayload);
    final certLen = ByteData.sublistView(innerBytes, 0, 2).getUint16(0, Endian.big);
    final certBytes = innerBytes.sublist(2, 2 + certLen);
    final encryptedMessage = innerBytes.sublist(2 + certLen);

    final certificate = SenderCertificate.fromBytes(certBytes);

    final isValid = await certificate.verify();
    if (!isValid) {
      throw Exception('Invalid sender certificate');
    }

    return UnsealedContent(
      senderId: certificate.senderId,
      senderPublicKey: certificate.senderPublicKey,
      encryptedMessage: encryptedMessage,
      certificateTimestamp: certificate.timestamp,
    );
  }

  Map<String, dynamic> toJson() => {
    'recipientId': recipientId,
    'payload': base64Encode(encryptedPayload),
    'ephemeralKey': base64Encode(ephemeralPublicKey),
    'timestamp': timestamp,
    'expireAt': expireAt,
  };

  factory SealedEnvelope.fromJson(Map<String, dynamic> json) {
    return SealedEnvelope(
      recipientId: json['recipientId'] as String,
      encryptedPayload: base64Decode(json['payload'] as String),
      ephemeralPublicKey: base64Decode(json['ephemeralKey'] as String),
      timestamp: json['timestamp'] as int,
      expireAt: json['expireAt'] as int,
    );
  }

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expireAt;
}

class UnsealedContent {
  final String senderId;
  final Uint8List senderPublicKey;
  final Uint8List encryptedMessage;
  final int certificateTimestamp;

  UnsealedContent({
    required this.senderId,
    required this.senderPublicKey,
    required this.encryptedMessage,
    required this.certificateTimestamp,
  });
}
