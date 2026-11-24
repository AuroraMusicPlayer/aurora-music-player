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
    r'\b('
    // English
    r'podcast|episode|ep\.?\s*\d+|interview|talk\s*show|radio\s*show|'
    r'livestream|live\s*stream|press\s*conference|reaction|breakdown|'
    r'explained|documentary|audiobook|chapter\s*\d+|asmr|debate|news|'
    r'full\s+(movie|film|episode)|season\s*\d+|part\s*\d+\s*of\s*\d+|'
    // Business, tech and current-affairs uploads: the "NVIDIA CEO" class
    r'breaking|earnings|stock\s*market|shareholders?|investors?|ceo|'
    r'acquisition|merger|economy|politics|election|sanctions|keynote|panel|'
    r'webinar|lecture|tutorial|course|unboxing|trailer|teaser|'
    r'explained|analysis|documentary|'
    // Albanian — most of the catalogue this app is used with
    r'dokumentar\w*|emision\w*|intervist\w*|podkast\w*|shfaqje\w*|lajme\w*|'
    r'tregim\w*|bised\w*|film\s+shqip|film\s+i\s+plot[eë]|epizod\w*|sezon\w*|'
    // Italian
    r'documentario\w*|intervista\w*|puntata\w*|notizie\w*'
    r')\b',
    caseSensitive: false,
  );

  static final _showChannel = RegExp(
    r'(podcast|talks?|shows?|news|radio|network|media|tv\b|'
    r'bloomberg|cnbc|reuters|forbes|business|finance|insider|tedx?|vox|'
    r'bbc|cnn|al\s*jazeera|euronews|dw\b|'
    r'dokumentar|emision|lajme)',
    caseSensitive: false,
  );

  /// A song is short. Business reports, panels and documentaries are not.
  /// Used where the app chooses on the user's behalf (autoplay, radio), never
  /// for a manual search.
  static const maxSongLikeSeconds = 9 * 60;

  static bool isSongLike(Track track) {
    if (!isMusic(track)) return false;
    final seconds = track.duration;
    return seconds == null || seconds <= maxSongLikeSeconds;
  }

  /// Normalised title for duplicate detection: accents, punctuation, brackets
  /// and "feat." noise removed, so the same recording counts once.
  static String titleKey(String title) {
    const accents = {
      'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
      'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ẽ': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n', 'ß': 'ss', 'æ': 'ae', 'ø': 'o',
    };

    var key = title.toLowerCase();
    accents.forEach((from, to) => key = key.replaceAll(from, to));
    key = key.replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ');
    key = key.replaceAll(RegExp(r'\b(feat|ft|featuring)\.?\s.+$'), ' ');
    key = key.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    return key.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

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
