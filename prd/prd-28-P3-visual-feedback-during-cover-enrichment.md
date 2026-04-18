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

## Implementation Plan
1. In `EnrichmentService`, maintain `final _enrichingIds = ValueNotifier<Set<String>>({})`; add a book's id before its HTTP request and remove on completion/failure.
2. Also track `_failedIds` (book ids that finished enrichment with no cover) so the UI can distinguish "fetching" vs "no cover available".
3. Expose both via getters or `ValueListenable` for efficient per-card rebuilds.
4. In `AudiobookCard` / `AudiobookListTile`, wrap the placeholder with `ValueListenableBuilder` watching `_enrichingIds`; when `contains(book.id)`, render a Shimmer or a small `CircularProgressIndicator.adaptive` overlay.
5. If not enriching and cover is null and id is in `_failedIds`, render a distinct "no cover" icon (e.g. `Icons.image_not_supported`) vs the default placeholder for unprocessed books.
6. Verify scroll performance on a large fixture library (50+ books) — the ValueListenable approach avoids rebuilding the whole grid.
7. Add widget tests asserting shimmer presence during enrichment and icon swap afterwards.

## Files Impacted
- `lib/services/enrichment_service.dart` (enriching/failed id tracking)
- `lib/widgets/audiobook_card.dart` (overlay + placeholder swap)
- `lib/widgets/audiobook_list_tile.dart` (same)
- `test/widgets/audiobook_card_test.dart` (new/extended)
