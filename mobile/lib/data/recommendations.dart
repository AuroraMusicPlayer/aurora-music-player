import 'library.dart';
import 'models.dart';
import 'youtube_source.dart';

/// A horizontal row on the home screen.
class HomeShelf {
  const HomeShelf({
    required this.title,
    required this.tracks,
    this.round = false,
    this.showArtists = true,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Track> tracks;

  /// Artist-style circular artwork.
  final bool round;

  /// Hide the artist line for compact shelves.
  final bool showArtists;
}

class HomeFeed {
  const HomeFeed({
    required this.recent,
    required this.offline,
    required this.shelves,
    this.artists = const [],
  });

  const HomeFeed.empty()
      : recent = const [],
        offline = const [],
        shelves = const [],
        artists = const [];

  final List<Track> recent;
  final List<Track> offline;
  final List<HomeShelf> shelves;
  final List<ArtistRef> artists;

  bool get isEmpty => recent.isEmpty && offline.isEmpty && shelves.isEmpty;
}

/// Builds the home screen from what the app has observed about your listening.
///
/// No opaque backend: the ranking is visible here.
///   1. Recently played, newest first.
///   2. Heavy rotation = most plays, skips already deducted by [Track.affinity].
///   3. "Because you played X" = a fresh YouTube search seeded by your top
///      artists, filtered to tracks you have not heard yet.
class Recommendations {
  Recommendations(this.library, this.source);

  final Library library;
  final YouTubeSource source;

  Future<HomeFeed> load() async {
    final recent = await library.recent(limit: 20);
    final played = await library.mostPlayed(limit: 20);
    final offline = await library.cached();
    final topArtists = await library.topArtists(limit: 2, minPlays: 2);
    final artistRefs = await library.artistRefs(limit: 12);

    final shelves = <HomeShelf>[];

    if (played.isNotEmpty) {
      shelves.add(HomeShelf(title: 'Heavy rotation', tracks: played));
    }

    // A mix, not a list of history: alternate your most played with the ones
    // you stopped playing, so it feels curated rather than chronological.
    final mix = _buildMix(played, recent);
    if (mix.length >= 4) {
      shelves.add(HomeShelf(
        title: 'Your mix',
        subtitle: 'Your rotation, shuffled by how you listen',
        tracks: mix,
      ));
    }

    // Local-only suggestion: no request, so it is safe to compute every load.
    final forgotten = await library.worthAnotherListen(limit: 12);
    if (forgotten.isNotEmpty) {
      shelves.add(HomeShelf(
        title: 'Worth another listen',
        subtitle: 'You liked these, then stopped playing them',
        tracks: forgotten,
      ));
    }

    final known = {
      ...played.map((t) => t.id),
      ...recent.map((t) => t.id),
      ...offline.map((t) => t.id),
    };

    for (final artist in topArtists) {
      final tracks = await _becauseYouPlayed(artist, known);
      if (tracks.isNotEmpty) {
        shelves.add(HomeShelf(
          title: 'Because you played $artist',
          subtitle: 'Fresh picks, not in your history',
          tracks: tracks,
        ));
      }
      if (shelves.length >= 4) break;
    }

    // A cold start should not be a blank screen.
    if (played.isEmpty && recent.isEmpty) {
      final starter = await _safeSearch('top songs this week', limit: 12);
      if (starter.isNotEmpty) {
        shelves.add(HomeShelf(
          title: 'Start here',
          subtitle: 'Play a few tracks and this becomes your own mix',
          tracks: starter,
        ));
      }
    }

    return HomeFeed(
      recent: recent,
      offline: offline,
      shelves: shelves,
      artists: artistRefs,
    );
  }

  /// Interleaves top plays with recently played, skipping duplicates.
  List<Track> _buildMix(List<Track> played, List<Track> recent) {
    final seen = <String>{};
    final mix = <Track>[];
    final longest = played.length > recent.length ? played.length : recent.length;

    for (var i = 0; i < longest; i++) {
      if (i < played.length && seen.add(played[i].id)) mix.add(played[i]);
      if (i < recent.length && seen.add(recent[i].id)) mix.add(recent[i]);
    }
    return mix.take(20).toList(growable: false);
  }

  Future<List<Track>> _becauseYouPlayed(String artist, Set<String> known) async {
    final results = await _safeSearch('$artist mix', limit: 15);
    return results
        .where((t) => !known.contains(t.id))
        .where((t) => t.artist.toLowerCase() != artist.toLowerCase())
        .take(10)
        .toList(growable: false);
  }

  Future<List<Track>> _safeSearch(String query, {int limit = 12}) async {
    try {
      final results = await source.search(query, limit: limit);
      for (final track in results) {
        await library.remember(track);
      }
      return results;
    } catch (_) {
      // A failed recommendation search must not break the home screen.
      return const [];
    }
  }
}
