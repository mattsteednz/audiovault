import 'dart:async' show unawaited;
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'theme.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'screens/consent_screen.dart';
import 'screens/library_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/audio_handler.dart';
import 'services/drive_book_repository.dart';
import 'services/drive_download_manager.dart';
import 'services/drive_service.dart';
import 'services/position_backup_service.dart';
import 'services/position_service.dart';
import 'services/preferences_service.dart';
import 'services/telemetry_service.dart';
import 'firebase_options.dart';
import 'widgets/audio_handler_scope.dart';
import 'locator.dart';

ThemeMode _themeModeFromString(String? value) {
  switch (value) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setupLocator();

  // Restore Drive session silently (no-op if never signed in).
  // NOTE: kept BEFORE runApp deliberately — LibraryScreen's first scan reads
  // DriveService.currentAccount to decide filter/reset behaviour, so the
  // session must be resolved before the first frame to avoid a startup race.
  await locator<DriveService>().restoreSession();

  // Initialise audio service.
  final audioHandler = await AudioService.init<KowhaiHandler>(
    builder: KowhaiHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.mattsteed.kowhai.audio',
      androidNotificationChannelName: 'Kōwhai',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      fastForwardInterval: Duration(seconds: 30),
      rewindInterval: Duration(seconds: 30),
    ),
  );

  // Initialise Google Cast — silently ignored if not available.
  try {
    const appId = GoogleCastDiscoveryCriteria.kDefaultApplicationId;
    GoogleCastOptions options;
    if (Platform.isIOS) {
      options = IOSGoogleCastOptions(
        GoogleCastDiscoveryCriteriaInitialize.initWithApplicationID(appId),
        stopCastingOnAppTerminated: true,
      );
    } else {
      options = GoogleCastOptionsAndroid(
        appId: appId,
        stopCastingOnAppTerminated: true,
      );
    }
    GoogleCastContext.instance.setSharedInstanceWithOptions(options);
  } catch (e, st) {
    // Cast not available on this platform or emulator — app continues.
    debugPrint('[Kowhai:Cast] init failed: $e\n$st');
    // Fire-and-forget; telemetry is no-op if Firebase isn't ready yet.
    TelemetryService.recordNonFatal(e, st);
  }

  // Initialise Firebase — silently ignored if config files are placeholders.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    TelemetryService.markAvailable();
  } catch (_) {
    // Firebase not yet configured — app continues without telemetry.
  }

  // Read persisted theme mode before first frame so there is no flash.
  final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);
  final storedTheme = await locator<PreferencesService>().getThemeMode();
  themeModeNotifier.value = _themeModeFromString(storedTheme);

  // Auto-restore from Drive if local DB is empty and sync is enabled, plus
  // recovery of downloads interrupted by app kill — both deferred past the
  // first frame so they don't delay time-to-interactive.
  final prefs = locator<PreferencesService>();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_deferredStartupRecovery(prefs));
  });

  runApp(KowhaiApp(
    audioHandler: audioHandler,
    themeModeNotifier: themeModeNotifier,
  ));
}

/// Background recovery work that must not block startup:
/// * reset stale 'downloading' states left by a process kill
/// * restore positions from Drive on a fresh install when sync is enabled
Future<void> _deferredStartupRecovery(PreferencesService prefs) async {
  try {
    await locator<DriveBookRepository>().resetStaleDownloads();
  } catch (e) {
    debugPrint('[Kowhai:Startup] resetStaleDownloads failed: $e');
  }

  final syncEnabled = await prefs.getDriveProgressSync();
  if (!syncEnabled) return;
  final positions = await locator<PositionService>().getAllPositions();
  if (positions.isNotEmpty) return;
  final root = await prefs.getLibraryPath();
  if (root != null) {
    await locator<PositionBackupService>().restoreFromDrive(root);
  }
}

class KowhaiApp extends StatefulWidget {
  final KowhaiHandler audioHandler;
  final ValueNotifier<ThemeMode> themeModeNotifier;

  const KowhaiApp({
    super.key,
    required this.audioHandler,
    required this.themeModeNotifier,
  });

  @override
  State<KowhaiApp> createState() => _KowhaiAppState();
}

class _KowhaiAppState extends State<KowhaiApp> {
  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onPause: () => unawaited(
          locator<PositionBackupService>().onAppBackground()),
      onResume: () => unawaited(
          locator<DriveDownloadManager>().resumeInterruptedDownloads()),
    );
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }
  // Built once — createTextTheme() has no BuildContext dependency.
  static final _appTheme = MaterialTheme(createTextTheme());

  @override
  Widget build(BuildContext context) {
    return AudioHandlerScope(
      audioHandler: widget.audioHandler,
      themeModeNotifier: widget.themeModeNotifier,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: widget.themeModeNotifier,
        builder: (context, themeMode, _) {
          return MaterialApp(
            title: 'Kōwhai',
            debugShowCheckedModeBanner: false,
            theme: _appTheme.light(),
            darkTheme: _appTheme.dark(),
            themeMode: themeMode,
            home: const _AppEntryPoint(),
          );
        },
      ),
    );
  }
}

class _AppEntryPoint extends StatefulWidget {
  const _AppEntryPoint();

  @override
  State<_AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends State<_AppEntryPoint> {
  // null = still loading
  bool? _consentDecided;
  bool? _hasLibrary;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final prefs = locator<PreferencesService>();
    final consent = await prefs.getAnalyticsConsent();

    if (consent == null) {
      // First launch — show consent screen.
      if (!mounted) return;
      setState(() => _consentDecided = false);
      return;
    }

    // Consent already recorded — apply it and proceed.
    await TelemetryService.applyConsent(consent);
    if (consent) {
      TelemetryService.enableCrashHandler();
    } else {
      TelemetryService.disableCrashHandler();
    }

    final path = await prefs.getLibraryPath();
    final driveFolder = await prefs.getDriveRootFolder();
    if (!mounted) return;
    setState(() {
      _consentDecided = true;
      _hasLibrary = (path != null && path.isNotEmpty) || driveFolder != null;
    });
  }

  Future<void> _handleConsent(bool accepted) async {
    final prefs = locator<PreferencesService>();
    await prefs.setAnalyticsConsent(accepted);
    await TelemetryService.applyConsent(accepted);
    if (accepted) {
      TelemetryService.enableCrashHandler();
    } else {
      TelemetryService.disableCrashHandler();
    }

    final path = await prefs.getLibraryPath();
    final driveFolder = await prefs.getDriveRootFolder();
    if (!mounted) return;
    setState(() {
      _consentDecided = true;
      _hasLibrary = (path != null && path.isNotEmpty) || driveFolder != null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Loading.
    if (_consentDecided == null) {
      return const _StartupLoading(label: 'Checking settings…');
    }

    // First launch — show consent prompt.
    if (_consentDecided == false) {
      return ConsentScreen(onChoice: _handleConsent);
    }

    // Normal app flow.
    if (_hasLibrary == null) {
      return const _StartupLoading(label: 'Loading library…');
    }

    return _hasLibrary! ? const LibraryScreen() : const OnboardingScreen();
  }
}

/// Shared startup loading screen. Identical layout across phases so the
/// only thing that changes between "Checking settings…" and "Loading
/// library…" is the label — no spinner jump.
class _StartupLoading extends StatelessWidget {
  const _StartupLoading({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(),
            ),
            const SizedBox(height: 24),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
