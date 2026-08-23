# prd-44 — Chunk F: Download Progress Unification (R7) + Robustness (R14, R15)

Status: [ ] not started / [x] done
Branch: `chore/download-tracker-refactor`
CONSULT REQUIRED: Principal System Architect (design options below). Record
verdict before implementation.

## Problem R7
Byte-level download progress state machine duplicated ×3:
1. `DriveDownloadOverlay._onEvent` (+_initState DB seed)
2. book_details `_ActionButtonsState` (_initDownloadState/_onEvent)
3. utils/drive_download_sheet `_DownloadProgressSheet._onEvent`
All three: subscribe to filtered downloadEvents, track completedBytes /
currentFileBytes / counts, compute overall progress. Divergence risk already
visible (error-state handling differs slightly).

## Design options
A) `BookDownloadTracker extends ChangeNotifier` (RECOMMENDED):
   lives in services/; constructor(folderId); exposes seeded state from repo,
   subscribes manager events for its folder, exposes
   {state enum, overallProgress double, downloadedCount,totalCount,
    totalBytes, doneBytes}; dispose() cancels sub.
   Widgets wrap w/ AnimatedBuilder/ListenableBuilder. One tracker per surface
   (3 instances, same folder OK — events are broadcast).
   Pros: minimal API churn; each widget keeps its layout; testable with fake
   event stream + fake repo.
B) Singleton per-folder registry inside DriveDownloadManager exposing
   ValueListenable<DownloadProgress?> per folderId.
   Pros: one source of truth; UI never seeds from DB.
   Cons: manager grows lifecycle complexity (when to drop listenables);
   larger refactor of manager + tests.
C) Keep duplication, extract pure reducer only.
   Pros: cheapest. Cons: doesn't fix subscription/seed boilerplate.

## Fold-in R14
- Guard `driveMetadata!` bangs: book_details initState/_cancelAndRemove,
  library paths via driveMetadata?.folderId null-checks, overlay initState.
  Behavior on missing metadata: treat as non-Drive (hide download UI), not crash.

## Fold-in R15 (prior review B6)
- cast_controller.stop(): after `localPlayer.seek(castPosition)` it immediately
  emits `localPlayer.position` (may be pre-seek). Fix: await seek completion
  then emit once, or skip immediate emit and let positionStream broadcast.
  Prefer: `await localPlayer.seek(...); onEffectivePosition(localPlayer.position);`
  is ALREADY awaited — verify actual staleness; if just_audio seek returns
  before position updates, use first positionStream event after seek.

## Tasks
- [x] F0. Architect consult; VERDICT recorded (Principal System Architect,
      2026-08-23):
      Option (a) CONFIRMED with amendments — manager-owned
      `DownloadProgressTracker extends ChangeNotifier` in
      lib/services/download_progress_tracker.dart: immutable
      `BookDownloadProgress` snapshots keyed by folderId; per-folder child
      Listenable (`listenableFor`) for granular card rebuilds; lazy idempotent
      `ensureSeeded(folderId)` (DB seed on first ask — survives cold-start
      ordering); explicit `reseed(folderId)` called by DriveLibraryService
      after undownload/deleteLocalFiles/promoteToLocal (replacing the
      overlay's didUpdateWidget length-heuristic recovery);
      `onBookCompleted`/`onCoverCompleted` callbacks fired once on
      idle→complete transitions; single `attach(events)` subscription.
      Throttle AT SOURCE (manager `_downloadFile` before `_controller.add`):
      injectable-clock `ProgressThrottle` (100 ms OR ≥1% delta; terminal
      events bypass; unknown total → byte-delta-only) instantiated per
      attempt closure. R14 = guard-at-boundary NOW (driveMetadata?. with
      hide-UI semantics), sealed class split deferred to its own future PRD
      (would collide with G's move-only guarantee). R15 = bounded post-seek
      handshake: `await seek; onEffectiveDuration; await
      positionStream.first.timeout(250ms, onTimeout: () => position)` —
      extract `@visibleForTesting resumeLocalPlayback({seekTarget})` for
      tests. Orchestration: add `DriveLibraryService.refreshBook(folderId)`
      (decision moves to service); list mutation stays in UI until G; NO
      completedBooks stream (tracker callback suffices). Belt-and-braces:
      `reseedAll()` after resetStaleDownloads in deferred startup.
      9-commit migration sequence + acceptance grep (completedBytes outside
      tracker == 0) recorded in consult transcript.
- [ ] F1. Implement tracker per verdict; migrate 3 surfaces; delete duplicated
      state machines. Existing tests updated; add tracker unit tests (seed,
      downloading/done/error transitions, cancel semantics unchanged).
- [ ] F2. R14 guards + tests (drive book w/o metadata renders, no throw).
- [ ] F3. R15 fix + fake-timer/stream test proving no stale emit.

## Acceptance
- Exactly ONE implementation of byte-progress accounting in lib/.
- analyze+test green.
