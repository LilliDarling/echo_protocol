import 'package:http/http.dart' as http;
import '../models/echo.dart';

class LinkPreviewService {
  static final _urlRegex = RegExp(
    r'https?://[^\s]+',
    caseSensitive: false,
  );

  static String? extractUrl(String text) {
    final match = _urlRegex.firstMatch(text);
    return match?.group(0);
  }

  static bool containsUrl(String text) {
    return _urlRegex.hasMatch(text);
  }

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

  LinkPreview? _parseHtml(String html, String url) {
    String? title;
    String? description;
    String? imageUrl;

    title = _extractMetaContent(html, 'og:title');
    description = _extractMetaContent(html, 'og:description');
    imageUrl = _extractMetaContent(html, 'og:image');

    title ??= _extractMetaContent(html, 'twitter:title');
    description ??= _extractMetaContent(html, 'twitter:description');
    imageUrl ??= _extractMetaContent(html, 'twitter:image');

    description ??= _extractMetaContent(html, 'description', isProperty: false);

    title ??= _extractTitle(html);

    if (title == null || title.isEmpty) {
      final uri = Uri.tryParse(url);
      title = uri?.host ?? url;
    }

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

  String? _extractMetaContent(String html, String name, {bool isProperty = true}) {
    final attribute = isProperty ? 'property' : 'name';

    final regex1 = RegExp(
      '<meta[^>]*$attribute=["\']$name["\'][^>]*content=["\']([^"\']*)["\']',
      caseSensitive: false,
    );
    final match1 = regex1.firstMatch(html);
    if (match1 != null) {
      return _decodeHtmlEntities(match1.group(1));
    }

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
