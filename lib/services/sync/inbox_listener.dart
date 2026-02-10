import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/crypto/sealed_envelope.dart';

class InboxMessage {
  final String id;
  final SealedEnvelope envelope;
  final DateTime deliveredAt;

  InboxMessage({
    required this.id,
    required this.envelope,
    required this.deliveredAt,
  });

  factory InboxMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final envelopeData = data['sealedEnvelope'] as Map<String, dynamic>;
    final envelope = SealedEnvelope.fromJson({
      'recipientId': '',
      ...envelopeData,
    });

    return InboxMessage(
      id: doc.id,
      envelope: envelope,
      deliveredAt: (data['deliveredAt'] as Timestamp).toDate(),
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

  void dispose() {
    stop();
    _controller.close();
  }
}
