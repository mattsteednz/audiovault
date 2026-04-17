# PRD-17 (P1): Tests for DriveDownloadManager

## Problem
`DriveDownloadManager` orchestrates a 2-concurrent download queue with retry logic and state. It has zero automated test coverage, and bugs here surface only in production when users sync large libraries.

## Evidence
- `lib/services/drive_download_manager.dart` — no corresponding file in `test/`

## Proposed Solution
- Add `test/services/drive_download_manager_test.dart`.
- Mock the download transport (file fetcher) behind an injectable interface.
- Cover:
  - concurrency limit enforced (never more than 2 in flight)
  - retries on transient failure, give-up after N attempts
  - cancellation drains in-flight jobs
  - completion order reflects queue + concurrency
  - error state is exposed to observers

## Acceptance Criteria
- [ ] New test file, all cases green
- [ ] Coverage for `DriveDownloadManager` > 80% lines
- [ ] No real network calls in tests

## Out of Scope
- Refactoring the manager beyond minimum injectability changes.
