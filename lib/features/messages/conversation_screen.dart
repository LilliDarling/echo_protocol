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

class _ConversationScreenState extends State<ConversationScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ScrollController _scrollController = ScrollController();

  late final EncryptionService _encryptionService;
  late final SecureStorageService _secureStorage;
  late final MessageEncryptionHelper _encryptionHelper;
  late final MessageRateLimiter _rateLimiter;
  late final ReplayProtectionService _replayProtection;
  MediaEncryptionService? _mediaEncryptionService;

  List<EchoModel> _messages = [];
  final Map<String, String> _decryptedContent = {};
  StreamSubscription? _messagesSubscription;
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;

  String get _currentUserId => _auth.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _subscribeToMessages();
    _markMessagesAsDelivered();
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeServices() async {
    _encryptionService = EncryptionService();
    _secureStorage = SecureStorageService();
    _rateLimiter = MessageRateLimiter();
    final prefs = await SharedPreferences.getInstance();
    _replayProtection = ReplayProtectionService(prefs);

    // Load user's private key
    final privateKey = await _secureStorage.getPrivateKey();
    if (privateKey != null) {
      final keyVersion = await _secureStorage.getCurrentKeyVersion();
      _encryptionService.setPrivateKey(privateKey, keyVersion: keyVersion);
    }

    // Set partner's public key
    _encryptionService.setPartnerPublicKey(widget.partner.publicKey);

    _encryptionHelper = MessageEncryptionHelper(
      encryptionService: _encryptionService,
      secureStorage: _secureStorage,
      replayProtection: _replayProtection,
      rateLimiter: _rateLimiter,
    );

    // Create media encryption service for encrypted file uploads/downloads
    _mediaEncryptionService = MediaEncryptionService(
      encryptionService: _encryptionService,
    );

    if (mounted) {
      setState(() {});
    }
  }

  void _subscribeToMessages() {
    final query = _db
        .collection('messages')
        .where('senderId', whereIn: [_currentUserId, widget.partner.id])
        .orderBy('timestamp', descending: false);

    _messagesSubscription = query.snapshots().listen(
      (snapshot) async {
        final messages = <EchoModel>[];
        for (final doc in snapshot.docs) {
          final message = EchoModel.fromFirestore(doc);
          // Only include messages between us and partner
          if ((message.senderId == _currentUserId &&
                  message.recipientId == widget.partner.id) ||
              (message.senderId == widget.partner.id &&
                  message.recipientId == _currentUserId)) {
            messages.add(message);
            // Decrypt if not already cached
            if (!_decryptedContent.containsKey(message.id)) {
              try {
                final decrypted = await _decryptMessage(message);
                _decryptedContent[message.id] = decrypted;
              } catch (e) {
                _decryptedContent[message.id] = '[Unable to decrypt message]';
              }
            }
          }
        }

        if (mounted) {
          setState(() {
            _messages = messages;
            _isLoading = false;
          });
          _scrollToBottom();
          _markVisibleMessagesAsRead();
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _error = error.toString();
            _isLoading = false;
          });
        }
      },
    );
  }

  Future<String> _decryptMessage(EchoModel message) async {
    return await _encryptionHelper.decryptMessage(
      message: message,
      myUserId: _currentUserId,
      partnerId: widget.partner.id,
    );
  }

  Future<void> _markMessagesAsDelivered() async {
    // Mark all unread messages from partner as delivered
    final undelivered = await _db
        .collection('messages')
        .where('senderId', isEqualTo: widget.partner.id)
        .where('recipientId', isEqualTo: _currentUserId)
        .where('status', isEqualTo: 'sent')
        .get();

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
    // Mark all delivered messages from partner as read
    final unread = await _db
        .collection('messages')
        .where('senderId', isEqualTo: widget.partner.id)
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

    // Reset unread count in conversation
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
      // Encrypt the message
      final encryptionResult = await _encryptionHelper.encryptMessage(
        plaintext: text,
        partnerId: widget.partner.id,
        senderId: _currentUserId,
      );

      // Create the message
      final message = EchoModel(
        id: '', // Will be set by Firestore
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

      // Save to Firestore
      final docRef = await _db.collection('messages').add(message.toJson());

      // Cache the decrypted content
      _decryptedContent[docRef.id] = text;

      // Update conversation
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
          // Error banner
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
          // Messages list
          Expanded(
            child: _buildMessagesList(),
          ),
          // Input field
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

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isMe = message.senderId == _currentUserId;
        final decryptedText = _decryptedContent[message.id] ?? '...';

        // Check if we need a date separator
        Widget? dateSeparator;
        if (index == 0 ||
            !_isSameDay(_messages[index - 1].timestamp, message.timestamp)) {
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
