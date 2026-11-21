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
  });

  const HomeFeed.empty()
      : recent = const [],
        offline = const [],
        shelves = const [];

  final List<Track> recent;
  final List<Track> offline;
  final List<HomeShelf> shelves;

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

    final shelves = <HomeShelf>[];

    if (played.isNotEmpty) {
      shelves.add(HomeShelf(title: 'Heavy rotation', tracks: played));
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

    return HomeFeed(recent: recent, offline: offline, shelves: shelves);
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
