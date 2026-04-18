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

## Implementation Plan
1. Audit pass: enumerate every `InkWell`, `GestureDetector`, `IconButton`, and `TextButton` in `lib/widgets/` and `lib/screens/`; note any with `iconSize < 24` or constrained `SizedBox` tap area.
2. Standardise touch targets: ensure all interactive controls have hit area ≥ 48×48 dp. Replace bare `Icon + GestureDetector` with `IconButton` where possible; otherwise wrap in `SizedBox(width: 48, height: 48)` or `InkResponse(radius: 24)`.
3. Add `Semantics(label: ...)` or `tooltip:` to every icon-only button (play/pause, skip, sleep timer, sort, search, settings).
4. Verify at 200% font scale: write a widget test that pumps LibraryScreen and PlayerScreen under `MediaQuery(textScaler: TextScaler.linear(2.0))` and asserts no overflow exceptions via `tester.takeException()`.
5. Fix overflows: wrap fixed-height rows in `IntrinsicHeight` or switch to `Flex`-friendly sizing; use `FittedBox` sparingly on numeric time labels.
6. Run Android Accessibility Scanner on a physical device for LibraryScreen, PlayerScreen, SettingsScreen; log and fix remaining findings.
7. Add `flutter_lints` a11y rules if not already enabled in `analysis_options.yaml`.

## Files Impacted
- `lib/widgets/audiobook_card.dart`, `audiobook_list_tile.dart` (touch sizing, Semantics)
- `lib/screens/library_screen.dart` (AppBar actions, mini-player)
- `lib/screens/player_screen.dart` (transport controls, chapter buttons)
- `lib/screens/settings_screen.dart` (ensure ListTile hit areas)
- `analysis_options.yaml` (lint rules)
- `test/accessibility/large_text_test.dart` (new)
