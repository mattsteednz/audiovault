import 'dart:io' show SocketException;

import '../models/audiobook.dart';
import '../models/availability_filter_state.dart';
import '../services/position_service.dart';

/// Pure query/sort/filter helpers for the library screens.
///
/// Extracted from library_screen.dart so they can be unit-tested without any
/// widget scaffolding (see test/screens/library_helpers_test.dart).

/// Returns books from [books] whose title or author contains [query]
/// (case-insensitive). Returns [books] unchanged when [query] is empty.
List<Audiobook> filterBooks(List<Audiobook> books, String query) {
  if (query.isEmpty) return books;
  final q = query.toLowerCase();
  return books.where((b) {
    if (b.title.toLowerCase().contains(q)) return true;
    final author = b.author;
    return author != null && author.toLowerCase().contains(q);
  }).toList();
}

/// Merges [cachedCovers] (book path → cover file path) into [books].
///
/// Only called when enrichment is enabled; pass an empty map to skip.
/// Books that already have embedded artwork are left unchanged.
List<Audiobook> applyCachedCovers(
  List<Audiobook> books,
  Map<String, String> cachedCovers,
) {
  if (cachedCovers.isEmpty) return books;
  return books.map((b) {
    if (b.coverImagePath != null || b.coverImageBytes != null) return b;
    final cached = cachedCovers[b.path];
    return cached != null ? b.copyWith(coverImagePath: cached) : b;
  }).toList();
}

/// Filters [books] to those whose status in [statuses] matches [filter].
/// When [filter] is null, returns [books] unchanged. Books without an entry in
/// [statuses] are treated as [BookStatus.notStarted].
List<Audiobook> applyStatusFilter(
  List<Audiobook> books,
  Map<String, BookStatus> statuses,
  BookStatus? filter,
) {
  if (filter == null) return books;
  return books
      .where((b) => (statuses[b.path] ?? BookStatus.notStarted) == filter)
      .toList();
}

/// Filters [books] by availability.
///
/// - [all]             → returns [books] unchanged.
/// - [availableOffline] → local books + Drive books with non-empty audioFiles.
/// - [driveOnly]       → Drive books with empty audioFiles only.
List<Audiobook> applyAvailabilityFilter(
  List<Audiobook> books,
  AvailabilityFilterState filter,
) {
  return switch (filter) {
    AvailabilityFilterState.all => books,
    AvailabilityFilterState.availableOffline => books.where((b) =>
        b.source == AudiobookSource.local ||
        (b.source == AudiobookSource.drive && b.audioFiles.isNotEmpty),
      ).toList(),
    AvailabilityFilterState.driveOnly => books.where((b) =>
        b.source == AudiobookSource.drive && b.audioFiles.isEmpty,
      ).toList(),
  };
}

/// Sorts [books] by last-played order: books with a position entry come first
/// (newest `updatedAt` first), then unplayed books alphabetically by title.
List<Audiobook> sortByLastPlayed(
  List<Audiobook> books,
  List<BookProgress> positions,
) {
  final played = <String, int>{
    for (final p in positions) p.bookPath: p.updatedAt
  };
  final withHistory = books.where((b) => played.containsKey(b.path)).toList()
    ..sort((a, b) => (played[b.path] ?? 0).compareTo(played[a.path] ?? 0));
  final withoutHistory = books.where((b) => !played.containsKey(b.path)).toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return [...withHistory, ...withoutHistory];
}

/// User-selectable library sort orders.
enum LibrarySortOrder {
  lastPlayed('Last played'),
  titleAsc('Title (A–Z)'),
  authorAsc('Author (A–Z)'),
  dateAdded('Date added'),
  durationDesc('Duration (longest first)');

  const LibrarySortOrder(this.label);
  final String label;

  static LibrarySortOrder fromName(String? name) {
    if (name == null) return LibrarySortOrder.lastPlayed;
    for (final v in LibrarySortOrder.values) {
      if (v.name == name) {
        return v;
      }
    }
    return LibrarySortOrder.lastPlayed;
  }
}

/// Sorts [books] according to [order].
///
/// * `lastPlayed` — see [sortByLastPlayed].
/// * `titleAsc` / `authorAsc` — case-insensitive alphabetical. Books with a
///   missing author sort after any present author.
/// * `dateAdded` — newest first by path mtime when available, falling back
///   to scan order (stable).
/// * `durationDesc` — longest first; books with unknown duration sort last.
List<Audiobook> sortBooks(
  List<Audiobook> books,
  LibrarySortOrder order, {
  List<BookProgress> positions = const [],
  Map<String, int> dateAddedMs = const {},
}) {
  final list = [...books];
  int cmpStr(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

  switch (order) {
    case LibrarySortOrder.lastPlayed:
      return sortByLastPlayed(list, positions);
    case LibrarySortOrder.titleAsc:
      list.sort((a, b) => cmpStr(a.title, b.title));
      return list;
    case LibrarySortOrder.authorAsc:
      list.sort((a, b) {
        final aa = a.author, ba = b.author;
        if (aa == null && ba == null) return cmpStr(a.title, b.title);
        if (aa == null) return 1;
        if (ba == null) return -1;
        final c = cmpStr(aa, ba);
        return c != 0 ? c : cmpStr(a.title, b.title);
      });
      return list;
    case LibrarySortOrder.dateAdded:
      list.sort((a, b) {
        final am = dateAddedMs[a.path] ?? 0;
        final bm = dateAddedMs[b.path] ?? 0;
        if (am != bm) return bm.compareTo(am); // newest first
        return cmpStr(a.title, b.title);
      });
      return list;
    case LibrarySortOrder.durationDesc:
      list.sort((a, b) {
        final ad = a.duration?.inMilliseconds ?? -1;
        final bd = b.duration?.inMilliseconds ?? -1;
        if (ad != bd) return bd.compareTo(ad); // longest first, unknowns last
        return cmpStr(a.title, b.title);
      });
      return list;
  }
}

/// Content to show when the library grid is empty, based on what the user
/// has configured. Pure function consumed by the library empty-state widget.
///
/// - `hasLocalFolder` and `hasDriveConfigured` reflect Settings state.
/// - `showCta` is true when the user has done zero configuration — the empty
///   state should nudge them into Settings.
({String title, String message, bool showCta}) emptyStateContent({
  required bool hasLocalFolder,
  required bool hasDriveConfigured,
}) {
  if (!hasLocalFolder && !hasDriveConfigured) {
    return (
      title: 'Your library is empty',
      message:
          'Add a folder from your device or connect Google Drive to get started.',
      showCta: true,
    );
  }
  if (hasDriveConfigured && !hasLocalFolder) {
    return (
      title: 'No audiobooks on Drive',
      message:
          "We didn't find any audiobooks in the Drive folder you selected. "
          'Check the folder in Settings or add more books.',
      showCta: false,
    );
  }
  // Local folder configured (with or without Drive).
  return (
    title: 'No audiobooks found',
    message: 'Make sure your library folder contains subfolders with audio '
        'files, then pull to refresh.',
    showCta: false,
  );
}

/// Maps a scan-time exception to a user-friendly error message.
/// Permission issues, missing folders, and generic failures each get a
/// distinct phrasing that suggests a next action.
String friendlyScanError(Object error) {
  final s = error.toString().toLowerCase();
  if (s.contains('permission denied') ||
      s.contains('operation not permitted') ||
      s.contains('errno = 13') ||
      s.contains('errno = 1,')) {
    return 'Storage access denied. Grant permission in Settings and try again.';
  }
  if (s.contains('no such file') ||
      s.contains('cannot find the file') ||
      s.contains('cannot find the path') ||
      s.contains('errno = 2') ||
      s.contains('errno = 3,')) {
    return "Library folder can't be found. It may have been moved or deleted — "
        'choose a new folder in Settings.';
  }
  if (error is SocketException ||
      s.contains('network') ||
      s.contains('connection')) {
    return "Couldn't reach Google Drive. Check your network and try again.";
  }
  return "Couldn't scan the library. Try again, or check your folder in Settings.";
}

/// Builds the "no matches" message from whichever filters are active.
/// Seven combinatorial variants keep the copy specific about what to relax.
String noMatchesMessage({
  required String searchQuery,
  required BookStatus? statusFilter,
  required AvailabilityFilterState availabilityFilter,
  required String Function(BookStatus) statusLabel,
}) {
  final hasSearch = searchQuery.isNotEmpty;
  final hasStatus = statusFilter != null;
  final hasAvailability =
      availabilityFilter != AvailabilityFilterState.all;

  final statusText =
      hasStatus ? statusLabel(statusFilter).toLowerCase() : '';
  final availText = hasAvailability ? availabilityFilter.label.toLowerCase() : '';

  if (hasSearch && hasStatus && hasAvailability) {
    return 'No $statusText $availText books match "$searchQuery".';
  }
  if (hasSearch && hasStatus) {
    return 'No $statusText books match "$searchQuery".';
  }
  if (hasSearch && hasAvailability) {
    return 'No $availText books match "$searchQuery".';
  }
  if (hasStatus && hasAvailability) {
    return 'No $statusText $availText books.';
  }
  if (hasStatus) {
    return 'No $statusText books.';
  }
  if (hasAvailability) {
    return 'No $availText books.';
  }
  return 'No results for "$searchQuery".';
}
