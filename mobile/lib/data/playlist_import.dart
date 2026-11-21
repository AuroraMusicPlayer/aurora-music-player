import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'youtube_source.dart';

/// One song we know the name of but not yet the YouTube video.
class ImportedEntry {
  const ImportedEntry({required this.title, required this.artist});

  final String title;
  final String artist;

  @override
  String toString() => '$artist — $title';
}

class ImportCandidate {
  const ImportCandidate({required this.name, required this.entries});

  final String name;
  final List<ImportedEntry> entries;
}

/// Reads playlist *names* from services that don't hand out audio, so the
/// tracks can then be matched to YouTube.
///
/// Spotify has no anonymous API, but its public embed page is server-rendered
/// with the track list in `__NEXT_DATA__`. That is used here: no credentials,
/// no login. It is best-effort by nature — if Spotify changes that page, the
/// text importer below still works.
class PlaylistReader {
  PlaylistReader({HttpClient? client})
      : _client = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 15));

  final HttpClient _client;

  static final _playlistId = RegExp(r'playlist[/:]([A-Za-z0-9]{10,})');

  /// Handles Spotify links, YouTube links (handled elsewhere) and raw text.
  bool looksLikeSpotify(String input) =>
      input.contains('spotify.com') || input.startsWith('spotify:');

  Future<ImportCandidate> fromSpotify(String input) async {
    final match = _playlistId.firstMatch(input);
    if (match == null) {
      throw const YouTubeSourceException('That does not look like a Spotify playlist link');
    }
    final id = match.group(1)!;

    final request = await _client
        .getUrl(Uri.parse('https://open.spotify.com/embed/playlist/$id'))
        .timeout(const Duration(seconds: 20));
    // The embed endpoint serves a browser page only.
    request.headers.set(HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
    final response = await request.close().timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw YouTubeSourceException(
          'Spotify returned ${response.statusCode} for that playlist');
    }

    final body = await utf8.decoder.bind(response).join();
    final json = _extractNextData(body);
    if (json == null) {
      throw const YouTubeSourceException(
        'Could not read that Spotify playlist. Try the text import instead.',
      );
    }

    final entity = _dig(json, ['props', 'pageProps', 'state', 'data', 'entity']);
    if (entity is! Map) {
      throw const YouTubeSourceException('That link is not a playlist');
    }

    final name = (entity['name'] ?? entity['title'] ?? 'Spotify playlist').toString();
    final list = entity['trackList'];
    if (list is! List) {
      throw const YouTubeSourceException('That playlist has no tracks');
    }

    final entries = <ImportedEntry>[];
    for (final item in list) {
      if (item is! Map) continue;
      final title = item['title']?.toString().trim();
      // Spotify separates artists with non-breaking spaces after a comma.
      final subtitle = item['subtitle']
          ?.toString()
          .replaceAll('\u00a0', ' ')
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();
      if (title == null || title.isEmpty) continue;
      entries.add(ImportedEntry(
        title: title,
        artist: (subtitle == null || subtitle.isEmpty) ? '' : subtitle,
      ));
    }

    if (entries.isEmpty) {
      throw const YouTubeSourceException('That Spotify playlist looks empty');
    }
    return ImportCandidate(name: name, entries: entries);
  }

  /// "Artist - Title" per line, or "Title" alone. Works for any service,
  /// including a Spotify export copied out of another tool.
  ImportCandidate fromText(String text, {String name = 'Imported playlist'}) {
    final entries = <ImportedEntry>[];
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      // Drop leading numbering and Spotify/YouTube URLs.
      final cleaned = line
          .replaceFirst(RegExp(r'^[\d\)\.\-\s]+'), '')
          .replaceAll(RegExp(r'https?://\S+'), '')
          .trim();
      if (cleaned.isEmpty) continue;

      final dash = cleaned.indexOf(RegExp(r'\s+[-–—]\s+'));
      if (dash > 0) {
        entries.add(ImportedEntry(
          artist: cleaned.substring(0, dash).trim(),
          title: cleaned.substring(dash).replaceFirst(RegExp(r'^\s+[-–—]\s+'), '').trim(),
        ));
      } else {
        entries.add(ImportedEntry(artist: '', title: cleaned));
      }
    }

    if (entries.isEmpty) {
      throw const YouTubeSourceException(
        'No songs found. Use one per line, as "Artist - Title".',
      );
    }
    return ImportCandidate(name: name, entries: entries);
  }

  /// Matches names to actual YouTube tracks, one search each.
  ///
  /// Deliberately throttled and capped: Google blocks devices that burst.
  Future<List<Track>> match(
    List<ImportedEntry> entries,
    YouTubeSource source, {
    int limit = 25,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final wanted = entries.take(limit).toList();
    final matched = <Track>[];
    final seen = <String>{};

    for (var i = 0; i < wanted.length; i++) {
      if (isCancelled?.call() ?? false) break;
      onProgress?.call(i, wanted.length);

      final entry = wanted[i];
      // Featuring lists ("Justice, Tame Impala, SZA") confuse search, and the
      // first credited artist is what identifies the song.
      final primaryArtist = entry.artist.split(',').first.trim();
      final query =
          primaryArtist.isEmpty ? entry.title : '$primaryArtist ${entry.title}';

      try {
        final results = await source.search(query, limit: 5, refresh: true);
        if (results.isEmpty) continue;

        // Prefer a result that actually contains the title.
        final needle = entry.title.toLowerCase();
        final best = results.firstWhere(
          (t) => t.title.toLowerCase().contains(needle),
          orElse: () => results.first,
        );
        if (seen.add(best.id)) matched.add(best);
      } catch (_) {
        // One unmatched song must not abort the whole import.
        continue;
      }
    }

    onProgress?.call(wanted.length, wanted.length);
    return matched;
  }

  /* ------------------------------ helpers ------------------------------- */

  Map<String, dynamic>? _extractNextData(String html) {
    final match = RegExp(
      r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
      dotAll: true,
    ).firstMatch(html);
    if (match == null) return null;
    try {
      final decoded = jsonDecode(match.group(1)!);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Object? _dig(Object? node, List<String> path) {
    var current = node;
    for (final key in path) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  void dispose() => _client.close(force: true);
}
