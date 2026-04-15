import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'drive_book_repository.dart';
import 'drive_service.dart';

class DriveDownloadEvent {
  final String folderId;
  final int? fileIndex; // null = cover download
  final DriveDownloadState state;
  final double? progress; // 0.0–1.0, null if unknown
  final int? bytesDownloaded; // bytes received for current file
  final int? fileSizeBytes; // total size of current file

  const DriveDownloadEvent({
    required this.folderId,
    this.fileIndex,
    required this.state,
    this.progress,
    this.bytesDownloaded,
    this.fileSizeBytes,
  });
}

class DriveDownloadManager {
  final DriveBookRepository _repo;
  final DriveService _driveService;

  DriveDownloadManager(this._repo, this._driveService);

  final _controller = StreamController<DriveDownloadEvent>.broadcast();
  Stream<DriveDownloadEvent> get downloadEvents => _controller.stream;

  // Per-book download queues. Each book has at most one active download at a time.
  final Map<String, _BookQueue> _queues = {};
  // Limit total concurrent active downloads across all books.
  int _activeCount = 0;
  static const _maxConcurrent = 2;

  /// Enqueues the next [count] undownloaded files for [folderId] starting from [fromFileIndex].
  Future<void> enqueueNextFiles({
    required String folderId,
    required int fromFileIndex,
    int count = 3,
  }) async {
    final files = await _repo.getFilesForBook(folderId);
    // Find undownloaded files starting at or after fromFileIndex
    final toQueue = files
        .where((f) =>
            f.fileIndex >= fromFileIndex &&
            f.downloadState == DriveDownloadState.none)
        .take(count)
        .toList();

    for (final f in toQueue) {
      _enqueue(folderId, f);
    }
    _drain();
  }

  /// Download all files for [folderId] — used for M4B (single file) and initial
  /// multi-file download where we want the whole book.
  Future<void> enqueueAllFiles(String folderId) async {
    // Clear any stale pending jobs from a previous download attempt.
    _queues[folderId]?.pending.clear();

    final files = await _repo.getFilesForBook(folderId);
    // Include error-state files so retrying a failed download works.
    final toQueue = files
        .where((f) =>
            f.downloadState == DriveDownloadState.none ||
            f.downloadState == DriveDownloadState.error)
        .toList();
    // Reset error-state files back to none before re-queuing.
    for (final f in toQueue) {
      if (f.downloadState == DriveDownloadState.error) {
        await _repo.updateFileState(folderId, f.fileIndex, DriveDownloadState.none);
      }
      _enqueue(folderId, f);
    }
    _drain();
  }

  void _enqueue(String folderId, DriveFileRecord file) {
    final queue = _queues.putIfAbsent(folderId, () => _BookQueue(folderId));
    // Avoid duplicates
    if (queue.pending.any((j) => j.fileIndex == file.fileIndex)) return;
    queue.pending.add(_DownloadJob(
      folderId: folderId,
      fileIndex: file.fileIndex,
      fileId: file.fileId,
      fileName: file.fileName,
      localPath: file.localPath ?? '',
      sizeBytes: file.sizeBytes,
    ));
  }

  void _drain() {
    if (_activeCount >= _maxConcurrent) return;
    for (final queue in _queues.values) {
      if (_activeCount >= _maxConcurrent) break;
      if (queue.active || queue.pending.isEmpty) continue;
      final job = queue.pending.removeAt(0);
      queue.active = true;
      _activeCount++;
      _runJob(queue, job);
    }
  }

  void _runJob(_BookQueue queue, _DownloadJob job) {
    _doDownload(job, queue).then((_) {
      queue.active = false;
      queue.activeClient = null;
      _activeCount--;
      _drain();
    }).catchError((e) {
      queue.active = false;
      queue.activeClient = null;
      _activeCount--;
      if (queue.cancelling) {
        // Cancellation in progress — don't retry, just drain remaining.
        queue.cancelling = false;
        _drain();
      } else if (job.retriesLeft > 0) {
        // Re-queue at the front with one fewer retry, after a short delay.
        Future.delayed(const Duration(seconds: 3), () {
          queue.pending.insert(0, job.withRetry());
          _drain();
        });
      } else {
        _drain();
      }
    });
  }

  /// Cancels all pending and active downloads for [folderId].
  Future<void> cancelDownload(String folderId) async {
    final queue = _queues[folderId];
    if (queue == null) return;
    queue.cancelling = true;
    queue.pending.clear();
    queue.activeClient?.close(); // Causes the active stream to throw
  }

  Future<void> _doDownload(_DownloadJob job, _BookQueue queue) async {
    await _repo.updateFileState(
        job.folderId, job.fileIndex, DriveDownloadState.downloading);
    _controller.add(DriveDownloadEvent(
      folderId: job.folderId,
      fileIndex: job.fileIndex,
      state: DriveDownloadState.downloading,
      progress: 0,
    ));

    try {
      final destPath = job.localPath.isNotEmpty
          ? job.localPath
          : await _defaultDestPath(job.folderId, job.fileName);

      await _downloadFile(
        fileId: job.fileId,
        destPath: destPath,
        onClientCreated: (client) => queue.activeClient = client,
        onProgress: (received, total) {
          _controller.add(DriveDownloadEvent(
            folderId: job.folderId,
            fileIndex: job.fileIndex,
            state: DriveDownloadState.downloading,
            progress: total > 0 ? received / total : null,
            bytesDownloaded: received,
            fileSizeBytes: job.sizeBytes,
          ));
        },
      );

      await _repo.updateFileState(
        job.folderId,
        job.fileIndex,
        DriveDownloadState.done,
        localPath: destPath,
      );
      _controller.add(DriveDownloadEvent(
        folderId: job.folderId,
        fileIndex: job.fileIndex,
        state: DriveDownloadState.done,
        progress: 1.0,
        fileSizeBytes: job.sizeBytes,
      ));
    } catch (_) {
      await _repo.updateFileState(
          job.folderId, job.fileIndex, DriveDownloadState.error);
      _controller.add(DriveDownloadEvent(
        folderId: job.folderId,
        fileIndex: job.fileIndex,
        state: DriveDownloadState.error,
      ));
      rethrow;
    }
  }

  /// Downloads a single Drive file to [destPath], streaming to avoid memory bloat.
  /// Retries once on 401 with a fresh token.
  Future<void> _downloadFile({
    required String fileId,
    required String destPath,
    void Function(int received, int total)? onProgress,
    void Function(http.Client client)? onClientCreated,
  }) async {
    final token = await _driveService.getAccessToken();
    if (token == null) throw Exception('Not signed in');

    Future<void> attempt(String t) async {
      final uri = Uri.parse(
          'https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
      final request = http.Request('GET', uri)
        ..headers['Authorization'] = 'Bearer $t';
      final client = http.Client();
      onClientCreated?.call(client);
      try {
        final response = await client.send(request);
        if (response.statusCode == 401) {
          throw _AuthException();
        }
        if (response.statusCode != 200) {
          throw Exception('Drive download failed: ${response.statusCode}');
        }

        final file = File(destPath);
        await file.parent.create(recursive: true);
        final sink = file.openWrite();
        int received = 0;
        final total = response.contentLength ?? 0;

        try {
          await for (final chunk in response.stream
              .timeout(const Duration(seconds: 30))) {
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(received, total);
          }
        } catch (_) {
          await sink.close();
          // Delete partial file so a retry starts fresh.
          if (await file.exists()) await file.delete();
          rethrow;
        }
        await sink.flush();
        await sink.close();
      } finally {
        client.close();
      }
    }

    try {
      await attempt(token);
    } on _AuthException {
      // Refresh and retry once
      final newToken = await _driveService.getAccessToken();
      if (newToken == null) rethrow;
      await attempt(newToken);
    }
  }

  /// Downloads the cover image for a book.
  Future<String?> downloadCover({
    required String folderId,
    required String coverFileId,
    required String destDir,
    String fileName = 'cover.jpg',
  }) async {
    final destPath = '$destDir/$fileName';
    try {
      await _downloadFile(fileId: coverFileId, destPath: destPath);
      _controller.add(DriveDownloadEvent(
        folderId: folderId,
        fileIndex: null,
        state: DriveDownloadState.done,
      ));
      return destPath;
    } catch (_) {
      return null;
    }
  }

  Future<String> _defaultDestPath(String folderId, String fileName) async {
    // Relies on path_provider — resolved by caller passing localPath or by
    // DriveLibraryService which knows the book directory.
    // This is a fallback; normally localPath is set by DriveLibraryService.
    return '/tmp/drive_books/$folderId/$fileName';
  }

  void dispose() {
    _controller.close();
  }
}

class _BookQueue {
  final String folderId;
  bool active = false;
  bool cancelling = false;
  http.Client? activeClient;
  final List<_DownloadJob> pending = [];
  _BookQueue(this.folderId);
}

class _DownloadJob {
  final String folderId;
  final int fileIndex;
  final String fileId;
  final String fileName;
  final String localPath;
  final int sizeBytes;
  final int retriesLeft;

  _DownloadJob({
    required this.folderId,
    required this.fileIndex,
    required this.fileId,
    required this.fileName,
    required this.localPath,
    required this.sizeBytes,
    this.retriesLeft = 3,
  });

  _DownloadJob withRetry() => _DownloadJob(
        folderId: folderId,
        fileIndex: fileIndex,
        fileId: fileId,
        fileName: fileName,
        localPath: localPath,
        sizeBytes: sizeBytes,
        retriesLeft: retriesLeft - 1,
      );
}

class _AuthException implements Exception {}
