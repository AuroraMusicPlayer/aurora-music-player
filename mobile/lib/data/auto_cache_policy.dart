import 'models.dart';

/// Decides when a track earns a permanent copy on the device.
///
/// One rule, deliberately: **finish the song**. A track is saved once playback
/// passes [percent] of its length. Repeating a song you never finish no longer
/// saves it — play counts still drive ranking and stats, they just stop
/// triggering downloads.
///
/// Favourites are the exception: hearting something is explicit intent.
class AutoCachePolicy {
  const AutoCachePolicy({
    this.enabled = true,
    this.percent = 80,
    this.maxDuration = const Duration(minutes: 20),
  });

  final bool enabled;

  /// How much of a track counts as "listened": 50–100.
  final int percent;

  /// Podcast-length uploads need a manual save, or one file eats the budget.
  final Duration maxDuration;

  /// Fraction of the track that must play before it is saved.
  double get fraction => percent.clamp(50, 100) / 100;

  bool shouldCache(Track track) {
    if (track.isCached) return false;
    if (track.favorite) return true;
    if (!enabled) return false;

    final seconds = track.duration;
    if (seconds != null && seconds > maxDuration.inSeconds) return false;
    return true;
  }

  /// Playback deadline for the "long listen" check. Kept for the UI, which shows
  /// nothing about it, and for tests.
  Duration cachePoint(Track track) {
    final length = track.length;
    if (length == null) return Duration.zero;
    return Duration(milliseconds: (length.inMilliseconds * fraction).round());
  }

  /// A play counts once playback reaches the shorter of 30s or half the track,
  /// the convention streaming apps use. Skipping before that is a skip.
  static Duration qualifiedAfter(Track track) {
    const thirty = Duration(seconds: 30);
    final length = track.length;
    if (length == null) return thirty;
    final half = Duration(milliseconds: length.inMilliseconds ~/ 2);
    return half < thirty ? half : thirty;
  }
}
