import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../locator.dart';
import '../models/audiobook.dart';
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

class _ActionButtons extends StatelessWidget {
  final Audiobook book;

  const _ActionButtons({required this.book});

  @override
  Widget build(BuildContext context) {
    final isDrive = book.source == AudiobookSource.drive;
    final downloaded = book.audioFiles.length;
    final total = book.driveMetadata?.totalFileCount ?? 0;
    final fullyDownloaded = isDrive && total > 0 && downloaded >= total;
    final hasDownloaded = isDrive && downloaded > 0;
    final notDownloaded = isDrive && !fullyDownloaded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => PlayerScreen(book: book)),
            );
          },
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Start listening'),
        ),
        if (notDownloaded) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              locator<DriveLibraryService>()
                  .startDownload(book.driveMetadata!.folderId);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.download_rounded),
            label: const Text('Download to device'),
          ),
        ],
        if (hasDownloaded) ...[
          const SizedBox(height: 8),
          _RemoveButton(book: book),
        ],
      ],
    );
  }
}

class _RemoveButton extends StatelessWidget {
  final Audiobook book;

  const _RemoveButton({required this.book});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.colorScheme.error,
        side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
      ),
      onPressed: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Remove from device?'),
            content: Text(
              'Downloaded files for "${book.title}" will be deleted. '
              'The book will remain in your Google Drive.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Remove',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          final folderId = book.driveMetadata!.folderId;
          await locator<DriveLibraryService>().undownloadBook(folderId);
          if (context.mounted) Navigator.pop(context, folderId);
        }
      },
      icon: const Icon(Icons.delete_outline_rounded),
      label: const Text('Remove from device'),
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
