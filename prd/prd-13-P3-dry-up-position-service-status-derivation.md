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
