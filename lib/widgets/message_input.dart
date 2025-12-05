import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/echo.dart';
import '../services/media_upload_service.dart';
import '../services/media_encryption_service.dart';

class MessageInput extends StatefulWidget {
  final Future<void> Function(String text, {EchoType type, EchoMetadata? metadata}) onSend;
  final bool isSending;
  final String partnerId;
  final MediaEncryptionService? mediaEncryptionService;
  final void Function(String)? onTextChanged;

  const MessageInput({
    super.key,
    required this.onSend,
    required this.isSending,
    required this.partnerId,
    this.mediaEncryptionService,
    this.onTextChanged,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();

  late MediaUploadService _uploadService;

  bool _isUploading = false;
  bool get _hasText => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _initUploadService();
  }

  @override
  void didUpdateWidget(MessageInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaEncryptionService != widget.mediaEncryptionService) {
      _initUploadService();
    }
  }

  void _initUploadService() {
    _uploadService = MediaUploadService(
      encryptionService: widget.mediaEncryptionService,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    if (!_hasText || widget.isSending) return;

    final text = _controller.text.trim();
    _controller.clear();
    widget.onSend(text);
    _focusNode.requestFocus();
  }

  Future<void> _pickImage() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (image != null && mounted) {
        await _uploadImage(image);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _takePhoto() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );

      if (image != null && mounted) {
        await _uploadImage(image);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to take photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _uploadImage(XFile image) async {
    setState(() => _isUploading = true);

    try {
      // Validate file size
      final fileSize = await MediaUploadService.getFileSize(image);
      if (!MediaUploadService.isFileSizeValid(fileSize)) {
        throw Exception('File too large (max 50MB)');
      }

      // Get current user
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Upload image
      final result = await _uploadService.uploadImage(
        file: image,
        userId: userId,
      );

      // Send message with image
      if (mounted) {
        final metadata = EchoMetadata(
          fileUrl: result['fileUrl']!,
          thumbnailUrl: result['thumbnailUrl']!,
          fileName: result['fileName'],
          isEncrypted: result['isEncrypted'] == 'true',
        );

        await widget.onSend(
          '[Image]',
          type: EchoType.image,
          metadata: metadata,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload image: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      final video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
      );

      if (video != null && mounted) {
        await _uploadVideo(video);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _uploadVideo(XFile video) async {
    setState(() => _isUploading = true);

    try {
      // Validate file size
      final fileSize = await MediaUploadService.getFileSize(video);
      if (!MediaUploadService.isFileSizeValid(fileSize)) {
        throw Exception('File too large (max 50MB)');
      }

      // Get current user
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Upload video
      final result = await _uploadService.uploadVideo(
        file: video,
        userId: userId,
      );

      // Send message with video
      if (mounted) {
        final metadata = EchoMetadata(
          fileUrl: result['fileUrl']!,
          thumbnailUrl: result['thumbnailUrl'],
          fileName: result['fileName'],
          isEncrypted: result['isEncrypted'] == 'true',
        );

        await widget.onSend(
          '[Video]',
          type: EchoType.video,
          metadata: metadata,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload video: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Send attachment',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.purple.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.photo_library, color: Colors.purple.shade700),
              ),
              title: const Text('Photo from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage();
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.camera_alt, color: Colors.blue.shade700),
              ),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _takePhoto();
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.videocam, color: Colors.orange.shade700),
              ),
              title: const Text('Video from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickVideo();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Attachment button
              IconButton(
                icon: Icon(
                  Icons.add_circle_outline,
                  color: Colors.grey.shade600,
                ),
                onPressed: _showAttachmentOptions,
              ),
              // Text field
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Message',
                      hintStyle: TextStyle(color: Colors.grey.shade500),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (text) {
                      setState(() {});
                      widget.onTextChanged?.call(text);
                    },
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Send button or upload indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: (widget.isSending || _isUploading)
                    ? Container(
                        width: 44,
                        height: 44,
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _isUploading ? Colors.orange : theme.primaryColor,
                          ),
                        ),
                      )
                    : IconButton(
                        icon: Icon(
                          Icons.send,
                          color: _hasText
                              ? theme.primaryColor
                              : Colors.grey.shade400,
                        ),
                        onPressed: _hasText ? _handleSend : null,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
