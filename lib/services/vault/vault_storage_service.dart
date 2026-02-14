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
    final plaintext = chunk.serialize();
    final encrypted = await _encryption.encryptChunk(
      plaintext: plaintext,
      chunkId: chunk.chunkId,
    );

    final storagePath = 'vault_chunks/$userId/${chunk.chunkId}.bin';

    final ref = _firebaseStorage.ref().child(storagePath);
    await ref.putData(
      encrypted,
      SettableMetadata(
        contentType: 'application/octet-stream',
        cacheControl: 'private, max-age=0',
      ),
    );

    final metadata = VaultChunkMetadata(
      chunkId: chunk.chunkId,
      chunkIndex: chunk.chunkIndex,
      startTimestamp: chunk.startTimestamp,
      endTimestamp: chunk.endTimestamp,
      messageCount: chunk.messageCount,
      compressedSize: encrypted.length,
      checksum: chunk.checksum,
      storagePath: storagePath,
      uploadedAt: DateTime.now(),
    );

    await _db
        .collection('vaults')
        .doc(userId)
        .collection('chunks')
        .doc(chunk.chunkId)
        .set(metadata.toFirestore());

    return metadata;
  }

  Future<VaultChunk> downloadChunk({
    required String userId,
    required VaultChunkMetadata metadata,
  }) async {
    final ref = _firebaseStorage.ref().child(metadata.storagePath);
    final data = await ref.getData();
    if (data == null) throw Exception('Vault chunk not found in storage');

    final decrypted = await _encryption.decryptChunk(
      encrypted: data,
      chunkId: metadata.chunkId,
    );

    final chunk = VaultChunk.deserialize(decrypted);

    if (chunk.checksum != metadata.checksum) {
      throw Exception('Vault chunk integrity check failed');
    }

    return chunk;
  }

  Future<List<VaultChunkMetadata>> listChunks({
    required String userId,
    int? afterIndex,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection('vaults')
        .doc(userId)
        .collection('chunks')
        .orderBy('chunkIndex');

    if (afterIndex != null) {
      query = query.where('chunkIndex', isGreaterThan: afterIndex);
    }

    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => VaultChunkMetadata.fromFirestore(doc.data()))
        .toList();
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
