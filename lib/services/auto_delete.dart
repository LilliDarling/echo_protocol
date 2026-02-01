import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class AutoDeleteService {
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  static const int _batchSize = 100;

  AutoDeleteService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  Future<int> deleteOldMessages({
    required String conversationId,
    required String userId,
    required int autoDeleteDays,
  }) async {
    if (autoDeleteDays <= 0) return 0;

    final cutoff = DateTime.now().subtract(Duration(days: autoDeleteDays));
    final cutoffTimestamp = Timestamp.fromDate(cutoff);

    final messagesRef = _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages');

    int totalDeleted = 0;

    while (true) {
      final snapshot = await messagesRef
          .where('timestamp', isLessThan: cutoffTimestamp)
          .limit(_batchSize)
          .get();

      if (snapshot.docs.isEmpty) break;

      final batch = _db.batch();
      final mediaUrls = <String>[];

      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);

        final data = doc.data();
        final metadata = data['metadata'] as Map<String, dynamic>?;
        if (metadata != null) {
          final fileUrl = metadata['fileUrl'] as String?;
          final thumbnailUrl = metadata['thumbnailUrl'] as String?;
          if (fileUrl != null && fileUrl.isNotEmpty) mediaUrls.add(fileUrl);
          if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) mediaUrls.add(thumbnailUrl);
        }
      }

      await batch.commit();
      totalDeleted += snapshot.docs.length;

      await _deleteMedia(mediaUrls);

      if (snapshot.docs.length < _batchSize) break;
    }

    return totalDeleted;
  }

  Future<void> _deleteMedia(List<String> urls) async {
    for (final url in urls) {
      try {
        await _storage.refFromURL(url).delete();
      } catch (_) {}
    }
  }
}
