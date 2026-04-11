import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiovault/services/preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesService prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PreferencesService();
  });

  group('PreferencesService — defaults', () {
    test('getLibraryPath returns null when unset', () async {
      expect(await prefs.getLibraryPath(), isNull);
    });

    test('getAnalyticsConsent returns null when unset', () async {
      expect(await prefs.getAnalyticsConsent(), isNull);
    });

    test('getThemeMode returns null when unset', () async {
      expect(await prefs.getThemeMode(), isNull);
    });

    test('getMetadataEnrichment defaults to true', () async {
      expect(await prefs.getMetadataEnrichment(), isTrue);
    });

    test('getAutoRewind defaults to true', () async {
      expect(await prefs.getAutoRewind(), isTrue);
    });

    test('getSkipInterval defaults to 30', () async {
      expect(await prefs.getSkipInterval(), 30);
    });
  });

  group('PreferencesService — round-trips', () {
    test('setLibraryPath / getLibraryPath', () async {
      await prefs.setLibraryPath('/storage/audiobooks');
      expect(await prefs.getLibraryPath(), '/storage/audiobooks');
    });

    test('clearLibraryPath removes the value', () async {
      await prefs.setLibraryPath('/storage/audiobooks');
      await prefs.clearLibraryPath();
      expect(await prefs.getLibraryPath(), isNull);
    });

    test('setAnalyticsConsent true / getAnalyticsConsent', () async {
      await prefs.setAnalyticsConsent(true);
      expect(await prefs.getAnalyticsConsent(), isTrue);
    });

    test('setAnalyticsConsent false / getAnalyticsConsent', () async {
      await prefs.setAnalyticsConsent(false);
      expect(await prefs.getAnalyticsConsent(), isFalse);
    });

    test('setThemeMode / getThemeMode', () async {
      for (final mode in ['light', 'dark', 'system']) {
        await prefs.setThemeMode(mode);
        expect(await prefs.getThemeMode(), mode);
      }
    });

    test('setMetadataEnrichment false / getMetadataEnrichment', () async {
      await prefs.setMetadataEnrichment(false);
      expect(await prefs.getMetadataEnrichment(), isFalse);
    });

    test('setAutoRewind false / getAutoRewind', () async {
      await prefs.setAutoRewind(false);
      expect(await prefs.getAutoRewind(), isFalse);
    });

    test('setSkipInterval / getSkipInterval', () async {
      for (final secs in [10, 15, 45, 60]) {
        await prefs.setSkipInterval(secs);
        expect(await prefs.getSkipInterval(), secs);
      }
    });
  });
}
