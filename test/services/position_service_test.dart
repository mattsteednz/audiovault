import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kowhai/models/audiobook.dart';
import 'package:kowhai/services/position_service.dart';

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

    group('setBookStatus', () {
      test('inserts with zero position for a new book', () async {
        final svc = await _makeService();
        await svc.setBookStatus('/books/new', BookStatus.inProgress);
        expect(await svc.getBookStatus('/books/new'), BookStatus.inProgress);
        final pos = await svc.getPosition('/books/new');
        expect(pos?.chapterIndex, 0);
        expect(pos?.position, Duration.zero);
      });

      test('does not wipe position when row already exists', () async {
        final svc = await _makeService();
        await svc.savePosition(
          bookPath: '/books/dune',
          chapterIndex: 5,
          position: const Duration(minutes: 30),
          globalPositionMs: 1800000,
          totalDurationMs: 36000000,
        );
        await svc.setBookStatus('/books/dune', BookStatus.finished);
        final pos = await svc.getPosition('/books/dune');
        expect(pos!.chapterIndex, 5,
            reason: 'setBookStatus must not zero chapter_index');
        expect(pos.position, const Duration(minutes: 30),
            reason: 'setBookStatus must not zero position_ms');
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

    group('savePosition preserves explicit status', () {
      test('saving over a finished row keeps the finished status', () async {
        final svc = await _makeService();
        const path = '/books/finished-book';
        await svc.updateBookStatus(path, BookStatus.finished);

        // A periodic save lands mid-book — far from the finished threshold.
        await svc.savePosition(
          bookPath: path,
          chapterIndex: 2,
          position: const Duration(minutes: 5),
          globalPositionMs: 1800000,
          totalDurationMs: 36000000,
        );

        expect(await svc.getBookStatus(path), BookStatus.finished,
            reason:
                'a position save must never wipe an explicit user-set status');
      });

      test('saving over a NULL-status row leaves it NULL (derived)', () async {
        final svc = await _makeService();
        const path = '/books/derived';
        await _insert(svc, bookPath: path, updatedAt: 1000,
            globalPositionMs: 1800000, totalDurationMs: 36000000);

        await svc.savePosition(
          bookPath: path,
          chapterIndex: 1,
          position: const Duration(minutes: 3),
          globalPositionMs: 2000000,
          totalDurationMs: 36000000,
        );

        final db = await svc.databaseForTesting;
        final rows = await db.query('positions',
            columns: ['status'],
            where: 'book_path = ?',
            whereArgs: [path]);
        expect(rows.single['status'], isNull);
        // And derivation still works.
        expect(await svc.getBookStatus(path), BookStatus.inProgress);
      });

      test('position columns still update across repeated saves', () async {
        final svc = await _makeService();
        const path = '/books/dune';
        await svc.updateBookStatus(path, BookStatus.finished);

        for (var i = 1; i <= 5; i++) {
          await svc.savePosition(
            bookPath: path,
            chapterIndex: i,
            position: Duration(minutes: i),
            globalPositionMs: i * 60000,
            totalDurationMs: 36000000,
          );
        }

        final saved = await svc.getPosition(path);
        expect(saved!.chapterIndex, 5);
        expect(saved.position, const Duration(minutes: 5));
        expect(await svc.getBookStatus(path), BookStatus.finished,
            reason: 'the interleaved-save loop must not clobber status');
      });

      test('first save onto an unknown book creates a NULL-status row', () async {
        final svc = await _makeService();
        await svc.savePosition(
          bookPath: '/books/new',
          chapterIndex: 0,
          position: Duration.zero,
          globalPositionMs: 0,
          totalDurationMs: 1000,
        );
        // Zero progress derives notStarted.
        expect(await svc.getBookStatus('/books/new'), BookStatus.notStarted);
      });
    });

    group('repairFromGlobal', () {
      test('rewrites legacy global-only rows to chapter + offset', () async {
        final svc = await _makeService();
        const path = '/books/legacy';
        final db = await svc.databaseForTesting;
        await db.insert('positions', {
          'book_path': path,
          'chapter_index': 0,
          'position_ms': 0,
          'global_position_ms': 25 * 60 * 1000, // 10m ch0 → 15m into ch1
          'total_duration_ms': 30 * 60 * 1000,
          'updated_at': 1000,
        });

        final repaired = await svc.repairFromGlobal(_repairBook(path));
        expect(repaired, isTrue);

        final saved = await svc.getPosition(path);
        expect(saved!.chapterIndex, 1);
        expect(saved.position, const Duration(minutes: 15));

        // global_position_ms must be untouched (status derivation reads it).
        final row = await db.query('positions',
            columns: ['global_position_ms'],
            where: 'book_path = ?',
            whereArgs: [path]);
        expect(row.single['global_position_ms'], 25 * 60 * 1000);
      });

      test('is idempotent and ignores healthy rows', () async {
        final svc = await _makeService();
        const path = '/books/healthy';
        await svc.savePosition(
          bookPath: path,
          chapterIndex: 2,
          position: const Duration(minutes: 4),
          globalPositionMs: 24 * 60 * 1000,
          totalDurationMs: 30 * 60 * 1000,
        );

        expect(await svc.repairFromGlobal(_repairBook(path)), isFalse);
      });

      test('keeps derived finished status for near-end globals', () async {
        final svc = await _makeService();
        const path = '/books/near-end';
        final db = await svc.databaseForTesting;
        await db.insert('positions', {
          'book_path': path,
          'chapter_index': 0,
          'position_ms': 0,
          // 45s before end of a 60m book → within the 60s finished threshold.
          'global_position_ms': 59 * 60 * 1000 + 15 * 1000,
          'total_duration_ms': 60 * 60 * 1000,
          'updated_at': 1000,
        });

        expect(
            await svc.getBookStatus(path), BookStatus.finished,
            reason: 'derivation applies before repair');
        expect(await svc.repairFromGlobal(_repairBook(path)), isTrue);
        expect(
            await svc.getBookStatus(path), BookStatus.finished,
            reason: 'repair must not disturb derived status');
      });

      test('skips books without chapter durations', () async {
        final svc = await _makeService();
        const path = '/books/no-durations';
        final db = await svc.databaseForTesting;
        await db.insert('positions', {
          'book_path': path,
          'chapter_index': 0,
          'position_ms': 0,
          'global_position_ms': 5000,
          'total_duration_ms': 60000,
          'updated_at': 1000,
        });

        final book = Audiobook(
          title: 'No durations',
          path: path,
          audioFiles: const [],
          chapterDurations: const [],
        );
        expect(await svc.repairFromGlobal(book), isFalse);
      });
    });
  });
}

/// Book fixture with two 10-minute chapters for repair tests.
Audiobook _repairBook(String path) => Audiobook(
      title: 'Repair fixture',
      path: path,
      audioFiles: const [],
      chapterDurations: const [
        Duration(minutes: 10),
        Duration(minutes: 20),
      ],
    );
