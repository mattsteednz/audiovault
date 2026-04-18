import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault/models/audiobook.dart';
import 'package:audiovault/services/position_service.dart';

void main() {
  group('PositionService status derivation', () {
    test('zero global position → notStarted', () {
      expect(
        PositionService.deriveStatusForTesting(0, 3600000),
        BookStatus.notStarted,
      );
    });

    test('negative global position → notStarted', () {
      expect(
        PositionService.deriveStatusForTesting(-100, 3600000),
        BookStatus.notStarted,
      );
    });

    test('in-progress mid-book → inProgress', () {
      expect(
        PositionService.deriveStatusForTesting(1800000, 3600000),
        BookStatus.inProgress,
      );
    });

    test('just inside 60s finished threshold → finished', () {
      // 3_600_000 - 59_999 = 3_540_001; within 60s of end
      expect(
        PositionService.deriveStatusForTesting(3540001, 3600000),
        BookStatus.finished,
      );
    });

    test('just outside 60s finished threshold → inProgress', () {
      // 3_600_000 - 60_001 = 3_539_999; outside the 60s window
      expect(
        PositionService.deriveStatusForTesting(3539999, 3600000),
        BookStatus.inProgress,
      );
    });

    test('global >= total → finished', () {
      expect(
        PositionService.deriveStatusForTesting(3600000, 3600000),
        BookStatus.finished,
      );
      expect(
        PositionService.deriveStatusForTesting(3700000, 3600000),
        BookStatus.finished,
      );
    });

    test('totalMs == 0 with progress → inProgress (unknown duration)', () {
      expect(
        PositionService.deriveStatusForTesting(1000, 0),
        BookStatus.inProgress,
      );
    });
  });
}
