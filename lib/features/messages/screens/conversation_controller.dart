import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../models/echo.dart';
import '../../../services/partner.dart';
import '../../../services/encryption.dart';
import '../../../services/secure_storage.dart';
import '../../../services/message_encryption_helper.dart';
import '../../../services/message_rate_limiter.dart';
import '../../../services/replay_protection.dart';
import '../../../services/media_encryption.dart';
import '../../../utils/decrypted_content_cache.dart';
import '../../../services/read_receipt.dart';
import '../../../services/offline_queue.dart';
import '../../../services/typing_indicator.dart';

class ConversationController extends ChangeNotifier {
  final PartnerInfo partner;
  final String conversationId;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late final EncryptionService _encryptionService;
  late final SecureStorageService _secureStorage;
  late final MessageEncryptionHelper _encryptionHelper;
  late final MessageRateLimiter _rateLimiter;
  late final ReplayProtectionService _replayProtection;
  MediaEncryptionService? _mediaEncryptionService;
  late final DecryptedContentCacheService _contentCache;
  late final ReadReceiptService _readReceiptService;
  late final OfflineQueueService _offlineQueue;
  late final TypingIndicatorService _typingService;

  List<EchoModel> _messages = [];
  StreamSubscription? _messagesSubscription;
  StreamSubscription? _newMessagesSubscription;
  StreamSubscription? _modificationsSubscription;
  StreamSubscription? _offlineQueueSubscription;
  StreamSubscription? _typingSubscription;

  bool _isLoading = true;
  bool _isSending = false;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  bool _isServicesInitialized = false;
  bool _isPartnerTyping = false;
  DocumentSnapshot? _oldestMessageDoc;
  String? _error;

  static const int _pageSize = 30;

  ConversationController({
    required this.partner,
    required this.conversationId,
  }) {
    _readReceiptService = ReadReceiptService(
      conversationId: conversationId,
      currentUserId: currentUserId,
    );
    _offlineQueue = OfflineQueueService();
    _typingService = TypingIndicatorService(
      conversationId: conversationId,
      currentUserId: currentUserId,
    );
  }

  // Getters
  List<EchoModel> get messages => _messages;
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
  DecryptedContentCacheService get contentCache => _contentCache;

  String get currentUserId => _auth.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _messagesRef =>
      _db.collection('conversations').doc(conversationId).collection('messages');

  Future<void> initialize() async {
    await _initializeServices();
    await _loadInitialMessages();
    _markMessagesAsDelivered();
  }

  Future<void> _initializeServices() async {
    try {
      _encryptionService = EncryptionService();
      _secureStorage = SecureStorageService();
      _rateLimiter = MessageRateLimiter();
      _replayProtection = ReplayProtectionService(userId: currentUserId);

      _contentCache = DecryptedContentCacheService(secureStorage: _secureStorage);
      await _contentCache.loadFromDisk();

      await _offlineQueue.initialize();
      _subscribeToOfflineQueue();
      _subscribeToTypingIndicator();

      final privateKey = await _secureStorage.getPrivateKey();
      if (privateKey == null) {
        throw Exception('Encryption keys not found. Please sign out and sign in again.');
      }

      final keyVersion = await _secureStorage.getCurrentKeyVersion();
      _encryptionService.setPrivateKey(privateKey, keyVersion: keyVersion);
      _encryptionService.setPartnerPublicKey(partner.publicKey);

      _encryptionHelper = MessageEncryptionHelper(
        encryptionService: _encryptionService,
        secureStorage: _secureStorage,
        replayProtection: _replayProtection,
        rateLimiter: _rateLimiter,
      );

      _mediaEncryptionService = MediaEncryptionService(
        encryptionService: _encryptionService,
      );

      _isServicesInitialized = true;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to initialize encryption: ${e.toString()}';
      notifyListeners();
    }
  }

  Future<void> _loadInitialMessages() async {
    try {
      final query = _messagesRef
          .orderBy('timestamp', descending: true)
          .limit(_pageSize);

      final snapshot = await query.get();
      final messages = <EchoModel>[];

      for (final doc in snapshot.docs) {
        final message = EchoModel.fromFirestore(doc);
        messages.add(message);
        await _cacheDecryptedContent(message);
      }

      if (snapshot.docs.isNotEmpty) {
        _oldestMessageDoc = snapshot.docs.last;
      }
      _hasMoreMessages = snapshot.docs.length >= _pageSize;

      _messages = messages.reversed.toList();
      _isLoading = false;
      notifyListeners();

      _subscribeToNewMessages();
      markVisibleMessagesAsRead();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreMessages(double scrollOffset, double maxScrollBefore) async {
    if (_isLoadingMore || !_hasMoreMessages || _oldestMessageDoc == null) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      final query = _messagesRef
          .orderBy('timestamp', descending: true)
          .startAfterDocument(_oldestMessageDoc!)
          .limit(_pageSize);

      final snapshot = await query.get();
      final olderMessages = <EchoModel>[];

      for (final doc in snapshot.docs) {
        final message = EchoModel.fromFirestore(doc);
        olderMessages.add(message);
        await _cacheDecryptedContent(message);
      }

      if (snapshot.docs.isNotEmpty) {
        _oldestMessageDoc = snapshot.docs.last;
      }
      _hasMoreMessages = snapshot.docs.length >= _pageSize;

      if (olderMessages.isNotEmpty) {
        _messages = [...olderMessages.reversed, ..._messages];
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
          _messages[index] = pending.toEchoModel();
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
    final newestTimestamp = _messages.isNotEmpty
        ? _messages.last.timestamp
        : DateTime.now();

    final query = _messagesRef
        .where('timestamp', isGreaterThan: Timestamp.fromDate(newestTimestamp))
        .orderBy('timestamp', descending: false);

    _newMessagesSubscription = query.snapshots().listen(
      (snapshot) async {
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final message = EchoModel.fromFirestore(change.doc);
            if (!_messages.any((m) => m.id == message.id)) {
              await _cacheDecryptedContent(message);
              _messages = [..._messages, message];
              notifyListeners();
              markVisibleMessagesAsRead();
            }
          } else if (change.type == DocumentChangeType.modified) {
            final message = EchoModel.fromFirestore(change.doc);
            await _handleMessageModification(message);
          }
        }
      },
      onError: (error) {
        _error = error.toString();
        notifyListeners();
      },
    );

    _subscribeToModifications();
  }

  void _subscribeToModifications() {
    _modificationsSubscription = _messagesRef.snapshots().listen(
      (snapshot) async {
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.modified) {
            final message = EchoModel.fromFirestore(change.doc);
            await _handleMessageModification(message);
          }
        }
      },
    );
  }

  Future<void> _handleMessageModification(EchoModel message) async {
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index == -1) return;

    final existingMessage = _messages[index];

    if (existingMessage.isEdited == message.isEdited &&
        existingMessage.isDeleted == message.isDeleted &&
        existingMessage.content == message.content &&
        existingMessage.status == message.status) {
      return;
    }

    if (message.isEdited && !message.isDeleted &&
        existingMessage.content != message.content) {
      _contentCache.remove(message.id);
      await _cacheDecryptedContent(message);
    } else if (message.isDeleted && !existingMessage.isDeleted) {
      _contentCache.remove(message.id);
    }

    _messages[index] = message;
    notifyListeners();
  }

  Future<void> _cacheDecryptedContent(EchoModel message) async {
    final cached = _contentCache.get(message.id);
    if (cached != null && cached != '[Unable to decrypt message]') {
      return;
    }

    try {
      final decrypted = await _decryptMessage(message);
      _contentCache.put(message.id, decrypted);
    } catch (_) {
      // Don't cache failures - allow retry on next load
    }
  }

  Future<String> _decryptMessage(EchoModel message) async {
    return await _encryptionHelper.decryptMessage(
      message: message,
      myUserId: currentUserId,
      partnerId: partner.id,
    );
  }

  Future<void> _markMessagesAsDelivered() async {
    final undelivered = await _messagesRef
        .where('recipientId', isEqualTo: currentUserId)
        .where('status', isEqualTo: 'sent')
        .get();

    if (undelivered.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in undelivered.docs) {
      batch.update(doc.reference, {
        'status': 'delivered',
        'deliveredAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  void markVisibleMessagesAsRead() {
    final unreadIds = _messages
        .where((m) =>
            m.recipientId == currentUserId &&
            m.status != EchoStatus.read)
        .map((m) => m.id)
        .toList();

    if (unreadIds.isNotEmpty) {
      _readReceiptService.markMultipleAsRead(unreadIds);
    }
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
      final encryptionResult = await _encryptionHelper.encryptMessage(
        plaintext: text,
        partnerId: partner.id,
        senderId: currentUserId,
      );

      final messageId = _messagesRef.doc().id;
      final timestamp = DateTime.now();
      final sequenceNumber = encryptionResult['sequenceNumber'] as int;

      String? validationToken;
      bool useOfflineQueue = false;

      try {
        final validationResult = await _replayProtection.validateMessageServerSide(
          messageId: messageId,
          conversationId: conversationId,
          recipientId: partner.id,
          sequenceNumber: sequenceNumber,
          timestamp: timestamp,
        );

        if (!validationResult.valid) {
          if (validationResult.isRateLimited) {
            final retrySeconds = validationResult.retryAfter.inSeconds;
            throw Exception(
              'Message rate limit exceeded. Please wait ${retrySeconds > 60 ? '${(retrySeconds / 60).ceil()} minutes' : '$retrySeconds seconds'}.',
            );
          }
          throw Exception(validationResult.error ?? 'Message validation failed');
        }

        validationToken = validationResult.token;
      } catch (e) {
        if (!_offlineQueue.isOnline || e.toString().contains('network')) {
          useOfflineQueue = true;
        } else {
          rethrow;
        }
      }

      final message = EchoModel(
        id: messageId,
        senderId: currentUserId,
        recipientId: partner.id,
        content: encryptionResult['content'] as String,
        timestamp: timestamp,
        type: type,
        status: useOfflineQueue ? EchoStatus.pending : EchoStatus.sent,
        metadata: metadata ?? EchoMetadata.empty(),
        senderKeyVersion: encryptionResult['senderKeyVersion'] as int,
        recipientKeyVersion: encryptionResult['recipientKeyVersion'] as int,
        sequenceNumber: sequenceNumber,
        validationToken: validationToken,
        conversationId: conversationId,
      );

      _contentCache.put(messageId, text);
      _messages = [..._messages, message];
      notifyListeners();

      if (useOfflineQueue) {
        await _offlineQueue.enqueue(
          messageId: messageId,
          conversationId: conversationId,
          senderId: currentUserId,
          recipientId: partner.id,
          plaintext: text,
          encryptedContent: encryptionResult['content'] as String,
          type: type,
          metadata: metadata ?? EchoMetadata.empty(),
          senderKeyVersion: encryptionResult['senderKeyVersion'] as int,
          recipientKeyVersion: encryptionResult['recipientKeyVersion'] as int,
          sequenceNumber: sequenceNumber,
          validationToken: validationToken,
        );
      } else {
        await _messagesRef.doc(messageId).set(message.toJson());

        await _db.collection('conversations').doc(conversationId).update({
          'lastMessage': encryptionResult['content'] as String,
          'lastMessageAt': FieldValue.serverTimestamp(),
          'unreadCount.${partner.id}': FieldValue.increment(1),
        });
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

  Future<void> editMessage(EchoModel message, String newText) async {
    if (newText.trim().isEmpty) return;
    if (message.senderId != currentUserId) return;
    if (message.isDeleted) return;

    try {
      final encryptionResult = await _encryptionHelper.encryptMessage(
        plaintext: newText,
        partnerId: partner.id,
        senderId: currentUserId,
      );

      _contentCache.put(message.id, newText);
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(
          content: encryptionResult['content'] as String,
          isEdited: true,
          editedAt: DateTime.now(),
        );
        notifyListeners();
      }

      await _messagesRef.doc(message.id).update({
        'content': encryptionResult['content'],
        'isEdited': true,
        'editedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteMessage(EchoModel message) async {
    if (message.senderId != currentUserId) return;
    if (message.isDeleted) return;

    try {
      _contentCache.remove(message.id);
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(
          isDeleted: true,
          deletedAt: DateTime.now(),
          content: '',
        );
        notifyListeners();
      }

      await _messagesRef.doc(message.id).update({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'content': '',
      });
    } catch (e) {
      rethrow;
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
    _messagesSubscription?.cancel();
    _newMessagesSubscription?.cancel();
    _modificationsSubscription?.cancel();
    _offlineQueueSubscription?.cancel();
    _typingSubscription?.cancel();
    _contentCache.saveToDisk();
    _readReceiptService.dispose();
    _offlineQueue.dispose();
    _typingService.dispose();
    super.dispose();
  }
}
