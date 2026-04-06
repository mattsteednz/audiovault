import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import '../models/audiobook.dart';
import '../services/audio_handler.dart';
import '../services/enrichment_service.dart';
import '../services/position_service.dart';
import '../services/preferences_service.dart';
import '../services/scanner_service.dart';
import '../widgets/audio_handler_scope.dart';
import '../widgets/audiobook_card.dart';
import '../widgets/audiobook_list_tile.dart';
import '../widgets/book_cover.dart';
import 'player_screen.dart';
import 'settings_screen.dart';

enum _ViewMode { grid, list }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Audiobook>? _books;       // sorted display order
  List<Audiobook>? _rawBooks;    // unsorted, straight from scanner
  String? _error;
  bool _scanning = false;
  _ViewMode _viewMode = _ViewMode.grid;

  // Currently-active book tracking (for badge).
  String? _activePath;
  bool _isPlaying = false;
  StreamSubscription<PlaybackState>? _playbackSub;
  StreamSubscription<({String bookPath, String coverPath})>? _enrichSub;

  late final AudioVaultHandler _audioHandler;
  bool _didInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      _audioHandler = AudioHandlerScope.of(context).audioHandler;
      _scan();
      _enrichSub = EnrichmentService().onCoverFetched.listen(_onCoverFetched);
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
    super.dispose();
  }

  // ── Scan + sort ─────────────────────────────────────────────────────────────

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final path = await PreferencesService().getLibraryPath();
      if (path == null) {
        setState(() {
          _error = 'No library folder set.';
          _scanning = false;
        });
        return;
      }
      final books = await ScannerService().scanFolder(path);

      // Apply any covers already fetched in a previous session.
      final cachedCovers = await EnrichmentService().getAllEnrichedCovers();
      _rawBooks = cachedCovers.isEmpty
          ? books
          : books.map((b) {
              if (b.coverImagePath != null || b.coverImageBytes != null) {
                return b;
              }
              final cached = cachedCovers[b.path];
              return cached != null ? b.copyWith(coverImagePath: cached) : b;
            }).toList();

      await _applySort();
      setState(() => _scanning = false);

      // Start background enrichment for books missing covers.
      final enrichEnabled = await PreferencesService().getMetadataEnrichment();
      if (enrichEnabled) {
        unawaited(EnrichmentService().enqueueBooks(_rawBooks!));
      }

      // Restore the last-played book into the handler so the mini player
      // appears immediately on launch (without auto-playing).
      if (_audioHandler.currentBook == null) {
        final lastPath = await PositionService().getLastPlayedBookPath();
        if (lastPath != null) {
          final book = books.where((b) => b.path == lastPath).firstOrNull;
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

    final positions = await PositionService().getAllPositions();
    final played = <String, int>{
      for (final p in positions) p.bookPath: p.updatedAt
    };

    final withHistory = raw.where((b) => played.containsKey(b.path)).toList()
      ..sort((a, b) => (played[b.path] ?? 0).compareTo(played[a.path] ?? 0));

    final withoutHistory = raw
        .where((b) => !played.containsKey(b.path))
        .toList()
      ..sort((a, b) =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    setState(() {
      _books = [...withHistory, ...withoutHistory];
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

  void _openPlayer(BuildContext context, Audiobook book) {
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
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerScreen(book: book)),
    ).then((_) => _applySort()); // re-sort when returning from player
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Library'),
        actions: [
          IconButton(
            icon: Icon(_viewMode == _ViewMode.grid
                ? Icons.view_list_rounded
                : Icons.grid_view_rounded),
            onPressed: () => setState(() => _viewMode =
                _viewMode == _ViewMode.grid ? _ViewMode.list : _ViewMode.grid),
            tooltip: _viewMode == _ViewMode.grid ? 'List view' : 'Grid view',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _scanning ? null : _scan,
            tooltip: 'Rescan',
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () async {
              final folderChanged = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              if (folderChanged == true) _scan();
            },
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

    final books = _books ?? [];

    if (books.isEmpty) {
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

    return _viewMode == _ViewMode.grid ? _grid(books) : _list(books);
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
        onTap: () => _openPlayer(context, books[i]),
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
        onTap: () => _openPlayer(context, books[i]),
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
            // Thin progress bar
            StreamBuilder<Duration>(
              stream: ah.player.positionStream,
              builder: (_, posSnap) {
                final pos =
                    posSnap.data?.inMilliseconds.toDouble() ?? 0;
                final dur = ah.player.duration
                        ?.inMilliseconds
                        .toDouble() ??
                    0;
                return LinearProgressIndicator(
                  value: dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0,
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
                              stream: ah.player.positionStream,
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
    final idx = ah.player.currentIndex ?? 0;
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
