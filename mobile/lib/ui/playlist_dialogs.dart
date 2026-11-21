import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';
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

/// Paste a YouTube playlist link and import it read-only into the library.
Future<void> showImportPlaylist(
  BuildContext context,
  AppServices services,
) async {
  final controller = TextEditingController();
  final messenger = ScaffoldMessenger.of(context);

  final url = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Import a playlist'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Paste a YouTube playlist link (…&list=…). Spotify links need an '
            'account connection, which this build does not have yet.',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Playlist link',
              hintText: 'https://youtube.com/playlist?list=…',
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

  if (url == null || url.isEmpty) return;

  messenger.showSnackBar(
    const SnackBar(content: Text('Reading playlist… this can take a moment')),
  );

  try {
    final imported = await services.source.fetchPlaylist(url);
    for (final track in imported.tracks) {
      await services.library.remember(track);
    }
    final id = await services.library.createPlaylistWithTracks(
      imported.name,
      imported.tracks,
    );
    services.events.bump();

    if (!context.mounted) return;
    final playlist = (await services.library.playlists())
        .firstWhere((p) => p.id == id, orElse: () => throw StateError('missing'));
    messenger.showSnackBar(
      SnackBar(content: Text('Imported ${imported.tracks.length} songs')),
    );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistScreen(services: services, playlist: playlist),
      ),
    );
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('$error')));
  }
}
