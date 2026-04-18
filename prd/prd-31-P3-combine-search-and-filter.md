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

## Implementation Plan
1. In `_LibraryScreenState`, replace separate filter/search branches with a single derived getter:
   ```dart
   List<Audiobook> get _filteredBooks => _books.where((b) =>
     _matchesStatus(b, _statusFilter) && _matchesQuery(b, _searchQuery)).toList();
   ```
2. Ensure `_searchQuery` and `_statusFilter` both trigger `setState` on change; remove any code path that clears one when the other changes.
3. When `_filteredBooks.isEmpty` but `_books.isNotEmpty`, render an inline `_EmptyMatchesView` with message "No matches" and a "Clear filters" button that resets both state variables.
4. Keep the status-filter pill row and the search field visible simultaneously — no hidden state.
5. Extend existing LibraryScreen widget test (per PRD-19) with scenarios:
   - Search + "In progress" filter → only in-progress results matching query.
   - Search with no matches under filter → empty-state renders with clear action.
   - Tapping "Clear filters" resets both and restores full list.

## Files Impacted
- `lib/screens/library_screen.dart` (filter composition + empty state)
- `lib/widgets/` (possibly a new `_EmptyMatchesView` widget, or inline)
- `test/screens/library_screen_test.dart` (extended)
