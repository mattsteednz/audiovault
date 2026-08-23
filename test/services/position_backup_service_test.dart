import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kowhai/services/position_backup_service.dart';
import 'package:kowhai/models/audiobook.dart';
import 'package:kowhai/services/position_service.dart';
import 'package:kowhai/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Future<PositionService> _makePositionService() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 4,
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
        await db.execute('''
          CREATE TABLE bookmarks (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            book_path    TEXT NOT NULL,
            chapter_index INTEGER NOT NULL,
            position_ms  INTEGER NOT NULL,
            label        TEXT NOT NULL,
            notes        TEXT,
            created_at   INTEGER NOT NULL
          )
        ''');
      },
    ),
  );
  return PositionService.withDatabase(db);
}

void _setupLocator(PositionService svc) {
  final locator = GetIt.instance;
  if (locator.isRegistered<PositionService>()) locator.unregister<PositionService>();
  if (locator.isRegistered<PreferencesService>()) locator.unregister<PreferencesService>();
  locator.registerSingleton<PositionService>(svc);
  locator.registerSingleton<PreferencesService>(PreferencesService());
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });

  group('PositionBackupService path helpers', () {
    test('toRelative strips root prefix', () {
      expect(
        PositionBackupService.toRelativeForTesting(
            '/storage/books/Author/Book', '/storage/books'),
        'Author/Book',
      );
    });

    test('toRelative returns path unchanged when not under root', () {
      expect(
        PositionBackupService.toRelativeForTesting(
            '/other/path/Book', '/storage/books'),
        '/other/path/Book',
      );
    });

    test('toAbsolute joins root and relative path', () {
      expect(
        PositionBackupService.toAbsoluteForTesting(
            'Author/Book', '/storage/books'),
        '/storage/books/Author/Book',
      );
    });

    test('toAbsolute returns absolute path unchanged', () {
      expect(
        PositionBackupService.toAbsoluteForTesting(
            '/storage/books/Author/Book', '/storage/books'),
        '/storage/books/Author/Book',
      );
    });
  });

  group('PositionBackupService export/import', () {
    late Directory tempDir;
    late PositionService svc;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('backup_test_');
      svc = await _makePositionService();
      _setupLocator(svc);
    });

    tearDown(() async {
      try { await tempDir.delete(recursive: true); } catch (_) {}
    });

    test('exportToJson writes valid JSON with relative paths', () async {
      final root = tempDir.path.replaceAll('\\', '/');
      await svc.savePosition(
        bookPath: '$root/Author/Book',
        chapterIndex: 2,
        position: const Duration(seconds: 30),
        globalPositionMs: 30000,
        totalDurationMs: 3600000,
      );

      final backup = PositionBackupService();
      await backup.exportToJson(root);

      final file = File('${tempDir.path}/positions.json');
      expect(await file.exists(), isTrue);

      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(data['version'], 2);
      final positions = data['positions'] as List;
      expect(positions.length, 1);
      expect(positions.first['book_path'], 'Author/Book');
      expect(positions.first['global_position_ms'], 30000);
    });

    test('exportToJson writes chapter-level position (schema v2)', () async {
      final root = tempDir.path.replaceAll('\\', '/');
      await svc.savePosition(
        bookPath: '$root/Author/Book',
        chapterIndex: 4,
        position: const Duration(minutes: 3),
        globalPositionMs: 183000,
        totalDurationMs: 7200000,
      );

      final backup = PositionBackupService();
      await backup.exportToJson(root);

      final data =
          jsonDecode(await File('${tempDir.path}/positions.json').readAsString())
              as Map<String, dynamic>;
      final entry = (data['positions'] as List).single;
      expect(entry['chapter_index'], 4);
      expect(entry['position_ms'], const Duration(minutes: 3).inMilliseconds);
    });

    test('importing a v2 entry restores full chapter fidelity', () async {
      final root = tempDir.path.replaceAll('\\', '/');
      final absPath = '$root/Author/Book';

      final json = jsonEncode({
        'version': 2,
        'exported_at': 0,
        'positions': [
          {
            'book_path': 'Author/Book',
            'chapter_index': 7,
            'position_ms': 153000,
            'global_position_ms': 60000,
            'total_duration_ms': 3600000,
            'status': 'inProgress',
            'updated_at': 9999999,
          }
        ],
      });
      await File('${tempDir.path}/positions.json').writeAsString(json);

      final backup = PositionBackupService();
      await backup.importFromJson(root);

      final saved = await svc.getPosition(absPath);
      expect(saved!.chapterIndex, 7);
      expect(saved.position, const Duration(seconds: 153));
    });

    test('importing a legacy v1 entry leaves a healable zero-position row',
        () async {
      final root = tempDir.path.replaceAll('\\', '/');
      final absPath = '$root/Author/Book';

      final json = jsonEncode({
        'version': 1,
        'exported_at': 0,
        'positions': [
          {
            'book_path': 'Author/Book',
            'global_position_ms': 60000,
            'total_duration_ms': 3600000,
            'status': 'inProgress',
            'updated_at': 9999999,
          }
        ],
      });
      await File('${tempDir.path}/positions.json').writeAsString(json);

      final backup = PositionBackupService();
      await backup.importFromJson(root);

      // Legacy shape: global set, chapter-level zero — exactly the signature
      // PositionService.repairFromGlobal fixes once durations are known.
      final saved = await svc.getPosition(absPath);
      expect(saved!.chapterIndex, 0);
      expect(saved.position, Duration.zero);

      final repaired = await svc.repairFromGlobal(Audiobook(
        title: 'Book',
        path: absPath,
        audioFiles: const [],
        chapterDurations: const [Duration(minutes: 10), Duration(hours: 1)],
      ));
      expect(repaired, isTrue);
      final healed = await svc.getPosition(absPath);
      // 60s global sits 60s into the 10-minute first chapter.
      expect(healed!.chapterIndex, 0);
      expect(healed.position, const Duration(seconds: 60));
      expect(await svc.getBookStatus(absPath), BookStatus.inProgress);
    });

    test('import does not write an explicit notStarted status', () async {
      final root = tempDir.path.replaceAll('\\', '/');
      final absPath = '$root/Author/Book';

      final json = jsonEncode({
        'version': 2,
        'exported_at': 0,
        'positions': [
          {
            'book_path': 'Author/Book',
            'global_position_ms': 1800000,
            'total_duration_ms': 3600000,
            'updated_at': 9999999,
          }
        ],
      });
      await File('${tempDir.path}/positions.json').writeAsString(json);

      final backup = PositionBackupService();
      await backup.importFromJson(root);

      final db = await svc.databaseForTesting;
      final rows = await db.query('positions',
          columns: ['status'], where: 'book_path = ?', whereArgs: [absPath]);
      expect(rows.single['status'], isNull,
          reason: 'NULL ⇒ derive; explicit notStarted would freeze the status');
      expect(await svc.getBookStatus(absPath), BookStatus.inProgress);
    });

    test('importFromJson applies newer entries', () async {
      final root = tempDir.path.replaceAll('\\', '/');
      final absPath = '$root/Author/Book';

      final json = jsonEncode({
        'version': 1,
        'exported_at': 0,
        'positions': [
          {
            'book_path': 'Author/Book',
            'global_position_ms': 60000,
            'total_duration_ms': 3600000,
            'status': 'inProgress',
            'updated_at': 9999999,
          }
        ],
      });
      await File('${tempDir.path}/positions.json').writeAsString(json);

      final backup = PositionBackupService();
      await backup.importFromJson(root);

      final positions = await svc.getAllPositions();
      expect(positions.length, 1);
      expect(positions.first.bookPath, absPath);
      expect(positions.first.globalPositionMs, 60000);
    });

    test('importFromJson skips entries where local updated_at is newer', () async {
      final root = tempDir.path.replaceAll('\\', '/');
      final absPath = '$root/Author/Book';

      await svc.savePosition(
        bookPath: absPath,
        chapterIndex: 3,
        position: const Duration(seconds: 90),
        globalPositionMs: 90000,
        totalDurationMs: 3600000,
      );
      final localPositions = await svc.getAllPositions();
      final localUpdatedAt = localPositions.first.updatedAt;

      final json = jsonEncode({
        'version': 1,
        'exported_at': 0,
        'positions': [
          {
            'book_path': 'Author/Book',
            'global_position_ms': 1000,
            'total_duration_ms': 3600000,
            'status': 'notStarted',
            'updated_at': localUpdatedAt - 1000,
          }
        ],
      });
      await File('${tempDir.path}/positions.json').writeAsString(json);

      final backup = PositionBackupService();
      await backup.importFromJson(root);

      final positions = await svc.getAllPositions();
      expect(positions.first.globalPositionMs, 90000);
    });

    test('round-trip: export then import leaves positions unchanged', () async {
      final root = tempDir.path.replaceAll('\\', '/');
      await svc.savePosition(
        bookPath: '$root/Author/Book',
        chapterIndex: 1,
        position: const Duration(seconds: 45),
        globalPositionMs: 45000,
        totalDurationMs: 7200000,
      );

      final backup = PositionBackupService();
      await backup.exportToJson(root);

      final svc2 = await _makePositionService();
      _setupLocator(svc2);
      await backup.importFromJson(root);

      final positions = await svc2.getAllPositions();
      expect(positions.length, 1);
      expect(positions.first.globalPositionMs, 45000);
      expect(positions.first.totalDurationMs, 7200000);
    });

    test('importFromJson with malformed JSON does not throw', () async {
      final root = tempDir.path.replaceAll('\\', '/');
      await File('${tempDir.path}/positions.json').writeAsString('not valid json {{{{');

      final backup = PositionBackupService();
      await expectLater(backup.importFromJson(root), completes);

      expect(await svc.getAllPositions(), isEmpty);
    });

    test('importFromJson with missing file is a no-op', () async {
      final root = tempDir.path.replaceAll('\\', '/');
      final backup = PositionBackupService();
      await expectLater(backup.importFromJson(root), completes);
      expect(await svc.getAllPositions(), isEmpty);
    });
  });
}
