import 'dart:convert';
import 'dart:io';

/// Search suggestions from Google's autocomplete endpoint.
///
/// This is the same suggestion service the YouTube search box uses, and it
/// costs no API quota — it is not part of the Data API. Results are cached per
/// query and requests are debounced by the caller, so typing does not produce a
/// request per keystroke.
class SearchSuggestions {
  SearchSuggestions({HttpClient? client})
      : _client = client ??
            (HttpClient()..connectionTimeout = const Duration(seconds: 8));

  final HttpClient _client;
  final Map<String, List<String>> _cache = {};

  Future<List<String>> forQuery(String query) async {
    final cleaned = query.trim();
    if (cleaned.length < 2) return const [];

    final cached = _cache[cleaned.toLowerCase()];
    if (cached != null) return cached;

    try {
      final uri = Uri.https('suggestqueries.google.com', '/complete/search', {
        'client': 'firefox',
        'ds': 'yt',
        'hl': 'en',
        'q': cleaned,
      });

      final request = await _client.getUrl(uri).timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');

      final response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        await response.drain<void>();
        return const [];
      }

      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      if (decoded is! List || decoded.length < 2) return const [];
      final raw = decoded[1];
      if (raw is! List) return const [];

      final suggestions = raw
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .take(8)
          .toList(growable: false);

      _cache[cleaned.toLowerCase()] = suggestions;
      return suggestions;
    } catch (_) {
      return const [];
    }
  }

  void dispose() => _client.close(force: true);
}
