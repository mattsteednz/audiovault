# Changelog

All notable changes to AudioVault are documented here.

## [Unreleased]

---

## [1.0.5] — 2026-04-11

### Added

- **Fine-grained playback speed** — Speed chip opens a dialog with a 0.5×–3.0× slider (0.05× steps) and quick-select chips for 0.75×, 1.0×, 1.25×, 1.5×, 2.0×, 2.5×. Live preview while dragging; Cancel reverts.
- **Custom skip interval** — New "Skip interval" setting (10 / 15 / 30 / 45 / 60 s). Rewind and fast-forward buttons update to match, including notification controls.
- **Custom sleep timer** — "Custom…" option at the bottom of the sleep timer menu opens a 1–180 minute picker.

---

## [1.0.4] — 2026-04-11

### Added

- **Library search** — Tap the search icon in the library AppBar to filter books by title or author (case-insensitive, partial match). A clear button appears while typing; back arrow dismisses search and resets the list.

---

## [1.0.3] — 2026-04-09

### Added

- **About screen** — Accessible from the bottom of Settings. Shows app name, version, links to the AudioVault website, privacy policy, and source code, plus a full third-party licences screen.
- **Third-party licences screen** — Lists all direct open-source dependencies with SPDX badge, copyright, and expandable full licence text (verbatim where required by BSD/Apache-2.0 terms).
- **App icon** — Custom vault-door icon replaces the Flutter default, applied across all Android mipmap densities (mdpi → xxxhdpi) with adaptive foreground layer and a matching 512 × 512 Play Store asset.

### Fixed

- **`path_provider_android` pinned to 2.2.23** — Prevents `path_provider_android ≥ 2.3.x` from pulling in `jni`/`jni_flutter`, which require NDK to compile `libdartjni.so`. Without NDK the `.so` is absent from the APK and the scanner crashes at runtime.

### Dependencies

- Added `package_info_plus: ^8.0.0`
- Added `url_launcher: ^6.3.0`
- Bumped `firebase_core` → `^4.0.0`, `firebase_analytics` → `^12.0.0`, `firebase_crashlytics` → `^5.0.0`
- Bumped `flutter_lints` → `^6.0.0`
- `path_provider_android` held at `2.2.23` via `dependency_overrides`

---

## [1.0.2] — 2026-04-08

### Added

- **Smart rewind on resume** — Playback automatically rewinds when you resume after a break: 10 s after 5 min, 15 s after 1 hour, 30 s after 24 hours. Toggleable via a new "Smart rewind on resume" switch in Settings (on by default).
- **Full Cast playback routing** — All playback controls (play, pause, seek, chapter skip, rewind, fast-forward, speed) now route to the Cast device when a Cast session is active. Previously only load/connect was wired up; everything else still drove local playback.
- **VPN warning in Cast picker** — A warning banner is shown in the Cast device picker when a VPN connection is detected, as VPNs routinely prevent Cast discovery and streaming.
- **`CastServer`** — Lightweight on-device HTTP server (with HTTP Range support) that serves local audio files over the LAN so Cast devices can stream them directly.
- **`effectivePositionStream` / `effectiveDurationStream`** — New streams on `AudioVaultHandler` that transparently emit local or Cast position/duration depending on the active playback mode. All UI that previously read `player.positionStream` now reads these.
- **`TelemetryService.logEvent`** — Static helper for logging custom Firebase Analytics events; no-ops when Firebase is unavailable.
- **`get_it` service locator** — Services (`PositionService`, `PreferencesService`, `ScannerService`, `EnrichmentService`) are now registered as lazy singletons via `get_it` and resolved through `locator.dart`, enabling proper DI for testing.
- **Unit tests** — Tests for `AudioVaultHandler` (rewind offsets, global position calculation) and `ScannerService`.

### Fixed

- **Chapter index off-by-one at boundaries** — The chapter elapsed/remaining time display now uses the raw playback position for chapter lookup instead of a second-snapped value, preventing a ~1 s window where the previous chapter was shown right after crossing a chapter boundary.
- **Mini player position during Cast** — Mini player progress and remaining-time label now use `effectivePositionStream` and skip `player.currentIndex` when casting.
- **Hidden files and folders excluded from scan** — The library scanner now ignores files and directories whose names start with `.` (e.g. `.DS_Store`, `.Spotlight-V100`).

### Changed

- Service singletons (`PositionService`, `PreferencesService`, `ScannerService`, `EnrichmentService`) converted from factory constructors to `get_it` lazy singletons; singleton factories removed from the service classes themselves.
- `_globalPositionMs()` refactored into a public static `calculateGlobalPosition()` method (`@visibleForTesting`) for unit testability.
- Firebase is now initialized with `DefaultFirebaseOptions.currentPlatform` from the generated `firebase_options.dart`.

### Dependencies

- Added `get_it: ^9.2.1`
- Added `mockito: ^5.6.4` (dev)
- Added `build_runner: ^2.13.1` (dev)

---

## [1.0.1] — 2026-04-06

### Added

- **Google Cast support** — Cast button in the player AppBar opens a device picker to start or stop casting to nearby Google Cast devices.
- **Chapter list for M4B books** — Single-file M4B audiobooks with embedded QuickTime chapter tracks now display a tappable "Chapter X of Y" label and a navigable chapter list sheet, matching the existing experience for multi-file MP3 books.
- **Light/dark/system theme** — Color mode setting (Follow system / Light / Dark), persisted and applied live without restarting the app. Theme is read before the first frame to avoid a flash on launch.
- **Metadata enrichment** — New `EnrichmentService` fetches missing cover art from [Open Library](https://openlibrary.org) in the background after a library scan. Covers are downloaded to the app cache and persisted in a separate SQLite database (`audiovault_enrichment.db`). Already-enriched books are skipped; failed lookups are retried no more than once per day.
- **"Get missing covers & metadata" toggle** — Settings switch (enabled by default) to start or stop background enrichment. Turning it off immediately cancels any in-progress queue.
- **`Audiobook.copyWith`** — Immutable helper on the `Audiobook` model for updating `coverImagePath` or `coverImageBytes` without recreating the full object.
- **`BookCover` widget** — Shared widget for rendering cover art (image or placeholder icon), replacing duplicated `_cover`/`_placeholder` methods across five files.
- **`AudioHandlerScope` InheritedWidget** — Provides `audioHandler` and `themeModeNotifier` via the widget tree, replacing the top-level global variable.

### Fixed

- **Chapter time labels** — The time display below the player progress bar now shows elapsed and remaining time within the current chapter (`mm:ss` / `-mm:ss`) rather than the global book position and total duration. Both labels update in lock-step on the same second boundary.
- **M4B chapter parsing** — Single-file M4B audiobooks with QuickTime chapter tracks (iTunes/Audible format) now correctly parse and display chapter information. `co64` (64-bit chunk offsets) is also supported for future-proofing.
- **Natural file sort** — Audio files inside a folder are now sorted by the natural numeric order of their filenames (e.g. `2.mp3 < 10.mp3 < 100.mp3`) instead of lexicographic order, fixing chapter sequencing for multi-file audiobooks.
- **Audio stream error handling** — Added `onError` callbacks to `playbackEventStream` and `currentIndexStream` listeners so playback errors are logged rather than silently swallowed.
- **Sleep timer off-by-one** — Timer now decrements before checking the zero threshold, so a 5-minute timer runs for exactly 5 minutes.
- **Mini player progress** — Fixed mini player progress bar showing per-file progress instead of global book progress for multi-file audiobooks.
- **History screen unreachable** — Wired up the history button in the library AppBar; the screen was fully implemented but had no navigation path.
- **Playback completion** — Position is now saved when `processingState` reaches `completed`, so resume works correctly after finishing a book.
- **M4B notification chapter count** — Fixed notification metadata reporting 1 chapter (the file count) instead of the actual embedded chapter count.

### Changed

- **Settings screen redesigned** — Each setting now uses an icon + title + current-value subtitle layout. Color mode opens a dialog picker (icon, label, and checkmark for the active selection). Section groups are separated by plain dividers with no header labels.
- `chapterIndexAt` logic moved from `AudioVaultHandler` and `PlayerScreen` into the `Audiobook` model to eliminate duplication.
- `PreferencesService` is now a proper singleton with a cached `SharedPreferences` instance.
- `PreferencesService` gains `getThemeMode` / `setThemeMode` and `getMetadataEnrichment` / `setMetadataEnrichment` methods.
- Position is saved on `stop()` to prevent losing progress when the OS kills the audio service.
- Library scan now applies previously cached covers immediately (before enrichment runs) so the UI is populated from the first render.
- Completed PRDs moved to `prd/done/`.

### Dependencies

- Added `http: ^1.2.0` for Open Library API requests.

---

## [1.0.0] — 2025

Initial release.

- Audiobook library scanner (folder-based, M4B/MP3/FLAC/etc.)
- Full-screen player with chapter list and progress scrubbing
- Mini player in library grid/list view
- Resume playback from last position (SQLite persistence)
- Sort library by last played / alphabetical
- Firebase Analytics & Crashlytics (opt-in, consent gate)
- Android: `MANAGE_EXTERNAL_STORAGE` for full file system access
