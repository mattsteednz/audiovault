import 'package:flutter/material.dart';
import '../locator.dart';
import '../models/audiobook.dart';
import '../services/enrichment_service.dart';
import 'book_cover.dart';

/// BookCover wrapper that reflects [EnrichmentService] state so the user can
/// distinguish "fetching a cover right now" from "no cover available".
class EnrichmentAwareCover extends StatelessWidget {
  final Audiobook book;
  final double iconSize;
  final CoverPlaceholderStyle placeholderStyle;

  /// Decode target (logical px) forwarded to [BookCover]; see its doc.
  final double decodeSize;

  const EnrichmentAwareCover({
    super.key,
    required this.book,
    required this.iconSize,
    this.placeholderStyle = CoverPlaceholderStyle.title,
    this.decodeSize = 256,
  });

  @override
  Widget build(BuildContext context) {
    // No enrichment happens for books that already have local cover data.
    if (book.coverImageBytes != null || book.coverImagePath != null) {
      return BookCover(
        book: book,
        iconSize: iconSize,
        placeholderStyle: placeholderStyle,
        decodeSize: decodeSize,
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
              placeholderStyle: placeholderStyle,
              decodeSize: decodeSize,
            );
          },
        );
      },
    );
  }
}
