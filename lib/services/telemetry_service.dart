import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Wraps Firebase Analytics + Crashlytics.
///
/// All methods are safe to call even if Firebase failed to initialise (e.g.
/// placeholder config files in use) — errors are caught and ignored silently.
class TelemetryService {
  static bool _available = false;

  /// Call once after [Firebase.initializeApp] succeeds.
  static void markAvailable() => _available = true;

  /// Apply the user's consent choice.  Safe to call multiple times.
  static Future<void> applyConsent(bool enabled) async {
    if (!_available) return;
    try {
      await FirebaseAnalytics.instance
          .setAnalyticsCollectionEnabled(enabled);
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(enabled);
      if (enabled) {
        await FirebaseAnalytics.instance.logAppOpen();
      }
    } catch (e) {
      debugPrint('[AudioVault:Telemetry] applyConsent error: $e');
    }
  }

  /// Log a custom analytics event.  No-ops when Firebase is unavailable.
  static Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    if (!_available) return;
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: name,
        parameters: parameters,
      );
    } catch (e) {
      debugPrint('[AudioVault:Telemetry] logEvent error: $e');
    }
  }

  /// Wire Crashlytics into Flutter's error handler.
  /// Only called when Firebase is available and the user has opted in.
  static void enableCrashHandler() {
    if (!_available) return;
    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }
}
