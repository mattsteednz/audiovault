# PRD-20 (P2): Widget tests for PlayerScreen controls

## Problem
PlayerScreen drives sleep timer, playback speed, skip intervals, and chapter navigation. These are stateful UIs that depend on the audio handler — untested, so a small handler refactor can break user-visible behaviour.

## Evidence
- `lib/screens/player_screen.dart`
- No `test/screens/player_screen_test.dart`

## Proposed Solution
- Use a fake `PlaybackController` (from PRD-12) or a mocked `AudioHandler`.
- Cover:
  - play/pause toggle updates the icon
  - skip forward/backward invokes handler with configured interval
  - chapter next/prev disabled at boundaries
  - sleep timer counts down and clears when expired/cancelled
  - speed slider persists to preferences

## Acceptance Criteria
- [ ] New test file, all cases green
- [ ] Runs without real audio decoding

## Out of Scope
- Integration tests with actual audio playback.
