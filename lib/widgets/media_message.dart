import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../models/echo.dart';
import '../services/media_encryption_service.dart';

/// Widget displaying media (image/video) messages
/// Supports both encrypted and unencrypted media
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

    // If encrypted, we need to decrypt
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
      return _buildPlaceholder();
    }

    return GestureDetector(
      onTap: () => _openFullScreen(context),
      child: Container(
        constraints: const BoxConstraints(
          maxHeight: 250,
          maxWidth: 250,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Image - use decrypted path if encrypted, otherwise use network
              _buildThumbnail(thumbnailUrl, fileUrl),
              // Video play button overlay
              if (widget.message.type == EchoType.video)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(String? thumbnailUrl, String? fileUrl) {
    // Show loading if decrypting
    if (_isDecrypting) {
      return _buildLoadingPlaceholder();
    }

    // Show error if decryption failed
    if (_hasError) {
      return _buildErrorPlaceholder();
    }

    // If encrypted and we have decrypted path, use file image
    if (widget.message.metadata.isEncrypted && _decryptedThumbnailPath != null) {
      return Image.file(
        File(_decryptedThumbnailPath!),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildErrorPlaceholder(),
      );
    }

    // If encrypted but no encryption service, show placeholder with lock
    if (widget.message.metadata.isEncrypted && widget.encryptionService == null) {
      return _buildEncryptedPlaceholder();
    }

    // Unencrypted - use cached network image as before
    return CachedNetworkImage(
      imageUrl: thumbnailUrl ?? fileUrl!,
      fit: BoxFit.cover,
      placeholder: (context, url) => _buildLoadingPlaceholder(),
      errorWidget: (context, url, error) => _buildErrorPlaceholder(),
    );
  }

  Widget _buildEncryptedPlaceholder() {
    return Container(
      width: 200,
      height: 150,
      color: Colors.grey.shade300,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock,
            size: 48,
            color: Colors.grey.shade500,
          ),
          const SizedBox(height: 8),
          Text(
            'Encrypted',
            style: TextStyle(
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 200,
      height: 150,
      color: Colors.grey.shade300,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.message.type == EchoType.video ? Icons.videocam : Icons.image,
            size: 48,
            color: Colors.grey.shade500,
          ),
          const SizedBox(height: 8),
          Text(
            widget.message.type == EchoType.video ? 'Video' : 'Image',
            style: TextStyle(
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingPlaceholder() {
    return Container(
      width: 200,
      height: 150,
      color: Colors.grey.shade200,
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _buildErrorPlaceholder() {
    return Container(
      width: 200,
      height: 150,
      color: Colors.grey.shade200,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 8),
          Text(
            'Failed to load',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  void _openFullScreen(BuildContext context) {
    final fileUrl = widget.message.metadata.fileUrl;
    if (fileUrl == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FullScreenMedia(
          url: fileUrl,
          isVideo: widget.message.type == EchoType.video,
          isEncrypted: widget.message.metadata.isEncrypted,
          encryptionService: widget.encryptionService,
        ),
      ),
    );
  }
}

/// Full screen view for images/videos
/// Supports both encrypted and unencrypted media
class _FullScreenMedia extends StatefulWidget {
  final String url;
  final bool isVideo;
  final bool isEncrypted;
  final MediaEncryptionService? encryptionService;

  const _FullScreenMedia({
    required this.url,
    required this.isVideo,
    this.isEncrypted = false,
    this.encryptionService,
  });

  @override
  State<_FullScreenMedia> createState() => _FullScreenMediaState();
}

class _FullScreenMediaState extends State<_FullScreenMedia> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _hasError = false;
  bool _isDecrypting = false;
  String? _decryptedFilePath;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    if (widget.isEncrypted && widget.encryptionService != null) {
      setState(() => _isDecrypting = true);
      try {
        final fileId = MediaEncryptionService.generateFileId(widget.url);
        final decryptedPath = await widget.encryptionService!.getDecryptedMedia(
          encryptedUrl: widget.url,
          fileId: fileId,
          isVideo: widget.isVideo,
        );
        if (mounted) {
          setState(() {
            _decryptedFilePath = decryptedPath;
            _isDecrypting = false;
          });
          if (widget.isVideo) {
            _initializeVideoFromFile(decryptedPath);
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _isDecrypting = false;
          });
        }
      }
    } else if (widget.isVideo) {
      _initializeVideoFromNetwork();
    }
  }

  Future<void> _initializeVideoFromNetwork() async {
    try {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await _videoController!.initialize();
      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });
        _videoController!.play();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  Future<void> _initializeVideoFromFile(String filePath) async {
    try {
      _videoController = VideoPlayerController.file(File(filePath));
      await _videoController!.initialize();
      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });
        _videoController!.play();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
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
      body: Center(
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    // Show loading while decrypting
    if (_isDecrypting) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Decrypting...',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    if (widget.isVideo) {
      return _buildVideoPlayer();
    }

    return _buildImageViewer();
  }

  Widget _buildImageViewer() {
    // If encrypted, use file image
    if (widget.isEncrypted && _decryptedFilePath != null) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Image.file(
          File(_decryptedFilePath!),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.broken_image,
            size: 64,
            color: Colors.white54,
          ),
        ),
      );
    }

    // Unencrypted - use network image
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: CachedNetworkImage(
        imageUrl: widget.url,
        fit: BoxFit.contain,
        placeholder: (context, url) => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
        errorWidget: (context, url, error) => const Icon(
          Icons.broken_image,
          size: 64,
          color: Colors.white54,
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_hasError) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.white54,
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load video',
            style: TextStyle(color: Colors.grey.shade400),
          ),
        ],
      );
    }

    if (!_isVideoInitialized || _videoController == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
        _VideoControls(controller: _videoController!),
      ],
    );
  }
}

/// Video playback controls
class _VideoControls extends StatefulWidget {
  final VideoPlayerController controller;

  const _VideoControls({required this.controller});

  @override
  State<_VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<_VideoControls> {
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateState);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateState);
    super.dispose();
  }

  void _updateState() {
    if (mounted) {
      setState(() {});
    }
  }

  void _togglePlayPause() {
    setState(() {
      if (widget.controller.value.isPlaying) {
        widget.controller.pause();
      } else {
        widget.controller.play();
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showControls = !_showControls;
        });
      },
      child: Container(
        color: Colors.transparent,
        child: AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Play/pause button
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    widget.controller.value.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
                    color: Colors.white,
                    size: 32,
                  ),
                  onPressed: _togglePlayPause,
                ),
              ),
              const SizedBox(height: 32),
              // Progress bar
              Container(
                color: Colors.black.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      _formatDuration(widget.controller.value.position),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: VideoProgressIndicator(
                        widget.controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Colors.white,
                          bufferedColor: Colors.white54,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDuration(widget.controller.value.duration),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
