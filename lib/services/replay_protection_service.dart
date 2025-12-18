import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReplayProtectionService {
  static const Duration _nonceExpiry = Duration(hours: 1);
  static const Duration _clockSkewTolerance = Duration(minutes: 2);

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final String _userId;

  ReplayProtectionService({
    required String userId,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _userId = userId,
        _db = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

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

  Future<ServerValidationResult> validateMessageServerSide({
    required String messageId,
    required String conversationId,
    required String recipientId,
    required int sequenceNumber,
    required DateTime timestamp,
  }) async {
    try {
      // Ensure we have a valid auth token before calling the function
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return ServerValidationResult(
          valid: false,
          error: 'Not authenticated. Please sign in again.',
        );
      }

      // Force token refresh to ensure we have a valid token
      try {
        await user.getIdToken(true);
      } catch (e) {
        return ServerValidationResult(
          valid: false,
          error: 'Session expired. Please sign in again.',
        );
      }

      final callable = _functions.httpsCallable('validateMessageSend');
      final result = await callable.call({
        'messageId': messageId,
        'conversationId': conversationId,
        'recipientId': recipientId,
        'sequenceNumber': sequenceNumber,
        'timestamp': timestamp.millisecondsSinceEpoch,
      });

      final data = result.data as Map<String, dynamic>;
      return ServerValidationResult(
        valid: data['valid'] as bool? ?? false,
        token: data['token'] as String?,
        error: data['error'] as String?,
        retryAfterMs: data['retryAfterMs'] as int?,
        remainingMinute: data['remainingMinute'] as int?,
        remainingHour: data['remainingHour'] as int?,
      );
    } on FirebaseFunctionsException catch (e) {
      // Handle specific auth errors
      if (e.code == 'unauthenticated') {
        return ServerValidationResult(
          valid: false,
          error: 'Session expired. Please sign out and sign back in.',
        );
      }
      return ServerValidationResult(
        valid: false,
        error: e.message ?? 'Validation failed',
      );
    }
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

class ServerValidationResult {
  final bool valid;
  final String? token;
  final String? error;
  final int? retryAfterMs;
  final int? remainingMinute;
  final int? remainingHour;

  ServerValidationResult({
    required this.valid,
    this.token,
    this.error,
    this.retryAfterMs,
    this.remainingMinute,
    this.remainingHour,
  });

  Duration get retryAfter =>
      retryAfterMs != null ? Duration(milliseconds: retryAfterMs!) : Duration.zero;

  bool get isRateLimited => retryAfterMs != null && retryAfterMs! > 0;
}
