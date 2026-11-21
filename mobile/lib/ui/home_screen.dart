import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';
import 'player_sheet.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  List<Track> _results = const [];
  List<Track> _cached = const [];
  Set<String> _cachedIds = const {};
  bool _loading = false;
  String? _error;
  String _query = '';
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    widget.services.events.revision.addListener(_refreshLibrary);
    _refreshLibrary();
  }

  @override
  void dispose() {
    widget.services.events.revision.removeListener(_refreshLibrary);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshLibrary() async {
    final cached = await widget.services.library.cached();
    if (!mounted) return;
    setState(() {
      _cached = cached;
      _cachedIds = cached.map((t) => t.id).toSet();
    });
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
      await _refreshLibrary();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _openTrack(Track track) async {
    final start = _results.indexWhere((t) => t.id == track.id);
    await widget.services.handler.playTracks(_results, startIndex: start < 0 ? 0 : start);
    if (!mounted) return;
    showPlayerSheet(context, widget.services);
  }

  Future<void> _download(Track track) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('Downloading ${track.title}…')));
    try {
      await widget.services.cache.download(track, origin: 'manual', force: true);
      await _refreshLibrary();
      messenger.showSnackBar(SnackBar(content: Text('Saved ${track.title}')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Download failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text('Aurora'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettingsScreen(services: widget.services),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Songs, artists, anything on YouTube',
              leading: const Icon(Icons.search),
              onSubmitted: _search,
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _results = const []);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _buildSearchTab(),
          _buildLibraryTab(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniPlayer(services: widget.services),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (index) => setState(() => _tab = index),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
              NavigationDestination(icon: Icon(Icons.download_done), label: 'Offline'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorState(
        message: _error!,
        onRetry: () => _search(_query),
        onSettings: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SettingsScreen(services: widget.services)),
        ),
      );
    }
    if (_results.isEmpty) {
      return _EmptyState(
        icon: Icons.graphic_eq,
        title: 'Find something to play',
        subtitle: 'Search YouTube and the first tap starts the queue. '
            'Play a track ${widget.services.settings.autoCacheThreshold} times and it saves itself for offline.',
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final track = _results[index];
        return _TrackTile(
          track: track,
          cached: _cachedIds.contains(track.id),
          onTap: () => _openTrack(track),
          onLongPress: () => _download(track),
        );
      },
    );
  }

  Widget _buildLibraryTab() {
    if (_cached.isEmpty) {
      return _EmptyState(
        icon: Icons.download_done,
        title: 'Nothing saved yet',
        subtitle: 'Tracks you replay, and anything you long-press to keep, appear here.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _cached.length,
      itemBuilder: (context, index) {
        final track = _cached[index];
        return _TrackTile(
          track: track,
          cached: true,
          subtitle: _autoLabel(track),
          onTap: () => widget.services.handler.playTracks(_cached, startIndex: index),
          onLongPress: () async {
            await widget.services.cache.remove(track);
            await _refreshLibrary();
          },
        );
      },
    );
  }

  String _autoLabel(Track track) {
    final source = track.cacheOrigin == 'auto' ? 'Cached automatically' : 'Saved by you';
    final mb = (track.bytes / (1024 * 1024)).toStringAsFixed(1);
    return '$source · $mb MB · played ${track.playCount}×';
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.cached,
    required this.onTap,
    required this.onLongPress,
    this.subtitle,
  });

  final Track track;
  final bool cached;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final duration = track.length;
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 52,
          height: 52,
          child: track.thumbnail == null
              ? const ColoredBox(color: Colors.white12)
              : Image.network(track.thumbnail!, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.white12)),
        ),
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitle ?? track.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cached)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.offline_pin, size: 18, color: Colors.greenAccent),
            ),
          if (duration != null)
            Text(_format(duration), style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  static String _format(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: services.handler.mediaItem.stream,
      builder: (context, snapshot) {
        final item = snapshot.data;
        if (item == null) return const SizedBox.shrink();

        return StreamBuilder<PlaybackState>(
          stream: services.handler.playbackState.stream,
          builder: (context, playbackSnapshot) {
            final playing = playbackSnapshot.data?.playing ?? false;
            return Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: InkWell(
                onTap: () => showPlayerSheet(context, services),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: item.artUri == null
                              ? const ColoredBox(color: Colors.white12)
                              : Image.network(item.artUri.toString(), fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(item.artist ?? '',
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                        onPressed: () => playing ? services.handler.pause() : services.handler.play(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        onPressed: services.handler.skipToNext,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry, required this.onSettings});

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 16),
            const Text('Couldn\'t reach YouTube', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              children: [
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
                OutlinedButton(onPressed: onSettings, child: const Text('Settings')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
