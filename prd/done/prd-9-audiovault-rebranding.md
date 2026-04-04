# PRD 9: AudioVault Rebranding

## Feature Overview
Rename the application from "SmartBook" to "AudioVault Audiobook Player" across all platforms, codebases, documentation, and branding. Update package names, Firebase configuration, and all references to reflect the new identity while maintaining all existing functionality.

## User Stories

**US-9.1:** As a developer, I want the Flutter project to have the correct package name and app identity so the app can be properly registered and distributed.

**US-9.2:** As a user, I want the app to be clearly named "AudioVault Audiobook Player" in app stores and system settings so I can easily identify and find the app.

**US-9.3:** As a contributor, I want all documentation and PRDs to reference "AudioVault" consistently so there's no confusion about the project name.

**US-9.4:** As a developer setting up Firebase, I want the app to be registered with the correct package name so telemetry and crash reporting work properly.

## Acceptance Criteria

### Flutter Project Setup:
- [ ] `pubspec.yaml` updated with name: "audiovault" and description referencing "AudioVault Audiobook Player"
- [ ] Android `build.gradle` applicationId set to `com.mattsteed.audiovault`
- [ ] Android `AndroidManifest.xml` package attribute set to `com.mattsteed.audiovault`
- [ ] iOS `Runner.xcodeproj` Bundle Identifier set to `com.mattsteed.audiovault`
- [ ] App display name set to "AudioVault" in both Android and iOS configurations
- [ ] All project directories/files with "smartbook" name updated to "audiovault" (if any)

### Documentation Updates:
- [ ] All 9 PRD files updated to reference "AudioVault" instead of "SmartBook"
- [ ] README files and wiki pages updated with new app name
- [ ] Package name references updated to `com.mattsteed.audiovault`
- [ ] Any architecture/setup documentation reflects new naming

### Firebase Configuration:
- [ ] New Firebase project created for "AudioVault" (or existing project reregistered)
- [ ] Android app registered with package `com.mattsteed.audiovault`
- [ ] iOS app registered with Bundle ID `com.mattsteed.audiovault`
- [ ] `google-services.json` (Android) downloaded and placed in `android/app/`
- [ ] `GoogleService-Info.plist` (iOS) downloaded and placed in `ios/Runner/`
- [ ] Firebase SDKs configured and tested in both platforms

### Branding & App Store Prep:
- [ ] App icon and splash screen assets updated (if not already generic)
- [ ] Play Store listing created with "AudioVault Audiobook Player" name and description
- [ ] App Store listing created with same name and description
- [ ] Privacy policy drafted and referenced correct app name
- [ ] Release notes mention the open-source nature and bring-your-own-books capability

### Code & Project Structure:
- [ ] Build artifacts cleaned and rebuilt successfully with new package name
- [ ] No hardcoded "SmartBook" references in source code
- [ ] Git history preserved (rebranding as code commits, not destructive rewrites)
- [ ] Project compiles and runs on both Android and iOS with new configuration

## Technical Requirements

### Package Name:
- App Package Name: `com.mattsteed.audiovault`
- iOS Bundle ID: `com.mattsteed.audiovault`
- Maven Group ID (if applicable): `com.mattsteed`
- Artifact ID: `audiovault`

### Firebase Configuration:
- Firebase Project Name: "AudioVault"
- Android App Name: "AudioVault (Android)"
- iOS App Name: "AudioVault (iOS)"
- Enable services: Analytics, Crashlytics, Performance Monitoring (optional)

### File/Directory Changes:
- Project root: `smart-book/` → `audiovault/` (optional, can keep for git history)
- Main package: `com.smartbook.*` → `com.mattsteed.audiovault`
- Asset folders: Update references if named after old app
- Build outputs: Clean and rebuild with new identifiers

### Git/Version Control:
- No destructive rewrites of history
- Create new commits for each logical change (package name update, Firebase config, docs, etc.)
- Tag milestone (e.g., `v0.1.0-audiovault-rebranding`) after completion

## Design Considerations

- Maintain all existing app functionality and user data during transition
- Ensure no breaking changes to data persistence or file paths
- Consider adding migration logic if app was previously installed under old package name
- Keep splash screen and onboarding generic enough to not reference specific app names where possible

## Success Metrics

- [ ] App builds successfully on both Android and iOS with new package name
- [ ] Firebase console shows events from both platforms with correct app IDs
- [ ] All PRD documentation references "AudioVault" consistently
- [ ] No compilation errors or package name conflicts
- [ ] App installs and runs with correct display name on both platforms

## Dependencies

- Firebase account with billing setup (free tier available)
- Flutter SDK and build tools
- Android Studio (for Android signing key generation)
- Xcode (for iOS configuration)
- Git for version control

## Related Features

- PRD 8 (Telemetry) — requires Firebase configuration with correct package names
- All other PRDs (0-7) — documentation should reference AudioVault

## Implementation Steps

1. **Update Flutter Configuration** (30 min)
   - Update pubspec.yaml
   - Update Android package names
   - Update iOS Bundle ID
   - Clean build artifacts

2. **Create Firebase Project** (15 min)
   - Create new Firebase project or repurpose existing
   - Register Android app
   - Register iOS app
   - Download configuration files

3. **Integrate Firebase Config** (15 min)
   - Place google-services.json in android/app/
   - Place GoogleService-Info.plist in ios/Runner/
   - Update build.gradle Firebase plugin references

4. **Update All Documentation** (45 min)
   - Update all 9 PRD files
   - Update README.md files
   - Update any wiki/setup docs

5. **Test & Verify** (30 min)
   - Build and run on Android
   - Build and run on iOS
   - Verify package names in system settings
   - Test Firebase connectivity

6. **App Store Setup** (1-2 hours)
   - Create Play Store developer account listing
   - Create App Store developer account listing
   - Draft privacy policy
   - Prepare release notes

## Priority

**High** - Foundation work that should be done before Phase 1 implementation. Ensures correct project identity and Firebase integration from the start.

## Notes

- This is a prerequisite for PRD 8 (Telemetry/Firebase)
- Should be completed before Phase 1 development accelerates
- Consider this a "foundational" task rather than a feature
- All data stored locally should work seamlessly after rename (package name is only for installation/identification)
