import 'dart:ui' show ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../models/audiobook.dart';
import '../services/audio_handler.dart';
import '../utils/formatters.dart';
import '../widgets/audio_handler_scope.dart';
import '../widgets/book_cover.dart';
import '../screens/player_screen.dart';

// ── Mini player ───────────────────────────────────────────────────────────────

/// Compact now-playing bar above the bottom of the library.
///
/// Rebuild structure (perf-sensitive — this sits under every library frame):
/// * outer [StreamBuilder<PlaybackState>] rebuilds on play/pause/book changes
///   only; owns the blur surface, cover, title and transport button.
/// * position ticks (~5 Hz) repaint ONLY [_MiniProgress], a tiny subtree with
///   the 2px bar and the "x left" label. The BackdropFilter is deliberately
///   outside any per-tick subtree — rebuilding it re-blurs every frame.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

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
            // Thin progress bar + remaining label — the only per-tick parts.
            _MiniProgress(ah: ah, book: book),
            ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Material(
                  color: theme.colorScheme.surface.withValues(alpha: 0.85),
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
                                    child: BookCover(
                                        book: book,
                                        iconSize: 28,
                                        decodeSize: 144),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
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
                                  _MiniRemainingLabel(ah: ah, book: book),
                                ],
                              ),
                            ),
                            // Circular play/pause button — mirrors the
                            // player screen's primary-coloured circle.
                            Semantics(
                              button: true,
                              label: playing ? 'Pause' : 'Play',
                              child: GestureDetector(
                                onTap: playing ? ah.pause : ah.play,
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Icon(
                                      playing
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      size: 26,
                                      color: theme.colorScheme.onPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ), // InkWell
                ), // Material
              ), // BackdropFilter
            ), // ClipRect
          ],
        );
      },
    );
  }
}

/// The position-dependent slice of the mini player: progress bar only.
/// Subscribes to the effective-position stream; everything else is static
/// for the life of the current book.
class _MiniProgress extends StatelessWidget {
  final KowhaiHandler ah;
  final Audiobook book;

  const _MiniProgress({required this.ah, required this.book});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<Duration>(
      stream: ah.effectivePositionStream,
      builder: (_, posSnap) {
        final position = posSnap.data ?? Duration.zero;
        final totalMs = book.duration?.inMilliseconds.toDouble() ?? 0;
        final idx = ah.isCasting ? 0 : (ah.player.currentIndex ?? 0);
        final globalMs = calculateGlobalPosition(
          chapterIndex: idx,
          chapterPosition: position,
          chapterDurations: book.chapterDurations,
        );
        return LinearProgressIndicator(
          value: totalMs > 0 ? (globalMs / totalMs).clamp(0.0, 1.0) : 0,
          minHeight: 2,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        );
      },
    );
  }
}

/// "Xh Ym left" label, rebuilt per tick independently of the bar.
class _MiniRemainingLabel extends StatelessWidget {
  final KowhaiHandler ah;
  final Audiobook book;

  const _MiniRemainingLabel({required this.ah, required this.book});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<Duration>(
      stream: ah.effectivePositionStream,
      builder: (_, posSnap) {
        final totalMs = book.duration?.inMilliseconds;
        if (totalMs == null || totalMs == 0) return const SizedBox.shrink();
        final idx = ah.isCasting ? 0 : (ah.player.currentIndex ?? 0);
        final globalMs = calculateGlobalPosition(
          chapterIndex: idx,
          chapterPosition: posSnap.data ?? Duration.zero,
          chapterDurations: book.chapterDurations,
        );
        final remainingMs = (totalMs - globalMs).clamp(0, totalMs);
        return Text(
          '${fmtHourMin(Duration(milliseconds: remainingMs))} left',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        );
      },
    );
  }
}
