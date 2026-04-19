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

  /// Optional render index (position in the current grid/list). When provided,
  /// the placeholder fallback picks a colour from [placeholderPalette] by
  /// `index % palette.length` so adjacent tiles never collide. When null,
  /// falls back to a hash of the book title (used outside list contexts, e.g.
  /// the mini player).
  final int? placeholderIndex;

  const BookCover({
    super.key,
    required this.book,
    this.iconSize = 52,
    this.isEnriching = false,
    this.enrichmentFailed = false,
    this.placeholderIndex,
  });

  /// Jewel-tone palette used for placeholder tiles when no cover art exists.
  /// Used in both light and dark modes.
  static const List<Color> placeholderPalette = [
    Color(0xFF1A3A5C), // deep navy
    Color(0xFF2A1A3A), // deep plum
    Color(0xFF1A2A1A), // dark forest
    Color(0xFF3A2A1A), // dark amber
    Color(0xFF2A3A1A), // dark moss
    Color(0xFF3A1A1A), // dark crimson
    Color(0xFF1A3A3A), // dark teal
    Color(0xFF2A2A3A), // dark slate
  ];

  Color _placeholderColor() {
    final idx = placeholderIndex;
    if (idx != null) {
      return placeholderPalette[idx.abs() % placeholderPalette.length];
    }
    final hash = book.title.codeUnits.fold(0, (h, c) => h * 31 + c);
    return placeholderPalette[hash.abs() % placeholderPalette.length];
  }

  @override
  Widget build(BuildContext context) {
    if (book.coverImageBytes != null) {
      return Image.memory(
        book.coverImageBytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    if (book.coverImagePath != null) {
      return Image.file(
        File(book.coverImagePath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    final showFailedIcon = enrichmentFailed && !isEnriching;
    final bg = _placeholderColor();
    return ColoredBox(
      color: bg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showFailedIcon)
            Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                size: iconSize,
                color: Colors.white.withValues(alpha: 0.55),
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
                    Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
