import 'dart:async';
import 'dart:io' show File, SocketException;
import 'package:audio_service/audio_service.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../models/audiobook.dart';
import '../models/availability_filter_state.dart';
import '../services/audio_handler.dart';
import '../services/drive_book_repository.dart';
import '../services/drive_download_manager.dart';
import '../services/drive_library_service.dart';
import '../services/drive_service.dart';
import '../utils/formatters.dart';
import '../services/enrichment_service.dart';
import '../services/position_service.dart';
import '../services/preferences_service.dart';
import '../services/scanner_service.dart';
import '../widgets/audio_handler_scope.dart';
import '../widgets/audiobook_card.dart';
import '../widgets/audiobook_list_tile.dart';
import '../widgets/library_overflow_menu.dart';
import '../widgets/mini_player.dart';
import '../widgets/sleep_timer_indicator.dart';
import 'book_details_screen.dart';
import 'history_screen.dart';
import 'player_screen.dart';
import 'settings_screen.dart';
import '../locator.dart';
import '../utils/drive_download_sheet.dart';

enum _ViewMode { grid, list }

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

/// Merges [cachedCovers] (path → cover file path) into [books].
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
      if (v.name == name) return v;
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

class LibraryScreen extends StatefulWidget {
  /// When true, forces a Drive sync on first load regardless of the
  /// refresh-on-startup preference. Used by onboarding after Drive setup
  /// so new users see their books immediately without a manual rescan.
  final bool initialSyncDrive;
  const LibraryScreen({super.key, this.initialSyncDrive = false});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Audiobook>? _books;       // sorted display order
  List<Audiobook>? _rawBooks;    // unsorted, straight from scanner
  List<Audiobook> _driveBooks = []; // Drive books (unsorted)
  Map<String, BookStatus> _statuses = {};
  String? _error;
  bool _syncing = false;
  String _scanStatus = 'Scanning your library…';
  bool _hasLocalFolder = false;
  bool _hasDriveConfigured = false;
  Set<String> _syncFoundPaths = {};
  _ViewMode _viewMode = _ViewMode.grid;

  // Search state.
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Status filter pill selection (null = show all).
  BookStatus? _statusFilter;

  // Availability filter selection.
  AvailabilityFilterState _availabilityFilter = AvailabilityFilterState.all;

  // User-selected sort order. Defaults to last-played until prefs load.
  LibrarySortOrder _sortOrder = LibrarySortOrder.lastPlayed;

  // Cached download size labels for Drive books not yet downloaded.
  // Key: book.path, Value: formatted size string e.g. "123.4 MB".
  final Map<String, String> _downloadSizeLabels = {};

  // Drive books currently being downloaded (tracked by folderId).
  final Set<String> _downloadingFolderIds = {};

  // Currently-active book tracking (for badge).
  String? _activePath;
  bool _isPlaying = false;
  StreamSubscription<PlaybackState>? _playbackSub;
  StreamSubscription<({String bookPath, String coverPath})>? _enrichSub;
  StreamSubscription<DriveDownloadEvent>? _driveSub;

  late final KowhaiHandler _audioHandler;
  bool _didInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      _audioHandler = AudioHandlerScope.of(context).audioHandler;
      _initLibrary();
      _enrichSub = locator<EnrichmentService>().onCoverFetched.listen(_onCoverFetched);
      _driveSub = locator<DriveDownloadManager>().downloadEvents.listen(_onDriveDownloadEvent);
      _playbackSub = _audioHandler.playbackState.listen((state) {
        final newPath = _audioHandler.currentBook?.path;
        if (newPath != _activePath || state.playing != _isPlaying) {
          setState(() {
            _activePath = newPath;
            _isPlaying = state.playing;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _playbackSub?.cancel();
    _enrichSub?.cancel();
    _driveSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _openSearch() => setState(() => _isSearching = true);

  void _closeSearch() {
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _searchQuery = '';
    });
  }

  List<Audiobook> get _displayedBooks {
    // Pipeline: availability → search → status
    final availFiltered = applyAvailabilityFilter(_books ?? [], _availabilityFilter);
    final searchFiltered = filterBooks(availFiltered, _searchQuery);
    return applyStatusFilter(searchFiltered, _statuses, _statusFilter);
  }

  // ── Scan + sort ─────────────────────────────────────────────────────────────

  Future<void> _initLibrary() async {
    final prefs = locator<PreferencesService>();
    final sortName = await prefs.getLibrarySort();
    final availFilter = await prefs.getAvailabilityFilter();
    final statusFilter = await prefs.getStatusFilter();
    final driveConnected = locator<DriveService>().currentAccount != null;
    if (mounted) {
      setState(() {
        _sortOrder = LibrarySortOrder.fromName(sortName);
        // Reset to `all` if Drive is not connected — the filter is meaningless
        // without a Drive account and the section won't be shown in the UI.
        _availabilityFilter = driveConnected ? availFilter : AvailabilityFilterState.all;
        _statusFilter = statusFilter;
      });
    }
    final shouldScan = widget.initialSyncDrive || await prefs.getRefreshOnStartup();
    // Always load previously discovered books so the library isn't empty on
    // launch. When refresh-on-startup is off, skip the Drive network sync —
    // cached Drive books still load from the DB.
    _scan(syncWithDrive: shouldScan);
  }

  /// Called by the scanner as each book is found. Appends it to the visible
  /// list immediately so the user sees books appear one by one during a scan.
  void _onBookFound(Audiobook book) {
    if (!mounted) return;
    _syncFoundPaths.add(book.path);
    _rawBooks ??= [];
    final idx = _rawBooks!.indexWhere((b) => b.path == book.path);
    if (idx == -1) {
      // New book — optimistic append to both lists (sort applied at end).
      setState(() {
        _rawBooks = [..._rawBooks!, book];
        _books = [...(_books ?? []), book];
      });
    } else {
      // Existing book — refresh metadata in place without reordering.
      setState(() {
        _rawBooks = List.from(_rawBooks!)..[idx] = book;
      });
    }
  }

  Future<void> _scan({bool syncWithDrive = true}) async {
    _syncFoundPaths = {};
    setState(() {
      _syncing = true;
      _scanStatus = 'Scanning your library…';
      _error = null;
      // Intentionally NOT clearing _rawBooks or _books so existing
      // books remain visible while the resync runs in the background.
    });
    try {
      final path = await locator<PreferencesService>().getLibraryPath();

      // No local folder — the wait is entirely on Drive, so say so.
      if (path == null && mounted) {
        setState(() => _scanStatus = 'Checking Google Drive…');
      }

      // Exclude Drive-managed dirs from local scan to avoid double-counting
      // books downloaded to the local library folder.
      final driveExcludes = path != null
          ? await locator<DriveLibraryService>().driveBookDirs()
          : <String>{};

      final results = await Future.wait([
        path != null
            ? locator<ScannerService>().scanFolder(
                path,
                excludePaths: driveExcludes,
                onBookFound: _onBookFound, // streams books into UI as found
              )
            : Future.value(<Audiobook>[]),
        // rescanDrive syncs with Drive when connected; falls back to DB-only
        // when offline or not configured. loadDriveBooks skips the network.
        syncWithDrive
            ? locator<DriveLibraryService>().rescanDrive()
            : locator<DriveLibraryService>().loadDriveBooks(),
      ]);
      final driveBooks = results[1];

      // Remove stale local books that were not found in this scan pass.
      final drivePaths = driveBooks.map((b) => b.path).toSet();
      _rawBooks = (_rawBooks ?? [])
          .where((b) =>
              drivePaths.contains(b.path) ||
              _syncFoundPaths.contains(b.path))
          .toList();

      final driveConfigured =
          await locator<PreferencesService>().getDriveRootFolder() != null;
      _hasLocalFolder = path != null;
      _hasDriveConfigured = driveConfigured;
      if (path == null && driveBooks.isEmpty && !driveConfigured) {
        if (!mounted) return;
        setState(() {
          _syncing = false;
        });
        return;
      }

      final enrichEnabled = await locator<PreferencesService>().getMetadataEnrichment();

      if (mounted && enrichEnabled) {
        setState(() => _scanStatus = 'Loading covers…');
      }

      // Apply cached enriched covers only when enrichment is enabled.
      // When disabled, treat each scan as a cache flush and show only
      // embedded artwork (or the default icon).
      final cachedCovers = enrichEnabled
          ? await locator<EnrichmentService>().getAllEnrichedCovers()
          : <String, String>{};
      _rawBooks = applyCachedCovers(_rawBooks ?? [], cachedCovers);
      _driveBooks = driveBooks;

      // Single DB read + full sort after all books are in.
      await _applySort();
      if (!mounted) return;
      setState(() => _syncing = false);

      // Start background enrichment for books missing covers.
      if (enrichEnabled) {
        unawaited(locator<EnrichmentService>().enqueueBooks(_rawBooks!));
      }

      // Restore the last-played book into the handler so the mini player
      // appears immediately on launch (without auto-playing).
      if (_audioHandler.currentBook == null) {
        final lastPath = await locator<PositionService>().getLastPlayedBookPath();
        if (lastPath != null) {
          final allBooks = [...(_rawBooks ?? []), ...driveBooks];
          final book = allBooks.where((b) => b.path == lastPath).firstOrNull;
          if (book != null) await _audioHandler.loadBook(book);
        }
      }
    } catch (e, st) {
      debugPrint('[LibraryScreen] scan failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = friendlyScanError(e);
        _syncing = false;
      });
    }
  }

  /// Persist the new sort order and re-sort the library.
  Future<void> _setSortOrder(LibrarySortOrder order) async {
    if (order == _sortOrder) return;
    setState(() => _sortOrder = order);
    await locator<PreferencesService>().setLibrarySort(order.name);
    await _applySort();
  }

  /// Loads positions from DB, sorts books, and updates state.
  Future<void> _applySort() async {
    final raw = _rawBooks;
    if (raw == null) return;

    final all = [...raw, ..._driveBooks];

    final positions = await locator<PositionService>().getAllPositions();
    final statuses = await locator<PositionService>().getAllStatuses();

    // dateAdded: use the folder's mtime for local books. Cheap enough for
    // typical library sizes (hundreds of books); skip on error.
    final dateAdded = <String, int>{};
    if (_sortOrder == LibrarySortOrder.dateAdded) {
      for (final b in all) {
        try {
          final st = await File(b.path).stat();
          dateAdded[b.path] = st.modified.millisecondsSinceEpoch;
        } catch (_) {
          // Drive-only books or stat errors fall through to 0.
        }
      }
    }

    // Prefetch formatted download sizes for Drive books that aren't fully
    // downloaded, so list tiles can show them without firing requests during
    // build. The cache map makes this idempotent across re-sorts.
    for (final b in all) {
      await _ensureDownloadSizeLabel(b);
    }

    if (!mounted) return;
    setState(() {
      _books = sortBooks(
        all,
        _sortOrder,
        positions: positions,
        dateAddedMs: dateAdded,
      );
      _statuses = statuses;
    });
  }

  void _onCoverFetched(({String bookPath, String coverPath}) event) {
    final raw = _rawBooks;
    if (raw == null) return;
    final idx = raw.indexWhere((b) => b.path == event.bookPath);
    if (idx == -1) return;
    final updated = List<Audiobook>.from(raw);
    updated[idx] = raw[idx].copyWith(coverImagePath: event.coverPath);
    _rawBooks = updated;
    _applySort();
  }

  void _onDriveDownloadEvent(DriveDownloadEvent event) {
    if (event.fileIndex == null) {
      // Cover download — still refresh on done for cover art.
      if (event.state == DriveDownloadState.done) {
        _refreshDriveBook(event.folderId).catchError((Object e, StackTrace st) {
          debugPrint('[LibraryScreen] _refreshDriveBook failed: $e\n$st');
        });
      }
      return;
    }
    // Track downloading state for the list-view menu.
    if (event.state == DriveDownloadState.downloading) {
      if (_downloadingFolderIds.add(event.folderId)) setState(() {});
    } else if (event.state == DriveDownloadState.done) {
      // Refresh on audio file done so cover art and metadata update.
      _refreshDriveBook(event.folderId).catchError((Object e, StackTrace st) {
        debugPrint('[LibraryScreen] _refreshDriveBook failed: $e\n$st');
      });
      // Check if all files are now done — if so, remove from downloading set.
      _checkDownloadComplete(event.folderId);
    } else if (event.state == DriveDownloadState.error) {
      _checkDownloadComplete(event.folderId);
    }
  }

  Future<void> _checkDownloadComplete(String folderId) async {
    final files = await locator<DriveBookRepository>().getFilesForBook(folderId);
    final stillDownloading = files.any(
        (f) => f.downloadState == DriveDownloadState.downloading);
    if (!stillDownloading && _downloadingFolderIds.remove(folderId)) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _refreshDriveBook(String folderId) async {
    final driveLibService = locator<DriveLibraryService>();
    final driveRepo = locator<DriveBookRepository>();
    final files = await driveRepo.getFilesForBook(folderId);
    final allDone = files.isNotEmpty && files.every((f) => f.downloadState == DriveDownloadState.done);

    Audiobook? updated;
    if (allDone) {
      // Promote: re-scan local dir for full metadata
      updated = await driveLibService.promoteToLocal(folderId);
    }
    // Fallback: reload from DB (covers partial downloads or failed promote)
    if (updated == null) {
      final freshBooks = await driveLibService.loadDriveBooks();
      updated = freshBooks.firstWhereOrNull(
        (b) => b.driveMetadata?.folderId == folderId,
      );
    }
    if (updated == null) return;

    final idx = _driveBooks.indexWhere((b) => b.driveMetadata?.folderId == folderId);
    if (idx != -1) {
      _driveBooks = List<Audiobook>.from(_driveBooks)..[idx] = updated;
    } else {
      _driveBooks = [..._driveBooks, updated];
    }
    // _applySort() rebuilds _books from _rawBooks + _driveBooks and calls
    // setState, which causes _displayedBooks to recompute via
    // applyAvailabilityFilter → filterBooks → applyStatusFilter.
    // This means a newly-downloaded Drive book automatically disappears from
    // the `driveOnly` view and appears in the `availableOffline` view without
    // any manual rescan (Requirements 2.6, 2.7).
    await _applySort();
  }

  Future<void> _openPlayer(BuildContext context, Audiobook book) async {
    if (book.isDrmLocked) {
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.lock_rounded),
          title: const Text('DRM-Protected File'),
          content: const Text(
            'This audiobook is in Audible\'s AAX/AA format and is protected '
            'by DRM (Digital Rights Management). Kōwhai cannot play '
            'DRM-protected files.\n\n'
            'To listen, use the Audible app, or convert the file to a '
            'DRM-free format using a tool that supports your local laws.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // Drive book: ensure files are available and metadata is fully populated
    if (book.source == AudiobookSource.drive &&
        (book.audioFiles.isEmpty || book.chapterDurations.isEmpty)) {
      final folderId = book.driveMetadata!.folderId;
      final files = await locator<DriveBookRepository>().getFilesForBook(folderId);
      final allDone = files.isNotEmpty &&
          files.every((f) => f.downloadState == DriveDownloadState.done);
      if (allDone) {
        await _refreshDriveBook(folderId);
        final refreshed = _driveBooks.firstWhereOrNull(
          (b) => b.driveMetadata?.folderId == folderId,
        );
        if (refreshed != null && refreshed.audioFiles.isNotEmpty) {
          book = refreshed;
        } else if (book.audioFiles.isEmpty) {
          if (context.mounted) showDriveDownloadSheet(context, book);
          return;
        }
      } else if (book.audioFiles.isEmpty) {
        // Check if a download is already in progress.
        final anyDownloading = files.any(
            (f) => f.downloadState == DriveDownloadState.downloading);
        if (anyDownloading) {
          if (context.mounted) {
            final cancelled =
                await showDriveDownloadProgressSheet(context, book);
            if (cancelled == true) _refreshDriveBook(folderId);
          }
        } else {
          if (context.mounted) showDriveDownloadSheet(context, book);
        }
        return;
      }
    }

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerScreen(book: book)),
    ).then((_) => _applySort()); // re-sort when returning from player
  }

  void _openDetails(BuildContext context, Audiobook book) {
    Navigator.push<dynamic>(
      context,
      MaterialPageRoute(builder: (_) => BookDetailsScreen(book: book)),
    ).then((result) {
      if (result == true) {
        _scan();
      } else if (result is String) {
        // Drive book was undownloaded — result is the folderId.
        _refreshDriveBook(result);
      } else {
        _applySort();
      }
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Library'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              child: SleepTimerIndicator(onTap: _openCurrentBookPlayer),
            ),
          ),
          IconButton(
            icon: Icon(_isSearching
                ? Icons.close_rounded
                : Icons.search_rounded),
            onPressed: _isSearching
                ? _closeSearch
                : (_books != null ? _openSearch : null),
            tooltip: _isSearching ? 'Close search' : 'Search',
          ),
          LibraryOverflowMenu(
            syncing: _syncing,
            onHistory: _openHistory,
            onRescan: _syncing ? null : _scan,
            onSettings: _openSettings,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _searchBar(),
          Expanded(child: _body()),
          MiniPlayer(),
        ],
      ),
    );
  }

  void _openHistory() {
    final books = _rawBooks;
    if (books == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HistoryScreen(books: [...books, ..._driveBooks]),
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          onFolderChanged: _scan,
          onDriveRescanned: _scan,
        ),
      ),
    );
  }

  Widget _searchBar() {
    final theme = Theme.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: _isSearching
          ? Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search by title or author…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          tooltip: 'Clear',
                        )
                      : null,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 64, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                onPressed: _scan,
              ),
            ],
          ),
        ),
      );
    }

    final allBooks = _books ?? [];

    if (allBooks.isEmpty) {
      if (_syncing) {
        return _DriveScanOverlay(status: _scanStatus);
      }
      final content = emptyStateContent(
        hasLocalFolder: _hasLocalFolder,
        hasDriveConfigured: _hasDriveConfigured,
      );
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.library_music_outlined,
                  size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                content.title,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(content.message, textAlign: TextAlign.center),
              if (content.showCta) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('Open Settings'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                        onFolderChanged: _scan,
                        onDriveRescanned: _scan,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final books = _displayedBooks;

    if (books.isEmpty && _statusFilter == null && _searchQuery.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded,
                  size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No audiobooks found.\n\nMake sure your folder contains subfolders with audio files.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        _viewBar(books.length),
        Expanded(
          child: books.isEmpty
              ? _noMatchesView()
              : _viewMode == _ViewMode.grid
                  ? _grid(books)
                  : _list(books),
        ),
      ],
    );
  }

  // ── View bar (pinned, below search) ─────────────────────────────────────────

  Widget _viewBar(int count) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasStatus = _statusFilter != null;
    final hasAvailability = _availabilityFilter != AvailabilityFilterState.all;
    final hasSort = _sortOrder != LibrarySortOrder.lastPlayed;

    final summaryParts = <String>[];
    if (hasStatus) summaryParts.add(_statusFilterLabel(_statusFilter!));
    if (hasAvailability) summaryParts.add(_availabilityFilter.label);
    if (hasSort) summaryParts.add(_sortOrder.label);
    final summary = summaryParts.isEmpty
        ? null
        : ' · ${summaryParts.join(' · ')}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(_viewMode == _ViewMode.grid
                ? Icons.view_list_rounded
                : Icons.grid_view_rounded),
            onPressed: () => setState(() => _viewMode =
                _viewMode == _ViewMode.grid
                    ? _ViewMode.list
                    : _ViewMode.grid),
            tooltip:
                _viewMode == _ViewMode.grid ? 'Switch to list view' : 'Switch to grid view',
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: count == 1 ? '1 book' : '$count books',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  if (summary != null)
                    TextSpan(
                      text: summary,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.primary,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _viewBarButton(
            icon: Icons.tune_rounded,
            active: hasStatus || hasAvailability,
            tooltip: 'Filter',
            onPressed: _openFilterSheet,
          ),
          const SizedBox(width: 4),
          _viewBarButton(
            icon: Icons.sort_rounded,
            active: hasSort,
            tooltip: 'Sort',
            onPressed: _openSortSheet,
          ),
        ],
      ),
    );
  }

  Widget _viewBarButton({
    required IconData icon,
    required bool active,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: active
          ? cs.primary.withValues(alpha: 0.14)
          : Colors.transparent,
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(
          icon,
          color: active ? cs.primary : cs.onSurface.withValues(alpha: 0.75),
        ),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }

  // ── Filter + Sort sheets ────────────────────────────────────────────────────

  Future<void> _openFilterSheet() async {
    // Compute counts based on search-filtered books (ignoring status filter).
    final searchFiltered = filterBooks(_books ?? [], _searchQuery);
    final allCount = searchFiltered.length;
    final statusCounts = <BookStatus, int>{};
    for (final s in BookStatus.values) {
      statusCounts[s] = applyStatusFilter(searchFiltered, _statuses, s).length;
    }

    // Availability pill counts (based on same search-filtered base).
    final availCounts = <AvailabilityFilterState, int>{};
    for (final s in AvailabilityFilterState.values) {
      availCounts[s] = applyAvailabilityFilter(searchFiltered, s).length;
    }

    final driveConnected = locator<DriveService>().currentAccount != null;
    final hasDriveBooks = _driveBooks.isNotEmpty;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final theme = Theme.of(sheetCtx);
          final maxHeight = MediaQuery.of(sheetCtx).size.height * 0.75;

          // Whether "Clear all" should be enabled.
          final canClear = _statusFilter != null ||
              _availabilityFilter != AvailabilityFilterState.all;

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Filter', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 16),
                          Text(
                            'PROGRESS',
                            style: theme.textTheme.labelSmall?.copyWith(
                              letterSpacing: 1.2,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _pill(
                                label: 'All ($allCount)',
                                selected: _statusFilter == null,
                                onTap: () {
                                  setState(() => _statusFilter = null);
                                  locator<PreferencesService>()
                                      .setStatusFilter(null);
                                  setSheetState(() {});
                                },
                              ),
                              for (final s in BookStatus.values)
                                _pill(
                                  label: '${_statusFilterLabel(s)} (${statusCounts[s] ?? 0})',
                                  selected: _statusFilter == s,
                                  onTap: () {
                                    setState(() => _statusFilter = s);
                                    locator<PreferencesService>()
                                        .setStatusFilter(s);
                                    setSheetState(() {});
                                  },
                                ),
                            ],
                          ),
                          // ── AVAILABILITY section (Drive-connected only) ──
                          if (driveConnected) ...[
                            const SizedBox(height: 20),
                            Text(
                              'AVAILABILITY',
                              style: theme.textTheme.labelSmall?.copyWith(
                                letterSpacing: 1.2,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _pill(
                                  label: 'All (${availCounts[AvailabilityFilterState.all] ?? 0})',
                                  selected: _availabilityFilter == AvailabilityFilterState.all,
                                  onTap: () {
                                    setState(() {
                                      _availabilityFilter = AvailabilityFilterState.all;
                                    });
                                    locator<PreferencesService>()
                                        .setAvailabilityFilter(AvailabilityFilterState.all);
                                    setSheetState(() {});
                                  },
                                ),
                                if (hasDriveBooks) ...[
                                  _pill(
                                    label: 'Available offline (${availCounts[AvailabilityFilterState.availableOffline] ?? 0})',
                                    selected: _availabilityFilter == AvailabilityFilterState.availableOffline,
                                    onTap: () {
                                      setState(() {
                                        _availabilityFilter = AvailabilityFilterState.availableOffline;
                                      });
                                      locator<PreferencesService>()
                                          .setAvailabilityFilter(AvailabilityFilterState.availableOffline);
                                      setSheetState(() {});
                                    },
                                  ),
                                  _pill(
                                    label: 'Drive only (${availCounts[AvailabilityFilterState.driveOnly] ?? 0})',
                                    selected: _availabilityFilter == AvailabilityFilterState.driveOnly,
                                    onTap: () {
                                      setState(() {
                                        _availabilityFilter = AvailabilityFilterState.driveOnly;
                                      });
                                      locator<PreferencesService>()
                                          .setAvailabilityFilter(AvailabilityFilterState.driveOnly);
                                      setSheetState(() {});
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ],
                          const SizedBox(height: 20),
                          TextButton.icon(
                            icon: const Icon(Icons.filter_alt_off_rounded),
                            label: const Text('Clear all'),
                            onPressed: canClear
                                ? () {
                                    setState(() {
                                      _statusFilter = null;
                                      _availabilityFilter = AvailabilityFilterState.all;
                                    });
                                    final prefs = locator<PreferencesService>();
                                    prefs.setStatusFilter(null);
                                    prefs.setAvailabilityFilter(AvailabilityFilterState.all);
                                    setSheetState(() {});
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openSortSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        final maxHeight = MediaQuery.of(sheetCtx).size.height * 0.75;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Sort by', style: theme.textTheme.titleMedium),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final order in LibrarySortOrder.values)
                        ListTile(
                          title: Text(_sortPillLabel(order)),
                          trailing: order == _sortOrder
                              ? Icon(Icons.check_rounded,
                                  color: theme.colorScheme.primary)
                              : null,
                          onTap: () async {
                            await _setSortOrder(order);
                            if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                          },
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _sortPillLabel(LibrarySortOrder order) => switch (order) {
        LibrarySortOrder.lastPlayed   => 'Last played',
        LibrarySortOrder.titleAsc     => 'Title A–Z',
        LibrarySortOrder.authorAsc    => 'Author A–Z',
        LibrarySortOrder.dateAdded    => 'Recently added',
        LibrarySortOrder.durationDesc => 'Longest first',
      };

  Widget _pill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? cs.primary.withValues(alpha: 0.16)
          : Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(
          width: 1.5,
          color: selected
              ? cs.primary
              : cs.outlineVariant,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? cs.primary : cs.onSurface,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _noMatchesView() {
    final hasSearch = _searchQuery.isNotEmpty;
    final hasStatus = _statusFilter != null;
    final hasAvailability = _availabilityFilter != AvailabilityFilterState.all;
    final hasAnyFilter = hasStatus || hasAvailability;

    final String message;
    if (hasSearch && hasStatus && hasAvailability) {
      message =
          'No ${_statusFilterLabel(_statusFilter!).toLowerCase()} '
          '${_availabilityFilter.label.toLowerCase()} books match "$_searchQuery".';
    } else if (hasSearch && hasStatus) {
      message =
          'No ${_statusFilterLabel(_statusFilter!).toLowerCase()} books match "$_searchQuery".';
    } else if (hasSearch && hasAvailability) {
      message =
          'No ${_availabilityFilter.label.toLowerCase()} books match "$_searchQuery".';
    } else if (hasStatus && hasAvailability) {
      message =
          'No ${_statusFilterLabel(_statusFilter!).toLowerCase()} '
          '${_availabilityFilter.label.toLowerCase()} books.';
    } else if (hasStatus) {
      message = 'No ${_statusFilterLabel(_statusFilter!).toLowerCase()} books.';
    } else if (hasAvailability) {
      message = 'No ${_availabilityFilter.label.toLowerCase()} books.';
    } else {
      message = 'No results for "$_searchQuery".';
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded,
                size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            if (hasSearch || hasAnyFilter) ...[
              const SizedBox(height: 20),
              TextButton.icon(
                icon: const Icon(Icons.filter_alt_off_rounded),
                label: const Text('Clear filters'),
                onPressed: _clearSearchAndFilters,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openCurrentBookPlayer() {
    final ah = AudioHandlerScope.of(context).audioHandler;
    final book = ah.currentBook;
    if (book == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerScreen(book: book)),
    );
  }

  void _clearSearchAndFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _statusFilter = null;
      _availabilityFilter = AvailabilityFilterState.all;
    });
    final prefs = locator<PreferencesService>();
    prefs.setStatusFilter(null);
    prefs.setAvailabilityFilter(AvailabilityFilterState.all);
  }

  String _statusFilterLabel(BookStatus s) => switch (s) {
        BookStatus.notStarted => 'Not started',
        BookStatus.inProgress => 'In progress',
        BookStatus.finished   => 'Finished',
      };

  Widget _grid(List<Audiobook> books) {
    const crossAxisCount = 2;
    const spacing = 12.0;
    const padding = 12.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - padding * 2 - spacing * (crossAxisCount - 1)) / crossAxisCount;
        return RefreshIndicator(
          onRefresh: _scan,
          child: GridView.builder(
            padding: const EdgeInsets.all(padding),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              mainAxisExtent: cardWidth, // pure square — no text block
            ),
            itemCount: books.length,
            itemBuilder: (context, i) => AudiobookCard(
              book: books[i],
              isActive: books[i].path == _activePath && _isPlaying,
              status: _statuses[books[i].path] ?? BookStatus.notStarted,
              onTap: () => _openPlayer(context, books[i]),
              onLongPress: () => _openDetails(context, books[i]),
            ),
          ),
        );
      },
    );
  }

  /// Fetches and caches the formatted download size for a Drive book that
  /// hasn't been fully downloaded yet. No-op if already cached or not applicable.
  Future<void> _ensureDownloadSizeLabel(Audiobook book) async {
    if (book.source != AudiobookSource.drive) return;
    final meta = book.driveMetadata;
    if (meta == null) return;
    // Only show for books that are not fully downloaded.
    final total = meta.totalFileCount;
    final downloaded = book.audioFiles.length;
    if (total > 0 && downloaded >= total) return;
    if (_downloadSizeLabels.containsKey(book.path)) return;

    final sizeBytes = await locator<DriveLibraryService>().totalSizeBytes(meta.folderId);
    if (!mounted) return;
    if (sizeBytes > 0) {
      setState(() => _downloadSizeLabels[book.path] = formatBytes(sizeBytes));
    }
  }

  Widget _list(List<Audiobook> books) {
    return RefreshIndicator(
      onRefresh: _scan,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: books.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 88),
        itemBuilder: (context, i) {
          final book = books[i];
          final folderId = book.driveMetadata?.folderId;
          final downloading = folderId != null &&
              _downloadingFolderIds.contains(folderId);
          return AudiobookListTile(
            book: book,
            isActive: book.path == _activePath && _isPlaying,
            status: _statuses[book.path] ?? BookStatus.notStarted,
            onTap: () => _openPlayer(context, book),
            onDetailsPressed: () => _openDetails(context, book),
            isDownloading: downloading,
            downloadSizeLabel: downloading
                ? null
                : _downloadSizeLabels[book.path],
            onDownloadPressed: !downloading && _downloadSizeLabels[book.path] != null
                ? () => showDriveDownloadSheet(context, book)
                : null,
            onCancelDownloadPressed: downloading
                ? () async {
                    final cancelled =
                        await showDriveDownloadProgressSheet(context, book);
                    if (cancelled == true) {
                      _downloadingFolderIds.remove(folderId);
                      _refreshDriveBook(folderId);
                    }
                  }
                : null,
          );
        },
      ),
    );
  }
}

/// Animated overlay shown while the Drive library is being scanned for the
/// first time. Designed to feel alive during what would otherwise be a blank
/// wait — especially during onboarding.
///
/// Features:
/// - Pulsing headphones icon (scale + opacity loop)
/// - Status text that cross-fades between phases
/// - A rotating audiobook tip that changes every few seconds
class _DriveScanOverlay extends StatefulWidget {
  final String status;

  const _DriveScanOverlay({required this.status});

  @override
  State<_DriveScanOverlay> createState() => _DriveScanOverlayState();
}

class _DriveScanOverlayState extends State<_DriveScanOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  late final AnimationController _tipController;
  int _tipIndex = 0;

  static const _tips = [
    'Tip: Tap the chapter label in the player to jump to any chapter.',
    'Tip: Set the sleep timer to stop at the end of a chapter.',
    'Tip: Add bookmarks while listening to save your favourite moments.',
    'Tip: Your listening position syncs across devices via Drive.',
    'Tip: Use the sort menu to find your next listen by author.',
    'Tip: Download a book to listen without an internet connection.',
  ];

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseOpacity = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _tipController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            _tipIndex = (_tipIndex + 1) % _tips.length;
          });
          _tipController.forward(from: 0);
        }
      });
    _tipController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _tipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing icon
            AnimatedBuilder(
              animation: _pulseController,
              builder: (_, __) => Opacity(
                opacity: _pulseOpacity.value,
                child: Transform.scale(
                  scale: _pulseScale.value,
                  child: Icon(
                    Icons.headphones_rounded,
                    size: 64,
                    color: cs.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // Cross-fading status text
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: child,
              ),
              child: Text(
                widget.status,
                key: ValueKey(widget.status),
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 40),

            // Rotating tip
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: child,
              ),
              child: Text(
                _tips[_tipIndex],
                key: ValueKey(_tipIndex),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
