import 'models.dart';

/// Decides when a track earns a permanent copy on the device.
///
/// The rule is deliberately simple enough to explain in the UI:
///
///   plays − early skips ≥ threshold
///
/// Skips count against a track, so a song you keep rejecting never takes up
/// space no matter how many times it lands in a queue by accident.
class AutoCachePolicy {
  const AutoCachePolicy({
    this.enabled = true,
    required this.threshold,
    this.maxDuration = const Duration(minutes: 20),
  });

  final bool enabled;
  final int threshold;

  /// Podcast-length uploads would eat the whole budget, so they need to be
  /// cached by hand.
  final Duration maxDuration;

  bool shouldCache(Track track) {
    if (track.isCached) return false;

    // Favourites are explicit intent; cache them even if auto-cache is off.
    if (track.favorite) return true;
    if (!enabled) return false;
    if (track.affinity < threshold) return false;

    final seconds = track.duration;
    if (seconds != null && seconds > maxDuration.inSeconds) return false;
    return true;
  }

  /// A play only counts once playback reaches the shorter of 30s or half the
  /// track, the same convention streaming apps use. Anything switched away
  /// from before that is a skip.
  static Duration qualifiedAfter(Track track) {
    const thirty = Duration(seconds: 30);
    final length = track.length;
    if (length == null) return thirty;
    final half = Duration(milliseconds: length.inMilliseconds ~/ 2);
    return half < thirty ? half : thirty;
  }
}
