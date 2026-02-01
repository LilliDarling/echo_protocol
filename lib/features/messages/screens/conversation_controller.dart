import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../../models/echo.dart';
import '../../../models/key_change_event.dart';
import '../../../services/partner.dart';
import '../../../services/crypto/protocol_service.dart';
import '../../../services/crypto/media_encryption.dart';
import '../../../services/secure_storage.dart';
import '../../../services/message_encryption_helper.dart';
import '../../../services/message_rate_limiter.dart';
import '../../../utils/decrypted_content_cache.dart';
import '../../../services/read_receipt.dart';
import '../../../services/offline_queue.dart';
import '../../../services/typing_indicator.dart';
import '../../../services/auto_delete.dart';

class ConversationController extends ChangeNotifier {
  final PartnerInfo partner;
  final String conversationId;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  late final ProtocolService _protocolService;
  late final SecureStorageService _secureStorage;
  late final MessageEncryptionHelper _encryptionHelper;
  late final MessageRateLimiter _rateLimiter;
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

  KeyChangeResult? _keyChangeResult;
  KeyChangeEvent? _pendingKeyChangeEvent;
  late final PartnerService _partnerService;

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

  void setTypingIndicatorEnabled(bool enabled) {
    _typingService.enabled = enabled;
  }

  Future<void> runAutoDelete(int autoDeleteDays) async {
    if (autoDeleteDays <= 0) return;

    final service = AutoDeleteService();
    final deleted = await service.deleteOldMessages(
      conversationId: conversationId,
      userId: currentUserId,
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

  CollectionReference<Map<String, dynamic>> get _messagesRef =>
      _db.collection('conversations').doc(conversationId).collection('messages');

  Future<int> _getNextSequenceNumber() async {
    final sortedIds = [currentUserId, partner.id]..sort();
    final conversationKey = '${sortedIds[0]}_${sortedIds[1]}';
    final docRef = _db
        .collection('users')
        .doc(currentUserId)
        .collection('message_sequences')
        .doc(conversationKey);

    return await _db.runTransaction<int>((transaction) async {
      final doc = await transaction.get(docRef);
      final lastSeq = (doc.data()?['lastSequence'] as num?)?.toInt() ?? 0;
      final nextSeq = lastSeq + 1;

      transaction.set(docRef, {
        'lastSequence': nextSeq,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return nextSeq;
    });
  }

  Future<void> initialize() async {
    await _initializeServices();
    await _loadInitialMessages();
    _markMessagesAsDelivered();
  }

  Future<void> _initializeServices() async {
    try {
      _protocolService = ProtocolService();
      _secureStorage = SecureStorageService();
      _rateLimiter = MessageRateLimiter();
      _partnerService = PartnerService();

      _contentCache = DecryptedContentCacheService(secureStorage: _secureStorage);
      await _contentCache.loadFromDisk();

      await _offlineQueue.initialize();
      _subscribeToOfflineQueue();
      _subscribeToTypingIndicator();

      await _protocolService.initializeFromStorage();

      _encryptionHelper = MessageEncryptionHelper(
        protocolService: _protocolService,
        rateLimiter: _rateLimiter,
      );

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
        recipientKeyVersion: partner.keyVersion,
      );

      final messageId = _messagesRef.doc().id;
      final timestamp = DateTime.now();
      final sequenceNumber = await _getNextSequenceNumber();

      final message = EchoModel(
        id: messageId,
        senderId: currentUserId,
        recipientId: partner.id,
        content: encryptionResult['content'] as String,
        timestamp: timestamp,
        type: type,
        status: EchoStatus.pending,
        metadata: metadata ?? EchoMetadata.empty(),
        senderKeyVersion: encryptionResult['senderKeyVersion'] as int,
        recipientKeyVersion: encryptionResult['recipientKeyVersion'] as int,
        sequenceNumber: sequenceNumber,
        conversationId: conversationId,
      );

      _contentCache.put(messageId, text);
      _messages = [..._messages, message];
      notifyListeners();

      if (!_offlineQueue.isOnline) {
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
        );
        return;
      }

      final result = await _functions.httpsCallable('sendMessage').call({
        'messageId': messageId,
        'conversationId': conversationId,
        'recipientId': partner.id,
        'content': encryptionResult['content'] as String,
        'sequenceNumber': sequenceNumber,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'senderKeyVersion': encryptionResult['senderKeyVersion'] as int,
        'recipientKeyVersion': encryptionResult['recipientKeyVersion'] as int,
        'type': type.value,
        'metadata': (metadata ?? EchoMetadata.empty()).toJson(),
        if (type == EchoType.image || type == EchoType.video)
          'mediaType': type.name,
        if (metadata?.fileUrl != null) 'mediaUrl': metadata!.fileUrl,
        if (metadata?.thumbnailUrl != null) 'thumbnailUrl': metadata!.thumbnailUrl,
      });

      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['success'] != true) {
        final error = data['error'] as String?;
        if (data['retryAfterMs'] != null) {
          final retryMs = (data['retryAfterMs'] as num).toInt();
          final retrySeconds = (retryMs / 1000).ceil();
          throw Exception(
            'Message rate limit exceeded. Please wait ${retrySeconds > 60 ? '${(retrySeconds / 60).ceil()} minutes' : '$retrySeconds seconds'}.',
          );
        }
        throw Exception(error ?? 'Failed to send message');
      }

      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(status: EchoStatus.sent);
        notifyListeners();
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
        recipientKeyVersion: partner.keyVersion,
      );

      _contentCache.put(message.id, newText);
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(
          content: encryptionResult['content'] as String,
          isEdited: true,
        );
        notifyListeners();
      }

      await _messagesRef.doc(message.id).update({
        'content': encryptionResult['content'],
        'isEdited': true,
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
          content: '',
        );
        notifyListeners();
      }

      await _deleteMediaFromStorage(message.metadata);

      await _messagesRef.doc(message.id).update({
        'isDeleted': true,
        'content': '',
        'metadata': {},
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _deleteMediaFromStorage(EchoMetadata metadata) async {
    final storage = FirebaseStorage.instance;
    final urls = [metadata.fileUrl, metadata.thumbnailUrl]
        .whereType<String>()
        .where((url) => url.isNotEmpty);

    for (final url in urls) {
      try {
        await storage.refFromURL(url).delete();
      } catch (_) {}
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
