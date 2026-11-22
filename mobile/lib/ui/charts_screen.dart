import 'package:flutter/material.dart';

import '../app.dart';
import '../data/deezer.dart';
import 'mini_player.dart';

/// Public Deezer charts. Tapping a row resolves it to a YouTube track on
/// demand — one search per tap, not a bulk import, so it cannot trigger a
/// rate-limit block.
class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  final _deezer = DeezerClient();
  List<ChartTrack> _tracks = const [];
  String? _error;
  bool _loading = true;
  String? _resolving;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _deezer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tracks = await _deezer.topTracks(limit: 40);
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _play(ChartTrack entry) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _resolving = entry.query);
    try {
      final results = await widget.services.source.search(entry.query, limit: 3);
      if (results.isEmpty) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Could not find that on YouTube')));
        return;
      }
      for (final track in results) {
        await widget.services.library.remember(track);
      }
      await widget.services.handler.playTracks(results);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _resolving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: MiniPlayer(services: widget.services),
      appBar: AppBar(
        title: const Text('Top charts'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off, size: 40),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 13)),
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                            onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: _tracks.length,
                  itemBuilder: (context, index) {
                    final entry = _tracks[index];
                    final busy = _resolving == entry.query;
                    return ListTile(
                      onTap: busy ? null : () => _play(entry),
                      leading: SizedBox(
                        width: 50,
                        height: 50,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: entry.artwork == null
                              ? const ColoredBox(color: Color(0xFF1E1E1E))
                              : Image.network(entry.artwork!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const ColoredBox(
                                      color: Color(0xFF1E1E1E))),
                        ),
                      ),
                      title: Text(entry.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(entry.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                      trailing: busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text('${index + 1}',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 12)),
                    );
                  },
                ),
    );
  }
}
