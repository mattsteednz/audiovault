import 'dart:io';
import 'package:flutter/material.dart';
import '../models/audiobook.dart';

class AudiobookCard extends StatelessWidget {
  final Audiobook book;
  final VoidCallback? onTap;
  final bool isActive;

  const AudiobookCard({
    super.key,
    required this.book,
    this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _cover(theme),
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
                    ),
                ],
              ),
            ),
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

  Widget _cover(ThemeData theme) {
    if (book.coverImageBytes != null) {
      return Image.memory(
        book.coverImageBytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(theme),
      );
    }
    if (book.coverImagePath != null) {
      return Image.file(
        File(book.coverImagePath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(theme),
      );
    }
    return _placeholder(theme);
  }

  Widget _placeholder(ThemeData theme) {
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.menu_book_rounded,
          size: 52,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

}
