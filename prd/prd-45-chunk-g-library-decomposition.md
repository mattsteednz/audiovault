# prd-45 — Chunk G: Library Screen Decomposition (R8)

Status: [ ] not started / [x] done
Branch: `chore/library-screen-decomposition`
DEPENDS ON: Chunk F (tracker refactor lands first to avoid double-churn).

## Goal
library_screen.dart = 1601 lines mixing orchestration + 4 sheets/overlays +
grid/list + empty states. Split into focused files WITHOUT behavior change.

## Target structure
lib/screens/library/
  library_screen.dart            (screen + state orchestration only)
  library_view_bar.dart          (count + summary + sort/filter buttons)
  library_filter_sheet.dart      (status+availability pills; expose show())
  library_sort_sheet.dart        (sort list; expose show())
  library_no_matches.dart        (combinatorial empty-match view)
  library_empty_state.dart       (unconfigured/no-books empty states)
  drive_scan_overlay.dart        (animated overlay, public class)
lib/widgets/library/
  (existing audiobook_card/list_tile stay put)

## Rules
- Pure helpers currently top-of-file move to `lib/utils/library_queries.dart`
  OR stay exported from a barrel — keep existing test imports working by
  re-exporting from library_screen.dart (`export '...'`) ONLY if needed;
  prefer updating imports in tests instead (tests are the only consumers).
- No logic edits in this chunk. If a bug is spotted, note it in prd file,
  don't fix here.
- Filter sheet internal StatefulBuilder may become a StatefulWidget as part of
  the MOVE only if it reduces passed-callback plumbing; otherwise copy verbatim.

## Tasks
- [ ] G1. Extract widgets/sheets file-by-file; compile after each extraction.
- [ ] G2. Update test imports (library_helpers/search/scan tests).
- [ ] G3. Final: library_screen.dart ≤ ~600 lines; all files <400 lines.
- [ ] G4. Gate green; manual smoke: scan/filter/sort/grid/list/empty states.

## Acceptance
No behavioral diff (widget tests + manual pass); file size targets met.
