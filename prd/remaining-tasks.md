# Remaining PRDs — Summary

**Session Status:** 4 P3 UX tasks completed (PRD-12, 27, 29, 32). 234 tests passing. Release APK installed on Pixel 10.

## By Priority

### P2 (High)
- **prd-22** — Unpin `path_provider_android` 2.2.23 after NDK setup (blocked on user-side infrastructure)

### P3 (Medium)

#### Code Quality / Maintenance
- **prd-13** — DRY up position-service status derivation (duplicate logic in `position_service.dart:158-204`)
- **prd-14** — Configure scanner recursion depth constant (magic number `2` vs. CHANGELOG's "three levels")
- **prd-15** — Guarantee enrichment cancellation timeout (cancel flag has no timeout in `enrichment_service.dart`)
- **prd-23** — Use `dart:async.unawaited()` instead of custom wrapper in `onboarding_screen.dart:321`
- **prd-24** — Log Cast init errors instead of swallowing in `main.dart:53-70`

#### UX / Accessibility
- **prd-28** — Visual feedback during cover enrichment (subtle per-book enrichment indicator)
- **prd-30** — Accessibility audit (touch targets ≥48dp, semantic labels, 200% font scale test)
- **prd-31** — Combine search and filter (AND-compose library search with status filter)
- **prd-33** — Sleep timer visible outside player (show countdown in mini-player / AppBar)

### P4 (Nice-to-Have / Future)
- **prd-16** — Extract HTTP range-parser utility (reusable helper from `cast_server.dart`)
- **prd-34** — Chapter bookmarks (pinned chapters / in-book bookmarks)
- **prd-35** — Queue management for multi-file books (quick jump to files from player)

### Legacy / Unclear Status
- **prd-2** — Remote repository (appears to be setup/reference doc, not an actionable PRD)
- **prd-6** — Google Drive (appears to be setup/reference doc, not an actionable PRD)

## Next Steps

1. **Immediate (if continuing):**
   - **prd-31** (search+filter AND-composition) — medium effort, high UX value
   - **prd-30** (a11y audit) — foundational work across multiple screens
   - **prd-13** (position-service DRY) — small code-quality win

2. **Blocked:**
   - **prd-22** requires NDK setup on your dev machine

3. **Deferred:**
   - P4 items (bookmarks, queue mgmt) are future enhancements

## Completed This Session
1. **prd-12** (P2) — Refactor AudioVaultHandler god class (762 → 418 lines, 5 extracted classes)
2. **prd-27** (P3) — Label startup loading states ("Checking settings…", "Loading library…")
3. **prd-29** (P3) — Surface playback errors with retry snackbar + disabled controls
4. **prd-32** (P3) — Library sort menu (Title, Author, Date added, Duration, Last played)

**Test Coverage:** 234 passing, 0 failed. Analyzer clean.
