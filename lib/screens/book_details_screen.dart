import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../locator.dart';
import '../models/audiobook.dart';
import '../services/drive_book_repository.dart';
import '../services/drive_download_manager.dart';
import '../services/drive_library_service.dart';
import '../widgets/book_cover.dart';
import 'player_screen.dart';

class BookDetailsScreen extends StatelessWidget {
  final Audiobook book;

  const BookDetailsScreen({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            foregroundColor: Colors.white,
            backgroundColor: Theme.of(context).colorScheme.surface,
            flexibleSpace: FlexibleSpaceBar(
              background: _CoverBackground(book: book),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: _BookContent(book: book),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverBackground extends StatelessWidget {
  final Audiobook book;

  const _CoverBackground({required this.book});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        BookCover(book: book, iconSize: 80),
        // Gradient fade at bottom so AppBar back button stays legible
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.5, 1.0],
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.6),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BookContent extends StatelessWidget {
  final Audiobook book;

  const _BookContent({required this.book});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          book.title,
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (book.author != null) ...[
          const SizedBox(height: 4),
          Text(
            'By ${book.author}',
            style: theme.textTheme.bodyLarge,
          ),
        ],
        if (book.narrator != null) ...[
          const SizedBox(height: 2),
          Text(
            'Read by ${book.narrator}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
        if (book.duration != null) ...[
          const SizedBox(height: 4),
          Text(
            _formatDuration(book.duration!),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
        const SizedBox(height: 24),
        _ActionButtons(book: book),
        if (book.description != null) ...[
          const SizedBox(height: 24),
          _DescriptionSection(description: book.description!),
        ],
        const SizedBox(height: 24),
        _MetadataSection(book: book),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

class _ActionButtons extends StatefulWidget {
  final Audiobook book;

  const _ActionButtons({required this.book});

  @override
  State<_ActionButtons> createState() => _ActionButtonsState();
}

class _ActionButtonsState extends State<_ActionButtons> {
  StreamSubscription<DriveDownloadEvent>? _sub;
  bool _isDownloading = false;
  int _totalBookBytes = 0;
  int _completedBytes = 0;
  int _currentFileBytes = 0;
  int _downloadedCount = 0;
  int _totalCount = 0;

  double get _progress {
    if (_totalBookBytes <= 0) return 0;
    return ((_completedBytes + _currentFileBytes) / _totalBookBytes)
        .clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    if (widget.book.source == AudiobookSource.drive) {
      _initDownloadState();
      _sub = locator<DriveDownloadManager>()
          .downloadEvents
          .where((e) =>
              e.folderId == widget.book.driveMetadata!.folderId &&
              e.fileIndex != null)
          .listen(_onEvent);
    }
  }

  Future<void> _initDownloadState() async {
    final folderId = widget.book.driveMetadata!.folderId;
    final files =
        await locator<DriveBookRepository>().getFilesForBook(folderId);
    if (!mounted) return;
    final done =
        files.where((f) => f.downloadState == DriveDownloadState.done).length;
    setState(() {
      _totalCount = files.length;
      _downloadedCount = done;
      _totalBookBytes = files.fold<int>(0, (s, f) => s + f.sizeBytes);
      _completedBytes = files
          .where((f) => f.downloadState == DriveDownloadState.done)
          .fold<int>(0, (s, f) => s + f.sizeBytes);
      _isDownloading =
          files.any((f) => f.downloadState == DriveDownloadState.downloading);
    });
  }

  void _onEvent(DriveDownloadEvent event) {
    if (!mounted) return;
    setState(() {
      if (event.state == DriveDownloadState.downloading) {
        _isDownloading = true;
        _currentFileBytes = event.bytesDownloaded ?? 0;
      } else if (event.state == DriveDownloadState.done) {
        _completedBytes += event.fileSizeBytes ?? 0;
        _currentFileBytes = 0;
        _downloadedCount++;
        if (_downloadedCount >= _totalCount) _isDownloading = false;
      } else if (event.state == DriveDownloadState.error) {
        _currentFileBytes = 0;
        // Keep _isDownloading; retry will fire a new downloading event.
        // After all retries fail no more events come and it stays false.
        _isDownloading = false;
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _cancelAndRemove(BuildContext context) async {
    final theme = Theme.of(context);
    final title =
        _isDownloading ? 'Cancel download?' : 'Remove from device?';
    final body = _isDownloading
        ? 'The download will be stopped and any partially downloaded '
            'files for "${widget.book.title}" will be deleted.'
        : 'Downloaded files for "${widget.book.title}" will be deleted. '
            'The book will remain in your Google Drive.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              _isDownloading ? 'Stop & remove' : 'Remove',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final folderId = widget.book.driveMetadata!.folderId;
    final dlManager = locator<DriveDownloadManager>();
    final driveLib = locator<DriveLibraryService>();
    await dlManager.cancelDownload(folderId);
    await driveLib.undownloadBook(folderId);
    if (context.mounted) Navigator.pop(context, folderId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDrive = widget.book.source == AudiobookSource.drive;
    final downloaded = widget.book.audioFiles.length;
    final total = widget.book.driveMetadata?.totalFileCount ?? 0;
    final fullyDownloaded = isDrive && total > 0 && downloaded >= total;
    final hasDownloaded = isDrive && (downloaded > 0 || _isDownloading);
    final notDownloaded = isDrive && !fullyDownloaded && !_isDownloading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (_) => PlayerScreen(book: widget.book)),
            );
          },
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Start listening'),
        ),
        if (_isDownloading) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: null, // disabled
            icon: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                value: _progress > 0 ? _progress : null,
                strokeWidth: 2,
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
            ),
            label: Text(_progress > 0
                ? 'Downloading — ${(_progress * 100).toStringAsFixed(0)}%'
                : 'Downloading…'),
          ),
        ] else if (notDownloaded) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              locator<DriveLibraryService>()
                  .startDownload(widget.book.driveMetadata!.folderId);
              setState(() => _isDownloading = true);
            },
            icon: const Icon(Icons.download_rounded),
            label: const Text('Download to device'),
          ),
        ],
        if (hasDownloaded) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(
                  color: theme.colorScheme.error.withValues(alpha: 0.5)),
            ),
            onPressed: () => _cancelAndRemove(context),
            icon: Icon(_isDownloading
                ? Icons.cancel_outlined
                : Icons.delete_outline_rounded),
            label: Text(_isDownloading ? 'Stop & remove' : 'Remove from device'),
          ),
        ],
      ],
    );
  }
}

class _DescriptionSection extends StatefulWidget {
  final String description;

  const _DescriptionSection({required this.description});

  @override
  State<_DescriptionSection> createState() => _DescriptionSectionState();
}

class _DescriptionSectionState extends State<_DescriptionSection> {
  bool _expanded = false;

  String get _preview {
    final newlineIdx = widget.description.indexOf('\n\n');
    if (newlineIdx > 0 && newlineIdx <= 400) {
      return widget.description.substring(0, newlineIdx);
    }
    if (widget.description.length <= 300) return widget.description;
    return '${widget.description.substring(0, 300)}…';
  }

  bool get _needsExpansion => _preview != widget.description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Summary',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _expanded ? widget.description : _preview,
          style: theme.textTheme.bodyMedium,
        ),
        if (_needsExpansion) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded ? 'Read less' : 'Read more',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MetadataSection extends StatelessWidget {
  final Audiobook book;

  const _MetadataSection({required this.book});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <_MetadataRow>[
      _MetadataRow('Source', _sourceLabel(book)),
      if (book.releaseDate != null)
        _MetadataRow('Released', book.releaseDate!),
      if (book.language != null)
        _MetadataRow('Language', book.language!),
      if (book.publisher != null)
        _MetadataRow('Publisher', book.publisher!),
    ];

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Details',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        ...rows.map((r) => _MetadataRowWidget(row: r)),
      ],
    );
  }

  String _sourceLabel(Audiobook b) {
    if (b.source == AudiobookSource.local) {
      final ext = b.audioFiles.isNotEmpty
          ? p.extension(b.audioFiles.first).toUpperCase().replaceFirst('.', '')
          : 'Unknown';
      return 'On device ($ext)';
    }
    final total = b.driveMetadata?.totalFileCount ?? 0;
    final dl = b.audioFiles.length;
    if (dl == 0) return 'Google Drive (Not downloaded)';
    if (dl >= total) return 'Google Drive (Downloaded)';
    return 'Google Drive ($dl/$total files)';
  }
}

class _MetadataRow {
  final String label;
  final String value;

  const _MetadataRow(this.label, this.value);
}

class _MetadataRowWidget extends StatelessWidget {
  final _MetadataRow row;

  const _MetadataRowWidget({required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              row.label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
          Expanded(
            child: Text(
              row.value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
