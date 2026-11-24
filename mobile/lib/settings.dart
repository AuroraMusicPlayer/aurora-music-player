import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preferences. Persisted eagerly; listeners rebuild the UI.
class Settings extends ChangeNotifier {
  Settings(this._prefs);

  static Future<Settings> load() async => Settings(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _kAutoCache = 'auto_cache';
  static const _kPercent = 'auto_cache_percent';
  static const _kWifiOnly = 'auto_cache_wifi_only';
  static const _kBudgetGb = 'cache_budget_gb';
  static const _kPullOnly = 'youtube_pull_only';
  static const _kGooglePrompt = 'google_prompt_shown';

  bool get autoCacheEnabled => _prefs.getBool(_kAutoCache) ?? true;

  set autoCacheEnabled(bool value) {
    _prefs.setBool(_kAutoCache, value);
    notifyListeners();
  }

  /// How much of a track must play before it is saved automatically.
  ///
  /// Listening twice no longer triggers a download; finishing the song does.
  int get autoCachePercent => _prefs.getInt(_kPercent) ?? 80;

  set autoCachePercent(int value) {
    _prefs.setInt(_kPercent, value.clamp(50, 100));
    notifyListeners();
  }

  bool get wifiOnly => _prefs.getBool(_kWifiOnly) ?? true;

  set wifiOnly(bool value) {
    _prefs.setBool(_kWifiOnly, value);
    notifyListeners();
  }

  int get cacheBudgetGb => _prefs.getInt(_kBudgetGb) ?? 4;

  set cacheBudgetGb(int value) {
    _prefs.setInt(_kBudgetGb, value.clamp(1, 64));
    notifyListeners();
  }

  int get cacheBudgetBytes => cacheBudgetGb * 1024 * 1024 * 1024;

  /// When on, sync only reads from YouTube: nothing is ever written back.
  /// Protects the account and the quota when the app is shared.
  /// The sign-in invitation is shown once, not on every launch.
  bool get googlePromptShown => _prefs.getBool(_kGooglePrompt) ?? false;

  Future<void> markGooglePromptShown() async {
    await _prefs.setBool(_kGooglePrompt, true);
    notifyListeners();
  }

  bool get youtubePullOnly => _prefs.getBool(_kPullOnly) ?? false;

  set youtubePullOnly(bool value) {
    _prefs.setBool(_kPullOnly, value);
    notifyListeners();
  }
}
