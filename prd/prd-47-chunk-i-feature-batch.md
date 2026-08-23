# prd-47 — Chunk I: Feature Batch (R13, R17, R22) + Deferred (R18, R21)

Status: [ ] not started / [x] done
Branches: `feature/enrichment-author-search`, `feature/responsive-library-grid`,
`feature/drive-nested-scan` (one per feature per CLAUDE.md).

## R13 Enrichment author-aware search
- enrichment_service._fetchCoverForTitle(title): add optional author param;
  query `?title=...&author=...&limit=1`; fallback to title-only query when
  author-only result empty OR zero docs. Keep isValidCoverResponse gate.
- Callers pass book.author. Tests: fake client asserting URL params +
  fallback behavior.

## R17 Responsive grid columns
- library grid: crossAxisCount = clamp((maxWidth / ~180dp).floor(), 2, 5)
  (tune constant); childAspectRatio stays square via computed extent already
  present (LayoutBuilder). Persist nothing (pure layout).
- Widget test with different surface sizes asserting item widths/columns via
  LayoutBuilder harness or golden-less geometry probe.

## R22 Drive nested scan parity
- drive_service.scanRootFolder currently treats each subfolder of root as ONE
  book. Add recursion mirroring ScannerService._scanAsBookOrAuthorFolder:
  folder w/o audio but w/ subfolders → descend (depth ≤3 total like local).
  Return flattened DriveFolderScan list. rescanDrive unchanged downstream.
- Unit tests w/ fakes for nesting shapes (book/author-book/author-series-book,
  empty folders ignored, depth cap).

## R18 DB restructure (DEFERRED w/ rationale)
Move drive_* tables out of positions DB → own `kowhai_library.db` + drop
sharedDb exposure. Requires migration v5 + repo surgery across 4 services.
Deferred until after Chunks D–G settle schema consumers; revisit as its own PRD.
NOTE alternative accepted now: rename conceptual doc comments to reflect shared
"library DB" reality (cheap honesty fix — fold into Chunk B docs pass if trivial).

## R21 MANAGE_EXTERNAL_STORAGE→SAF (OUT OF SCOPE this cycle)
Sideload/GitHub-release distribution model makes current permission acceptable.
Reopen only when Play distribution is a goal. Kept here so the decision is
recorded, not lost.
