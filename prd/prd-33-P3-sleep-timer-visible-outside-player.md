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
