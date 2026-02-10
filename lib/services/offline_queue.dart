import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/local/message.dart';

class PendingMessage {
  final String id;
  final String conversationId;
  final String recipientId;
  final Map<String, dynamic> sealedEnvelope;
  final int sequenceNumber;
  final DateTime createdAt;
  int retryCount;
  DateTime? lastRetryAt;
  String? lastError;

  PendingMessage({
    required this.id,
    required this.conversationId,
    required this.recipientId,
    required this.sealedEnvelope,
    required this.sequenceNumber,
    required this.createdAt,
    this.retryCount = 0,
    this.lastRetryAt,
    this.lastError,
  });

  LocalMessageStatus get status => retryCount >= OfflineQueueService.maxRetries
      ? LocalMessageStatus.failed
      : LocalMessageStatus.pending;

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'recipientId': recipientId,
        'sealedEnvelope': sealedEnvelope,
        'sequenceNumber': sequenceNumber,
        'createdAt': createdAt.toIso8601String(),
        'retryCount': retryCount,
        'lastRetryAt': lastRetryAt?.toIso8601String(),
        'lastError': lastError,
      };

  factory PendingMessage.fromJson(Map<String, dynamic> json) => PendingMessage(
        id: json['id'] as String,
        conversationId: json['conversationId'] as String,
        recipientId: json['recipientId'] as String,
        sealedEnvelope: Map<String, dynamic>.from(json['sealedEnvelope'] as Map),
        sequenceNumber: json['sequenceNumber'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
        retryCount: json['retryCount'] as int? ?? 0,
        lastRetryAt: json['lastRetryAt'] != null
            ? DateTime.parse(json['lastRetryAt'] as String)
            : null,
        lastError: json['lastError'] as String?,
      );
}

class OfflineQueueService {
  final FirebaseFunctions _functions;
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
    FirebaseFunctions? functions,
    Connectivity? connectivity,
  })  : _functions = functions ?? FirebaseFunctions.instance,
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
    required String recipientId,
    required Map<String, dynamic> sealedEnvelope,
    required int sequenceNumber,
  }) async {
    final pending = PendingMessage(
      id: messageId,
      conversationId: conversationId,
      recipientId: recipientId,
      sealedEnvelope: sealedEnvelope,
      sequenceNumber: sequenceNumber,
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

      final result = await _functions.httpsCallable('deliverMessage').call({
        'messageId': pending.id,
        'recipientId': pending.recipientId,
        'sealedEnvelope': pending.sealedEnvelope,
        'sequenceNumber': pending.sequenceNumber,
      });

      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['success'] != true) {
        final error = data['error'] as String? ?? 'Unknown error';
        throw Exception(error);
      }

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
