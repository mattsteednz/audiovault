import 'package:flutter/material.dart';

import '../locator.dart';
import '../models/audiobook.dart';
import '../services/drive_book_repository.dart';
import '../services/drive_download_manager.dart';

/// Wraps a book card/tile with Drive-specific overlays:
/// - Grey tint + download icon when not downloaded
/// - Progress indicator when downloading
/// - Cloud badge when at least partially downloaded
class DriveDownloadOverlay extends StatefulWidget {
  final Audiobook book;
  final Widget child;

  const DriveDownloadOverlay({
    super.key,
    required this.book,
    required this.child,
  });

  @override
  State<DriveDownloadOverlay> createState() => _DriveDownloadOverlayState();
}

class _DriveDownloadOverlayState extends State<DriveDownloadOverlay> {
  late final DriveDownloadManager _dlManager;
  late final DriveBookRepository _repo;

  _OverlayState _state = _OverlayState.notDownloaded;
  double _progress = 0;
  int _downloadedCount = 0;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _dlManager = locator<DriveDownloadManager>();
    _repo = locator<DriveBookRepository>();
    _initState();
    _dlManager.downloadEvents
        .where((e) => e.folderId == widget.book.driveMetadata!.folderId)
        .listen(_onEvent);
  }

  Future<void> _initState() async {
    final folderId = widget.book.driveMetadata!.folderId;
    final files = await _repo.getFilesForBook(folderId);
    if (!mounted) return;
    final downloaded = files.where((f) => f.downloadState == DriveDownloadState.done).length;
    final total = files.length;
    final anyDownloading = files.any((f) => f.downloadState == DriveDownloadState.downloading);

    setState(() {
      _downloadedCount = downloaded;
      _totalCount = total;
      if (total == 0 || downloaded == 0) {
        _state = _OverlayState.notDownloaded;
      } else if (anyDownloading) {
        _state = _OverlayState.downloading;
      } else if (downloaded < total) {
        _state = _OverlayState.partial;
      } else {
        _state = _OverlayState.done;
      }
    });
  }

  void _onEvent(DriveDownloadEvent event) {
    if (!mounted) return;
    setState(() {
      if (event.state == DriveDownloadState.downloading) {
        _state = _OverlayState.downloading;
        if (event.progress != null) _progress = event.progress!;
      } else if (event.state == DriveDownloadState.done) {
        _downloadedCount++;
        if (_downloadedCount >= _totalCount) {
          _state = _OverlayState.done;
        } else {
          _state = _OverlayState.partial;
        }
        _progress = 0;
      } else if (event.state == DriveDownloadState.error) {
        _state = _downloadedCount > 0
            ? _OverlayState.partial
            : _OverlayState.notDownloaded;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalCount = widget.book.driveMetadata!.totalFileCount;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,

        // Grey tint + download icon for not-downloaded books
        if (_state == _OverlayState.notDownloaded)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.black.withValues(alpha: 0.55),
                child: const Center(
                  child: Icon(Icons.download_for_offline,
                      size: 40, color: Colors.white),
                ),
              ),
            ),
          ),

        // Progress overlay while downloading
        if (_state == _OverlayState.downloading)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
              color: Colors.black.withValues(alpha: 0.45),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    ),
                    if (_progress > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${(_progress * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          ),

        // Cloud badge — top-left — shown when any files exist in Drive
        Positioned(
          top: 6,
          left: 6,
          child: _CloudBadge(
            downloadedCount: _downloadedCount,
            totalCount: _totalCount > 0 ? _totalCount : totalCount,
            state: _state,
          ),
        ),
      ],
    );
  }
}

class _CloudBadge extends StatelessWidget {
  final int downloadedCount;
  final int totalCount;
  final _OverlayState state;

  const _CloudBadge({
    required this.downloadedCount,
    required this.totalCount,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = state == _OverlayState.done
        ? theme.colorScheme.primary
        : Colors.white54;

    final showProgress = state == _OverlayState.partial && totalCount > 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud, size: 12, color: color),
          if (showProgress) ...[
            const SizedBox(width: 3),
            Text(
              '$downloadedCount/$totalCount',
              style: TextStyle(color: color, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }
}

enum _OverlayState { notDownloaded, downloading, partial, done }
