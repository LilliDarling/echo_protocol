import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../services/partner.dart';
import 'partner_linking.dart';
import 'conversation.dart';

class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key});

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  final PartnerService _partnerService = PartnerService();

  bool _isLoading = true;
  bool _hasInitializedEncryption = false;
  PartnerInfo? _partner;
  String? _conversationId;
  String? _error;

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
    );
  }
}

class _ConversationPreview extends StatelessWidget {
  final PartnerInfo partner;
  final String conversationId;

  const _ConversationPreview({
    required this.partner,
    required this.conversationId,
  });

  String _decryptPreview(String? encryptedMessage) {
    if (encryptedMessage == null || encryptedMessage.isEmpty) {
      return 'Start a conversation';
    }
    return 'Tap to view message';
  }

  String _truncatePreview(String text, {int maxLength = 50}) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .snapshots(),
      builder: (context, snapshot) {
        final conversationData = snapshot.data?.data() as Map<String, dynamic>?;
        final lastMessageEncrypted = conversationData?['lastMessage'] as String?;
        final lastMessageAt = conversationData?['lastMessageAt'] as Timestamp?;
        final unreadCounts =
            conversationData?['unreadCount'] as Map<String, dynamic>?;
        final myUnreadCount = unreadCounts?[currentUserId] as int? ?? 0;
        final decryptedPreview = _decryptPreview(lastMessageEncrypted);
        final displayMessage = _truncatePreview(decryptedPreview);

        return Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  _buildConversationTile(
                    context,
                    lastMessage: displayMessage,
                    lastMessageAt: lastMessageAt,
                    unreadCount: myUnreadCount,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildConversationTile(
    BuildContext context, {
    String? lastMessage,
    Timestamp? lastMessageAt,
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
              // Partner avatar
              Stack(
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
                  if (partner.isOnline)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
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
                            _formatTimestamp(lastMessageAt.toDate()),
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
