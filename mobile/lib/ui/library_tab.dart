import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';
import 'playlist_dialogs.dart';
import 'playlist_screen.dart';

/// Playlists and everything stored on the device.
class LibraryTab extends StatefulWidget {
  const LibraryTab({super.key, required this.services});

  final AppServices services;

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  List<Track> _cached = const [];
  List<Playlist> _playlists = const [];
  int _bytes = 0;

  @override
  void initState() {
    super.initState();
    widget.services.events.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.services.events.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final cached = await widget.services.library.cached();
    final playlists = await widget.services.library.playlists();
    final bytes = await widget.services.library.cachedBytes();
    if (!mounted) return;
    setState(() {
      _cached = cached;
      _playlists = playlists;
      _bytes = bytes;
    });
  }

  Future<void> _newPlaylist() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
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
    if (name == null || name.isEmpty) return;
    await widget.services.library.createPlaylist(name);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final usedMb = _bytes / (1024 * 1024);
    final budgetGb = widget.services.settings.cacheBudgetGb;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text('Library',
            style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        actions: [
          IconButton(
            tooltip: 'Import playlist',
            icon: const Icon(Icons.playlist_add),
            onPressed: () => showImportPlaylist(context, widget.services),
          ),
          IconButton(
            tooltip: 'New playlist',
            icon: const Icon(Icons.add),
            onPressed: _newPlaylist,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _sectionHeader(context, 'Playlists', trailing: '${_playlists.length}'),
            if (_playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Create one with ＋, or import a YouTube playlist link.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ..._playlists.map(
              (playlist) => ListTile(
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlaylistScreen(
                        services: widget.services,
                        playlist: playlist,
                      ),
                    ),
                  );
                  await _load();
                },
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 50,
                    height: 50,
                    child: playlist.thumbnail == null
                        ? const ColoredBox(
                            color: Color(0xFF1E1E1E),
                            child: Icon(Icons.queue_music, color: Colors.white38),
                          )
                        : Image.network(playlist.thumbnail!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const ColoredBox(
                                color: Color(0xFF1E1E1E))),
                  ),
                ),
                title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${playlist.trackCount} songs',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ),
            ),
            _sectionHeader(
              context,
              'Downloaded',
              trailing: '${usedMb.toStringAsFixed(0)} MB / $budgetGb GB',
            ),
            if (_cached.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Tracks you replay or listen through are saved automatically. '
                  'Long-press a search result to save it now.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ..._cached.map(
              (track) => ListTile(
                onTap: () => widget.services.handler
                    .playTracks(_cached, startIndex: _cached.indexOf(track)),
                onLongPress: () async {
                  await widget.services.cache.remove(track);
                  await _load();
                },
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 50,
                    height: 50,
                    child: track.thumbnail == null
                        ? const ColoredBox(color: Color(0xFF1E1E1E))
                        : Image.network(track.thumbnail!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const ColoredBox(color: Color(0xFF1E1E1E))),
                  ),
                ),
                title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${track.cacheOrigin == 'auto' ? 'Auto' : 'Saved'} · '
                  '${(track.bytes / (1024 * 1024)).toStringAsFixed(1)} MB · '
                  'played ${track.playCount}×',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: const Icon(Icons.offline_pin_outlined,
                    size: 16, color: Colors.greenAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, {String? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
          if (trailing != null)
            Text(trailing,
                style: const TextStyle(fontSize: 11, color: Colors.white38)),
        ],
      ),
    );
  }
}
