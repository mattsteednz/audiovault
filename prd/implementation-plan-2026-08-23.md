# Implementation Plan â€” Post-Review Remediation (2026-08-23)

Source: full-codebase review of 2026-08-23 (checkpoints in
`%TEMP%\opencode\review-checkpoints\`). This file is the MASTER RESUME STATE.
Each chunk has its own prd-N plan file with per-task checkboxes. Agents resuming
mid-chunk: read the chunk's prd file, do the next unchecked task, keep this
master's status line updated, and always finish a work session with
`flutter analyze --fatal-warnings` + `flutter test` green and work committed.

## Ground rules (from CLAUDE.md)
- Branch per chunk: types feature/ fix/ security/ chore/. Squash-merge only.
- Gate before push: `flutter analyze --fatal-warnings && flutter test`.
- Flow: push â†’ `gh pr create` â†’ `gh pr merge <n> --auto --squash`.
- CHANGELOG.md + README.md updates ride along on user-visible changes.

## Pre-work state recovered (DONE)
- ENV CONSTRAINT: this workspace's git credentials (geometric-dev) have NO push
  access to origin (403 on mattsteednz/audiovault). All chunks are therefore
  committed as LOCAL BRANCHES ONLY, stacked on fix/preserve-polish. Owner must
  push + open PRs (one per chunk) from their own machine; CLAUDE.md's
  pushâ†’PRâ†’auto-merge step is deferred to the owner. Verify each branch passes
  CI once pushed.
- Local `main` was stale/diverged; reset to origin/main (b3b3abe). Old unique
  commit 21ff24a content verified already present on origin/main.
- Stale local branches seen: chore/code-review-chunk4, chore/kowhai-rebrand,
  docs/*, feature/*, fix/* â€” candidate cleanup AFTER all chunks merge
  (confirm merged via `git branch --merged origin/main` first).

## Chunk status
| Chunk | PRD | Items | Status |
|---|---|---|---|
| A Quality gate | prd-39 | R1 R2 R4 | [x] DONE â€” commits cf6e45c (A2) + 1de9ac1 (A3/A4); gate green 357/357 |
| B Hygiene/identity | prd-40 | R5 R6 R24 | [x] DONE on chore/identity-cleanup â€” commits 8e7ce11, 4052b74, cbe1f38 |
| C Quick wins | prd-41 | R11 R12 R19 R16 R25 R23 | [~] IN PROGRESS on branch fix/quick-wins (WIP observed: main/library/player/details/preferences/overlay + bookmark_undo util) |
| D Drive resume fix | prd-42 | R3 | SUPERSEDED by J (same files; consultation combined into J) |
| E Performance | prd-43 | R9 R10 | [ ] pending |
| F Download tracker | prd-44 | R7 R14 R15 | [ ] pending â€” CONSULT Principal Architect first |
| G Library decomposition | prd-45 | R8 | [ ] pending â€” after F |
| H Dependencies | prd-46 | R20 PRD-22 | [ ] pending â€” risk-gated |
| I Feature batch | prd-47 | R13 R17 R22 (+R18/R21 deferred) | [ ] pending |
| J Playback & persistence integrity | prd-48 | savePosition wipe, loadBook race, re-cast handoff, cast stop lifecycle, R3 resume repair | [x] DONE on `fix/robustness-batch` â€” commits ac060aa, f1facaa, 50ffc3c; SWE consult verdict in prd-48 J0; gate green 398/398 |
| K Correctness & robustness batch | prd-49 | download cancel/retry races, progress throttle, stale-download guards, Drive path sanitisation, scanner root guard, chapter sort, parser fixes, dead code | [x] DONE on local branch `fix/robustness-batch` (worktree `C:\Users\Matt\dev\audiovault-k`), commits ec765c3..101a0eb; gate green 373/373 |
| L UI perf & responsiveness | prd-50 | mini-player scope, sleep-timer VLB, search debounce, persist view mode, enrichment default align, dead ternary | [x] DONE on `fix/robustness-batch` commit 12588a1 (owner smoke-checks noted as follow-ups in prd-50) |
| M Privacy/compliance/hygiene | prd-51 | bundle fonts, telemetry consent teardown, README/firebase truth, cast token/bind, lint+keystore path, CHANGELOG dates, identity decision | [x] DONE on `fix/robustness-batch` commit 4bba7f6 (M6 owner memo written; lint re-enable + identity = follow-ups) |
| N Test infrastructure debt | prd-52 | real migration test, shared fixtures, tautology cleanup, fake_async, KowhaiHandler instance tests (locks J) | [x] DONE on `fix/robustness-batch` commit bd38ca9; N5 largely delivered inside J's lifecycle suite |
| O SAF storage strategy | prd-53 | MANAGE_EXTERNAL_STORAGE exit plan (Play policy risk) | [ ] DOC ONLY â€” owner decision |

Revised order (reliability-first mandate): A â†’ B â†’ **J â†’ K â†’ N(1-4)** â†’ C â†’ L â†’ M â†’
E â†’ F â†’ G â†’ H â†’ I â†’ O. J before C/L because data integrity outranks polish;
N1-N4 harden the suite that proves J; N5 depends on J's seams. K/L/M touch
disjoint files from B so can run parallel if another agent is active on B.
Parallel-branch note: branches off the A tip (1de9ac1) are independent PRs;
avoid two agents mutating lib/ simultaneously â€” coordinate via this table.

Order rationale (original): A restores the gate everything else relies on. B
removes identity noise so later diffs are clean. C is cheap UX/correctness
value. D was the only user-data-loss bug (now inside J). F precedes G to avoid
refactoring the same file twice. H/I are risk-gated or additive.

## Consultation log
| When | Chunk | Subagent | Options given | Verdict |
|---|---|---|---|---|
| 2026-08-23 | J | Principal Software Engineer | status-preserve Ã—3; loadBook/re-cast sequencing Ã—3; cast-stop position source Ã—2; R3 repair placement + JSON v2 | UPSERT-omit-status; stop-cast-first + success-path _book assignment + nullable readPosition suppression + future-chain serialisation; cached last non-zero receiver position via saveSnapshot, skip when empty; repair = loadBook primary + promoteToLocal secondary, never mutate global_position_ms; JSON v2 additive, importer skips explicit notStarted. Seams: @visibleForTesting ctor params (handler), position-stream provider (cast). Full text in prd-48 J0. |
| 2026-08-23 | F | Principal System Architect | ChangeNotifier tracker vs manager registry vs pure reducer (+ throttle placement) | (a) CONFIRMED + amendments: tracker owns reseeding; lazy ensureSeeded; canonical error semantics via isBusy/isComplete; throttle AT SOURCE w/ injectable-clock ProgressThrottle; R14 guards now / sealed split deferred; R15 bounded post-seek handshake; refreshBook into service now, list mutation in UI until G; reseedAll after resetStaleDownloads. 9-commit sequence. Full text in prd-44 F0. |

## Follow-up register (captured during consults â€” not yet chunked)
- `_onPlaybackCompleted` fires only on LOCAL processingStateStream â†’ a
  receiver-side finish never marks finished/schedules removal during Cast
  (flagged by SWE consult, prd-48).
- Sealed LocalBook/DriveBook model split (deferred from R14/F).
- Receiver-finish + stale-snapshot classes: revisit playback-context record
  design only if a third interleaving bug appears (SWE guidance).

## Definition of done (whole effort)
All chunk boxes ticked here + in their prd files; CHANGELOG entries for every
user-visible item; README tech-stack/feature text still accurate;
origin/main green; stale branches cleaned.
