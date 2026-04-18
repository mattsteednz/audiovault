# PRD-35 (P4): Queue management for multi-file books

## Problem
Multi-file books play sequentially with no quick jump to a specific file from the main player UI. Users have to open the chapter list every time — annoying for books with tens of files.

## Evidence
- `lib/screens/player_screen.dart` — chapter list lives behind a secondary action; no always-visible queue indicator

## Proposed Solution
- Add a horizontal "now playing" strip to PlayerScreen showing previous / current / next chapter with titles.
- Tap previous/next to jump; swipe to open the full chapter list.
- Persist last-visible queue position for scroll restoration.

## Acceptance Criteria
- [ ] Player shows adjacent chapter context without opening the full list
- [ ] Jumping to a neighbour saves position for the current chapter first
- [ ] Works for both single-file (M4B) and multi-file books

## Out of Scope
- Manual reordering of chapters.

## Implementation Plan
1. Expose current chapter index + `List<Chapter>` from the audio handler/`PlaybackStateController` as a `ValueListenable<({int index, List<Chapter> chapters})>`.
2. Build `lib/widgets/now_playing_strip.dart` — a horizontal `Row` with three `_ChapterPill`s (previous / current / next), each showing a truncated title and elapsed/total duration. Current pill is visually emphasised.
3. Tapping prev/next calls `audioHandler.skipToQueueItem(index ± 1)`; ensure the handler first saves the current chapter position via `PositionService` before seeking.
4. Swipe-up (or tap on current pill) opens the existing full chapter list sheet.
5. Handle edge cases: first chapter hides prev pill (or shows disabled); last chapter hides next. M4B single-file books expose chapters from metadata the same way — confirm `Chapter` model already uniform for single vs multi-file.
6. Persist the chapter-list scroll offset in a `ValueNotifier<double>` on the controller so reopening the sheet restores position.
7. Widget tests: multi-file book of 10 chapters → verify pill jumps save position; single-file M4B with chapter markers → verify same UI works.

## Files Impacted
- `lib/services/audio/playback_state_controller.dart` (expose chapter tuple)
- `lib/widgets/now_playing_strip.dart` (new)
- `lib/screens/player_screen.dart` (insert strip above controls; wire chapter sheet)
- `test/widgets/now_playing_strip_test.dart` (new)
