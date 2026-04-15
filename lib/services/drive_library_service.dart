import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/audiobook.dart';
import 'drive_book_repository.dart';
import 'drive_download_manager.dart';
import 'drive_service.dart';
import 'preferences_service.dart';
import 'scanner_service.dart';

class DriveLibraryService {
  final DriveBookRepository _repo;
  final DriveService _driveService;
  final DriveDownloadManager _downloadManager;
  final PreferencesService _prefs;
  final ScannerService _scanner;

  DriveLibraryService(
    this._repo,
    this._driveService,
    this._downloadManager,
    this._prefs,
    this._scanner,
  );

  /// Returns the local download directory for a Drive book.
  Future<String> bookDir(String folderId) async {
    final docs = await getApplicationDocumentsDirectory();
    return '${docs.path}/drive_books/$folderId';
  }

  /// Loads all known Drive books from DB without any network calls.
  Future<List<Audiobook>> loadDriveBooks() async {
    final books = await _repo.getAllDriveBooks();
    final result = <Audiobook>[];
    for (final record in books) {
      final book = await _buildAudiobook(record);
      result.add(book);
    }
    return result;
  }

  /// Builds an [Audiobook] from a [DriveBookRecord] + its file records.
  Future<Audiobook> _buildAudiobook(DriveBookRecord record) async {
    final dir = await bookDir(record.folderId);
    final files = await _repo.getFilesForBook(record.folderId);

    // audioFiles only contains paths for downloaded files
    final audioFiles = files
        .where((f) => f.downloadState == DriveDownloadState.done && f.localPath != null)
        .map((f) => f.localPath!)
        .toList();

    // Cover: check if cover.jpg exists locally; kick off background download if not
    String? coverPath;
    final coverFile = File('$dir/cover.jpg');
    if (await coverFile.exists()) {
      coverPath = coverFile.path;
    } else if (record.coverFileId != null) {
      // Fire-and-forget: download cover in the background
      _downloadManager
          .downloadCover(
            folderId: record.folderId,
            coverFileId: record.coverFileId!,
            destDir: dir,
          )
          .ignore();
    }

    final totalFiles = files.length;

    return Audiobook(
      title: record.folderName,
      path: dir,
      audioFiles: audioFiles,
      source: AudiobookSource.drive,
      driveMetadata: DriveBookMeta(
        folderId: record.folderId,
        folderName: record.folderName,
        isShared: record.isShared,
        totalFileCount: totalFiles,
      ),
      coverImagePath: coverPath,
    );
  }

  /// Re-scans Drive for the user's chosen root folder, diffs against stored
  /// records, and adds new books. Does not remove books whose Drive source is
  /// gone (keeps downloaded content accessible).
  Future<List<Audiobook>> rescanDrive() async {
    final rootFolder = await _prefs.getDriveRootFolder();
    if (rootFolder == null) return await loadDriveBooks();

    final account = _driveService.currentAccount;
    if (account == null) return await loadDriveBooks();

    final scans = await _driveService.scanRootFolder(
        rootFolder.id, rootFolder.isShared);

    for (final scan in scans) {
      final existing = await _repo.getDriveBook(scan.folder.id);
      if (existing != null) continue; // already tracked

      final dir = await bookDir(scan.folder.id);
      await Directory(dir).create(recursive: true);

      // Save book record
      await _repo.upsertDriveBook(DriveBookRecord(
        folderId: scan.folder.id,
        folderName: scan.folder.name,
        rootFolderId: rootFolder.id,
        isShared: scan.folder.isShared,
        accountEmail: account.email,
        addedAt: DateTime.now().millisecondsSinceEpoch,
        coverFileId: scan.coverFile?.id,
        audioFileIds: scan.audioFiles.map((f) => f.id).toList(),
      ));

      // Save file records
      for (int i = 0; i < scan.audioFiles.length; i++) {
        final f = scan.audioFiles[i];
        await _repo.upsertFile(DriveFileRecord(
          folderId: scan.folder.id,
          fileIndex: i,
          fileId: f.id,
          fileName: f.name,
          mimeType: f.mimeType,
          sizeBytes: f.sizeBytes,
          downloadState: DriveDownloadState.none,
          localPath: '$dir/${f.name}',
        ));
      }
    }

    return await loadDriveBooks();
  }

  /// Removes all Drive books that have no downloaded files from the DB.
  /// Call on disconnect. Books with at least one downloaded file are kept.
  Future<void> removeUndownloadedBooks() async {
    final books = await _repo.getAllDriveBooks();
    for (final record in books) {
      final files = await _repo.getFilesForBook(record.folderId);
      final hasDownloaded = files.any((f) => f.downloadState == DriveDownloadState.done);
      if (!hasDownloaded) {
        await _repo.deleteDriveBook(record.folderId);
      }
    }
  }

  /// Initiates download of the first file for a multi-file book so the user
  /// can start playing, then queues the rest progressively.
  /// For M4B (single file), downloads the whole book.
  Future<void> startDownload(String folderId) async {
    final files = await _repo.getFilesForBook(folderId);
    if (files.isEmpty) return;

    final isSingleFile = files.length == 1;
    if (isSingleFile) {
      await _downloadManager.enqueueAllFiles(folderId);
    } else {
      // Download first file immediately, rest will be queued progressively
      await _downloadManager.enqueueNextFiles(
        folderId: folderId,
        fromFileIndex: 0,
        count: 1,
      );
    }
  }

  /// After a book is fully downloaded, re-scans its local directory via
  /// ScannerService to get embedded chapters, author, durations, etc.
  /// Returns the enriched Audiobook, or null if scan fails.
  Future<Audiobook?> promoteToLocal(String folderId) async {
    final record = await _repo.getDriveBook(folderId);
    if (record == null) return null;

    final dir = await bookDir(folderId);

    // Download cover if we have a cover file ID and don't have it yet
    final coverPath = '$dir/cover.jpg';
    if (record.coverFileId != null && !await File(coverPath).exists()) {
      await _downloadManager.downloadCover(
        folderId: folderId,
        coverFileId: record.coverFileId!,
        destDir: dir,
      );
    }

    // Re-scan the local directory
    final scanned = await _scanner.scanSingleBook(dir);
    if (scanned == null) return null;

    // Return the scanned book augmented with Drive metadata
    return Audiobook(
      title: scanned.title.isNotEmpty ? scanned.title : record.folderName,
      author: scanned.author,
      duration: scanned.duration,
      path: scanned.path,
      coverImagePath: scanned.coverImagePath,
      coverImageBytes: scanned.coverImageBytes,
      audioFiles: scanned.audioFiles,
      chapterDurations: scanned.chapterDurations,
      chapters: scanned.chapters,
      chapterNames: scanned.chapterNames,
      isDrmLocked: scanned.isDrmLocked,
      source: AudiobookSource.drive,
      driveMetadata: DriveBookMeta(
        folderId: record.folderId,
        folderName: record.folderName,
        isShared: record.isShared,
        totalFileCount: (await _repo.getFilesForBook(folderId)).length,
      ),
    );
  }

  /// Returns total size in bytes for all files in a Drive book.
  Future<int> totalSizeBytes(String folderId) async {
    final files = await _repo.getFilesForBook(folderId);
    return files.fold<int>(0, (sum, f) => sum + f.sizeBytes);
  }

  /// Deletes all downloaded audio files for [folderId] from disk and resets
  /// their download state to [DriveDownloadState.none]. The DB record and
  /// metadata are preserved so the book remains in the library as finished.
  Future<void> deleteLocalFiles(String folderId) async {
    final files = await _repo.getFilesForBook(folderId);
    for (final f in files) {
      if (f.localPath != null) {
        final file = File(f.localPath!);
        if (await file.exists()) await file.delete();
      }
      await _repo.updateFileState(folderId, f.fileIndex, DriveDownloadState.none);
    }
  }
}
