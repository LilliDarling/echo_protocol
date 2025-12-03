import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/echo.dart';
import '../../services/partner_service.dart';
import '../../services/encryption.dart';
import '../../services/secure_storage.dart';
import '../../services/message_encryption_helper.dart';
import '../../services/message_rate_limiter.dart';
import '../../services/replay_protection_service.dart';
import '../../services/media_encryption_service.dart';
import '../../services/decrypted_content_cache.dart';
import '../settings/fingerprint_verification.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/message_input.dart';
import '../../widgets/date_separator.dart';

/// Main conversation screen for messaging with partner
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

  List<EchoModel> _messages = [];
  StreamSubscription? _messagesSubscription;
  StreamSubscription? _newMessagesSubscription;
  bool _isLoading = true;
  bool _isSending = false;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  DocumentSnapshot? _oldestMessageDoc;
  String? _error;

  static const int _pageSize = 30;

  String get _currentUserId => _auth.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _initializeServices();
    _loadInitialMessages();
    _markMessagesAsDelivered();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messagesSubscription?.cancel();
    _newMessagesSubscription?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _contentCache.saveToDisk();
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
    final prefs = await SharedPreferences.getInstance();
    _replayProtection = ReplayProtectionService(prefs);

    _contentCache = DecryptedContentCacheService(secureStorage: _secureStorage);
    await _contentCache.loadFromDisk();

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
      final query = _db
          .collection('messages')
          .where('conversationId', isEqualTo: widget.conversationId)
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

      final query = _db
          .collection('messages')
          .where('conversationId', isEqualTo: widget.conversationId)
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

  void _subscribeToNewMessages() {
    final newestTimestamp = _messages.isNotEmpty
        ? _messages.last.timestamp
        : DateTime.now();

    final query = _db
        .collection('messages')
        .where('conversationId', isEqualTo: widget.conversationId)
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
    final undelivered = await _db
        .collection('messages')
        .where('conversationId', isEqualTo: widget.conversationId)
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

  Future<void> _markVisibleMessagesAsRead() async {
    final unread = await _db
        .collection('messages')
        .where('conversationId', isEqualTo: widget.conversationId)
        .where('recipientId', isEqualTo: _currentUserId)
        .where('status', whereIn: ['sent', 'delivered'])
        .get();

    if (unread.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {
        'status': 'read',
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    await _db.collection('conversations').doc(widget.conversationId).update({
      'unreadCount.$_currentUserId': 0,
    });
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

    setState(() {
      _isSending = true;
      _error = null;
    });

    try {
      final rateLimitResult = await _rateLimiter.checkServerRateLimit(
        conversationId: widget.conversationId,
        recipientId: widget.partner.id,
      );

      if (!rateLimitResult.allowed) {
        final retrySeconds = (rateLimitResult.retryAfter.inSeconds);
        throw Exception(
          'Message rate limit exceeded. Please wait ${retrySeconds > 60 ? '${(retrySeconds / 60).ceil()} minutes' : '$retrySeconds seconds'}.',
        );
      }

      final encryptionResult = await _encryptionHelper.encryptMessage(
        plaintext: text,
        partnerId: widget.partner.id,
        senderId: _currentUserId,
      );

      final message = EchoModel(
        id: '',
        senderId: _currentUserId,
        recipientId: widget.partner.id,
        content: encryptionResult['content'] as String,
        timestamp: DateTime.now(),
        type: type,
        status: EchoStatus.sent,
        metadata: metadata ?? EchoMetadata.empty(),
        senderKeyVersion: encryptionResult['senderKeyVersion'] as int,
        recipientKeyVersion: encryptionResult['recipientKeyVersion'] as int,
        sequenceNumber: encryptionResult['sequenceNumber'] as int,
      );

      final docRef = await _db.collection('messages').add(message.toJson());
      _contentCache.put(docRef.id, text);

      await _db.collection('conversations').doc(widget.conversationId).update({
        'lastMessage': _truncateForPreview(text),
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unreadCount.${widget.partner.id}': FieldValue.increment(1),
      });

      _scrollToBottom();
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
          MessageInput(
            onSend: _sendMessage,
            isSending: _isSending,
            partnerId: widget.partner.id,
            mediaEncryptionService: _mediaEncryptionService,
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
