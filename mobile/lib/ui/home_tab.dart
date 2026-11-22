import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';
import '../data/recommendations.dart';
import 'charts_screen.dart';
import 'search_results_screen.dart';
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
  Track? _continueTrack;
  Duration _continueAt = Duration.zero;

  /// Rebuilding the feed costs YouTube searches, and Google blocks devices
  /// that ask too often. Recompute at most this often; pull-to-refresh always
  /// works for a manual update.
  static const _feedTtl = Duration(minutes: 45);

  @override
  void initState() {
    super.initState();
    widget.services.events.revision.addListener(_onLibraryChanged);
    _loadContinue();
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

  /// Where you stopped last time, so the app opens with a way back in.
  Future<void> _loadContinue() async {
    final id = widget.services.memory.lastTrackId;
    if (id == null) return;
    final track = await widget.services.library.byId(id);
    if (!mounted || track == null) return;
    setState(() {
      _continueTrack = track;
      _continueAt = widget.services.memory.lastPosition;
    });
  }

  Future<void> _resume() async {
    final track = _continueTrack;
    if (track == null) return;
    final at = _continueAt;
    await widget.services.handler.playTracks([track]);
    if (at > const Duration(seconds: 5)) {
      await widget.services.handler.seek(at);
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

  void _openMood(String mood) => _openQuery(mood, '$mood music mix');

  void _openQuery(String title, String query) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchResultsScreen(
          services: widget.services,
          title: title,
          query: query,
        ),
      ),
    );
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

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (_continueTrack != null) _ContinueCard(
          track: _continueTrack!,
          at: _continueAt,
          onTap: _resume,
        ),
        _MoodRow(onPick: _openMood),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Card(
            elevation: 0,
            color: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.trending_up),
              title: const Text('Top charts'),
              subtitle: const Text('Public charts, played from YouTube',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChartsScreen(services: widget.services),
                ),
              ),
            ),
          ),
        ),
        if (feed.artists.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 6),
            child: Text('Your artists',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          SizedBox(
            height: 130,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: feed.artists.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final artist = feed.artists[index];
                return ArtistCircle(
                  artist: artist,
                  onTap: () => _openQuery(artist.name, artist.name),
                );
              },
            ),
          ),
        ],
        for (final shelf in shelves) ShelfView(shelf: shelf, onPlay: _play),
      ],
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


/// Situation shortcuts — the cheapest way to imitate "moods" without a
/// recommendation backend: one search when you tap, nothing up front.
class _MoodRow extends StatelessWidget {
  const _MoodRow({required this.onPick});

  final void Function(String mood) onPick;

  static const _moods = ['Chill', 'Gym', 'Focus', 'Commute', 'Party', 'Sleep'];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        itemCount: _moods.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final mood = _moods[index];
          return ActionChip(
            label: Text(mood),
            backgroundColor: const Color(0xFF1E1E1E),
            side: BorderSide.none,
            onPressed: () => onPick(mood),
          );
        },
      ),
    );
  }
}


/// "Pick up where you left off" — a single card, not a shelf.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.track,
    required this.at,
    required this.onTap,
  });

  final Track track;
  final Duration at;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = track.duration == null || track.duration == 0
        ? 0.0
        : (at.inSeconds / track.duration!).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: track.thumbnail == null
                      ? const ColoredBox(color: Color(0xFF2A2A2A))
                      : Image.network(track.thumbnail!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const ColoredBox(color: Color(0xFF2A2A2A))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Pick up where you left off',
                        style: TextStyle(fontSize: 10, color: Colors.white38)),
                    const SizedBox(height: 2),
                    Text(track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 2,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.play_circle_fill, size: 34),
            ],
          ),
        ),
      ),
    );
  }
}
