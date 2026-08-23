# prd-46 — Chunk H: Dependency Strategy (R20 + PRD-22)

Status: [ ] not started / [x] done
Branch: `chore/dependency-updates`

## Scope & risk
Cannot device-test Drive/Cast flows from CLI; CI only runs analyze+unit tests.
Therefore: batch LOW-RISK upgrades; plan-but-maybe-defer HIGH-RISK ones.

## Tasks
- [ ] H1. `flutter pub upgrade --dry-run` — capture report into this file.
- [ ] H2. Apply patch/minor bumps EXCLUDING: google_sign_in, firebase_* majors,
      just_audio, audio_service, path_provider override. Run gate.
- [ ] H3. PRD-22 (unpin path_provider_android 2.2.23): attempt bump in a
      THROWAWAY branch build (`flutter build apk --release`) IF local Android
      toolchain exists; record result here. If no toolchain → leave pinned,
      note "needs device-verified build" and keep PRD open.
- [ ] H4. google_sign_in 6→7: read migration notes; write concrete migration
      checklist below (signInSilently removal → restoreSession rewrite,
      serverAuthCode/canAccessScopes equivalents). IMPLEMENT ONLY if API
      migration is mechanical and unit tests cover DriveService seams;
      otherwise convert this chunk's output into prd update for a
      device-testing session. Record decision.
- [ ] H5. firebase_* majors: check breaking notes; same rule as H4.

## Acceptance
pubspec diffs are intentional; every deferred item has an explicit note +
owner (future session) recorded here. Gate green on whatever lands.
