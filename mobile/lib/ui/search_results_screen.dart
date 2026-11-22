import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';

/// A query turned into a playable list — used by mood/situation shortcuts.
class SearchResultsScreen extends StatefulWidget {
  const SearchResultsScreen({
    super.key,
    required this.services,
    required this.title,
    required this.query,
  });

  final AppServices services;
  final String title;
  final String query;

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  List<Track> _results = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.services.source.search(widget.query, limit: 25);
      for (final track in results) {
        await widget.services.library.remember(track);
      }
      if (!mounted) return;
      setState(() {
        _results = results;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_results.isNotEmpty)
            IconButton(
              tooltip: 'Shuffle play',
              icon: const Icon(Icons.shuffle),
              onPressed: () async {
                if (!widget.services.handler.player.shuffleModeEnabled) {
                  await widget.services.handler.toggleShuffle();
                }
                await widget.services.handler.playTracks(_results);
              },
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
                            onPressed: _search, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _results.isEmpty
                  ? const Center(
                      child: Text('Nothing found',
                          style: TextStyle(color: Colors.white54)))
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final track = _results[index];
                        return ListTile(
                          onTap: () => widget.services.handler
                              .playTracks(_results, startIndex: index),
                          leading: SizedBox(
                            width: 50,
                            height: 50,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
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
                          subtitle: Text(track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                        );
                      },
                    ),
    );
  }
}
