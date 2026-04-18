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

## Implementation Plan
1. Open `lib/services/scanner_service.dart`; inspect the recursion at line 87 to confirm "depth 0 = root" vs "depth 0 = first subfolder".
2. Trace `remainingDepth = 2` through the recursive call to compute the effective max depth (root + N levels).
3. Decide canonical convention: reconcile with CHANGELOG's "three levels deep"; update whichever is wrong.
4. Add `static const int maxScanDepth = 3;` (or correct value) at top of class with a doc comment describing the convention ("0 = library root, 3 = three levels of subfolders scanned").
5. Replace the literal `2` with `maxScanDepth - 1` (or matching value) so the depth budget is explicit.
6. Add a scanner unit test covering a 4-level-deep fixture to verify boundary behaviour.
7. Update `CHANGELOG.md` wording if implementation was correct.

## Files Impacted
- `lib/services/scanner_service.dart` (constant + doc comment)
- `CHANGELOG.md` (possibly)
- `test/services/scanner_service_test.dart` (new or extended)
