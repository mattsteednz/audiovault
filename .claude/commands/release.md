---
name: release
description: Version bump, changelog, README update, and GitHub release with APK
---

# /release — Publish a GitHub release

Run this when main is ready to ship. It determines the right version bump, updates docs, builds a release APK, and publishes to GitHub Releases.

## Steps

### 1. Make sure you're on main and up to date

```bash
git checkout main && git pull origin main
```

### 2. Assess the level of change since the last release

Read `CHANGELOG.md` to find the last released version. Then review what's changed since then:

```bash
git log --oneline $(git describe --tags --abbrev=0)..HEAD 2>/dev/null || git log --oneline -20
```

Classify each commit and pick the highest level that applies:

| Level | Examples | Version change |
|---|---|---|
| **major** | Breaking changes, full redesign | `1.x.y` → `2.0.0` |
| **minor** | New user-facing features | `1.2.x` → `1.3.0` |
| **patch** | Bug fixes, polish, minor enhancements | `1.2.3` → `1.2.4` |

The version in `pubspec.yaml` is `MAJOR.MINOR.PATCH+BUILD`. Always increment BUILD by 1 as well (e.g. `1.2.3+4` → `1.3.0+5`).

### 3. Bump version in pubspec.yaml

Edit `pubspec.yaml` to the new version. Example for a minor bump:

```
version: 1.2.5+5  →  version: 1.3.0+6
```

### 4. Update CHANGELOG.md

Replace the `## [Unreleased]` section (if present) with a new versioned entry at the top, immediately after the header block. If there is no Unreleased section, insert a new entry above the previous release.

Format:

```markdown
## [X.Y.Z] — YYYY-MM-DD

### Added
- **Feature name** — what it does and why it matters

### Changed
- **Thing that changed** — what was different before, what it is now

### Fixed
- **Bug description** — what was wrong and what fixed it
```

Only include sections that have entries. Omit empty sections.
Keep bullets user-facing — avoid internal implementation details unless they affect developers using the project.

### 5. Update README.md

Check these sections and update anything that has changed since the last release:
- **Features** list — add new features, remove or reword anything that no longer applies
- **Tech Stack** table — add any new packages
- **Project Structure** — add any new files or directories under `lib/`

Keep language factual and concise.

### 6. Run analysis and tests

```bash
flutter analyze && flutter test
```

Fix any failures before continuing. Do not release with broken tests or analyzer errors.

### 7. Commit the release prep

```bash
git add pubspec.yaml CHANGELOG.md README.md
git commit -m "chore: bump to X.Y.Z, update CHANGELOG and README"
git push origin main
```

### 8. Build the release APK

```bash
flutter build apk --release
```

Fix any build errors before continuing.

### 9. Copy and rename the APK

```bash
cp build/app/outputs/flutter-apk/app-release.apk build/app/outputs/flutter-apk/audiovault-X.Y.Z.apk
```

### 10. Create the GitHub release

Use `gh release create` with the tag `vX.Y.Z`, a human-readable title, and release notes drawn from the new CHANGELOG entry. Attach the renamed APK.

```bash
gh release create vX.Y.Z \
  "build/app/outputs/flutter-apk/audiovault-X.Y.Z.apk#audiovault-X.Y.Z.apk" \
  --title "AudioVault X.Y.Z" \
  --notes "<release notes here>"
```

The release notes should match the new CHANGELOG entry — same bullets, same sections. Add a footer line linking to the full CHANGELOG:

```
---
[Full changelog](https://github.com/mattsteednz/audiovault/blob/main/CHANGELOG.md)
```

### 11. Confirm

Report back with:
- Previous version → new version
- GitHub release URL
- APK filename and approximate size
- Summary of what's in the release
