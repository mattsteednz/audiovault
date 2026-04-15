# AudioVault — Project Rules

## Project Overview

Flutter audiobook player for Android and iOS.

- Package: `com.mattsteed.audiovault`
- Flutter package: `audiovault` (pubspec.yaml)
- Theme: Material 3 dark, seed color `0xFF6B4C9A`
- Flutter installed at `C:\Users\Matt.Steed\dev\flutter\bin` (not on PATH — invoke via `cmd /c "c:\Users\Matt.Steed\dev\flutter\bin\flutter.bat"` or add to system PATH)

## Architecture

```
lib/
  main.dart                  # App entry, Firebase init, consent gate, global audioHandler
  locator.dart               # Service locator
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
    drive_service.dart       # Google Drive OAuth + file listing
    drive_library_service.dart    # Drive audiobook discovery
    drive_book_repository.dart    # Drive book metadata/caching
    drive_download_manager.dart   # Drive file download management
    position_service.dart    # SQLite position persistence (audiovault_positions.db)
    preferences_service.dart # SharedPreferences wrapper
    scanner_service.dart     # Folder scanner + audio_metadata_reader
    telemetry_service.dart   # Firebase analytics/crashlytics guard
  widgets/
    audiobook_card.dart      # Grid card (cover, title, last-played date, active badge)
    audiobook_list_tile.dart # List row
    drive_download_overlay.dart  # Download progress UI
    drive_folder_picker.dart     # Drive folder selection UI
```

## Key Patterns

### Global audio handler
`audioHandler` is a top-level `late` variable in `main.dart`, initialized via `AudioService.init()` before `runApp`. Access via `import '../main.dart'`.

### Firebase guard
All Firebase calls go through `TelemetryService`. Firebase init is wrapped in try-catch in `main()`; if it fails, `TelemetryService._available` stays false and all calls are no-ops. Never call Firebase packages directly.

### Position persistence
`PositionService` is a singleton with lazy DB init. Schema stores `chapter_index`, `position_ms`, `global_position_ms`, `total_duration_ms`, `updated_at` (epoch ms). `getAllPositions()` returns rows ordered by `updated_at DESC` for last-played sort.

### Global position calculation
`Audiobook.chapterDurations: List<Duration>` is populated by the scanner. `AudioVaultHandler._globalPositionMs()` sums durations of completed chapters + current chapter position.

### Library sort
`_LibraryScreenState` keeps `_rawBooks` (scan order) and `_books` (sorted). `_applySort()` splits into played/unplayed, sorts played by `updated_at DESC` and unplayed alphabetically.

### Settings → library rescan
`SettingsScreen` returns `bool` via `Navigator.pop(context, _folderChanged)`. `LibraryScreen` calls `_scan()` if the returned value is `true`.

## Dependency Notes

- **`just_audio ^0.10.0`** — use `setAudioSources()` (not deprecated `ConcatenatingAudioSource`). Pass `initialPosition: saved?.position` (nullable); just_audio 0.10 handles M4B edit-list offsets natively
- **`audio_service ^0.18.0`** — service class is `AudioService` (not `AudioServiceBackground`)
- **`audio_metadata_reader ^1.4.2`** — use only `album` tag for book title, never `title` (which contains track/chapter name)
- **`sqflite ^2.3.0`** — DB file is `audiovault_positions.db` in the app's documents directory

## Common Commands

```bash
flutter run           # Run on connected device
flutter build apk     # Build Android APK
flutter pub get       # Get dependencies
flutter analyze       # Analyze
```

## Firebase Setup

```bash
flutterfire configure --project=<your-firebase-project-id>
```

Replaces both placeholder config files (`android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`).

Note: the `current_key` in `google-services.json` is the public Firebase Android client identifier, not a secret. Security scanners will flag it — this is a known false positive. See README for details.

## Git

- Remote: `https://github.com/mattsteednz/audiovault`
- Default branch: `main`
