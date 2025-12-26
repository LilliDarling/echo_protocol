import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/echo.dart';
import '../../../services/media_encryption.dart';
import 'media_placeholders.dart';
import 'full_screen_media_view.dart';

class MediaMessage extends StatefulWidget {
  final EchoModel message;
  final bool isMe;
  final MediaEncryptionService? encryptionService;

  const MediaMessage({
    super.key,
    required this.message,
    required this.isMe,
    this.encryptionService,
  });

  @override
  State<MediaMessage> createState() => _MediaMessageState();
}

class _MediaMessageState extends State<MediaMessage> {
  String? _decryptedThumbnailPath;
  bool _isDecrypting = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    final thumbnailUrl = widget.message.metadata.thumbnailUrl;
    if (thumbnailUrl == null || thumbnailUrl.isEmpty) return;

    if (widget.message.metadata.isEncrypted && widget.encryptionService != null) {
      setState(() => _isDecrypting = true);
      try {
        final fileId = MediaEncryptionService.generateFileId(thumbnailUrl);
        final decryptedPath = await widget.encryptionService!.getDecryptedMedia(
          encryptedUrl: thumbnailUrl,
          fileId: '${fileId}_thumb',
          isVideo: false,
        );
        if (mounted) {
          setState(() {
            _decryptedThumbnailPath = decryptedPath;
            _isDecrypting = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _isDecrypting = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileUrl = widget.message.metadata.fileUrl;
    final thumbnailUrl = widget.message.metadata.thumbnailUrl;

    if (fileUrl == null && thumbnailUrl == null) {
      return MediaPlaceholders.forType(widget.message.type);
    }

    return GestureDetector(
      onTap: () => _openFullScreen(context),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 250, maxWidth: 250),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            alignment: Alignment.center,
            children: [
              _buildThumbnail(thumbnailUrl, fileUrl),
              if (widget.message.type == EchoType.video)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(String? thumbnailUrl, String? fileUrl) {
    if (_isDecrypting) return MediaPlaceholders.loading();
    if (_hasError) return MediaPlaceholders.error();

    if (widget.message.metadata.isEncrypted && _decryptedThumbnailPath != null) {
      return Image.file(
        File(_decryptedThumbnailPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => MediaPlaceholders.error(),
      );
    }

    if (widget.message.metadata.isEncrypted && widget.encryptionService == null) {
      return MediaPlaceholders.encrypted();
    }

    return CachedNetworkImage(
      imageUrl: thumbnailUrl ?? fileUrl!,
      fit: BoxFit.cover,
      placeholder: (_, _) => MediaPlaceholders.loading(),
      errorWidget: (_, _, _) => MediaPlaceholders.error(),
    );
  }

  void _openFullScreen(BuildContext context) {
    final fileUrl = widget.message.metadata.fileUrl;
    if (fileUrl == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FullScreenMediaView(
          url: fileUrl,
          thumbnailUrl: widget.message.metadata.thumbnailUrl,
          decryptedThumbnailPath: _decryptedThumbnailPath,
          isVideo: widget.message.type == EchoType.video,
          isEncrypted: widget.message.metadata.isEncrypted,
          encryptionService: widget.encryptionService,
        ),
      ),
    );
  }
}
