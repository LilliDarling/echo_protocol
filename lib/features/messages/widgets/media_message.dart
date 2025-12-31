import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/echo.dart';
import '../../../services/crypto/media_encryption.dart';
import 'media_placeholders.dart';
import 'full_screen_media_view.dart';

class MediaMessage extends StatefulWidget {
  final EchoModel message;
  final bool isMe;
  final MediaEncryptionService? encryptionService;
  final String? myUserId;
  final String? decryptedContent;

  const MediaMessage({
    super.key,
    required this.message,
    required this.isMe,
    this.encryptionService,
    this.myUserId,
    this.decryptedContent,
  });

  @override
  State<MediaMessage> createState() => _MediaMessageState();
}

class _MediaMessageState extends State<MediaMessage> {
  Uint8List? _decryptedThumbnailBytes;
  bool _isDecrypting = false;
  bool _hasError = false;
  Uint8List? _mediaKey;
  Uint8List? _thumbKey;

  @override
  void initState() {
    super.initState();
    _parseKeys();
    _loadMedia();
  }

  void _parseKeys() {
    if (widget.decryptedContent == null) return;
    try {
      final data = jsonDecode(widget.decryptedContent!) as Map<String, dynamic>;
      if (data['mediaKey'] != null) {
        _mediaKey = base64Decode(data['mediaKey'] as String);
      }
      if (data['thumbKey'] != null) {
        _thumbKey = base64Decode(data['thumbKey'] as String);
      }
    } catch (_) {
    }
  }

  Future<void> _loadMedia() async {
    final thumbnailUrl = widget.message.metadata.thumbnailUrl;
    if (thumbnailUrl == null || thumbnailUrl.isEmpty) return;

    if (widget.message.metadata.isEncrypted &&
        widget.encryptionService != null) {
      final thumbMediaId = widget.message.metadata.thumbMediaId;
      if (thumbMediaId == null || _thumbKey == null) {
        setState(() => _hasError = true);
        return;
      }

      setState(() => _isDecrypting = true);
      try {
        final decryptedBytes = await widget.encryptionService!.downloadAndDecryptToMemory(
          encryptedUrl: thumbnailUrl,
          mediaId: thumbMediaId,
          mediaKey: _thumbKey!,
        );
        if (mounted) {
          setState(() {
            _decryptedThumbnailBytes = decryptedBytes;
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

    if (widget.message.metadata.isEncrypted && _decryptedThumbnailBytes != null) {
      return Image.memory(
        _decryptedThumbnailBytes!,
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
          decryptedThumbnailBytes: _decryptedThumbnailBytes,
          isVideo: widget.message.type == EchoType.video,
          isEncrypted: widget.message.metadata.isEncrypted,
          encryptionService: widget.encryptionService,
          mediaId: widget.message.metadata.mediaId,
          mediaKey: _mediaKey,
        ),
      ),
    );
  }
}
