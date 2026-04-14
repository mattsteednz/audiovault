import 'package:flutter/material.dart';
import '../models/audiobook.dart';
import 'book_cover.dart';
import 'drive_download_overlay.dart';

class AudiobookListTile extends StatelessWidget {
  final Audiobook book;
  final VoidCallback? onTap;
  final VoidCallback? onDetailsPressed;
  final bool isActive;
  final BookStatus status;

  const AudiobookListTile({
    super.key,
    required this.book,
    this.onTap,
    this.onDetailsPressed,
    this.isActive = false,
    this.status = BookStatus.notStarted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final coverWidget = Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(width: 56, height: 56, child: BookCover(book: book, iconSize: 28)),
        ),
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
    );

    final leading = book.source == AudiobookSource.drive
        ? DriveDownloadOverlay(book: book, child: coverWidget, iconSize: 24, indicatorSize: 24)
        : coverWidget;

    final tile = ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: leading,
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
          if (status == BookStatus.finished)
            Icon(Icons.check_circle_rounded,
                size: 20, color: theme.colorScheme.secondary),
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

    return tile;
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

}
