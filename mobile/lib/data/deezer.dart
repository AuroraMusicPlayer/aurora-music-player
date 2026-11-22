import 'dart:convert';
import 'dart:io';

/// One entry from a public chart.
class ChartTrack {
  const ChartTrack({
    required this.title,
    required this.artist,
    this.artwork,
    this.album,
  });

  final String title;
  final String artist;
  final String? artwork;
  final String? album;

  String get query => artist.isEmpty ? title : '$artist $title';
}

/// Deezer's public API needs no key for charts, which makes it a rare thing:
/// real editorial data with no account involved.
class DeezerClient {
  DeezerClient({HttpClient? client})
      : _client = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 12));

  final HttpClient _client;

  Future<List<ChartTrack>> topTracks({int limit = 30}) async {
    final uri = Uri.https('api.deezer.com', '/chart/0/tracks', {'limit': '$limit'});
    final request = await _client.getUrl(uri).timeout(const Duration(seconds: 15));
    final response = await request.close().timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      await response.drain<void>();
      throw Exception('Charts unavailable (${response.statusCode})');
    }

    final body = jsonDecode(await utf8.decoder.bind(response).join());
    final data = (body is Map && body['data'] is List) ? body['data'] as List : const [];

    return [
      for (final item in data)
        if (item is Map)
          ChartTrack(
            title: (item['title'] ?? '').toString(),
            artist: ((item['artist'] is Map) ? item['artist']['name'] : '')?.toString() ?? '',
            artwork: (item['album'] is Map ? item['album']['cover_medium'] : null)?.toString(),
            album: (item['album'] is Map ? item['album']['title'] : null)?.toString(),
          ),
    ].where((t) => t.title.isNotEmpty).toList(growable: false);
  }

  void dispose() => _client.close(force: true);
}
