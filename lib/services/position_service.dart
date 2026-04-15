import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class PositionService {
  PositionService();

  /// Injects an already-opened [Database] — for use in tests only.
  @visibleForTesting
  PositionService.withDatabase(Database db) : _db = db;

  Database? _db;

  /// Direct database access for test assertions — do not use in production.
  @visibleForTesting
  Future<Database> get databaseForTesting => _database;

  /// Shared DB access for DriveBookRepository (same file, same instance).
  Future<Database> get sharedDb => _database;

  Future<Database> get _database async {
    _db ??= await _openDb();
    return _db!;
  }

  Future<Database> _openDb() async {
    final dir = await getApplicationDocumentsDirectory();
    return openDatabase(
      '${dir.path}/audiovault_positions.db',
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE positions (
            book_path TEXT PRIMARY KEY,
            chapter_index INTEGER NOT NULL DEFAULT 0,
            position_ms INTEGER NOT NULL DEFAULT 0,
            global_position_ms INTEGER NOT NULL DEFAULT 0,
            total_duration_ms INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL
          )
        ''');
        await _createDriveTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createDriveTables(db);
        }
      },
    );
  }

  Future<void> _createDriveTables(Database db) async {
    await db.execute('''
      CREATE TABLE drive_books (
        folder_id       TEXT PRIMARY KEY,
        folder_name     TEXT NOT NULL,
        root_folder_id  TEXT NOT NULL,
        is_shared       INTEGER NOT NULL DEFAULT 0,
        account_email   TEXT NOT NULL,
        added_at        INTEGER NOT NULL,
        cover_file_id   TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE drive_book_files (
        folder_id       TEXT NOT NULL,
        file_index      INTEGER NOT NULL,
        file_id         TEXT NOT NULL,
        file_name       TEXT NOT NULL,
        mime_type       TEXT NOT NULL,
        size_bytes      INTEGER NOT NULL DEFAULT 0,
        download_state  TEXT NOT NULL DEFAULT 'none',
        local_path      TEXT,
        PRIMARY KEY (folder_id, file_index),
        FOREIGN KEY (folder_id) REFERENCES drive_books(folder_id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> savePosition({
    required String bookPath,
    required int chapterIndex,
    required Duration position,
    required int globalPositionMs,
    required int totalDurationMs,
  }) async {
    final db = await _database;
    await db.insert(
      'positions',
      {
        'book_path': bookPath,
        'chapter_index': chapterIndex,
        'position_ms': position.inMilliseconds,
        'global_position_ms': globalPositionMs,
        'total_duration_ms': totalDurationMs,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<({int chapterIndex, Duration position})?> getPosition(
      String bookPath) async {
    final db = await _database;
    final rows = await db.query(
      'positions',
      where: 'book_path = ?',
      whereArgs: [bookPath],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return (
      chapterIndex: row['chapter_index'] as int,
      position: Duration(milliseconds: row['position_ms'] as int),
    );
  }

  Future<String?> getLastPlayedBookPath() async {
    final db = await _database;
    final rows = await db.query(
      'positions',
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['book_path'] as String?;
  }

  Future<List<BookProgress>> getAllPositions() async {
    final db = await _database;
    final rows =
        await db.query('positions', orderBy: 'updated_at DESC');
    return rows
        .map((r) => (
              bookPath: r['book_path'] as String,
              globalPositionMs: r['global_position_ms'] as int,
              totalDurationMs: r['total_duration_ms'] as int,
              updatedAt: r['updated_at'] as int,
            ))
        .toList();
  }
}

typedef BookProgress = ({
  String bookPath,
  int globalPositionMs,
  int totalDurationMs,
  int updatedAt,
});
