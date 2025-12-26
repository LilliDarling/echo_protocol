import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'encryption.dart';

/// Service for encrypting and decrypting media files
/// Uses the existing EncryptionService for cryptographic operations (DRY)
class MediaEncryptionService {
  final EncryptionService _encryptionService;

  /// Cache directory for decrypted media
  static const String _cacheSubdir = 'decrypted_media';

  MediaEncryptionService({
    required EncryptionService encryptionService,
  }) : _encryptionService = encryptionService;

  /// Encrypt file bytes before upload
  /// Returns encrypted bytes ready for storage
  Uint8List encryptFileBytes(Uint8List plainBytes) {
    return _encryptionService.encryptFile(plainBytes);
  }

  /// Decrypt file bytes after download
  /// Returns decrypted bytes
  Uint8List decryptFileBytes(Uint8List encryptedBytes) {
    return _encryptionService.decryptFile(encryptedBytes);
  }

  /// Download encrypted media from URL, decrypt it, and save to local cache
  /// Returns path to decrypted file for display
  Future<String> getDecryptedMedia({
    required String encryptedUrl,
    required String fileId,
    required bool isVideo,
  }) async {
    // Check if already cached
    final cachedPath = await _getCachedFilePath(fileId, isVideo);
    if (await File(cachedPath).exists()) {
      return cachedPath;
    }

    // Download encrypted file
    final response = await http.get(Uri.parse(encryptedUrl));
    if (response.statusCode != 200) {
      throw Exception('Failed to download media: ${response.statusCode}');
    }

    // Decrypt
    final encryptedBytes = Uint8List.fromList(response.bodyBytes);
    final decryptedBytes = decryptFileBytes(encryptedBytes);

    // Save to cache
    final file = File(cachedPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(decryptedBytes);

    return cachedPath;
  }

  /// Get the local cache path for a file
  Future<String> _getCachedFilePath(String fileId, bool isVideo) async {
    final cacheDir = await getTemporaryDirectory();
    final extension = isVideo ? 'mp4' : 'jpg';
    return '${cacheDir.path}/$_cacheSubdir/$fileId.$extension';
  }

  /// Generate a unique file ID from URL for caching
  static String generateFileId(String url) {
    final hash = sha256.convert(utf8.encode(url));
    return hash.toString().substring(0, 32);
  }

  /// Clear all cached decrypted media
  Future<void> clearCache() async {
    final cacheDir = await getTemporaryDirectory();
    final mediaCache = Directory('${cacheDir.path}/$_cacheSubdir');
    if (await mediaCache.exists()) {
      await mediaCache.delete(recursive: true);
    }
  }

  /// Get cache size in bytes
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
}
