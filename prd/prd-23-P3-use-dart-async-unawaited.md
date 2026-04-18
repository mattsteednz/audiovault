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

## Implementation Plan
1. Add `import 'dart:async';` to `lib/screens/onboarding_screen.dart` (or `show unawaited` if other async types aren't needed).
2. Delete the custom `void unawaited(Future<void> _) {}` helper at line 321.
3. Grep `lib/` for other local definitions: `Grep "void unawaited"` and `Grep "unawaited(Future"` — replace any duplicates.
4. Run `flutter analyze` to confirm no lints (especially `unawaited_futures`).
5. Run `flutter test` to confirm no behavioural regressions.

## Files Impacted
- `lib/screens/onboarding_screen.dart` (import + delete helper)
- Any other file with a shadowed helper (pending grep result)
