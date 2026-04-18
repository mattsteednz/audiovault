# PRD-33 (P3): Surface sleep-timer countdown outside PlayerScreen

## Problem
The sleep timer is only visible while on PlayerScreen. If a user sets a timer and navigates back to the library, they lose visibility into how much time is left.

## Evidence
- Sleep timer state lives in the audio handler but isn't rendered in the mini-player or library AppBar

## Proposed Solution
- Expose `sleepTimerRemaining` as a `ValueListenable<Duration?>` on the audio handler (or the `SleepTimerController` from PRD-12).
- In the mini-player, show a small moon icon + `mm:ss` remaining when active; tap opens a bottom sheet to extend/cancel.
- In the library AppBar, show the same indicator so it's visible even without the mini-player.

## Acceptance Criteria
- [ ] Timer visible and counting down on library + mini-player when active
- [ ] Tapping the indicator lets the user extend or cancel
- [ ] Clears from UI exactly when the timer fires

## Out of Scope
- Multiple concurrent timers.

## Implementation Plan
1. In `SleepTimerController` (from PRD-12 extraction) expose `ValueListenable<Duration?> remaining` that emits null when inactive and counts down once-per-second while active. Internally use a `Timer.periodic(Duration(seconds: 1))` that also handles fire and cancel.
2. Expose the controller via the global `audioHandler` (`audioHandler.sleepTimer`) so UI anywhere can subscribe.
3. Build a shared `SleepTimerIndicator` widget in `lib/widgets/sleep_timer_indicator.dart` — a small `Icon(Icons.bedtime) + mm:ss` Text — wrapped in a `ValueListenableBuilder`; renders `SizedBox.shrink()` when null.
4. Tapping the indicator opens a bottom sheet with "Extend 15m", "Extend 30m", "Cancel" actions that call the controller.
5. Embed the indicator:
   - In the library AppBar actions (before sort/search).
   - In the mini-player (between title and controls).
   - In the player screen (replace existing timer UI or keep the full control).
6. When the timer fires, ensure the controller sets `remaining.value = null` so all indicators disappear in the same frame.
7. Widget test: set a timer, pump frames, confirm countdown text updates; call cancel, confirm indicator disappears.

## Files Impacted
- `lib/services/audio/sleep_timer_controller.dart` (expose ValueListenable)
- `lib/widgets/sleep_timer_indicator.dart` (new)
- `lib/screens/library_screen.dart` (AppBar + mini-player integration)
- `lib/screens/player_screen.dart` (use shared indicator)
- `test/widgets/sleep_timer_indicator_test.dart` (new)
