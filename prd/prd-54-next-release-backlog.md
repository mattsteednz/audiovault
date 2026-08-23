# prd-54 — Backlog for next feature release (v2.2.0)

Trimmed out of the 2.1.0 cycle per PM scope decision (fixes ship, features wait).

## Items
- [ ] R13 Enrichment author-aware cover search: query Open Library with
      title+author; FALLBACK to title-only when author empty or zero docs;
      log fallback rate to telemetry so recall loss is observable.
- [ ] R17 Responsive grid: SliverGridDelegateWithMaxCrossAxisExtent
      (architect-recommended over breakpoint tables; handles foldables).
- [ ] R22 Drive nested-scan parity (depth ≤3, author/series folders).
      RISKIEST item: N+1 Drive round-trips per folder walk + pagination;
      batch per-folder listing and respect quota before shipping.

## Source
PM scope trim + architect risk notes, consultations 2026-08-23.
