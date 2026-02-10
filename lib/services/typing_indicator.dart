import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class TypingIndicatorService {
  final FirebaseFirestore _db;
  final String currentUserId;
  final String partnerId;

  Timer? _typingTimer;
  Timer? _debounceTimer;
  bool _isTyping = false;
  bool _enabled = false;
  StreamSubscription? _partnerTypingSubscription;

  static const Duration _typingTimeout = Duration(seconds: 3);
  static const Duration _debounceDelay = Duration(milliseconds: 300);
  static const Duration _signalTtl = Duration(seconds: 30);

  set enabled(bool value) => _enabled = value;

  final StreamController<bool> _partnerTypingController = StreamController.broadcast();
  Stream<bool> get partnerTypingStream => _partnerTypingController.stream;

  TypingIndicatorService({
    required this.currentUserId,
    required this.partnerId,
    FirebaseFirestore? firestore,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  DocumentReference get _mySignalRef =>
      _db.collection('typing_signals').doc(partnerId).collection('from').doc(currentUserId);

  CollectionReference get _incomingSignalsRef =>
      _db.collection('typing_signals').doc(currentUserId).collection('from');

  void startListening() {
    _partnerTypingSubscription = _incomingSignalsRef.snapshots().listen((snapshot) {
      final now = DateTime.now();
      final partnerTyping = snapshot.docs.any((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) return false;
        final timestamp = data['timestamp'] as Timestamp?;
        if (timestamp == null) return false;
        return now.difference(timestamp.toDate()) < _typingTimeout;
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
    if (!_enabled) return;
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
      await _mySignalRef.set({
        'timestamp': FieldValue.serverTimestamp(),
        'expireAt': Timestamp.fromDate(DateTime.now().add(_signalTtl)),
      });
    } catch (_) {}
  }

  Future<void> _clearTypingStatus() async {
    try {
      await _mySignalRef.delete();
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
