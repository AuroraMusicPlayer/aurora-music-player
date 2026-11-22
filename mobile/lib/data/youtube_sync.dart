import 'dart:convert';
import 'dart:io';

import 'google_account.dart';
import 'library.dart';
import 'youtube_library.dart';

class SyncResult {
  SyncResult();

  int likesPulled = 0;
  int likesPushed = 0;
  int playlistsPulled = 0;
  int playlistsPushed = 0;
  int itemsPushed = 0;
  final List<String> warnings = [];

  String get summary => [
        if (likesPulled > 0) '$likesPulled likes from YouTube',
        if (likesPushed > 0) '$likesPushed likes sent to YouTube',
        if (playlistsPulled > 0) '$playlistsPulled playlists from YouTube',
        if (playlistsPushed > 0) '$playlistsPushed playlists sent to YouTube',
        if (itemsPushed > 0) '$itemsPushed songs added remotely',
      ].join(' · ').padLeft(0).trim();
}

/// Two-way sync between the local library and YouTube Music.
///
/// YouTube Music shares its data model with YouTube: "liked music" is
/// `videos.rate(rating=like)` and a playlist is a YouTube playlist. That means
/// the official Data API can keep both sides in step.
///
/// Deliberate rules, because this writes to a real account:
///  * additions only — nothing is ever deleted remotely;
///  * caps per run, because every write costs 50 quota units;
///  * one failed item does not abort the run, it is reported.
class YouTubeSync {
  YouTubeSync({
    required this.account,
    required this.library,
    required this.reader,
    HttpClient? client,
  }) : _client = client ??
            (HttpClient()..connectionTimeout = const Duration(seconds: 15));

  final GoogleAccount account;
  final Library library;
  final YouTubeLibrary reader;
  final HttpClient _client;

  static const _maxLikePush = 15;
  static const _maxPlaylistPush = 2;
  static const _maxItemsPerPlaylist = 30;

  Future<SyncResult> run({void Function(String)? onStatus}) async {
    final result = SyncResult();

    onStatus?.call('Reading liked songs from YouTube…');
    final remoteLiked = await reader.likedTracks();

    onStatus?.call('Comparing likes…');
    final localLiked = await library.favorites(limit: 2000);
    final localIds = localLiked.map((t) => t.id).toSet();
    final remoteIds = remoteLiked.map((t) => t.id).toSet();

    // Pull: likes that exist remotely but not here.
    for (final track in remoteLiked.where((t) => !localIds.contains(t.id))) {
      await library.remember(track);
      await library.setFavorite(track.id, true);
      result.likesPulled++;
    }

    // Push: local likes YouTube has never seen.
    final toPush = localLiked.where((t) => !remoteIds.contains(t.id)).take(_maxLikePush);
    for (final track in toPush) {
      try {
        await _rate(track.id, 'like');
        result.likesPushed++;
      } catch (error) {
        result.warnings.add('Could not like ${track.title}: $error');
      }
    }
    if (localLiked.where((t) => !remoteIds.contains(t.id)).length > _maxLikePush) {
      result.warnings.add(
        'More than $_maxLikePush new likes: the rest are sent next time '
        '(YouTube quota is 50 units per like).',
      );
    }

    onStatus?.call('Reading playlists from YouTube…');
    final remotePlaylists = await reader.playlists(
      onProgress: (done, total) => onStatus?.call('Reading playlist $done/$total…'),
    );

    // Pull playlists by id; match through the stored youtube_id.
    for (final remote in remotePlaylists) {
      final remoteId = remote.remoteId;
      if (remoteId != null) {
        final existing = await library.playlistByYoutubeId(remoteId);
        if (existing != null) continue;
      }

      for (final track in remote.tracks) {
        await library.remember(track);
      }
      final localId = await library.createPlaylistWithTracks(remote.title, remote.tracks);
      if (remoteId != null) {
        await library.setPlaylistYoutubeId(localId, remoteId);
      }
      result.playlistsPulled++;
    }

    // Push local playlists that were never sent.
    final locals = await library.playlists();
    final unsent = locals.where((p) => p.youtubeId == null).take(_maxPlaylistPush);

    for (final playlist in unsent) {
      try {
        onStatus?.call('Sending ${playlist.name} to YouTube…');
        final remoteId = await _createRemotePlaylist(playlist.name);
        await library.setPlaylistYoutubeId(playlist.id, remoteId);

        final tracks = await library.playlistTracks(playlist.id);
        for (final track in tracks.take(_maxItemsPerPlaylist)) {
          await _addToRemotePlaylist(remoteId, track.id);
          result.itemsPushed++;
        }
        result.playlistsPushed++;
      } catch (error) {
        result.warnings.add('Could not send ${playlist.name}: $error');
      }
    }

    return result;
  }

  Future<void> _rate(String videoId, String rating) async {
    await _request('POST', '/youtube/v3/videos/rate', {
      'id': videoId,
      'rating': rating,
    });
  }

  Future<String> _createRemotePlaylist(String title) async {
    final body = await _request(
      'POST',
      '/youtube/v3/playlists',
      {'part': 'snippet', 'mine': 'true'},
      body: {
        'snippet': {'title': title},
        'status': {'privacyStatus': 'private'},
      },
    );
    final id = body['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const YouTubeSourceFailure('YouTube did not return a playlist id');
    }
    return id;
  }

  Future<void> _addToRemotePlaylist(String playlistId, String videoId) async {
    await _request(
      'POST',
      '/youtube/v3/playlistItems',
      {'part': 'snippet'},
      body: {
        'snippet': {
          'playlistId': playlistId,
          'resourceId': {'kind': 'youtube#video', 'videoId': videoId},
        },
      },
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path,
    Map<String, String> query, {
    Map<String, Object?>? body,
  }) async {
    final headers = await account.libraryHeaders();
    final uri = Uri.https('www.googleapis.com', path, query);
    final request = await _client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');

    if (body != null) {
      final payload = jsonEncode(body);
      request.headers.contentType = ContentType.json;
      request.write(payload);
    }

    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw YouTubeSourceFailure(
        'YouTube ${response.statusCode}: '
        '${text.length > 180 ? text.substring(0, 180) : text}',
      );
    }
    if (text.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  void dispose() => _client.close(force: true);
}

class YouTubeSourceFailure implements Exception {
  const YouTubeSourceFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
