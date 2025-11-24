import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Service for uploading media files to Firebase Storage
class MediaUploadService {
  final FirebaseStorage _storage;

  MediaUploadService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  /// Upload an image with thumbnail generation
  Future<Map<String, String>> uploadImage({
    required XFile file,
    required String userId,
  }) async {
    final fileBytes = await file.readAsBytes();
    final encryptedFilename = _generateEncryptedFilename(fileBytes, userId);

    // Generate thumbnail
    final thumbnailBytes = await _generateImageThumbnail(fileBytes);
    final thumbnailFilename = '${encryptedFilename}_thumb';

    // Upload full image
    final imageUrl = await _uploadToStorage(
      bytes: fileBytes,
      path: 'media/images/$userId/$encryptedFilename',
      contentType: 'image/jpeg',
    );

    // Upload thumbnail
    final thumbnailUrl = await _uploadToStorage(
      bytes: thumbnailBytes,
      path: 'media/thumbnails/$userId/$thumbnailFilename',
      contentType: 'image/jpeg',
    );

    return {
      'fileUrl': imageUrl,
      'thumbnailUrl': thumbnailUrl,
      'fileName': encryptedFilename,
    };
  }

  /// Upload a video with thumbnail extraction
  Future<Map<String, String>> uploadVideo({
    required XFile file,
    required String userId,
  }) async {
    final fileBytes = await file.readAsBytes();
    final encryptedFilename = _generateEncryptedFilename(fileBytes, userId);

    // Extract video thumbnail
    final thumbnailPath = await _extractVideoThumbnail(file.path);
    final thumbnailBytes = thumbnailPath != null
        ? await File(thumbnailPath).readAsBytes()
        : null;
    final thumbnailFilename = '${encryptedFilename}_thumb';

    // Upload video
    final videoUrl = await _uploadToStorage(
      bytes: fileBytes,
      path: 'media/videos/$userId/$encryptedFilename',
      contentType: 'video/mp4',
    );

    // Upload thumbnail if available
    String? thumbnailUrl;
    if (thumbnailBytes != null) {
      thumbnailUrl = await _uploadToStorage(
        bytes: thumbnailBytes,
        path: 'media/thumbnails/$userId/$thumbnailFilename',
        contentType: 'image/jpeg',
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
      'fileName': encryptedFilename,
    };
  }

  /// Generate encrypted filename using SHA-256
  String _generateEncryptedFilename(Uint8List bytes, String userId) {
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
