import 'dart:convert';
import 'dart:io';

/// One timed line of lyrics.
class LyricLine {
  const LyricLine({required this.at, required this.text});

  final Duration at;
  final String text;
}

class Lyrics {
  const Lyrics({required this.lines, required this.synced, this.plain});

  final List<LyricLine> lines;

  /// True when the lines carry real timestamps and can follow playback.
  final bool synced;

  /// Unsynced fallback text.
  final String? plain;
}

/// Lyrics from lrclib.net — a free, keyless, community database.
///
/// Synced (LRC) lyrics are preferred because they can follow the playhead;
/// plain text is kept as a fallback for tracks nobody has timed yet.
class LyricsClient {
  LyricsClient({HttpClient? client})
      : _client = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 10));

  final HttpClient _client;
  final Map<String, Lyrics?> _cache = {};

  Future<Lyrics?> forTrack({
    required String title,
    required String artist,
    int? durationSeconds,
  }) async {
    final key = '${title.toLowerCase()}|${artist.toLowerCase()}|$durationSeconds';
    if (_cache.containsKey(key)) return _cache[key];

    final cleanTitle = _clean(title);
    final cleanArtist = artist.split(',').first.trim();

    final result = await _get(cleanTitle, cleanArtist, durationSeconds) ??
        await _search(cleanTitle, cleanArtist);

    _cache[key] = result;
    return result;
  }

  Future<Lyrics?> _get(String title, String artist, int? duration) async {
    final params = {
      'artist_name': artist,
      'track_name': title,
      if (duration != null) 'duration': '$duration',
    };
    final body = await _fetch('/api/get', params);
    if (body == null) return null;
    return _parse(body);
  }

  Future<Lyrics?> _search(String title, String artist) async {
    final body = await _fetch('/api/search', {'q': '$artist $title'});
    if (body is! List || body.isEmpty) return null;
    for (final item in body.take(5)) {
      if (item is Map<String, dynamic>) {
        final parsed = _parse(item);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  Future<Object?> _fetch(String path, Map<String, String> query) async {
    try {
      final uri = Uri.https('lrclib.net', path, query);
      final request = await _client.getUrl(uri).timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.userAgentHeader, 'aurora-music/1.0');
      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      final body = await utf8.decoder.bind(response).join();
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  Lyrics? _parse(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    final synced = json['syncedLyrics'] as String?;
    final plain = json['plainLyrics'] as String?;

    if (synced != null && synced.trim().isNotEmpty) {
      final lines = parseLrc(synced);
      if (lines.isNotEmpty) return Lyrics(lines: lines, synced: true, plain: plain);
    }
    if (plain != null && plain.trim().isNotEmpty) {
      return Lyrics(
        lines: [
          for (final line in const LineSplitter().convert(plain))
            if (line.trim().isNotEmpty) LyricLine(at: Duration.zero, text: line.trim())
        ],
        synced: false,
        plain: plain,
      );
    }
    return null;
  }

  /// Matches one `[mm:ss.xx]` stamp. The text is taken after the last stamp so
  /// a repeated chorus line (`[00:10][01:20] Chorus`) works too.
  static final _stamp = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');

  /// Public so it can be unit-tested without a network call.
  static List<LyricLine> parseLrc(String lrc) {
    final lines = <LyricLine>[];
    for (final raw in const LineSplitter().convert(lrc)) {
      final matches = _stamp.allMatches(raw).toList();
      if (matches.isEmpty) continue;

      final text = raw.substring(matches.last.end).trim();
      if (text.isEmpty) continue;

      // A line can carry several timestamps (repeated choruses).
      for (final match in matches) {
        final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
        final fractionRaw = match.group(3) ?? '0';
        final millis = int.tryParse(fractionRaw.padRight(3, '0').substring(0, 3)) ?? 0;

        lines.add(LyricLine(
          at: Duration(minutes: minutes, seconds: seconds, milliseconds: millis),
          text: text,
        ));
      }
    }

    lines.sort((a, b) => a.at.compareTo(b.at));
    return lines;
  }

  /// YouTube titles carry release noise that breaks lyrics matching.
  String _clean(String title) {
    var cleaned = title
        .replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ')
        .replaceAll(RegExp(r'\b(official|video|audio|lyrics?|hd|hq|remaster(ed)?)\b',
            caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    if (cleaned.isEmpty) cleaned = title;
    return cleaned;
  }

  void dispose() => _client.close(force: true);
}
