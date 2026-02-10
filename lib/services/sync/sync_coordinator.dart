import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/local/message.dart';
import '../../models/local/conversation.dart';
import '../../repositories/message_dao.dart';
import '../../repositories/conversation_dao.dart';
import '../crypto/protocol_service.dart';
import '../database/app_database.dart';
import '../secure_storage.dart';
import '../../utils/security.dart';
import 'inbox_listener.dart';
import 'message_processor.dart';

enum SyncState { idle, initializing, syncing, ready, error }

class SyncCoordinator {
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  final ProtocolService _protocol;

  AppDatabase? _database;
  late final InboxListener _inboxListener;
  late MessageDao _messageDao;
  late ConversationDao _conversationDao;
  MessageProcessor? _processor;

  StreamSubscription? _inboxSubscription;
  StreamSubscription? _authSubscription;

  final _stateController = StreamController<SyncState>.broadcast();
  final _messageController = StreamController<ProcessedMessage>.broadcast();

  final SecureStorageService _storage = SecureStorageService();
  Map<String, int> _sequenceCounters = {};

  final _messageQueue = <InboxMessage>[];
  bool _isProcessingQueue = false;

  SyncState _state = SyncState.idle;
  String? _error;
  bool _initialized = false;

  static final SyncCoordinator _instance = SyncCoordinator._internal();
  factory SyncCoordinator() => _instance;

  SyncCoordinator._internal()
    : _auth = FirebaseAuth.instance,
      _functions = FirebaseFunctions.instance,
      _protocol = ProtocolService() {
    _inboxListener = InboxListener(auth: _auth);
  }

  MessageDao get messageDao => _messageDao;
  ConversationDao get conversationDao => _conversationDao;

  Stream<SyncState> get stateStream => _stateController.stream;
  Stream<ProcessedMessage> get messageStream => _messageController.stream;
  SyncState get state => _state;
  String? get error => _error;

  Future<void> initialize() async {
    if (_initialized) return;

    _setState(SyncState.initializing);

    try {
      _database ??= await AppDatabase.instance();
      _messageDao = _database!.messageDao;
      _conversationDao = _database!.conversationDao;
      await _protocol.initializeFromStorage();
      await _loadSequenceCounters();

      _authSubscription = _auth.authStateChanges().listen(_onAuthChanged);

      if (_auth.currentUser != null) {
        await _startSync();
      }

      _initialized = true;
      _setState(SyncState.ready);
    } catch (e) {
      _error = e.toString();
      _setState(SyncState.error);
    }
  }

  void _onAuthChanged(User? user) {
    if (user != null) {
      _startSync();
    } else {
      _stopSync();
    }
  }

  Future<void> _startSync() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    _setState(SyncState.syncing);

    _processor = MessageProcessor(
      protocol: _protocol,
      messageDao: _messageDao,
      conversationDao: _conversationDao,
      myUserId: userId,
    );

    _inboxListener.start();
    _inboxSubscription = _inboxListener.messages.listen(_onInboxMessage);

    _setState(SyncState.ready);
  }

  void _stopSync() {
    _inboxSubscription?.cancel();
    _inboxSubscription = null;
    _inboxListener.stop();
    _messageQueue.clear();
    _processor = null;
    _protocol.dispose();
    _initialized = false;
    _setState(SyncState.idle);
  }

  void _onInboxMessage(InboxMessage message) {
    _messageQueue.add(message);
    _drainQueue();
  }

  Future<void> _drainQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      while (_messageQueue.isNotEmpty) {
        final processor = _processor;
        if (processor == null) {
          _messageQueue.clear();
          break;
        }
        final message = _messageQueue.removeAt(0);
        final processed = await processor.processInboxMessage(message);
        if (processed != null) {
          _messageController.add(processed);
          await _inboxListener.deleteMessage(message.id);
        }
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<bool> sendMessage({
    required String content,
    required String recipientId,
    required Uint8List recipientPublicKey,
    LocalMessageType type = LocalMessageType.text,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return false;

    try {
      final envelope = await _protocol.sealEnvelope(
        plaintext: content,
        senderId: userId,
        recipientId: recipientId,
        recipientPublicKey: recipientPublicKey,
      );

      final conversationId = _getConversationId(userId, recipientId);
      final randomBytes = SecurityUtils.generateSecureRandomBytes(16);
      final messageId = base64Url.encode(randomBytes).replaceAll('=', '');

      final localMessage = LocalMessage(
        id: messageId,
        conversationId: conversationId,
        senderId: userId,
        senderUsername: '',
        content: content,
        timestamp: DateTime.now(),
        type: type,
        status: LocalMessageStatus.pending,
        isOutgoing: true,
        createdAt: DateTime.now(),
      );

      await _database!.transaction(() async {
        await _messageDao.insert(localMessage);

        final preview = content.length > 100 ? '${content.substring(0, 100)}...' : content;
        final existing = await _conversationDao.getById(conversationId);
        if (existing != null) {
          await _conversationDao.updateLastMessage(
            conversationId: conversationId,
            content: preview,
            timestamp: DateTime.now(),
          );
        } else {
          final now = DateTime.now();
          await _conversationDao.insert(LocalConversation(
            id: conversationId,
            recipientId: recipientId,
            recipientUsername: '',
            recipientPublicKey: '',
            lastMessageContent: preview,
            lastMessageAt: now,
            unreadCount: 0,
            createdAt: now,
            updatedAt: now,
          ));
        }
      });

      final result = await _functions.httpsCallable('deliverMessage').call({
        'messageId': messageId,
        'recipientId': recipientId,
        'sealedEnvelope': envelope.toJson(),
        'sequenceNumber': await _getNextSequence(conversationId),
      });

      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['success'] == true) {
        await _messageDao.updateStatus(messageId, LocalMessageStatus.sent);
        return true;
      } else {
        await _messageDao.updateStatus(messageId, LocalMessageStatus.failed);
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  String _getConversationId(String userId, String partnerId) {
    final ids = [userId, partnerId]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  Future<void> _loadSequenceCounters() async {
    final json = await _storage.getSequenceCounters();
    if (json != null) {
      try {
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        _sequenceCounters = decoded.map((k, v) => MapEntry(k, v as int));
      } catch (_) {
        _sequenceCounters = {};
      }
    }
  }

  Future<int> _getNextSequence(String conversationId) async {
    final current = _sequenceCounters[conversationId] ?? 0;
    final next = current + 1;
    _sequenceCounters[conversationId] = next;
    await _storage.storeSequenceCounters(jsonEncode(_sequenceCounters));
    return next;
  }

  Future<List<LocalConversation>> getConversations() async {
    return _conversationDao.getAll();
  }

  Future<List<LocalMessage>> getMessages(String conversationId, {int limit = 50}) async {
    return _messageDao.getByConversation(conversationId, limit: limit);
  }

  Future<void> markConversationRead(String conversationId) async {
    await _conversationDao.resetUnreadCount(conversationId);
  }

  void _setState(SyncState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void dispose() {
    _authSubscription?.cancel();
    _inboxSubscription?.cancel();
    _inboxListener.dispose();
    _stateController.close();
    _messageController.close();
  }
}
