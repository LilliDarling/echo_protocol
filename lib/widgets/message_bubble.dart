import 'package:flutter/material.dart';
import '../models/echo.dart';
import '../services/media_encryption_service.dart';
import 'message_status.dart';
import 'media_message.dart';
import 'link_preview_widget.dart';

/// Widget displaying a single message bubble
class MessageBubble extends StatelessWidget {
  final EchoModel message;
  final String decryptedContent;
  final bool isMe;
  final String partnerName;
  final MediaEncryptionService? mediaEncryptionService;

  const MessageBubble({
    super.key,
    required this.message,
    required this.decryptedContent,
    required this.isMe,
    required this.partnerName,
    this.mediaEncryptionService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(
        left: isMe ? 48 : 0,
        right: isMe ? 0 : 48,
        top: 4,
        bottom: 4,
      ),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: isMe
                ? theme.primaryColor
                : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 16),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 16),
            ),
            child: _buildContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = isMe ? Colors.white : theme.textTheme.bodyLarge?.color;

    switch (message.type) {
      case EchoType.image:
      case EchoType.video:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            MediaMessage(
              message: message,
              isMe: isMe,
              encryptionService: mediaEncryptionService,
            ),
            if (decryptedContent.isNotEmpty && decryptedContent != '[Media]')
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Text(
                  decryptedContent,
                  style: TextStyle(color: textColor),
                ),
              ),
            _buildFooter(context),
          ],
        );

      case EchoType.link:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.metadata.linkPreview != null)
              LinkPreviewWidget(
                linkPreview: message.metadata.linkPreview!,
                isMe: isMe,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                decryptedContent,
                style: TextStyle(color: textColor),
              ),
            ),
            _buildFooter(context),
          ],
        );

      case EchoType.voice:
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.play_circle_filled,
                    color: isMe ? Colors.white : Colors.grey.shade700,
                    size: 36,
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 120,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isMe
                          ? Colors.white.withValues(alpha: 0.3)
                          : Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        'Voice message',
                        style: TextStyle(
                          fontSize: 12,
                          color: isMe ? Colors.white70 : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _buildFooter(context),
          ],
        );

      case EchoType.text:
        // Check if text contains a URL for link preview
        final hasUrl = _containsUrl(decryptedContent);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                decryptedContent,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                ),
              ),
            ),
            if (hasUrl && message.metadata.linkPreview != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: LinkPreviewWidget(
                  linkPreview: message.metadata.linkPreview!,
                  isMe: isMe,
                  compact: true,
                ),
              ),
            _buildFooter(context),
          ],
        );
    }
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            _formatTime(message.timestamp),
            style: TextStyle(
              fontSize: 11,
              color: isMe ? Colors.white70 : Colors.grey.shade500,
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 4),
            MessageStatus(status: message.status),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$hour12:$minute $period';
  }

  bool _containsUrl(String text) {
    final urlRegex = RegExp(
      r'https?://[^\s]+',
      caseSensitive: false,
    );
    return urlRegex.hasMatch(text);
  }
}
