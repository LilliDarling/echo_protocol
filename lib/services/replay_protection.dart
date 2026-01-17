import 'package:cloud_firestore/cloud_firestore.dart';

class ReplayProtectionService {
  static const Duration _nonceExpiry = Duration(hours: 1);
  static const Duration _clockSkewTolerance = Duration(minutes: 2);

  final FirebaseFirestore _db;
  final String _userId;

  ReplayProtectionService({
    required String userId,
    FirebaseFirestore? firestore,
  })  : _userId = userId,
        _db = firestore ?? FirebaseFirestore.instance;

  String _getConversationId(String userId1, String userId2) {
    final ids = [userId1, userId2]..sort();
    return ids.join('_');
  }

  CollectionReference<Map<String, dynamic>> get _noncesCollection =>
      _db.collection('users').doc(_userId).collection('seen_nonces');

  CollectionReference<Map<String, dynamic>> get _sequencesCollection =>
      _db.collection('users').doc(_userId).collection('message_sequences');

  Future<int> getLastSequenceNumber(String senderId, String recipientId) async {
    final conversationId = _getConversationId(senderId, recipientId);
    final doc = await _sequencesCollection.doc(conversationId).get();
    return doc.data()?['lastSequence'] as int? ?? 0;
  }

  Future<void> updateSequenceNumber(
    String senderId,
    String recipientId,
    int sequenceNumber,
  ) async {
    final conversationId = _getConversationId(senderId, recipientId);
    await _sequencesCollection.doc(conversationId).set({
      'lastSequence': sequenceNumber,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> isNonceValid(
    String messageId,
    DateTime timestamp,
  ) async {
    final now = DateTime.now();
    final age = now.difference(timestamp);

    if (age > _nonceExpiry) {
      return false;
    }
    if (age.isNegative && age.abs() > _clockSkewTolerance) {
      return false;
    }

    return await _db.runTransaction<bool>((transaction) async {
      final nonceRef = _noncesCollection.doc(messageId);
      final nonceDoc = await transaction.get(nonceRef);

      if (nonceDoc.exists) {
        return false;
      }

      transaction.set(nonceRef, {
        'timestamp': Timestamp.fromDate(timestamp),
        'storedAt': FieldValue.serverTimestamp(),
      });

      return true;
    });
  }

  Future<bool> validateMessage({
    required String messageId,
    required String senderId,
    required String recipientId,
    required int sequenceNumber,
    required DateTime timestamp,
  }) async {
    final now = DateTime.now();
    final age = now.difference(timestamp);

    if (age > _nonceExpiry) {
      return false;
    }
    if (age.isNegative && age.abs() > _clockSkewTolerance) {
      return false;
    }

    final conversationId = _getConversationId(senderId, recipientId);

    return await _db.runTransaction<bool>((transaction) async {
      final nonceRef = _noncesCollection.doc(messageId);
      final sequenceRef = _sequencesCollection.doc(conversationId);

      final nonceDoc = await transaction.get(nonceRef);
      final sequenceDoc = await transaction.get(sequenceRef);

      if (nonceDoc.exists) {
        return false;
      }

      final lastSeq = sequenceDoc.data()?['lastSequence'] as int? ?? 0;
      if (sequenceNumber <= lastSeq) {
        return false;
      }

      transaction.set(nonceRef, {
        'timestamp': Timestamp.fromDate(timestamp),
        'storedAt': FieldValue.serverTimestamp(),
      });

      transaction.set(sequenceRef, {
        'lastSequence': sequenceNumber,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return true;
    });
  }

  Future<int> getNextSequenceNumber(String senderId, String recipientId) async {
    final conversationId = _getConversationId(senderId, recipientId);

    return await _db.runTransaction<int>((transaction) async {
      final docRef = _sequencesCollection.doc(conversationId);
      final doc = await transaction.get(docRef);

      final lastSeq = doc.data()?['lastSequence'] as int? ?? 0;
      final nextSeq = lastSeq + 1;

      transaction.set(docRef, {
        'lastSequence': nextSeq,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return nextSeq;
    });
  }

  Future<void> resetConversation(String senderId, String recipientId) async {
    final conversationId = _getConversationId(senderId, recipientId);
    await _sequencesCollection.doc(conversationId).delete();
  }

  Future<void> cleanupExpiredNonces() async {
    final cutoff = DateTime.now().subtract(_nonceExpiry);
    final expiredDocs = await _noncesCollection
        .where('storedAt', isLessThan: Timestamp.fromDate(cutoff))
        .limit(100)
        .get();

    if (expiredDocs.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in expiredDocs.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
