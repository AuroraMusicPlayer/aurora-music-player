import 'models.dart';

/// Re-orders YouTube search results using what this library already knows.
///
/// The problem it solves: searching "noizy pwa" returns an unrelated song whose
/// *title* happens to contain "pwa", because YouTube ranks by its own signals.
/// If the account has played Noizy before, that is decisive evidence, and a
/// result from an unrelated artist should not be able to win.
///
/// The score is deliberately simple and explainable:
///   position prior + artist affinity + token matches − penalties
class SearchRanker {
  const SearchRanker(this.artistScores);

  /// Artist name (lowercase) → plays minus skips.
  final Map<String, int> artistScores;

  List<Track> rank(String query, List<Track> results) {
    if (results.length < 2) return results;

    final tokens = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 1)
        .toList(growable: false);
    if (tokens.isEmpty) return results;

    // Artists the user has actually listened to that the query seems to name.
    final knownQueryArtists = artistScores.keys
        .where((artist) =>
            tokens.any((token) => artist.contains(token) || token.contains(artist)))
        .toList(growable: false);

    final scored = <({Track track, double score})>[];
    for (var position = 0; position < results.length; position++) {
      final track = results[position];
      final artist = track.artist.toLowerCase();
      final title = track.title.toLowerCase();

      var score = 1.0 / (1 + position); // YouTube's own order still counts

      final affinity = artistScores.entries
          .where((entry) => artist.contains(entry.key))
          .fold<int>(0, (sum, entry) => sum + entry.value);
      if (affinity > 0) score += (affinity.clamp(0, 10)) * 0.12;

      final matchesArtist = tokens.any(artist.contains);
      final matchesTitle = tokens.any(title.contains);
      if (matchesArtist) score += 0.8;
      if (matchesTitle) score += 0.3;
      if (!matchesArtist && !matchesTitle) score -= 1.0;

      // The decisive rule: if the query names an artist we know, a result from
      // somebody else loses.
      if (knownQueryArtists.isNotEmpty && !matchesArtist) score -= 2.0;

      scored.add((track: track, score: score));
    }

    // If we recognised the artist in the query and enough results came from
    // them, drop the rest entirely rather than trusting a title coincidence.
    if (knownQueryArtists.isNotEmpty) {
      final byArtist = scored
          .where((entry) => knownQueryArtists
              .any((artist) => entry.track.artist.toLowerCase().contains(artist)))
          .toList(growable: false);

      if (byArtist.length >= 3) {
        byArtist.sort((a, b) => b.score.compareTo(a.score));
        return byArtist.map((entry) => entry.track).toList(growable: false);
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.map((entry) => entry.track).toList(growable: false);
  }
}
