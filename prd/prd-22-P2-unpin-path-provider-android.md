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
