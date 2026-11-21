import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preferences. Persisted eagerly; listeners rebuild the UI.
class Settings extends ChangeNotifier {
  Settings(this._prefs);

  static Future<Settings> load() async => Settings(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _kAutoCache = 'auto_cache';
  static const _kThreshold = 'auto_cache_threshold';
  static const _kWifiOnly = 'auto_cache_wifi_only';
  static const _kBudgetGb = 'cache_budget_gb';

  bool get autoCacheEnabled => _prefs.getBool(_kAutoCache) ?? true;

  set autoCacheEnabled(bool value) {
    _prefs.setBool(_kAutoCache, value);
    notifyListeners();
  }

  /// Qualified plays required before a track is kept offline automatically.
  int get autoCacheThreshold => _prefs.getInt(_kThreshold) ?? 2;

  set autoCacheThreshold(int value) {
    _prefs.setInt(_kThreshold, value.clamp(1, 10));
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
}
