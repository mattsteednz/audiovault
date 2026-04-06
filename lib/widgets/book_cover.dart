import 'dart:io';
import 'package:flutter/material.dart';
import '../models/audiobook.dart';

/// Renders an audiobook's cover art with a placeholder fallback.
///
/// Checks [Audiobook.coverImageBytes] first, then [Audiobook.coverImagePath],
/// then falls back to a themed placeholder icon.
class BookCover extends StatelessWidget {
  final Audiobook book;
  final double iconSize;

  const BookCover({
    super.key,
    required this.book,
    this.iconSize = 52,
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

  Widget _placeholder(ThemeData theme) => ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.menu_book_rounded,
            size: iconSize,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
}
