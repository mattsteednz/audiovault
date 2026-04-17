# PRD-19 (P1): Widget tests for LibraryScreen

## Problem
LibraryScreen is the app's home — search, status filter pills, grid/list toggle, mini player, refresh, error banner. No widget tests exist, so any refactor risks breaking filtering or sort behaviour silently.

## Evidence
- `lib/screens/library_screen.dart`
- No `test/screens/library_screen_test.dart`

## Proposed Solution
- Introduce widget tests with fakes for `ScannerService`, `PositionService`, `PreferencesService`, and `AudioHandler`.
- Cover:
  - renders grid and list views; toggle switches
  - search filters by title and author
  - status pills filter correctly; combined filter+search (see PRD-31)
  - empty state (once PRD-25 lands) renders
  - error banner shows friendly message (see PRD-26)
  - mini player appears when a book is active

## Acceptance Criteria
- [ ] New test file under `test/screens/`
- [ ] All cases green via `flutter test`
- [ ] No dependency on real filesystem or Drive

## Out of Scope
- Golden-image tests.
