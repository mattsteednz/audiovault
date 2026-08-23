# prd-48 — Chunk J: Playback & Persistence Integrity

Status: [ ] not started / [x] done
Branch: `fix/playback-integrity`
CONSULT REQUIRED BEFORE CODING: Principal Software Engineer (see consultation
log in implementation-plan). Record verdict in J0 before implementing.
Absorbs old Chunk D (prd-42 / R3). All items verified against source 2026-08-23.

## Problem statements
- **J-bug1 status wipe**: `PositionService.savePosition` (:113-134) inserts
  without the `status` column using `ConflictAlgorithm.replace`. SQLite REPLACE
  deletes the conflicting row → explicit status (e.g. Finished set manually)
  silently reverts to derived status on the next periodic save. Contradicts the
  deliberate ON CONFLICT preservation in `setBookStatus` (:153-165).
- **J-bug2 loadBook race**: `_book = book` assigned (audio_handler.dart:183)
  BEFORE `await _player.setAudioSources(...)` (:204). The persister's closures
  read live player state; a tick landing inside the window persists the NEW
  book's path with the OLD player's position/index.
- **J-bug3 re-cast handoff**: when already casting, loadBook calls
  `_cast.stop()` then `_cast.start()` (:220-223) AFTER sources swapped.
  `CastController.stop()` seeks the local player to the OLD book's receiver
  position (cast_controller.dart:185-211) — now applied to the NEW book's
  sources → wrong resume position.
- **J-bug4 stop lifecycle**: `KowhaiHandler.stop()` never calls
  `CastController.stop()` (audio_handler.dart:377-385) → CastServer socket
  leaks, `_casting` stays true; also double `_persister.save()`.
- **J-bug5 cast-stop zero fallback**: on receiver death,
  `castPosition = Duration.zero` fallback (:188-191) → local seeked to 0 and a
  later pause persists 0 over the last good save; no final save before teardown.
- **J-item6 R3 resume repair** (from prd-42): backup JSON stores only
  global_position_ms; importFromJson writes chapterIndex 0/position zero
  (position_backup_service.dart:130-136); loadBook resumes at start despite
  correct History %. Fix must ALSO repair already-corrupted rows.

## Tasks
- [x] J0. Consultation verdict recorded here:
      VERDICT (Principal Software Engineer, 2026-08-23):
      - D1 = UPSERT rawInsert omitting `status` (mirror of setBookStatus idiom);
        read-modify-write rejected (TOCTOU); derived-only rejected.
      - D2 = stop-cast-FIRST at loadBook entry while OLD sources still loaded
        (try/catch best-effort; harden CastController.stop so `_casting=false`
        happens in finally); defer `_book`/`_artUri` assignment to success path
        and DELETE the failure-path `_book = null` (previous book stays
        current); suppress persister ticks via NULLABLE readPosition closure
        (`PositionSnapshot? Function()` returning null when `_loading`) — flag
        held until AFTER post-load `_cast.start()` completes; serialize
        loadBook via future-chain `_loadQueue`.
      - D3 = cache last NON-ZERO receiver position from position stream
        (reset on start AND end of stop); final save via NEW
        `PositionPersister.saveSnapshot(book, snap)` (single impl of global
        math) BEFORE teardown; skip seek+save when cache empty (local player
        stays parked at handoff position — better than 0); clamp seek to local
        duration; chapterIndex from localPlayer.currentIndex (same coordinate
        space). Receiver-finish edge: still save near-end progress (derived
        finished falls out via 60s threshold).
      - D4 = (a)+(c): pure `globalToChapterPosition` in utils/formatters.dart;
        repair hooks = `_doLoadBook` pre-getPosition (PRIMARY,
        point-of-consumption, covers every corruption source) +
        `promoteToLocal` post-scan (secondary); NO scanner/UI-layer hook;
        repair NEVER mutates global_position_ms; export JSON v2 adds
        chapter_index/position_ms (getAllPositions must expose them), importer
        accepts v1+v2 without gating on version field; IMPORTER CLEARING RULE:
        only write explicit status when parsed value is inProgress|finished —
        absent/notStarted leaves status NULL (NULL ⇒ derive invariant).
      - Required test seams: @visibleForTesting ctor params on KowhaiHandler
        (player/cast); optional position-stream provider on CastController.
      - Follow-up flagged (NOT in J): `_onPlaybackCompleted` never fires when
        receiver finishes a book (local-only processingStateStream) — record
        as future chunk item.
      Implementation guidance + 22-test regression list captured in consult
      transcript; summarized tasks below reflect it.
- [x] J1. savePosition preserves explicit status. Preferred shape (confirm vs
      verdict): single rawInsert UPSERT `ON CONFLICT(book_path) DO UPDATE SET`
      position/chapter/global/total/updated_at columns ONLY (never touch
      `status`). Regression tests: (a) save over row w/ status=finished keeps
      finished; (b) save onto row w/o status leaves NULL; (c) periodic-save loop
      does not clobber manual status.
- [x] J2. loadBook sequencing fix: detect `isCasting && differentBook` at ENTRY;
      if so fully stop cast BEFORE mutating `_book`/sources (old sources still
      loaded → stop's position-seek lands correctly). Then proceed with load.
      Additionally defer `_book`/`_artUri` assignment until AFTER
      `setAudioSources` succeeds (failure path already resets — make success
      path the only assigner). Persister snapshot safety: pass an immutable
      snapshot (book+index+pos captured at save time) OR gate persister ticks
      during load via a simple `_loading` flag checked by the readPosition
      closure. Tests: simulate tick during load asserts no cross-book write.
- [x] J3. CastController.stop(): never fall back to Duration.zero — cache last
      non-zero receiver position from the position stream (field updated in the
      existing listener); final `persister.save()` BEFORE cancelling timer using
      cached value; skip local seek-back entirely if no session/cached value.
      Test w/ fake stream: receiver death mid-session → next pause persists
      cached position, not 0.
- [x] J4. KowhaiHandler.stop(): call `_cast.stop()` first when casting (single
      teardown path), collapse to ONE persister.save(). Test: stop while casting
      → cast server stopped flag + single save observed (via injected spies).
- [x] J5. R3 repair-on-scan (per verdict): add pure
      `globalToChapterPosition(globalMs, chapterDurations)` inverse helper in
      utils/formatters.dart (+ boundary tests: exact chapter start, mid-chapter,
      beyond total, empty list). Repair hook invoked post-scan/promote for rows
      matching signature `chapter_index==0 AND position_ms==0 AND
      global_position_ms>0` with known chapterDurations. Extend export JSON to
      v2 (`chapter_index`, `position_ms` fields; importer accepts both v1/v2).
      Regression test end-to-end: export v1-style JSON → import → scan repair →
      getPosition returns mapped chapter+offset.
- [x] J6. CHANGELOG entry under [Unreleased] (user-visible: fixed lost Finished
      status, fixed cast-switch resume bug, restore fidelity).
- [x] J7. Gate: analyze --fatal-warnings + flutter test green. Commit(s):
      `fix(persistence): preserve explicit status across position saves`,
      `fix(player): safe loadBook/re-cast sequencing`, `fix(cast): teardown
      lifecycle + last-known-position`, `feat(backup): chapter-level restore +
      repair-on-scan`.

## Acceptance
- No code path can zero an explicit status or persist position of book A under
  book B's path.
- Casting book A → load book B while casting → B resumes at B's saved position.
- Receiver death mid-cast cannot overwrite good progress with 0.
- Cross-device JSON restore resumes at correct chapter+offset after first scan.

## Implementation notes (2026-08-23)
- All items implemented per verdict. Test seams added: KowhaiHandler ctor
  (player/cast params, annotations on the PARAMS so production calls stay
  clean), handler.persister accessor, FakeCastController implements-style fake.
- globalToChapterPosition clamps last-chapter overshoot to chapter length so
  legacy rows near book end cannot seek past EOF and insta-complete.
- Handler-level regression suite: test/services/audio_handler_lifecycle_test.dart
  (resume restore, failure keeps previous book, mid-load suppression,
  stop-before-swap ordering, single-save stop).
- Receiver-side finish still does not mark finished (local-only completion
  listener) � logged in master follow-up register for a future chunk.
