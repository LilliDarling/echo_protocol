import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:http/http.dart' as http;
import '../../utils/security.dart';

class MediaEncryptionService {
  static const String _cacheSubdir = 'decrypted_media';

  final AesGcm _aesGcm = AesGcm.with256bits();

  MediaEncryptionService();

  Future<({Uint8List encrypted, String mediaId, Uint8List mediaKey})> encryptMedia({
    required Uint8List plainBytes,
    required String recipientId,
    required String senderId,
  }) async {
    // Generate a random media key for each piece of media
    final mediaKey = SecurityUtils.generateSecureRandomBytes(32);
    final mediaId = _generateMediaId(DateTime.now().millisecondsSinceEpoch);

    final encrypted = await _aesEncrypt(mediaKey, plainBytes, mediaId);

    // Return the key so it can be included in the encrypted message
    return (encrypted: encrypted, mediaId: mediaId, mediaKey: Uint8List.fromList(mediaKey));
  }

  Future<Uint8List> decryptMedia({
    required Uint8List encryptedBytes,
    required String mediaId,
    required Uint8List mediaKey,
  }) async {
    return _aesDecrypt(mediaKey, encryptedBytes, mediaId);
  }

  Future<void> deleteMedia({
    required String mediaId,
  }) async {
    await _deleteCachedMedia(mediaId);
  }

  Future<String> downloadAndDecrypt({
    required String encryptedUrl,
    required String mediaId,
    required Uint8List mediaKey,
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
      mediaKey: mediaKey,
    );

    final file = File(cachedPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(decryptedBytes);

    return cachedPath;
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
