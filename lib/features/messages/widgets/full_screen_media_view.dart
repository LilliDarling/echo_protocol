import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../services/crypto/media_encryption.dart';
import 'media_placeholders.dart';
import 'video_player_view.dart';

class FullScreenMediaView extends StatefulWidget {
  final String url;
  final String? thumbnailUrl;
  final String? decryptedThumbnailPath;
  final bool isVideo;
  final bool isEncrypted;
  final MediaEncryptionService? encryptionService;
  final String? mediaId;
  final Uint8List? mediaKey;

  const FullScreenMediaView({
    super.key,
    required this.url,
    required this.isVideo,
    this.thumbnailUrl,
    this.decryptedThumbnailPath,
    this.isEncrypted = false,
    this.encryptionService,
    this.mediaId,
    this.mediaKey,
  });

  @override
  State<FullScreenMediaView> createState() => _FullScreenMediaViewState();
}

class _FullScreenMediaViewState extends State<FullScreenMediaView> {
  bool _isDecrypting = false;
  bool _isLoadingFullResolution = false;
  bool _fullResolutionLoaded = false;
  String? _decryptedFilePath;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) _loadFullResolution();
  }

  Future<void> _loadFullResolution() async {
    if (_fullResolutionLoaded || _isLoadingFullResolution) return;

    setState(() => _isLoadingFullResolution = true);

    if (widget.isEncrypted &&
        widget.encryptionService != null &&
        widget.mediaId != null &&
        widget.mediaKey != null) {
      setState(() => _isDecrypting = true);
      try {
        final decryptedPath = await widget.encryptionService!.downloadAndDecrypt(
          encryptedUrl: widget.url,
          mediaId: widget.mediaId!,
          mediaKey: widget.mediaKey!,
          isVideo: widget.isVideo,
        );
        if (mounted) {
          setState(() {
            _decryptedFilePath = decryptedPath;
            _isDecrypting = false;
            _isLoadingFullResolution = false;
            _fullResolutionLoaded = true;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isDecrypting = false;
            _isLoadingFullResolution = false;
          });
        }
      }
    } else if (!widget.isVideo) {
      setState(() {
        _isLoadingFullResolution = false;
        _fullResolutionLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(child: _buildContent()),
    );
  }

  Widget _buildContent() {
    if (_isDecrypting) return MediaPlaceholders.decrypting();

    if (widget.isVideo) return _buildVideoPlayer();

    return _buildImageViewer();
  }

  Widget _buildVideoPlayer() {
    if (widget.isEncrypted && _decryptedFilePath != null) {
      return VideoPlayerView(filePath: _decryptedFilePath);
    }
    return VideoPlayerView(networkUrl: widget.url);
  }

  Widget _buildImageViewer() {
    if (_fullResolutionLoaded) return _buildFullResolutionImage();

    return GestureDetector(
      onTap: _loadFullResolution,
      child: Stack(
        alignment: Alignment.center,
        children: [
          InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: _buildThumbnailImage(),
          ),
          if (_isLoadingFullResolution || _isDecrypting)
            MediaPlaceholders.loadingOverlay(
              message: _isDecrypting ? 'Decrypting...' : 'Loading full image...',
            )
          else
            MediaPlaceholders.tapForFullResolution(),
        ],
      ),
    );
  }

  Widget _buildThumbnailImage() {
    if (widget.decryptedThumbnailPath != null) {
      return Image.file(
        File(widget.decryptedThumbnailPath!),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => MediaPlaceholders.thumbnailFallback(),
      );
    }

    if (widget.thumbnailUrl != null) {
      return CachedNetworkImage(
        imageUrl: widget.thumbnailUrl!,
        fit: BoxFit.contain,
        placeholder: (_, _) => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
        errorWidget: (_, _, _) => MediaPlaceholders.thumbnailFallback(),
      );
    }

    return MediaPlaceholders.thumbnailFallback();
  }

  Widget _buildFullResolutionImage() {
    if (widget.isEncrypted && _decryptedFilePath != null) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Image.file(
          File(_decryptedFilePath!),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Icon(
            Icons.broken_image,
            size: 64,
            color: Colors.white54,
          ),
        ),
      );
    }

    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: CachedNetworkImage(
        imageUrl: widget.url,
        fit: BoxFit.contain,
        placeholder: (_, _) => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
        errorWidget: (_, _, _) => const Icon(
          Icons.broken_image,
          size: 64,
          color: Colors.white54,
        ),
      ),
    );
  }
}
