# prd-43 — Chunk E: Performance Batch (R9, R10)

Status: [ ] not started / [x] done
Branch: `chore/perf-scan-and-covers`

## R9 — Move scanner metadata parsing off main isolate
- ScannerService._scanSubfolder loops `readMetadata(File(...))` sequentially on
  the UI isolate → jank during scans of large libraries.
- Plan: wrap the PER-BOOK metadata pass in `Isolate.run(() => ...)`. Constraints:
  - Must not send open files/receive ports; pass plain paths + return plain data
    (durations, titles, art bytes as Uint8List — transferable).
  - CUE parse + OPF parse are cheap string work; can stay on main OR move with
    the same payload. Prefer moving whole `_scanSubfolder` body except the
    directory listing (needs no isolate) — measure first; simplest correct step:
    isolate ONLY the metadata loop (`_readFilesMetadata` extracted, pure inputs).
  - Keep `onBookFound` streaming behavior (per-book callback on main isolate).
- Test: existing scanner_service_test must stay green unchanged (behavioral
  contract). Add one test asserting results identical w/ >50-file folder?

## R10 — Cover decode cost
- BookCover uses Image.memory(embedded bytes) decoded at full size every
  rebuild; grid of N books = N full decodes, no downscaling.
- Plan: add `cacheWidth:` sized from layout. BookCover gets optional
  `targetSize` param (grid card ~600px logical is overkill; use 256 default for
  tiles/cards, player passes larger). Image.file gets same treatment
  (cacheWidth only — cacheHeight too since square).
- EnrichmentAwareCover/AudiobookCard/ListTile pass appropriate sizes.
- Test: widget test already exists (book_cover_test); extend to assert
  Image has expected cacheWidth via tester widget inspection if feasible;
  otherwise manual verify in profile mode + note.

## Acceptance
- analyze+test green; no behavioral changes; scan of large library no longer
  drops frames (profile-mode note appended below by implementer).
