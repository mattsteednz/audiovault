import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Wraps Firebase Analytics + Crashlytics.
///
/// All methods are safe to call even if Firebase failed to initialise (e.g.
/// placeholder config files in use) — errors are caught and ignored silently.
class TelemetryService {
  static bool _available = false;
  static bool _consented = false;

  /// The handlers installed by [enableCrashHandler], so [disableCrashHandler]
  /// can restore what was there before (idempotent, repeat-safe).
  static void Function(FlutterErrorDetails)? _installedFlutterHandler;
  static bool Function(Object, StackTrace)? _installedPlatformHandler;

  /// Call once after [Firebase.initializeApp] succeeds.
  static void markAvailable() => _available = true;

  /// Whether the user has granted analytics consent. Event/recording APIs
  /// consult this directly — SDK-level gating alone is not defence in depth,
  /// and events can fire before consent is decided (e.g. init failures).
  static bool get consented => _consented;

  /// Apply the user's consent choice.  Safe to call multiple times.
  static Future<void> applyConsent(bool enabled) async {
    _consented = enabled;
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
      debugPrint('[Kowhai:Telemetry] applyConsent error: $e');
    }
  }

  /// Log a custom analytics event.  No-ops when Firebase is unavailable or
  /// consent has not been granted.
  static Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    if (!_available || !_consented) return;
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: name,
        parameters: parameters,
      );
    } catch (e) {
      debugPrint('[Kowhai:Telemetry] logEvent error: $e');
    }
  }

  /// Record a non-fatal error (e.g. a swallowed init failure) so it shows
  /// up in Crashlytics without crashing the app. No-op when Firebase is
  /// unavailable or the user hasn't consented.
  static Future<void> recordNonFatal(Object error, StackTrace stack) async {
    if (!_available || !_consented) return;
    try {
      await FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
    } catch (e) {
      debugPrint('[Kowhai:Telemetry] recordNonFatal error: $e');
    }
  }

  /// Wire Crashlytics into Flutter's error handler.
  /// Only called when Firebase is available and the user has opted in.
  static void enableCrashHandler() {
    if (!_available || !_consented) return;
    // Idempotent: don't stack duplicate handlers on repeated calls.
    if (_installedFlutterHandler != null) return;
    final flutterOnError = FlutterError.onError;
    _installedFlutterHandler = flutterOnError;
    FlutterError.onError = (details) {
      flutterOnError?.call(details);
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };
    final platformOnError = PlatformDispatcher.instance.onError;
    _installedPlatformHandler = platformOnError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  /// Restore the pre-consent error handlers. Called when the user revokes
  /// analytics consent so errors stop flowing to Crashlytics.
  static void disableCrashHandler() {
    if (_installedFlutterHandler != null) {
      FlutterError.onError = _installedFlutterHandler;
      _installedFlutterHandler = null;
    }
    if (_installedPlatformHandler != null) {
      PlatformDispatcher.instance.onError = _installedPlatformHandler;
      _installedPlatformHandler = null;
    }
  }
}
