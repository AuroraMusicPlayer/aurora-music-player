import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'models.dart';
import 'music_filter.dart';
import 'youtube_api.dart';

/// A playable audio URL plus what we know about it.
class ResolvedStream {
  const ResolvedStream({
    required this.url,
    required this.bytes,
    required this.resolvedAt,
  });

  final String url;
  final int? bytes;
  final DateTime resolvedAt;

  bool get isStale => DateTime.now().difference(resolvedAt) > const Duration(hours: 5);
}

class _CachedSearch {
  const _CachedSearch(this.at, this.tracks);

  final DateTime at;
  final List<Track> tracks;
}

/// YouTube access entirely on the device — no server involved.
///
/// Google rate-limits undisguised traffic: hammering it produces
/// `GOOGLE_ABUSE_EXCEPTION` redirect loops instead of results. This class is
/// therefore deliberately conservative:
///
///  * every request goes through a minimum gap ([_minGap]),
///  * identical searches are cached for [searchTtl],
///  * an abuse response puts the whole source into a cool-down instead of
///    retrying in a loop, and surfaces a readable message to the UI.
class YouTubeSource {
  YouTubeSource({
    this.minGap = const Duration(milliseconds: 900),
    YouTubeApi? metadata,
  }) : _metadata = metadata;

  final Duration minGap;
  final YouTubeApi? _metadata;
  static const searchTtl = Duration(minutes: 20);
  static const abuseCooldown = Duration(minutes: 4);

  final YoutubeExplode _yt = YoutubeExplode();
  final Map<String, ResolvedStream> _urls = {};
  final Map<String, _CachedSearch> _searches = {};

  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _cooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);

  // Things that never belong in a music library.
  static final _noise = RegExp(
    r'[\(\[]\s*(?:official\s*(?:music\s*)?(?:video|audio|visuali[sz]er)|lyric\s*video|lyrics?|audio|hd|hq|4k|mv|m\/v|8d|remaster(?:ed)?(?:\s*\d{4})?|explicit|clean|full\s*album)\s*[\)\]]',
    caseSensitive: false,
  );
  static final _noiseTail = RegExp(
    r'\s*[-–—|]\s*(?:official\s*(?:music\s*)?(?:video|audio)|lyric\s*video|lyrics)\s*$',
    caseSensitive: false,
  );

  bool get isCoolingDown => DateTime.now().isBefore(_cooldownUntil);

  Duration get cooldownRemaining =>
      isCoolingDown ? _cooldownUntil.difference(DateTime.now()) : Duration.zero;

  /// Searches YouTube, and if a multi-word query finds nothing, retries with
  /// its first word.
  ///
  /// Concrete case: "noizy pwa" returns zero videos, while "noizy" returns the
  /// artist's catalogue. A dead end is worse than a slightly looser query,
  /// especially since the ranker then orders the results by what you play.
  Future<List<Track>> search(String query, {int limit = 25, bool refresh = false}) async {
    final tracks = await _searchOnce(query, limit: limit, refresh: refresh);
    if (tracks.isNotEmpty) return tracks;

    final firstWord = query.trim().split(RegExp(r'\s+')).first;
    if (firstWord.length < 3 || firstWord == query.trim()) return tracks;

    return _searchOnce(firstWord, limit: limit, refresh: refresh);
  }

  Future<List<Track>> _searchOnce(
    String query, {
    required int limit,
    required bool refresh,
  }) async {
    final key = '${query.trim().toLowerCase()}|$limit';
    final cached = _searches[key];
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(cached.at) < searchTtl) {
      return cached.tracks;
    }

    await _beforeRequest();

    try {
      final results = await _yt.search
          .search(query)
          .timeout(const Duration(seconds: 15));

      final seen = <String>{};
      final tracks = <Track>[];
      for (final video in results) {
        final track = _toTrack(video);
        // "Emmène-moi", "Emmene moi" and "Emmène-moi (Remastered)" are one song.
        final dedupeKey =
            '${MusicFilter.titleKey(track.title)}|${track.artist.toLowerCase()}';
        if (!seen.add(dedupeKey)) continue;
        tracks.add(track);
        if (tracks.length >= limit) break;
      }

      // Every caller gets music only. Filtering here, rather than at each call
      // site, is what stops a stray documentary entering a queue through a
      // path nobody remembered to guard.
      final songs = MusicFilter.songsOnly(tracks);
      _searches[key] = _CachedSearch(DateTime.now(), songs);
      return songs;
    } catch (error) {
      throw _translate(error);
    }
  }

  /// Resolve (and memoise) a playable URL for a video id.
  ///
  /// Only the progressive (muxed) stream is used. Audio-only streams are DASH
  /// fragments (`ftypdash`) that AVFoundation refuses to play over HTTP and
  /// that YouTube answers with 403. The muxed stream is a plain `ftypmp42` MP4
  /// both AVPlayer and ExoPlayer handle, at the cost of a 360p video track.
  Future<ResolvedStream> stream(String videoId) async {
    final cached = _urls[videoId];
    if (cached != null && !cached.isStale) return cached;

    await _beforeRequest();

    try {
      final manifest = await _yt.videos.streamsClient
          .getManifest(videoId)
          .timeout(const Duration(seconds: 20));

      final progressive = manifest.muxed.toList()
        ..sort((a, b) => a.size.totalBytes.compareTo(b.size.totalBytes));

      if (progressive.isEmpty) {
        throw const YouTubeSourceException(
          'No progressive stream for that video — try another upload',
        );
      }

      final stream = progressive.first;
      final resolved = ResolvedStream(
        url: stream.url.toString(),
        bytes: stream.size.totalBytes,
        resolvedAt: DateTime.now(),
      );
      _urls[videoId] = resolved;
      return resolved;
    } catch (error) {
      throw _translate(error);
    }
  }

  /// Reads a YouTube playlist (public, no sign-in) into tracks.
  ///
  /// Capped at [maxTracks] because every page is a request and Google starts
  /// blocking devices that ask too often.
  Future<ImportedPlaylist> fetchPlaylist(String input, {int maxTracks = 80}) async {
    final id = _playlistIdFrom(input);
    if (id == null) {
      throw const YouTubeSourceException(
        'That does not look like a YouTube playlist link',
      );
    }

    await _beforeRequest();

    try {
      final meta = await _yt.playlists
          .get(id)
          .timeout(const Duration(seconds: 20));

      final tracks = <Track>[];
      await for (final video
          in _yt.playlists.getVideos(id).timeout(const Duration(seconds: 45))) {
        tracks.add(_toTrack(video));
        if (tracks.length >= maxTracks) break;
      }

      if (tracks.isEmpty) {
        throw const YouTubeSourceException('That playlist has no videos');
      }

      return ImportedPlaylist(
        name: meta.title.trim().isEmpty ? 'Imported playlist' : meta.title.trim(),
        tracks: await _withDurations(tracks),
      );
    } catch (error) {
      throw _translate(error);
    }
  }

  String? _playlistIdFrom(String input) {
    final trimmed = input.trim();
    if (RegExp(r'^[A-Za-z0-9_-]{13,}$').hasMatch(trimmed) && !trimmed.contains('/')) {
      return trimmed;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    final list = uri.queryParameters['list'];
    if (list != null && list.isNotEmpty) return list;
    if (uri.pathSegments.contains('playlist')) return null;
    return null;
  }

  /// Fills in missing durations so the seek bar and the "half the track"
  /// caching rule have something to work with.
  Future<List<Track>> _withDurations(List<Track> tracks) async {
    final api = _metadata;
    if (api == null || !api.isConfigured) return tracks;

    try {
      final durations = await api.durations(tracks.map((t) => t.id).toList());
      if (durations.isEmpty) return tracks;
      return [
        for (final track in tracks)
          track.duration == null && durations.containsKey(track.id)
              ? track.copyWith(duration: durations[track.id])
              : track,
      ];
    } catch (_) {
      return tracks; // durations are a nicety, never a blocker
    }
  }

  /// Called when a URL stops working mid-session (they expire after ~6h).
  void invalidate(String videoId) => _urls.remove(videoId);

  String? videoIdFrom(String input) {
    final trimmed = input.trim();
    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(trimmed)) return trimmed;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.host.contains('youtu.be')) return uri.pathSegments.firstOrNull;
    final v = uri.queryParameters['v'];
    if (v != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(v)) return v;
    return null;
  }

  /* ------------------------------ internals ----------------------------- */

  Future<void> _beforeRequest() async {
    if (isCoolingDown) {
      final minutes = (cooldownRemaining.inSeconds / 60).ceil();
      throw YouTubeSourceException(
        'YouTube is rate-limiting this device. Try again in about '
        '$minutes minute${minutes == 1 ? '' : 's'}.',
      );
    }

    final since = DateTime.now().difference(_lastRequest);
    if (since < minGap) {
      await Future<void>.delayed(minGap - since);
    }
    _lastRequest = DateTime.now();
  }

  /// Turns YouTube's opaque abuse redirects into something a person can act on,
  /// and stops the app from making it worse.
  Exception _translate(Object error) {
    final text = error.toString();
    final abused = text.contains('GOOGLE_ABUSE_EXCEPTION') ||
        text.contains('Redirect limit exceeded') ||
        text.contains('403');

    if (abused) {
      _cooldownUntil = DateTime.now().add(abuseCooldown);
      return YouTubeSourceException(
        'YouTube temporarily blocked this device. Wait a few minutes, then '
        'try again. Playing music that is already saved for offline still works.',
      );
    }
    if (error is YouTubeSourceException) return error;
    return YouTubeSourceException('YouTube request failed: $text');
  }

  Track _toTrack(Video video) {
    final artist = video.author
        .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
        .trim();
    return Track(
      id: video.id.value,
      title: cleanTrackTitle(video.title, artist),
      artist: artist.isEmpty ? 'Unknown artist' : artist,
      duration: video.duration?.inSeconds,
      thumbnail: video.thumbnails.highResUrl,
    );
  }

  /// Titles that are clearly playlists or marathons rather than songs.
  static final _compilation = RegExp(
    r'\b(top\s*\d+|top\s+(songs|hits|music)|hits?|billboard|chart|playlist|compilation|greatest|best\s+of|nonstop|full\s+album|megamix)\b',
    caseSensitive: false,
  );

  static bool isCompilation(Track track) =>
      _compilation.hasMatch(track.title) || (track.duration ?? 0) > 900;

  /// Shared with the Google import, which receives the same messy titles.
  static String cleanTrackTitle(String raw, String artist) {
    var title = raw.replaceAll(_noise, ' ').replaceAll(_noiseTail, '');
    if (artist.isNotEmpty) {
      final prefix = RegExp('^\\s*${RegExp.escape(artist)}\\s*[-–—]\\s*', caseSensitive: false);
      title = title.replaceFirst(prefix, '');
    }
    title = title.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return title.isEmpty ? raw : title;
  }

  void close() => _yt.close();
}

class ImportedPlaylist {
  const ImportedPlaylist({required this.name, required this.tracks});

  final String name;
  final List<Track> tracks;
}

class YouTubeSourceException implements Exception {
  const YouTubeSourceException(this.message);

  final String message;

  @override
  String toString() => message;
}
