import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:kowhai/models/audiobook.dart';
import 'package:kowhai/models/availability_filter_state.dart';
import 'package:kowhai/utils/library_queries.dart';
import 'package:kowhai/services/position_service.dart';
import 'package:kowhai/utils/formatters.dart';

Audiobook _book(String title) =>
    Audiobook(title: title, path: '/library/$title', audioFiles: const []);

BookProgress _progress(String path, int updatedAt) => (
      bookPath: path,
      chapterIndex: 0,
      positionMs: 0,
      globalPositionMs: 0,
      totalDurationMs: 0,
      updatedAt: updatedAt,
    );

void main() {
  _registerPropertyTests();

  group('applyStatusFilter', () {
    final books = [_book('A'), _book('B'), _book('C')];
    final statuses = {
      '/library/A': BookStatus.inProgress,
      '/library/B': BookStatus.finished,
      // C has no entry → treated as notStarted
    };

    test('null filter returns books unchanged', () {
      expect(applyStatusFilter(books, statuses, null), books);
    });

    test('filters to inProgress', () {
      final r = applyStatusFilter(books, statuses, BookStatus.inProgress);
      expect(r.map((b) => b.title), ['A']);
    });

    test('filters to finished', () {
      final r = applyStatusFilter(books, statuses, BookStatus.finished);
      expect(r.map((b) => b.title), ['B']);
    });

    test('books missing from statuses map count as notStarted', () {
      final r = applyStatusFilter(books, statuses, BookStatus.notStarted);
      expect(r.map((b) => b.title), ['C']);
    });

    test('empty statuses + notStarted filter returns all books', () {
      final r = applyStatusFilter(books, {}, BookStatus.notStarted);
      expect(r, books);
    });

    test('empty book list returns empty', () {
      expect(applyStatusFilter([], statuses, BookStatus.inProgress), isEmpty);
    });
  });

  group('sortByLastPlayed', () {
    test('played books come first, newest updatedAt first', () {
      final books = [_book('A'), _book('B'), _book('C')];
      final positions = [
        _progress('/library/A', 100),
        _progress('/library/C', 300),
      ];
      final result = sortByLastPlayed(books, positions);
      expect(result.map((b) => b.title), ['C', 'A', 'B']);
    });

    test('unplayed books are sorted alphabetically (case-insensitive)', () {
      final books = [_book('charlie'), _book('Alpha'), _book('bravo')];
      final result = sortByLastPlayed(books, []);
      expect(result.map((b) => b.title), ['Alpha', 'bravo', 'charlie']);
    });

    test('mixed: played first (by updatedAt desc), then alphabetical unplayed', () {
      final books = [
        _book('Zeta'),
        _book('Alpha'),
        _book('Beta'),
        _book('Gamma'),
      ];
      final positions = [
        _progress('/library/Beta', 100),
        _progress('/library/Zeta', 200),
      ];
      final result = sortByLastPlayed(books, positions);
      expect(result.map((b) => b.title), ['Zeta', 'Beta', 'Alpha', 'Gamma']);
    });

    test('empty books list returns empty', () {
      expect(sortByLastPlayed([], []), isEmpty);
    });

    test('positions for books not in input are ignored', () {
      final books = [_book('A')];
      final positions = [_progress('/library/Ghost', 999)];
      final result = sortByLastPlayed(books, positions);
      expect(result.map((b) => b.title), ['A']);
    });
  });

  group('friendlyScanError', () {
    test('permission-denied messages are caught', () {
      expect(
        friendlyScanError(const FileSystemException(
            'Permission denied', '/storage/emulated/0')),
        contains('Storage access denied'),
      );
      expect(
        friendlyScanError('errno = 13, Permission denied'),
        contains('Storage access denied'),
      );
    });

    test('missing-folder messages are caught', () {
      expect(
        friendlyScanError(
            const FileSystemException('No such file or directory', '/bad')),
        contains("can't be found"),
      );
      expect(
        friendlyScanError('The system cannot find the path specified'),
        contains("can't be found"),
      );
    });

    test('network errors map to Drive-specific copy', () {
      expect(
        friendlyScanError(const SocketException('Failed host lookup')),
        contains("Couldn't reach Google Drive"),
      );
    });

    test('unknown errors get a generic fallback', () {
      expect(
        friendlyScanError(StateError('something weird')),
        contains("Couldn't scan the library"),
      );
    });

    test('never returns raw exception class names', () {
      final result =
          friendlyScanError(const FileSystemException('boom', '/x'));
      expect(result, isNot(contains('FileSystemException')));
    });
  });

  group('emptyStateContent', () {
    test('zero configuration shows the first-run CTA', () {
      final r = emptyStateContent(
          hasLocalFolder: false, hasDriveConfigured: false);
      expect(r.title, 'Your library is empty');
      expect(r.showCta, isTrue);
    });

    test('Drive-only configuration omits the CTA and uses Drive copy', () {
      final r = emptyStateContent(
          hasLocalFolder: false, hasDriveConfigured: true);
      expect(r.title, 'No audiobooks on Drive');
      expect(r.showCta, isFalse);
    });

    test('local folder configured (with or without Drive) uses local copy', () {
      for (final drive in [true, false]) {
        final r = emptyStateContent(
            hasLocalFolder: true, hasDriveConfigured: drive);
        expect(r.title, 'No audiobooks found');
        expect(r.showCta, isFalse);
      }
    });
  });

  group('formatBytes', () {
    test('bytes under 1 KB show as B', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('KB range rounds to whole KB', () {
      expect(formatBytes(1024), '1 KB');
      expect(formatBytes(1024 * 500), '500 KB');
    });

    test('MB range shows one decimal', () {
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(1024 * 1024 * 15 + 1024 * 512), '15.5 MB');
    });

    test('GB range shows two decimals', () {
      expect(formatBytes(1024 * 1024 * 1024), '1.00 GB');
      expect(formatBytes((1024 * 1024 * 1024 * 2.5).round()), '2.50 GB');
    });
  });

  group('LibrarySortOrder.fromName', () {
    test('null falls back to lastPlayed', () {
      expect(LibrarySortOrder.fromName(null), LibrarySortOrder.lastPlayed);
    });
    test('unknown falls back to lastPlayed', () {
      expect(LibrarySortOrder.fromName('nope'), LibrarySortOrder.lastPlayed);
    });
    test('round-trips known names', () {
      for (final v in LibrarySortOrder.values) {
        expect(LibrarySortOrder.fromName(v.name), v);
      }
    });
  });

  group('sortBooks', () {
    Audiobook mk(String title, {String? author, Duration? duration}) =>
        Audiobook(
          title: title,
          author: author,
          duration: duration,
          path: '/library/$title',
          audioFiles: const [],
        );

    test('titleAsc is case-insensitive alphabetical', () {
      final books = [mk('banana'), mk('Apple'), mk('cherry')];
      final r = sortBooks(books, LibrarySortOrder.titleAsc);
      expect(r.map((b) => b.title), ['Apple', 'banana', 'cherry']);
    });

    test('authorAsc groups by author then title, nulls last', () {
      final books = [
        mk('Zed', author: 'Bob'),
        mk('Alpha', author: 'Bob'),
        mk('Orphan'), // null author
        mk('Beta', author: 'Alice'),
      ];
      final r = sortBooks(books, LibrarySortOrder.authorAsc);
      expect(r.map((b) => b.title), ['Beta', 'Alpha', 'Zed', 'Orphan']);
    });

    test('dateAdded sorts newest first, unknown treated as 0', () {
      final books = [mk('A'), mk('B'), mk('C')];
      final r = sortBooks(
        books,
        LibrarySortOrder.dateAdded,
        dateAddedMs: {
          '/library/A': 100,
          '/library/B': 300,
          // C missing → 0, sorts last
        },
      );
      expect(r.map((b) => b.title), ['B', 'A', 'C']);
    });

    test('durationDesc puts longest first, unknowns last', () {
      final books = [
        mk('Short', duration: const Duration(minutes: 30)),
        mk('Unknown'),
        mk('Long', duration: const Duration(hours: 10)),
        mk('Medium', duration: const Duration(hours: 2)),
      ];
      final r = sortBooks(books, LibrarySortOrder.durationDesc);
      expect(r.map((b) => b.title), ['Long', 'Medium', 'Short', 'Unknown']);
    });

    test('lastPlayed delegates to sortByLastPlayed', () {
      final books = [_book('A'), _book('B'), _book('C')];
      final positions = [_progress('/library/B', 200)];
      final r = sortBooks(books, LibrarySortOrder.lastPlayed,
          positions: positions);
      expect(r.map((b) => b.title), ['B', 'A', 'C']);
    });
  });
}

// ---------------------------------------------------------------------------
// Arbitraries for applyAvailabilityFilter property tests
// ---------------------------------------------------------------------------

/// Generates an [Audiobook] with a random [AudiobookSource] and a random
/// number of audio files (0–3), which determines offline availability.
Arbitrary<Audiobook> _audiobookArbitrary() {
  return combine3(
    integer(min: 0, max: 999),          // unique index for path/title
    constantFrom(AudiobookSource.values), // local or drive
    integer(min: 0, max: 3),             // number of audio files
  ).map((t) {
    final (idx, source, fileCount) = t;
    final audioFiles = List.generate(fileCount, (i) => '/audio/$idx/file$i.mp3');
    return Audiobook(
      title: 'Book $idx',
      path: '/library/book_$idx',
      audioFiles: audioFiles,
      source: source,
    );
  });
}

/// Generates a list of 0–10 [Audiobook]s.
Arbitrary<List<Audiobook>> _bookListArbitrary() =>
    list(_audiobookArbitrary(), minLength: 0, maxLength: 10);

/// Generates any [AvailabilityFilterState].
Arbitrary<AvailabilityFilterState> _filterStateArbitrary() =>
    constantFrom(AvailabilityFilterState.values);

/// Generates any nullable [BookStatus] (null = show all).
Arbitrary<BookStatus?> _bookStatusArbitrary() => oneOf([
      constant(null),
      constantFrom(BookStatus.values),
    ]).map((v) => v as BookStatus?);

// ---------------------------------------------------------------------------
// Property tests — applyAvailabilityFilter
// ---------------------------------------------------------------------------

void _propertyTests() {
  // Feature: library-availability-filter, Property 1: all filter is identity
  property(
    'Property 1: all filter is identity — '
    'applyAvailabilityFilter(books, all) returns the same books in the same order',
    () {
      forAll(
        _bookListArbitrary(),
        (books) {
          // **Validates: Requirements 2.1**
          final result = applyAvailabilityFilter(books, AvailabilityFilterState.all);
          expect(result.length, equals(books.length));
          for (var i = 0; i < books.length; i++) {
            expect(result[i], same(books[i]));
          }
        },
        maxExamples: 25,
      );
    },
  );

  // Feature: library-availability-filter, Property 2: availableOffline filter returns only offline-available books
  property(
    'Property 2: availableOffline filter — soundness and completeness',
    () {
      forAll(
        _bookListArbitrary(),
        (books) {
          // **Validates: Requirements 2.2**
          final result = applyAvailabilityFilter(
              books, AvailabilityFilterState.availableOffline);

          // Soundness: every book in the output satisfies the predicate
          for (final b in result) {
            final isOfflineAvailable = b.source == AudiobookSource.local ||
                (b.source == AudiobookSource.drive && b.audioFiles.isNotEmpty);
            expect(isOfflineAvailable, isTrue,
                reason:
                    'Book "${b.title}" (source=${b.source}, audioFiles=${b.audioFiles.length}) '
                    'should not appear in availableOffline output');
          }

          // Completeness: every qualifying input book appears in the output
          final resultPaths = result.map((b) => b.path).toSet();
          for (final b in books) {
            final qualifies = b.source == AudiobookSource.local ||
                (b.source == AudiobookSource.drive && b.audioFiles.isNotEmpty);
            if (qualifies) {
              expect(resultPaths, contains(b.path),
                  reason:
                      'Book "${b.title}" qualifies for availableOffline but is missing from output');
            }
          }
        },
        maxExamples: 25,
      );
    },
  );

  // Feature: library-availability-filter, Property 3: driveOnly filter returns only undownloaded Drive books
  property(
    'Property 3: driveOnly filter — soundness and completeness',
    () {
      forAll(
        _bookListArbitrary(),
        (books) {
          // **Validates: Requirements 2.3**
          final result =
              applyAvailabilityFilter(books, AvailabilityFilterState.driveOnly);

          // Soundness: every book in the output is a Drive book with empty audioFiles
          for (final b in result) {
            expect(b.source, equals(AudiobookSource.drive),
                reason:
                    'Book "${b.title}" (source=${b.source}) should not appear in driveOnly output');
            expect(b.audioFiles, isEmpty,
                reason:
                    'Book "${b.title}" has non-empty audioFiles but appears in driveOnly output');
          }

          // Completeness: every qualifying input book appears in the output
          final resultPaths = result.map((b) => b.path).toSet();
          for (final b in books) {
            final qualifies =
                b.source == AudiobookSource.drive && b.audioFiles.isEmpty;
            if (qualifies) {
              expect(resultPaths, contains(b.path),
                  reason:
                      'Book "${b.title}" qualifies for driveOnly but is missing from output');
            }
          }
        },
        maxExamples: 25,
      );
    },
  );

  // Feature: library-availability-filter, Property 4: availability filter preserves sort order
  property(
    'Property 4: availability filter preserves relative sort order',
    () {
      forAll(
        combine2(_bookListArbitrary(), _filterStateArbitrary()),
        (args) {
          // **Validates: Requirements 2.5**
          final (books, filter) = args;
          final result = applyAvailabilityFilter(books, filter);

          // Walk the result in order; for each book find its position in the
          // input list by scanning forward from where we left off.  If we
          // can always find the next result book further along in the input,
          // relative order is preserved.
          int searchFrom = 0;
          for (final b in result) {
            // Find this exact object instance in the input from searchFrom onward.
            final idx = books.indexWhere((x) => identical(x, b), searchFrom);
            expect(idx, greaterThanOrEqualTo(searchFrom),
                reason:
                    'Book "${b.title}" appears out of order in filtered result');
            searchFrom = idx + 1;
          }
        },
        maxExamples: 25,
      );
    },
  );

  // Feature: library-availability-filter, Property 5: availability filter composes correctly with status filter
  property(
    'Property 5: availability + status filter composition',
    () {
      forAll(
        combine3(
          _bookListArbitrary(),
          _filterStateArbitrary(),
          _bookStatusArbitrary(),
        ),
        (args) {
          // **Validates: Requirements 2.4**
          final (books, availFilter, statusFilter) = args;

          // Deterministic per-book explicit statuses so the status predicate
          // carries real information (a mix of all three values across books).
          final statuses = <String, BookStatus>{
            for (final b in books)
              b.path: BookStatus
                  .values[b.title.length % BookStatus.values.length],
          };

          final availResult = applyAvailabilityFilter(books, availFilter);
          final composed = applyStatusFilter(availResult, statuses, statusFilter);

          // The composed result must be a subset of the availability-only result
          final availPaths = availResult.map((b) => b.path).toSet();
          for (final b in composed) {
            expect(availPaths, contains(b.path),
                reason:
                    'Book "${b.title}" in composed result is not in availability-only result');
          }

          // Every book in the composed result satisfies both predicates independently
          for (final b in composed) {
            // Availability predicate
            final satisfiesAvail = switch (availFilter) {
              AvailabilityFilterState.all => true,
              AvailabilityFilterState.availableOffline =>
                b.source == AudiobookSource.local ||
                    (b.source == AudiobookSource.drive &&
                        b.audioFiles.isNotEmpty),
              AvailabilityFilterState.driveOnly =>
                b.source == AudiobookSource.drive && b.audioFiles.isEmpty,
            };
            expect(satisfiesAvail, isTrue,
                reason:
                    'Book "${b.title}" in composed result does not satisfy availability predicate');

            // Status predicate against the populated statuses map
            if (statusFilter != null) {
              final bookStatus = statuses[b.path] ?? BookStatus.notStarted;
              expect(bookStatus, equals(statusFilter),
                  reason:
                      'Book "${b.title}" in composed result does not satisfy status predicate');
            }
          }

          // Completeness: every book passing BOTH predicates must appear in
          // the composed result.
          final composedPaths = composed.map((b) => b.path).toSet();
          for (final b in availResult) {
            final bookStatus = statuses[b.path] ?? BookStatus.notStarted;
            final passesBoth =
                statusFilter == null || bookStatus == statusFilter;
            if (passesBoth) {
              expect(composedPaths, contains(b.path),
                  reason:
                      'Book "${b.title}" passes both predicates but is missing from the composed result');
            }
          }
        },
        maxExamples: 25,
      );
    },
  );

  // Feature: library-availability-filter, Property 6: pill counts match actual filtered counts
  property(
    'Property 6: pill counts match an independent predicate count',
    () {
      forAll(
        _bookListArbitrary(),
        (books) {
          // **Validates: Requirements 3.2**
          for (final state in AvailabilityFilterState.values) {
            final filtered = applyAvailabilityFilter(books, state);
            // Independent oracle: recompute expected membership with a
            // hand-written predicate rather than calling the same function.
            final expected = books.where((b) {
              return switch (state) {
                AvailabilityFilterState.all => true,
                AvailabilityFilterState.availableOffline =>
                  b.source == AudiobookSource.local ||
                      (b.source == AudiobookSource.drive &&
                          b.audioFiles.isNotEmpty),
                AvailabilityFilterState.driveOnly =>
                  b.source == AudiobookSource.drive && b.audioFiles.isEmpty,
              };
            }).length;
            expect(filtered.length, expected,
                reason:
                    'Pill count for $state should match the independent predicate count');
          }
        },
        maxExamples: 25,
      );
    },
  );

  // Former Property 7 ("drive-book pill visibility") was a tautology — both
  // sides of its assertion were the same expression. Deleted; pill visibility
  // itself lives in widget code and is covered by manual smoke checks.
}

// Register property tests inside the main test suite
void _registerPropertyTests() {
  group('applyAvailabilityFilter — property tests', _propertyTests);
}
