# prd-49 — Chunk K: Correctness & Robustness Batch

Status: [ ] not started / [x] done
Branch: `fix/robustness-batch`
No consult required — mechanical fixes with clear correct behaviour. Files are
disjoint from Chunk B (safe to run parallel off the A tip).

## Tasks
- [ ] K1. Download manager cancel/retry races (drive_download_manager.dart):
      (a) retry delay callback (:151-156) must re-check `queue.cancelling`
      BEFORE re-inserting into pending — cancelled jobs must not resurrect;
      (b) reset `cancelling=false` in a `finally` around job lifecycle so an
      idle-queue cancel doesn't permanently forfeit retries (:164-170);
      (c) log (debugPrint + TelemetryService.recordNonFatal) inside the
      `catchError` at :143-160 instead of swallowing silently.
      Tests (fake_async): cancel during retry window → stays cancelled;
      cancel idle queue then fail next job → retries still happen.
- [ ] ~~K2. Throttle download progress events~~ SUPERSEDED — owned by Chunk F
      commit 1 per Architect verdict (source-side ProgressThrottle, injectable
      clock). Do NOT duplicate here.
- [ ] K3. Startup robustness (drive_book_repository.dart resetStaleDownloads
      :246-255): wrap per-file File IO in try/catch — unreadable file logs and
      skips rather than blocking launch (main.dart awaits this pre-runApp).
      expectedSize==0 semantics: file exists && length>0 → mark done; missing →
      none (re-downloadable). Extend repository test matrix for both cases.
- [ ] K4. Sanitise Drive names used as filesystem paths. Centralise in one
      helper e.g. `safeFsName(String)` in utils (strip `/` `\`, drop `..`
      segments, trim trailing dots/spaces (Windows), collapse whitespace, cap
      length ~100 chars preserving extension context). Apply at ALL construction
      sites: drive_library_service.dart:45 (`$localPath/$folderName`) and :176
      (`$dir/${f.name}`), staging paths, anywhere folder/file names join paths.
      Unit tests: traversal attempts, unicode names, reserved-ish names.
      NOTE: sanitisation happens at USE time (records keep original Drive
      names for matching/display).
- [ ] K5. Scanner root guard (scanner_service.dart:61): wrap root listing in
      try/catch → throw the same friendly exception type used elsewhere /
      return empty with logged error so UI shows retryable message
      (friendlyScanError already classifies). Test: unreadable root → no throw.
- [ ] K6. Chapter ordering guarantee: sort chapters ascending by start time at
      parse boundaries (m4b parser before returning; CUE path already ordered —
      assert/sort defensively), and make `Audiobook.chapterIndexAt` binary
      search + handle unsorted gracefully (or document precondition now that
      parsers guarantee it). Tests: unsorted QuickTime track input yields sorted
      chapters and correct lookups.
- [ ] K7. m4b `meta` FullBox fix (m4b_chapter_parser.dart:97): `meta` carries a
      4-byte version/flags header before children — skip it when descending
      into `meta` so chpl under moov/udta/meta parses. Test: synthesized box
      tree moov/udta/meta/chpl currently-missed case now found.
- [ ] K8. opf namespace tolerance (opf_parser.dart): resolve elements by
      LOCAL name (title/creator/date/series metas) so default-namespace DC OPFs
      parse. Keep precedence rules identical. Test: default-namespace fixture.
- [ ] K9. Remove dead `enqueueNextFiles` (drive_download_manager.dart:44-62) if
      grep confirms no lib/ callers (mocks reference it — regenerate mocks in
      same commit). Analyzer clean afterwards.
- [ ] K10. CHANGELOG entries under [Unreleased] (robustness fixes user-visible
      on flaky networks/folders with apostrophes etc.). Gate green; commits:
      `fix(drive): cancel/retry races + throttled progress`,
      `fix(drive): sanitize filesystem names from Drive metadata`,
      `fix(scanner): tolerate unreadable roots; guarantee chapter order`,
      `fix(parsers): m4b meta FullBox + namespace-free OPF lookup`.
