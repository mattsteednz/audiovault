import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault/services/drive_download_manager.dart';

DownloadQueueSnapshot _q(String id,
        {bool active = false, bool hasPending = true}) =>
    DownloadQueueSnapshot(folderId: id, active: active, hasPending: hasPending);

void main() {
  group('selectQueuesToStart', () {
    test('returns empty when concurrency is saturated', () {
      final result = selectQueuesToStart(
        queues: [_q('A'), _q('B')],
        activeCount: 2,
        maxConcurrent: 2,
      );
      expect(result, isEmpty);
    });

    test('returns empty when activeCount exceeds maxConcurrent', () {
      final result = selectQueuesToStart(
        queues: [_q('A')],
        activeCount: 3,
        maxConcurrent: 2,
      );
      expect(result, isEmpty);
    });

    test('skips active queues', () {
      final result = selectQueuesToStart(
        queues: [_q('A', active: true), _q('B')],
        activeCount: 1,
        maxConcurrent: 2,
      );
      expect(result, ['B']);
    });

    test('skips queues with no pending work', () {
      final result = selectQueuesToStart(
        queues: [_q('A', hasPending: false), _q('B')],
        activeCount: 0,
        maxConcurrent: 2,
      );
      expect(result, ['B']);
    });

    test('caps result to remaining slots', () {
      final result = selectQueuesToStart(
        queues: [_q('A'), _q('B'), _q('C')],
        activeCount: 1,
        maxConcurrent: 2,
      );
      expect(result, ['A']);
    });

    test('returns all eligible queues when capacity allows', () {
      final result = selectQueuesToStart(
        queues: [_q('A'), _q('B')],
        activeCount: 0,
        maxConcurrent: 2,
      );
      expect(result, ['A', 'B']);
    });

    test('preserves iteration order', () {
      final result = selectQueuesToStart(
        queues: [_q('Z'), _q('A'), _q('M')],
        activeCount: 0,
        maxConcurrent: 3,
      );
      expect(result, ['Z', 'A', 'M']);
    });

    test('empty queues returns empty', () {
      final result = selectQueuesToStart(
        queues: const [],
        activeCount: 0,
        maxConcurrent: 2,
      );
      expect(result, isEmpty);
    });

    test('a single active book with many pending still blocks that queue', () {
      // The invariant: a book never has two concurrent downloads. An active
      // queue must be skipped even if concurrency has headroom.
      final result = selectQueuesToStart(
        queues: [_q('A', active: true)],
        activeCount: 1,
        maxConcurrent: 5,
      );
      expect(result, isEmpty);
    });
  });
}
