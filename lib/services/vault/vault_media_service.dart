import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../models/vault/vault_metadata.dart';

class VaultMediaService {
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  static const int thumbnailInlineLimit = 100 * 1024; // 100KB

  VaultMediaService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  Future<VaultMediaMetadata> uploadMediaToVault({
    required String userId,
    required String mediaId,
    required Uint8List encryptedBytes,
    DateTime? expireAt,
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

    final metadata = VaultMediaMetadata(
      mediaId: mediaId,
      storagePath: storagePath,
      uploadedAt: DateTime.now(),
      expireAt: expireAt,
      sizeBytes: encryptedBytes.length,
    );

    await _db
        .collection('vaults')
        .doc(userId)
        .collection('media')
        .doc(mediaId)
        .set(metadata.toFirestore());

    return metadata;
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
