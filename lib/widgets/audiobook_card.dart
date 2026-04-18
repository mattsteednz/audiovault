import 'package:flutter/material.dart';
import '../locator.dart';
import '../models/audiobook.dart';
import '../services/enrichment_service.dart';
import 'book_cover.dart';
import 'drive_download_overlay.dart';

class AudiobookCard extends StatelessWidget {
  final Audiobook book;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isActive;
  final BookStatus status;

  const AudiobookCard({
    super.key,
    required this.book,
    this.onTap,
    this.onLongPress,
    this.isActive = false,
    this.status = BookStatus.notStarted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget coverStack = Stack(
      fit: StackFit.expand,
      children: [
        _EnrichmentAwareCover(book: book, iconSize: 52),
        if (book.isDrmLocked)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.45),
              child: const Center(
                child: Icon(
                  Icons.lock_rounded,
                  size: 36,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        if (isActive)
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.volume_up_rounded,
                size: 14,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          )
        else if (status == BookStatus.finished)
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_rounded,
                size: 14,
                color: theme.colorScheme.onSecondary,
              ),
            ),
          ),
      ],
    );

    if (book.source == AudiobookSource.drive) {
      coverStack = DriveDownloadOverlay(book: book, child: coverStack);
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: coverStack),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// BookCover wrapper that reflects [EnrichmentService] state so the user can
/// distinguish "fetching a cover right now" from "no cover available".
class _EnrichmentAwareCover extends StatelessWidget {
  final Audiobook book;
  final double iconSize;

  const _EnrichmentAwareCover({required this.book, required this.iconSize});

  @override
  Widget build(BuildContext context) {
    // No enrichment happens for books that already have local cover data.
    if (book.coverImageBytes != null || book.coverImagePath != null) {
      return BookCover(book: book, iconSize: iconSize);
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
            );
          },
        );
      },
    );
  }
}
