# prd-50 — Chunk L: UI Performance & Responsiveness

Status: [ ] not started / [x] done
Branch: `perf/ui-responsiveness`
Files disjoint from Chunks B/C (safe parallel branch). Each item is small and
independently committable.

## Tasks
- [x] L1. MiniPlayer rebuild scoping (widgets/mini_player.dart): today TWO
      nested StreamBuilders (:21 playbackState, :35 effectivePositionStream)
      wrap the ENTIRE bar incl. BackdropFilter blur → full repaint ~5×/s.
      Restructure: outer StreamBuilder(playbackState) keeps visibility/blur/
      cover/text; position consumed by a small inner widget containing ONLY the
      progress bar + "x left" text. Blur surface must NOT be inside any
      per-tick subtree. Verify: flutter run + devtools rebuild counts, note
      result here.
- [x] L2. Sleep-timer full-screen rebuild (screens/player_screen.dart:105-110):
      `_sleepListener` does setState((){}) on a 1 Hz notifier → whole screen
      rebuilds every second while timer active. Remove the listener; render
      chips via scoped ValueListenableBuilder on SleepTimerController.remaining
      / stopAtChapterEnd (pattern already exists in sleep_timer_indicator.dart).
      Manual check: timer running → only chip area repaints.
- [x] L3. Search debounce (~150 ms) in library_screen search field (:759-797):
      keystrokes currently re-run the full filter pipeline synchronously.
      Timer-based debounce; clear-search must flush immediately. Also hoist
      lowercase haystack computation out of the per-item loop if trivially
      doable without changing filterBooks' pure signature (precompute map
      book→haystack alongside books list).
- [x] L4. Persist view mode: promote private _ViewMode to models/ (or reuse
      availability_filter_state.dart pattern), store via PreferencesService
      get/setViewMode, load during _initLibrary, save on toggle. Round-trip
      test in preferences_service_test. Grid/list survives relaunch.
- [x] L5. Enrichment default mismatch: onboarding_screen.dart checkbox defaults
      FALSE while PreferencesService.getMetadataEnrichment defaults TRUE —
      first-run users who never touch the box get enrichment off, settings
      screen claims otherwise. Align: onboarding initial value reads the pref
      default (true) unless user toggles. Test/verify onboarding flow manually;
      note result.
- [x] L6. Dead ternary cleanup player_screen.dart:627-629 (both arms identical)
      — delete, keep single expression.
- [x] L7. Gate green. Commits: `perf(mini-player): scope position rebuilds`,
      `perf(player): sleep timer chip-scoped updates`, `feat(library): persist
      view mode`, `fix(onboarding): align enrichment default with settings`.

## Implementation notes (2026-08-23)
- L1: MiniPlayer split - outer playbackState StreamBuilder owns blur/cover/
  title/button; position ticks now repaint only _MiniProgress (2px bar) and
  _MiniRemainingLabel. BackdropFilter is outside all per-tick subtrees.
- L3: 150 ms debounce on search; clear-search and clear-all-filters flush
  immediately and cancel any pending timer.
- L4: view mode persisted via PreferencesService.getViewMode/setViewMode
  (string-based, unknown values fall back to grid). Preservation suite stub
  added; mocks regenerated.
- Manual smoke items (rebuild counts, timer chip repaint) left for the owner -
  noted as follow-ups below.

## Follow-ups
- [ ] Owner smoke check: devtools rebuild counts on library screen with mini
      player visible (expect ~5 Hz repaint limited to progress bar + label).
- [ ] Owner smoke check: sleep timer running only repaints the chip area.
