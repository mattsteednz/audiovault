# Implementation Plan — Post-Review Remediation (2026-08-23)

Source: full-codebase review of 2026-08-23 (checkpoints in
`%TEMP%\opencode\review-checkpoints\`). This file is the MASTER RESUME STATE.
Each chunk has its own prd-N plan file with per-task checkboxes. Agents resuming
mid-chunk: read the chunk's prd file, do the next unchecked task, keep this
master's status line updated, and always finish a work session with
`flutter analyze --fatal-warnings` + `flutter test` green and work committed.

## Ground rules (from CLAUDE.md)
- Branch per chunk: types feature/ fix/ security/ chore/. Squash-merge only.
- Gate before push: `flutter analyze --fatal-warnings && flutter test`.
- Flow: push → `gh pr create` → `gh pr merge <n> --auto --squash`.
- CHANGELOG.md + README.md updates ride along on user-visible changes.

## Pre-work state recovered (DONE)
- ENV CONSTRAINT: this workspace's git credentials (geometric-dev) have NO push
  access to origin (403 on mattsteednz/audiovault). All chunks are therefore
  committed as LOCAL BRANCHES ONLY, stacked on fix/preserve-polish. Owner must
  push + open PRs (one per chunk) from their own machine; CLAUDE.md's
  push→PR→auto-merge step is deferred to the owner. Verify each branch passes
  CI once pushed.
- Local `main` was stale/diverged; reset to origin/main (b3b3abe). Old unique
  commit 21ff24a content verified already present on origin/main.
- Stale local branches seen: chore/code-review-chunk4, chore/kowhai-rebrand,
  docs/*, feature/*, fix/* — candidate cleanup AFTER all chunks merge
  (confirm merged via `git branch --merged origin/main` first).

## Chunk status (FINAL � 2026-08-23 post-cascade)
| Chunk | PRD | Items | Status |
|---|---|---|---|
| A Quality gate | prd-39 | R1 R2 R4 | [x] MERGED #21 |
| B Hygiene/identity | prd-40 | R5 R6 R24 | [x] MERGED #22 |
| C Quick wins | prd-41 | R11 R12 R19 R16 R25 R23 | [x] MERGED #25 (C3 deviation noted in prd-41) |
| D Drive resume fix | prd-42 | R3 | [x] SUPERSEDED -> done inside J (#26) |
| E Performance | prd-43 | R9 R10 | [ ] pending |
| F Download tracker | prd-44 | R7 (+R14/R15 landed via J/K) | [ ] pending (F0 verdict recorded) |
| G Library decomposition | prd-45 | R8 | [ ] pending (after F) |
| H Dependencies | prd-46 | R20 PRD-22 | [ ] pending (risk-gated) |
| I Feature batch | prd-47 | R13 R17 R22 (+R18/R21 deferred) | [ ] pending |
| J Playback & persistence integrity | prd-48 | savePosition wipe, loadBook race, re-cast handoff, cast stop lifecycle, resume repair | [x] MERGED #26 |
| K Correctness & robustness batch | prd-49 | races/guards/sanitisation/parser fixes | [x] MERGED #26 |
| L UI perf & responsiveness | prd-50 | mini-player scope, debounce, persist view mode | [x] MERGED #26 |
| M Privacy/compliance/hygiene | prd-51 | fonts/consent/token/keystore | [x] MERGED #26 |
| N Test infrastructure debt | prd-52 | migrations/fixtures/oracles/lifecycle | [x] MERGED #26 |
| O SAF storage strategy | prd-53 | MANAGE_EXTERNAL_STORAGE exit plan | [ ] DOC ONLY � owner decision |

## Post-cascade notes (2026-08-23)
- All work landed via squash PRs #20 #21 #22 #25 #26; remote feature branches
  deleted. Probe PRs #23/#24 closed.
- Account renamed mattsteednz -> **masterslueth** mid-cascade. Pinned for this
  checkout: repo-local git identity + .git/hooks/pre-commit enforcement +
  `.ghcred.sh` credential helper (untracked; beats GCM via blank-reset) +
  canonical remote masterslueth/kowhai. gh API calls need
  `$env:GH_TOKEN=(gh auth token --user masterslueth)` prefix when another
  session flips the active account.
- A second WORKTREE exists at `C:/Users/Matt/dev/audiovault-k` sharing this
  .git (used by a parallel agent). It shares config/hooks � coordinate before
  concurrent git ops, or remove it if no longer needed.
- Remaining open chunks: E, F, G, H, I, O.
## Definition of done (whole effort)
All chunk boxes ticked here + in their prd files; CHANGELOG entries for every
user-visible item; README tech-stack/feature text still accurate;
origin/main green; stale branches cleaned.
