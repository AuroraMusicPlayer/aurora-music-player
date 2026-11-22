import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';
import 'artwork.dart';
import 'mini_player.dart';

/// Tracks inside one playlist.
class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key, required this.services, required this.playlist});

  final AppServices services;
  final Playlist playlist;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  List<Track> _tracks = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tracks = await widget.services.library.playlistTracks(widget.playlist.id);
    if (!mounted) return;
    setState(() {
      _tracks = tracks;
      _loading = false;
    });
  }

  Future<void> _playAll({bool shuffle = false}) async {
    if (_tracks.isEmpty) return;
    if (shuffle && !widget.services.handler.player.shuffleModeEnabled) {
      await widget.services.handler.toggleShuffle();
    } else if (!shuffle && widget.services.handler.player.shuffleModeEnabled) {
      await widget.services.handler.toggleShuffle();
    }
    await widget.services.handler.playTracks(_tracks);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: MiniPlayer(services: widget.services),
      appBar: AppBar(
        title: Text(widget.playlist.name),
        actions: [
          IconButton(
            tooltip: 'Rename',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _rename,
          ),
          IconButton(
            tooltip: 'Download all',
            icon: const Icon(Icons.download_for_offline_outlined),
            onPressed: _tracks.isEmpty ? null : _downloadAll,
          ),
          IconButton(
            tooltip: 'Delete playlist',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tracks.isEmpty
              ? const Center(
                  child: Text('This playlist is empty',
                      style: TextStyle(color: Colors.white54)))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _playAll(),
                              icon: const Icon(Icons.play_arrow),
                              label: Text('Play ${_tracks.length}'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: () => _playAll(shuffle: true),
                            icon: const Icon(Icons.shuffle),
                            label: const Text('Shuffle'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemCount: _tracks.length,
                        onReorder: (oldIndex, newIndex) async {
                          await widget.services.library
                              .movePlaylistTrack(widget.playlist.id, oldIndex, newIndex);
                          await _load();
                        },
                        itemBuilder: (context, index) {
                          final track = _tracks[index];
                          return ListTile(
                            key: ValueKey('pl-${widget.playlist.id}-${track.id}'),
                            onTap: () => widget.services.handler
                                .playTracks(_tracks, startIndex: index),
                            onLongPress: () async {
                              await widget.services.library
                                  .removeFromPlaylist(widget.playlist.id, track.id);
                              await _load();
                            },
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: SizedBox(
                                width: 50,
                                height: 50,
                                child: track.thumbnail == null
                                    ? const ColoredBox(color: Color(0xFF1E1E1E))
                                    : artworkForVideo(track.id),
                              ),
                            ),
                            title: Text(track.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 12)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (track.isCached)
                                  const Icon(Icons.offline_pin_outlined,
                                      size: 16, color: Colors.greenAccent),
                                ReorderableDragStartListener(
                                  index: index,
                                  child: const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: Icon(Icons.drag_handle,
                                        size: 18, color: Colors.white38),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Future<void> _downloadAll() async {
    final messenger = ScaffoldMessenger.of(context);
    final total = _tracks.where((t) => !t.isCached).length;
    if (total == 0) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Everything here is already saved')));
      return;
    }

    messenger.showSnackBar(SnackBar(
      content: Text('Saving $total songs… they download one at a time'),
      duration: const Duration(seconds: 4),
    ));

    final saved = await widget.services.cache.downloadAll(_tracks);
    await _load();
    messenger.showSnackBar(SnackBar(content: Text('Saved $saved of $total')));
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: widget.playlist.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename playlist'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await widget.services.library.renamePlaylist(widget.playlist.id, name);
    if (!mounted) return;
    setState(() {});
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: const Text('The songs stay in your library.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.services.library.deletePlaylist(widget.playlist.id);
    if (!mounted) return;
    Navigator.pop(context);
  }
}
