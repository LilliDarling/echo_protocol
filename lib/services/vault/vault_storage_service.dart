import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../models/vault/vault_chunk.dart';
import '../../models/vault/vault_metadata.dart';
import 'vault_encryption_service.dart';

class VaultStorageService {
  final FirebaseFirestore _db;
  final FirebaseStorage _firebaseStorage;
  final VaultEncryptionService _encryption;

  VaultStorageService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    VaultEncryptionService? encryption,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _firebaseStorage = storage ?? FirebaseStorage.instance,
        _encryption = encryption ?? VaultEncryptionService();

  Future<VaultChunkMetadata> uploadChunk({
    required String userId,
    required VaultChunk chunk,
  }) async {
    final storagePath = 'vault_chunks/$userId/${chunk.chunkId}.bin';
    final docRef = _db
        .collection('vaults')
        .doc(userId)
        .collection('chunks')
        .doc(chunk.chunkId);

    // Check if this chunk was already uploaded (crash recovery / retry)
    final existingDoc = await docRef.get();
    if (existingDoc.exists) {
      return VaultChunkMetadata.fromFirestore(existingDoc.data()!);
    }

    // Clean up any orphaned Storage blob from a prior failed attempt
    try {
      await _firebaseStorage.ref().child(storagePath).delete();
    } catch (_) {
      // Expected — no orphan exists on first upload
    }

    final plaintext = chunk.serialize();
    final encrypted = await _encryption.encryptChunk(
      plaintext: plaintext,
      chunkId: chunk.chunkId,
    );

    final ref = _firebaseStorage.ref().child(storagePath);
    await ref.putData(
      encrypted,
      SettableMetadata(
        contentType: 'application/octet-stream',
        cacheControl: 'private, max-age=0',
      ),
    );

    final checksum = VaultEncryptionService.computeChecksum(encrypted);

    final metadata = VaultChunkMetadata(
      chunkId: chunk.chunkId,
      chunkIndex: chunk.chunkIndex,
      startTimestamp: chunk.startTimestamp,
      endTimestamp: chunk.endTimestamp,
      messageCount: chunk.messageCount,
      compressedSize: encrypted.length,
      checksum: checksum,
      storagePath: storagePath,
      uploadedAt: DateTime.now(),
    );

    await docRef.set(metadata.toFirestore());

    return metadata;
  }

  Future<VaultChunk> downloadChunk({
    required String userId,
    required VaultChunkMetadata metadata,
  }) async {
    final ref = _firebaseStorage.ref().child(metadata.storagePath);
    final data = await ref.getData();
    if (data == null) throw Exception('Vault chunk not found in storage');

    // Verify encrypted blob integrity before decryption
    final checksum = VaultEncryptionService.computeChecksum(data);
    if (checksum != metadata.checksum) {
      throw Exception('Vault chunk integrity check failed');
    }

    final decrypted = await _encryption.decryptChunk(
      encrypted: data,
      chunkId: metadata.chunkId,
    );

    return VaultChunk.deserialize(decrypted);
  }

  static const int _listChunksPageSize = 500;

  Future<List<VaultChunkMetadata>> listChunks({
    required String userId,
    DateTime? afterTimestamp,
  }) async {
    final results = <VaultChunkMetadata>[];
    DocumentSnapshot? lastDoc;

    while (true) {
      Query<Map<String, dynamic>> query = _db
          .collection('vaults')
          .doc(userId)
          .collection('chunks')
          .orderBy('uploadedAt')
          .limit(_listChunksPageSize);

      if (afterTimestamp != null) {
        query = query.where(
          'uploadedAt',
          isGreaterThan: afterTimestamp.millisecondsSinceEpoch,
        );
      }

      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) break;

      results.addAll(
        snapshot.docs.map((doc) => VaultChunkMetadata.fromFirestore(doc.data())),
      );

      if (snapshot.docs.length < _listChunksPageSize) break;
      lastDoc = snapshot.docs.last;
    }

    return results;
  }

  Future<int> getLatestChunkIndex(String userId) async {
    final snapshot = await _db
        .collection('vaults')
        .doc(userId)
        .collection('chunks')
        .orderBy('chunkIndex', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return -1;
    return (snapshot.docs.first.data()['chunkIndex'] as int?) ?? -1;
  }
}
