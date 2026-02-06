import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/local/message.dart';
import '../../models/local/conversation.dart';
import '../../repositories/message.dart';
import '../../repositories/conversation.dart';
import '../crypto/protocol_service.dart';
import '../database/database_service.dart';
import 'inbox_listener.dart';
import 'message_processor.dart';

enum SyncState { idle, initializing, syncing, ready, error }

class SyncCoordinator {
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  final DatabaseService _database;
  final ProtocolService _protocol;

  late final InboxListener _inboxListener;
  late final MessageRepository _messageRepo;
  late final ConversationRepository _conversationRepo;
  MessageProcessor? _processor;

  StreamSubscription? _inboxSubscription;
  StreamSubscription? _authSubscription;

  final _stateController = StreamController<SyncState>.broadcast();
  final _messageController = StreamController<ProcessedMessage>.broadcast();

  SyncState _state = SyncState.idle;
  String? _error;

  SyncCoordinator({
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    DatabaseService? database,
    ProtocolService? protocol,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _functions = functions ?? FirebaseFunctions.instance,
        _database = database ?? DatabaseService(),
        _protocol = protocol ?? ProtocolService() {
    _inboxListener = InboxListener(auth: _auth);
    _messageRepo = MessageRepository(databaseService: _database);
    _conversationRepo = ConversationRepository(databaseService: _database);
  }

  Stream<SyncState> get stateStream => _stateController.stream;
  Stream<ProcessedMessage> get messageStream => _messageController.stream;
  SyncState get state => _state;
  String? get error => _error;

  Future<void> initialize() async {
    _setState(SyncState.initializing);

    try {
      await _database.database;
      await _protocol.initializeFromStorage();

      _authSubscription = _auth.authStateChanges().listen(_onAuthChanged);

      if (_auth.currentUser != null) {
        await _startSync();
      }

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
      messageRepository: _messageRepo,
      conversationRepository: _conversationRepo,
      myUserId: userId,
    );

    await _processPendingMessages();

    _inboxListener.start();
    _inboxSubscription = _inboxListener.messages.listen(_onInboxMessage);

    _setState(SyncState.ready);
  }

  void _stopSync() {
    _inboxSubscription?.cancel();
    _inboxSubscription = null;
    _inboxListener.stop();
    _processor = null;
    _setState(SyncState.idle);
  }

  Future<void> _processPendingMessages() async {
    if (_processor == null) return;

    final pending = await _inboxListener.fetchPending();

    for (final message in pending) {
      await _processMessage(message);
    }
  }

  Future<void> _onInboxMessage(InboxMessage message) async {
    await _processMessage(message);
  }

  Future<void> _processMessage(InboxMessage message) async {
    if (_processor == null) return;

    final processed = await _processor!.processInboxMessage(message);

    if (processed != null) {
      _messageController.add(processed);
      await _inboxListener.deleteMessage(message.id);
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
      final messageId = DateTime.now().millisecondsSinceEpoch.toString();

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

      await _messageRepo.insert(localMessage);

      await _conversationRepo.updateLastMessage(
        conversationId: conversationId,
        content: content.length > 100 ? '${content.substring(0, 100)}...' : content,
        timestamp: DateTime.now(),
      );

      final result = await _functions.httpsCallable('deliverMessage').call({
        'messageId': messageId,
        'recipientId': recipientId,
        'sealedEnvelope': envelope.toJson(),
        'sequenceNumber': await _getNextSequence(conversationId),
      });

      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['success'] == true) {
        await _messageRepo.updateStatus(messageId, LocalMessageStatus.sent);
        return true;
      } else {
        await _messageRepo.updateStatus(messageId, LocalMessageStatus.failed);
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

  int _sequenceCounter = 0;

  Future<int> _getNextSequence(String conversationId) async {
    _sequenceCounter++;
    return _sequenceCounter;
  }

  Future<List<LocalConversation>> getConversations() async {
    return _conversationRepo.getAll();
  }

  Future<List<LocalMessage>> getMessages(String conversationId, {int limit = 50}) async {
    return _messageRepo.getByConversation(conversationId, limit: limit);
  }

  Future<void> markConversationRead(String conversationId) async {
    await _conversationRepo.resetUnreadCount(conversationId);
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
