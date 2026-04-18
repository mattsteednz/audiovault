import 'dart:async';

import 'package:flutter/foundation.dart';

/// Result of a sleep-timer tick: the new remaining time and whether the
/// timer should fire (invoke pause) this tick.
///
/// Pure function — exported for widget tests and the player screen's
/// own timer flow to share the boundary logic.
({Duration next, bool shouldFire}) sleepTimerTick(Duration current) {
  final nextMs = current.inMilliseconds - 1000;
  if (nextMs <= 0) return (next: Duration.zero, shouldFire: true);
  return (next: Duration(milliseconds: nextMs), shouldFire: false);
}

/// Shared sleep-timer state.
///
/// PlayerScreen starts/cancels the timer; LibraryScreen's AppBar and the
/// mini-player watch [remaining] / [stopAtChapterEnd] to show a countdown
/// indicator even when the player screen isn't mounted.
///
/// The timer itself runs here rather than in the audio handler so the fire
/// action (invoke pause) can be wired by the caller without the controller
/// depending on audio_service.
class SleepTimerController {
  SleepTimerController();

  Timer? _timer;

  /// Remaining duration for a timed sleep timer, or null when no timed
  /// timer is active. Updates once per second.
  final ValueNotifier<Duration?> remaining = ValueNotifier<Duration?>(null);

  /// True while the user has asked playback to stop at the end of the
  /// current chapter. PlayerScreen owns the chapter-boundary detection;
  /// this notifier only exposes the flag so other surfaces can render it.
  final ValueNotifier<bool> stopAtChapterEnd = ValueNotifier<bool>(false);

  /// True iff either form of sleep timer is currently active.
  bool get isActive => remaining.value != null || stopAtChapterEnd.value;

  /// Start (or replace) a timed sleep timer. [onFire] is invoked once, when
  /// the countdown reaches zero — typically to pause playback.
  void startTimed(Duration duration, {required VoidCallback onFire}) {
    cancel();
    if (duration <= Duration.zero) {
      onFire();
      return;
    }
    remaining.value = duration;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final cur = remaining.value;
      if (cur == null) return;
      final tick = sleepTimerTick(cur);
      if (tick.shouldFire) {
        _timer?.cancel();
        _timer = null;
        remaining.value = null;
        onFire();
      } else {
        remaining.value = tick.next;
      }
    });
  }

  /// Mark that playback should stop at the end of the current chapter.
  /// Clears any timed countdown — the two modes are mutually exclusive.
  void setStopAtChapterEnd(bool value) {
    if (value) {
      _timer?.cancel();
      _timer = null;
      remaining.value = null;
    }
    stopAtChapterEnd.value = value;
  }

  /// Cancel any active timer and reset both flags.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    remaining.value = null;
    stopAtChapterEnd.value = false;
  }

  @visibleForTesting
  void disposeForTesting() {
    _timer?.cancel();
    remaining.dispose();
    stopAtChapterEnd.dispose();
  }
}
