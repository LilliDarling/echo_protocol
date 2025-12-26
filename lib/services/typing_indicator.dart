import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class TypingIndicatorService {
  final FirebaseFirestore _db;
  final String conversationId;
  final String currentUserId;

  Timer? _typingTimer;
  Timer? _debounceTimer;
  bool _isTyping = false;
  StreamSubscription? _partnerTypingSubscription;

  static const Duration _typingTimeout = Duration(seconds: 3);
  static const Duration _debounceDelay = Duration(milliseconds: 300);

  final StreamController<bool> _partnerTypingController = StreamController.broadcast();
  Stream<bool> get partnerTypingStream => _partnerTypingController.stream;

  TypingIndicatorService({
    required this.conversationId,
    required this.currentUserId,
    FirebaseFirestore? firestore,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  DocumentReference get _conversationRef =>
      _db.collection('conversations').doc(conversationId);

  void startListening() {
    _partnerTypingSubscription = _conversationRef.snapshots().listen((snapshot) {
      if (!snapshot.exists) return;

      final data = snapshot.data() as Map<String, dynamic>?;
      if (data == null) return;

      final typing = data['typing'] as Map<String, dynamic>? ?? {};

      final partnerTyping = typing.entries
          .where((e) => e.key != currentUserId)
          .any((e) {
            final timestamp = e.value as Timestamp?;
            if (timestamp == null) return false;
            final typingTime = timestamp.toDate();
            return DateTime.now().difference(typingTime) < _typingTimeout;
          });

      _partnerTypingController.add(partnerTyping);
    });
  }

  void onTextChanged(String text) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () {
      if (text.isNotEmpty) {
        _setTyping(true);
      } else {
        _setTyping(false);
      }
    });
  }

  void _setTyping(bool typing) {
    if (_isTyping == typing) return;
    _isTyping = typing;

    _typingTimer?.cancel();

    if (typing) {
      _updateTypingStatus();
      _typingTimer = Timer.periodic(_typingTimeout - const Duration(milliseconds: 500), (_) {
        if (_isTyping) {
          _updateTypingStatus();
        }
      });
    } else {
      _clearTypingStatus();
    }
  }

  Future<void> _updateTypingStatus() async {
    try {
      await _conversationRef.update({
        'typing.$currentUserId': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _clearTypingStatus() async {
    try {
      await _conversationRef.update({
        'typing.$currentUserId': FieldValue.delete(),
      });
    } catch (_) {}
  }

  void stopTyping() {
    _setTyping(false);
  }

  void dispose() {
    _typingTimer?.cancel();
    _debounceTimer?.cancel();
    _partnerTypingSubscription?.cancel();
    _partnerTypingController.close();
    _clearTypingStatus();
  }
}
