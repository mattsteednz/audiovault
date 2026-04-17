# PRD-24 (P3): Log Google Cast init errors instead of swallowing them

## Problem
Cast initialization is wrapped in `try { ... } catch (_) {}` so real configuration issues (missing plist entries, wrong app ID) are silently ignored — making Cast breakages painful to diagnose.

## Evidence
- `lib/main.dart:53-70`

## Proposed Solution
- `catch (e, st) { debugPrint('[Cast] init failed: $e\n$st'); }`.
- Optionally forward to `TelemetryService.recordNonFatal(e, st)` so Crashlytics sees it (guarded by consent).
- Keep the graceful-degradation behaviour — app must still start.

## Acceptance Criteria
- [ ] Cast init errors surface in logs (and Crashlytics if consented)
- [ ] App still starts when Cast is unavailable

## Out of Scope
- Surfacing a user-visible Cast-unavailable banner.
