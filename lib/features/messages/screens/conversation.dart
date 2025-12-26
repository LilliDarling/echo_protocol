import 'package:flutter/material.dart';
import '../../../models/echo.dart';
import '../../../services/partner.dart';
import '../../settings/fingerprint_verification.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';
import '../widgets/date_separator.dart';
import '../widgets/typing_indicator.dart';
import '../widgets/message_options_sheet.dart';
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

  void _showMessageOptions(EchoModel message, String decryptedText) {
    if (message.senderId != _controller.currentUserId) return;
    if (message.isDeleted) return;

    MessageOptionsSheet.show(
      context,
      message: message,
      decryptedText: decryptedText,
      onEdit: _controller.editMessage,
      onDelete: _controller.deleteMessage,
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
        final message = _controller.messages[messageIndex];
        final isMe = message.senderId == _controller.currentUserId;
        final decryptedText = _controller.contentCache.get(message.id) ?? '...';

        Widget? dateSeparator;
        if (messageIndex == 0 ||
            !_isSameDay(_controller.messages[messageIndex - 1].timestamp, message.timestamp)) {
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
              mediaEncryptionService: _controller.mediaEncryptionService,
              onRetry: message.status.isFailed
                  ? () => _controller.offlineQueue.retry(message.id)
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
