# PRD-22 (P2): Unpin `path_provider_android` once NDK is configured

## Problem
`pubspec.yaml` pins `path_provider_android: 2.2.23` because newer versions require NDK via `jni`. This blocks transitive Android dependency updates and leaves us stuck on an older path_provider.

## Evidence
- `pubspec.yaml:46-47` — pin + comment explaining JNI/NDK reason

## Proposed Solution
- Install and configure Android NDK in local and CI build environments.
- Update `android/app/build.gradle(.kts)` `ndkVersion` to a supported version.
- Remove the pin from `pubspec.yaml`, run `flutter pub upgrade path_provider_android`.
- Verify app builds and runs on a physical device.

## Acceptance Criteria
- [ ] Pin removed, `flutter pub outdated` shows path_provider_android current
- [ ] `flutter build apk` and `flutter build appbundle` succeed locally and in CI
- [ ] App launches and folder-picker still works on device

## Out of Scope
- Migrating other packages that may now become unpinned.

## Implementation Plan
1. Install Android NDK via Android Studio SDK Manager (note the version, e.g. 26.1.10909125). Also install CMake.
2. Update `android/app/build.gradle.kts`: set `ndkVersion = "26.1.10909125"` (match installed version) inside the `android { }` block.
3. Ensure `ANDROID_NDK_HOME` env var is set for CI (GitHub Actions: use `android-actions/setup-android` or `nttld/setup-ndk`).
4. Remove the `path_provider_android: 2.2.23` pin from `pubspec.yaml` (lines 46-47, including the comment).
5. Run `flutter pub upgrade path_provider_android` then `flutter pub get`.
6. `flutter clean && flutter build apk` locally; verify success.
7. Smoke test on a physical device: launch app, open onboarding, pick a folder (confirms `path_provider` still resolves the documents dir correctly).
8. `flutter build appbundle` to confirm release build compiles with NDK.
9. Update CI workflow to install NDK before `flutter build`.
10. Monitor `flutter pub outdated` and note whether any other packages also unlock.

## Files Impacted
- `pubspec.yaml` (remove pin + comment)
- `pubspec.lock` (regenerated)
- `android/app/build.gradle.kts` (ndkVersion)
- `.github/workflows/*.yml` (NDK setup step, if CI exists)
