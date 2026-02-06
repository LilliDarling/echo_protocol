import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark;
  UserPreferences _preferences = UserPreferences.defaultPreferences;
  String? _userId;

  final FirebaseFirestore _db;

  ThemeProvider({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  ThemeMode get themeMode => _themeMode;
  UserPreferences get preferences => _preferences;

  ThemeMode _stringToThemeMode(String theme) {
    switch (theme) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> loadPreferences(String userId) async {
    _userId = userId;

    try {
      final doc = await _db.collection('users').doc(userId).get();
      final data = doc.data();

      if (data != null && data['preferences'] != null) {
        _preferences = UserPreferences.fromJson(
          data['preferences'] as Map<String, dynamic>,
        );
        _themeMode = _stringToThemeMode(_preferences.theme);
        notifyListeners();
      }
    } catch (e) {
      // Use default preferences on error
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;
    _preferences = _preferences.copyWith(theme: _themeModeToString(mode));
    notifyListeners();

    await _savePreferences();
  }

  Future<void> setNotifications(bool enabled) async {
    if (_preferences.notifications == enabled) return;

    _preferences = _preferences.copyWith(notifications: enabled);
    notifyListeners();

    await _savePreferences();
  }

  Future<void> setAutoDeleteDays(int days) async {
    if (_preferences.autoDeleteDays == days) return;

    _preferences = _preferences.copyWith(autoDeleteDays: days);
    notifyListeners();

    await _savePreferences();
  }

  Future<void> setNotificationPreview(NotificationPreview preview) async {
    if (_preferences.notificationPreview == preview) return;

    _preferences = _preferences.copyWith(notificationPreview: preview);
    notifyListeners();

    await _savePreferences();
  }

  Future<void> setShowTypingIndicator(bool show) async {
    if (_preferences.showTypingIndicator == show) return;

    _preferences = _preferences.copyWith(showTypingIndicator: show);
    notifyListeners();

    await _savePreferences();
  }

  Future<void> _savePreferences() async {
    if (_userId == null) return;

    try {
      await _db.collection('users').doc(_userId).update({
        'preferences': _preferences.toJson(),
      });
    } catch (e) {
      // Handle error silently - preferences will sync on next load
    }
  }

  void reset() {
    _themeMode = ThemeMode.dark;
    _preferences = UserPreferences.defaultPreferences;
    _userId = null;
    notifyListeners();
  }
}
