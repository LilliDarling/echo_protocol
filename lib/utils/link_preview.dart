import 'package:http/http.dart' as http;
import '../models/echo.dart';

/// Service for fetching link previews from URLs
class LinkPreviewService {
  static final _urlRegex = RegExp(
    r'https?://[^\s]+',
    caseSensitive: false,
  );

  /// Extract the first URL from text
  static String? extractUrl(String text) {
    final match = _urlRegex.firstMatch(text);
    return match?.group(0);
  }

  /// Check if text contains a URL
  static bool containsUrl(String text) {
    return _urlRegex.hasMatch(text);
  }

  /// Fetch link preview metadata from a URL
  Future<LinkPreview?> fetchPreview(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (compatible; EchoProtocol/1.0)',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return null;
      }

      final html = response.body;
      return _parseHtml(html, url);
    } catch (e) {
      return null;
    }
  }

  /// Parse HTML to extract Open Graph and meta tags
  LinkPreview? _parseHtml(String html, String url) {
    String? title;
    String? description;
    String? imageUrl;

    // Try Open Graph tags first
    title = _extractMetaContent(html, 'og:title');
    description = _extractMetaContent(html, 'og:description');
    imageUrl = _extractMetaContent(html, 'og:image');

    // Fallback to Twitter cards
    title ??= _extractMetaContent(html, 'twitter:title');
    description ??= _extractMetaContent(html, 'twitter:description');
    imageUrl ??= _extractMetaContent(html, 'twitter:image');

    // Fallback to standard meta tags
    description ??= _extractMetaContent(html, 'description', isProperty: false);

    // Fallback to title tag
    title ??= _extractTitle(html);

    // If we couldn't get a title, use the domain
    if (title == null || title.isEmpty) {
      final uri = Uri.tryParse(url);
      title = uri?.host ?? url;
    }

    // Make relative image URLs absolute
    if (imageUrl != null && !imageUrl.startsWith('http')) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        if (imageUrl.startsWith('//')) {
          imageUrl = 'https:$imageUrl';
        } else if (imageUrl.startsWith('/')) {
          imageUrl = '${uri.scheme}://${uri.host}$imageUrl';
        }
      }
    }

    return LinkPreview(
      title: title,
      description: description ?? '',
      imageUrl: imageUrl ?? '',
    );
  }

  /// Extract content from a meta tag
  String? _extractMetaContent(String html, String name, {bool isProperty = true}) {
    final attribute = isProperty ? 'property' : 'name';

    // Try property="og:xxx" format
    final regex1 = RegExp(
      '<meta[^>]*$attribute=["\']$name["\'][^>]*content=["\']([^"\']*)["\']',
      caseSensitive: false,
    );
    final match1 = regex1.firstMatch(html);
    if (match1 != null) {
      return _decodeHtmlEntities(match1.group(1));
    }

    // Try content="xxx" property="og:xxx" format (reversed order)
    final regex2 = RegExp(
      '<meta[^>]*content=["\']([^"\']*)["\'][^>]*$attribute=["\']$name["\']',
      caseSensitive: false,
    );
    final match2 = regex2.firstMatch(html);
    if (match2 != null) {
      return _decodeHtmlEntities(match2.group(1));
    }

    return null;
  }

  /// Extract title from <title> tag
  String? _extractTitle(String html) {
    final regex = RegExp(
      r'<title[^>]*>([^<]*)</title>',
      caseSensitive: false,
    );
    final match = regex.firstMatch(html);
    if (match != null) {
      return _decodeHtmlEntities(match.group(1)?.trim());
    }
    return null;
  }

  /// Decode HTML entities
  String? _decodeHtmlEntities(String? text) {
    if (text == null) return null;
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();
  }
}
