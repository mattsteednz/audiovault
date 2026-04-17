# PRD-27 (P3): Labeled loading states on app startup

## Problem
Two bare `CircularProgressIndicator` screens appear during startup (consent check, then library check). Users on slow devices may think the app is frozen.

## Evidence
- `lib/main.dart:204-205`
- `lib/main.dart:214-215`

## Proposed Solution
- Wrap each spinner with a centered `Column` containing the spinner and a subtitle:
  - consent phase → "Checking settings…"
  - library phase → "Loading library…"
- Use Material 3 typography; keep layout identical across the two phases to avoid jumps.

## Acceptance Criteria
- [ ] Both startup screens show a label
- [ ] No layout shift between phases
- [ ] No new build time on cold start

## Out of Scope
- Custom splash screen / animations.
