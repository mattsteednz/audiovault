import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static final PreferencesService _instance = PreferencesService._();
  PreferencesService._();
  factory PreferencesService() => _instance;

  static const _libraryPathKey = 'library_path';
  static const _analyticsConsentKey = 'analytics_consent';
  static const _themeModeKey = 'theme_mode';
  static const _metadataEnrichmentKey = 'metadata_enrichment';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _sp async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<String?> getLibraryPath() async {
    return (await _sp).getString(_libraryPathKey);
  }

  Future<void> setLibraryPath(String path) async {
    await (await _sp).setString(_libraryPathKey, path);
  }

  Future<void> clearLibraryPath() async {
    await (await _sp).remove(_libraryPathKey);
  }

  /// Returns null if the user has not yet been asked, true/false if they have.
  Future<bool?> getAnalyticsConsent() async {
    final prefs = await _sp;
    if (!prefs.containsKey(_analyticsConsentKey)) return null;
    return prefs.getBool(_analyticsConsentKey);
  }

  Future<void> setAnalyticsConsent(bool value) async {
    await (await _sp).setBool(_analyticsConsentKey, value);
  }

  /// Returns null if no preference has been stored (treat as 'system').
  Future<String?> getThemeMode() async {
    return (await _sp).getString(_themeModeKey);
  }

  Future<void> setThemeMode(String value) async {
    await (await _sp).setString(_themeModeKey, value);
  }

  Future<bool> getMetadataEnrichment() async {
    return (await _sp).getBool(_metadataEnrichmentKey) ?? true; // default on
  }

  Future<void> setMetadataEnrichment(bool value) async {
    await (await _sp).setBool(_metadataEnrichmentKey, value);
  }
}
