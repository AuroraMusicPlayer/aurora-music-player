import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';
import '../data/playlist_import.dart';
import '../data/youtube_source.dart';
import 'playlist_screen.dart';

/// Add-to-playlist sheet, with inline creation so the flow never dead-ends.
Future<void> showAddToPlaylist(
  BuildContext context,
  AppServices services,
  Track track,
) async {
  final playlists = await services.library.playlists();
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: const Color(0xFF141414),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Add to playlist',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('New playlist'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final name = await _askName(context, suggested: track.artist);
                      if (name == null) return;
                      final id = await services.library.createPlaylist(name);
                      await services.library.addToPlaylist(id, track.id);
                      messenger.showSnackBar(
                          SnackBar(content: Text('Added to $name')));
                    },
                  ),
                  const Divider(height: 1),
                  ...playlists.map(
                    (playlist) => ListTile(
                      leading: const Icon(Icons.queue_music),
                      title: Text(playlist.name),
                      subtitle: Text('${playlist.trackCount} songs'),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await services.library.addToPlaylist(playlist.id, track.id);
                        messenger.showSnackBar(
                            SnackBar(content: Text('Added to ${playlist.name}')));
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

Future<String?> _askName(BuildContext context, {String suggested = ''}) {
  final controller = TextEditingController(text: suggested);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('New playlist'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Create'),
        ),
      ],
    ),
  );
}

/// Import songs from a Spotify link, a YouTube playlist link, or a pasted list.
///
/// Spotify and pasted lists only give us names, so each song is matched with a
/// YouTube search — throttled, capped, and cancellable.
Future<void> showImportPlaylist(
  BuildContext context,
  AppServices services,
) async {
  final controller = TextEditingController();

  final input = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Import a playlist'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Paste a Spotify playlist link, a YouTube playlist link, or a list '
            'of songs (one per line as "Artist - Title").',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: 6,
            minLines: 2,
            decoration: const InputDecoration(
              labelText: 'Link or song list',
              hintText: 'https://open.spotify.com/playlist/…',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Import'),
        ),
      ],
    ),
  );

  if (input == null || input.isEmpty) return;

  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final reader = PlaylistReader();
  final cancelled = <bool>[false];
  final status = ValueNotifier<String>('Reading playlist…');

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
      actions: [
        TextButton(
          onPressed: () {
            cancelled[0] = true;
            Navigator.pop(dialogContext);
          },
          child: const Text('Stop'),
        ),
      ],
    ),
  ));

  try {
    late final String name;
    late final List<Track> tracks;

    if (reader.looksLikeSpotify(input)) {
      final candidate = await reader.fromSpotify(input);
      name = candidate.name;
      tracks = await reader.match(
        candidate.entries,
        services.source,
        onProgress: (done, total) =>
            status.value = 'Finding songs on YouTube: $done of $total',
        isCancelled: () => cancelled[0],
      );
    } else if (input.contains('list=') || input.contains('youtube.com/playlist')) {
      final imported = await services.source.fetchPlaylist(input);
      name = imported.name;
      tracks = imported.tracks;
    } else {
      final candidate = reader.fromText(input);
      name = candidate.name;
      tracks = await reader.match(
        candidate.entries,
        services.source,
        onProgress: (done, total) =>
            status.value = 'Finding songs on YouTube: $done of $total',
        isCancelled: () => cancelled[0],
      );
    }

    if (tracks.isEmpty) {
      throw const YouTubeSourceException('Nothing could be matched to YouTube');
    }

    for (final track in tracks) {
      await services.library.remember(track);
    }
    final id = await services.library.createPlaylistWithTracks(name, tracks);
    services.events.bump();

    navigator.pop(); // progress dialog
    messenger.showSnackBar(
      SnackBar(content: Text('Imported ${tracks.length} of ${name}')),
    );

    final playlist = (await services.library.playlists())
        .where((p) => p.id == id)
        .firstOrNull;
    if (playlist != null) {
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => PlaylistScreen(services: services, playlist: playlist),
        ),
      );
    }
  } catch (error) {
    navigator.pop(); // progress dialog
    messenger.showSnackBar(SnackBar(content: Text('$error')));
  } finally {
    reader.dispose();
  }
}
