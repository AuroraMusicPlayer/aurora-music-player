import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';
import '../data/recommendations.dart';
import 'settings_screen.dart';
import 'widgets.dart';

/// The feed: built from what you actually listen to.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key, required this.services});

  final AppServices services;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  HomeFeed? _feed;
  bool _loading = false;
  String? _error;
  DateTime? _loadedAt;

  /// Rebuilding the feed costs YouTube searches, and Google blocks devices
  /// that ask too often. Recompute at most this often; pull-to-refresh always
  /// works for a manual update.
  static const _feedTtl = Duration(minutes: 45);

  @override
  void initState() {
    super.initState();
    widget.services.events.revision.addListener(_onLibraryChanged);
    _load();
  }

  @override
  void dispose() {
    widget.services.events.revision.removeListener(_onLibraryChanged);
    super.dispose();
  }

  void _onLibraryChanged() {
    final loadedAt = _loadedAt;
    if (loadedAt == null || DateTime.now().difference(loadedAt) > _feedTtl) {
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final feed = Recommendations(
        widget.services.library,
        widget.services.source,
      ).load();
      final result = await feed;
      if (!mounted) return;
      setState(() {
        _feed = result;
        _error = null;
        _loadedAt = DateTime.now();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _play(List<Track> tracks, int index) {
    widget.services.handler.playTracks(tracks, startIndex: index);
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text(
          'Aurora',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
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
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: feed == null
            ? ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.6,
                    child: Center(
                      child: _error == null
                          ? const CircularProgressIndicator()
                          : _ErrorView(message: _error!, onRetry: _load),
                    ),
                  ),
                ],
              )
            : _buildFeed(feed),
      ),
    );
  }

  Widget _buildFeed(HomeFeed feed) {
    if (feed.isEmpty) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.5,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.graphic_eq,
                        size: 48, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 16),
                    const Text('Nothing here yet',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    const Text(
                      'Play a few songs from Search. This screen then fills with '
                      'your rotation and picks based on those artists.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final shelves = <HomeShelf>[
      if (feed.recent.isNotEmpty)
        HomeShelf(title: 'Listen again', subtitle: 'Picked up where you left off', tracks: feed.recent),
      ...feed.shelves,
      if (feed.offline.isNotEmpty)
        HomeShelf(title: 'Downloaded', subtitle: 'Plays without a connection', tracks: feed.offline),
    ];

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: shelves.length,
      itemBuilder: (context, index) => ShelfView(
        shelf: shelves[index],
        onPlay: _play,
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 40),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
