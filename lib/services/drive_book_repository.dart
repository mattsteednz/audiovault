import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'position_service.dart';

enum DriveDownloadState { none, downloading, done, error }

class DriveBookRecord {
  final String folderId;
  final String folderName;
  final String rootFolderId;
  final bool isShared;
  final String accountEmail;
  final int addedAt;
  final String? coverFileId;
  final List<String> audioFileIds; // ordered list of Drive file IDs

  const DriveBookRecord({
    required this.folderId,
    required this.folderName,
    required this.rootFolderId,
    required this.isShared,
    required this.accountEmail,
    required this.addedAt,
    this.coverFileId,
    required this.audioFileIds,
  });

  Map<String, Object?> toMap() => {
        'folder_id': folderId,
        'folder_name': folderName,
        'root_folder_id': rootFolderId,
        'is_shared': isShared ? 1 : 0,
        'account_email': accountEmail,
        'added_at': addedAt,
        'cover_file_id': coverFileId,
      };

  static DriveBookRecord fromMap(Map<String, Object?> map, List<String> fileIds) =>
      DriveBookRecord(
        folderId: map['folder_id'] as String,
        folderName: map['folder_name'] as String,
        rootFolderId: map['root_folder_id'] as String,
        isShared: (map['is_shared'] as int) != 0,
        accountEmail: map['account_email'] as String,
        addedAt: map['added_at'] as int,
        coverFileId: map['cover_file_id'] as String?,
        audioFileIds: fileIds,
      );
}

class DriveFileRecord {
  final String folderId;
  final int fileIndex;
  final String fileId;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final DriveDownloadState downloadState;
  final String? localPath;

  const DriveFileRecord({
    required this.folderId,
    required this.fileIndex,
    required this.fileId,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.downloadState,
    this.localPath,
  });

  Map<String, Object?> toMap() => {
        'folder_id': folderId,
        'file_index': fileIndex,
        'file_id': fileId,
        'file_name': fileName,
        'mime_type': mimeType,
        'size_bytes': sizeBytes,
        'download_state': _stateToString(downloadState),
        'local_path': localPath,
      };

  static DriveFileRecord fromMap(Map<String, Object?> map) => DriveFileRecord(
        folderId: map['folder_id'] as String,
        fileIndex: map['file_index'] as int,
        fileId: map['file_id'] as String,
        fileName: map['file_name'] as String,
        mimeType: map['mime_type'] as String,
        sizeBytes: map['size_bytes'] as int,
        downloadState: _stateFromString(map['download_state'] as String),
        localPath: map['local_path'] as String?,
      );

  static String _stateToString(DriveDownloadState s) => switch (s) {
        DriveDownloadState.none => 'none',
        DriveDownloadState.downloading => 'downloading',
        DriveDownloadState.done => 'done',
        DriveDownloadState.error => 'error',
      };

  static DriveDownloadState _stateFromString(String s) => switch (s) {
        'downloading' => DriveDownloadState.downloading,
        'done' => DriveDownloadState.done,
        'error' => DriveDownloadState.error,
        _ => DriveDownloadState.none,
      };
}

class DriveBookRepository {
  final PositionService _positionService;

  DriveBookRepository(this._positionService);

  Future<Database> get _db => _positionService.sharedDb;

  Future<void> upsertDriveBook(DriveBookRecord record) async {
    final db = await _db;
    await db.insert('drive_books', record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertFile(DriveFileRecord record) async {
    final db = await _db;
    await db.insert('drive_book_files', record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<DriveBookRecord>> getAllDriveBooks() async {
    final db = await _db;
    final bookRows = await db.query('drive_books');
    final result = <DriveBookRecord>[];
    for (final row in bookRows) {
      final folderId = row['folder_id'] as String;
      final fileRows = await db.query(
        'drive_book_files',
        where: 'folder_id = ?',
        whereArgs: [folderId],
        orderBy: 'file_index ASC',
      );
      final fileIds = fileRows.map((r) => r['file_id'] as String).toList();
      result.add(DriveBookRecord.fromMap(row, fileIds));
    }
    return result;
  }

  Future<DriveBookRecord?> getDriveBook(String folderId) async {
    final db = await _db;
    final rows = await db.query(
      'drive_books',
      where: 'folder_id = ?',
      whereArgs: [folderId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final fileRows = await db.query(
      'drive_book_files',
      where: 'folder_id = ?',
      whereArgs: [folderId],
      orderBy: 'file_index ASC',
    );
    final fileIds = fileRows.map((r) => r['file_id'] as String).toList();
    return DriveBookRecord.fromMap(rows.first, fileIds);
  }

  /// Resets all files for a book back to [DriveDownloadState.none] and clears
  /// their local paths. The book record itself is kept — it stays in the library.
  Future<void> resetBookDownloads(String folderId) async {
    final db = await _db;
    await db.update(
      'drive_book_files',
      {'download_state': 'none', 'local_path': null},
      where: 'folder_id = ?',
      whereArgs: [folderId],
    );
  }

  Future<void> deleteDriveBook(String folderId) async {
    final db = await _db;
    // Foreign key cascade handles drive_book_files deletion if FK pragmas are on,
    // but SQLite FK is off by default in sqflite — delete explicitly.
    await db.delete('drive_book_files', where: 'folder_id = ?', whereArgs: [folderId]);
    await db.delete('drive_books', where: 'folder_id = ?', whereArgs: [folderId]);
  }

  Future<List<DriveFileRecord>> getFilesForBook(String folderId) async {
    final db = await _db;
    final rows = await db.query(
      'drive_book_files',
      where: 'folder_id = ?',
      whereArgs: [folderId],
      orderBy: 'file_index ASC',
    );
    return rows.map(DriveFileRecord.fromMap).toList();
  }

  Future<void> updateFileState(
    String folderId,
    int fileIndex,
    DriveDownloadState state, {
    String? localPath,
  }) async {
    final db = await _db;
    final values = <String, Object?>{
      'download_state': DriveFileRecord._stateToString(state),
    };
    if (localPath != null) values['local_path'] = localPath;
    await db.update(
      'drive_book_files',
      values,
      where: 'folder_id = ? AND file_index = ?',
      whereArgs: [folderId, fileIndex],
    );
  }

  /// Recovers stale 'downloading' state on startup.
  /// If the local file exists, marks it as 'done'; otherwise resets to 'none'.
  Future<void> resetStaleDownloads() async {
    final db = await _db;
    final stale = await db.query(
      'drive_book_files',
      where: "download_state = 'downloading'",
    );
    for (final row in stale) {
      final localPath = row['local_path'] as String?;
      final exists = localPath != null && await File(localPath).exists();
      await db.update(
        'drive_book_files',
        {'download_state': exists ? 'done' : 'none'},
        where: 'folder_id = ? AND file_index = ?',
        whereArgs: [row['folder_id'], row['file_index']],
      );
    }
  }
}
