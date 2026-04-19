import 'package:flutter/material.dart';
import '../locator.dart';
import '../models/audiobook.dart';
import '../services/enrichment_service.dart';
import 'book_cover.dart';
import 'drive_download_overlay.dart';

class AudiobookListTile extends StatelessWidget {
  final Audiobook book;
  final VoidCallback? onTap;
  final VoidCallback? onDetailsPressed;
  final bool isActive;
  final BookStatus status;
  final int? placeholderIndex;

  const AudiobookListTile({
    super.key,
    required this.book,
    this.onTap,
    this.onDetailsPressed,
    this.isActive = false,
    this.status = BookStatus.notStarted,
    this.placeholderIndex,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget cover = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 56,
        height: 56,
        child: book.source == AudiobookSource.drive
            ? DriveDownloadOverlay(
                book: book,
                iconSize: 24,
                indicatorSize: 24,
                child: _EnrichmentAwareCover(
                  book: book,
                  iconSize: 28,
                  placeholderIndex: placeholderIndex,
                ),
              )
            : _EnrichmentAwareCover(
                book: book,
                iconSize: 28,
                placeholderIndex: placeholderIndex,
              ),
      ),
    );

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Stack(
        children: [
          cover,
          if (isActive)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.volume_up_rounded,
                  size: 12,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ),
        ],
      ),
      title: Text(
        book.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (book.author != null)
            Text(
              book.author!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          if (book.duration != null)
            Text(
              _formatDuration(book.duration!),
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (book.isDrmLocked)
            Icon(Icons.lock_rounded,
                size: 20,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'details',
                child: ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('Book details'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'details') onDetailsPressed?.call();
            },
          ),
        ],
      ),
      isThreeLine: book.author != null,
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

/// BookCover wrapper that reflects [EnrichmentService] state so the user can
/// distinguish "fetching a cover right now" from "no cover available".
class _EnrichmentAwareCover extends StatelessWidget {
  final Audiobook book;
  final double iconSize;
  final int? placeholderIndex;

  const _EnrichmentAwareCover({
    required this.book,
    required this.iconSize,
    this.placeholderIndex,
  });

  @override
  Widget build(BuildContext context) {
    if (book.coverImageBytes != null || book.coverImagePath != null) {
      return BookCover(
        book: book,
        iconSize: iconSize,
        placeholderIndex: placeholderIndex,
      );
    }
    final service = locator<EnrichmentService>();
    return ValueListenableBuilder<Set<String>>(
      valueListenable: service.enrichingPaths,
      builder: (_, enriching, __) {
        return ValueListenableBuilder<Set<String>>(
          valueListenable: service.failedPaths,
          builder: (_, failed, __) {
            return BookCover(
              book: book,
              iconSize: iconSize,
              isEnriching: enriching.contains(book.path),
              enrichmentFailed: failed.contains(book.path),
              placeholderIndex: placeholderIndex,
            );
          },
        );
      },
    );
  }
}
