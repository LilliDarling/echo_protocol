import 'package:flutter/material.dart';
import '../../../models/echo.dart';

class MediaPlaceholders {
  MediaPlaceholders._();

  static Widget encrypted() {
    return Container(
      width: 200,
      height: 150,
      color: Colors.grey.shade300,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock, size: 48, color: Colors.grey.shade500),
          const SizedBox(height: 8),
          Text('Encrypted', style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  static Widget forType(EchoType type) {
    return Container(
      width: 200,
      height: 150,
      color: Colors.grey.shade300,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            type == EchoType.video ? Icons.videocam : Icons.image,
            size: 48,
            color: Colors.grey.shade500,
          ),
          const SizedBox(height: 8),
          Text(
            type == EchoType.video ? 'Video' : 'Image',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  static Widget loading() {
    return Container(
      width: 200,
      height: 150,
      color: Colors.grey.shade200,
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  static Widget error() {
    return Container(
      width: 200,
      height: 150,
      color: Colors.grey.shade200,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(
            'Failed to load',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }

  static Widget thumbnailFallback() {
    return Container(
      width: 200,
      height: 200,
      color: Colors.grey.shade800,
      child: const Icon(Icons.image, size: 64, color: Colors.white38),
    );
  }

  static Widget videoError() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 64, color: Colors.white54),
        const SizedBox(height: 16),
        Text('Failed to load video', style: TextStyle(color: Colors.grey.shade400)),
      ],
    );
  }

  static Widget decrypting() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text('Decrypting...', style: TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }

  static Widget loadingOverlay({required String message}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  static Widget tapForFullResolution() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app, color: Colors.white70, size: 20),
          SizedBox(width: 8),
          Text(
            'Tap for full resolution',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
