import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault/models/audiobook.dart';
import 'package:audiovault/screens/library_screen.dart';

Audiobook _book(String title, {String? author}) => Audiobook(
      title: title,
      author: author,
      path: '/dummy/$title',
      audioFiles: const [],
    );

void main() {
  final books = [
    _book('The Secret Garden', author: 'Frances Hodgson Burnett'),
    _book('Dune', author: 'Frank Herbert'),
    _book('Foundation', author: 'Isaac Asimov'),
    _book('The Hobbit', author: 'J.R.R. Tolkien'),
    _book('No Author'),
  ];

  group('filterBooks', () {
    test('empty query returns all books', () {
      expect(filterBooks(books, ''), books);
    });

    test('matches by title (case-insensitive)', () {
      final result = filterBooks(books, 'dune');
      expect(result.map((b) => b.title), ['Dune']);
    });

    test('matches partial title', () {
      final result = filterBooks(books, 'the');
      expect(result.map((b) => b.title),
          containsAll(['The Secret Garden', 'The Hobbit']));
      expect(result.length, 2);
    });

    test('matches by author (case-insensitive)', () {
      final result = filterBooks(books, 'asimov');
      expect(result.map((b) => b.title), ['Foundation']);
    });

    test('matches partial author name', () {
      final result = filterBooks(books, 'frank');
      expect(result.map((b) => b.title), ['Dune']);
    });

    test('matches across both title and author fields', () {
      // 'frances' matches author of Secret Garden; 'hobbit' matches title
      final byAuthor = filterBooks(books, 'frances');
      expect(byAuthor.map((b) => b.title), ['The Secret Garden']);

      final byTitle = filterBooks(books, 'hobbit');
      expect(byTitle.map((b) => b.title), ['The Hobbit']);
    });

    test('query matching both title and author returns book once', () {
      // 'foundation' matches the title; only one result expected
      final result = filterBooks(books, 'foundation');
      expect(result.length, 1);
    });

    test('no match returns empty list', () {
      expect(filterBooks(books, 'zzznomatch'), isEmpty);
    });

    test('books without author are not excluded on title match', () {
      final result = filterBooks(books, 'no author');
      expect(result.map((b) => b.title), ['No Author']);
    });

    test('books without author do not crash on author query', () {
      // "No Author" book has null author; querying an author string should
      // not throw and should simply not match it.
      expect(() => filterBooks(books, 'tolkien'), returnsNormally);
      final result = filterBooks(books, 'tolkien');
      expect(result.every((b) => b.author != null), isTrue);
    });

    test('empty book list returns empty list', () {
      expect(filterBooks([], 'dune'), isEmpty);
    });
  });

  group('search + status filter AND-composition', () {
    final books = [
      _book('Dune', author: 'Frank Herbert'),
      _book('Dune Messiah', author: 'Frank Herbert'),
      _book('Foundation', author: 'Isaac Asimov'),
      _book('The Hobbit', author: 'J.R.R. Tolkien'),
    ];
    final statuses = {
      '/dummy/Dune': BookStatus.inProgress,
      '/dummy/Dune Messiah': BookStatus.finished,
      '/dummy/Foundation': BookStatus.inProgress,
      // 'The Hobbit' not present → treated as notStarted
    };

    test('search + status filter narrows to intersection', () {
      final bySearch = filterBooks(books, 'dune');
      final combined = applyStatusFilter(bySearch, statuses, BookStatus.inProgress);
      expect(combined.map((b) => b.title), ['Dune']);
    });

    test('search matches multiple but status filter narrows further', () {
      final bySearch = filterBooks(books, 'dune');
      expect(bySearch.length, 2); // "Dune" and "Dune Messiah"
      final finished = applyStatusFilter(bySearch, statuses, BookStatus.finished);
      expect(finished.map((b) => b.title), ['Dune Messiah']);
    });

    test('search with no status match returns empty', () {
      final bySearch = filterBooks(books, 'hobbit');
      final combined = applyStatusFilter(bySearch, statuses, BookStatus.inProgress);
      expect(combined, isEmpty);
    });

    test('empty search with status filter behaves as filter only', () {
      final bySearch = filterBooks(books, '');
      final combined = applyStatusFilter(bySearch, statuses, BookStatus.inProgress);
      expect(combined.map((b) => b.title), containsAll(['Dune', 'Foundation']));
      expect(combined.length, 2);
    });

    test('null status filter with search behaves as search only', () {
      final bySearch = filterBooks(books, 'dune');
      final combined = applyStatusFilter(bySearch, statuses, null);
      expect(combined.length, 2);
    });
  });
}
