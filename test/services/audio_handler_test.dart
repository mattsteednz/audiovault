import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:audiovault/locator.dart';
import 'package:audiovault/services/audio_handler.dart';
import 'package:audiovault/services/position_service.dart';
import 'package:audiovault/services/preferences_service.dart';
import 'audio_handler_test.mocks.dart';

@GenerateMocks([PositionService, PreferencesService])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    setupLocator();
    locator.allowReassignment = true;
  });

  group('AudioVaultHandler', () {
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

    test('can instantiate correctly', () {
      final handler = AudioVaultHandler();
      expect(handler, isNotNull);
    });

    group('getRewindOffset (Smart Rewind)', () {
      test('returns zero for pauses under 5 minutes', () {
        expect(AudioVaultHandler.getRewindOffset(Duration.zero), Duration.zero);
        expect(AudioVaultHandler.getRewindOffset(const Duration(minutes: 4, seconds: 59)), Duration.zero);
      });

      test('returns 10s at exactly 5 minutes', () {
        expect(AudioVaultHandler.getRewindOffset(const Duration(minutes: 5)), const Duration(seconds: 10));
      });

      test('returns 10s for pauses between 5 minutes and 1 hour', () {
        expect(AudioVaultHandler.getRewindOffset(const Duration(minutes: 30)), const Duration(seconds: 10));
        expect(AudioVaultHandler.getRewindOffset(const Duration(minutes: 59, seconds: 59)), const Duration(seconds: 10));
      });

      test('returns 15s at exactly 1 hour', () {
        expect(AudioVaultHandler.getRewindOffset(const Duration(hours: 1)), const Duration(seconds: 15));
      });

      test('returns 15s for pauses between 1 hour and 24 hours', () {
        expect(AudioVaultHandler.getRewindOffset(const Duration(hours: 6)), const Duration(seconds: 15));
        expect(AudioVaultHandler.getRewindOffset(const Duration(hours: 23, minutes: 59, seconds: 59)), const Duration(seconds: 15));
      });

      test('returns 30s at exactly 24 hours', () {
        expect(AudioVaultHandler.getRewindOffset(const Duration(hours: 24)), const Duration(seconds: 30));
      });

      test('returns 30s for pauses over 24 hours', () {
        expect(AudioVaultHandler.getRewindOffset(const Duration(days: 3)), const Duration(seconds: 30));
      });
    });

    group('calculateGlobalPosition (Timeline Math)', () {
      final durations = [
        const Duration(minutes: 5), // 300,000 ms
        const Duration(minutes: 10), // 600,000 ms
        const Duration(minutes: 5), // 300,000 ms
      ];

      test('returns exact chapter position for chapter zero', () {
        final pos = AudioVaultHandler.calculateGlobalPosition(
          chapterIndex: 0,
          chapterPosition: const Duration(minutes: 2),
          chapterDurations: durations,
        );
        // 2 mins = 120,000 ms
        expect(pos, 120000);
      });

      test('factors in previous chapters correctly', () {
        final pos = AudioVaultHandler.calculateGlobalPosition(
          chapterIndex: 1, // Currently in second chapter
          chapterPosition: const Duration(minutes: 3),
          chapterDurations: durations,
        );
        // 5 min (prev) + 3 min (curr) = 8 mins = 480,000 ms
        expect(pos, 480000);
      });

      test('handles index out of bounds gracefully', () {
        final pos = AudioVaultHandler.calculateGlobalPosition(
          chapterIndex: 5, // Doesn't exist
          chapterPosition: const Duration(minutes: 1),
          chapterDurations: durations,
        );
        // ALL prev chapters (20 mins) + 1 min = 21 mins = 1,260,000 ms
        expect(pos, 1260000);
      });
    });
  });
}
