import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault/models/audiobook.dart';
import 'package:audiovault/screens/library_screen.dart';
import 'package:audiovault/services/position_service.dart';

Audiobook _book(String title) =>
    Audiobook(title: title, path: '/library/$title', audioFiles: const []);

BookProgress _progress(String path, int updatedAt) => (
      bookPath: path,
      globalPositionMs: 0,
      totalDurationMs: 0,
      updatedAt: updatedAt,
    );

void main() {
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
}
