import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// User-configurable settings (design: `AppSettings`).
class AppSettings {
  const AppSettings({
    this.sensitivity = SettingsStore.defaultSensitivity,
    this.naturalScrolling = false,
    this.tapToClick = true,
  });

  final double sensitivity;
  final bool naturalScrolling;
  final bool tapToClick;

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.sensitivity == sensitivity &&
      other.naturalScrolling == naturalScrolling &&
      other.tapToClick == tapToClick;

  @override
  int get hashCode => Object.hash(sensitivity, naturalScrolling, tapToClick);

  @override
  String toString() =>
      'AppSettings(sensitivity: $sensitivity, naturalScrolling: '
      '$naturalScrolling, tapToClick: $tapToClick)';
}

/// Persists settings with `shared_preferences`.
///
/// Sensitivity is validated against [minSensitivity]..[maxSensitivity]
/// (inclusive); out-of-range or non-finite values are rejected and the
/// previous value is retained. No exception is thrown for invalid input.
class SettingsStore {
  SettingsStore._(this._prefs) {
    _settings = AppSettings(
      sensitivity: _readSensitivity(),
      naturalScrolling: _prefs.getBool(naturalScrollingKey) ?? false,
      tapToClick: _prefs.getBool(tapToClickKey) ?? true,
    );
  }

  static const double minSensitivity = 0.5;
  static const double maxSensitivity = 5.0;
  static const double defaultSensitivity = 1.0;

  static const String sensitivityKey = 'settings.sensitivity';
  static const String naturalScrollingKey = 'settings.naturalScrolling';
  static const String tapToClickKey = 'settings.tapToClick';

  /// Loads the store, reading any previously persisted values.
  static Future<SettingsStore> load([SharedPreferences? prefs]) async =>
      SettingsStore._(prefs ?? await SharedPreferences.getInstance());

  /// Whether [value] is an acceptable Sensitivity.
  static bool isValidSensitivity(double value) =>
      value.isFinite && value >= minSensitivity && value <= maxSensitivity;

  final SharedPreferences _prefs;
  late AppSettings _settings;
  final StreamController<double> _sensitivityController =
      StreamController<double>.broadcast();

  AppSettings get settings => _settings;
  double get sensitivity => _settings.sensitivity;
  bool get naturalScrolling => _settings.naturalScrolling;
  bool get tapToClick => _settings.tapToClick;

  /// Emits the new Sensitivity every time it is successfully set.
  Stream<double> get sensitivityChanges => _sensitivityController.stream;

  /// Sets Sensitivity. Returns true if accepted; false if rejected, in which
  /// case the previous value is retained.
  Future<bool> setSensitivity(double value) async {
    if (!isValidSensitivity(value)) return false;
    await _prefs.setDouble(sensitivityKey, value);
    _settings = AppSettings(
      sensitivity: value,
      naturalScrolling: _settings.naturalScrolling,
      tapToClick: _settings.tapToClick,
    );
    _sensitivityController.add(value);
    return true;
  }

  Future<void> setNaturalScrolling(bool value) async {
    await _prefs.setBool(naturalScrollingKey, value);
    _settings = AppSettings(
      sensitivity: _settings.sensitivity,
      naturalScrolling: value,
      tapToClick: _settings.tapToClick,
    );
  }

  Future<void> setTapToClick(bool value) async {
    await _prefs.setBool(tapToClickKey, value);
    _settings = AppSettings(
      sensitivity: _settings.sensitivity,
      naturalScrolling: _settings.naturalScrolling,
      tapToClick: value,
    );
  }

  Future<void> dispose() => _sensitivityController.close();

  double _readSensitivity() {
    final stored = _prefs.getDouble(sensitivityKey);
    return stored != null && isValidSensitivity(stored)
        ? stored
        : defaultSensitivity;
  }
}
