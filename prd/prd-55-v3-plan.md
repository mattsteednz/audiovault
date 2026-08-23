# prd-55 — v3.0.0 plan (breaking / modernization) — GATED

Do NOT tag until the on-device regression pass completes. CLI cannot exercise
OAuth consent, Drive scope grants, or Cast handoff.

## Scope (each needs device verification)
1. google_sign_in 6 -> 7 (target: ^7.1.0 — re-check at start; API rework:
   signInSilently removed, authorization delegates). Rewrite DriveService
   auth surface; restoreSession becomes authorize+silent attempt.
2. firebase_core ^5? -> current major at time of work; analytics/crashlytics
   matching majors. (Exact pins: record AT START of v3 cycle after running
   `flutter pub outdated`; do not trust numbers written earlier.)
3. R18 DB split: move drive_* tables out of kowhai_positions.db into own DB
   or rename concept to library.db; requires schema v5 migration + repo seam.
4. Storage strategy resolution (prd-53 owner decision) — SAF/document-tree
   picker if Play distribution ever desired.
5. Sealed LocalBook/DriveBook model split (deferred from F/R14).

## Cadence guard
Run `flutter pub outdated` monthly; update this file's exact targets so the
jump never silently grows.

## Gates to tag v3.0.0
- Full 30-min device smoke: fresh install, upgrade-install over prior,
  Drive connect/scope grant, rescan, download cancel->retry, cast start/stop,
  backup restore across devices.
- pubspec version == tag == CHANGELOG heading (workflow fail-fast enforces).
