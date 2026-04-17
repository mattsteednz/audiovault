# PRD-26 (P2): User-friendly scan error messages

## Problem
When a scan fails, `LibraryScreen` shows `'Scan failed: $e'` — dumping raw exception text like `FileSystemException: Permission denied, path = '/storage/...'`. Users can't act on this.

## Evidence
- `lib/screens/library_screen.dart:249` — `_error = 'Scan failed: $e'`

## Proposed Solution
- Introduce typed scanner exceptions (`ScanPermissionDenied`, `ScanFolderMissing`, `ScanGeneric`) in `ScannerService`.
- Map each to a friendly message + suggested action in the UI:
  - permission → "Storage access denied. Grant permission in Settings." with deep-link button.
  - missing folder → "Library folder no longer exists. Choose a new folder."
  - generic → "Couldn't scan the library. Try again." with a retry button.
- Keep raw `$e` in `debugPrint` for diagnostics.

## Acceptance Criteria
- [ ] No raw exception text in UI
- [ ] Each error path tested (see PRD-19)
- [ ] Deep links / re-pick actions work on Android

## Out of Scope
- iOS permission wording (app is Android-first today).
