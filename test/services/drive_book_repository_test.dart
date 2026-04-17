import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiovault/services/drive_book_repository.dart';
import 'package:audiovault/services/position_service.dart';

/// Opens a fresh in-memory DB matching the production schema (version 3).
Future<({PositionService positionService, DriveBookRepository repo})>
    _makeRepo() async {
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
  final positionService = PositionService.withDatabase(db);
  return (
    positionService: positionService,
    repo: DriveBookRepository(positionService),
  );
}

DriveBookRecord _book(String folderId,
        {String name = 'Book', List<String> fileIds = const []}) =>
    DriveBookRecord(
      folderId: folderId,
      folderName: name,
      rootFolderId: 'root',
      isShared: false,
      accountEmail: 'user@example.com',
      addedAt: 1000,
      coverFileId: 'cover-$folderId',
      audioFileIds: fileIds,
    );

DriveFileRecord _file(String folderId, int index,
        {DriveDownloadState state = DriveDownloadState.none,
        String? localPath}) =>
    DriveFileRecord(
      folderId: folderId,
      fileIndex: index,
      fileId: '$folderId-$index',
      fileName: 'track${index.toString().padLeft(2, '0')}.mp3',
      mimeType: 'audio/mpeg',
      sizeBytes: 1024 * (index + 1),
      downloadState: state,
      localPath: localPath,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Record map round-trips', () {
    test('DriveBookRecord.toMap/fromMap preserves fields', () {
      final record = _book('F1', name: 'My Book', fileIds: ['a', 'b']);
      final map = record.toMap();
      final back = DriveBookRecord.fromMap(map, ['a', 'b']);
      expect(back.folderId, 'F1');
      expect(back.folderName, 'My Book');
      expect(back.isShared, isFalse);
      expect(back.accountEmail, 'user@example.com');
      expect(back.addedAt, 1000);
      expect(back.coverFileId, 'cover-F1');
      expect(back.audioFileIds, ['a', 'b']);
    });

    test('DriveFileRecord round-trips for each download state', () {
      for (final state in DriveDownloadState.values) {
        final record = _file('F', 3, state: state, localPath: '/tmp/x.mp3');
        final back = DriveFileRecord.fromMap(record.toMap());
        expect(back.downloadState, state, reason: 'state: $state');
        expect(back.folderId, 'F');
        expect(back.fileIndex, 3);
        expect(back.localPath, '/tmp/x.mp3');
      }
    });

    test('DriveFileRecord accepts unknown download_state as none', () {
      final map = _file('F', 0).toMap();
      map['download_state'] = 'gibberish';
      expect(DriveFileRecord.fromMap(map).downloadState,
          DriveDownloadState.none);
    });
  });

  group('DriveBookRepository', () {
    late DriveBookRepository repo;

    setUp(() async {
      repo = (await _makeRepo()).repo;
    });

    test('upsertDriveBook + getDriveBook round-trips', () async {
      await repo.upsertDriveBook(_book('F1', name: 'A'));
      final got = await repo.getDriveBook('F1');
      expect(got, isNotNull);
      expect(got!.folderName, 'A');
      expect(got.audioFileIds, isEmpty);
    });

    test('getDriveBook returns null for missing folder', () async {
      expect(await repo.getDriveBook('missing'), isNull);
    });

    test('upsertDriveBook replaces on conflict', () async {
      await repo.upsertDriveBook(_book('F1', name: 'First'));
      await repo.upsertDriveBook(_book('F1', name: 'Second'));
      final got = await repo.getDriveBook('F1');
      expect(got?.folderName, 'Second');
    });

    test('getFilesForBook returns files ordered by fileIndex', () async {
      await repo.upsertDriveBook(_book('F1'));
      await repo.upsertFile(_file('F1', 2));
      await repo.upsertFile(_file('F1', 0));
      await repo.upsertFile(_file('F1', 1));

      final files = await repo.getFilesForBook('F1');
      expect(files.map((f) => f.fileIndex), [0, 1, 2]);
    });

    test('getAllDriveBooks returns each book with its ordered file IDs',
        () async {
      await repo.upsertDriveBook(_book('F1', name: 'Alpha'));
      await repo.upsertFile(_file('F1', 1));
      await repo.upsertFile(_file('F1', 0));

      await repo.upsertDriveBook(_book('F2', name: 'Beta'));
      await repo.upsertFile(_file('F2', 0));

      final all = await repo.getAllDriveBooks();
      expect(all.length, 2);
      final f1 = all.firstWhere((b) => b.folderId == 'F1');
      expect(f1.audioFileIds, ['F1-0', 'F1-1']);
    });

    test('updateFileState persists and optionally sets localPath', () async {
      await repo.upsertDriveBook(_book('F1'));
      await repo.upsertFile(_file('F1', 0));

      await repo.updateFileState('F1', 0, DriveDownloadState.downloading);
      var files = await repo.getFilesForBook('F1');
      expect(files.first.downloadState, DriveDownloadState.downloading);
      expect(files.first.localPath, isNull);

      await repo.updateFileState('F1', 0, DriveDownloadState.done,
          localPath: '/tmp/done.mp3');
      files = await repo.getFilesForBook('F1');
      expect(files.first.downloadState, DriveDownloadState.done);
      expect(files.first.localPath, '/tmp/done.mp3');
    });

    test('resetBookDownloads resets every file to none', () async {
      await repo.upsertDriveBook(_book('F1'));
      await repo.upsertFile(
          _file('F1', 0, state: DriveDownloadState.done, localPath: '/x'));
      await repo.upsertFile(_file('F1', 1, state: DriveDownloadState.error));

      await repo.resetBookDownloads('F1');

      final files = await repo.getFilesForBook('F1');
      expect(files.every((f) => f.downloadState == DriveDownloadState.none),
          isTrue);
      // localPath must be preserved so re-downloads reuse the same location.
      expect(files.firstWhere((f) => f.fileIndex == 0).localPath, '/x');
    });

    test('deleteDriveBook removes book and its files', () async {
      await repo.upsertDriveBook(_book('F1'));
      await repo.upsertFile(_file('F1', 0));
      await repo.upsertFile(_file('F1', 1));

      await repo.deleteDriveBook('F1');

      expect(await repo.getDriveBook('F1'), isNull);
      expect(await repo.getFilesForBook('F1'), isEmpty);
    });

    test('deleteDriveBook does not affect other books', () async {
      await repo.upsertDriveBook(_book('F1'));
      await repo.upsertDriveBook(_book('F2'));
      await repo.upsertFile(_file('F2', 0));

      await repo.deleteDriveBook('F1');

      expect(await repo.getDriveBook('F2'), isNotNull);
      expect((await repo.getFilesForBook('F2')).length, 1);
    });

    test('resetStaleDownloads resets missing-file rows to none', () async {
      await repo.upsertDriveBook(_book('F1'));
      // localPath points to a non-existent file.
      await repo.upsertFile(_file('F1', 0,
          state: DriveDownloadState.downloading,
          localPath: '/does/not/exist.mp3'));

      await repo.resetStaleDownloads();

      final files = await repo.getFilesForBook('F1');
      expect(files.first.downloadState, DriveDownloadState.none);
    });
  });
}
