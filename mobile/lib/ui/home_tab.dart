import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';
import '../data/recommendations.dart';
import '../data/youtube_library.dart';
import 'artist_screen.dart';
import 'charts_screen.dart';
import 'search_results_screen.dart';
import 'settings_screen.dart';
import 'widgets.dart';

/// The feed: built from what you actually listen to.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key, required this.services, this.onOpenSearch});

  final AppServices services;
  final VoidCallback? onOpenSearch;

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
  List<Track> _quickPicks = const [];
  DateTime? _channelsLoadedAt;
  List<Track> _youtubeLikes = const [];

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
      // Signed-in accounts also get their own channels; this costs a handful of
      // quota units, so it is cached for an hour.
      unawaited(_loadChannels(result));
      unawaited(_loadYoutubeLikes());
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Recent uploads from the channels the signed-in account follows. This is
  /// the closest thing to YouTube Music's own suggestions that its API allows.
  Future<void> _loadChannels(HomeFeed feed) async {
    final services = widget.services;
    if (!services.google.isConfigured || services.google.user == null) return;

    final loadedAt = _channelsLoadedAt;
    if (loadedAt != null &&
        DateTime.now().difference(loadedAt) < const Duration(minutes: 60)) {
      return;
    }

    YouTubeLibrary? reader;
    try {
      reader = YouTubeLibrary(services.google);
      final tracks = await reader.recentFromSubscriptions();
      if (!mounted || tracks.isEmpty) return;

      for (final track in tracks) {
        await services.library.remember(track);
      }
      _channelsLoadedAt = DateTime.now();
      if (!mounted) return;
      setState(() {
        feed.shelves.insert(
          0,
          HomeShelf(
            title: 'From your channels',
            subtitle: 'Recent uploads from who you follow on YouTube',
            tracks: tracks,
          ),
        );
      });
    } catch (_) {
      // Suggestions are a bonus; never surface an error for them.
    } finally {
      reader?.dispose();
    }
  }

  /// The songs you liked in YouTube Music, straight on to Home.
  ///
  /// YouTube exposes neither listening history nor its recommender, so this is
  /// the strongest signal available: your real likes, newest first. The local
  /// copy renders immediately; it is refreshed at most every six hours.
  Future<void> _loadYoutubeLikes() async {
    final services = widget.services;
    if (!services.google.isConfigured || services.google.user == null) return;

    final stored = await services.library.youtubeLikes();
    if (stored.isNotEmpty && mounted) {
      setState(() => _youtubeLikes = _freshOnly(stored));
    }

    const ttl = Duration(hours: 6);
    final fetchedAt = DateTime.tryParse(
      await services.library.syncValue('youtube_like_sync', 'fetched_at') ?? '',
    );
    if (fetchedAt != null &&
        DateTime.now().toUtc().difference(fetchedAt) < ttl) {
      return;
    }

    YouTubeLibrary? reader;
    try {
      reader = YouTubeLibrary(services.google);
      final likedAt = <String, DateTime>{};
      final tracks = await reader.likedTracks(likedAt: likedAt);
      if (tracks.isEmpty) return;

      final now = DateTime.now().toUtc();
      for (final track in tracks) {
        await services.library.remember(track);
        await services.library.setSyncValue(
          'youtube_like',
          track.id,
          (likedAt[track.id] ?? now).toIso8601String(),
        );
      }
      await services.library
          .setSyncValue('youtube_like_sync', 'fetched_at', now.toIso8601String());

      final refreshed = await services.library.youtubeLikes();
      if (!mounted) return;
      setState(() => _youtubeLikes = _freshOnly(refreshed));
    } catch (_) {
      // A bonus shelf: a failed lookup must never disturb the feed.
    } finally {
      reader?.dispose();
    }
  }

  /// Anything played today already shows up in "Listen again"; the shelf is
  /// meant to add to that list, not repeat it.
  List<Track> _freshOnly(List<Track> tracks) {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    return tracks
        .where((t) => t.lastPlayed == null || t.lastPlayed!.isBefore(cutoff))
        .take(12)
        .toList(growable: false);
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
      // A cold install should still be usable: the shortcuts that need no
      // listening history come first, the explanation second.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 128),
        children: [
          _MoodRow(onPick: _openMood),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Card(
              elevation: 0,
              color: const Color(0xFF1A1A1A),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          if (_youtubeLikes.isNotEmpty)
            ShelfView(
              shelf: HomeShelf(
                title: 'From your YouTube',
                subtitle: 'What you liked in YouTube Music',
                tracks: _youtubeLikes,
              ),
              onPlay: _play,
            )
          else ...[
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  Icon(Icons.graphic_eq,
                      size: 44, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 14),
                  const Text('Nothing here yet',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  const SizedBox(height: 8),
                  const Text(
                    'Search for a few songs you like. This screen then fills with '
                    'your rotation, quick picks and mixes built from those artists.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: FilledButton.icon(
              onPressed: widget.onOpenSearch,
              icon: const Icon(Icons.search),
              label: const Text('Search music'),
            ),
          ),
        ],
      );
    }

    // The same tracks that head your shelves, in the compact two-column form
    // YouTube Music uses for quick picks.
    final source = feed.shelves.isNotEmpty
        ? feed.shelves.first.tracks
        : feed.recent;
    _quickPicks = source.take(6).toList(growable: false);

    final shelves = <HomeShelf>[
      if (_youtubeLikes.isNotEmpty)
        HomeShelf(
          title: 'From your YouTube',
          subtitle: 'What you liked in YouTube Music',
          tracks: _youtubeLikes,
        ),
      if (feed.recent.isNotEmpty)
        HomeShelf(title: 'Listen again', subtitle: 'Picked up where you left off', tracks: feed.recent),
      ...feed.shelves,
      if (feed.offline.isNotEmpty)
        HomeShelf(title: 'Downloaded', subtitle: 'Plays without a connection', tracks: feed.offline),
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      // Clear the navigation bar and the mini player so the last shelf is
      // never cut off.
      padding: const EdgeInsets.only(bottom: 128),
      children: [
        if (_continueTrack != null) _ContinueCard(
          track: _continueTrack!,
          at: _continueAt,
          onTap: _resume,
        ),
        if (_quickPicks.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Text('Quick picks',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          _QuickPicksGrid(
            tracks: _quickPicks,
            onPlay: (index) => _play(_quickPicks, index),
          ),
        ],
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
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ArtistScreen(
                        services: widget.services,
                        artist: artist.name,
                        thumbnail: artist.thumbnail,
                      ),
                    ),
                  ),
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


/// Two columns of compact rows, the way YouTube Music opens its home screen.
class _QuickPicksGrid extends StatelessWidget {
  const _QuickPicksGrid({required this.tracks, required this.onPlay});

  final List<Track> tracks;
  final void Function(int index) onPlay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 2.9,
        ),
        itemCount: tracks.length,
        itemBuilder: (context, index) {
          final track = tracks[index];
          return InkWell(
            onTap: () => onPlay(index),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: track.thumbnail == null
                          ? const ColoredBox(color: Color(0xFF222222))
                          : Image.network(track.thumbnail!, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const ColoredBox(color: Color(0xFF222222))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(track.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 2),
                        Text(track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 10, color: Colors.white54)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
