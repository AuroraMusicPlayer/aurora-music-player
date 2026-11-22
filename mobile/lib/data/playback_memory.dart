import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// What the app remembers between launches: where you were in a track, and
/// what you searched for. Deliberately local — no account, no syncing.
class PlaybackMemory {
  PlaybackMemory(this._prefs);

  static Future<PlaybackMemory> load() async =>
      PlaybackMemory(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _kTrackId = 'last_track_id';
  static const _kPosition = 'last_position_ms';
  static const _kSearches = 'recent_searches';
  static const _maxSearches = 8;

  String? get lastTrackId => _prefs.getString(_kTrackId);

  Duration get lastPosition =>
      Duration(milliseconds: _prefs.getInt(_kPosition) ?? 0);

  Future<void> save(Track track, Duration position) async {
    // Ignore the first seconds; a track you barely started is not worth
    // resuming and would just be noise on the home screen.
    if (position.inSeconds < 5) return;
    await _prefs.setString(_kTrackId, track.id);
    await _prefs.setInt(_kPosition, position.inMilliseconds);
  }

  Future<void> clear() async {
    await _prefs.remove(_kTrackId);
    await _prefs.remove(_kPosition);
  }

  List<String> get recentSearches =>
      (_prefs.getStringList(_kSearches) ?? const []).toList(growable: false);

  Future<void> addSearch(String query) async {
    final cleaned = query.trim();
    if (cleaned.isEmpty) return;

    final existing = _prefs.getStringList(_kSearches) ?? <String>[];
    final updated = [
      cleaned,
      ...existing.where((q) => q.toLowerCase() != cleaned.toLowerCase()),
    ].take(_maxSearches).toList(growable: false);

    await _prefs.setStringList(_kSearches, updated);
  }

  Future<void> clearSearches() => _prefs.remove(_kSearches);

  /// Exposed for diagnostics and future export.
  String debugState() => jsonEncode({
        'lastTrackId': lastTrackId,
        'positionMs': lastPosition.inMilliseconds,
        'searches': recentSearches,
      });
}
