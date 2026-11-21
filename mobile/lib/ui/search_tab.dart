import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';

class SearchTab extends StatefulWidget {
  const SearchTab({super.key, required this.services});

  final AppServices services;

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final _controller = TextEditingController();
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
    _controller.dispose();
    super.dispose();
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
      final results = await widget.services.source.search(q);
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
        _loading = false;
        _error = '$error';
      });
    }
  }

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
              onSubmitted: _search,
              trailing: [
                if (_controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _results = const []);
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
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Search YouTube. Long-press a result to keep it offline.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final track = _results[index];
        return _ResultTile(
          track: track,
          cached: _cachedIds.contains(track.id),
          onTap: () => widget.services.handler
              .playTracks(_results, startIndex: index),
          onLongPress: () => _download(track),
        );
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.track,
    required this.cached,
    required this.onTap,
    required this.onLongPress,
  });

  final Track track;
  final bool cached;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

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
              : Image.network(track.thumbnail!, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: Color(0xFF1E1E1E))),
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
          if (cached)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.offline_pin_outlined,
                  size: 16, color: Colors.greenAccent),
            ),
          if (clock.isNotEmpty)
            Text(clock, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }
}
