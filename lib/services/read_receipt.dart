import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class ReadReceiptService {
  final FirebaseFirestore _db;
  final String conversationId;
  final String currentUserId;

  final Set<String> _pendingMessageIds = {};
  Timer? _debounceTimer;
  bool _isProcessing = false;

  static const _debounceDelay = Duration(milliseconds: 500);
  static const _maxBatchSize = 500;

  ReadReceiptService({
    required this.conversationId,
    required this.currentUserId,
    FirebaseFirestore? firestore,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _messagesRef =>
      _db.collection('conversations').doc(conversationId).collection('messages');

  void markAsRead(String messageId) {
    _pendingMessageIds.add(messageId);
    _scheduleFlush();
  }

  void markMultipleAsRead(List<String> messageIds) {
    _pendingMessageIds.addAll(messageIds);
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, _flush);
  }

  Future<void> _flush() async {
    if (_pendingMessageIds.isEmpty || _isProcessing) return;

    _isProcessing = true;
    final idsToProcess = _pendingMessageIds.toList();
    _pendingMessageIds.clear();

    try {
      for (var i = 0; i < idsToProcess.length; i += _maxBatchSize) {
        final batchIds = idsToProcess.skip(i).take(_maxBatchSize).toList();
        await _processBatch(batchIds);
      }

      await _db.collection('conversations').doc(conversationId).update({
        'unreadCount.$currentUserId': 0,
      });
    } finally {
      _isProcessing = false;
      if (_pendingMessageIds.isNotEmpty) {
        _scheduleFlush();
      }
    }
  }

  Future<void> _processBatch(List<String> messageIds) async {
    final batch = _db.batch();
    final timestamp = FieldValue.serverTimestamp();

    for (final id in messageIds) {
      batch.update(_messagesRef.doc(id), {
        'status': 'read',
        'readAt': timestamp,
      });
    }

    await batch.commit();
  }

  Future<void> markAllUnreadAsRead() async {
    final unread = await _messagesRef
        .where('recipientId', isEqualTo: currentUserId)
        .where('status', whereIn: ['sent', 'delivered'])
        .get();

    if (unread.docs.isEmpty) return;

    markMultipleAsRead(unread.docs.map((d) => d.id).toList());
    await flushNow();
  }

  Future<void> flushNow() async {
    _debounceTimer?.cancel();
    await _flush();
  }

  void dispose() {
    _debounceTimer?.cancel();
    if (_pendingMessageIds.isNotEmpty) {
      _flush();
    }
  }
}
