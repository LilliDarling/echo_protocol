import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../../services/crypto/media_encryption.dart';
import 'media_placeholders.dart';
import 'video_player_view.dart';

class FullScreenMediaView extends StatefulWidget {
  final String url;
  final String? thumbnailUrl;
  final Uint8List? decryptedThumbnailBytes;
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
    this.decryptedThumbnailBytes,
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
  bool _isSaving = false;
  Uint8List? _decryptedImageBytes;
  String? _decryptedVideoPath;

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
        if (widget.isVideo) {
          final decryptedPath = await widget.encryptionService!.downloadAndDecrypt(
            encryptedUrl: widget.url,
            mediaId: widget.mediaId!,
            mediaKey: widget.mediaKey!,
            isVideo: true,
          );
          if (mounted) {
            setState(() {
              _decryptedVideoPath = decryptedPath;
              _isDecrypting = false;
              _isLoadingFullResolution = false;
              _fullResolutionLoaded = true;
            });
          }
        } else {
          final decryptedBytes = await widget.encryptionService!.downloadAndDecryptToMemory(
            encryptedUrl: widget.url,
            mediaId: widget.mediaId!,
            mediaKey: widget.mediaKey!,
          );
          if (mounted) {
            setState(() {
              _decryptedImageBytes = decryptedBytes;
              _isDecrypting = false;
              _isLoadingFullResolution = false;
              _fullResolutionLoaded = true;
            });
          }
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
        actions: [
          if (_canSave())
            IconButton(
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.download),
              onPressed: _isSaving ? null : _saveToGallery,
            ),
        ],
      ),
      body: Center(child: _buildContent()),
    );
  }

  bool _canSave() {
    if (widget.isVideo) {
      return _decryptedVideoPath != null || !widget.isEncrypted;
    }
    return _decryptedImageBytes != null || _fullResolutionLoaded;
  }

  Future<void> _saveToGallery() async {
    setState(() => _isSaving = true);
    try {
      if (widget.isVideo) {
        await _saveVideo();
      } else {
        await _saveImage();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved to gallery'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveImage() async {
    if (_decryptedImageBytes != null) {
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/save_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(_decryptedImageBytes!);
      try {
        await Gal.putImage(tempPath);
      } finally {
        if (await tempFile.exists()) await tempFile.delete();
      }
    } else {
      final response = await http.get(Uri.parse(widget.url));
      if (response.statusCode != 200) throw Exception('Download failed');
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/save_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(response.bodyBytes);
      try {
        await Gal.putImage(tempPath);
      } finally {
        if (await tempFile.exists()) await tempFile.delete();
      }
    }
  }

  Future<void> _saveVideo() async {
    if (_decryptedVideoPath != null) {
      await Gal.putVideo(_decryptedVideoPath!);
    } else {
      final response = await http.get(Uri.parse(widget.url));
      if (response.statusCode != 200) throw Exception('Download failed');
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/save_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(response.bodyBytes);
      try {
        await Gal.putVideo(tempPath);
      } finally {
        if (await tempFile.exists()) await tempFile.delete();
      }
    }
  }

  Widget _buildContent() {
    if (_isDecrypting) return MediaPlaceholders.decrypting();

    if (widget.isVideo) return _buildVideoPlayer();

    return _buildImageViewer();
  }

  Widget _buildVideoPlayer() {
    if (widget.isEncrypted && _decryptedVideoPath != null) {
      return VideoPlayerView(
        filePath: _decryptedVideoPath,
        deleteOnDispose: true,
      );
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
    if (widget.decryptedThumbnailBytes != null) {
      return Image.memory(
        widget.decryptedThumbnailBytes!,
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
    if (widget.isEncrypted && _decryptedImageBytes != null) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Image.memory(
          _decryptedImageBytes!,
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
