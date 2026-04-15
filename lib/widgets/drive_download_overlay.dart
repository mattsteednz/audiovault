import 'dart:async';
import 'package:flutter/material.dart';

import '../locator.dart';
import '../models/audiobook.dart';
import '../services/drive_book_repository.dart';
import '../services/drive_download_manager.dart';

/// Wraps a book cover with Drive-specific overlays:
/// - Grey tint + download icon when not downloaded
/// - Progress indicator when downloading (overall book progress)
/// - Cloud badge when downloaded
class DriveDownloadOverlay extends StatefulWidget {
  final Audiobook book;
  final Widget child;
  final double iconSize;
  final double indicatorSize;

  const DriveDownloadOverlay({
    super.key,
    required this.book,
    required this.child,
    this.iconSize = 40,
    this.indicatorSize = 40,
  });

  @override
  State<DriveDownloadOverlay> createState() => _DriveDownloadOverlayState();
}

class _DriveDownloadOverlayState extends State<DriveDownloadOverlay> {
  late final DriveDownloadManager _dlManager;
  late final DriveBookRepository _repo;
  StreamSubscription<DriveDownloadEvent>? _sub;

  _OverlayState _state = _OverlayState.notDownloaded;
  int _downloadedCount = 0;
  int _totalCount = 0;

  // Byte-level tracking for aggregate progress
  int _totalBookBytes = 0;
  int _completedBytes = 0;
  int _currentFileBytes = 0;

  double get _overallProgress {
    if (_totalBookBytes <= 0) return 0;
    return ((_completedBytes + _currentFileBytes) / _totalBookBytes).clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    _dlManager = locator<DriveDownloadManager>();
    _repo = locator<DriveBookRepository>();
    _initState();
    _sub = _dlManager.downloadEvents
        .where((e) => e.folderId == widget.book.driveMetadata!.folderId)
        .listen(_onEvent);
  }

  @override
  void didUpdateWidget(DriveDownloadOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.driveMetadata?.folderId !=
        widget.book.driveMetadata?.folderId) {
      _sub?.cancel();
      _sub = _dlManager.downloadEvents
          .where((e) => e.folderId == widget.book.driveMetadata!.folderId)
          .listen(_onEvent);
      _initState();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
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
      _totalBookBytes = files.fold<int>(0, (sum, f) => sum + f.sizeBytes);
      _completedBytes = files
          .where((f) => f.downloadState == DriveDownloadState.done)
          .fold<int>(0, (sum, f) => sum + f.sizeBytes);

      if (total == 0 || downloaded == 0) {
        _state = anyDownloading ? _OverlayState.downloading : _OverlayState.notDownloaded;
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
        _currentFileBytes = event.bytesDownloaded ?? 0;
      } else if (event.state == DriveDownloadState.done) {
        _completedBytes += event.fileSizeBytes ?? 0;
        _currentFileBytes = 0;
        _downloadedCount++;
        if (_downloadedCount >= _totalCount) {
          _state = _OverlayState.done;
        }
      } else if (event.state == DriveDownloadState.error) {
        _currentFileBytes = 0;
        _state = _downloadedCount > 0
            ? _OverlayState.partial
            : _OverlayState.notDownloaded;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = _overallProgress;

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
                child: Center(
                  child: Icon(Icons.download_for_offline,
                      size: widget.iconSize, color: Colors.white),
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
                        width: widget.indicatorSize,
                        height: widget.indicatorSize,
                        child: CircularProgressIndicator(
                          value: progress > 0 ? progress : null,
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      ),
                      if (progress > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${(progress * 100).toStringAsFixed(0)}%',
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

        // Cloud badge — top-left
        Positioned(
          top: 4,
          left: 4,
          child: _CloudBadge(state: _state),
        ),
      ],
    );
  }
}

class _CloudBadge extends StatelessWidget {
  final _OverlayState state;

  const _CloudBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = state == _OverlayState.done
        ? theme.colorScheme.primary
        : Colors.white54;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.cloud, size: 12, color: color),
    );
  }
}

enum _OverlayState { notDownloaded, downloading, partial, done }
