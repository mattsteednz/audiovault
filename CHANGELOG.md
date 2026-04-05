# Changelog

All notable changes to AudioVault are documented here.

## [Unreleased]

### Added

- **Google Cast support** — Cast button in the player AppBar opens a device picker to start or stop casting to nearby Google Cast devices.
- **Chapter list for M4B books** — Single-file M4B audiobooks with embedded QuickTime chapter tracks now display a tappable "Chapter X of Y" label and a navigable chapter list sheet, matching the existing experience for multi-file MP3 books.
- **Light/dark/system theme** — New "Appearance" section in Settings with a segmented control (Follow system / Light / Dark). Selection is persisted and applied immediately without restarting the app. Theme is read before the first frame to avoid a flash on launch.
- **Metadata enrichment** — New `EnrichmentService` fetches missing cover art from [Open Library](https://openlibrary.org) in the background after a library scan. Covers are downloaded to the app cache and persisted in a separate SQLite database (`audiovault_enrichment.db`). Already-enriched books are skipped; failed lookups are retried no more than once per day.
- **"Get missing covers & metadata" toggle** — Settings switch (under Audiobooks, enabled by default) to start or stop background enrichment. Turning the toggle off immediately cancels any in-progress queue.
- **`Audiobook.copyWith`** — Immutable helper on the `Audiobook` model for updating `coverImagePath` or `coverImageBytes` without recreating the full object.

### Fixed

- **Chapter time labels** — The time display below the player progress bar now shows elapsed and remaining time within the current chapter (`mm:ss` / `-mm:ss`) rather than the global book position and total duration. Both labels update in lock-step on the same second boundary.
- **M4B chapter parsing** — Single-file M4B audiobooks with QuickTime chapter tracks (iTunes/Audible format) now correctly parse and display chapter information. `co64` (64-bit chunk offsets) is also supported for future-proofing.
- **Natural file sort** — Audio files inside a folder are now sorted by the natural numeric order of their filenames (e.g. `2.mp3 < 10.mp3 < 100.mp3`) instead of lexicographic order, fixing chapter sequencing for multi-file audiobooks.
- **Audio stream error handling** — Added `onError` callbacks to `playbackEventStream` and `currentIndexStream` listeners in `AudioVaultHandler` so playback errors are logged rather than silently swallowed.

### Changed

- `AudioVaultApp` converted from `StatelessWidget` to `StatefulWidget` to support reactive theme switching via `ValueListenableBuilder`.
- `PreferencesService` gains `getThemeMode` / `setThemeMode` and `getMetadataEnrichment` / `setMetadataEnrichment` methods.
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
