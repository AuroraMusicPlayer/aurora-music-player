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
  static const _kQueueIds = 'queue_ids';
  static const _kQueueIndex = 'queue_index';
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

  /// The queue survives restarts, so reopening the app does not throw away the
  /// playlist you were in the middle of.
  Future<void> saveQueue(List<String> ids, int index) async {
    await _prefs.setStringList(_kQueueIds, ids.take(200).toList(growable: false));
    await _prefs.setInt(_kQueueIndex, index);
  }

  List<String> get queueIds =>
      (_prefs.getStringList(_kQueueIds) ?? const []).toList(growable: false);

  int get queueIndex => _prefs.getInt(_kQueueIndex) ?? 0;

  Future<void> clearQueue() async {
    await _prefs.remove(_kQueueIds);
    await _prefs.remove(_kQueueIndex);
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
