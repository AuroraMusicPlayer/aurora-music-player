import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../data/google_account.dart';
import '../data/models.dart';
import '../data/youtube_library.dart';

/// Imports the signed-in account's playlists and liked songs, optionally
/// saving every imported track for offline playback.
///
/// Downloads run one at a time: parallel fetches from googlevideo are what make
/// Google throttle a device, and an import can easily be a few hundred tracks.
Future<void> showGoogleImport(BuildContext context, AppServices services) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  final saveOffline = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Import YouTube library'),
      content: const Text(
        'Your playlists and liked songs will be added to Aurora.\n\n'
        'Saving them for offline playback downloads every song, one at a time, '
        'and can take a while on a large library.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Import only'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Import + save offline'),
        ),
      ],
    ),
  );
  if (saveOffline == null) return;

  final status = ValueNotifier<String>('Contacting YouTube…');
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Importing'),
      content: ValueListenableBuilder<String>(
        valueListenable: status,
        builder: (context, value, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
        ),
      ),
    ),
  ));

  YouTubeLibrary? library;
  try {
    library = YouTubeLibrary(services.google);

    status.value = 'Reading liked songs…';
    final liked = await library.likedTracks();

    status.value = 'Reading playlists…';
    final playlists = await library.playlists(
      onProgress: (done, total) =>
          status.value = 'Reading playlists $done/$total',
    );

    final all = <Track>[
      ...liked,
      for (final playlist in playlists) ...playlist.tracks,
    ];

    if (all.isEmpty) {
      throw const GoogleAccountException(
        'Nothing found. If your library is empty, or access was declined, '
        'there is nothing to import.',
      );
    }

    status.value = 'Filling in track lengths…';
    final durations = await services.metadata
        .durations(all.map((t) => t.id).toList())
        .catchError((Object _) => <String, int>{});

    List<Track> enrich(List<Track> tracks) => [
          for (final track in tracks)
            track.duration == null && durations.containsKey(track.id)
                ? track.copyWith(duration: durations[track.id])
                : track,
        ];

    final likedTracks = enrich(liked);
    final importedPlaylists = [
      for (final playlist in playlists)
        LibraryPlaylist(
          title: playlist.title,
          thumbnail: playlist.thumbnail,
          tracks: enrich(playlist.tracks),
        ),
    ];
    final enriched = [
      ...likedTracks,
      for (final playlist in importedPlaylists) ...playlist.tracks,
    ];

    status.value = 'Saving ${enriched.length} songs to your library…';
    for (final track in enriched) {
      await services.library.remember(track);
    }

    if (likedTracks.isNotEmpty) {
      await services.library
          .createPlaylistWithTracks('Liked from YouTube', likedTracks);
    }
    for (final playlist in importedPlaylists) {
      await services.library
          .createPlaylistWithTracks(playlist.title, playlist.tracks);
    }
    services.events.bump();

    var saved = 0;
    if (saveOffline) {
      saved = await services.cache.downloadAll(
        enriched,
        onProgress: (done, total) =>
            status.value = 'Saving offline $done/$total',
      );
    }

    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: Text(saveOffline
          ? 'Imported ${playlists.length + 1} playlists · $saved songs saved offline'
          : 'Imported ${playlists.length + 1} playlists · ${all.length} songs'),
    ));
  } catch (error) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('$error')));
  } finally {
    library?.dispose();
  }
}
