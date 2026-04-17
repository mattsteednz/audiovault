# PRD-32 (P3): Library sort menu

## Problem
The library is always sorted by last-played → alphabetical. Users with large collections want to sort by title, author, date added, or duration. There's no UI to change this.

## Evidence
- `lib/screens/library_screen.dart` — `_applySort()` hardcoded order

## Proposed Solution
- Add a sort menu (PopupMenuButton) in the AppBar with options: Last played, Title (A–Z), Author (A–Z), Date added, Duration.
- Persist selection via `PreferencesService` under `library_sort`.
- Refactor `_applySort` to take a `LibrarySortOrder` enum.
- Default stays "Last played".

## Acceptance Criteria
- [ ] Sort menu appears in AppBar
- [ ] Selection persists across app restarts
- [ ] Each sort option produces the documented order in unit tests

## Out of Scope
- Group-by (author, series).
