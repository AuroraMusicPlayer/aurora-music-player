import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

/// Drives the iOS Live Activity (Dynamic Island + lock screen card).
///
/// This exists because the *system* Now Playing widget cannot open a
/// self-signed app: iOS resolves that tap through LaunchServices, which fails
/// for Feather/AltStore installs. Our own Live Activity uses `widgetURL`, so
/// tapping it opens the app regardless of how it was signed.
class LiveActivity {
  static const _channel = MethodChannel('aurora/live_activity');

  static String? _lastSignature;

  /// Only sends when something meaningful changed: Live Activities are
  /// expensive to update, and a position tick is not meaningful.
  static Future<void> sync({
    required bool isPlaying,
    Track? track,
    Duration position = Duration.zero,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;

    final current = track;
    if (current == null) {
      await end();
      return;
    }

    final signature = '${current.id}|$isPlaying';
    if (signature == _lastSignature) return;
    _lastSignature = signature;

    try {
      await _channel.invokeMethod<void>('update', {
        'id': current.id,
        'title': current.title,
        'artist': current.artist,
        'isPlaying': isPlaying,
        'position': position.inMilliseconds / 1000.0,
        'duration': (current.duration ?? 0).toDouble(),
      });
    } catch (error) {
      // A missing extension, an old iOS version or a disabled setting all land
      // here; none of them should affect playback.
      if (kDebugMode) debugPrint('live activity: $error');
    }
  }

  static Future<void> end() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    if (_lastSignature == null) return;
    _lastSignature = null;
    try {
      await _channel.invokeMethod<void>('end');
    } catch (_) {}
  }
}
