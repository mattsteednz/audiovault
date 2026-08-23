import 'dart:io';
import 'package:flutter/material.dart';
import '../models/audiobook.dart';

/// Controls how the placeholder renders when no cover art is available.
enum CoverPlaceholderStyle {
  /// Three-line title centred on the colour block (grid cards).
  title,
  /// Single large initial centred on the colour block (list tile thumbnails).
  initial,
}

/// Renders an audiobook's cover art with a placeholder fallback.
///
/// Checks [Audiobook.coverImageBytes] first, then [Audiobook.coverImagePath],
/// then falls back to a themed placeholder.
///
/// When [isEnriching] is true, overlays a small progress indicator on the
/// placeholder so the user knows a cover fetch is in flight.
class BookCover extends StatelessWidget {
  final Audiobook book;
  final double iconSize;
  final bool isEnriching;
  final bool enrichmentFailed;
  final CoverPlaceholderStyle placeholderStyle;

  const BookCover({
    super.key,
    required this.book,
    this.iconSize = 52,
    this.isEnriching = false,
    this.enrichmentFailed = false,
    this.placeholderStyle = CoverPlaceholderStyle.title,
  });

  /// Muted mid-tone palette used for placeholder tiles when no cover art exists.
  /// Works in both light and dark modes — light enough not to overpower a light
  /// UI, dark enough to keep the icon legible.
  static const List<Color> placeholderPalette = [
    Color(0xFF5C7A9E), // muted steel blue
    Color(0xFF7A5C8A), // muted mauve
    Color(0xFF5C7A5C), // muted sage
    Color(0xFF8A7A5C), // muted tan
    Color(0xFF6B8A5C), // muted olive
    Color(0xFF8A5C5C), // muted rose
    Color(0xFF5C8A8A), // muted teal
    Color(0xFF6B6B8A), // muted periwinkle
    Color(0xFF7A6B5C), // muted umber
    Color(0xFF5C6B7A), // muted slate
    Color(0xFF8A6B7A), // muted dusty pink
    Color(0xFF6B7A5C), // muted fern
    Color(0xFF7A5C6B), // muted plum
    Color(0xFF5C7A6B), // muted seafoam
    Color(0xFF8A8A5C), // muted khaki
    Color(0xFF6B5C8A), // muted violet
  ];

  Color _placeholderColor() {
    // Use the book path as the hash source — stable across sort order changes
    // and consistent between the library grid/list and the player screen.
    // Mix with xorshift so books that share a long path prefix (same library
    // folder) still get well-spread colours.
    var h = 0;
    for (final c in book.path.codeUnits) {
      h = h * 31 + c;
    }
    // xorshift finalisation — avalanches the low bits so nearby paths
    // (differing only in the last few characters) land on different colours.
    h ^= h >> 17;
    h ^= h << 13;
    h ^= h >> 7;
    return placeholderPalette[h.abs() % placeholderPalette.length];
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
    final bg = _placeholderColor();
    final textColor = bg.computeLuminance() > 0.35
        ? Colors.black.withValues(alpha: 0.75)
        : Colors.white.withValues(alpha: 0.85);

    final Widget content = switch (placeholderStyle) {
      CoverPlaceholderStyle.title => Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: Text(
              book.title,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ),
      CoverPlaceholderStyle.initial => Center(
          child: Text(
            book.title.isNotEmpty
                ? book.title.trimLeft()[0].toUpperCase()
                : '?',
            style: TextStyle(
              color: textColor,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
    };

    return ColoredBox(
      color: bg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          content,
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
