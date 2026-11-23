import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';
import '../data/search_ranker.dart';
import '../data/suggestions.dart';
import 'playlist_dialogs.dart';
import 'artwork.dart';

class SearchTab extends StatefulWidget {
  const SearchTab({super.key, required this.services});

  final AppServices services;

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final _controller = TextEditingController();
  final _suggestions = SearchSuggestions();
  Timer? _debounce;
  List<String> _suggested = const [];
  List<Track> _results = const [];
  Set<String> _cachedIds = const {};
  bool _loading = false;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    widget.services.events.revision.addListener(_refreshCached);
    _refreshCached();
  }

  @override
  void dispose() {
    widget.services.events.revision.removeListener(_refreshCached);
    _debounce?.cancel();
    _suggestions.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Suggestions are fetched 280 ms after typing stops, so a burst of
  /// keystrokes produces one request instead of ten.
  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      if (value.trim().length < 2) {
        if (mounted) setState(() => _suggested = const []);
        return;
      }
      final results = await _suggestions.forQuery(value);
      if (!mounted) return;
      // Ignore a slow response for a query the user has moved past.
      if (_controller.text.trim() != value.trim()) return;
      setState(() => _suggested = results);
    });
  }

  Future<void> _submit(String query) async {
    _debounce?.cancel();
    _controller.text = query;
    setState(() => _suggested = const []);
    FocusScope.of(context).unfocus();
    await _search(query);
  }

  Future<void> _refreshCached() async {
    final cached = await widget.services.library.cached();
    if (!mounted) return;
    setState(() => _cachedIds = cached.map((t) => t.id).toSet());
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _query = q;
    });

    try {
      final raw = await widget.services.source.search(q);

      // Re-order by what this library knows: a known artist in the query
      // outranks a same-titled song from somebody unrelated.
      final scores = await widget.services.library.artistScores();
      final results = SearchRanker(scores).rank(q, raw);

      for (final track in results) {
        await widget.services.library.remember(track);
      }
      await widget.services.memory.addSearch(q);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  /// Long-press menu: like, download, add to playlist — the three things you
  /// want from a search result without opening the player.
  Future<void> _showActions(Track track) async {
    final services = widget.services;
    final stored = await services.library.byId(track.id) ?? track;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF141414),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(track.artist, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                stored.favorite ? Icons.favorite : Icons.favorite_border,
                color: stored.favorite ? Colors.redAccent : null,
              ),
              title: Text(stored.favorite ? 'Remove from liked songs' : 'Like'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await services.library.setFavorite(track.id, !stored.favorite);
                if (!stored.favorite) {
                  // Liking implies keeping it offline.
                  await services.cache
                      .download(stored, origin: 'manual')
                      .catchError((Object _) => null);
                }
                services.events.bump();
                await _refreshCached();
              },
            ),
            ListTile(
              leading: Icon(stored.isCached
                  ? Icons.offline_pin
                  : Icons.download_outlined),
              title: Text(stored.isCached ? 'Remove download' : 'Download'),
              onTap: () async {
                Navigator.pop(sheetContext);
                if (stored.isCached) {
                  await services.cache.remove(stored);
                  await _refreshCached();
                } else {
                  await _download(track);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.radio),
              title: const Text('Start radio'),
              subtitle: const Text('Endless mix from this artist',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              onTap: () async {
                Navigator.pop(sheetContext);
                await services.library.remember(track);
                await services.handler.startRadio(track);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_play),
              title: const Text('Play next'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await services.library.remember(track);
                await services.handler.playNext(track);
                messenger(context).showSnackBar(
                    SnackBar(content: Text('Playing ${track.title} next')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue),
              title: const Text('Add to queue'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await services.library.remember(track);
                await services.handler.addToQueue(track);
                messenger(context).showSnackBar(
                    SnackBar(content: Text('Added ${track.title} to queue')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Add to playlist'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await services.library.remember(track);
                if (!context.mounted) return;
                await showAddToPlaylist(context, services, track);
              },
            ),
          ],
        ),
      ),
    );
  }

  ScaffoldMessengerState messenger(BuildContext context) =>
      ScaffoldMessenger.of(context);

  Future<void> _download(Track track) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('Saving ${track.title}…')));
    try {
      await widget.services.cache.download(track, origin: 'manual', force: true);
      await _refreshCached();
      messenger.showSnackBar(SnackBar(content: Text('Saved ${track.title}')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text('Search',
            style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SearchBar(
              controller: _controller,
              hintText: 'Songs, artists, albums',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              backgroundColor: const WidgetStatePropertyAll(Color(0xFF1F1F1F)),
              onChanged: _onQueryChanged,
              onSubmitted: _submit,
              trailing: [
                if (_controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _controller.clear();
                      setState(() {
                        _results = const [];
                        _suggested = const [];
                      });
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_suggested.isNotEmpty) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (final suggestion in _suggested)
            ListTile(
              dense: true,
              leading: const Icon(Icons.search, size: 18),
              title: Text(suggestion, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.north_west, size: 14),
              onTap: () => _submit(suggestion),
            ),
        ],
      );
    }

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => _search(_query),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      final recent = widget.services.memory.recentSearches;
      return ListView(
        children: [
          if (recent.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Recent searches',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            for (final query in recent)
              ListTile(
                leading: const Icon(Icons.history, size: 18),
                title: Text(query, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.north_west, size: 14),
                onTap: () {
                  _controller.text = query;
                  _search(query);
                },
              ),
          ],
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Search YouTube. Long-press a result to like it, download it or '
              'start a radio.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
        ],
      );
    }

    return ValueListenableBuilder<Set<String>>(
      valueListenable: widget.services.cache.downloading,
      builder: (context, downloading, _) {
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: _results.length,
          itemBuilder: (context, index) {
            final track = _results[index];
            return _ResultTile(
              track: track,
              cached: _cachedIds.contains(track.id),
              downloading: downloading.contains(track.id),
              progress: widget.services.cache.progress.value[track.id],
              onTap: () => widget.services.handler
                  .playTracks(_results, startIndex: index),
              onLongPress: () => _showActions(track),
              onDownload: () => _download(track),
            );
          },
        );
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.track,
    required this.cached,
    required this.downloading,
    required this.onTap,
    this.progress,
    required this.onLongPress,
    required this.onDownload,
  });

  final Track track;
  final bool cached;
  final bool downloading;
  final double? progress;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final duration = track.length;
    final clock = duration == null
        ? ''
        : '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 56,
          height: 56,
          child: track.thumbnail == null
              ? const ColoredBox(color: Color(0xFF1E1E1E))
              : artworkForVideo(track.id),
        ),
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        track.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (clock.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(clock,
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ),
          if (downloading)
            SizedBox(
              width: 34,
              child: Text(
                progress == null ? '…' : '${(progress! * 100).round()}%',
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            )
          else if (cached)
            const Icon(Icons.offline_pin_outlined,
                size: 18, color: Colors.greenAccent)
          else
            IconButton(
              tooltip: 'Download',
              icon: const Icon(Icons.download_outlined, size: 20),
              onPressed: onDownload,
            ),
        ],
      ),
    );
  }
}
