# PRD-12 (P2): Refactor AudioVaultHandler god class

## Problem
`AudioVaultHandler` mixes local playback, Google Cast state, position persistence, sleep timer, and completion handling in one 700+ line file. Adding features (bookmarks, queue, new cast targets) compounds complexity and makes testing difficult.

## Evidence
- `lib/services/audio_handler.dart` — ~763 lines, multiple responsibilities

## Proposed Solution
Split along responsibility lines, keeping `AudioVaultHandler` as thin orchestrator:
- `LocalPlaybackController` — wraps `just_audio` player, exposes play/pause/seek.
- `CastPlaybackController` — same interface, delegates to Cast SDK.
- `PlaybackRouter` — chooses active controller, forwards state.
- `SleepTimerController` — owns timer state + stream.
- `PositionPersister` — debounced writes to `PositionService`.

Introduce a common `PlaybackController` interface so UI binds to one contract regardless of source.

## Acceptance Criteria
- [ ] `audio_handler.dart` under 250 lines
- [ ] Each new class is independently unit-testable without a real player
- [ ] No behavioural regressions: play, pause, seek, chapter nav, sleep timer, cast handoff, position save all work

## Out of Scope
- Replacing `just_audio` or `audio_service`.
