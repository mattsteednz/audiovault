# prd-39 — Chunk A: Quality Gate Restoration (R1, R2, R4)

Status: [x] DONE (branch fix/quality-gate; A1=stale shader cache confirmed via flutter clean; A2=Bug B ported as preservation Property 6; A3=pinned 3.44.4+cache both workflows; A4=mocks regen, suppression removed)
Branch: `fix/quality-gate`

## Problem
- `flutter test` fails on main: 357 pass / 2 fail.
  - F1: `test/screens/book_download_prompt_bug_exploration_test.dart` — TDD
    scratch artifact, intentionally failing ("Bug B … fails on unfixed code").
    The fix it guarded ALREADY SHIPPED (book_details gates on `notDownloaded`),
    so the test is stale/wrong forever.
  - F2: `book_download_prompt_preservation_test.dart` mobile-data case —
    env failure: `shaders/ink_sparkle.frag` runtime-stages version mismatch
    (stale build cache vs Flutter SDK). Likely fixed by `flutter clean`;
    if not, the test needs insulating from real asset loading.
- CI uses floating `channel: stable` → local/CI SDK drift caused F2-class breaks.
- Global analyzer suppression `override_on_non_overriding_member: ignore`
  exists ONLY to let stale committed `.mocks.dart` compile → hides real errors.

## Tasks
- [ ] A1. `flutter clean && flutter pub get`; rerun F2 test. If green → cause was
      stale cache; still pin CI (A3) to prevent recurrence.
      If still red → inspect; likely fix: avoid Material ink sparkle path by
      pumping with `MaterialApp` w/o interactive shaders or wrap expectations;
      prefer NOT editing generated Flutter assets.
- [ ] A2. R1: Delete `book_download_prompt_bug_exploration_test.dart` AND its
      `.mocks.dart`. Rationale: exploration tests are scaffolding; the durable
      regression coverage lives in `book_download_prompt_preservation_test.dart`.
      Verify preservation test still covers Bug B ("Start listening" gating).
      If coverage gap found, port the missing assertions into preservation test.
- [ ] A3. R2: Pin Flutter version in `.github/workflows/ci.yml` and
      `build-release.yml`: use exact `flutter-version:` matching local
      (`flutter --version`) + add `cache: true` to subosito/flutter-action.
- [ ] A4. R4: Run `dart run build_runner build --delete-conflicting-outputs`
      to regenerate ALL mocks against current interfaces. Confirm no source
      changes needed. Then remove `override_on_non_overriding_member` ignore
      from `analysis_options.yaml`. Run analyze: must stay clean.
- [ ] A5. Full gate: `flutter analyze --fatal-warnings` + `flutter test` green.
- [ ] A6. Commit(s): `fix: remove stale exploration test; keep suite green`,
      `chore(ci): pin flutter version + enable pub cache`,
      `chore: regenerate mocks; drop global analyzer suppression`.

## Acceptance
- `flutter test` exits 0 locally; CI expected green (pinned SDK).
- No global analyzer error suppressions remain.
- Mocks regenerate cleanly (no manual edits inside .mocks.dart).
