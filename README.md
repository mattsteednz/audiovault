# AudioVault

A Flutter audiobook player for Android and iOS with background playback, position persistence, and a clean Material 3 dark UI.

## Features

- **Library scanning** — point AudioVault at any folder; it recursively finds audiobooks organised as subfolders of audio files (MP3, M4B, AAC, FLAC, OGG)
- **Cover art** — reads embedded cover art from audio metadata; falls back to a `cover.jpg` / `folder.jpg` in the book folder
- **Background playback** — continues playing when the screen is off or you switch apps, with a lock-screen / notification media control
- **Chapter navigation** — chapter list drawn from audio metadata; swipe or tap to jump between chapters
- **Position persistence** — resumes exactly where you left off across app restarts, using a local SQLite database
- **Book status tracking** — books are automatically marked Not started, In progress, or Finished; filter the library by status using the pill row at the top
- **Last-played sort** — library sorted by most recently played; unread books follow alphabetically
- **Mini player** — persistent strip at the bottom of the library shows the current book title, remaining time, and a play/pause button
- **Settings screen** — change the audiobooks folder and manage telemetry preference without leaving the app
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

The repo ships with **placeholder** Firebase config files so the project compiles without a real Firebase project:

- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

> **Note on the `current_key` in `google-services.json`:** Static analysis tools (e.g. Amazon Q, GitGuardian) flag the `current_key` field in this file as a hardcoded credential. It is **not a secret** — it is the Firebase Android API key, which is a public client identifier [intentionally embedded in shipped apps](https://firebase.google.com/docs/projects/api-keys). Firebase security is enforced via SHA-1 certificate fingerprints and server-side rules, not by keeping this key private. The flag can be safely dismissed.

The app catches Firebase init failures silently and runs without telemetry if the config is a placeholder. To enable real crash reporting and analytics:

1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Register Android (`com.mattsteed.audiovault`) and iOS (`com.mattsteed.audiovault`) apps
3. Download and replace the config files above
4. Or run `flutterfire configure --project=<your-project-id>` to do it automatically

## Tech Stack

| Area | Package |
|---|---|
| Audio playback | `just_audio` + `audio_service` |
| Background / lock-screen controls | `audio_service` |
| Audio metadata | `audio_metadata_reader` |
| Position persistence | `sqflite` |
| Preferences | `shared_preferences` |
| File/folder picker | `file_picker` |
| Permissions (Android) | `permission_handler` |
| Crash reporting & analytics | `firebase_crashlytics`, `firebase_analytics` |
| UI | Flutter Material 3 dark theme |

## Project Structure

```
lib/
  main.dart                  # App entry, Firebase init, consent gate
  models/
    audiobook.dart           # Audiobook data model
  screens/
    consent_screen.dart      # First-run telemetry consent
    library_screen.dart      # Book grid/list + mini player
    onboarding_screen.dart   # First-run folder selection
    player_screen.dart       # Full-screen player
    settings_screen.dart     # Folder + telemetry settings
  services/
    audio_handler.dart       # AudioVaultHandler (audio_service)
    position_service.dart    # SQLite position persistence
    preferences_service.dart # SharedPreferences wrapper
    scanner_service.dart     # Folder scanner + metadata reader
    telemetry_service.dart   # Firebase analytics/crashlytics guard
  widgets/
    audiobook_card.dart      # Grid card widget
    audiobook_list_tile.dart # List row widget
```

## Android Permissions

AudioVault requests `MANAGE_EXTERNAL_STORAGE` on Android 11+ to browse the full file system for audiobooks. The permission prompt is shown when the user taps "Select Folder" in Settings or Onboarding.

## License

MIT
