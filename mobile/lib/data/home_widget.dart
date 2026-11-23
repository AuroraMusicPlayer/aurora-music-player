import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Mirrors the current track into the Android home-screen widget.
///
/// The widget reads the same SharedPreferences file Flutter writes, and the
/// channel call only tells Android to repaint. Buttons in the widget send media
/// key events to audio_service, so they control the real playback session.
class HomeWidget {
  static const _channel = MethodChannel('aurora/widget');

  static String? _lastSignature;

  static Future<void> sync({
    Track? track,
    required bool isPlaying,
    String? artworkPath,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    final signature = '${track?.id ?? 'none'}|$isPlaying|${artworkPath != null}';
    if (signature == _lastSignature) return;
    _lastSignature = signature;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('aurora_widget_title', track?.title ?? '');
      await prefs.setString('aurora_widget_artist', track?.artist ?? '');
      await prefs.setBool('aurora_widget_playing', isPlaying);
      await prefs.setString('aurora_widget_art', artworkPath ?? '');
      await _channel.invokeMethod<void>('update');
    } catch (error) {
      if (kDebugMode) debugPrint('home widget: $error');
    }
  }

  static Future<void> clear() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _lastSignature = null;
    await sync(track: null, isPlaying: false);
  }
}
