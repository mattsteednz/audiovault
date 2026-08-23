import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kowhai/models/audiobook.dart';
import 'package:kowhai/services/position_persister.dart';
import 'package:kowhai/services/position_service.dart';
import 'package:kowhai/utils/formatters.dart';

/// In-memory PositionService backed by the production schema (v3).
Future<PositionService> _makeService() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 3,
      singleInstance: false,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE positions (
            book_path TEXT PRIMARY KEY,
            chapter_index INTEGER NOT NULL DEFAULT 0,
            position_ms INTEGER NOT NULL DEFAULT 0,
            global_position_ms INTEGER NOT NULL DEFAULT 0,
            total_duration_ms INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL,
            status TEXT
          )
        ''');
      },
    ),
  );
  return PositionService.withDatabase(db);
}

Audiobook _book({
  String path = '/books/test',
  List<Duration> chapterDurations = const [],
  Duration? duration,
}) =>
    Audiobook(
      title: 'Test',
      path: path,
      audioFiles: const [],
      chapterDurations: chapterDurations,
      duration: duration,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('globalToChapterPosition', () {
    test('returns zero chapter/offset for zero or negative input', () {
      expect(globalToChapterPosition(0, [const Duration(minutes: 10)]),
          (chapterIndex: 0, position: Duration.zero));
      expect(globalToChapterPosition(-5, [const Duration(minutes: 10)]),
          (chapterIndex: 0, position: Duration.zero));
    });

    test('handles an empty duration list by parking everything on chapter 0',
        () {
      final r = globalToChapterPosition(90000, const []);
      expect(r.chapterIndex, 0);
      expect(r.position.inMilliseconds, 90000);
    });

    test('maps mid-chapter offsets', () {
      final r = globalToChapterPosition(
        15 * 60 * 1000 + 30 * 1000,
        [
          const Duration(minutes: 10),
          const Duration(minutes: 20),
          const Duration(minutes: 30),
        ],
      );
      // 10 min consumed by ch0 → 5m30s into ch1.
      expect(r.chapterIndex, 1);
      expect(r.position, const Duration(minutes: 5, seconds: 30));
    });

    test('exact chapter boundary rolls to the next chapter start', () {
      final r = globalToChapterPosition(
        10 * 60 * 1000, // exactly the end of chapter 0
        [
          const Duration(minutes: 10),
          const Duration(minutes: 20),
        ],
      );
      expect(r.chapterIndex, 1);
      expect(r.position, Duration.zero);
    });

    test('overshoot clamps to the end of the last chapter', () {
      final r = globalToChapterPosition(
        999 * 60 * 1000,
        [
          const Duration(minutes: 10),
          const Duration(minutes: 20),
        ],
      );
      expect(r.chapterIndex, 1);
      expect(r.position, const Duration(minutes: 20),
          reason: 'must never exceed the chapter duration');
    });

    test('round-trips with calculateGlobalPosition for sampled inputs', () {
      const durations = [
        Duration(minutes: 7, seconds: 13),
        Duration(minutes: 21),
        Duration(minutes: 2, seconds: 45),
        Duration(hours: 1),
      ];
      for (var i = 0; i < durations.length; i++) {
        for (final offsetMs in [0, 1, 5000, durations[i].inMilliseconds - 1]) {
          if (offsetMs < 0) continue;
          final global = calculateGlobalPosition(
            chapterIndex: i,
            chapterPosition: Duration(milliseconds: offsetMs),
            chapterDurations: durations,
          );
          final back = globalToChapterPosition(global, durations);
          expect(back.chapterIndex, i,
              reason: 'global=$global sample=($i, $offsetMs)');
          expect(back.position.inMilliseconds, offsetMs,
              reason: 'global=$global sample=($i, $offsetMs)');
        }
      }
    });
  });

  group('calculateGlobalPosition', () {
    test('returns raw chapter offset for chapter 0', () {
      final ms = calculateGlobalPosition(
        chapterIndex: 0,
        chapterPosition: const Duration(minutes: 5),
        chapterDurations: [
          const Duration(minutes: 10),
          const Duration(minutes: 10),
        ],
      );
      expect(ms, const Duration(minutes: 5).inMilliseconds);
    });

    test('sums previous chapter durations', () {
      final ms = calculateGlobalPosition(
        chapterIndex: 2,
        chapterPosition: const Duration(seconds: 30),
        chapterDurations: [
          const Duration(minutes: 10),
          const Duration(minutes: 20),
          const Duration(minutes: 30),
        ],
      );
      expect(
        ms,
        const Duration(minutes: 30, seconds: 30).inMilliseconds,
      );
    });

    test('empty chapterDurations falls back to raw position', () {
      final ms = calculateGlobalPosition(
        chapterIndex: 3,
        chapterPosition: const Duration(seconds: 42),
        chapterDurations: const [],
      );
      expect(ms, const Duration(seconds: 42).inMilliseconds);
    });

    test('chapterIndex beyond list length uses what it can', () {
      final ms = calculateGlobalPosition(
        chapterIndex: 5,
        chapterPosition: const Duration(seconds: 10),
        chapterDurations: [
          const Duration(minutes: 1),
          const Duration(minutes: 2),
        ],
      );
      // 60000 + 120000 + 10000
      expect(ms, 190000);
    });
  });

  group('PositionPersister', () {
    test('save() is a no-op when no book is loaded', () async {
      final svc = await _makeService();
      final persister = PositionPersister(
        positionService: svc,
        getBook: () => null,
        readPosition: () => (chapterIndex: 0, position: Duration.zero),
      );
      await persister.save();
      // Nothing inserted.
      expect(await svc.getPosition('/books/test'), isNull);
    });

    test('save() is suppressed when readPosition returns null', () async {
      final svc = await _makeService();
      final persister = PositionPersister(
        positionService: svc,
        getBook: () => _book(path: '/books/dune'),
        readPosition: () => null, // mid-load suppression
      );
      await persister.save();
      expect(await svc.getPosition('/books/dune'), isNull);
    });

    test('saveSnapshot persists the same math as save()', () async {
      final svc = await _makeService();
      const path = '/books/snapshot';
      final book = _book(
        path: path,
        chapterDurations: [
          const Duration(minutes: 10),
          const Duration(minutes: 10),
        ],
        duration: const Duration(minutes: 20),
      );
      final persister = PositionPersister(
        positionService: svc,
        getBook: () => book,
        readPosition: () => (
          chapterIndex: 1,
          position: const Duration(minutes: 3),
        ),
      );

      await persister.saveSnapshot(
        book: book,
        snap: (
          chapterIndex: 1,
          position: const Duration(minutes: 3),
        ),
      );

      final saved = await svc.getPosition(path);
      expect(saved!.chapterIndex, 1);
      expect(saved.position, const Duration(minutes: 3));
      final row = (await svc.getAllPositions()).single;
      expect(row.globalPositionMs, const Duration(minutes: 13).inMilliseconds);
    });

    test('save() writes the current snapshot to the DB', () async {
      final svc = await _makeService();
      final persister = PositionPersister(
        positionService: svc,
        getBook: () => _book(
          path: '/books/dune',
          chapterDurations: [
            const Duration(minutes: 10),
            const Duration(minutes: 10),
          ],
          duration: const Duration(minutes: 20),
        ),
        readPosition: () => (
          chapterIndex: 1,
          position: const Duration(minutes: 3),
        ),
      );

      await persister.save();

      final saved = await svc.getPosition('/books/dune');
      expect(saved, isNotNull);
      expect(saved!.chapterIndex, 1);
      expect(saved.position, const Duration(minutes: 3));
    });

    test('save() computes globalPositionMs using chapterDurations', () async {
      final svc = await _makeService();
      const path = '/books/range';
      final persister = PositionPersister(
        positionService: svc,
        getBook: () => _book(
          path: path,
          chapterDurations: [
            const Duration(minutes: 10),
            const Duration(minutes: 20),
          ],
        ),
        readPosition: () => (
          chapterIndex: 1,
          position: const Duration(minutes: 5),
        ),
      );
      await persister.save();

      // Read the raw column through getAllPositions.
      final rows = await svc.getAllPositions();
      final row =
          rows.firstWhere((r) => r.bookPath == path);
      expect(
        row.globalPositionMs,
        const Duration(minutes: 15).inMilliseconds,
      );
    });

    test('startPeriodic is idempotent', () async {
      final svc = await _makeService();
      final persister = PositionPersister(
        positionService: svc,
        getBook: () => null,
        readPosition: () => (chapterIndex: 0, position: Duration.zero),
        interval: const Duration(milliseconds: 50),
      );
      persister.startPeriodic();
      persister.startPeriodic(); // no-op
      expect(persister.isRunning, isTrue);
      persister.stopPeriodic();
      expect(persister.isRunning, isFalse);
    });

    test('stopPeriodic cancels the timer cleanly', () async {
      final svc = await _makeService();
      var saveCount = 0;
      final persister = PositionPersister(
        positionService: svc,
        getBook: () {
          saveCount++;
          return null; // no-op save, but we count the attempt
        },
        readPosition: () => (chapterIndex: 0, position: Duration.zero),
        interval: const Duration(milliseconds: 20),
      );
      persister.startPeriodic();
      await Future.delayed(const Duration(milliseconds: 70));
      persister.stopPeriodic();
      final after = saveCount;
      await Future.delayed(const Duration(milliseconds: 60));
      expect(saveCount, after, reason: 'no saves after stopPeriodic');
      expect(after, greaterThanOrEqualTo(2));
    });

    test('dispose stops the timer', () async {
      final svc = await _makeService();
      final persister = PositionPersister(
        positionService: svc,
        getBook: () => null,
        readPosition: () => (chapterIndex: 0, position: Duration.zero),
      );
      persister.startPeriodic();
      persister.dispose();
      expect(persister.isRunning, isFalse);
    });
  });
}
