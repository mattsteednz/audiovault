# prd-42 — Chunk D: Drive Resume-Position Fix (R3)

Status: [ ] not started / [x] done
Branch: `fix/drive-resume-position`
CONSULT REQUIRED BEFORE CODING: Principal Software Engineer subagent
(options + recommendation below). Record verdict here before implementation.

## Problem
`PositionBackupService.importFromJson()` restores rows via
`savePosition(chapterIndex: 0, position: Duration.zero, globalPositionMs: X)`.
On next `loadBook`, `getPosition()` returns chapter 0 @ 0:00 → playback restarts
at book start even though History/status show correct %. Cross-device restore
loses the actual listening position. JSON has no per-chapter durations, and at
import time books may not be scanned yet — so exact remap is impossible there.

## Options
A) Repair-on-scan (RECOMMENDED): after a successful scan/promote, for each book,
   read its position row; if `chapter_index==0 && position_ms==0 &&
   global_position_ms>0 && book.chapterDurations.isNotEmpty`, recompute
   (chapter, offset) from globalPositionMs via a new pure function
   `globalToChapterPosition(globalMs, chapterDurations)` in formatters.dart
   (inverse of calculateGlobalPosition), then savePosition with real values.
   Where: library_screen after `_applySort()`? Better: ScannerService caller
   agnostic → new small service/method e.g. PositionService.repairFromGlobal(book)
   invoked by DriveLibraryService.promoteToLocal AND local scan path.
   Pros: fixes existing corrupted rows too; no format change; testable.
   Cons: one extra read per book post-scan (cheap).
B) Store global-only and compute lazily everywhere: change loadBook to accept
   global ms and derive chapter/offset when durations known.
   Cons: touches audio handler contract; positions table semantics split-brain;
   larger blast radius.
C) Extend backup JSON to include chapterIndex/positionMs going forward +
   option A for legacy rows.
   Pros: future-proof. Cons: schema versioning of JSON; older clients ignore.

## Tasks
- [ ] D0. Consult subagent w/ options above; record recommendation + rationale:
      VERDICT: <fill in>
- [ ] D1. Implement chosen design. Include pure function + unit tests
      (boundaries: exactly at chapter start, mid-chapter, beyond total, empty list).
- [ ] D2. Regression test: import JSON w/ globalPositionMs only → run repair
      with synthetic Audiobook → assert getPosition returns mapped chapter/offset.
- [ ] D3. Manual note: restore flow on device/emulator if available.

## Acceptance
- Restoring positions.json on a fresh install resumes at the correct chapter+offset.
- Existing rows with the zero-position/global-nonzero signature are repaired on scan.
