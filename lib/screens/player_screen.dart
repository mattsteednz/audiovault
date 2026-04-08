import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:path/path.dart' as p;
import '../models/audiobook.dart';
import '../services/audio_handler.dart';
import '../widgets/audio_handler_scope.dart';
import '../widgets/book_cover.dart';

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

  late final AudioVaultHandler _audioHandler;
  bool _didInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      _audioHandler = AudioHandlerScope.of(context).audioHandler;
      _loadBook();
      _chapterSub = _audioHandler.player.currentIndexStream.listen((idx) {
        if (idx != null && idx != _lastChapterIndex) {
          if (_stopAtChapterEnd) {
            _audioHandler.pause();
            _cancelTimer();
          }
          setState(() => _lastChapterIndex = idx);
        }
      });
    }
  }

  Future<void> _loadBook() async {
    final isNew = _audioHandler.currentBook?.path != widget.book.path;
    if (isNew) setState(() => _lastChapterIndex = 0);
    await _audioHandler.loadBook(widget.book);
    if (isNew) _audioHandler.play();
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
                  child: isM4b
                      ? StreamBuilder<Duration>(
                          stream: _audioHandler.effectivePositionStream,
                          builder: (ctx, snap) {
                            final pos = snap.data ?? Duration.zero;
                            final currentIdx =
                                book.chapterIndexAt(pos);
                            return _chapterListView(
                              scrollCtrl: scrollCtrl,
                              count: chapCount,
                              currentIndex: currentIdx,
                              title: (i) => book.chapters[i].title,
                              onTap: (i) {
                                _audioHandler.seek(book.chapters[i].start);
                                Navigator.of(ctx).pop();
                              },
                            );
                          },
                        )
                      : StreamBuilder<int?>(
                          stream: _audioHandler.player.currentIndexStream,
                          builder: (ctx, snap) {
                            final currentIdx = snap.data ?? 0;
                            return _chapterListView(
                              scrollCtrl: scrollCtrl,
                              count: chapCount,
                              currentIndex: currentIdx,
                              title: (i) => p.basenameWithoutExtension(
                                  book.audioFiles[i]),
                              onTap: (i) {
                                _audioHandler.player
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
            stream: _audioHandler.effectivePositionStream,
            builder: (_, snap) {
              final pos = snap.data ?? Duration.zero;
              final idx = book.chapterIndexAt(pos);
              return chapterLabel(idx);
            },
          )
        else
          // For multi-file: use just_audio's current index
          StreamBuilder<int?>(
            stream: _audioHandler.player.currentIndexStream,
            builder: (_, snap) => chapterLabel(snap.data ?? 0),
          ),
      ],
    ]);
  }

  // ── Progress section ───────────────────────────────────────────────────────

  Widget _progressSection(Audiobook book, ThemeData theme) {
    final isM4b = book.chapters.isNotEmpty;
    return StreamBuilder<Duration?>(
      stream: _audioHandler.effectiveDurationStream,
      builder: (_, durSnap) {
        final dur = durSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: _audioHandler.effectivePositionStream,
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
            _iconBtn(Icons.replay_30_rounded, 34, _audioHandler.rewind),
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
            _iconBtn(Icons.forward_30_rounded, 34, _audioHandler.fastForward),
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
        PopupMenuButton<double>(
          tooltip: 'Playback speed',
          onSelected: (s) {
            setState(() => _speed = s);
            _audioHandler.setSpeed(s);
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
