import 'dart:convert';
import 'dart:io';

/// Public API key (safe to ship in a client; it only grants public data).
///
///   --dart-define=YOUTUBE_API_KEY=AIza...
///
/// It is used for cheap metadata lookups only — 1 quota unit per 50 videos.
/// Reading a *user's own* playlists and likes requires OAuth, which an API key
/// cannot do.
const youtubeApiKey = String.fromEnvironment('YOUTUBE_API_KEY');

class YouTubeApiException implements Exception {
  const YouTubeApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Fills in facts the scraped pages do not give us reliably — mainly duration.
///
/// This matters beyond display: the auto-cache rule counts a "qualified play"
/// as 30 seconds or half the track, which is meaningless without a duration.
class YouTubeApi {
  YouTubeApi({HttpClient? client})
      : _client = client ??
            (HttpClient()..connectionTimeout = const Duration(seconds: 12));

  final HttpClient _client;

  bool get isConfigured => youtubeApiKey.isNotEmpty;

  /// Returns durations in seconds, keyed by video id.
  Future<Map<String, int>> durations(List<String> ids) async {
    if (!isConfigured || ids.isEmpty) return const {};
    final unique = ids.toSet().toList(growable: false);
    final result = <String, int>{};

    for (var start = 0; start < unique.length; start += 50) {
      final chunk = unique.skip(start).take(50).toList(growable: false);
      final body = await _get('/youtube/v3/videos', {
        'part': 'contentDetails',
        'id': chunk.join(','),
        'maxResults': '50',
        'key': youtubeApiKey,
      });

      for (final item in (body['items'] as List? ?? const [])) {
        if (item is! Map) continue;
        final id = item['id']?.toString();
        final details = item['contentDetails'];
        final raw = details is Map ? details['duration']?.toString() : null;
        if (id == null || raw == null) continue;
        final seconds = _parseIsoDuration(raw);
        if (seconds != null) result[id] = seconds;
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> _get(String path, Map<String, String> query) async {
    final uri = Uri.https('www.googleapis.com', path, query);
    final request = await _client.getUrl(uri).timeout(const Duration(seconds: 18));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 18));
    final body = await utf8.decoder.bind(response).join();

    if (response.statusCode == 403) {
      throw const YouTubeApiException(
        'YouTube API quota reached for today. Imports still work, just without '
        'durations, until the quota resets.',
      );
    }
    if (response.statusCode != 200) {
      throw YouTubeApiException('YouTube API returned ${response.statusCode}');
    }

    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  /// ISO 8601 duration, e.g. `PT5M40S` or `PT1H2M3S`.
  static int? _parseIsoDuration(String value) {
    final match = RegExp(r'P(?:(\d+)D)?T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?').firstMatch(value);
    if (match == null) return null;
    final days = int.tryParse(match.group(1) ?? '') ?? 0;
    final hours = int.tryParse(match.group(2) ?? '') ?? 0;
    final minutes = int.tryParse(match.group(3) ?? '') ?? 0;
    final seconds = int.tryParse(match.group(4) ?? '') ?? 0;
    final total = days * 86400 + hours * 3600 + minutes * 60 + seconds;
    return total > 0 ? total : null;
  }

  void dispose() => _client.close(force: true);
}
