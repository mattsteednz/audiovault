# PRD-28 (P3): Visual feedback during cover enrichment

## Problem
After a scan, covers download silently in the background. Users watching the grid see covers appear at random — and a book with no cover looks identical whether it's "no cover found" or "still fetching".

## Evidence
- `lib/services/enrichment_service.dart` emits state but nothing in `AudiobookCard` / `AudiobookListTile` reflects it

## Proposed Solution
- Expose an `enrichingBookIds` stream (or set) from `EnrichmentService`.
- `AudiobookCard` / `AudiobookListTile` show a subtle shimmer or spinner overlay on the placeholder cover while the book is enriching.
- After first failed attempt, fall back to a distinct "no cover" placeholder icon.

## Acceptance Criteria
- [ ] Placeholder differentiates "fetching" vs "no cover available"
- [ ] Shimmer stops when enrichment finishes for that book
- [ ] No regression in scroll performance

## Out of Scope
- Manual "refetch cover" button (separate enhancement).
