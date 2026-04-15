import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiovault/models/audiobook.dart';
import 'package:audiovault/services/position_service.dart';

/// Opens a fresh in-memory database with the positions schema.
/// singleInstance: false ensures each call gets an isolated database.
Future<PositionService> _makeService() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      singleInstance: false,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE positions (
          book_path TEXT PRIMARY KEY,
          chapter_index INTEGER NOT NULL DEFAULT 0,
          position_ms INTEGER NOT NULL DEFAULT 0,
          global_position_ms INTEGER NOT NULL DEFAULT 0,
          total_duration_ms INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL,
          status TEXT
        )
      '''),
    ),
  );
  return PositionService.withDatabase(db);
}

/// Inserts a row directly with an explicit [updatedAt] for ordering tests.
Future<void> _insert(
  PositionService svc, {
  required String bookPath,
  required int updatedAt,
  int globalPositionMs = 0,
  int totalDurationMs = 0,
}) async {
  final db = await svc.databaseForTesting;
  await db.insert('positions', {
    'book_path': bookPath,
    'chapter_index': 0,
    'position_ms': 0,
    'global_position_ms': globalPositionMs,
    'total_duration_ms': totalDurationMs,
    'updated_at': updatedAt,
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('PositionService', () {
    group('savePosition / getPosition', () {
      test('returns null for an unknown book', () async {
        final svc = await _makeService();
        expect(await svc.getPosition('/unknown/book'), isNull);
      });

      test('saves and retrieves chapter index and position', () async {
        final svc = await _makeService();
        await svc.savePosition(
          bookPath: '/books/dune',
          chapterIndex: 3,
          position: const Duration(minutes: 12, seconds: 30),
          globalPositionMs: 750000,
          totalDurationMs: 36000000,
        );

        final result = await svc.getPosition('/books/dune');
        expect(result, isNotNull);
        expect(result!.chapterIndex, 3);
        expect(result.position, const Duration(minutes: 12, seconds: 30));
      });

      test('overwrites an existing entry on re-save', () async {
        final svc = await _makeService();
        await svc.savePosition(
          bookPath: '/books/dune',
          chapterIndex: 1,
          position: const Duration(minutes: 5),
          globalPositionMs: 300000,
          totalDurationMs: 36000000,
        );
        await svc.savePosition(
          bookPath: '/books/dune',
          chapterIndex: 7,
          position: const Duration(hours: 2),
          globalPositionMs: 7200000,
          totalDurationMs: 36000000,
        );

        final result = await svc.getPosition('/books/dune');
        expect(result!.chapterIndex, 7);
        expect(result.position, const Duration(hours: 2));
      });

      test('stores multiple books independently', () async {
        final svc = await _makeService();
        await svc.savePosition(
          bookPath: '/books/dune',
          chapterIndex: 2,
          position: const Duration(minutes: 10),
          globalPositionMs: 600000,
          totalDurationMs: 36000000,
        );
        await svc.savePosition(
          bookPath: '/books/foundation',
          chapterIndex: 5,
          position: const Duration(minutes: 20),
          globalPositionMs: 1200000,
          totalDurationMs: 28800000,
        );

        final dune = await svc.getPosition('/books/dune');
        final foundation = await svc.getPosition('/books/foundation');
        expect(dune!.chapterIndex, 2);
        expect(foundation!.chapterIndex, 5);
      });
    });

    group('getLastPlayedBookPath', () {
      test('returns null when no books have been played', () async {
        final svc = await _makeService();
        expect(await svc.getLastPlayedBookPath(), isNull);
      });

      test('returns the book with the most recent updatedAt', () async {
        final svc = await _makeService();
        final now = DateTime.now().millisecondsSinceEpoch;
        await _insert(svc, bookPath: '/books/older', updatedAt: now - 60000);
        await _insert(svc, bookPath: '/books/newer', updatedAt: now);
        expect(await svc.getLastPlayedBookPath(), '/books/newer');
      });

      test('returns single book when only one exists', () async {
        final svc = await _makeService();
        await _insert(svc, bookPath: '/books/only', updatedAt: 1000);
        expect(await svc.getLastPlayedBookPath(), '/books/only');
      });
    });

    group('getAllPositions', () {
      test('returns empty list when no positions saved', () async {
        final svc = await _makeService();
        expect(await svc.getAllPositions(), isEmpty);
      });

      test('returns all positions ordered by updatedAt descending', () async {
        final svc = await _makeService();
        final now = DateTime.now().millisecondsSinceEpoch;
        await _insert(svc, bookPath: '/books/a', updatedAt: now - 2000);
        await _insert(svc, bookPath: '/books/b', updatedAt: now);
        await _insert(svc, bookPath: '/books/c', updatedAt: now - 1000);

        final results = await svc.getAllPositions();
        expect(results.length, 3);
        expect(results[0].bookPath, '/books/b'); // most recent
        expect(results[1].bookPath, '/books/c');
        expect(results[2].bookPath, '/books/a'); // oldest
      });

      test('exposes globalPositionMs and totalDurationMs', () async {
        final svc = await _makeService();
        await svc.savePosition(
          bookPath: '/books/dune',
          chapterIndex: 1,
          position: const Duration(minutes: 5),
          globalPositionMs: 450000,
          totalDurationMs: 36000000,
        );

        final results = await svc.getAllPositions();
        expect(results.first.globalPositionMs, 450000);
        expect(results.first.totalDurationMs, 36000000);
      });
    });

    group('getBookStatus', () {
      test('returns notStarted for unknown book', () async {
        final svc = await _makeService();
        expect(await svc.getBookStatus('/books/unknown'), BookStatus.notStarted);
      });

      test('returns notStarted when position is zero and no explicit status', () async {
        final svc = await _makeService();
        await _insert(svc, bookPath: '/books/dune', updatedAt: 1000,
            globalPositionMs: 0, totalDurationMs: 36000000);
        expect(await svc.getBookStatus('/books/dune'), BookStatus.notStarted);
      });

      test('derives inProgress from position when no explicit status', () async {
        final svc = await _makeService();
        await _insert(svc, bookPath: '/books/dune', updatedAt: 1000,
            globalPositionMs: 1800000, totalDurationMs: 36000000);
        expect(await svc.getBookStatus('/books/dune'), BookStatus.inProgress);
      });

      test('derives finished when position is within 60s of end', () async {
        final svc = await _makeService();
        await _insert(svc, bookPath: '/books/dune', updatedAt: 1000,
            globalPositionMs: 35960000, totalDurationMs: 36000000);
        expect(await svc.getBookStatus('/books/dune'), BookStatus.finished);
      });

      test('returns explicit status over derived value', () async {
        final svc = await _makeService();
        // Position would derive inProgress, but explicit status is finished.
        await svc.savePosition(
          bookPath: '/books/dune',
          chapterIndex: 1,
          position: const Duration(minutes: 5),
          globalPositionMs: 1800000,
          totalDurationMs: 36000000,
        );
        await svc.updateBookStatus('/books/dune', BookStatus.finished);
        expect(await svc.getBookStatus('/books/dune'), BookStatus.finished);
      });
    });

    group('updateBookStatus', () {
      test('creates a row when none exists', () async {
        final svc = await _makeService();
        await svc.updateBookStatus('/books/new', BookStatus.inProgress);
        expect(await svc.getBookStatus('/books/new'), BookStatus.inProgress);
      });

      test('updates status without overwriting position', () async {
        final svc = await _makeService();
        await svc.savePosition(
          bookPath: '/books/dune',
          chapterIndex: 3,
          position: const Duration(minutes: 12),
          globalPositionMs: 720000,
          totalDurationMs: 36000000,
        );
        await svc.updateBookStatus('/books/dune', BookStatus.finished);
        final pos = await svc.getPosition('/books/dune');
        expect(pos!.chapterIndex, 3);
        expect(pos.position, const Duration(minutes: 12));
        expect(await svc.getBookStatus('/books/dune'), BookStatus.finished);
      });

      test('can transition between statuses', () async {
        final svc = await _makeService();
        await svc.updateBookStatus('/books/dune', BookStatus.finished);
        await svc.updateBookStatus('/books/dune', BookStatus.inProgress);
        expect(await svc.getBookStatus('/books/dune'), BookStatus.inProgress);
      });
    });

    group('getAllStatuses', () {
      test('returns empty map when no positions exist', () async {
        final svc = await _makeService();
        expect(await svc.getAllStatuses(), isEmpty);
      });

      test('returns explicit statuses for all books', () async {
        final svc = await _makeService();
        await svc.updateBookStatus('/books/a', BookStatus.notStarted);
        await svc.updateBookStatus('/books/b', BookStatus.inProgress);
        await svc.updateBookStatus('/books/c', BookStatus.finished);
        final statuses = await svc.getAllStatuses();
        expect(statuses['/books/a'], BookStatus.notStarted);
        expect(statuses['/books/b'], BookStatus.inProgress);
        expect(statuses['/books/c'], BookStatus.finished);
      });

      test('derives status from position when no explicit status set', () async {
        final svc = await _makeService();
        await _insert(svc, bookPath: '/books/a', updatedAt: 1000,
            globalPositionMs: 0, totalDurationMs: 36000000);
        await _insert(svc, bookPath: '/books/b', updatedAt: 2000,
            globalPositionMs: 1800000, totalDurationMs: 36000000);
        await _insert(svc, bookPath: '/books/c', updatedAt: 3000,
            globalPositionMs: 35960000, totalDurationMs: 36000000);
        final statuses = await svc.getAllStatuses();
        expect(statuses['/books/a'], BookStatus.notStarted);
        expect(statuses['/books/b'], BookStatus.inProgress);
        expect(statuses['/books/c'], BookStatus.finished);
      });
    });
  });
}
