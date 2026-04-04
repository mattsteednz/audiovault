# AudioVault — Claude Instructions

## Project Overview

AudioVault is a Flutter audiobook player app for Android and iOS.

- **Package name:** `com.mattsteed.audiovault`
- **Flutter package name:** `audiovault` (in pubspec.yaml)
- **Version:** 1.0.0+1
- **Theme:** Material 3 dark, seed color `0xFF6B4C9A`

## Flutter Setup

Flutter is installed at `C:\Users\Matt\dev\flutter` and is **not on Git Bash PATH**. To run Flutter commands use PowerShell or cmd, or prefix with the full path:

```bash
/c/Users/Matt/dev/flutter/bin/flutter <command>
```

## Architecture

```
lib/
  main.dart                  # App entry, Firebase init, consent gate, global audioHandler
  models/
    audiobook.dart           # Audiobook data model (title, chapters, chapterDurations, cover)
  screens/
    consent_screen.dart      # First-run telemetry consent (shown once)
    library_screen.dart      # Book grid/list + mini player + AppBar actions
    onboarding_screen.dart   # First-run folder selection
    player_screen.dart       # Full-screen player with chapter list
    settings_screen.dart     # Folder path + telemetry toggle
  services/
    audio_handler.dart       # AudioVaultHandler extends BaseAudioHandler (audio_service)
    position_service.dart    # SQLite position persistence (audiovault_positions.db)
    preferences_service.dart # SharedPreferences wrapper (library_path, analytics_consent)
    scanner_service.dart     # Folder scanner + audio_metadata_reader
    telemetry_service.dart   # Firebase analytics/crashlytics guard (no-ops if unavailable)
  widgets/
    audiobook_card.dart      # Grid card (cover, title, last-played date, active badge)
    audiobook_list_tile.dart # List row (same data as card)
```

## Key Patterns

### Global audio handler
`audioHandler` is a top-level `late` variable in `main.dart`, initialized via `AudioService.init()` before `runApp`. Accessible everywhere via `import '../main.dart'`.

### Firebase guard
All Firebase calls go through `TelemetryService`. Firebase init is wrapped in try-catch in `main()`; if it fails (placeholder config files), `TelemetryService._available` stays false and all calls are no-ops. Never call Firebase packages directly.

### Position persistence
`PositionService` is a singleton with lazy DB init. Schema stores `chapter_index`, `position_ms`, `global_position_ms`, `total_duration_ms`, `updated_at` (epoch ms). `getAllPositions()` returns rows ordered by `updated_at DESC` — used for last-played sort.

### Global position calculation
`Audiobook.chapterDurations: List<Duration>` is populated by the scanner from metadata. `AudioVaultHandler._globalPositionMs()` sums durations of completed chapters + current chapter position to get a true book-wide offset.

### Library sort
`_LibraryScreenState` keeps `_rawBooks` (scan order) and `_books` (sorted). `_applySort()` reads all DB positions, splits into played/unplayed, sorts played by `updated_at DESC` and unplayed alphabetically.

### Settings → library rescan
`SettingsScreen` returns `bool` via `Navigator.pop(context, _folderChanged)`. `LibraryScreen` calls `_scan()` if the returned value is `true`.

## Android

- `MainActivity` extends `AudioServiceActivity` (not `FlutterActivity`) — required by `audio_service ^0.18.x`
- AndroidManifest service class: `com.ryanheise.audioservice.AudioService`
- Requests `MANAGE_EXTERNAL_STORAGE` permission on Android 11+ for full file system access
- `google-services.json` in `android/app/` is a placeholder; replace with real file to enable Firebase

## iOS

- `GoogleService-Info.plist` in `ios/Runner/` is a placeholder
- Bundle ID: `com.mattsteed.audiovault`

## Key Dependency Notes

- **`just_audio ^0.9.0`** — always pass `initialPosition: Duration.zero` to `setAudioSource()` to prevent M4B edit-list offsets from skipping the beginning
- **`audio_service ^0.18.0`** — service class name changed from `AudioServiceBackground` to `AudioService` in this version
- **`audio_metadata_reader ^1.4.2`** — use only `album` tag for book title (never `title` tag, which contains track/chapter name)
- **`sqflite ^2.3.0`** — DB file is `audiovault_positions.db` in the app's documents directory

## Common Commands

```bash
# Run on connected device
flutter run

# Build Android APK
flutter build apk

# Get dependencies
flutter pub get

# Analyze
flutter analyze
```

## Firebase Setup (real project)

```bash
flutterfire configure --project=<your-firebase-project-id>
```

This replaces both placeholder config files automatically.

## Git

- Remote: `https://github.com/mattsteednz/audiovault`
- Default branch: `main`
