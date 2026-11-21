import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';

/// Generic song list used by Liked songs, Offline songs and Downloads.
class TrackListScreen extends StatefulWidget {
  const TrackListScreen({
    super.key,
    required this.services,
    required this.title,
    required this.load,
    required this.emptyMessage,
    this.onLongPress,
    this.showHeart = false,
  });

  final AppServices services;
  final String title;

  /// Loaded on open and after every change, so the list never goes stale.
  final Future<List<Track>> Function() load;
  final String emptyMessage;

  /// Long-press action: unlike, remove download, etc.
  final Future<void> Function(Track track)? onLongPress;

  final bool showHeart;

  @override
  State<TrackListScreen> createState() => _TrackListScreenState();
}

class _TrackListScreenState extends State<TrackListScreen> {
  List<Track> _tracks = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final tracks = await widget.load();
    if (!mounted) return;
    setState(() {
      _tracks = tracks;
      _loading = false;
    });
  }

  Future<void> _longPress(Track track) async {
    final action = widget.onLongPress;
    if (action == null) return;
    await action(track);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final totalMb = _tracks.fold<int>(0, (sum, t) => sum + t.bytes) / (1024 * 1024);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_tracks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  totalMb > 0
                      ? '${_tracks.length} songs · ${totalMb.toStringAsFixed(0)} MB'
                      : '${_tracks.length} songs',
                  style: const TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tracks.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      widget.emptyMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: _tracks.length,
                  itemBuilder: (context, index) {
                    final track = _tracks[index];
                    return ListTile(
                      onTap: () => widget.services.handler
                          .playTracks(_tracks, startIndex: index),
                      onLongPress: () => _longPress(track),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 50,
                          height: 50,
                          child: track.thumbnail == null
                              ? const ColoredBox(color: Color(0xFF1E1E1E))
                              : Image.network(track.thumbnail!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const ColoredBox(color: Color(0xFF1E1E1E))),
                        ),
                      ),
                      title: Text(track.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.showHeart && track.favorite)
                            const Icon(Icons.favorite, size: 16, color: Colors.redAccent),
                          if (track.isCached)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Icon(Icons.offline_pin_outlined,
                                  size: 16, color: Colors.greenAccent),
                            ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
