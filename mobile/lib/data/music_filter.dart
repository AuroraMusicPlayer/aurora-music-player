import 'models.dart';

/// Decides whether a result is plausibly music.
///
/// YouTube has no "track" concept: a search can return podcasts, talk shows,
/// interviews, live streams and hour-long uploads. Playing those in the middle
/// of a queue is the complaint this addresses, so the rules are deliberately
/// conservative — only clear cases are rejected, and a search that finds
/// nothing else still shows what it found.
class MusicFilter {
  /// Anything longer than this is almost never a song.
  static const maxSongSeconds = 20 * 60;

  static final _showTitle = RegExp(
    r'\b(podcast|episode|ep\.?\s*\d+|interview|talk\s*show|radio\s*show|'
    r'livestream|live\s*stream|press\s*conference|reaction|breakdown|'
    r'explained|documentary|audiobook|chapter\s*\d+|asmr|debate|news)\b',
    caseSensitive: false,
  );

  static final _showChannel = RegExp(
    r'(podcast|talks?|shows?|news|radio|network|media\s*house|tv$)',
    caseSensitive: false,
  );

  /// True when the result looks like music rather than spoken content.
  static bool isMusic(Track track) {
    final seconds = track.duration;
    if (seconds != null && seconds > maxSongSeconds) return false;
    if (_showTitle.hasMatch(track.title)) return false;
    if (_showChannel.hasMatch(track.artist)) return false;
    return true;
  }

  /// Filters a list, but never to nothing: if every result looks like a show,
  /// returning them beats returning an empty screen.
  static List<Track> songsOnly(List<Track> tracks) {
    final music = tracks.where(isMusic).toList(growable: false);
    return music.isEmpty ? tracks : music;
  }
}
