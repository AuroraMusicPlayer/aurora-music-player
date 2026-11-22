import 'dart:convert';
import 'dart:io';

import 'google_account.dart';
import 'models.dart';
import 'youtube_source.dart';

/// A playlist from the signed-in account.
class LibraryPlaylist {
  const LibraryPlaylist({
    required this.title,
    required this.tracks,
    this.thumbnail,
    this.remoteId,
  });

  final String title;

  /// YouTube playlist id, used to link the local copy.
  final String? remoteId;
  final List<Track> tracks;
  final String? thumbnail;
}

/// Reads the user's own YouTube library through the official Data API.
///
/// Read-only: nothing is written back to the account. Snippets already carry
/// title, channel and artwork, so importing does not need a single scrape.
class YouTubeLibrary {
  YouTubeLibrary(this.account, {HttpClient? client})
      : _client = client ??
            (HttpClient()..connectionTimeout = const Duration(seconds: 15));

  final GoogleAccount account;
  final HttpClient _client;

  static const _api = 'www.googleapis.com';
  static const _maxPages = 4; // 200 items per collection at 50 per page

  Future<Map<String, dynamic>> _get(String path, Map<String, String> query) async {
    final headers = await account.libraryHeaders();
    final uri = Uri.https(_api, path, query);
    final request = await _client.getUrl(uri);
    headers.forEach(request.headers.set);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');

    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != 200) {
      throw YouTubeSourceException(
        'YouTube returned ${response.statusCode}'
        '${body.length > 140 ? ': ${body.substring(0, 140)}' : ''}',
      );
    }
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  /// Liked videos, newest first.
  Future<List<Track>> likedTracks() async {
    final tracks = <Track>[];
    String? pageToken;

    for (var page = 0; page < _maxPages; page++) {
      final body = await _get('/youtube/v3/videos', {
        'part': 'snippet',
        'myRating': 'like',
        'maxResults': '50',
        if (pageToken != null) 'pageToken': pageToken,
      });

      for (final item in (body['items'] as List? ?? const [])) {
        if (item is! Map) continue;
        final id = item['id']?.toString();
        final snippet = item['snippet'];
        if (id == null || snippet is! Map) continue;
        tracks.add(_trackFrom(id, snippet));
      }

      pageToken = body['nextPageToken']?.toString();
      if (pageToken == null) break;
    }
    return tracks;
  }

  /// Every playlist in the account, with its tracks.
  Future<List<LibraryPlaylist>> playlists({
    void Function(int done, int total)? onProgress,
  }) async {
    final summaries = <({String id, String title, String? thumbnail})>[];
    String? pageToken;

    for (var page = 0; page < _maxPages; page++) {
      final body = await _get('/youtube/v3/playlists', {
        'part': 'snippet',
        'mine': 'true',
        'maxResults': '50',
        if (pageToken != null) 'pageToken': pageToken,
      });

      for (final item in (body['items'] as List? ?? const [])) {
        if (item is! Map) continue;
        final id = item['id']?.toString();
        final snippet = item['snippet'];
        if (id == null || snippet is! Map) continue;
        summaries.add((
          id: id,
          title: (snippet['title'] ?? 'Playlist').toString(),
          thumbnail: _thumbUrl(snippet),
        ));
      }

      pageToken = body['nextPageToken']?.toString();
      if (pageToken == null) break;
    }

    final result = <LibraryPlaylist>[];
    for (var i = 0; i < summaries.length; i++) {
      onProgress?.call(i, summaries.length);
      final summary = summaries[i];
      final tracks = await _playlistTracks(summary.id);
      if (tracks.isEmpty) continue;
      result.add(LibraryPlaylist(
        title: summary.title,
        tracks: tracks,
        thumbnail: summary.thumbnail,
        remoteId: summary.id,
      ));
    }
    onProgress?.call(summaries.length, summaries.length);
    return result;
  }

  Future<List<Track>> _playlistTracks(String playlistId) async {
    final tracks = <Track>[];
    String? pageToken;

    for (var page = 0; page < _maxPages; page++) {
      final body = await _get('/youtube/v3/playlistItems', {
        'part': 'snippet',
        'playlistId': playlistId,
        'maxResults': '50',
        if (pageToken != null) 'pageToken': pageToken,
      });

      for (final item in (body['items'] as List? ?? const [])) {
        if (item is! Map) continue;
        final snippet = item['snippet'];
        if (snippet is! Map) continue;
        final id = (snippet['resourceId'] is Map
                ? snippet['resourceId']['videoId']
                : null)
            ?.toString();
        if (id == null || id.isEmpty) continue;
        tracks.add(_trackFrom(id, snippet));
      }

      pageToken = body['nextPageToken']?.toString();
      if (pageToken == null) break;
    }
    return tracks;
  }

  Track _trackFrom(String videoId, Map snippet) {
    final rawTitle = (snippet['title'] ?? 'Unknown title').toString();
    final channel = (snippet['videoOwnerChannelTitle'] ??
            snippet['channelTitle'] ??
            '')
        .toString()
        .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
        .trim();

    return Track(
      id: videoId,
      title: YouTubeSource.cleanTrackTitle(rawTitle, channel),
      artist: channel.isEmpty ? 'Unknown artist' : channel,
      thumbnail: _thumbUrl(snippet),
    );
  }

  String? _thumbUrl(Map snippet) {
    final thumbs = snippet['thumbnails'];
    if (thumbs is! Map) return null;
    for (final key in ['high', 'medium', 'default']) {
      final entry = thumbs[key];
      if (entry is Map && entry['url'] != null) return entry['url'].toString();
    }
    return null;
  }

  void dispose() => _client.close(force: true);
}
