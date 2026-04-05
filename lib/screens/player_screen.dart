import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:path/path.dart' as p;
import '../main.dart';
import '../models/audiobook.dart';

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

const _speedOpts = [1.0, 1.1, 1.25, 1.5];

// ── Screen ────────────────────────────────────────────────────────────────────

class PlayerScreen extends StatefulWidget {
  final Audiobook book;
  const PlayerScreen({super.key, required this.book});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  double _speed = 1.0;

  // Sleep timer
  Timer? _sleepTimer;
  Duration _sleepRemaining = Duration.zero;
  bool _stopAtChapterEnd = false;

  // Progress slider drag state
  bool _dragging = false;
  Duration _dragPosition = Duration.zero;

  // Chapter tracking for "end of chapter" timer
  int _lastChapterIndex = 0;
  StreamSubscription<int?>? _chapterSub;

  @override
  void initState() {
    super.initState();
    _loadBook();
    _chapterSub = audioHandler.player.currentIndexStream.listen((idx) {
      if (idx != null && idx != _lastChapterIndex) {
        if (_stopAtChapterEnd) {
          audioHandler.pause();
          _cancelTimer();
        }
        setState(() => _lastChapterIndex = idx);
      }
    });
  }

  Future<void> _loadBook() async {
    final isNew = audioHandler.currentBook?.path != widget.book.path;
    if (isNew) setState(() => _lastChapterIndex = 0);
    await audioHandler.loadBook(widget.book);
    if (isNew) audioHandler.play();
  }

  @override
  void dispose() {
    _chapterSub?.cancel();
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
      if (_sleepRemaining <= Duration.zero) {
        audioHandler.pause();
        _cancelTimer();
      } else {
        setState(() => _sleepRemaining -= const Duration(seconds: 1));
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

  Future<void> _showCastPicker() async {
    final discovery = GoogleCastDiscoveryManager.instance;
    final sessionManager = GoogleCastSessionManager.instance;

    await discovery.startDiscovery();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cast to device'),
        content: SizedBox(
          width: double.maxFinite,
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
                        child: CircularProgressIndicator(strokeWidth: 2),
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
                    subtitle: device.modelName != null ? Text(device.modelName!) : null,
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

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  /// Formats a duration as m:ss (or h:mm:ss if >= 1 hour).
  String _fmtHM(Duration d) {
    if (d < Duration.zero) d = Duration.zero;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String get _timerLabel {
    if (_stopAtChapterEnd) return 'End of ch.';
    if (_sleepTimer != null) return _fmt(_sleepRemaining);
    return 'Off';
  }

  bool get _timerActive => _sleepTimer != null || _stopAtChapterEnd;

  // ── Chapter helpers ──────────────────────────────────────────────────────────

  /// For M4B books with embedded chapters, returns the index of the chapter
  /// that contains [position].
  int _m4bChapterAt(Duration position, List<Chapter> chapters) {
    int current = 0;
    for (int i = 0; i < chapters.length; i++) {
      if (position >= chapters[i].start) {
        current = i;
      } else {
        break;
      }
    }
    return current;
  }

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
                  child: isM4b
                      ? StreamBuilder<Duration>(
                          stream: audioHandler.player.positionStream,
                          builder: (ctx, snap) {
                            final pos = snap.data ?? Duration.zero;
                            final currentIdx =
                                _m4bChapterAt(pos, book.chapters);
                            return _chapterListView(
                              scrollCtrl: scrollCtrl,
                              count: chapCount,
                              currentIndex: currentIdx,
                              title: (i) => book.chapters[i].title,
                              onTap: (i) {
                                audioHandler.seek(book.chapters[i].start);
                                Navigator.of(ctx).pop();
                              },
                            );
                          },
                        )
                      : StreamBuilder<int?>(
                          stream: audioHandler.player.currentIndexStream,
                          builder: (ctx, snap) {
                            final currentIdx = snap.data ?? 0;
                            return _chapterListView(
                              scrollCtrl: scrollCtrl,
                              count: chapCount,
                              currentIndex: currentIdx,
                              title: (i) => p.basenameWithoutExtension(
                                  book.audioFiles[i]),
                              onTap: (i) {
                                audioHandler.player
                                    .seek(Duration.zero, index: i);
                                Navigator.of(ctx).pop();
                              },
                            );
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
  }) {
    final theme = Theme.of(context);
    return ListView.builder(
      controller: scrollCtrl,
      itemCount: count,
      itemBuilder: (ctx, i) {
        final isCurrent = i == currentIndex;
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
                      child: _coverWidget(theme),
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

  // ── Cover ──────────────────────────────────────────────────────────────────

  Widget _coverWidget(ThemeData theme) {
    if (widget.book.coverImageBytes != null) {
      return Image.memory(widget.book.coverImageBytes!, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _coverPlaceholder(theme));
    }
    if (widget.book.coverImagePath != null) {
      return Image.file(File(widget.book.coverImagePath!), fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _coverPlaceholder(theme));
    }
    return _coverPlaceholder(theme);
  }

  Widget _coverPlaceholder(ThemeData theme) => ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(Icons.menu_book_rounded, size: 80,
              color: theme.colorScheme.onSurfaceVariant),
        ),
      );

  // ── Info section ───────────────────────────────────────────────────────────

  Widget _infoSection(Audiobook book, int chapterCount, ThemeData theme) {
    final isM4b = book.chapters.isNotEmpty;
    final totalChapters = isM4b ? book.chapters.length : chapterCount;
    final hasChapters = totalChapters > 1;

    Widget chapterLabel(int currentIndex) => GestureDetector(
          onTap: hasChapters ? () => _showChapterList(context) : null,
          child: Row(
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
        if (isM4b)
          // For M4B: derive current chapter from playback position
          StreamBuilder<Duration>(
            stream: audioHandler.player.positionStream,
            builder: (_, snap) {
              final pos = snap.data ?? Duration.zero;
              final idx = _m4bChapterAt(pos, book.chapters);
              return chapterLabel(idx);
            },
          )
        else
          // For multi-file: use just_audio's current index
          StreamBuilder<int?>(
            stream: audioHandler.player.currentIndexStream,
            builder: (_, snap) => chapterLabel(snap.data ?? 0),
          ),
      ],
    ]);
  }

  // ── Progress section ───────────────────────────────────────────────────────

  Widget _progressSection(Audiobook book, ThemeData theme) {
    final isM4b = book.chapters.isNotEmpty;
    return StreamBuilder<Duration?>(
      stream: audioHandler.player.durationStream,
      builder: (_, durSnap) {
        final dur = durSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: audioHandler.player.positionStream,
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

            // Chapter-scoped elapsed and remaining
            final Duration chapterElapsed;
            final Duration chapterRemaining;
            if (isM4b) {
              final chIdx = _m4bChapterAt(displayedSec, book.chapters);
              final chStart = book.chapters[chIdx].start;
              final chEnd = (chIdx + 1 < book.chapters.length)
                  ? book.chapters[chIdx + 1].start
                  : dur;
              chapterElapsed = displayedSec - chStart;
              chapterRemaining = chEnd - displayedSec;
            } else {
              // MP3: positionStream/durationStream are already per-file
              chapterElapsed = displayedSec;
              chapterRemaining = dur - displayedSec;
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
                    audioHandler.seek(Duration(milliseconds: v.toInt()));
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
      stream: audioHandler.playbackState,
      builder: (_, snap) {
        final state = snap.data;
        final playing = state?.playing ?? false;
        final busy = state?.processingState == AudioProcessingState.loading ||
            state?.processingState == AudioProcessingState.buffering;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _iconBtn(Icons.skip_previous_rounded, 34, audioHandler.skipToPrevious),
            _iconBtn(Icons.replay_30_rounded, 34, audioHandler.rewind),
            // Central play/pause button
            GestureDetector(
              onTap: playing ? audioHandler.pause : audioHandler.play,
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
            _iconBtn(Icons.forward_30_rounded, 34, audioHandler.fastForward),
            _iconBtn(Icons.skip_next_rounded, 34, audioHandler.skipToNext),
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
        PopupMenuButton<double>(
          tooltip: 'Playback speed',
          onSelected: (s) {
            setState(() => _speed = s);
            audioHandler.setSpeed(s);
          },
          itemBuilder: (_) => _speedOpts
              .map((s) => PopupMenuItem(
                    value: s,
                    child: Row(children: [
                      if (s == _speed)
                        Icon(Icons.check, size: 18,
                            color: theme.colorScheme.primary)
                      else
                        const SizedBox(width: 18),
                      const SizedBox(width: 8),
                      Text('$s×'),
                    ]),
                  ))
              .toList(),
          child: _chip(
            icon: Icons.speed_rounded,
            label: '$_speed×',
            active: _speed != 1.0,
            theme: theme,
          ),
        ),
        // Sleep timer
        PopupMenuButton<int>(
          tooltip: 'Sleep timer',
          onSelected: (i) => _setTimer(_timerOpts[i]),
          itemBuilder: (_) => List.generate(
            _timerOpts.length,
            (i) => PopupMenuItem(
              value: i,
              child: Text(_timerOpts[i].label),
            ),
          ),
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
