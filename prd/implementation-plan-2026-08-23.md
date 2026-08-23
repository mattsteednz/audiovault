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

## Chunk status
| Chunk | PRD | Items | Status |
|---|---|---|---|
| A Quality gate | prd-39 | R1 R2 R4 | [ ] pending — DO FIRST (unblocks trustworthy CI) |
| B Hygiene/identity | prd-40 | R5 R6 R24 | [ ] pending |
| C Quick wins | prd-41 | R11 R12 R19 R16 R25 R23 | [ ] pending |
| D Drive resume fix | prd-42 | R3 | [ ] pending — CONSULT Principal SWE first |
| E Performance | prd-43 | R9 R10 | [ ] pending |
| F Download tracker | prd-44 | R7 R14 R15 | [ ] pending — CONSULT Principal Architect first |
| G Library decomposition | prd-45 | R8 | [ ] pending — after F |
| H Dependencies | prd-46 | R20 PRD-22 | [ ] pending — risk-gated |
| I Feature batch | prd-47 | R13 R17 R22 (+R18/R21 deferred) | [ ] pending |

Order rationale: A restores the gate everything else relies on. B removes
identity noise so later diffs are clean. C is cheap UX/correctness value.
D is the only user-data-loss bug. F precedes G to avoid refactoring the same
file twice. H/I are risk-gated or additive.

## Consultation log
| When | Chunk | Subagent | Options given | Verdict |
|---|---|---|---|---|
| (pending) | D | Principal Software Engineer | repair-on-scan vs lazy-global vs JSON schema v2 | — |
| (pending) | F | Principal System Architect | ChangeNotifier tracker vs manager registry vs pure reducer | — |

## Definition of done (whole effort)
All chunk boxes ticked here + in their prd files; CHANGELOG entries for every
user-visible item; README tech-stack/feature text still accurate;
origin/main green; stale branches cleaned.
