# PRD-30 (P3): Accessibility audit — touch targets, semantics, large text

## Problem
No systematic accessibility review has been done. Small `IconButton`s, unlabeled icons, and fixed-font-size layouts may fail Material's 48dp touch-target minimum and break at large text scales.

## Evidence
- `lib/widgets/audiobook_card.dart`, `audiobook_list_tile.dart` — fixed sizes
- Player controls and mini player use `Icon` widgets without explicit `Semantics`

## Proposed Solution
- Enable accessibility lints (`avoid_web_libraries_in_flutter` already; add a11y rules from `flutter_lints`).
- For each interactive icon: confirm ≥48dp hit area (`IconButton` default, `InkWell` with explicit size, or `Semantics`+`GestureDetector` wrapper).
- Add `Semantics(label: …)` on controls whose meaning is icon-only.
- Test with the Accessibility Scanner on device and at 200% font scale.

## Acceptance Criteria
- [ ] No interactive element under 48×48 dp
- [ ] Every icon button has a semantic label
- [ ] Library and Player screens remain usable at system font scale 200%

## Out of Scope
- RTL layout audit (separate effort).
