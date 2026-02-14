class VaultChunkMetadata {
  final String chunkId;
  final int chunkIndex;
  final DateTime startTimestamp;
  final DateTime endTimestamp;
  final int messageCount;
  final int compressedSize;
  final String checksum;
  final String storagePath;
  final DateTime uploadedAt;

  VaultChunkMetadata({
    required this.chunkId,
    required this.chunkIndex,
    required this.startTimestamp,
    required this.endTimestamp,
    required this.messageCount,
    required this.compressedSize,
    required this.checksum,
    required this.storagePath,
    required this.uploadedAt,
  });

  Map<String, dynamic> toFirestore() => {
        'chunkId': chunkId,
        'chunkIndex': chunkIndex,
        'startTimestamp': startTimestamp.millisecondsSinceEpoch,
        'endTimestamp': endTimestamp.millisecondsSinceEpoch,
        'messageCount': messageCount,
        'compressedSize': compressedSize,
        'checksum': checksum,
        'storagePath': storagePath,
        'uploadedAt': uploadedAt.millisecondsSinceEpoch,
      };

  factory VaultChunkMetadata.fromFirestore(Map<String, dynamic> data) {
    return VaultChunkMetadata(
      chunkId: data['chunkId'] as String,
      chunkIndex: data['chunkIndex'] as int,
      startTimestamp:
          DateTime.fromMillisecondsSinceEpoch(data['startTimestamp'] as int),
      endTimestamp:
          DateTime.fromMillisecondsSinceEpoch(data['endTimestamp'] as int),
      messageCount: data['messageCount'] as int,
      compressedSize: data['compressedSize'] as int,
      checksum: data['checksum'] as String,
      storagePath: data['storagePath'] as String,
      uploadedAt:
          DateTime.fromMillisecondsSinceEpoch(data['uploadedAt'] as int),
    );
  }
}

class VaultMediaMetadata {
  final String mediaId;
  final String storagePath;
  final DateTime uploadedAt;
  final DateTime? expireAt;
  final int sizeBytes;

  VaultMediaMetadata({
    required this.mediaId,
    required this.storagePath,
    required this.uploadedAt,
    this.expireAt,
    required this.sizeBytes,
  });

  Map<String, dynamic> toFirestore() => {
        'mediaId': mediaId,
        'storagePath': storagePath,
        'uploadedAt': uploadedAt.millisecondsSinceEpoch,
        'expireAt': expireAt?.millisecondsSinceEpoch,
        'sizeBytes': sizeBytes,
      };

  factory VaultMediaMetadata.fromFirestore(Map<String, dynamic> data) {
    return VaultMediaMetadata(
      mediaId: data['mediaId'] as String,
      storagePath: data['storagePath'] as String,
      uploadedAt:
          DateTime.fromMillisecondsSinceEpoch(data['uploadedAt'] as int),
      expireAt: data['expireAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['expireAt'] as int)
          : null,
      sizeBytes: data['sizeBytes'] as int,
    );
  }
}
