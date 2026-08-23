import 'package:flutter_test/flutter_test.dart';
import 'package:kowhai/models/audiobook.dart';
import 'package:kowhai/utils/library_queries.dart';

Audiobook _book(String title, {String? coverPath}) => Audiobook(
      title: title,
      path: '/library/$title',
      audioFiles: const [],
      coverImagePath: coverPath,
    );

void main() {
  group('applyCachedCovers', () {
    test('empty cache (or enrichment disabled) returns books unchanged', () {
      final books = [_book('Book A'), _book('Book B')];
      // Both the "no cache entries" and "enrichment disabled" cases pass an
      // empty map, so no cached covers should be applied.
      final result = applyCachedCovers(books, {});
      expect(result, same(books));
      expect(result.every((b) => b.coverImagePath == null), isTrue);
    });

    test('applies cached cover to book without any artwork', () {
      final books = [_book('Book A')];
      final cache = {'/library/Book A': '/cache/cover_a.jpg'};
      final result = applyCachedCovers(books, cache);
      expect(result.first.coverImagePath, '/cache/cover_a.jpg');
    });

    test('does not override existing embedded coverImagePath', () {
      final books = [_book('Book A', coverPath: '/embedded/cover.jpg')];
      final cache = {'/library/Book A': '/cache/cover_a.jpg'};
      final result = applyCachedCovers(books, cache);
      expect(result.first.coverImagePath, '/embedded/cover.jpg');
    });

    test('leaves books with no cache entry unchanged', () {
      final books = [_book('Book A'), _book('Book B')];
      final cache = {'/library/Book B': '/cache/cover_b.jpg'};
      final result = applyCachedCovers(books, cache);
      expect(result[0].coverImagePath, isNull); // Book A unchanged
      expect(result[1].coverImagePath, '/cache/cover_b.jpg');
    });

    test('handles empty book list gracefully', () {
      expect(applyCachedCovers([], {'/x': '/y'}), isEmpty);
    });

    test('applies covers to multiple books in one pass', () {
      final books = [_book('A'), _book('B'), _book('C')];
      final cache = {
        '/library/A': '/cache/a.jpg',
        '/library/C': '/cache/c.jpg',
      };
      final result = applyCachedCovers(books, cache);
      expect(result[0].coverImagePath, '/cache/a.jpg');
      expect(result[1].coverImagePath, isNull); // B has no cache entry
      expect(result[2].coverImagePath, '/cache/c.jpg');
    });
  });
}
