# PRD-25 (P2): Empty-state UI for the library

## Problem
When the library is empty or no folder is set, users see a blank grid with a small "No library folder set." error — no guidance and no CTA to fix it. First-run and post-uninstall-reinstall UX feels broken.

## Evidence
- `lib/screens/library_screen.dart` — body renders grid/list or error text only

## Proposed Solution
- Add a dedicated `_LibraryEmptyState` widget shown when `_books.isEmpty`.
- Three variants:
  - no folder set → icon + copy + "Add a folder" button → Settings.
  - folder set but 0 books found → "No audiobooks found in <folder>" + Rescan button + tip about supported formats.
  - Drive configured but empty → CTA to reconfigure Drive.
- Use Material 3 typography and container colors from the theme.

## Acceptance Criteria
- [ ] Fresh install + no folder → CTA visible, tapping opens Settings
- [ ] Valid folder, 0 books → distinct message + rescan works
- [ ] Covered by widget test (see PRD-19)

## Out of Scope
- Animated illustrations.
