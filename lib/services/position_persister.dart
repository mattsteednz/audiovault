import 'dart:async';
import '../models/audiobook.dart';
import 'position_service.dart';

/// A snapshot of where playback currently is — chapter index + offset
/// within that chapter. Source-agnostic: can come from the local player or
/// from a Cast device.
typedef PositionSnapshot = ({int chapterIndex, Duration position});

/// Owns position persistence for the currently-loaded book:
///
/// * periodic save every [interval] while [startPeriodic] is active
/// * one-shot [save] on demand (used on pause / stop / completion)
///
/// Source-agnostic by design — the caller injects [readPosition] and
/// [getBook] closures so the same class works for local playback, Cast
/// playback, or any future source.
class PositionPersister {
  PositionPersister({
    required this.positionService,
    required this.readPosition,
    required this.getBook,
    this.interval = const Duration(seconds: 5),
  });

  final PositionService positionService;
  final PositionSnapshot Function() readPosition;
  final Audiobook? Function() getBook;
  final Duration interval;

  Timer? _timer;

  bool get isRunning => _timer != null;

  /// Begin saving on every [interval] tick. Idempotent — calling twice
  /// doesn't stack timers.
  void startPeriodic() {
    _timer ??= Timer.periodic(interval, (_) => save());
  }

  /// Stop the periodic timer (if any). Does NOT perform a final save —
  /// callers typically want [save] right after.
  void stopPeriodic() {
    _timer?.cancel();
    _timer = null;
  }

  /// Save the current position right now. No-op if no book is loaded.
  Future<void> save() async {
    final book = getBook();
    if (book == null) return;
    final snap = readPosition();
    await positionService.savePosition(
      bookPath: book.path,
      chapterIndex: snap.chapterIndex,
      position: snap.position,
      globalPositionMs: calculateGlobalPosition(
        chapterIndex: snap.chapterIndex,
        chapterPosition: snap.position,
        chapterDurations: book.chapterDurations,
      ),
      totalDurationMs: book.duration?.inMilliseconds ?? 0,
    );
  }

  void dispose() => stopPeriodic();
}

/// Sums completed chapter durations + current chapter offset to produce a
/// book-wide elapsed position in milliseconds. Pure.
int calculateGlobalPosition({
  required int chapterIndex,
  required Duration chapterPosition,
  required List<Duration> chapterDurations,
}) {
  int offset = 0;
  for (int i = 0; i < chapterIndex && i < chapterDurations.length; i++) {
    offset += chapterDurations[i].inMilliseconds;
  }
  return offset + chapterPosition.inMilliseconds;
}
