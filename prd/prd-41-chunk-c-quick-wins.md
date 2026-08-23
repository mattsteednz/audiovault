# prd-41 — Chunk C: Quick-Win Batch (R11, R12, R19, R16, R25, R23)

Status: [ ] not started / [x] done
Branch: `fix/quick-wins`
Six small, independent, user-visible improvements. One commit per item.

## Tasks
- [ ] C1 (R11) Persist status filter like availability filter.
      PreferencesService: add `_statusFilterKey`, get/set using BookStatus name
      (null = all). library_screen: load in _initLibrary alongside availability;
      save on pill tap + clear-all. Reset to null on load is NOT needed
      (status filter is meaningful without Drive).
      Test: preferences_service_test round-trip; helper already pure.
- [ ] C2 (R12) Stop firing futures inside build.
      library_screen `_list()` loops `_ensureDownloadSizeLabel(b)` per rebuild.
      Move population into `_applySort()` (after books computed, before
      setState) guarded by the same `_downloadSizeLabels` cache. Keep the
      mounted checks. Remove call from `_list()`.
- [ ] C3 (R19) Defer startup work past first frame (main.dart):
      restoreSession(), resetStaleDownloads(), Drive auto-restore check → wrap
      in `WidgetsBinding.instance.addPostFrameCallback` AFTER runApp? Careful:
      AudioService.init MUST stay pre-runApp (handler required by UI).
      Safe ordering: keep AudioService.init awaited; move Drive session restore
      + resetStaleDownloads + theme read? NO — theme must stay pre-frame (no
      flash). Move only: restoreSession, resetStaleDownloads, drive position
      auto-restore block into post-frame callback. Cast init can also defer
      (fire-and-forget today anyway) — keep as-is to limit scope.
- [ ] C4 (R16) Make `_scanStatus` live through scan phases:
      set 'Scanning device folder…' when local path != null,
      'Checking Google Drive…' before rescanDrive/loadDriveBooks,
      'Loading covers…' while applying cached covers.
      Pass via existing setState; overlay cross-fades already handle changes.
- [ ] C5 (R25) Theme the download badge: drive_download_overlay.dart replace
      `const Color(0xfff4bd6f)` with Theme primary (widget has context in
      build; move color resolution there). Keep white icon.
- [ ] C6 (R23) Bookmark delete undo:
      player_screen `_BookmarksSheet._delete` and book_details
      `_BookmarksSection._delete`: capture Bookmark before delete, show
      ScaffoldMessenger snackbar w/ action re-adding via addBookmark
      (preserving label/notes/position/chapter; new id ok). 4s duration.
      Shared helper? Two call sites — acceptable to duplicate a 10-line
      `_deleteWithUndo(BuildContext, Bookmark)` OR put static helper in
      PositionService-adjacent util. Prefer small shared function in
      `lib/utils/bookmark_undo.dart` used by both.

## Verification per item
- analyze --fatal-warnings + flutter test green.
- Manual smoke notes appended to this file by implementing agent:
  (leave a one-line result note under each task when done)
