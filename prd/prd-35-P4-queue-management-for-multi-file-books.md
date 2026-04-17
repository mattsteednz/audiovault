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
