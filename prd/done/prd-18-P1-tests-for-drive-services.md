# PRD-18 (P1): Tests for Drive services (auth, library, repository)

## Problem
`DriveService`, `DriveLibraryService`, and `DriveBookRepository` form the entire Google Drive integration. None has automated tests, so regressions in auth session handling, folder scanning, or DB writes are caught only manually.

## Evidence
- `lib/services/drive_service.dart`
- `lib/services/drive_library_service.dart`
- `lib/services/drive_book_repository.dart`
- No matching files in `test/services/`

## Proposed Solution
- Introduce a thin `DriveApi` seam (interface) and inject it so tests can use a fake.
- Add `test/services/drive_service_test.dart`: sign-in success/failure, session restore, sign-out clears state.
- Add `test/services/drive_library_service_test.dart`: scanning nested folders, filtering audio extensions, pagination.
- Add `test/services/drive_book_repository_test.dart`: insert/update/delete, idempotent resync, FK cascades.
- Use `sqflite_common_ffi` for in-memory DB in repository tests.

## Acceptance Criteria
- [ ] Three new test files, all green
- [ ] No real Drive API calls, no real filesystem writes outside temp dirs
- [ ] Core success and error paths covered

## Out of Scope
- Full end-to-end tests against live Drive.
