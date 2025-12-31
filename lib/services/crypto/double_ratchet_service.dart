import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../../models/crypto/identity_key.dart';
import '../../models/crypto/prekey.dart';
import '../../models/crypto/ratchet_session.dart';
import '../../models/crypto/encrypted_message.dart';
import '../../utils/security.dart';
import 'x3dh_service.dart';

class DoubleRatchetService {
  static const String _rootKdfInfo = 'EchoProtocol-RootKDF-v1';
  static const String _chainKdfInfo = 'EchoProtocol-ChainKDF-v1';

  final X25519 _x25519 = X25519();
  final AesGcm _aesGcm = AesGcm.with256bits();

  Future<RatchetSession> initializeAsInitiator({
    required X3DHResult x3dhResult,
    required String ourUserId,
    required String theirUserId,
    required IdentityPublicKey theirIdentityKey,
    required Uint8List theirRatchetPublicKey,
  }) async {
    final sessionId = RatchetSession.generateSessionId(ourUserId, theirUserId);
    final now = DateTime.now();

    final newKeyPair = await _x25519.newKeyPair();
    final newPublic = await newKeyPair.extractPublicKey();
    final newPrivate = await newKeyPair.extractPrivateKeyBytes();

    final dhOutput = await _computeDH(Uint8List.fromList(newPrivate), theirRatchetPublicKey);
    final (rootKey, chainKey) = await _kdfRootKey(x3dhResult.rootKey, dhOutput, _rootKdfInfo);
    SecurityUtils.secureClear(dhOutput);

    return RatchetSession(
      sessionId: sessionId,
      ourUserId: ourUserId,
      theirUserId: theirUserId,
      theirIdentityKey: theirIdentityKey,
      rootKey: rootKey,
      ourRatchetPrivateKey: Uint8List.fromList(newPrivate),
      ourRatchetPublicKey: Uint8List.fromList(newPublic.bytes),
      theirRatchetPublicKey: theirRatchetPublicKey,
      sendingChain: ChainState(
        chainKey: chainKey,
        messageIndex: 0,
        ratchetPublicKey: Uint8List.fromList(newPublic.bytes),
      ),
      createdAt: now,
      lastActivityAt: now,
      isInitiator: true,
    );
  }

  Future<RatchetSession> initializeAsResponder({
    required X3DHResult x3dhResult,
    required String ourUserId,
    required String theirUserId,
    required IdentityPublicKey theirIdentityKey,
    required SignedPrekey ourSignedPrekey,
  }) async {
    final sessionId = RatchetSession.generateSessionId(ourUserId, theirUserId);
    final now = DateTime.now();

    final signedPrekeyPublic = await ourSignedPrekey.keyPair.extractPublicKey();
    final signedPrekeyPrivate = await ourSignedPrekey.keyPair.extractPrivateKeyBytes();

    return RatchetSession(
      sessionId: sessionId,
      ourUserId: ourUserId,
      theirUserId: theirUserId,
      theirIdentityKey: theirIdentityKey,
      rootKey: x3dhResult.rootKey,
      ourRatchetPrivateKey: Uint8List.fromList(signedPrekeyPrivate),
      ourRatchetPublicKey: Uint8List.fromList(signedPrekeyPublic.bytes),
      receivingChain: ChainState(
        chainKey: x3dhResult.chainKey,
        messageIndex: 0,
        ratchetPublicKey: Uint8List(0),
      ),
      createdAt: now,
      lastActivityAt: now,
      isInitiator: false,
    );
  }

  Future<EncryptedMessage> encrypt({
    required RatchetSession session,
    required Uint8List plaintext,
  }) async {
    if (session.sendingChain == null) {
      await _performSendingRatchet(session);
    }

    final (newChainKey, messageKey) = await _kdfChainKey(session.sendingChain!.chainKey);
    session.sendingChain!.chainKey = newChainKey;

    final aad = _constructAAD(
      senderId: session.ourUserId,
      recipientId: session.theirUserId,
      senderRatchetKey: session.ourRatchetPublicKey!,
      messageIndex: session.sendingChain!.messageIndex,
      sessionAD: session.associatedData,
    );

    final ciphertext = await _aesEncrypt(messageKey, plaintext, aad);
    SecurityUtils.secureClear(messageKey);

    final message = EncryptedMessage(
      type: MessageType.whisper,
      senderRatchetKey: session.ourRatchetPublicKey!,
      previousChainLength: session.receivingChain?.messageIndex ?? 0,
      messageIndex: session.sendingChain!.messageIndex,
      ciphertext: ciphertext,
    );

    session.sendingChain!.messageIndex++;
    session.updateActivity();

    return message;
  }

  Future<Uint8List> decrypt({
    required RatchetSession session,
    required EncryptedMessage message,
  }) async {
    final skippedPlaintext = await _tryDecryptWithSkippedKey(session, message);
    if (skippedPlaintext != null) {
      session.updateActivity();
      return skippedPlaintext;
    }

    final theirKeyChanged = session.theirRatchetPublicKey == null ||
        !SecurityUtils.constantTimeBytesEquals(message.senderRatchetKey, session.theirRatchetPublicKey!);

    if (theirKeyChanged) {
      await _performReceivingRatchet(session, message);
    }

    await _skipMessageKeys(session, message.messageIndex);

    final (newChainKey, messageKey) = await _kdfChainKey(session.receivingChain!.chainKey);
    session.receivingChain!.chainKey = newChainKey;

    final aad = _constructAAD(
      senderId: session.theirUserId,
      recipientId: session.ourUserId,
      senderRatchetKey: message.senderRatchetKey,
      messageIndex: message.messageIndex,
      sessionAD: session.associatedData,
    );

    final plaintext = await _aesDecrypt(messageKey, message.ciphertext, aad);
    SecurityUtils.secureClear(messageKey);

    session.receivingChain!.messageIndex++;
    session.updateActivity();

    return plaintext;
  }

  Future<void> _performReceivingRatchet(RatchetSession session, EncryptedMessage message) async {
    if (session.receivingChain != null && session.theirRatchetPublicKey != null) {
      await _skipMessageKeys(session, message.previousChainLength);
      final chainId = _getChainId(session.theirRatchetPublicKey!);
      session.previousReceivingChains[chainId] = session.receivingChain!.clone();
    }

    session.theirRatchetPublicKey = Uint8List.fromList(message.senderRatchetKey);

    final dhOutput = await _computeDH(session.ourRatchetPrivateKey!, message.senderRatchetKey);
    final (newRootKey, recvChainKey) = await _kdfRootKey(session.rootKey, dhOutput, _rootKdfInfo);
    SecurityUtils.secureClear(dhOutput);

    session.rootKey = newRootKey;
    session.receivingChain = ChainState(
      chainKey: recvChainKey,
      messageIndex: 0,
      ratchetPublicKey: Uint8List.fromList(message.senderRatchetKey),
    );
  }

  Future<void> _performSendingRatchet(RatchetSession session) async {
    final newKeyPair = await _x25519.newKeyPair();
    final newPublic = await newKeyPair.extractPublicKey();
    final newPrivate = await newKeyPair.extractPrivateKeyBytes();

    if (session.ourRatchetPrivateKey != null) {
      SecurityUtils.secureClear(session.ourRatchetPrivateKey!);
    }

    session.ourRatchetPrivateKey = Uint8List.fromList(newPrivate);
    session.ourRatchetPublicKey = Uint8List.fromList(newPublic.bytes);

    final dhOutput = await _computeDH(session.ourRatchetPrivateKey!, session.theirRatchetPublicKey!);
    final (newRootKey, sendChainKey) = await _kdfRootKey(session.rootKey, dhOutput, _rootKdfInfo);
    SecurityUtils.secureClear(dhOutput);

    session.rootKey = newRootKey;
    session.sendingChain = ChainState(
      chainKey: sendChainKey,
      messageIndex: 0,
      ratchetPublicKey: Uint8List.fromList(newPublic.bytes),
    );
  }

  Future<void> _skipMessageKeys(RatchetSession session, int until) async {
    if (session.receivingChain == null) return;

    final skipCount = until - session.receivingChain!.messageIndex;
    if (skipCount <= 0) return;

    if (!session.canSkipMessages(skipCount)) {
      throw Exception('Decryption failed');
    }

    while (session.receivingChain!.messageIndex < until) {
      final (newChainKey, messageKey) = await _kdfChainKey(session.receivingChain!.chainKey);
      session.receivingChain!.chainKey = newChainKey;

      final keyId = _getSkippedKeyId(
        session.receivingChain!.ratchetPublicKey,
        session.receivingChain!.messageIndex,
      );

      session.skippedMessageKeys[keyId] = SkippedMessageKey(
        messageKey: messageKey,
        chainIndex: session.receivingChain!.messageIndex,
        ratchetPublicKey: Uint8List.fromList(session.receivingChain!.ratchetPublicKey),
        storedAt: DateTime.now(),
      );
      session.skippedKeysCount++;
      session.receivingChain!.messageIndex++;
    }
  }

  Future<Uint8List?> _tryDecryptWithSkippedKey(RatchetSession session, EncryptedMessage message) async {
    final keyId = _getSkippedKeyId(message.senderRatchetKey, message.messageIndex);
    final skippedKey = session.skippedMessageKeys[keyId];

    if (skippedKey == null) return null;
    if (skippedKey.isExpired()) {
      skippedKey.dispose();
      session.skippedMessageKeys.remove(keyId);
      session.skippedKeysCount--;
      return null;
    }

    final aad = _constructAAD(
      senderId: session.theirUserId,
      recipientId: session.ourUserId,
      senderRatchetKey: message.senderRatchetKey,
      messageIndex: message.messageIndex,
      sessionAD: session.associatedData,
    );

    final plaintext = await _aesDecrypt(skippedKey.messageKey, message.ciphertext, aad);

    skippedKey.dispose();
    session.skippedMessageKeys.remove(keyId);
    session.skippedKeysCount--;

    return plaintext;
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

  Future<(Uint8List, Uint8List)> _kdfRootKey(Uint8List rootKey, Uint8List dhOutput, String info) async {
    final derived = SecurityUtils.hkdfSha256(
      dhOutput,
      rootKey,
      Uint8List.fromList(utf8.encode(info)),
      64,
    );

    return (
      Uint8List.fromList(derived.sublist(0, 32)),
      Uint8List.fromList(derived.sublist(32, 64)),
    );
  }

  Future<(Uint8List, Uint8List)> _kdfChainKey(Uint8List chainKey) async {
    final messageKey = SecurityUtils.hkdfSha256(
      chainKey,
      Uint8List.fromList([0x01]),
      Uint8List.fromList(utf8.encode('$_chainKdfInfo-msg')),
      32,
    );

    final newChainKey = SecurityUtils.hkdfSha256(
      chainKey,
      Uint8List.fromList([0x02]),
      Uint8List.fromList(utf8.encode('$_chainKdfInfo-chain')),
      32,
    );

    return (newChainKey, messageKey);
  }

  Uint8List _constructAAD({
    required String senderId,
    required String recipientId,
    required Uint8List senderRatchetKey,
    required int messageIndex,
    required Uint8List sessionAD,
  }) {
    final senderBytes = utf8.encode(senderId);
    final recipientBytes = utf8.encode(recipientId);

    final buffer = ByteData(4);
    buffer.setInt32(0, messageIndex, Endian.big);

    return Uint8List.fromList([
      ...utf8.encode('EchoAAD-v1'),
      ...sessionAD,
      senderBytes.length,
      ...senderBytes,
      recipientBytes.length,
      ...recipientBytes,
      ...senderRatchetKey,
      ...buffer.buffer.asUint8List(),
    ]);
  }

  Future<Uint8List> _aesEncrypt(Uint8List messageKey, Uint8List plaintext, Uint8List aad) async {
    final secretKey = SecretKey(messageKey);
    final nonce = _deriveNonce(messageKey);

    final secretBox = await _aesGcm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
      aad: aad,
    );

    return Uint8List.fromList([...nonce, ...secretBox.cipherText, ...secretBox.mac.bytes]);
  }

  Uint8List _deriveNonce(Uint8List messageKey) {
    return SecurityUtils.hkdfSha256(
      messageKey,
      Uint8List.fromList([0x00]),
      Uint8List.fromList(utf8.encode('EchoProtocol-Nonce-v1')),
      12,
    );
  }

  Future<Uint8List> _aesDecrypt(Uint8List messageKey, Uint8List ciphertext, Uint8List aad) async {
    if (ciphertext.length < 28) {
      throw Exception('Decryption failed');
    }

    final nonce = ciphertext.sublist(0, 12);
    final ct = ciphertext.sublist(12, ciphertext.length - 16);
    final tag = ciphertext.sublist(ciphertext.length - 16);

    final secretKey = SecretKey(messageKey);
    final secretBox = SecretBox(ct, nonce: nonce, mac: Mac(tag));

    return Uint8List.fromList(await _aesGcm.decrypt(secretBox, secretKey: secretKey, aad: aad));
  }

  String _getChainId(Uint8List ratchetPublicKey) {
    return ratchetPublicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _getSkippedKeyId(Uint8List ratchetPublicKey, int index) {
    return '${_getChainId(ratchetPublicKey)}:$index';
  }

  void cleanupExpiredSkippedKeys(RatchetSession session) {
    session.cleanupExpiredKeys();
  }
}
