# /complete — Feature completion checklist

Run this command when a feature is ready to ship. It will verify tests, analyse code, update docs, bump the version, and merge to main.

## Steps

### 1. Identify the feature scope

Review recent commits on the current branch (or recent commits to main if already on main) to understand what was changed:

```bash
git log --oneline main..HEAD 2>/dev/null || git log --oneline -10
```

Summarise the change in one sentence. Then classify it:
- **medium** — new user-facing feature or significant behaviour change → bump minor version (1.2.x → 1.3.0, reset build to 0... but since this project uses semver+build, do 1.2.1 → 1.3.0+0, or more precisely bump the second number of the semver part)
- **small** — bug fix, polish, minor enhancement → bump build number only (1.2.1+3 → 1.2.1+4)

The version is in `pubspec.yaml` as `version: MAJOR.MINOR.PATCH+BUILD`.

### 2. Check for missing tests

Look at the files changed in this feature. For any new service methods, utility functions, or non-trivial logic, check whether a corresponding test exists in `test/`. If tests are missing for testable logic, write them before proceeding.

Testable = pure functions, service methods with injectable dependencies, data transformations.
Not required = UI widgets, platform calls, fire-and-forget async side effects.

### 3. Run static analysis

```bash
flutter analyze
```

Fix any errors or warnings before continuing.

### 4. Run tests

```bash
flutter test
```

All tests must pass. Fix failures before continuing.

### 5. Update CHANGELOG.md

Add an entry at the top of CHANGELOG.md under an `## Unreleased` section (or create a new versioned section if releasing). Format:

```
## [MAJOR.MINOR.PATCH+BUILD] — YYYY-MM-DD

### Added / Changed / Fixed
- <concise bullet describing each user-visible change>
```

### 6. Update README.md

Update any sections that describe features, capabilities, or setup steps affected by this change. Keep it factual and concise — no marketing language.

### 7. Bump version in pubspec.yaml

- **medium change**: increment MINOR, reset PATCH to 0, reset BUILD to 0
  - e.g. `1.2.1+3` → `1.3.0+0`
- **small change**: increment BUILD only
  - e.g. `1.2.1+3` → `1.2.1+4`

### 8. Commit

Stage all modified files and commit:

```bash
git add -A
git commit -m "<type>(<scope>): <description>

<optional body with more detail>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

Use conventional commit types: `feat`, `fix`, `refactor`, `chore`, `docs`.

### 9. Merge to main and clean up

If on a feature branch:

```bash
BRANCH=$(git branch --show-current)
git checkout main
git pull origin main
git merge --squash $BRANCH
git commit -m "<feat|fix>(PRD-X): <feature title>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
git push origin main
git branch -d $BRANCH
git push origin --delete $BRANCH 2>/dev/null || true
```

If already on main, just push:

```bash
git push origin main
```

### 10. Confirm

Report back with:
- Version bumped from → to
- Test count
- What was added to CHANGELOG
- Branch status
