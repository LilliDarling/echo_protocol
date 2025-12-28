import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:http/http.dart' as http;
import '../../models/crypto/ratchet_session.dart';
import '../../utils/security.dart';
import 'session_manager.dart';

class MediaEncryptionService {
  static const String _mediaKdfInfo = 'EchoProtocol-MediaKey-v1';
  static const String _mediaChainInfo = 'EchoProtocol-MediaChain-v1';
  static const String _cacheSubdir = 'decrypted_media';

  final SessionManager _sessionManager;
  final AesGcm _aesGcm = AesGcm.with256bits();

  MediaEncryptionService({SessionManager? sessionManager})
      : _sessionManager = sessionManager ?? SessionManager();

  Future<({Uint8List encrypted, String mediaId})> encryptMedia({
    required Uint8List plainBytes,
    required String recipientId,
    required String senderId,
  }) async {
    final session = await _sessionManager.getSession(recipientId, senderId);
    if (session == null) {
      throw Exception('Media encryption failed');
    }

    _initializeMediaChainIfNeeded(session);

    final mediaId = _generateMediaId(session.mediaKeyIndex);
    final mediaKey = _deriveMediaKey(session);

    session.mediaKeys[mediaId] = Uint8List.fromList(mediaKey);

    _advanceMediaChain(session);
    await _sessionManager.saveSession(session);

    final encrypted = await _aesEncrypt(mediaKey, plainBytes, mediaId);
    SecurityUtils.secureClear(mediaKey);

    return (encrypted: encrypted, mediaId: mediaId);
  }

  Future<Uint8List> decryptMedia({
    required Uint8List encryptedBytes,
    required String mediaId,
    required String senderId,
    required String myUserId,
  }) async {
    final session = await _sessionManager.getSession(senderId, myUserId);
    if (session == null) {
      throw Exception('Media decryption failed');
    }

    final mediaKey = session.mediaKeys[mediaId];
    if (mediaKey == null) {
      throw Exception('Media decryption failed');
    }

    return _aesDecrypt(mediaKey, encryptedBytes, mediaId);
  }

  Future<void> deleteMedia({
    required String mediaId,
    required String recipientId,
    required String senderId,
  }) async {
    final session = await _sessionManager.getSession(recipientId, senderId);
    if (session == null) return;

    session.deleteMediaKey(mediaId);
    await _sessionManager.saveSession(session);

    await _deleteCachedMedia(mediaId);
  }

  Future<String> downloadAndDecrypt({
    required String encryptedUrl,
    required String mediaId,
    required String senderId,
    required String myUserId,
    required bool isVideo,
  }) async {
    final cachedPath = await _getCachedFilePath(mediaId, isVideo);
    if (await File(cachedPath).exists()) {
      return cachedPath;
    }

    final response = await http.get(Uri.parse(encryptedUrl));
    if (response.statusCode != 200) {
      throw Exception('Media download failed');
    }

    final encryptedBytes = Uint8List.fromList(response.bodyBytes);
    final decryptedBytes = await decryptMedia(
      encryptedBytes: encryptedBytes,
      mediaId: mediaId,
      senderId: senderId,
      myUserId: myUserId,
    );

    final file = File(cachedPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(decryptedBytes);

    return cachedPath;
  }

  void _initializeMediaChainIfNeeded(RatchetSession session) {
    if (session.mediaChainKey != null) return;

    session.mediaChainKey = SecurityUtils.hkdfSha256(
      session.rootKey,
      Uint8List.fromList(utf8.encode('media-init')),
      Uint8List.fromList(utf8.encode(_mediaChainInfo)),
      32,
    );
    session.mediaKeyIndex = 0;
  }

  Uint8List _deriveMediaKey(RatchetSession session) {
    return SecurityUtils.hkdfSha256(
      session.mediaChainKey!,
      Uint8List.fromList([session.mediaKeyIndex & 0xFF]),
      Uint8List.fromList(utf8.encode(_mediaKdfInfo)),
      32,
    );
  }

  void _advanceMediaChain(RatchetSession session) {
    final newChainKey = SecurityUtils.hkdfSha256(
      session.mediaChainKey!,
      Uint8List.fromList([0xFF]),
      Uint8List.fromList(utf8.encode('$_mediaChainInfo-advance')),
      32,
    );

    SecurityUtils.secureClear(session.mediaChainKey!);
    session.mediaChainKey = newChainKey;
    session.mediaKeyIndex++;
  }

  String _generateMediaId(int index) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final data = '$timestamp:$index';
    final hash = crypto_pkg.sha256.convert(utf8.encode(data));
    return hash.toString().substring(0, 16);
  }

  Future<Uint8List> _aesEncrypt(Uint8List key, Uint8List plaintext, String mediaId) async {
    final secretKey = SecretKey(key);
    final nonce = SecurityUtils.generateSecureRandomBytes(12);
    final aad = utf8.encode('EchoMedia:$mediaId');

    final secretBox = await _aesGcm.encrypt(
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

  Future<Uint8List> _aesDecrypt(Uint8List key, Uint8List ciphertext, String mediaId) async {
    if (ciphertext.length < 12 + 16) {
      throw Exception('Media decryption failed');
    }

    final nonce = ciphertext.sublist(0, 12);
    final ct = ciphertext.sublist(12, ciphertext.length - 16);
    final tag = ciphertext.sublist(ciphertext.length - 16);
    final aad = utf8.encode('EchoMedia:$mediaId');

    final secretKey = SecretKey(key);
    final secretBox = SecretBox(ct, nonce: nonce, mac: Mac(tag));

    return Uint8List.fromList(
      await _aesGcm.decrypt(secretBox, secretKey: secretKey, aad: aad),
    );
  }

  Future<String> _getCachedFilePath(String mediaId, bool isVideo) async {
    final cacheDir = await getTemporaryDirectory();
    final extension = isVideo ? 'mp4' : 'jpg';
    return '${cacheDir.path}/$_cacheSubdir/$mediaId.$extension';
  }

  Future<void> _deleteCachedMedia(String mediaId) async {
    final cacheDir = await getTemporaryDirectory();
    final cacheSubdir = Directory('${cacheDir.path}/$_cacheSubdir');

    if (!await cacheSubdir.exists()) return;

    await for (final entity in cacheSubdir.list()) {
      if (entity is File && entity.path.contains(mediaId)) {
        await entity.delete();
      }
    }
  }

  Future<void> clearCache() async {
    final cacheDir = await getTemporaryDirectory();
    final mediaCache = Directory('${cacheDir.path}/$_cacheSubdir');
    if (await mediaCache.exists()) {
      await mediaCache.delete(recursive: true);
    }
  }

  Future<int> getCacheSize() async {
    final cacheDir = await getTemporaryDirectory();
    final mediaCache = Directory('${cacheDir.path}/$_cacheSubdir');
    if (!await mediaCache.exists()) {
      return 0;
    }

    int totalSize = 0;
    await for (final entity in mediaCache.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    return totalSize;
  }

  static String generateFileId(String url) {
    final hash = crypto_pkg.sha256.convert(utf8.encode(url));
    return hash.toString().substring(0, 32);
  }
}
