# PRD-14 (P3): Make scanner recursion depth explicit and consistent

## Problem
`ScannerService` uses a hardcoded `remainingDepth = 2` while the CHANGELOG advertises scanning "up to three levels deep". Either the docs or the code is wrong; either way the magic number is opaque.

## Evidence
- `lib/services/scanner_service.dart:87` — `remainingDepth = 2`
- `CHANGELOG.md` — mentions "three levels deep"

## Proposed Solution
- Define `static const int maxScanDepth = <correct value>` with a doc comment explaining what "depth 0" means (root or first subfolder?).
- Reconcile with CHANGELOG; update whichever is wrong.
- Optional: expose as advanced setting if users with deeply-nested libraries complain.

## Acceptance Criteria
- [ ] No bare integer literal for depth in scan recursion
- [ ] Doc comment describes the counting convention
- [ ] CHANGELOG and code agree

## Out of Scope
- A full scanner rewrite.
