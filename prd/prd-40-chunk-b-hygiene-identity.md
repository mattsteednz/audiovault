# prd-40 — Chunk B: Repo Hygiene & Identity Cleanup (R5, R6, R24)

Status: [ ] not started / [x] done
Branch: `chore/identity-cleanup`

## Problem
Project renamed smart_book → audiovault → Kōwhai; every layer still shows a
different name. README claims MIT but no LICENSE exists. CI build number frozen.

## Tasks
- [ ] B1 (R5). Add `LICENSE` file — MIT, copyright holder Matt Steed
      (match GitHub owner mattsteednz; verify preferred name in existing
      sources/about screen first). Reference from README license section.
- [ ] B2 (R6a). Delete tracked stale app copy: `assets/lib/{main,theme,util}.dart`.
      Confirm nothing references them (`grep -r "assets/lib"`); remove the
      analyzer `exclude: assets/**` block if it becomes pointless (keep if other
      assets need it — check for stray .dart under assets/ after deletion).
- [ ] B3 (R6b). Delete duplicate dotfile `.analysis_options.yaml` (root).
- [ ] B4 (R6c). Unify debug log tags to `[Kowhai:*]`: main.dart uses
      `[AudioVault:Cast]`; grep all `[AudioVault` occurrences and rename.
- [ ] B5 (R6d). Rename temp cover prefix `sbcover_` → `kowhai_cover_` in
      audio_handler.dart. NOTE: old files may linger in cache dirs — harmless.
- [ ] B6 (R6e). Fix doc/comment drift: PositionBackupService comment says
      `AudioVault/positions.json` (folder constant is 'Kowhai');
      GithubReleaseService comment says "AudioVault GitHub repo".
      MediaStateBroadcaster header says "AudioVault's internal state".
- [ ] B7 (R24). CI build number: in ci.yml/build-release.yml pass
      `--build-number=${{ github.run_number }}` to build/test invocations where
      meaningful (build-release.yml apk build). Consider bumping pubspec
      `version: 2.0.0+1` baseline so run_number continues above it.
- [ ] B8. Update CHANGELOG.md under a new `[Unreleased]` heading summarizing
      hygiene work (per CLAUDE.md merge requirement).
- [ ] B9. Gate: analyze + test green.

## Acceptance
- No tracked files named like old identities (smart_book.iml already ignored);
  zero `[AudioVault` / `sbcover` / `smart_book` references in lib/ and CI.
- LICENSE present and referenced by README.
