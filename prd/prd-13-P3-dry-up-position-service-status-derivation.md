# PRD-13 (P3): DRY up BookStatus derivation in PositionService

## Problem
`getBookStatus()` and `getAllStatuses()` duplicate the globalPositionMs/totalDurationMs → BookStatus logic. A future threshold tweak has to be made in two places.

## Evidence
- `lib/services/position_service.dart:158-178` — `getBookStatus`
- `lib/services/position_service.dart:180-204` — `getAllStatuses` repeats same derivation

## Proposed Solution
- Extract `BookStatus _deriveStatus(int globalMs, int totalMs)` private helper.
- Both callers reuse it.
- Add a unit test for each boundary (unstarted, in-progress, near-end threshold, finished).

## Acceptance Criteria
- [ ] Single source of truth for status derivation
- [ ] Tests cover threshold boundaries
- [ ] No public API changes

## Out of Scope
- Changing the current thresholds.

## Implementation Plan
1. Read `getBookStatus` (lines 158-178) and `getAllStatuses` (lines 180-204) in `position_service.dart`; identify the exact thresholds (unstarted, in-progress, near-end, finished).
2. Add `static BookStatus _deriveStatus(int globalMs, int totalMs)` near the top of the class (kept private since callers are internal).
3. Replace the duplicated inline switch/if blocks in both methods with `_deriveStatus(globalMs, totalMs)`.
4. Add `test/services/position_service_status_test.dart` with parameterised cases: totalMs=0, globalMs=0, globalMs=1 (in-progress), globalMs at near-end boundary, globalMs >= totalMs (finished), globalMs > totalMs (overflow safety).
5. Run `flutter analyze` and `flutter test` to confirm no regressions.

## Files Impacted
- `lib/services/position_service.dart` (refactor)
- `test/services/position_service_status_test.dart` (new)
