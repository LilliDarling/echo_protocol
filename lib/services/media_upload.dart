import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'media_encryption.dart';

/// Service for uploading media files to Firebase Storage
/// Supports optional end-to-end encryption of media files
class MediaUploadService {
  final FirebaseStorage _storage;
  final MediaEncryptionService? _encryptionService;

  MediaUploadService({
    FirebaseStorage? storage,
    MediaEncryptionService? encryptionService,
  })  : _storage = storage ?? FirebaseStorage.instance,
        _encryptionService = encryptionService;

  /// Whether encryption is enabled for this service instance
  bool get isEncryptionEnabled => _encryptionService != null;

  /// Upload an image with thumbnail generation
  /// If encryption service is provided, encrypts file before upload
  Future<Map<String, String>> uploadImage({
    required XFile file,
    required String userId,
  }) async {
    final fileBytes = await file.readAsBytes();
    final hashedFilename = _generateHashedFilename(fileBytes, userId);

    // Generate thumbnail before encryption (for preview display)
    final thumbnailBytes = await _generateImageThumbnail(fileBytes);
    final thumbnailFilename = '${hashedFilename}_thumb';

    // Encrypt files if encryption service is available
    final uploadBytes = _encryptionService != null
        ? _encryptionService.encryptFileBytes(Uint8List.fromList(fileBytes))
        : Uint8List.fromList(fileBytes);
    final uploadThumbnailBytes = _encryptionService != null
        ? _encryptionService.encryptFileBytes(thumbnailBytes)
        : thumbnailBytes;

    // Use application/octet-stream for encrypted files to indicate binary data
    final contentType = _encryptionService != null
        ? 'application/octet-stream'
        : 'image/jpeg';

    // Upload full image
    final imageUrl = await _uploadToStorage(
      bytes: uploadBytes,
      path: 'media/images/$userId/$hashedFilename',
      contentType: contentType,
    );

    // Upload thumbnail
    final thumbnailUrl = await _uploadToStorage(
      bytes: uploadThumbnailBytes,
      path: 'media/thumbnails/$userId/$thumbnailFilename',
      contentType: contentType,
    );

    return {
      'fileUrl': imageUrl,
      'thumbnailUrl': thumbnailUrl,
      'fileName': hashedFilename,
      'isEncrypted': _encryptionService != null ? 'true' : 'false',
    };
  }

  /// Upload a video with thumbnail extraction
  /// If encryption service is provided, encrypts file before upload
  Future<Map<String, String>> uploadVideo({
    required XFile file,
    required String userId,
  }) async {
    final fileBytes = await file.readAsBytes();
    final hashedFilename = _generateHashedFilename(Uint8List.fromList(fileBytes), userId);

    // Extract video thumbnail before encryption (for preview display)
    final thumbnailPath = await _extractVideoThumbnail(file.path);
    final thumbnailBytes = thumbnailPath != null
        ? await File(thumbnailPath).readAsBytes()
        : null;
    final thumbnailFilename = '${hashedFilename}_thumb';

    // Encrypt video if encryption service is available
    final uploadBytes = _encryptionService != null
        ? _encryptionService.encryptFileBytes(Uint8List.fromList(fileBytes))
        : Uint8List.fromList(fileBytes);

    // Use application/octet-stream for encrypted files
    final videoContentType = _encryptionService != null
        ? 'application/octet-stream'
        : 'video/mp4';
    final thumbnailContentType = _encryptionService != null
        ? 'application/octet-stream'
        : 'image/jpeg';

    // Upload video
    final videoUrl = await _uploadToStorage(
      bytes: uploadBytes,
      path: 'media/videos/$userId/$hashedFilename',
      contentType: videoContentType,
    );

    // Upload thumbnail if available
    String? thumbnailUrl;
    if (thumbnailBytes != null) {
      final uploadThumbnailBytes = _encryptionService != null
          ? _encryptionService.encryptFileBytes(Uint8List.fromList(thumbnailBytes))
          : Uint8List.fromList(thumbnailBytes);

      thumbnailUrl = await _uploadToStorage(
        bytes: uploadThumbnailBytes,
        path: 'media/thumbnails/$userId/$thumbnailFilename',
        contentType: thumbnailContentType,
      );
    }

    // Clean up temporary thumbnail
    if (thumbnailPath != null) {
      try {
        await File(thumbnailPath).delete();
      } catch (_) {}
    }

    return {
      'fileUrl': videoUrl,
      'thumbnailUrl': thumbnailUrl ?? '',
      'fileName': hashedFilename,
      'isEncrypted': _encryptionService != null ? 'true' : 'false',
    };
  }

  /// Generate hashed filename using SHA-256 for privacy
  String _generateHashedFilename(Uint8List bytes, String userId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final input = '$userId:$timestamp:${bytes.length}';
    final hash = sha256.convert(utf8.encode(input));
    return hash.toString();
  }

  /// Generate thumbnail for image
  Future<Uint8List> _generateImageThumbnail(Uint8List imageBytes) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/temp_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(imageBytes);

      final compressed = await FlutterImageCompress.compressWithFile(
        tempFile.path,
        minWidth: 300,
        minHeight: 300,
        quality: 70,
      );

      // Clean up temp file
      try {
        await tempFile.delete();
      } catch (_) {}

      return compressed ?? imageBytes;
    } catch (e) {
      // Fallback: return original bytes if compression fails
      return imageBytes;
    }
  }

  /// Extract thumbnail from video
  Future<String?> _extractVideoThumbnail(String videoPath) async {
    try {
      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: (await getTemporaryDirectory()).path,
        imageFormat: ImageFormat.JPEG,
        maxHeight: 300,
        maxWidth: 300,
        quality: 70,
      );
      return thumbnailPath;
    } catch (e) {
      return null;
    }
  }

  /// Upload bytes to Firebase Storage
  Future<String> _uploadToStorage({
    required Uint8List bytes,
    required String path,
    required String contentType,
  }) async {
    try {
      final ref = _storage.ref().child(path);

      final metadata = SettableMetadata(
        contentType: contentType,
        cacheControl: 'public, max-age=31536000',
      );

      await ref.putData(bytes, metadata);
      final downloadUrl = await ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      throw Exception('Failed to upload: $e');
    }
  }

  /// Delete a file from storage
  Future<void> deleteFile(String fileUrl) async {
    try {
      final ref = _storage.refFromURL(fileUrl);
      await ref.delete();
    } catch (e) {
      // Silently fail - file might already be deleted
    }
  }

  /// Get file size estimate
  static Future<int> getFileSize(XFile file) async {
    final bytes = await file.readAsBytes();
    return bytes.length;
  }

  /// Validate file size (max 50MB)
  static bool isFileSizeValid(int bytes) {
    const maxSize = 50 * 1024 * 1024; // 50MB
    return bytes <= maxSize;
  }

  /// Get file extension
  static String getFileExtension(String path) {
    return path.split('.').last.toLowerCase();
  }

  /// Validate image format
  static bool isValidImageFormat(String extension) {
    const validFormats = ['jpg', 'jpeg', 'png', 'webp', 'heic'];
    return validFormats.contains(extension.toLowerCase());
  }

  /// Validate video format
  static bool isValidVideoFormat(String extension) {
    const validFormats = ['mp4', 'mov', 'avi', 'mkv'];
    return validFormats.contains(extension.toLowerCase());
  }
}
