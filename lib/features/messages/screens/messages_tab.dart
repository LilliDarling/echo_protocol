import 'package:flutter/material.dart';
import '../../../services/partner.dart';
import '../../../services/sync/sync_coordinator.dart';
import '../../../models/local/conversation.dart';
import 'partner_linking.dart';
import 'conversation.dart';

class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key});

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  final PartnerService _partnerService = PartnerService();
  final SyncCoordinator _syncCoordinator = SyncCoordinator();

  bool _isLoading = true;
  bool _hasInitializedEncryption = false;
  PartnerInfo? _partner;
  String? _conversationId;
  String? _error;
  LocalConversation? _cachedConversation;

  @override
  void initState() {
    super.initState();
    _loadPartnerInfo();
  }

  Future<void> _loadPartnerInfo() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final partner = await _partnerService.getPartner(forceRefresh: true);
      final conversationId = await _partnerService.getConversationId();

      if (partner != null && !_hasInitializedEncryption) {
        _hasInitializedEncryption = true;
        await _partnerService.initializePartnerEncryption();
      }

      if (conversationId != null) {
        await _loadCachedConversationData(conversationId);
      }

      if (mounted) {
        setState(() {
          _partner = partner;
          _conversationId = conversationId;
          _isLoading = false;
        });
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

  Future<void> _loadCachedConversationData(String conversationId) async {
    try {
      final conversations = await _syncCoordinator.getConversations();
      final cached = conversations.where((c) => c.id == conversationId).firstOrNull;
      if (cached != null && mounted) {
        setState(() {
          _cachedConversation = cached;
        });
      }
    } catch (_) {
      // Ignore cache errors
    }
  }

  void _onPartnerLinked() {
    _loadPartnerInfo();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(
                'Error loading partner info',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadPartnerInfo,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_partner == null) {
      return PartnerLinkingScreen(
        onPartnerLinked: _onPartnerLinked,
      );
    }

    return _ConversationPreview(
      partner: _partner!,
      conversationId: _conversationId!,
      cachedConversation: _cachedConversation,
    );
  }
}

class _ConversationPreview extends StatelessWidget {
  final PartnerInfo partner;
  final String conversationId;
  final LocalConversation? cachedConversation;

  const _ConversationPreview({
    required this.partner,
    required this.conversationId,
    this.cachedConversation,
  });

  String _truncatePreview(String text, {int maxLength = 50}) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  @override
  Widget build(BuildContext context) {
    String displayMessage;
    DateTime? lastMessageAt;
    int unreadCount;

    if (cachedConversation != null) {
      final content = cachedConversation!.lastMessageContent;
      displayMessage = content != null && content.isNotEmpty
          ? _truncatePreview(content)
          : 'Start a conversation';
      lastMessageAt = cachedConversation!.lastMessageAt;
      unreadCount = cachedConversation!.unreadCount;
    } else {
      displayMessage = 'Start a conversation';
      unreadCount = 0;
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              _buildConversationTile(
                context,
                lastMessage: displayMessage,
                lastMessageAt: lastMessageAt,
                unreadCount: unreadCount,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConversationTile(
    BuildContext context, {
    String? lastMessage,
    DateTime? lastMessageAt,
    int unreadCount = 0,
  }) {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ConversationScreen(
                partner: partner,
                conversationId: conversationId,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.pink.shade100,
                backgroundImage: partner.avatar != null
                    ? NetworkImage(partner.avatar!)
                    : null,
                child: partner.avatar == null
                    ? Text(
                        partner.name.isNotEmpty
                            ? partner.name[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.pink.shade700,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            partner.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (lastMessageAt != null)
                          Text(
                            _formatTimestamp(lastMessageAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lastMessage ?? 'Start a conversation',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: lastMessage != null
                                  ? Colors.grey.shade700
                                  : Colors.grey.shade400,
                              fontStyle: lastMessage == null
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                          ),
                        ),
                        if (unreadCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : unreadCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inDays == 0) {
      final hour = timestamp.hour;
      final minute = timestamp.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$hour12:$minute $period';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[timestamp.weekday - 1];
    } else {
      return '${timestamp.month}/${timestamp.day}';
    }
  }
}
