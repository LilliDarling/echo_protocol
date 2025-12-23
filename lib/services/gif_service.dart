import 'package:flutter/material.dart';
import 'package:giphy_get/giphy_get.dart';

/// Service for handling GIF selection using Giphy
class GifService {
  // API key is passed via --dart-define=GIPHY_API_KEY=your_key
  // Build with: flutter build apk --dart-define=GIPHY_API_KEY=your_api_key
  static const String _apiKey = String.fromEnvironment(
    'GIPHY_API_KEY',
    defaultValue: '',
  );

  /// Check if Giphy API key is configured
  static bool get isConfigured => _apiKey.isNotEmpty;

  /// Show the GIF picker and return the selected GIF
  /// Returns null if user cancels or API key not configured
  static Future<GifResult?> pickGif(BuildContext context) async {
    if (!isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GIF feature not configured. Please set GIPHY_API_KEY.'),
          backgroundColor: Colors.orange,
        ),
      );
      return null;
    }

    final gif = await GiphyGet.getGif(
      context: context,
      apiKey: _apiKey,
      lang: GiphyLanguage.english,
      tabColor: Colors.pink,
      debounceTimeInMilliseconds: 350,
    );

    if (gif == null) return null;

    // Get the best quality URL available
    final originalUrl = gif.images?.original?.url;
    final fixedHeightUrl = gif.images?.fixedHeight?.url;
    final previewUrl = gif.images?.previewGif?.url ??
                       gif.images?.fixedHeightSmallStill?.url;

    return GifResult(
      url: originalUrl ?? fixedHeightUrl ?? '',
      previewUrl: previewUrl ?? fixedHeightUrl ?? originalUrl ?? '',
      title: gif.title ?? 'GIF',
      width: int.tryParse(gif.images?.original?.width ?? '0') ?? 0,
      height: int.tryParse(gif.images?.original?.height ?? '0') ?? 0,
    );
  }
}

/// Result from GIF picker
class GifResult {
  final String url;
  final String previewUrl;
  final String title;
  final int width;
  final int height;

  GifResult({
    required this.url,
    required this.previewUrl,
    required this.title,
    required this.width,
    required this.height,
  });
}
