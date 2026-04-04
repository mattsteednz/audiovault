import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const _libraryPathKey = 'library_path';
  static const _analyticsConsentKey = 'analytics_consent';

  Future<String?> getLibraryPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_libraryPathKey);
  }

  Future<void> setLibraryPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_libraryPathKey, path);
  }

  Future<void> clearLibraryPath() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_libraryPathKey);
  }

  /// Returns null if the user has not yet been asked, true/false if they have.
  Future<bool?> getAnalyticsConsent() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_analyticsConsentKey)) return null;
    return prefs.getBool(_analyticsConsentKey);
  }

  Future<void> setAnalyticsConsent(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_analyticsConsentKey, value);
  }
}
