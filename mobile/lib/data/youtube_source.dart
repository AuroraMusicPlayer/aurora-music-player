import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'models.dart';

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

/// YouTube access entirely on the device — no server involved.
///
/// Search and manifest resolution use `youtube_explode_dart`. The bytes are
/// fetched by [DeviceCache] with a plain HTTP client rather than the library's
/// downloader, which stalls on googlevideo's redirect chain.
class YouTubeSource {
  final YoutubeExplode _yt = YoutubeExplode();
  final Map<String, ResolvedStream> _urls = {};

  // Things that never belong in a music library.
  static final _noise = RegExp(
    r'[\(\[]\s*(?:official\s*(?:music\s*)?(?:video|audio|visuali[sz]er)|lyric\s*video|lyrics?|audio|hd|hq|4k|mv|m\/v|8d|remaster(?:ed)?(?:\s*\d{4})?|explicit|clean|full\s*album)\s*[\)\]]',
    caseSensitive: false,
  );
  static final _noiseTail = RegExp(
    r'\s*[-–—|]\s*(?:official\s*(?:music\s*)?(?:video|audio)|lyric\s*video|lyrics)\s*$',
    caseSensitive: false,
  );

  Future<List<Track>> search(String query, {int limit = 25}) async {
    final results = await _yt.search
        .search(query)
        .timeout(const Duration(seconds: 30));

    final seen = <String>{};
    final tracks = <Track>[];
    for (final video in results) {
      final track = _toTrack(video);
      final key = '${track.title.toLowerCase()}|${track.artist.toLowerCase()}';
      if (!seen.add(key)) continue;
      tracks.add(track);
      if (tracks.length >= limit) break;
    }
    return tracks;
  }

  /// Resolve (and memoise) a playable URL for a video id.
  ///
  /// Only the **progressive (muxed) stream** is used. Audio-only streams are
  /// DASH fragments (`ftypdash`) which AVFoundation refuses to play over HTTP
  /// and which YouTube answers with 403 for client-side requests. The muxed
  /// stream is a plain `ftypmp42` MP4 that both AVPlayer and ExoPlayer handle,
  /// at the cost of carrying a 360p video track alongside the audio.
  Future<ResolvedStream> stream(String videoId) async {
    final cached = _urls[videoId];
    if (cached != null && !cached.isStale) return cached;

    final manifest = await _yt.videos.streamsClient
        .getManifest(videoId)
        .timeout(const Duration(seconds: 30));

    // Smallest progressive stream first: same container, less video to fetch.
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

  Track _toTrack(Video video) {
    final artist = video.author.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '').trim();
    return Track(
      id: video.id.value,
      title: _cleanTitle(video.title, artist),
      artist: artist.isEmpty ? 'Unknown artist' : artist,
      duration: video.duration?.inSeconds,
      thumbnail: video.thumbnails.highResUrl,
    );
  }

  String _cleanTitle(String raw, String artist) {
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

class YouTubeSourceException implements Exception {
  const YouTubeSourceException(this.message);

  final String message;

  @override
  String toString() => message;
}
