import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../models/echo.dart';
import '../../../models/key_change_event.dart';
import '../../../models/local/message.dart';
import '../../../services/partner.dart';
import '../../../services/crypto/protocol_service.dart';
import '../../../services/crypto/media_encryption.dart';
import '../../../services/secure_storage.dart';
import '../../../utils/decrypted_content_cache.dart';
import '../../../services/offline_queue.dart';
import '../../../services/typing_indicator.dart';
import '../../../services/auto_delete.dart';
import '../../../services/sync/sync_coordinator.dart';
import '../../../repositories/message_dao.dart';
import '../../../utils/security.dart';

class ConversationController extends ChangeNotifier {
  final PartnerInfo partner;
  final String conversationId;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  late final ProtocolService _protocolService;
  late final SecureStorageService _secureStorage;
  MediaEncryptionService? _mediaEncryptionService;
  late final DecryptedContentCacheService _contentCache;
  late final OfflineQueueService _offlineQueue;
  late final TypingIndicatorService _typingService;
  late final SyncCoordinator _syncCoordinator;
  late final MessageDao _messageDao;

  List<LocalMessage> _messages = [];
  StreamSubscription? _syncMessageSubscription;
  StreamSubscription? _offlineQueueSubscription;
  StreamSubscription? _typingSubscription;

  bool _isLoading = true;
  bool _isSending = false;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  bool _isServicesInitialized = false;
  bool _isPartnerTyping = false;
  String? _error;

  KeyChangeResult? _keyChangeResult;
  KeyChangeEvent? _pendingKeyChangeEvent;
  late final PartnerService _partnerService;

  static const int _pageSize = 30;

  ConversationController({
    required this.partner,
    required this.conversationId,
  }) {
    _offlineQueue = OfflineQueueService();
    _typingService = TypingIndicatorService(
      currentUserId: currentUserId,
      partnerId: partner.id,
    );
  }

  List<LocalMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMoreMessages => _hasMoreMessages;
  bool get isServicesInitialized => _isServicesInitialized;
  bool get isPartnerTyping => _isPartnerTyping;
  String? get error => _error;
  MediaEncryptionService? get mediaEncryptionService => _mediaEncryptionService;
  OfflineQueueService get offlineQueue => _offlineQueue;
  TypingIndicatorService get typingService => _typingService;

  void setTypingIndicatorEnabled(bool enabled) {
    _typingService.enabled = enabled;
  }

  Future<void> runAutoDelete(int autoDeleteDays) async {
    if (autoDeleteDays <= 0) return;

    final service = AutoDeleteService(messageDao: _messageDao);
    final deleted = await service.deleteOldMessages(
      conversationId: conversationId,
      autoDeleteDays: autoDeleteDays,
    );

    if (deleted > 0) {
      _messages.removeWhere((m) {
        final cutoff = DateTime.now().subtract(Duration(days: autoDeleteDays));
        return m.timestamp.isBefore(cutoff);
      });
      notifyListeners();
    }
  }

  DecryptedContentCacheService get contentCache => _contentCache;
  KeyChangeResult? get keyChangeResult => _keyChangeResult;
  KeyChangeEvent? get pendingKeyChangeEvent => _pendingKeyChangeEvent;
  bool get hasKeyChangeWarning => _keyChangeResult?.status == KeyChangeStatus.changed;

  String get currentUserId => _auth.currentUser?.uid ?? '';

  Future<void> initialize() async {
    await _initializeServices();
    _subscribeToNewMessages();
    await _loadInitialMessages();
  }

  Future<void> _initializeServices() async {
    try {
      _protocolService = ProtocolService();
      _secureStorage = SecureStorageService();
      _partnerService = PartnerService();
      _syncCoordinator = SyncCoordinator();
      await _syncCoordinator.initialize();
      _messageDao = _syncCoordinator.messageDao;

      _contentCache = DecryptedContentCacheService(secureStorage: _secureStorage);
      await _contentCache.loadFromDisk();

      await _offlineQueue.initialize();
      _subscribeToOfflineQueue();
      _subscribeToTypingIndicator();

      await _protocolService.initializeFromStorage();

      _mediaEncryptionService = MediaEncryptionService();
      await _mediaEncryptionService!.clearCache();

      await _checkPartnerKeyChange();

      _isServicesInitialized = true;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to initialize encryption: ${e.toString()}';
      notifyListeners();
    }
  }

  Future<void> _checkPartnerKeyChange() async {
    _keyChangeResult = await _partnerService.checkPartnerKeyChange(partner.publicKey);

    if (_keyChangeResult!.status == KeyChangeStatus.firstKey) {
      await _partnerService.trustCurrentKey(partner.publicKey);
    } else if (_keyChangeResult!.status == KeyChangeStatus.changed) {
      _pendingKeyChangeEvent = await _partnerService.logKeyChangeEvent(
        previousFingerprint: _keyChangeResult!.previousFingerprint!,
        newFingerprint: _keyChangeResult!.currentFingerprint,
      );
    }
  }

  Future<void> acknowledgeKeyChange() async {
    if (_pendingKeyChangeEvent == null) return;

    await _partnerService.acknowledgeKeyChange(_pendingKeyChangeEvent!.id);
    await _partnerService.trustCurrentKey(partner.publicKey);

    _keyChangeResult = KeyChangeResult(
      status: KeyChangeStatus.noChange,
      previousFingerprint: _keyChangeResult!.currentFingerprint,
      currentFingerprint: _keyChangeResult!.currentFingerprint,
    );
    _pendingKeyChangeEvent = null;
    notifyListeners();
  }

  String get partnerFingerprint => _partnerService.computeFingerprint(partner.publicKey);

  Future<void> _loadInitialMessages() async {
    try {
      final localMessages = await _syncCoordinator.getMessages(
        conversationId,
        limit: _pageSize,
      );

      final dbIds = localMessages.map((m) => m.id).toSet();
      final streamOnly = _messages.where((m) => !dbIds.contains(m.id)).toList();
      _messages = [...localMessages, ...streamOnly];
      _hasMoreMessages = localMessages.length >= _pageSize;
      _isLoading = false;
      notifyListeners();

      await _syncCoordinator.markConversationRead(conversationId);
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreMessages(double scrollOffset, double maxScrollBefore) async {
    if (_isLoadingMore || !_hasMoreMessages || _messages.isEmpty) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      final oldestTimestamp = _messages.first.timestamp;
      final olderMessages = await _messageDao.getMessagesBefore(
        conversationId,
        oldestTimestamp,
        limit: _pageSize,
      );

      _hasMoreMessages = olderMessages.length >= _pageSize;

      if (olderMessages.isNotEmpty) {
        _messages = [...olderMessages, ..._messages];
      }
    } catch (e) {
      _error = 'Failed to load older messages';
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  void _subscribeToOfflineQueue() {
    _offlineQueueSubscription = _offlineQueue.statusStream.listen((updates) {
      for (final entry in updates.entries) {
        final messageId = entry.key;
        final pending = entry.value;

        if (pending.conversationId != conversationId) continue;

        final index = _messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(
            status: pending.status,
          );
          notifyListeners();
        }
      }
    });
  }

  void _subscribeToTypingIndicator() {
    _typingService.startListening();
    _typingSubscription = _typingService.partnerTypingStream.listen((isTyping) {
      _isPartnerTyping = isTyping;
      notifyListeners();
    });
  }

  void _subscribeToNewMessages() {
    _syncMessageSubscription = _syncCoordinator.messageStream.listen(
      (processed) {
        if (processed.conversationId != conversationId) return;

        final existingIndex = _messages.indexWhere((m) => m.id == processed.messageId);
        if (existingIndex != -1) return;

        final newMessage = LocalMessage(
          id: processed.messageId,
          conversationId: processed.conversationId,
          senderId: processed.senderId,
          senderUsername: '',
          content: processed.content,
          timestamp: processed.timestamp,
          type: _convertProcessedType(processed.type),
          status: LocalMessageStatus.delivered,
          isOutgoing: processed.senderId == currentUserId,
          createdAt: DateTime.now(),
        );

        _messages = [..._messages, newMessage];
        notifyListeners();

        if (processed.senderId != currentUserId) {
          _syncCoordinator.markConversationRead(conversationId);
        }
      },
      onError: (error) {
        _error = error.toString();
        notifyListeners();
      },
    );
  }

  LocalMessageType _convertProcessedType(LocalMessageType type) {
    return type;
  }

  Future<void> sendMessage(String text, {EchoType type = EchoType.text, EchoMetadata? metadata}) async {
    if (text.trim().isEmpty && type == EchoType.text) return;

    if (!_isServicesInitialized) {
      _error = 'Please wait, initializing encryption...';
      notifyListeners();
      return;
    }

    _typingService.stopTyping();

    _isSending = true;
    _error = null;
    notifyListeners();

    try {
      final randomBytes = SecurityUtils.generateSecureRandomBytes(16);
      final messageId = base64Url.encode(randomBytes).replaceAll('=', '');
      final timestamp = DateTime.now();

      final optimisticMessage = LocalMessage(
        id: messageId,
        conversationId: conversationId,
        senderId: currentUserId,
        senderUsername: '',
        content: text,
        timestamp: timestamp,
        type: _convertEchoType(type),
        status: LocalMessageStatus.pending,
        isOutgoing: true,
        createdAt: timestamp,
      );

      _messages = [..._messages, optimisticMessage];
      notifyListeners();

      if (!_offlineQueue.isOnline) {
        final recipientPubKey = base64Decode(partner.publicKey);
        final envelope = await _protocolService.sealEnvelope(
          plaintext: text,
          senderId: currentUserId,
          recipientId: partner.id,
          recipientPublicKey: recipientPubKey,
        );
        await _offlineQueue.enqueue(
          messageId: messageId,
          conversationId: conversationId,
          recipientId: partner.id,
          sealedEnvelope: envelope.toJson(),
          sequenceNumber: 0,
        );
        return;
      }

      final recipientPublicKey = base64Decode(partner.publicKey);

      final success = await _syncCoordinator.sendMessage(
        content: text,
        recipientId: partner.id,
        recipientPublicKey: recipientPublicKey,
        type: _convertEchoType(type),
      );

      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(
          status: success ? LocalMessageStatus.sent : LocalMessageStatus.failed,
        );
        notifyListeners();
      }

      if (!success) {
        throw Exception('Failed to send message');
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      rethrow;
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  LocalMessageType _convertEchoType(EchoType type) {
    switch (type) {
      case EchoType.text:
        return LocalMessageType.text;
      case EchoType.image:
        return LocalMessageType.image;
      case EchoType.video:
        return LocalMessageType.video;
      case EchoType.voice:
        return LocalMessageType.voice;
      case EchoType.link:
        return LocalMessageType.link;
      case EchoType.gif:
        return LocalMessageType.gif;
    }
  }

  Future<void> editMessage(EchoModel message, String newText) async {
    _error = 'Edit is not supported with sealed sender messaging';
    notifyListeners();
  }

  Future<void> deleteMessage(EchoModel message) async {
    if (message.senderId != currentUserId) return;

    try {
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index != -1) {
        _messages.removeAt(index);
        await _messageDao.deleteMessage(message.id);
        notifyListeners();
      }
    } catch (e) {
      _error = 'Failed to delete message';
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void saveCache() {
    _contentCache.saveToDisk();
  }

  @override
  void dispose() {
    _syncMessageSubscription?.cancel();
    _offlineQueueSubscription?.cancel();
    _typingSubscription?.cancel();
    _contentCache.saveToDisk();
    _offlineQueue.dispose();
    _typingService.dispose();
    super.dispose();
  }
}
