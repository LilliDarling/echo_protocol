import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/crypto/sealed_envelope.dart';

class InboxMessage {
  final String id;
  final SealedEnvelope? envelope;
  final String? senderPayload;
  final DateTime deliveredAt;
  final bool isOutgoing;
  final String? recipientId;

  InboxMessage({
    required this.id,
    this.envelope,
    this.senderPayload,
    required this.deliveredAt,
    required this.isOutgoing,
    this.recipientId,
  });

  factory InboxMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final isOutgoing = data['isOutgoing'] as bool? ?? false;

    SealedEnvelope? envelope;
    String? senderPayload;

    if (isOutgoing) {
      senderPayload = data['senderPayload'] as String?;
    } else {
      final envelopeData = data['sealedEnvelope'] as Map<String, dynamic>;
      envelope = SealedEnvelope.fromJson({
        'recipientId': '',
        ...envelopeData,
      });
    }

    return InboxMessage(
      id: doc.id,
      envelope: envelope,
      senderPayload: senderPayload,
      deliveredAt: (data['deliveredAt'] as Timestamp).toDate(),
      isOutgoing: isOutgoing,
      recipientId: data['recipientId'] as String?,
    );
  }
}

class InboxListener {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  StreamSubscription? _subscription;
  final _controller = StreamController<InboxMessage>.broadcast();
  bool _isListening = false;

  InboxListener({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  Stream<InboxMessage> get messages => _controller.stream;
  bool get isListening => _isListening;

  String? get _userId => _auth.currentUser?.uid;

  void start() {
    if (_isListening || _userId == null) return;

    _isListening = true;
    final inboxRef = _db
        .collection('inboxes')
        .doc(_userId)
        .collection('pending')
        .orderBy('deliveredAt', descending: false);

    _subscription = inboxRef.snapshots().listen(
      (snapshot) {
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            try {
              final message = InboxMessage.fromFirestore(change.doc);
              _controller.add(message);
            } catch (e) {
              // Skip malformed messages
            }
          }
        }
      },
      onError: (error) {
        _controller.addError(error);
      },
    );
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _isListening = false;
  }

  Future<void> deleteMessage(String messageId) async {
    if (_userId == null) return;

    await _db
        .collection('inboxes')
        .doc(_userId)
        .collection('pending')
        .doc(messageId)
        .delete();
  }

  Future<List<InboxMessage>> fetchPending() async {
    if (_userId == null) return [];

    final snapshot = await _db
        .collection('inboxes')
        .doc(_userId)
        .collection('pending')
        .orderBy('deliveredAt', descending: false)
        .get();

    return snapshot.docs
        .map((doc) {
          try {
            return InboxMessage.fromFirestore(doc);
          } catch (_) {
            return null;
          }
        })
        .whereType<InboxMessage>()
        .toList();
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
