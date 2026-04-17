# PRD-8 (P1): Redact PII from debug logs

## Problem
`DriveService` logs the authenticated user's email via `debugPrint`. On Android, `debugPrint` output can be captured by logcat readers, bug-report archives, and third-party log aggregators. User email is PII and should not leak into logs even in debug builds.

## Evidence
- `lib/services/drive_service.dart:87` — `debugPrint('[Drive] Session restored: ${_account!.email}')`
- `lib/services/drive_service.dart:107` — similar email log on sign-in

## Proposed Solution
- Remove email from log strings entirely, or mask as `a***@domain.com`.
- Audit all `debugPrint`/`print` calls in `lib/` for PII (emails, folder names that may contain names, tokens).
- Add a tiny `_redactEmail(String)` helper in a shared logging util if masking is preferred over removal.

## Acceptance Criteria
- [ ] No full email appears in `debugPrint` output anywhere in `lib/`
- [ ] Verified with `grep -rn 'email' lib/ | grep -i 'print\|log'`
- [ ] Drive sign-in/session-restore flows still log a meaningful event (e.g. `[Drive] Session restored`)

## Out of Scope
- Structured logging framework migration.
