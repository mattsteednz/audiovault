# Kōwhai Audiobook Player

A Flutter audiobook player for Android and iOS with background playback, position persistence, and a Material 3 UI themed in warm amber and brown tones.

## Features

- **Library scanning** — points at any folder and recursively finds audiobooks organised as subfolders of audio files (MP3, M4B, AAC, FLAC, OGG), including author/series grouping up to three levels deep. Reads `metadata.opf` files (Calibre/OverDrive) for richer metadata including series and narrator.
- **Google Drive** — connect a Drive folder to stream or download your cloud audiobook collection alongside local books
- **Cover art** — embedded art from audio metadata, `cover.jpg` fallback, and optional background enrichment from Open Library
- **Background playback** — lock-screen and notification media controls via `audio_service`
- **Google Cast** — stream to any Chromecast or Cast-enabled speaker from the player
- **Chapter navigation** — chapter list from audio metadata; M4B QuickTime chapter tracks fully supported
- **Position persistence** — resumes exactly where you left off; positions backed up to `positions.json` alongside your books, with optional Drive sync
- **Bookmarks** — save named moments while listening; jump back from the player or book details screen
- **Book status** — automatically tracked as Not started, In progress, or Finished; filter the library by status
- **Playback controls** — variable speed (0.5×–3.0×), configurable skip interval, sleep timer with library AppBar countdown, smart rewind on resume
- **Library** — grid/list toggle, sort by last played/title/author/date/duration, inline search, filter sheet, frosted-glass mini player
- **Settings** — audiobooks folder, Drive connection and sync, theme (light/dark/system), enrichment, rewind, skip interval, startup scan, telemetry

## Getting Started

### Prerequisites

- Flutter 3.x
- Android Studio or Xcode for device/emulator deployment

```bash
flutter pub get
flutter run
```

## Firebase / Telemetry Setup

The Firebase configuration files **are committed** (`android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`, `lib/firebase_options.dart`) and contain this project's client API keys. These keys are public identifiers by design — Firebase secures them via package-name/bundle-ID restrictions and (optionally) App Check, not secrecy. They are committed so release builds work from CI without extra secret plumbing.

To fork with your own Firebase project:

1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Register Android (`com.mattsteed.kowhai`) and iOS apps with your own identifiers
3. Run `flutterfire configure --project=<your-project-id>`
4. Replace the three config files above with your generated ones
5. In your Firebase console, enforce API-key restrictions (Android/iOS app restrictions) and consider enabling App Check

Telemetry is consent-gated: the app asks before any analytics or crash reporting, works fully without valid config, and uninstalls its crash handlers if consent is revoked.

## Tech Stack

| Area | Package |
|---|---|
| Audio playback | `just_audio` + `audio_service` |
| Google Cast | `flutter_chrome_cast` |
| Google Drive | `googleapis` + `google_sign_in` |
| Audio metadata | `audio_metadata_reader` + `xml` |
| Position persistence | `sqflite` |
| Service locator | `get_it` |
| Crash reporting & analytics | `firebase_crashlytics`, `firebase_analytics` |
| UI | Flutter Material 3 |

## Android Permissions

Kōwhai requests `MANAGE_EXTERNAL_STORAGE` on Android 11+ to browse the full file system for audiobooks.

## License

MIT
