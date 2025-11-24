import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/echo.dart';

/// Widget displaying a link preview card
class LinkPreviewWidget extends StatelessWidget {
  final LinkPreview linkPreview;
  final bool isMe;
  final bool compact;

  const LinkPreviewWidget({
    super.key,
    required this.linkPreview,
    required this.isMe,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompactPreview(context);
    }
    return _buildFullPreview(context);
  }

  Widget _buildFullPreview(BuildContext context) {
    return GestureDetector(
      onTap: () => _openUrl(linkPreview.imageUrl),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isMe
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.grey.shade300,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview image
            if (linkPreview.imageUrl.isNotEmpty)
              SizedBox(
                height: 140,
                width: double.infinity,
                child: CachedNetworkImage(
                  imageUrl: linkPreview.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Colors.grey.shade200,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey.shade200,
                    child: Icon(
                      Icons.link,
                      size: 48,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ),
              ),
            // Title and description
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    linkPreview.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isMe ? Colors.white : Colors.black87,
                    ),
                  ),
                  if (linkPreview.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      linkPreview.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isMe ? Colors.white70 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactPreview(BuildContext context) {
    return GestureDetector(
      onTap: () => _openUrl(linkPreview.imageUrl),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isMe
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            // Small image
            if (linkPreview.imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: CachedNetworkImage(
                    imageUrl: linkPreview.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.grey.shade200,
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey.shade200,
                      child: Icon(
                        Icons.link,
                        size: 24,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            // Title only
            Expanded(
              child: Text(
                linkPreview.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isMe ? Colors.white : Colors.black87,
                ),
              ),
            ),
            Icon(
              Icons.open_in_new,
              size: 16,
              color: isMe ? Colors.white70 : Colors.grey.shade500,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
