import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

class VaultMediaService {
  final FirebaseStorage _storage;

  static const int thumbnailInlineLimit = 100 * 1024; // 100KB

  VaultMediaService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  Future<String> uploadMediaToVault({
    required String userId,
    required String mediaId,
    required Uint8List encryptedBytes,
  }) async {
    final storagePath = 'vaults/$userId/media/$mediaId';
    final ref = _storage.ref().child(storagePath);
    await ref.putData(
      encryptedBytes,
      SettableMetadata(
        contentType: 'application/octet-stream',
        cacheControl: 'private, max-age=0',
      ),
    );
    return storagePath;
  }

  Future<Uint8List?> downloadMediaFromVault({
    required String userId,
    required String mediaId,
  }) async {
    final storagePath = 'vaults/$userId/media/$mediaId';
    final ref = _storage.ref().child(storagePath);
    return ref.getData();
  }

  static bool shouldInlineThumbnail(int sizeBytes) {
    return sizeBytes <= thumbnailInlineLimit;
  }
}
