# PRD-23 (P3): Replace custom `unawaited()` with `dart:async`

## Problem
`onboarding_screen.dart` defines a local `unawaited()` helper instead of importing the standard one from `dart:async`. Redundant and inconsistent with the rest of the Flutter ecosystem.

## Evidence
- `lib/screens/onboarding_screen.dart:108` — call site
- `lib/screens/onboarding_screen.dart:321` — local definition

## Proposed Solution
- `import 'dart:async' show unawaited;`
- Delete the local helper.
- Grep the rest of `lib/` for similar ad-hoc definitions.

## Acceptance Criteria
- [ ] Local `unawaited` removed
- [ ] `flutter analyze` clean

## Out of Scope
- Auditing every `Future` in the codebase for missing `await`.
