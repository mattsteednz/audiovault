import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:kowhai/locator.dart';
import 'package:kowhai/services/audio_handler.dart';
import 'package:kowhai/services/position_service.dart';
import 'package:kowhai/services/preferences_service.dart';
import 'audio_handler_test.mocks.dart';

@GenerateMocks([PositionService, PreferencesService, AudioPlayer])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    setupLocator();
    locator.allowReassignment = true;
  });

  group('AudioHandler', () {
    late MockPositionService mockPositionService;
    late MockPreferencesService mockPreferencesService;

    setUp(() {
      mockPositionService = MockPositionService();
      mockPreferencesService = MockPreferencesService();
      
      when(mockPreferencesService.getAutoRewind()).thenAnswer((_) async => true);
      when(mockPreferencesService.getSkipInterval()).thenAnswer((_) async => 30);

      locator.registerLazySingleton<PositionService>(() => mockPositionService);
      locator.registerLazySingleton<PreferencesService>(() => mockPreferencesService);
    });

    group('getRewindOffset (Smart Rewind)', () {
      test('returns zero for pauses under 5 minutes', () {
        expect(KowhaiHandler.getRewindOffset(Duration.zero), Duration.zero);
        expect(KowhaiHandler.getRewindOffset(const Duration(minutes: 4, seconds: 59)), Duration.zero);
      });

      test('returns 10s at exactly 5 minutes', () {
        expect(KowhaiHandler.getRewindOffset(const Duration(minutes: 5)), const Duration(seconds: 10));
      });

      test('returns 10s for pauses between 5 minutes and 1 hour', () {
        expect(KowhaiHandler.getRewindOffset(const Duration(minutes: 30)), const Duration(seconds: 10));
        expect(KowhaiHandler.getRewindOffset(const Duration(minutes: 59, seconds: 59)), const Duration(seconds: 10));
      });

      test('returns 15s at exactly 1 hour', () {
        expect(KowhaiHandler.getRewindOffset(const Duration(hours: 1)), const Duration(seconds: 15));
      });

      test('returns 15s for pauses between 1 hour and 24 hours', () {
        expect(KowhaiHandler.getRewindOffset(const Duration(hours: 6)), const Duration(seconds: 15));
        expect(KowhaiHandler.getRewindOffset(const Duration(hours: 23, minutes: 59, seconds: 59)), const Duration(seconds: 15));
      });

      test('returns 30s at exactly 24 hours', () {
        expect(KowhaiHandler.getRewindOffset(const Duration(hours: 24)), const Duration(seconds: 30));
      });

      test('returns 30s for pauses over 24 hours', () {
        expect(KowhaiHandler.getRewindOffset(const Duration(days: 3)), const Duration(seconds: 30));
      });
    });

    // calculateGlobalPosition is tested in position_persister_test.dart
    // (the canonical implementation). The static method on KowhaiHandler
    // is a @visibleForTesting redirect — no need to duplicate coverage here.

    group('humanizePlayerError', () {
      test('source-not-found maps to missing-file copy', () {
        expect(
          KowhaiHandler.humanizePlayerError(
              Exception('Source could not be opened')),
          contains("couldn't be opened"),
        );
      });

      test('permission errors map to permission copy', () {
        expect(
          KowhaiHandler.humanizePlayerError(
              Exception('Permission denied')),
          contains('Permission'),
        );
      });

      test('codec/format errors map to unsupported-format copy', () {
        expect(
          KowhaiHandler.humanizePlayerError(
              Exception('Unsupported codec')),
          contains('unsupported audio format'),
        );
      });

      test('network errors map to network copy', () {
        expect(
          KowhaiHandler.humanizePlayerError(
              Exception('Socket connection refused')),
          contains('Network'),
        );
      });

      test('unknown errors fall back to generic retry copy', () {
        expect(
          KowhaiHandler.humanizePlayerError(
              Exception('something weird happened')),
          contains('Tap retry'),
        );
      });
    });
  });
}
