import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kowhai/models/audiobook.dart' show BookStatus;
import 'package:kowhai/services/position_service.dart';

/// The v1 schema exactly as it existed before the drive tables (v2), the
/// explicit status column (v3), and bookmarks (v4) were added.
const _v1PositionsSql = '''
  CREATE TABLE positions (
    book_path TEXT PRIMARY KEY,
    chapter_index INTEGER NOT NULL DEFAULT 0,
    position_ms INTEGER NOT NULL DEFAULT 0,
    global_position_ms INTEGER NOT NULL DEFAULT 0,
    total_duration_ms INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL
  )
''';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('v1 → v4 production upgrade chain preserves data and adds all tables',
      () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, singleInstance: false,
          onCreate: (db, _) => db.execute(_v1PositionsSql)),
    );

    // Seed v1-era rows: one mid-book, one with progress.
    await db.insert('positions', {
      'book_path': '/books/my-book',
      'chapter_index': 2,
      'position_ms': 45000,
      'global_position_ms': 120000,
      'total_duration_ms': 3600000,
      'updated_at': 1000000,
    });
    await db.insert('positions', {
      'book_path': '/books/other',
      'chapter_index': 0,
      'position_ms': 5000,
      'global_position_ms': 5000,
      'total_duration_ms': 600000,
      'updated_at': 2000000,
    });

    // THE PRODUCTION PATH — the same static production's onUpgrade delegates to.
    await PositionService.performUpgrades(db, 1);

    // positions data intact + status column now present.
    final positions = await db.query('positions');
    expect(positions.length, 2);
    expect(positions.firstWhere((r) => r['book_path'] == '/books/my-book')['chapter_index'], 2);
    final cols = (await db.rawQuery('PRAGMA table_info(positions)'))
        .map((r) => r['name'])
        .toSet();
    expect(cols, containsAll(['status', 'global_position_ms']));

    // Explicit status written at v3+ survives further schema evolution.
    await db.update('positions', {'status': 'finished'},
        where: 'book_path = ?', whereArgs: ['/books/my-book']);
    final after = await db.query('positions',
        where: 'book_path = ?', whereArgs: ['/books/my-book']);
    expect(after.first['status'], 'finished');

    // Drive catalog tables created and usable.
    await db.insert('drive_books', {
      'folder_id': 'F1',
      'folder_name': 'Book F1',
      'root_folder_id': 'root',
      'is_shared': 0,
      'account_email': 'u@e.com',
      'added_at': 1,
    });
    expect(await db.query('drive_books'), hasLength(1));

    // Bookmarks table created with its index and insertable.
    await db.insert('bookmarks', {
      'book_path': '/books/my-book',
      'chapter_index': 2,
      'position_ms': 45000,
      'label': 'Test bookmark',
      'created_at': 2000000,
    });
    expect(await db.query('bookmarks'), hasLength(1));

    // Service-level operations work on the migrated schema.
    final svc = PositionService.withDatabase(db);
    final pos = await svc.getPosition('/books/my-book');
    expect(pos!.chapterIndex, 2);
    expect(await svc.getBookStatus('/books/my-book'), BookStatus.finished);
  });

  test('v3 → v4 step only creates bookmarks, keeps status column', () async {
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
    await db.insert('positions', {
      'book_path': '/books/my-book',
      'chapter_index': 2,
      'position_ms': 45000,
      'global_position_ms': 120000,
      'total_duration_ms': 3600000,
      'updated_at': 1000000,
      'status': null,
    });

    await PositionService.performUpgrades(db, 3);

    expect((await db.query('positions')).length, 1);
    expect(await db.query('bookmarks'), isEmpty); // exists, empty
    await db.insert('bookmarks', {
      'book_path': '/books/my-book',
      'chapter_index': 2,
      'position_ms': 45000,
      'label': 'B',
      'created_at': 1,
    });
    expect(await db.query('bookmarks'), hasLength(1));
  });

  test('PositionService.withDatabase works with v4 schema', () async {
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
              position_ms INTEGER NOT NULL,
              label        TEXT NOT NULL,
              notes        TEXT,
              created_at   INTEGER NOT NULL
            )
          ''');
        },
      ),
    );

    final svc = PositionService.withDatabase(db);
    await svc.savePosition(
      bookPath: '/books/test',
      chapterIndex: 0,
      position: const Duration(seconds: 30),
      globalPositionMs: 30000,
      totalDurationMs: 3600000,
    );
    final pos = await svc.getPosition('/books/test');
    expect(pos, isNotNull);
    expect(pos!.chapterIndex, 0);
  });
}
