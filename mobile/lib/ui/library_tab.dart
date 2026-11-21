import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';

/// Everything stored on the device, newest first.
class LibraryTab extends StatefulWidget {
  const LibraryTab({super.key, required this.services});

  final AppServices services;

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  List<Track> _cached = const [];
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
    final bytes = await widget.services.library.cachedBytes();
    if (!mounted) return;
    setState(() {
      _cached = cached;
      _bytes = bytes;
    });
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
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${usedMb.toStringAsFixed(0)} MB / $budgetGb GB',
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ),
          ),
        ],
      ),
      body: _cached.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nothing saved yet.\nTracks you replay are saved automatically; '
                  'long-press a search result to save it now.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: _cached.length,
              itemBuilder: (context, index) {
                final track = _cached[index];
                return ListTile(
                  onTap: () => widget.services.handler
                      .playTracks(_cached, startIndex: index),
                  onLongPress: () async {
                    await widget.services.cache.remove(track);
                    await _load();
                  },
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: track.thumbnail == null
                          ? const ColoredBox(color: Color(0xFF1E1E1E))
                          : Image.network(track.thumbnail!, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const ColoredBox(color: Color(0xFF1E1E1E))),
                    ),
                  ),
                  title: Text(track.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    _subtitle(track),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.offline_pin_outlined,
                      size: 16, color: Colors.greenAccent),
                );
              },
            ),
    );
  }

  String _subtitle(Track track) {
    final origin = track.cacheOrigin == 'auto' ? 'Auto' : 'Saved';
    final mb = (track.bytes / (1024 * 1024)).toStringAsFixed(1);
    return '$origin · $mb MB · played ${track.playCount}×';
  }
}
