import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/echo.dart';

class PendingMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String recipientId;
  final String plaintext;
  final String encryptedContent;
  final EchoType type;
  final EchoMetadata metadata;
  final int senderKeyVersion;
  final int recipientKeyVersion;
  final int sequenceNumber;
  final String? validationToken;
  final DateTime createdAt;
  int retryCount;
  DateTime? lastRetryAt;
  String? lastError;

  PendingMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.recipientId,
    required this.plaintext,
    required this.encryptedContent,
    required this.type,
    required this.metadata,
    required this.senderKeyVersion,
    required this.recipientKeyVersion,
    required this.sequenceNumber,
    this.validationToken,
    required this.createdAt,
    this.retryCount = 0,
    this.lastRetryAt,
    this.lastError,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'senderId': senderId,
        'recipientId': recipientId,
        'plaintext': plaintext,
        'encryptedContent': encryptedContent,
        'type': type.value,
        'metadata': metadata.toJson(),
        'senderKeyVersion': senderKeyVersion,
        'recipientKeyVersion': recipientKeyVersion,
        'sequenceNumber': sequenceNumber,
        'validationToken': validationToken,
        'createdAt': createdAt.toIso8601String(),
        'retryCount': retryCount,
        'lastRetryAt': lastRetryAt?.toIso8601String(),
        'lastError': lastError,
      };

  factory PendingMessage.fromJson(Map<String, dynamic> json) => PendingMessage(
        id: json['id'] as String,
        conversationId: json['conversationId'] as String,
        senderId: json['senderId'] as String,
        recipientId: json['recipientId'] as String,
        plaintext: json['plaintext'] as String,
        encryptedContent: json['encryptedContent'] as String,
        type: EchoType.fromString(json['type'] as String),
        metadata: EchoMetadata.fromJson(json['metadata'] as Map<String, dynamic>),
        senderKeyVersion: json['senderKeyVersion'] as int,
        recipientKeyVersion: json['recipientKeyVersion'] as int,
        sequenceNumber: json['sequenceNumber'] as int,
        validationToken: json['validationToken'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        retryCount: json['retryCount'] as int? ?? 0,
        lastRetryAt: json['lastRetryAt'] != null
            ? DateTime.parse(json['lastRetryAt'] as String)
            : null,
        lastError: json['lastError'] as String?,
      );

  EchoModel toEchoModel() => EchoModel(
        id: id,
        senderId: senderId,
        recipientId: recipientId,
        content: encryptedContent,
        timestamp: createdAt,
        type: type,
        status: retryCount >= OfflineQueueService.maxRetries
            ? EchoStatus.failed
            : EchoStatus.pending,
        metadata: metadata,
        senderKeyVersion: senderKeyVersion,
        recipientKeyVersion: recipientKeyVersion,
        sequenceNumber: sequenceNumber,
        validationToken: validationToken,
        conversationId: conversationId,
      );
}

class OfflineQueueService {
  final FirebaseFirestore _db;
  final Connectivity _connectivity;

  static const String _storageKey = 'offline_message_queue';
  static const int maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 5);
  static const Duration _minRetryInterval = Duration(seconds: 30);

  final Map<String, List<PendingMessage>> _queue = {};
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _retryTimer;
  bool _isProcessing = false;
  bool _isOnline = true;

  final StreamController<Map<String, PendingMessage>> _statusController =
      StreamController.broadcast();

  Stream<Map<String, PendingMessage>> get statusStream => _statusController.stream;

  OfflineQueueService({
    FirebaseFirestore? firestore,
    Connectivity? connectivity,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _connectivity = connectivity ?? Connectivity();

  Future<void> initialize() async {
    await _loadFromDisk();
    _startConnectivityMonitoring();
  }

  void _startConnectivityMonitoring() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (results) {
        final wasOffline = !_isOnline;
        _isOnline = results.isNotEmpty &&
            !results.contains(ConnectivityResult.none);

        if (_isOnline && wasOffline) {
          _scheduleRetry();
        }
      },
    );

    _connectivity.checkConnectivity().then((results) {
      _isOnline = results.isNotEmpty &&
          !results.contains(ConnectivityResult.none);
    });
  }

  Future<void> _loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_storageKey);
      if (data == null) return;

      final decoded = jsonDecode(data) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        final conversationId = entry.key;
        final messages = (entry.value as List)
            .map((m) => PendingMessage.fromJson(m as Map<String, dynamic>))
            .toList();
        _queue[conversationId] = messages;
      }
    } catch (_) {}
  }

  Future<void> _saveToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = <String, dynamic>{};
      for (final entry in _queue.entries) {
        data[entry.key] = entry.value.map((m) => m.toJson()).toList();
      }
      await prefs.setString(_storageKey, jsonEncode(data));
    } catch (_) {}
  }

  Future<PendingMessage> enqueue({
    required String messageId,
    required String conversationId,
    required String senderId,
    required String recipientId,
    required String plaintext,
    required String encryptedContent,
    required EchoType type,
    required EchoMetadata metadata,
    required int senderKeyVersion,
    required int recipientKeyVersion,
    required int sequenceNumber,
    String? validationToken,
  }) async {
    final pending = PendingMessage(
      id: messageId,
      conversationId: conversationId,
      senderId: senderId,
      recipientId: recipientId,
      plaintext: plaintext,
      encryptedContent: encryptedContent,
      type: type,
      metadata: metadata,
      senderKeyVersion: senderKeyVersion,
      recipientKeyVersion: recipientKeyVersion,
      sequenceNumber: sequenceNumber,
      validationToken: validationToken,
      createdAt: DateTime.now(),
    );

    _queue.putIfAbsent(conversationId, () => []);
    _queue[conversationId]!.add(pending);
    await _saveToDisk();

    _statusController.add({pending.id: pending});

    if (_isOnline) {
      _scheduleRetry();
    }

    return pending;
  }

  List<PendingMessage> getPendingForConversation(String conversationId) {
    return List.unmodifiable(_queue[conversationId] ?? []);
  }

  bool hasPending(String messageId) {
    return _queue.values.any((messages) => messages.any((m) => m.id == messageId));
  }

  PendingMessage? getPending(String messageId) {
    for (final messages in _queue.values) {
      final found = messages.where((m) => m.id == messageId).firstOrNull;
      if (found != null) return found;
    }
    return null;
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, _processQueue);
  }

  Future<void> _processQueue() async {
    if (_isProcessing || !_isOnline) return;
    _isProcessing = true;

    try {
      for (final conversationId in _queue.keys.toList()) {
        final messages = _queue[conversationId];
        if (messages == null || messages.isEmpty) continue;

        for (final pending in messages.toList()) {
          if (pending.retryCount >= maxRetries) continue;

          if (pending.lastRetryAt != null) {
            final elapsed = DateTime.now().difference(pending.lastRetryAt!);
            if (elapsed < _minRetryInterval) continue;
          }

          await _sendMessage(pending);
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _sendMessage(PendingMessage pending) async {
    try {
      pending.retryCount++;
      pending.lastRetryAt = DateTime.now();
      _statusController.add({pending.id: pending});

      final messagesRef = _db
          .collection('conversations')
          .doc(pending.conversationId)
          .collection('messages');

      final message = EchoModel(
        id: pending.id,
        senderId: pending.senderId,
        recipientId: pending.recipientId,
        content: pending.encryptedContent,
        timestamp: pending.createdAt,
        type: pending.type,
        status: EchoStatus.sent,
        metadata: pending.metadata,
        senderKeyVersion: pending.senderKeyVersion,
        recipientKeyVersion: pending.recipientKeyVersion,
        sequenceNumber: pending.sequenceNumber,
        validationToken: pending.validationToken,
        conversationId: pending.conversationId,
      );

      await messagesRef.doc(pending.id).set(message.toJson());

      await _db.collection('conversations').doc(pending.conversationId).update({
        'lastMessage': pending.encryptedContent,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unreadCount.${pending.recipientId}': FieldValue.increment(1),
      });

      _removeFromQueue(pending);
    } catch (e) {
      pending.lastError = e.toString();
      _statusController.add({pending.id: pending});
      await _saveToDisk();

      if (pending.retryCount >= maxRetries) {
        _statusController.add({pending.id: pending});
      }
    }
  }

  void _removeFromQueue(PendingMessage pending) {
    final messages = _queue[pending.conversationId];
    if (messages != null) {
      messages.removeWhere((m) => m.id == pending.id);
      if (messages.isEmpty) {
        _queue.remove(pending.conversationId);
      }
    }
    _saveToDisk();
  }

  Future<void> retry(String messageId) async {
    final pending = getPending(messageId);
    if (pending == null) return;

    pending.retryCount = 0;
    pending.lastError = null;
    pending.lastRetryAt = null;
    await _saveToDisk();

    _statusController.add({pending.id: pending});

    if (_isOnline) {
      await _sendMessage(pending);
    }
  }

  Future<void> remove(String messageId) async {
    for (final conversationId in _queue.keys.toList()) {
      final messages = _queue[conversationId];
      if (messages != null) {
        messages.removeWhere((m) => m.id == messageId);
        if (messages.isEmpty) {
          _queue.remove(conversationId);
        }
      }
    }
    await _saveToDisk();
  }


  bool get isOnline => _isOnline;

  int get totalPendingCount {
    return _queue.values.fold(0, (total, messages) => total + messages.length);
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _retryTimer?.cancel();
    _statusController.close();
    _saveToDisk();
  }
}
