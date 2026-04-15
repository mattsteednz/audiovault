import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../models/audiobook.dart';
import '../services/audio_handler.dart';
import '../services/drive_book_repository.dart';
import '../services/drive_download_manager.dart';
import '../services/drive_library_service.dart';
import '../services/enrichment_service.dart';
import '../services/position_service.dart';
import '../services/preferences_service.dart';
import '../services/scanner_service.dart';
import '../widgets/audio_handler_scope.dart';
import '../widgets/audiobook_card.dart';
import '../widgets/audiobook_list_tile.dart';
import '../widgets/book_cover.dart';
import 'book_details_screen.dart';
import 'history_screen.dart';
import 'player_screen.dart';
import 'settings_screen.dart';
import '../locator.dart';

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

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Audiobook>? _books;       // sorted display order
  List<Audiobook>? _rawBooks;    // unsorted, straight from scanner
  List<Audiobook> _driveBooks = []; // Drive books (unsorted)
  Map<String, BookStatus> _statuses = {};
  String? _error;
  bool _scanning = false;
  _ViewMode _viewMode = _ViewMode.grid;

  // Search state.
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Status filter pill selection (null = show all).
  BookStatus? _statusFilter;

  // Currently-active book tracking (for badge).
  String? _activePath;
  bool _isPlaying = false;
  StreamSubscription<PlaybackState>? _playbackSub;
  StreamSubscription<({String bookPath, String coverPath})>? _enrichSub;
  StreamSubscription<DriveDownloadEvent>? _driveSub;

  late final AudioVaultHandler _audioHandler;
  bool _didInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      _audioHandler = AudioHandlerScope.of(context).audioHandler;
      _scan();
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
    var books = filterBooks(_books ?? [], _searchQuery);
    if (_statusFilter != null) {
      books = books
          .where((b) =>
              (_statuses[b.path] ?? BookStatus.notStarted) == _statusFilter)
          .toList();
    }
    return books;
  }

  // ── Scan + sort ─────────────────────────────────────────────────────────────

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final path = await locator<PreferencesService>().getLibraryPath();

      // Exclude Drive-managed dirs from local scan to avoid double-counting
      // books downloaded to the local library folder.
      final driveExcludes = path != null
          ? await locator<DriveLibraryService>().driveBookDirs()
          : <String>{};

      final results = await Future.wait([
        path != null
            ? locator<ScannerService>()
                .scanFolder(path, excludePaths: driveExcludes)
            : Future.value(<Audiobook>[]),
        // rescanDrive syncs with Drive when connected; falls back to DB-only
        // when offline or not configured.
        locator<DriveLibraryService>().rescanDrive(),
      ]);
      final books = results[0];
      final driveBooks = results[1];

      final driveConfigured =
          await locator<PreferencesService>().getDriveRootFolder() != null;
      if (path == null && driveBooks.isEmpty && !driveConfigured) {
        setState(() {
          _error = 'No library folder set.';
          _scanning = false;
        });
        return;
      }

      final enrichEnabled = await locator<PreferencesService>().getMetadataEnrichment();

      // Apply cached enriched covers only when enrichment is enabled.
      // When disabled, treat each scan as a cache flush and show only
      // embedded artwork (or the default icon).
      final cachedCovers = enrichEnabled
          ? await locator<EnrichmentService>().getAllEnrichedCovers()
          : <String, String>{};
      _rawBooks = applyCachedCovers(books, cachedCovers);
      _driveBooks = driveBooks;

      await _applySort();
      setState(() => _scanning = false);

      // Start background enrichment for books missing covers.
      if (enrichEnabled) {
        unawaited(locator<EnrichmentService>().enqueueBooks(_rawBooks!));
      }

      // Restore the last-played book into the handler so the mini player
      // appears immediately on launch (without auto-playing).
      if (_audioHandler.currentBook == null) {
        final lastPath = await locator<PositionService>().getLastPlayedBookPath();
        if (lastPath != null) {
          final allBooks = [...books, ...driveBooks];
          final book = allBooks.where((b) => b.path == lastPath).firstOrNull;
          if (book != null) await _audioHandler.loadBook(book);
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Scan failed: $e';
        _scanning = false;
      });
    }
  }

  /// Loads positions from DB, sorts books, and updates state.
  Future<void> _applySort() async {
    final raw = _rawBooks;
    if (raw == null) return;

    final all = [...raw, ..._driveBooks];

    final positions = await locator<PositionService>().getAllPositions();
    final statuses = await locator<PositionService>().getAllStatuses();
    final played = <String, int>{
      for (final p in positions) p.bookPath: p.updatedAt
    };

    final withHistory = all.where((b) => played.containsKey(b.path)).toList()
      ..sort((a, b) => (played[b.path] ?? 0).compareTo(played[a.path] ?? 0));

    final withoutHistory = all
        .where((b) => !played.containsKey(b.path))
        .toList()
      ..sort((a, b) =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    setState(() {
      _books = [...withHistory, ...withoutHistory];
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
    if (event.state == DriveDownloadState.done) {
      // Refresh on audio file done OR cover done (fileIndex == null) so
      // cover art appears as soon as it finishes downloading.
      _refreshDriveBook(event.folderId);
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
      updated = freshBooks.cast<Audiobook?>().firstWhere(
        (b) => b?.driveMetadata?.folderId == folderId,
        orElse: () => null,
      );
    }
    if (updated == null) return;

    final idx = _driveBooks.indexWhere((b) => b.driveMetadata?.folderId == folderId);
    if (idx != -1) {
      _driveBooks = List<Audiobook>.from(_driveBooks)..[idx] = updated;
    } else {
      _driveBooks = [..._driveBooks, updated];
    }
    _applySort();
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
            'by DRM (Digital Rights Management). AudioVault cannot play '
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
        final refreshed = _driveBooks.cast<Audiobook?>().firstWhere(
          (b) => b?.driveMetadata?.folderId == folderId,
          orElse: () => null,
        );
        if (refreshed != null && refreshed.audioFiles.isNotEmpty) {
          book = refreshed;
        } else if (book.audioFiles.isEmpty) {
          if (context.mounted) _showDriveDownloadSheet(context, book);
          return;
        }
      } else if (book.audioFiles.isEmpty) {
        if (context.mounted) _showDriveDownloadSheet(context, book);
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

  Future<void> _showDriveDownloadSheet(BuildContext context, Audiobook book) async {
    final folderId = book.driveMetadata!.folderId;
    final connectivity = await Connectivity().checkConnectivity();
    final isWifi = connectivity.contains(ConnectivityResult.wifi) ||
        connectivity.contains(ConnectivityResult.ethernet);

    int? sizeBytes;
    if (!isWifi) {
      sizeBytes = await locator<DriveLibraryService>().totalSizeBytes(folderId);
    }
    if (!context.mounted) return;

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(book.title,
                style: Theme.of(ctx).textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            if (sizeBytes != null)
              Text('You\'re on mobile data. This book is ${_formatBytes(sizeBytes)}. '
                  'Download anyway?')
            else
              const Text(
                  'This book hasn\'t been downloaded yet. Download it to start listening.'),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.download_rounded),
                  label: Text(sizeBytes != null
                      ? 'Download (${_formatBytes(sizeBytes)})'
                      : 'Download'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    locator<DriveLibraryService>().startDownload(folderId);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _isSearching
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _closeSearch,
                tooltip: 'Cancel search',
              )
            : null,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search by title or author…',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : const Text('My Library'),
        actions: _isSearching
            ? [
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    tooltip: 'Clear',
                  ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.search_rounded),
                  onPressed: _books != null && _books!.isNotEmpty
                      ? _openSearch
                      : null,
                  tooltip: 'Search',
                ),
                IconButton(
                  icon: const Icon(Icons.history_rounded),
                  onPressed: () {
                    final books = _rawBooks;
                    if (books != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => HistoryScreen(books: books)),
                      );
                    }
                  },
                  tooltip: 'History',
                ),
                IconButton(
                  icon: Icon(_viewMode == _ViewMode.grid
                      ? Icons.view_list_rounded
                      : Icons.grid_view_rounded),
                  onPressed: () => setState(() => _viewMode =
                      _viewMode == _ViewMode.grid
                          ? _ViewMode.list
                          : _ViewMode.grid),
                  tooltip:
                      _viewMode == _ViewMode.grid ? 'List view' : 'Grid view',
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _scanning ? null : _scan,
                  tooltip: 'Rescan',
                ),
                IconButton(
                  icon: const Icon(Icons.settings_rounded),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                        onFolderChanged: _scan,
                        onDriveRescanned: _scan,
                      ),
                    ),
                  ),
                  tooltip: 'Settings',
                ),
              ],
      ),
      body: Column(
        children: [
          Expanded(child: _body()),
          _MiniPlayer(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_scanning) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Scanning your library…'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(_error!,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error)),
        ),
      );
    }

    final allBooks = _books ?? [];

    if (allBooks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.library_music_outlined,
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
        _filterPillsRow(),
        Expanded(
          child: books.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.search_off_rounded,
                            size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          _statusFilter != null
                              ? 'No ${_statusFilterLabel(_statusFilter!).toLowerCase()} books.'
                              : 'No results for "$_searchQuery".',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : _viewMode == _ViewMode.grid
                  ? _grid(books)
                  : _list(books),
        ),
      ],
    );
  }

  String _statusFilterLabel(BookStatus s) => switch (s) {
        BookStatus.notStarted => 'Not started',
        BookStatus.inProgress => 'In progress',
        BookStatus.finished   => 'Finished',
      };

  Widget _filterPillsRow() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: BookStatus.values.map((status) {
          final selected = _statusFilter == status;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(_statusFilterLabel(status)),
              selected: selected,
              onSelected: (_) => setState(() {
                _statusFilter = selected ? null : status;
              }),
              showCheckmark: false,
              avatar: Icon(
                switch (status) {
                  BookStatus.notStarted => Icons.radio_button_unchecked_rounded,
                  BookStatus.inProgress => Icons.timelapse_rounded,
                  BookStatus.finished   => Icons.check_circle_rounded,
                },
                size: 16,
                color: selected
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _grid(List<Audiobook> books) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.68,
      ),
      itemCount: books.length,
      itemBuilder: (context, i) => AudiobookCard(
        book: books[i],
        isActive: books[i].path == _activePath && _isPlaying,
        status: _statuses[books[i].path] ?? BookStatus.notStarted,
        onTap: () => _openPlayer(context, books[i]),
        onLongPress: () => _openDetails(context, books[i]),
      ),
    );
  }

  Widget _list(List<Audiobook> books) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: books.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 88),
      itemBuilder: (context, i) => AudiobookListTile(
        book: books[i],
        isActive: books[i].path == _activePath && _isPlaying,
        status: _statuses[books[i].path] ?? BookStatus.notStarted,
        onTap: () => _openPlayer(context, books[i]),
        onDetailsPressed: () => _openDetails(context, books[i]),
      ),
    );
  }
}

// ── Mini player ───────────────────────────────────────────────────────────────

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer();

  @override
  Widget build(BuildContext context) {
    final ah = AudioHandlerScope.of(context).audioHandler;
    return StreamBuilder<PlaybackState>(
      stream: ah.playbackState,
      builder: (context, snap) {
        final state = snap.data;
        final book = ah.currentBook;
        if (book == null ||
            state == null ||
            state.processingState == AudioProcessingState.idle) {
          return const SizedBox.shrink();
        }

        final playing = state.playing;
        final theme = Theme.of(context);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thin progress bar (global book progress)
            StreamBuilder<Duration>(
              stream: ah.effectivePositionStream,
              builder: (_, posSnap) {
                final totalMs =
                    book.duration?.inMilliseconds.toDouble() ?? 0;
                if (totalMs <= 0) {
                  return LinearProgressIndicator(
                    value: 0,
                    minHeight: 2,
                    backgroundColor:
                        theme.colorScheme.surfaceContainerHighest,
                  );
                }
                final idx = ah.isCasting ? 0 : (ah.player.currentIndex ?? 0);
                int offsetMs = 0;
                for (int i = 0;
                    i < idx && i < book.chapterDurations.length;
                    i++) {
                  offsetMs += book.chapterDurations[i].inMilliseconds;
                }
                final globalMs = offsetMs +
                    (posSnap.data?.inMilliseconds ?? 0);
                return LinearProgressIndicator(
                  value: (globalMs / totalMs).clamp(0.0, 1.0),
                  minHeight: 2,
                  backgroundColor:
                      theme.colorScheme.surfaceContainerHighest,
                );
              },
            ),
            Material(
              color: theme.colorScheme.surfaceContainerHigh,
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => PlayerScreen(book: book)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: BookCover(book: book, iconSize: 28),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              book.title,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(
                                      fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            StreamBuilder<Duration>(
                              stream: ah.effectivePositionStream,
                              builder: (_, posSnap) {
                                final remaining =
                                    _remaining(ah, book, posSnap.data);
                                if (remaining == null) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  _fmtRemaining(remaining),
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(
                                          color: theme
                                              .colorScheme.onSurface
                                              .withValues(alpha: 0.6)),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded),
                        onPressed: playing
                            ? ah.pause
                            : ah.play,
                      ),
                    ],
                  ),
                ),
                ), // SafeArea
              ),
            ),
          ],
        );
      },
    );
  }

  Duration? _remaining(
      AudioVaultHandler ah, Audiobook book, Duration? chapterPos) {
    final totalMs = book.duration?.inMilliseconds;
    if (totalMs == null || totalMs == 0) return null;
    final idx = ah.isCasting ? 0 : (ah.player.currentIndex ?? 0);
    int offsetMs = 0;
    for (int i = 0; i < idx && i < book.chapterDurations.length; i++) {
      offsetMs += book.chapterDurations[i].inMilliseconds;
    }
    final globalMs = offsetMs + (chapterPos?.inMilliseconds ?? 0);
    final remainingMs = (totalMs - globalMs).clamp(0, totalMs);
    return Duration(milliseconds: remainingMs);
  }

  String _fmtRemaining(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m left';
    return '${m}m left';
  }
}
