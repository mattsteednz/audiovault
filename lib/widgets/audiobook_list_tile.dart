import 'package:flutter/material.dart';
import '../models/audiobook.dart';
import 'book_cover.dart';
import 'drive_download_overlay.dart';

class AudiobookListTile extends StatelessWidget {
  final Audiobook book;
  final VoidCallback? onTap;
  final bool isActive;

  const AudiobookListTile({
    super.key,
    required this.book,
    this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tile = ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Stack(
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
      trailing: book.isDrmLocked
          ? Icon(Icons.lock_rounded,
              size: 20, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))
          : null,
      isThreeLine: book.author != null,
    );

    if (book.source == AudiobookSource.drive) {
      return ClipRect(child: DriveDownloadOverlay(book: book, child: tile));
    }
    return tile;
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

}
