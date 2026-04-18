import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault/screens/player_screen.dart';
import 'package:audiovault/services/sleep_timer_controller.dart';

void main() {
  group('fmtSpeed', () {
    test('whole and tenth values use one decimal', () {
      expect(fmtSpeed(1.0), '1.0×');
      expect(fmtSpeed(0.5), '0.5×');
      expect(fmtSpeed(2.0), '2.0×');
    });

    test('non-tenth values use two decimals', () {
      expect(fmtSpeed(1.25), '1.25×');
      expect(fmtSpeed(0.75), '0.75×');
      expect(fmtSpeed(1.33), '1.33×');
    });

    test('rounds to two decimals', () {
      // 1.234 → "1.23"
      expect(fmtSpeed(1.234), '1.23×');
    });
  });

  group('fmtHM', () {
    test('under an hour shows MM:SS', () {
      expect(fmtHM(const Duration(seconds: 0)), '00:00');
      expect(fmtHM(const Duration(seconds: 9)), '00:09');
      expect(fmtHM(const Duration(minutes: 5, seconds: 3)), '05:03');
      expect(fmtHM(const Duration(minutes: 59, seconds: 59)), '59:59');
    });

    test('one hour or more shows H:MM:SS', () {
      expect(fmtHM(const Duration(hours: 1)), '1:00:00');
      expect(fmtHM(const Duration(hours: 2, minutes: 3, seconds: 4)),
          '2:03:04');
      expect(fmtHM(const Duration(hours: 10, minutes: 0, seconds: 7)),
          '10:00:07');
    });

    test('negative durations clamp to zero', () {
      expect(fmtHM(const Duration(seconds: -5)), '00:00');
      expect(fmtHM(const Duration(hours: -1)), '00:00');
    });

    test('pads single-digit minutes and seconds', () {
      expect(fmtHM(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
    });
  });

  group('sleepTimerTick', () {
    test('decrements by one second when > 1s remains', () {
      final r = sleepTimerTick(const Duration(seconds: 10));
      expect(r.next, const Duration(seconds: 9));
      expect(r.shouldFire, isFalse);
    });

    test('fires when 1 second remains', () {
      final r = sleepTimerTick(const Duration(seconds: 1));
      expect(r.shouldFire, isTrue);
      expect(r.next, Duration.zero);
    });

    test('fires when already zero', () {
      final r = sleepTimerTick(Duration.zero);
      expect(r.shouldFire, isTrue);
      expect(r.next, Duration.zero);
    });

    test('fires when negative (defensive)', () {
      final r = sleepTimerTick(const Duration(seconds: -5));
      expect(r.shouldFire, isTrue);
    });

    test('minute-scale durations decrement cleanly', () {
      final r = sleepTimerTick(const Duration(minutes: 5));
      expect(r.next, const Duration(minutes: 4, seconds: 59));
      expect(r.shouldFire, isFalse);
    });
  });
}
