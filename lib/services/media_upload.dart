import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'crypto/media_encryption.dart';

class MediaUploadService {
  final FirebaseStorage _storage;
  final MediaEncryptionService? _encryptionService;
  final String? _senderId;
  final String? _recipientId;

  MediaUploadService({
    FirebaseStorage? storage,
    MediaEncryptionService? encryptionService,
    String? senderId,
    String? recipientId,
  })  : _storage = storage ?? FirebaseStorage.instance,
        _encryptionService = encryptionService,
        _senderId = senderId,
        _recipientId = recipientId;

  bool get isEncryptionEnabled =>
      _encryptionService != null && _senderId != null && _recipientId != null;

  Future<Map<String, String>> uploadImage({
    required XFile file,
    required String userId,
  }) async {
    final rawBytes = await file.readAsBytes();
    final fileBytes = await _stripExifData(rawBytes);
    final hashedFilename = _generateHashedFilename(fileBytes, userId);

    final thumbnailBytes = await _generateImageThumbnail(fileBytes);
    final thumbnailFilename = '${hashedFilename}_thumb';

    Uint8List uploadBytes;
    Uint8List uploadThumbnailBytes;
    String? mediaId;
    String? thumbMediaId;
    String? mediaKey;
    String? thumbMediaKey;

    if (isEncryptionEnabled) {
      final result = await _encryptionService!.encryptMedia(
        plainBytes: Uint8List.fromList(fileBytes),
        recipientId: _recipientId!,
        senderId: _senderId!,
      );
      uploadBytes = result.encrypted;
      mediaId = result.mediaId;
      mediaKey = base64Encode(result.mediaKey);

      final thumbResult = await _encryptionService.encryptMedia(
        plainBytes: thumbnailBytes,
        recipientId: _recipientId,
        senderId: _senderId,
      );
      uploadThumbnailBytes = thumbResult.encrypted;
      thumbMediaId = thumbResult.mediaId;
      thumbMediaKey = base64Encode(thumbResult.mediaKey);
    } else {
      uploadBytes = Uint8List.fromList(fileBytes);
      uploadThumbnailBytes = thumbnailBytes;
    }

    final contentType = isEncryptionEnabled ? 'application/octet-stream' : 'image/jpeg';

    final imageUrl = await _uploadToStorage(
      bytes: uploadBytes,
      path: 'media/images/$userId/$hashedFilename',
      contentType: contentType,
    );

    final thumbnailUrl = await _uploadToStorage(
      bytes: uploadThumbnailBytes,
      path: 'media/thumbnails/$userId/$thumbnailFilename',
      contentType: contentType,
    );

    return {
      'fileUrl': imageUrl,
      'thumbnailUrl': thumbnailUrl,
      'fileName': hashedFilename,
      'isEncrypted': isEncryptionEnabled ? 'true' : 'false',
      if (mediaId != null) 'mediaId': mediaId,
      if (thumbMediaId != null) 'thumbMediaId': thumbMediaId,
      if (mediaKey != null) 'mediaKey': mediaKey,
      if (thumbMediaKey != null) 'thumbMediaKey': thumbMediaKey,
    };
  }

  Future<Map<String, String>> uploadVideo({
    required XFile file,
    required String userId,
  }) async {
    final fileBytes = await file.readAsBytes();
    final hashedFilename = _generateHashedFilename(Uint8List.fromList(fileBytes), userId);

    final thumbnailPath = await _extractVideoThumbnail(file.path);
    final thumbnailBytes = thumbnailPath != null
        ? await File(thumbnailPath).readAsBytes()
        : null;
    final thumbnailFilename = '${hashedFilename}_thumb';

    Uint8List uploadBytes;
    String? mediaId;
    String? thumbMediaId;
    String? mediaKey;
    String? thumbMediaKey;

    if (isEncryptionEnabled) {
      final result = await _encryptionService!.encryptMedia(
        plainBytes: Uint8List.fromList(fileBytes),
        recipientId: _recipientId!,
        senderId: _senderId!,
      );
      uploadBytes = result.encrypted;
      mediaId = result.mediaId;
      mediaKey = base64Encode(result.mediaKey);
    } else {
      uploadBytes = Uint8List.fromList(fileBytes);
    }

    final videoContentType = isEncryptionEnabled ? 'application/octet-stream' : 'video/mp4';
    final thumbnailContentType = isEncryptionEnabled ? 'application/octet-stream' : 'image/jpeg';

    final videoUrl = await _uploadToStorage(
      bytes: uploadBytes,
      path: 'media/videos/$userId/$hashedFilename',
      contentType: videoContentType,
    );

    String? thumbnailUrl;
    if (thumbnailBytes != null) {
      Uint8List uploadThumbnailBytes;

      if (isEncryptionEnabled) {
        final thumbResult = await _encryptionService!.encryptMedia(
          plainBytes: Uint8List.fromList(thumbnailBytes),
          recipientId: _recipientId!,
          senderId: _senderId!,
        );
        uploadThumbnailBytes = thumbResult.encrypted;
        thumbMediaId = thumbResult.mediaId;
        thumbMediaKey = base64Encode(thumbResult.mediaKey);
      } else {
        uploadThumbnailBytes = Uint8List.fromList(thumbnailBytes);
      }

      thumbnailUrl = await _uploadToStorage(
        bytes: uploadThumbnailBytes,
        path: 'media/thumbnails/$userId/$thumbnailFilename',
        contentType: thumbnailContentType,
      );
    }

    if (thumbnailPath != null) {
      try {
        final thumbFile = File(thumbnailPath);
        if (await thumbFile.exists()) {
          await thumbFile.writeAsBytes(List.filled(thumbFile.lengthSync(), 0));
          await thumbFile.delete();
        }
      } catch (_) {}
    }

    return {
      'fileUrl': videoUrl,
      'thumbnailUrl': thumbnailUrl ?? '',
      'fileName': hashedFilename,
      'isEncrypted': isEncryptionEnabled ? 'true' : 'false',
      if (mediaId != null) 'mediaId': mediaId,
      if (thumbMediaId != null) 'thumbMediaId': thumbMediaId,
      if (mediaKey != null) 'mediaKey': mediaKey,
      if (thumbMediaKey != null) 'thumbMediaKey': thumbMediaKey,
    };
  }

  String _generateHashedFilename(Uint8List bytes, String userId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final input = '$userId:$timestamp:${bytes.length}';
    final hash = sha256.convert(utf8.encode(input));
    return hash.toString();
  }

  Future<Uint8List> _stripExifData(Uint8List imageBytes) async {
    try {
      final result = await FlutterImageCompress.compressWithList(
        imageBytes,
        quality: 95,
        keepExif: false,
      );
      return result;
    } catch (_) {
      return imageBytes;
    }
  }

  Future<Uint8List> _generateImageThumbnail(Uint8List imageBytes) async {
    File? tempFile;
    try {
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/.temp_${DateTime.now().millisecondsSinceEpoch}.jpg';
      tempFile = File(tempPath);
      await tempFile.writeAsBytes(imageBytes);

      final compressed = await FlutterImageCompress.compressWithFile(
        tempFile.path,
        minWidth: 300,
        minHeight: 300,
        quality: 70,
      );

      return compressed ?? imageBytes;
    } catch (e) {
      return imageBytes;
    } finally {
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.writeAsBytes(List.filled(tempFile.lengthSync(), 0));
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }

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

  Future<void> deleteFile(String fileUrl) async {
    final ref = _storage.refFromURL(fileUrl);
    await ref.delete().catchError((_) {});
  }

  static Future<int> getFileSize(XFile file) async {
    final bytes = await file.readAsBytes();
    return bytes.length;
  }

  static bool isFileSizeValid(int bytes) {
    const maxSize = 50 * 1024 * 1024;
    return bytes <= maxSize;
  }

  static String getFileExtension(String path) {
    return path.split('.').last.toLowerCase();
  }

  static bool isValidImageFormat(String extension) {
    const validFormats = ['jpg', 'jpeg', 'png', 'webp', 'heic'];
    return validFormats.contains(extension.toLowerCase());
  }

  static bool isValidVideoFormat(String extension) {
    const validFormats = ['mp4', 'mov', 'avi', 'mkv'];
    return validFormats.contains(extension.toLowerCase());
  }
}
