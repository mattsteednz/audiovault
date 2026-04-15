import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:path/path.dart' as p;
import '../models/audiobook.dart';
import '../services/audio_handler.dart';
import '../services/preferences_service.dart';
import '../widgets/audio_handler_scope.dart';
import '../widgets/book_cover.dart';
import '../locator.dart';

// ── Sleep timer options ───────────────────────────────────────────────────────

typedef _TimerOpt = ({String label, Duration? duration, bool endOfChapter});

const List<_TimerOpt> _timerOpts = [
  (label: 'Off',            duration: null,                   endOfChapter: false),
  (label: '5 minutes',      duration: Duration(minutes: 5),   endOfChapter: false),
  (label: '10 minutes',     duration: Duration(minutes: 10),  endOfChapter: false),
  (label: '15 minutes',     duration: Duration(minutes: 15),  endOfChapter: false),
  (label: '30 minutes',     duration: Duration(minutes: 30),  endOfChapter: false),
  (label: '45 minutes',     duration: Duration(minutes: 45),  endOfChapter: false),
  (label: '60 minutes',     duration: Duration(minutes: 60),  endOfChapter: false),
  (label: 'End of chapter', duration: null,                   endOfChapter: true),
];

const _commonSpeeds = [0.75, 1.0, 1.25, 1.5, 2.0, 2.5];

// ── Screen ────────────────────────────────────────────────────────────────────

class PlayerScreen extends StatefulWidget {
  final Audiobook book;
  const PlayerScreen({super.key, required this.book});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  double _speed = 1.0;
  int _skipInterval = 30;

  // Sleep timer
  Timer? _sleepTimer;
  Duration _sleepRemaining = Duration.zero;
  bool _stopAtChapterEnd = false;

  // Progress slider drag state
  bool _dragging = false;
  Duration _dragPosition = Duration.zero;

  // Chapter tracking — used for both UI display and "end of chapter" timer.
  // _currentChapterIndex drives the chapter label and chapter list highlight.
  // It is set synchronously after loadBook() completes (not from player.position
  // at build-time, which can be transiently zero during setAudioSources).
  int _currentChapterIndex = 0;
  int _lastChapterIndex = 0; // shadow copy used only by the sleep-timer logic
  StreamSubscription<int?>? _chapterSub;
  StreamSubscription<Duration>? _posSub; // M4B: tracks chapter changes via position

  late final AudioVaultHandler _audioHandler;
  bool _didInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      _audioHandler = AudioHandlerScope.of(context).audioHandler;
      _speed = _audioHandler.player.speed;
      _loadSkipInterval();
      _loadBook();
      // currentIndexStream fires when the active track changes.
      // For M4B books the index is always 0 (single file), so we must NOT
      // use it to drive _currentChapterIndex — _posSub handles that instead.
      // For multi-file books there are no embedded chapters, so the track
      // index IS the chapter index and _posSub is not subscribed.
      _chapterSub = _audioHandler.player.currentIndexStream.listen((idx) {
        if (idx == null) return;
        if (widget.book.chapters.isEmpty && idx != _currentChapterIndex) {
          setState(() => _currentChapterIndex = idx);
        }
        if (idx != _lastChapterIndex) {
          if (_stopAtChapterEnd) {
            _audioHandler.pause();
            _cancelTimer();
          }
          setState(() => _lastChapterIndex = idx);
        }
      });

      // M4B: derive chapter from position stream, but only setState when
      // the chapter index actually changes (avoids rebuilds every 200 ms).
      if (widget.book.chapters.isNotEmpty) {
        _posSub = _audioHandler.effectivePositionStream.listen((pos) {
          if (!mounted) return;
          final idx = widget.book.chapterIndexAt(pos);
          if (idx != _currentChapterIndex) {
            setState(() => _currentChapterIndex = idx);
          }
        });
      }
    }
  }

  Future<void> _loadBook() async {
    final isNew = _audioHandler.currentBook?.path != widget.book.path;
    if (isNew) setState(() { _lastChapterIndex = 0; _currentChapterIndex = 0; });
    await _audioHandler.loadBook(widget.book);
    // loadBook has now positioned the player (either restored from DB or left
    // in place for the same book). Read the correct chapter index now and push
    // it to state — this is the first reliable moment to do so.
    if (mounted) {
      final pos = _audioHandler.player.position;
      final idx = widget.book.chapters.isNotEmpty
          ? widget.book.chapterIndexAt(pos)
          : (_audioHandler.player.currentIndex ?? 0);
      setState(() => _currentChapterIndex = idx);
    }
  }

  @override
  void dispose() {
    _chapterSub?.cancel();
    _posSub?.cancel();
    _sleepTimer?.cancel();
    super.dispose();
  }

  // ── Sleep timer ─────────────────────────────────────────────────────────────

  void _setTimer(_TimerOpt opt) {
    _cancelTimer();
    if (opt.endOfChapter) {
      setState(() => _stopAtChapterEnd = true);
      return;
    }
    if (opt.duration == null) return; // "Off"
    setState(() => _sleepRemaining = opt.duration!);
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = _sleepRemaining - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        _audioHandler.pause();
        _cancelTimer();
      } else {
        setState(() => _sleepRemaining = next);
      }
    });
  }

  void _cancelTimer() {
    _sleepTimer?.cancel();
    setState(() {
      _sleepTimer = null;
      _sleepRemaining = Duration.zero;
      _stopAtChapterEnd = false;
    });
  }

  // ── Cast device picker ───────────────────────────────────────────────────────

  static Future<bool> _vpnActive() async {
    try {
      final interfaces = await NetworkInterface.list();
      return interfaces.any((i) {
        final n = i.name.toLowerCase();
        return n.startsWith('tun') ||
            n.startsWith('ppp') ||
            n.startsWith('tap') ||
            n.startsWith('vpn');
      });
    } catch (_) {
      return false;
    }
  }

  Future<void> _showCastPicker() async {
    final discovery = GoogleCastDiscoveryManager.instance;
    final sessionManager = GoogleCastSessionManager.instance;

    final vpn = await _vpnActive();
    await discovery.startDiscovery();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cast to device'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (vpn)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 20,
                          color: Theme.of(ctx).colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'A VPN connection is active. This may prevent '
                          'casting from working correctly.',
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                color: Theme.of(ctx).colorScheme.error,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              Flexible(
                child: StreamBuilder<List<GoogleCastDevice>>(
                  stream: discovery.devicesStream,
                  initialData: discovery.devices,
                  builder: (ctx, snap) {
                    final devices = snap.data ?? [];
                    if (devices.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Text('Scanning for devices…'),
                          ],
                        ),
                      );
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: devices.length,
                      itemBuilder: (ctx, i) {
                        final device = devices[i];
                        return ListTile(
                          leading: const Icon(Icons.cast),
                          title: Text(device.friendlyName),
                          subtitle: device.modelName != null
                              ? Text(device.modelName!)
                              : null,
                          onTap: () {
                            sessionManager.startSessionWithDevice(device);
                            Navigator.of(ctx).pop();
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    await discovery.stopDiscovery();
  }

  // ── Skip interval ────────────────────────────────────────────────────────────

  Future<void> _loadSkipInterval() async {
    final s = await locator<PreferencesService>().getSkipInterval();
    _audioHandler.updateSkipInterval(s);
    if (mounted) setState(() => _skipInterval = s);
  }

  IconData get _rewindIcon {
    switch (_skipInterval) {
      case 10: return Icons.replay_10_rounded;
      case 30: return Icons.replay_30_rounded;
      default: return Icons.replay_rounded;
    }
  }

  IconData? get _forwardIcon {
    switch (_skipInterval) {
      case 10: return Icons.forward_10_rounded;
      case 30: return Icons.forward_30_rounded;
      default: return null; // use mirrored replay icon
    }
  }

  // ── Speed ────────────────────────────────────────────────────────────────────

  /// Formats a speed value as e.g. "1.0×", "1.25×", "0.75×".
  static String _fmtSpeed(double s) {
    final str = s.toStringAsFixed(2);
    return '${str.endsWith('0') ? s.toStringAsFixed(1) : str}×';
  }

  void _showSpeedDialog() {
    double tempSpeed = _speed;
    final originalSpeed = _speed;

    showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final theme = Theme.of(ctx);
          return AlertDialog(
            title: const Text('Playback speed'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _fmtSpeed(tempSpeed),
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Slider(
                  value: tempSpeed,
                  min: 0.5,
                  max: 3.0,
                  divisions: 50, // 0.05× steps
                  onChanged: (v) {
                    setDialogState(() => tempSpeed = v);
                    _audioHandler.setSpeed(v);
                  },
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  children: _commonSpeeds.map((s) {
                    final active = (tempSpeed - s).abs() < 0.01;
                    return ChoiceChip(
                      label: Text(_fmtSpeed(s)),
                      selected: active,
                      onSelected: (_) {
                        setDialogState(() => tempSpeed = s);
                        _audioHandler.setSpeed(s);
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _audioHandler.setSpeed(originalSpeed);
                  Navigator.pop(ctx, false);
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        setState(() => _speed = tempSpeed);
      } else {
        setState(() => _speed = originalSpeed);
      }
    });
  }

  // ── Custom sleep timer ────────────────────────────────────────────────────────

  Future<void> _showCustomTimerDialog() async {
    int minutes = 20;
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final theme = Theme.of(ctx);
          return AlertDialog(
            title: const Text('Custom sleep timer'),
            content: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_rounded),
                  onPressed: minutes > 1
                      ? () => setDialogState(() => minutes--)
                      : null,
                ),
                SizedBox(
                  width: 88,
                  child: Text(
                    '$minutes min',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_rounded),
                  onPressed: minutes < 180
                      ? () => setDialogState(() => minutes++)
                      : null,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, minutes),
                child: const Text('Set'),
              ),
            ],
          );
        },
      ),
    );
    if (result != null) {
      _setTimer((
        label: '$result min',
        duration: Duration(minutes: result),
        endOfChapter: false,
      ));
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _fmtHM(Duration d) {
    if (d < Duration.zero) d = Duration.zero;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String get _timerLabel {
    if (_stopAtChapterEnd) return 'End of ch.';
    if (_sleepTimer != null) return _fmtHM(_sleepRemaining);
    return 'Off';
  }

  bool get _timerActive => _sleepTimer != null || _stopAtChapterEnd;

  Future<void> _showChapterList(BuildContext context) async {
    final book = widget.book;
    final isM4b = book.chapters.isNotEmpty;
    final chapCount = isM4b ? book.chapters.length : book.audioFiles.length;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (ctx, scrollCtrl) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Chapters',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  // The chapter list is a StatefulWidget-scoped sheet, so it
                  // can't subscribe to streams itself. We pass _currentChapterIndex
                  // from state (which is already live-updated) and rebuild the
                  // sheet via setState whenever the chapter changes.
                  child: isM4b
                      ? _chapterListView(
                          scrollCtrl: scrollCtrl,
                          count: chapCount,
                          currentIndex: _currentChapterIndex,
                          title: (i) => book.chapters[i].title,
                          duration: (i) {
                            final start = book.chapters[i].start;
                            final end = i + 1 < book.chapters.length
                                ? book.chapters[i + 1].start
                                : (book.duration ?? Duration.zero);
                            return end > start ? end - start : null;
                          },
                          onTap: (i) {
                            _audioHandler.seek(book.chapters[i].start);
                            Navigator.of(context).pop();
                          },
                        )
                      : _chapterListView(
                          scrollCtrl: scrollCtrl,
                          count: chapCount,
                          currentIndex: _currentChapterIndex,
                          title: (i) => book.chapterNames.isNotEmpty
                              ? book.chapterNames[i]
                              : p.basenameWithoutExtension(book.audioFiles[i]),
                          duration: (i) => i < book.chapterDurations.length
                              ? book.chapterDurations[i]
                              : null,
                          onTap: (i) {
                            _audioHandler.player
                                .seek(Duration.zero, index: i);
                            Navigator.of(context).pop();
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _chapterListView({
    required ScrollController scrollCtrl,
    required int count,
    required int currentIndex,
    required String Function(int) title,
    required void Function(int) onTap,
    Duration? Function(int)? duration,
  }) {
    final theme = Theme.of(context);
    return ListView.builder(
      controller: scrollCtrl,
      itemCount: count,
      itemBuilder: (ctx, i) {
        final isCurrent = i == currentIndex;
        final dur = duration?.call(i);
        return ListTile(
          leading: isCurrent
              ? Icon(Icons.volume_up_rounded,
                  color: theme.colorScheme.primary, size: 20)
              : Text(
                  '${i + 1}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
          title: Text(
            title(i),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isCurrent ? FontWeight.bold : null,
              color: isCurrent ? theme.colorScheme.primary : null,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: dur != null && dur > Duration.zero
              ? Text(
                  _fmtHM(dur),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                )
              : null,
          onTap: () => onTap(i),
        );
      },
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = widget.book;
    final chapterCount = book.audioFiles.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          StreamBuilder<GoogleCastSession?>(
            stream: GoogleCastSessionManager.instance.currentSessionStream,
            builder: (context, _) {
              final connected =
                  GoogleCastSessionManager.instance.connectionState ==
                  GoogleCastConnectState.connected;
              return IconButton(
                tooltip: connected ? 'Stop casting' : 'Cast',
                icon: Icon(connected ? Icons.cast_connected : Icons.cast),
                color: connected ? Theme.of(context).colorScheme.primary : null,
                onPressed: connected
                    ? GoogleCastSessionManager.instance.endSessionAndStopCasting
                    : _showCastPicker,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // ── Cover ──
              Expanded(
                flex: 5,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BookCover(book: widget.book, iconSize: 80),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // ── Title / author / chapter ──
              _infoSection(book, chapterCount, theme),
              const SizedBox(height: 12),
              // ── Progress slider ──
              _progressSection(book, theme),
              const SizedBox(height: 8),
              // ── Playback controls ──
              _controlsSection(theme),
              const SizedBox(height: 12),
              // ── Speed + timer ──
              _bottomRow(theme),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ── Info section ───────────────────────────────────────────────────────────

  Widget _infoSection(Audiobook book, int chapterCount, ThemeData theme) {
    final isM4b = book.chapters.isNotEmpty;
    final totalChapters = isM4b ? book.chapters.length : chapterCount;
    final hasChapters = totalChapters > 1;

    String? chapterTitle(int currentIndex) {
      if (isM4b) return book.chapters[currentIndex].title;
      if (book.chapterNames.isNotEmpty &&
          currentIndex < book.chapterNames.length) {
        return book.chapterNames[currentIndex];
      }
      return null;
    }

    Widget chapterLabel(int currentIndex) => GestureDetector(
          onTap: hasChapters ? () => _showChapterList(context) : null,
          child: Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Chapter ${currentIndex + 1} of $totalChapters',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                  if (hasChapters) ...[
                    const SizedBox(width: 2),
                    Icon(Icons.expand_more_rounded,
                        size: 16, color: theme.colorScheme.primary),
                  ],
                ],
              ),
              if (chapterTitle(currentIndex) case final title?)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.75),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        );

    return Column(children: [
      Text(
        book.title,
        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
      if (book.author != null) ...[
        const SizedBox(height: 4),
        Text(
          book.author!,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
      ],
      if (hasChapters) ...[
        const SizedBox(height: 4),
        // _currentChapterIndex is kept up-to-date by stream subscriptions set up
        // in didChangeDependencies, and seeded synchronously after loadBook().
        // Using state directly avoids a one-frame flash to chapter 1 that occurred
        // when StreamBuilder initialData read player.position during setAudioSources.
        chapterLabel(_currentChapterIndex),
      ],
    ]);
  }

  // ── Progress section ───────────────────────────────────────────────────────

  Widget _progressSection(Audiobook book, ThemeData theme) {
    final isM4b = book.chapters.isNotEmpty;
    return StreamBuilder<Duration?>(
      stream: _audioHandler.effectiveDurationStream,
      initialData: _audioHandler.player.duration,
      builder: (_, durSnap) {
        final dur = durSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: _audioHandler.effectivePositionStream,
          initialData: _audioHandler.player.position,
          builder: (_, posSnap) {
            final pos = posSnap.data ?? Duration.zero;
            final displayed = _dragging ? _dragPosition : pos;
            final maxMs = dur.inMilliseconds.toDouble();
            final value = maxMs > 0
                ? displayed.inMilliseconds.toDouble().clamp(0.0, maxMs)
                : 0.0;

            // Snap to whole seconds so both labels always tick together
            final displayedSec =
                Duration(seconds: displayed.inSeconds);

            // Chapter-scoped elapsed and remaining.
            // Use raw `displayed` (not second-snapped) for chapter lookup so we
            // don't land one chapter behind when position is just past a boundary
            // that doesn't fall on a whole second (e.g. chapters[4].start=1574007ms
            // but displayedSec=1574000ms would return chapter 3 for ~1 second).
            final Duration chapterElapsed;
            final Duration chapterRemaining;
            if (isM4b) {
              final chIdx = book.chapterIndexAt(displayed);
              final chStart = book.chapters[chIdx].start;
              final chEnd = (chIdx + 1 < book.chapters.length)
                  ? book.chapters[chIdx + 1].start
                  : dur;
              // Clamp elapsed to zero: displayedSec can be slightly before chStart
              // in the first sub-second after a seek to a non-second-aligned boundary.
              chapterElapsed = displayedSec > chStart
                  ? displayedSec - chStart
                  : Duration.zero;
              chapterRemaining = chEnd > displayedSec
                  ? chEnd - displayedSec
                  : Duration.zero;
            } else {
              // Multi-file: just_audio 0.10 exposes global position and total
              // duration via setAudioSources, so we compute chapter-relative
              // elapsed/remaining from chapterDurations + _currentChapterIndex.
              if (book.chapterDurations.isNotEmpty) {
                int startMs = 0;
                for (int i = 0; i < _currentChapterIndex; i++) {
                  startMs += book.chapterDurations[i].inMilliseconds;
                }
                final chapStart = Duration(milliseconds: startMs);
                final chapDur = _currentChapterIndex < book.chapterDurations.length
                    ? book.chapterDurations[_currentChapterIndex]
                    : Duration.zero;
                final chapEnd = chapStart + chapDur;
                chapterElapsed =
                    displayedSec > chapStart ? displayedSec - chapStart : Duration.zero;
                chapterRemaining =
                    chapEnd > displayedSec ? chapEnd - displayedSec : Duration.zero;
              } else {
                // chapterDurations not populated — fall back to book-level times.
                chapterElapsed = displayedSec;
                chapterRemaining = dur - displayedSec;
              }
            }

            return Column(children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                ),
                child: Slider(
                  value: value,
                  min: 0,
                  max: maxMs > 0 ? maxMs : 1,
                  onChangeStart: (_) => setState(() => _dragging = true),
                  onChanged: (v) =>
                      setState(() => _dragPosition = Duration(milliseconds: v.toInt())),
                  onChangeEnd: (v) {
                    setState(() => _dragging = false);
                    _audioHandler.seek(Duration(milliseconds: v.toInt()));
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_fmtHM(chapterElapsed),
                        style: theme.textTheme.bodySmall),
                    Text('-${_fmtHM(chapterRemaining)}',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ]);
          },
        );
      },
    );
  }

  // ── Controls ───────────────────────────────────────────────────────────────

  Widget _controlsSection(ThemeData theme) {
    return StreamBuilder<PlaybackState>(
      stream: _audioHandler.playbackState,
      builder: (_, snap) {
        final state = snap.data;
        final playing = state?.playing ?? false;
        final busy = state?.processingState == AudioProcessingState.loading ||
            state?.processingState == AudioProcessingState.buffering;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _iconBtn(Icons.skip_previous_rounded, 34, _audioHandler.skipToPrevious),
            _iconBtn(_rewindIcon, 34, _audioHandler.rewind),
            // Central play/pause button
            GestureDetector(
              onTap: playing ? _audioHandler.pause : _audioHandler.play,
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: busy
                      ? SizedBox(
                          width: 28, height: 28,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: theme.colorScheme.onPrimary))
                      : Icon(
                          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 38,
                          color: theme.colorScheme.onPrimary,
                        ),
                ),
              ),
            ),
            _forwardIcon != null
                ? _iconBtn(_forwardIcon!, 34, _audioHandler.fastForward)
                : IconButton(
                    iconSize: 34,
                    icon: Transform.scale(
                      scaleX: -1,
                      child: const Icon(Icons.replay_rounded),
                    ),
                    onPressed: _audioHandler.fastForward,
                  ),
            _iconBtn(Icons.skip_next_rounded, 34, _audioHandler.skipToNext),
          ],
        );
      },
    );
  }

  Widget _iconBtn(IconData icon, double size, VoidCallback onTap) => IconButton(
        iconSize: size,
        icon: Icon(icon),
        onPressed: onTap,
      );

  // ── Speed + timer row ──────────────────────────────────────────────────────

  Widget _bottomRow(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Speed
        GestureDetector(
          onTap: _showSpeedDialog,
          child: _chip(
            icon: Icons.speed_rounded,
            label: _fmtSpeed(_speed),
            active: (_speed - 1.0).abs() > 0.001,
            theme: theme,
          ),
        ),
        // Sleep timer
        PopupMenuButton<int>(
          tooltip: 'Sleep timer',
          onSelected: (i) {
            if (i == _timerOpts.length) {
              _showCustomTimerDialog();
            } else {
              _setTimer(_timerOpts[i]);
            }
          },
          itemBuilder: (_) => [
            ...List.generate(
              _timerOpts.length,
              (i) => PopupMenuItem(
                value: i,
                child: Text(_timerOpts[i].label),
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: _timerOpts.length,
              child: const Text('Custom…'),
            ),
          ],
          child: _chip(
            icon: Icons.timer_rounded,
            label: _timerLabel,
            active: _timerActive,
            theme: theme,
          ),
        ),
      ],
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required bool active,
    required ThemeData theme,
  }) {
    final color = active ? theme.colorScheme.primary : theme.colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: active
            ? theme.colorScheme.primary.withValues(alpha: 0.15)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: color)),
        const SizedBox(width: 4),
        Icon(Icons.arrow_drop_down, size: 16, color: color),
      ]),
    );
  }
}
