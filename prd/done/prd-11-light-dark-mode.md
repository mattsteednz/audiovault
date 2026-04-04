# PRD: Light/Dark Mode Theming

## Summary
AudioVault currently forces a dark theme unconditionally by hardcoding `brightness: Brightness.dark` in `MaterialApp`'s `ThemeData`. This feature replaces that with a three-option theme mode setting (Follow system / Light / Dark), defaulting to "Follow system" on first use. The selected preference is persisted via `SharedPreferences` and applied at app startup before the first frame is painted.

## User story
As an AudioVault user, I want to choose whether the app follows my system theme, stays dark, or stays light, so that the app matches my personal preference and environment.

## Scope

### In scope
- A new persisted preference key `theme_mode` in `PreferencesService`, storing one of three string values: `system`, `light`, `dark`
- Default value of `system` (i.e. if the key is absent, treat as `system`)
- `AudioVaultApp` reads the stored preference and passes the corresponding `ThemeMode` to `MaterialApp`
- A light `ThemeData` using the same seed color `0xFF6B4C9A` with `brightness: Brightness.light`
- A new "Appearance" section in `SettingsScreen` with a three-option segmented button (Follow system / Light / Dark) that saves the choice immediately and rebuilds the app theme
- The theme change must take effect without restarting the app

### Out of scope
- Changing the existing dark color scheme, seed color, or any other visual design decisions
- Changing any screen other than `SettingsScreen` (no per-screen theming)
- Animated theme transitions
- Per-book or per-library theme overrides
- Scheduled theming (e.g. auto-dark at night)
- Any changes to consent, onboarding, or audio playback flows
- Adding or removing any other settings

## Existing behaviour to preserve
- The forced dark theme must remain the effective result when the user explicitly selects "Dark" — the visual output must be identical to the current app in that case
- The `_folderChanged` return value from `SettingsScreen` via `Navigator.pop(context, _folderChanged)` must continue to work exactly as it does today; the back button behaviour must not change
- All existing `SettingsScreen` sections (Audiobooks folder, Privacy/telemetry) must remain unchanged in position and behaviour
- `PreferencesService` must continue to expose all existing methods unchanged — new methods are additive only

## Implementation notes

### Files to change
- `lib/services/preferences_service.dart` — add `getThemeMode()` returning `String?` (null means absent, treat as `system`) and `setThemeMode(String value)`. Use the key `theme_mode`. No other changes to this file.
- `lib/main.dart` — `AudioVaultApp` must become a `StatefulWidget` (or use an `InheritedNotifier`/`ValueNotifier`) so it can rebuild when the theme mode changes. Read the stored preference before first build. Supply both a `theme:` (light `ThemeData`) and `darkTheme:` (existing dark `ThemeData`) to `MaterialApp`, and set `themeMode:` from the preference. Expose a way for `SettingsScreen` to trigger a rebuild (e.g. a top-level `ValueNotifier<ThemeMode>` or a callback passed down).
- `lib/screens/settings_screen.dart` — add an "Appearance" section (with `_sectionHeader`) above the existing "Audiobooks" section (Appearance → Audiobooks → Privacy). Add a `SegmentedButton<String>` (or equivalent) with three segments: Follow system, Light, Dark. Load the current preference in `_load()`. On change, call `PreferencesService().setThemeMode(value)` and notify `main.dart` to rebuild the theme. Do not change any existing sections.

### Files to read (but not modify)
- `lib/screens/library_screen.dart` — understand how `SettingsScreen` is pushed and its return value consumed, to ensure the `Navigator.pop` contract is not broken
- `lib/screens/player_screen.dart` — confirm it has no hardcoded `Brightness` references that would need updating (read-only check)

### Files to leave alone
- `lib/models/audiobook.dart` — no theming involvement
- `lib/services/audio_handler.dart` — no theming involvement
- `lib/services/position_service.dart` — no theming involvement
- `lib/services/scanner_service.dart` — no theming involvement
- `lib/services/telemetry_service.dart` — no theming involvement
- `lib/screens/consent_screen.dart` — no theming involvement; it appears before `AudioVaultApp` is fully rendered and will inherit whatever theme is active
- `lib/screens/onboarding_screen.dart` — no theming involvement
- `lib/widgets/` — widget files use `Theme.of(context)` and will automatically reflect the active theme; no changes needed

## Acceptance criteria
- [ ] Fresh install: app follows the system light/dark mode with no setting stored
- [ ] Selecting "Light" in Settings makes all screens render in the light theme immediately (no restart required)
- [ ] Selecting "Dark" in Settings makes all screens render identically to the current forced-dark app
- [ ] Selecting "Follow system" restores system-matched theming
- [ ] The selected theme mode survives an app restart (preference is persisted)
- [ ] The Audiobooks folder and Privacy sections in Settings are unchanged in appearance and function
- [ ] `Navigator.pop(context, _folderChanged)` still returns the correct bool to `LibraryScreen`

## Open questions
None. Decisions resolved:
1. **Section order:** Appearance appears above Audiobooks (order: Appearance → Audiobooks → Privacy).
2. **Cold start flash:** Theme mode preference must be read before `runApp`, in the existing async init block in `main()`, so the correct `ThemeMode` is passed to `AudioVaultApp` from the very first frame.
