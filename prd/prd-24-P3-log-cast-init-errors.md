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

## Implementation Plan
1. In `lib/main.dart:53-70`, replace `catch (_) {}` with `catch (e, st) { debugPrint('[Cast] init failed: $e\n$st'); TelemetryService.instance.recordNonFatal(e, st); }`.
2. Confirm `TelemetryService.recordNonFatal` exists (guarded by `_available` + consent); if not, add a thin wrapper around `FirebaseCrashlytics.instance.recordError`.
3. Ensure `import 'package:flutter/foundation.dart';` is present for `debugPrint`.
4. Manually test graceful degradation: run on a device without Cast framework (iOS sim or Android without Play Services) and confirm app launches plus log line appears in `adb logcat`.

## Files Impacted
- `lib/main.dart` (catch block)
- `lib/services/telemetry_service.dart` (add `recordNonFatal` if missing)
