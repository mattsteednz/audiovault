# PRD-29 (P3): Disable player controls and surface retry on error

## Problem
If the audio player enters an error state (corrupt file, missing file, codec issue), the PlayerScreen keeps play/seek/skip buttons live. Users tap repeatedly and get no feedback.

## Evidence
- `lib/screens/player_screen.dart` — no handling of `ProcessingState.error` / `PlaybackException`

## Proposed Solution
- Listen to the handler's playback state / error stream.
- On error: disable play/pause/seek/skip buttons, dim chapter list, and show a snackbar/banner with the error message and a "Retry" action that reloads the current chapter.
- Log the underlying error via `TelemetryService.recordNonFatal` (consent-gated).

## Acceptance Criteria
- [ ] Controls disabled during error state
- [ ] Retry restores playback for recoverable errors (file still exists)
- [ ] Covered in PlayerScreen test (PRD-20)

## Out of Scope
- Auto-skip to next chapter on error.
