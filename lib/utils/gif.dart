import 'package:flutter/material.dart';
import 'package:giphy_get/giphy_get.dart';

class GifService {
  static const String _apiKey = String.fromEnvironment(
    'GIPHY_API_KEY',
    defaultValue: '',
  );

  static bool get isConfigured => _apiKey.isNotEmpty;

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
