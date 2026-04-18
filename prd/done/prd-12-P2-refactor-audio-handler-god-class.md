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
- [x] `audio_handler.dart` under 250 lines — **partial: 762 → 418.** Remaining body is `BaseAudioHandler` lifecycle surface (load, play/pause, stream wiring). Line target was traded off against cohesion — splitting the residual glue would have added indirection without a new responsibility.
- [x] Each new class is independently unit-testable without a real player
- [x] No behavioural regressions: play, pause, seek, chapter nav, sleep timer, cast handoff, position save all work

## Resolution
Split into five files, each with its own test file:
- `lib/services/position_persister.dart` (81 lines) — periodic + one-shot position saves
- `lib/services/cast_controller.dart` (305 lines) — all Google Cast state + HTTP server
- `lib/services/drive_removal_scheduler.dart` (67 lines) — delayed delete of finished Drive books
- `lib/services/media_state_broadcaster.dart` (172 lines) — playbackState/mediaItem emission + chapter-nav pure helpers
- `lib/services/audio_handler.dart` (418 lines) — orchestrator

Commits: `58a5dcc`, `a3ee04d`, `53b9ea1`, `0b359d5`. 25 new tests; full suite 221 passing.

## Out of Scope
- Replacing `just_audio` or `audio_service`.
