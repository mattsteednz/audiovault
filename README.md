# AudioVault

A Flutter audiobook player for Android and iOS with background playback, position persistence, and a clean Material 3 dark UI.

## Features

- **Library scanning** — point AudioVault at any folder; it recursively finds audiobooks organised as subfolders of audio files (MP3, M4B, AAC, FLAC, OGG), including author/series grouping folders up to three levels deep
- **Google Drive library** — connect a Google Drive folder to stream or download your cloud audiobook collection alongside local books
- **Cover art** — reads embedded cover art from audio metadata; falls back to a `cover.jpg` / `folder.jpg` in the book folder; optional background enrichment fetches missing covers from Open Library
- **Background playback** — continues playing when the screen is off or you switch apps, with a lock-screen / notification media control
- **Google Cast** — stream to any Chromecast or Cast-enabled speaker directly from the player
- **Chapter navigation** — chapter list drawn from audio metadata; swipe or tap to jump between chapters; M4B embedded QuickTime chapter tracks fully supported
- **Position persistence** — resumes exactly where you left off across app restarts, using a local SQLite database
- **Book status tracking** — books are automatically marked Not started, In progress, or Finished; filter the library by status using the pill row at the top
- **Last-played sort** — library sorted by most recently played; unread books follow alphabetically
- **Mini player** — persistent strip at the bottom of the library shows the current book title, remaining time, and a play/pause button
- **Library search** — filter by title or author from the AppBar
- **Book details** — long-press any book for a details sheet with metadata and Drive download controls
- **Playback controls** — variable speed (0.5×–3.0×), configurable skip interval (10–60 s), custom sleep timer, smart rewind on resume
- **Settings screen** — audiobooks folder, Drive connection, theme (light/dark/system), enrichment, rewind, skip interval, startup scan toggle, and telemetry
- **Telemetry opt-in** — first-run consent prompt; anonymous crash reports and usage data via Google Firebase (can be toggled off anytime in Settings)

## Screenshots

_Coming soon_

## Getting Started

### Prerequisites

- Flutter 3.x (`flutter --version`)
- Android Studio or Xcode for device/emulator deployment
- A folder of audiobooks on your device (each book in its own subfolder)

### Install dependencies

```bash
flutter pub get
```

### Run

```bash
flutter run
```

## Firebase / Telemetry Setup

This repo is configured for the AudioVault Firebase project. The config files (`android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`) are set up for `com.mattsteed.audiovault` and are not included in the repository.

If you are forking this project, you will need to set up your own Firebase project:

1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Register Android and iOS apps with your own package identifier
3. Run `flutterfire configure --project=<your-project-id>` to generate the config files

The app catches Firebase init failures silently and runs without telemetry if no valid config is present.

## Tech Stack

| Area | Package |
|---|---|
| Audio playback | `just_audio` + `audio_service` |
| Background / lock-screen controls | `audio_service` |
| Google Cast | `flutter_cast_framework` |
| Google Drive | `googleapis` + `google_sign_in` |
| Audio metadata | `audio_metadata_reader` |
| Position persistence | `sqflite` |
| Preferences | `shared_preferences` |
| File/folder picker | `file_picker` |
| Permissions (Android) | `permission_handler` |
| Service locator | `get_it` |
| Crash reporting & analytics | `firebase_crashlytics`, `firebase_analytics` |
| UI | Flutter Material 3 dark theme |

## Project Structure

```
lib/
  main.dart                    # App entry, Firebase init, consent gate
  locator.dart                 # get_it service locator setup
  models/
    audiobook.dart             # Audiobook data model
  screens/
    about_screen.dart          # App info, licences, links
    book_details_screen.dart   # Book metadata + Drive download controls
    consent_screen.dart        # First-run telemetry consent
    history_screen.dart        # Recently played list
    library_screen.dart        # Book grid/list + mini player + AppBar
    onboarding_screen.dart     # First-run folder/Drive selection
    player_screen.dart         # Full-screen player with chapter list
    settings_screen.dart       # All app settings
  services/
    audio_handler.dart         # AudioVaultHandler (audio_service)
    cast_server.dart           # On-device HTTP server for Cast streaming
    drive_book_repository.dart # Drive file metadata DB
    drive_download_manager.dart# Download queue and progress events
    drive_library_service.dart # Drive scan, download, promote to local
    drive_service.dart         # Google Sign-In + Drive API wrapper
    enrichment_service.dart    # Background cover fetching (Open Library)
    position_service.dart      # SQLite position persistence
    preferences_service.dart   # SharedPreferences wrapper
    scanner_service.dart       # Folder scanner + metadata reader
    telemetry_service.dart     # Firebase analytics/crashlytics guard
  widgets/
    audio_handler_scope.dart   # InheritedWidget for audioHandler + theme
    audiobook_card.dart        # Grid card widget
    audiobook_list_tile.dart   # List row widget
    book_cover.dart            # Shared cover art / placeholder widget
    drive_folder_picker.dart   # Drive folder browser dialog
```

## Android Permissions

AudioVault requests `MANAGE_EXTERNAL_STORAGE` on Android 11+ to browse the full file system for audiobooks. The permission prompt is shown when the user taps "Select Folder" in Settings or Onboarding.

## License

MIT
