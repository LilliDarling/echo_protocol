import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../models/echo.dart';
import '../../../models/local/message.dart';
import '../../../services/partner.dart';
import '../../settings/fingerprint_verification.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';
import '../widgets/date_separator.dart';
import '../widgets/typing_indicator.dart';
import 'conversation_controller.dart';

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
  late final ConversationController _controller;
  final ScrollController _scrollController = ScrollController();

  bool _preferencesApplied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = ConversationController(
      partner: widget.partner,
      conversationId: widget.conversationId,
    );
    _scrollController.addListener(_onScroll);
    _controller.addListener(_onControllerUpdate);
    _controller.initialize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_preferencesApplied) {
      final prefs = Provider.of<ThemeProvider>(context, listen: false).preferences;
      _controller.setTypingIndicatorEnabled(prefs.showTypingIndicator);
      _controller.runAutoDelete(prefs.autoDeleteDays);
      _preferencesApplied = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _controller.saveCache();
    }
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_scrollController.position.pixels <=
            _scrollController.position.minScrollExtent + 100 &&
        !_controller.isLoadingMore &&
        _controller.hasMoreMessages) {
      final scrollOffset = _scrollController.position.pixels;
      final maxScrollBefore = _scrollController.position.maxScrollExtent;
      _controller.loadMoreMessages(scrollOffset, maxScrollBefore).then((_) {
        _maintainScrollPosition(scrollOffset, maxScrollBefore);
      });
    }
  }

  void _maintainScrollPosition(double scrollOffset, double maxScrollBefore) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final maxScrollAfter = _scrollController.position.maxScrollExtent;
        final scrollDelta = maxScrollAfter - maxScrollBefore;
        _scrollController.jumpTo(scrollOffset + scrollDelta);
      }
    });
  }

  void _scrollToBottom({bool immediate = false}) {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted || !_scrollController.hasClients) return;

      final maxExtent = _scrollController.position.maxScrollExtent;
      if (maxExtent <= 0) return;

      if (immediate) {
        _scrollController.jumpTo(maxExtent);
      } else {
        _scrollController.animateTo(
          maxExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSend(String text, {EchoType type = EchoType.text, EchoMetadata? metadata}) async {
    try {
      await _controller.sendMessage(text, type: type, metadata: metadata);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: ${_controller.error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showMessageOptions(LocalMessage message) {
    if (message.senderId != _controller.currentUserId) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(context);
                _controller.deleteMessage(EchoModel(
                  id: message.id,
                  senderId: message.senderId,
                  recipientId: '',
                  content: '',
                  timestamp: message.timestamp,
                  type: EchoType.text,
                  status: EchoStatus.sent,
                  metadata: EchoMetadata.empty(),
                  conversationId: message.conversationId,
                  senderKeyVersion: 1,
                  recipientKeyVersion: 1,
                  sequenceNumber: 0,
                ));
              },
            ),
          ],
        ),
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
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildErrorBanner(),
          _buildKeyChangeBanner(),
          Expanded(child: _buildMessagesList()),
          if (_controller.isPartnerTyping)
            TypingIndicator(partnerName: widget.partner.name),
          MessageInput(
            onSend: _handleSend,
            isSending: _controller.isSending || !_controller.isServicesInitialized,
            partnerId: widget.partner.id,
            mediaEncryptionService: _controller.mediaEncryptionService,
            onTextChanged: _controller.isServicesInitialized
                ? _controller.typingService.onTextChanged
                : null,
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
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
    );
  }

  Widget _buildErrorBanner() {
    if (_controller.error == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      color: Colors.red.shade100,
      child: Row(
        children: [
          Icon(Icons.error, color: Colors.red.shade700, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _controller.error!,
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: _controller.clearError,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyChangeBanner() {
    if (!_controller.hasKeyChangeWarning) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: Colors.orange.shade100,
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Security code changed',
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Verify with ${widget.partner.name} that this is expected',
                  style: TextStyle(color: Colors.orange.shade800, fontSize: 11),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _showKeyChangeDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'View',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showKeyChangeDialog() {
    final result = _controller.keyChangeResult;
    if (result == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.security, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Text('Security Code Changed'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${widget.partner.name}\'s security code has changed. '
                'This could mean they reinstalled the app or got a new device.',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              const Text(
                'Previous code:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  result.previousFingerprint ?? 'Unknown',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'New code:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Text(
                  result.currentFingerprint,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Verify this code matches what ${widget.partner.name} sees '
                        'in their security settings.',
                        style: TextStyle(fontSize: 11, color: Colors.blue.shade800),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _controller.acknowledgeKeyChange();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
            ),
            child: const Text('I Verified - Accept'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_controller.messages.isEmpty) {
      return _buildEmptyState();
    }

    final itemCount = _controller.messages.length + (_controller.isLoadingMore ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (_controller.isLoadingMore && index == 0) {
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

        final messageIndex = _controller.isLoadingMore ? index - 1 : index;
        final localMessage = _controller.messages[messageIndex];
        final isMe = localMessage.senderId == _controller.currentUserId;

        Widget? dateSeparator;
        if (messageIndex == 0 ||
            !_isSameDay(_controller.messages[messageIndex - 1].timestamp, localMessage.timestamp)) {
          dateSeparator = DateSeparator(date: localMessage.timestamp);
        }

        final echoMessage = _localToEcho(localMessage);

        return Column(
          children: [
            if (dateSeparator != null) dateSeparator,
            MessageBubble(
              message: echoMessage,
              decryptedContent: localMessage.content,
              isMe: isMe,
              partnerName: widget.partner.name,
              mediaEncryptionService: _controller.mediaEncryptionService,
              myUserId: _controller.currentUserId,
              onRetry: localMessage.status == LocalMessageStatus.failed
                  ? () => _controller.offlineQueue.retry(localMessage.id)
                  : null,
              onLongPress: isMe
                  ? () => _showMessageOptions(localMessage)
                  : null,
            ),
          ],
        );
      },
    );
  }

  EchoModel _localToEcho(LocalMessage local) {
    return EchoModel(
      id: local.id,
      senderId: local.senderId,
      recipientId: local.isOutgoing ? widget.partner.id : _controller.currentUserId,
      content: '',
      timestamp: local.timestamp,
      type: _convertType(local.type),
      status: _convertStatus(local.status),
      metadata: EchoMetadata(
        mediaId: local.mediaId,
        thumbnailUrl: local.thumbnailPath,
      ),
      conversationId: local.conversationId,
      senderKeyVersion: 1,
      recipientKeyVersion: 1,
      sequenceNumber: 0,
    );
  }

  EchoType _convertType(LocalMessageType type) {
    switch (type) {
      case LocalMessageType.text:
        return EchoType.text;
      case LocalMessageType.image:
        return EchoType.image;
      case LocalMessageType.video:
        return EchoType.video;
      case LocalMessageType.voice:
        return EchoType.voice;
      case LocalMessageType.link:
        return EchoType.link;
      case LocalMessageType.gif:
        return EchoType.gif;
    }
  }

  EchoStatus _convertStatus(LocalMessageStatus status) {
    switch (status) {
      case LocalMessageStatus.pending:
        return EchoStatus.pending;
      case LocalMessageStatus.sent:
        return EchoStatus.sent;
      case LocalMessageStatus.delivered:
        return EchoStatus.delivered;
      case LocalMessageStatus.read:
        return EchoStatus.read;
      case LocalMessageStatus.failed:
        return EchoStatus.failed;
    }
  }

  Widget _buildEmptyState() {
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

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
