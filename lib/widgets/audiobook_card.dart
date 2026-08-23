import 'package:flutter/material.dart';
import '../models/audiobook.dart';
import 'drive_download_overlay.dart';
import 'enrichment_aware_cover.dart';

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
        EnrichmentAwareCover(
          book: book,
          iconSize: 52,
          decodeSize: 512,
        ),
        if (book.isDrmLocked)
          Positioned.fill(
            child: Semantics(
              label: 'DRM protected',
              excludeSemantics: true,
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
          ),
        if (isActive)
          Positioned(
            right: 6,
            bottom: 6,
            child: Semantics(
              label: 'Now playing',
              excludeSemantics: true,
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
            ),
          )
        else if (status == BookStatus.finished)
          Positioned(
            right: 6,
            bottom: 6,
            child: Semantics(
              label: 'Finished',
              excludeSemantics: true,
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
        // Square cover only — title lives on the cover placeholder.
        child: AspectRatio(
          aspectRatio: 1,
          child: coverStack,
        ),
      ),
    );
  }
}

