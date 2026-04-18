import 'dart:io';
import 'package:flutter/material.dart';
import '../models/audiobook.dart';

/// Renders an audiobook's cover art with a placeholder fallback.
///
/// Checks [Audiobook.coverImageBytes] first, then [Audiobook.coverImagePath],
/// then falls back to a themed placeholder icon.
///
/// When [isEnriching] is true, overlays a small progress indicator on the
/// placeholder so the user knows a cover fetch is in flight. When
/// [enrichmentFailed] is true and no local art exists, renders a distinct
/// "no cover available" icon instead of the default placeholder.
class BookCover extends StatelessWidget {
  final Audiobook book;
  final double iconSize;
  final bool isEnriching;
  final bool enrichmentFailed;

  const BookCover({
    super.key,
    required this.book,
    this.iconSize = 52,
    this.isEnriching = false,
    this.enrichmentFailed = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
    final iconData = enrichmentFailed && !isEnriching
        ? Icons.image_not_supported_outlined
        : Icons.menu_book_rounded;
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Icon(
              iconData,
              size: iconSize,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (isEnriching)
            Positioned(
              right: 6,
              bottom: 6,
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
