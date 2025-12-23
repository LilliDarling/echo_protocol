import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/echo.dart';
import '../services/media_encryption_service.dart';
import 'message_status.dart';
import 'media_message.dart';
import 'link_preview_widget.dart';

class MessageBubble extends StatelessWidget {
  final EchoModel message;
  final String decryptedContent;
  final bool isMe;
  final String partnerName;
  final MediaEncryptionService? mediaEncryptionService;
  final VoidCallback? onRetry;
  final VoidCallback? onLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    required this.decryptedContent,
    required this.isMe,
    required this.partnerName,
    this.mediaEncryptionService,
    this.onRetry,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isFailed = message.status.isFailed;

    if (message.isDeleted) {
      return _buildDeletedMessage(context, isDark);
    }

    Widget bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      decoration: BoxDecoration(
        color: isMe
            ? (isFailed ? Colors.red.shade700 : theme.primaryColor)
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
    );

    if (isFailed && onRetry != null) {
      bubble = GestureDetector(
        onTap: onRetry,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            bubble,
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: Text(
                'Tap to retry',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.red.shade400,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (isMe && onLongPress != null) {
      bubble = GestureDetector(
        onLongPress: onLongPress,
        child: bubble,
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: isMe ? 48 : 0,
        right: isMe ? 0 : 48,
        top: 4,
        bottom: 4,
      ),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: bubble,
      ),
    );
  }

  Widget _buildDeletedMessage(BuildContext context, bool isDark) {
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 16),
            ),
            border: Border.all(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.block,
                size: 16,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 8),
              Text(
                'This message was deleted',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                  fontSize: 14,
                ),
              ),
            ],
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

      case EchoType.gif:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 250,
                maxHeight: 250,
              ),
              child: CachedNetworkImage(
                imageUrl: message.metadata.fileUrl ?? '',
                placeholder: (context, url) => Container(
                  width: 150,
                  height: 150,
                  color: Colors.grey.shade300,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  width: 150,
                  height: 100,
                  color: Colors.grey.shade300,
                  child: const Center(
                    child: Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
                fit: BoxFit.contain,
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
          if (message.isEdited) ...[
            Text(
              'edited',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: isMe ? Colors.white60 : Colors.grey.shade400,
              ),
            ),
            const SizedBox(width: 4),
          ],
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
