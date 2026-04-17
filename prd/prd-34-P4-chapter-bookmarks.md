# PRD-34 (P4): Chapter bookmarks

## Problem
The app only tracks a single "current position" per book. Users can't mark a quote or interesting section to return to later. For long audiobooks this is a meaningful gap versus competing apps.

## Evidence
- `PositionService` stores only current position, not bookmarks
- No UI affordance for marking

## Proposed Solution
- Extend `PositionService` schema with a `bookmarks` table (`book_id`, `chapter_index`, `position_ms`, `label?`, `created_at`).
- Add a bookmark button to PlayerScreen (floating action or AppBar); long-press to label.
- Add a bookmarks sheet listing bookmarks for the current book; tap to seek.
- Optional: show bookmarks as ticks on the scrubber.

## Acceptance Criteria
- [ ] Users can add, label, jump to, and delete bookmarks
- [ ] Bookmarks persist across app restarts
- [ ] Schema migration tested on existing DB

## Out of Scope
- Cloud sync of bookmarks.
