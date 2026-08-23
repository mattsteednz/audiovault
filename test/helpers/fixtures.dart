import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kowhai/models/audiobook.dart';
import 'package:kowhai/services/drive_book_repository.dart';
import 'package:kowhai/services/drive_download_manager.dart';
import 'package:kowhai/services/position_service.dart';

/// Opens an in-memory database with the CURRENT production schema
/// (positions + bookmarks + drive catalog). Replaces the divergent per-file
/// schema copies across service tests.
Future<Database> openCurrentSchemaDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return databaseFactoryFfi.openDatabase(
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
            PRIMARY KEY (folder_id, file_index)
          )
        ''');
      },
    ),
  );
}

/// PositionService over [openCurrentSchemaDb].
Future<PositionService> makePositionService({void Function()? onSave}) async {
  final db = await openCurrentSchemaDb();
  return PositionService.withDatabase(db, onPositionSaved: onSave);
}

Audiobook testBook({
  String path = '/books/test',
  String title = 'Test Book',
  List<String>? audioFiles,
  List<Duration> chapterDurations = const [],
  Duration? duration,
}) =>
    Audiobook(
      title: title,
      path: path,
      audioFiles: audioFiles ?? const [],
      chapterDurations: chapterDurations,
      duration: duration,
    );

DriveBookRecord testDriveBook(String folderId) => DriveBookRecord(
      folderId: folderId,
      folderName: 'Book $folderId',
      rootFolderId: 'root',
      isShared: false,
      accountEmail: 'user@example.com',
      addedAt: 1000,
      audioFileIds: const [],
    );

DriveFileRecord testDriveFile(
  String folderId,
  int index,
  DriveDownloadState state,
) =>
    DriveFileRecord(
      folderId: folderId,
      fileIndex: index,
      fileId: '$folderId-$index',
      fileName: 'track$index.mp3',
      mimeType: 'audio/mpeg',
      sizeBytes: 1024,
      downloadState: state,
      localPath: '/path/$folderId/track$index.mp3',
    );

DownloadQueueSnapshot queueSnapshot(String id,
        {bool active = false, bool hasPending = true}) =>
    DownloadQueueSnapshot(folderId: id, active: active, hasPending: hasPending);

/// Stubs the connectivity_plus method channel so widget tests never hit the
/// real platform API. Mirrors the stub used by the prompt-preservation suite.
void stubConnectivity([List<ConnectivityResult> results = const []]) {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/connectivity');
  final encoded = results.map((r) => r.name).toList();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'check') return encoded;
    return null;
  });
}
