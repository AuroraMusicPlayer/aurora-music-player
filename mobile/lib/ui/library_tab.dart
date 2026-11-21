import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';
import 'playlist_dialogs.dart';
import 'playlist_screen.dart';
import 'track_list_screen.dart';

/// Playlists, liked songs and everything stored on the device.
class LibraryTab extends StatefulWidget {
  const LibraryTab({super.key, required this.services});

  final AppServices services;

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  List<Playlist> _playlists = const [];
  int _liked = 0;
  int _autoCount = 0;
  int _autoBytes = 0;
  int _manualCount = 0;
  int _manualBytes = 0;
  List<Track> _recentAuto = const [];

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
    final library = widget.services.library;
    final playlists = await library.playlists();
    final liked = await library.favoriteCount();
    final auto = await library.offline(origin: 'auto');
    final manual = await library.offline(origin: 'manual');

    int bytesOf(List<Track> tracks) =>
        tracks.fold<int>(0, (sum, t) => sum + t.bytes);

    if (!mounted) return;
    setState(() {
      _playlists = playlists;
      _liked = liked;
      _autoCount = auto.length;
      _autoBytes = bytesOf(auto);
      _manualCount = manual.length;
      _manualBytes = bytesOf(manual);
      _recentAuto = auto.take(6).toList(growable: false);
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

  void _open(TrackListScreen screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;

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
            onPressed: () => showImportPlaylist(context, services),
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
            ListTile(
              leading: _icon(Icons.favorite, Colors.redAccent),
              title: const Text('Liked songs'),
              subtitle: Text('$_liked songs',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () => _open(TrackListScreen(
                services: services,
                title: 'Liked songs',
                showHeart: true,
                emptyMessage: 'Nothing liked yet.\nTap the heart in the player '
                    'on a song you love — it is saved offline too.',
                load: () => services.library.favorites(),
                onLongPress: (track) async {
                  await services.library.setFavorite(track.id, false);
                  services.events.bump();
                },
              )),
            ),
            ListTile(
              leading: _icon(Icons.offline_pin, Colors.greenAccent),
              title: const Text('Offline songs'),
              subtitle: Text(
                _autoCount == 0
                    ? 'Nothing saved automatically yet'
                    : '$_autoCount songs · ${(_autoBytes / (1024 * 1024)).toStringAsFixed(0)} MB',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () => _open(TrackListScreen(
                services: services,
                title: 'Offline songs',
                showHeart: true,
                emptyMessage: 'Songs you play twice, or listen through once, '
                    'are saved here automatically. They play with no network.',
                load: () => services.library.offline(origin: 'auto'),
                onLongPress: (track) async {
                  await services.cache.remove(track);
                  services.events.bump();
                },
              )),
            ),
            ListTile(
              leading: _icon(Icons.download_done, Colors.white70),
              title: const Text('Downloads'),
              subtitle: Text(
                _manualCount == 0
                    ? 'Nothing downloaded by hand yet'
                    : '$_manualCount songs · ${(_manualBytes / (1024 * 1024)).toStringAsFixed(0)} MB',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () => _open(TrackListScreen(
                services: services,
                title: 'Downloads',
                showHeart: true,
                emptyMessage: 'Songs you download yourself appear here. '
                    'These are never removed automatically.',
                load: () => services.library.offline(origin: 'manual'),
                onLongPress: (track) async {
                  await services.cache.remove(track);
                  services.events.bump();
                },
              )),
            ),

            _sectionHeader(context, 'Playlists', trailing: '${_playlists.length}'),
            if (_playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Create one with ＋, or import a Spotify or YouTube playlist.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ..._playlists.map(
              (playlist) => ListTile(
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlaylistScreen(
                        services: services,
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

            if (_recentAuto.isNotEmpty) ...[
              _sectionHeader(context, 'Recently saved'),
              ..._recentAuto.map(
                (track) => ListTile(
                  onTap: () => services.handler.playTracks(_recentAuto,
                      startIndex: _recentAuto.indexOf(track)),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: track.thumbnail == null
                          ? const ColoredBox(color: Color(0xFF1E1E1E))
                          : Image.network(track.thumbnail!, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const ColoredBox(color: Color(0xFF1E1E1E))),
                    ),
                  ),
                  title: Text(track.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  trailing: const Icon(Icons.offline_pin_outlined,
                      size: 16, color: Colors.greenAccent),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _icon(IconData icon, Color color) => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 20, color: color),
      );

  Widget _sectionHeader(BuildContext context, String title, {String? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          if (trailing != null)
            Text(trailing,
                style: const TextStyle(fontSize: 11, color: Colors.white38)),
        ],
      ),
    );
  }
}
