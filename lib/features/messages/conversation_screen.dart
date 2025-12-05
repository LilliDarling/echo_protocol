import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/echo.dart';
import '../../services/partner_service.dart';
import '../../services/encryption.dart';
import '../../services/secure_storage.dart';
import '../../services/message_encryption_helper.dart';
import '../../services/message_rate_limiter.dart';
import '../../services/replay_protection_service.dart';
import '../../services/media_encryption_service.dart';
import '../../services/decrypted_content_cache.dart';
import '../../services/read_receipt_service.dart';
import '../../services/offline_queue_service.dart';
import '../../services/typing_indicator_service.dart';
import '../settings/fingerprint_verification.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/message_input.dart';
import '../../widgets/date_separator.dart';
import '../../widgets/typing_indicator.dart';

class ConversationScreen extends StatefulWidget {
  final PartnerInfo partner;
  final String conversationId;

  const ConversationScreen({
    super.key,
    required this.partner,
    required this.conversationId,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with WidgetsBindingObserver {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ScrollController _scrollController = ScrollController();

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
  StreamSubscription? _offlineQueueSubscription;
  bool _isLoading = true;
  bool _isSending = false;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  DocumentSnapshot? _oldestMessageDoc;
  String? _error;
  bool _isPartnerTyping = false;

  static const int _pageSize = 30;

  String get _currentUserId => _auth.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _messagesRef =>
      _db.collection('conversations').doc(widget.conversationId).collection('messages');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _readReceiptService = ReadReceiptService(
      conversationId: widget.conversationId,
      currentUserId: _currentUserId,
    );
    _offlineQueue = OfflineQueueService();
    _typingService = TypingIndicatorService(
      conversationId: widget.conversationId,
      currentUserId: _currentUserId,
    );
    _initializeServices();
    _loadInitialMessages();
    _markMessagesAsDelivered();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messagesSubscription?.cancel();
    _newMessagesSubscription?.cancel();
    _offlineQueueSubscription?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _contentCache.saveToDisk();
    _readReceiptService.dispose();
    _offlineQueue.dispose();
    _typingService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _contentCache.saveToDisk();
    }
  }

  Future<void> _initializeServices() async {
    _encryptionService = EncryptionService();
    _secureStorage = SecureStorageService();
    _rateLimiter = MessageRateLimiter();
    _replayProtection = ReplayProtectionService(userId: _currentUserId);

    _contentCache = DecryptedContentCacheService(secureStorage: _secureStorage);
    await _contentCache.loadFromDisk();

    await _offlineQueue.initialize();
    _subscribeToOfflineQueue();
    _subscribeToTypingIndicator();

    final privateKey = await _secureStorage.getPrivateKey();
    if (privateKey != null) {
      final keyVersion = await _secureStorage.getCurrentKeyVersion();
      _encryptionService.setPrivateKey(privateKey, keyVersion: keyVersion);
    }

    _encryptionService.setPartnerPublicKey(widget.partner.publicKey);

    _encryptionHelper = MessageEncryptionHelper(
      encryptionService: _encryptionService,
      secureStorage: _secureStorage,
      replayProtection: _replayProtection,
      rateLimiter: _rateLimiter,
    );

    _mediaEncryptionService = MediaEncryptionService(
      encryptionService: _encryptionService,
    );

    if (mounted) {
      setState(() {});
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels <=
            _scrollController.position.minScrollExtent + 100 &&
        !_isLoadingMore &&
        _hasMoreMessages) {
      _loadMoreMessages();
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

      if (mounted) {
        setState(() {
          _messages = messages.reversed.toList();
          _isLoading = false;
        });
        _scrollToBottom();
        _subscribeToNewMessages();
        _markVisibleMessagesAsRead();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages || _oldestMessageDoc == null) return;

    setState(() => _isLoadingMore = true);

    try {
      final scrollOffset = _scrollController.position.pixels;
      final maxScrollBefore = _scrollController.position.maxScrollExtent;

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

      if (mounted && olderMessages.isNotEmpty) {
        setState(() {
          _messages = [...olderMessages.reversed, ..._messages];
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            final maxScrollAfter = _scrollController.position.maxScrollExtent;
            final scrollDelta = maxScrollAfter - maxScrollBefore;
            _scrollController.jumpTo(scrollOffset + scrollDelta);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to load older messages');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _subscribeToOfflineQueue() {
    _offlineQueueSubscription = _offlineQueue.statusStream.listen((updates) {
      if (!mounted) return;

      for (final entry in updates.entries) {
        final messageId = entry.key;
        final pending = entry.value;

        if (pending.conversationId != widget.conversationId) continue;

        final index = _messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          setState(() {
            _messages[index] = pending.toEchoModel();
          });
        }
      }
    });
  }

  void _subscribeToTypingIndicator() {
    _typingService.startListening();
    _typingService.partnerTypingStream.listen((isTyping) {
      if (!mounted) return;
      setState(() => _isPartnerTyping = isTyping);
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
              if (mounted) {
                setState(() => _messages = [..._messages, message]);
                _scrollToBottom();
                _markVisibleMessagesAsRead();
              }
            }
          } else if (change.type == DocumentChangeType.modified) {
            final message = EchoModel.fromFirestore(change.doc);
            if (mounted) {
              setState(() {
                final index = _messages.indexWhere((m) => m.id == message.id);
                if (index != -1) {
                  _messages[index] = message;
                }
              });
            }
          }
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() => _error = error.toString());
        }
      },
    );
  }

  Future<void> _cacheDecryptedContent(EchoModel message) async {
    if (!_contentCache.contains(message.id)) {
      try {
        final decrypted = await _decryptMessage(message);
        _contentCache.put(message.id, decrypted);
      } catch (e) {
        _contentCache.put(message.id, '[Unable to decrypt message]');
      }
    }
  }

  Future<String> _decryptMessage(EchoModel message) async {
    return await _encryptionHelper.decryptMessage(
      message: message,
      myUserId: _currentUserId,
      partnerId: widget.partner.id,
    );
  }

  Future<void> _markMessagesAsDelivered() async {
    final undelivered = await _messagesRef
        .where('recipientId', isEqualTo: _currentUserId)
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

  void _markVisibleMessagesAsRead() {
    final unreadIds = _messages
        .where((m) =>
            m.recipientId == _currentUserId &&
            m.status != EchoStatus.read)
        .map((m) => m.id)
        .toList();

    if (unreadIds.isNotEmpty) {
      _readReceiptService.markMultipleAsRead(unreadIds);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> _sendMessage(String text, {EchoType type = EchoType.text, EchoMetadata? metadata}) async {
    if (text.trim().isEmpty && type == EchoType.text) return;

    _typingService.stopTyping();

    setState(() {
      _isSending = true;
      _error = null;
    });

    try {
      final encryptionResult = await _encryptionHelper.encryptMessage(
        plaintext: text,
        partnerId: widget.partner.id,
        senderId: _currentUserId,
      );

      final messageId = _messagesRef.doc().id;
      final timestamp = DateTime.now();
      final sequenceNumber = encryptionResult['sequenceNumber'] as int;

      String? validationToken;
      bool useOfflineQueue = false;

      try {
        final validationResult = await _replayProtection.validateMessageServerSide(
          messageId: messageId,
          conversationId: widget.conversationId,
          recipientId: widget.partner.id,
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
        senderId: _currentUserId,
        recipientId: widget.partner.id,
        content: encryptionResult['content'] as String,
        timestamp: timestamp,
        type: type,
        status: useOfflineQueue ? EchoStatus.pending : EchoStatus.sent,
        metadata: metadata ?? EchoMetadata.empty(),
        senderKeyVersion: encryptionResult['senderKeyVersion'] as int,
        recipientKeyVersion: encryptionResult['recipientKeyVersion'] as int,
        sequenceNumber: sequenceNumber,
        validationToken: validationToken,
        conversationId: widget.conversationId,
      );

      _contentCache.put(messageId, text);
      setState(() => _messages = [..._messages, message]);
      _scrollToBottom();

      if (useOfflineQueue) {
        await _offlineQueue.enqueue(
          messageId: messageId,
          conversationId: widget.conversationId,
          senderId: _currentUserId,
          recipientId: widget.partner.id,
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

        await _db.collection('conversations').doc(widget.conversationId).update({
          'lastMessage': _truncateForPreview(text),
          'lastMessageAt': FieldValue.serverTimestamp(),
          'unreadCount.${widget.partner.id}': FieldValue.increment(1),
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $_error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  String _truncateForPreview(String text) {
    const maxLength = 50;
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  Future<void> _editMessage(EchoModel message, String newText) async {
    if (newText.trim().isEmpty) return;
    if (message.senderId != _currentUserId) return;
    if (message.isDeleted) return;

    try {
      final encryptionResult = await _encryptionHelper.encryptMessage(
        plaintext: newText,
        partnerId: widget.partner.id,
        senderId: _currentUserId,
      );

      await _messagesRef.doc(message.id).update({
        'content': encryptionResult['content'],
        'isEdited': true,
        'editedAt': FieldValue.serverTimestamp(),
      });

      _contentCache.put(message.id, newText);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to edit message: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteMessage(EchoModel message) async {
    if (message.senderId != _currentUserId) return;
    if (message.isDeleted) return;

    try {
      await _messagesRef.doc(message.id).update({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'content': '',
      });

      _contentCache.remove(message.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete message: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showMessageOptions(EchoModel message, String decryptedText) {
    if (message.senderId != _currentUserId) return;
    if (message.isDeleted) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.type == EchoType.text)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit message'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditDialog(message, decryptedText);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete message', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirmation(message);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(EchoModel message, String currentText) {
    final controller = TextEditingController(text: currentText);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          maxLines: null,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter new message',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _editMessage(message, controller.text);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(EchoModel message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message'),
        content: const Text('This message will be deleted for everyone. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMessage(message);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _openSecurityVerification() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FingerprintVerificationScreen(
          userId: widget.partner.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.pink.shade100,
              backgroundImage: widget.partner.avatar != null
                  ? NetworkImage(widget.partner.avatar!)
                  : null,
              child: widget.partner.avatar == null
                  ? Text(
                      widget.partner.name.isNotEmpty
                          ? widget.partner.name[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.pink.shade700,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.partner.name,
                    style: const TextStyle(fontSize: 16),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.lock,
                        size: 12,
                        color: Colors.green.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'End-to-end encrypted',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.verified_user),
            tooltip: 'Verify Security Code',
            onPressed: _openSecurityVerification,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.red.shade100,
              child: Row(
                children: [
                  Icon(Icons.error, color: Colors.red.shade700, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => setState(() => _error = null),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _buildMessagesList(),
          ),
          if (_isPartnerTyping)
            TypingIndicator(partnerName: widget.partner.name),
          MessageInput(
            onSend: _sendMessage,
            isSending: _isSending,
            partnerId: widget.partner.id,
            mediaEncryptionService: _mediaEncryptionService,
            onTextChanged: _typingService.onTextChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Send a message to start the conversation',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      );
    }

    final itemCount = _messages.length + (_isLoadingMore ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (_isLoadingMore && index == 0) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final messageIndex = _isLoadingMore ? index - 1 : index;
        final message = _messages[messageIndex];
        final isMe = message.senderId == _currentUserId;
        final decryptedText = _contentCache.get(message.id) ?? '...';

        Widget? dateSeparator;
        if (messageIndex == 0 ||
            !_isSameDay(_messages[messageIndex - 1].timestamp, message.timestamp)) {
          dateSeparator = DateSeparator(date: message.timestamp);
        }

        return Column(
          children: [
            if (dateSeparator != null) dateSeparator,
            MessageBubble(
              message: message,
              decryptedContent: decryptedText,
              isMe: isMe,
              partnerName: widget.partner.name,
              mediaEncryptionService: _mediaEncryptionService,
              onRetry: message.status.isFailed
                  ? () => _offlineQueue.retry(message.id)
                  : null,
              onLongPress: isMe && !message.isDeleted
                  ? () => _showMessageOptions(message, decryptedText)
                  : null,
            ),
          ],
        );
      },
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
