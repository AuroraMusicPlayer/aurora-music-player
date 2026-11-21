import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';

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
      appBar: AppBar(
        title: Text(widget.playlist.name),
        actions: [
          IconButton(
            tooltip: 'Rename',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _rename,
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
                      child: ListView.builder(
                        itemCount: _tracks.length,
                        itemBuilder: (context, index) {
                          final track = _tracks[index];
                          return ListTile(
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
                                    : Image.network(track.thumbnail!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const ColoredBox(
                                            color: Color(0xFF1E1E1E))),
                              ),
                            ),
                            title: Text(track.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 12)),
                            trailing: track.isCached
                                ? const Icon(Icons.offline_pin_outlined,
                                    size: 16, color: Colors.greenAccent)
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
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
