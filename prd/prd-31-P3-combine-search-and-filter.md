# PRD-31 (P3): Combine search and status filter in LibraryScreen

## Problem
Search (title/author) and status filter pills work independently. Users can't search within "In progress" — they must clear the filter first. In a large library this is friction.

## Evidence
- `lib/screens/library_screen.dart` — filter and search apply from separate state branches

## Proposed Solution
- Compose both filters in a single `_filteredBooks` computation: `books.where((b) => matchesStatus(b) && matchesQuery(b))`.
- When search is active and filter pills are selected, show both visual states together (no hidden state).
- If the combined result is empty, show an "No matches" inline message with a "Clear filters" button.

## Acceptance Criteria
- [ ] Search + pill filter work as AND
- [ ] "No matches" state renders when combined result is empty
- [ ] Covered in LibraryScreen test (PRD-19)

## Out of Scope
- Saved searches.
