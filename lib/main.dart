import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'screens/consent_screen.dart';
import 'screens/library_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/audio_handler.dart';
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

  // Initialise audio service.
  final audioHandler = await AudioService.init<AudioVaultHandler>(
    builder: AudioVaultHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.mattsteed.audiovault.audio',
      androidNotificationChannelName: 'AudioVault',
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
  } catch (_) {
    // Cast not available on this platform or emulator — app continues.
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

  runApp(AudioVaultApp(
    audioHandler: audioHandler,
    themeModeNotifier: themeModeNotifier,
  ));
}

class AudioVaultApp extends StatefulWidget {
  final AudioVaultHandler audioHandler;
  final ValueNotifier<ThemeMode> themeModeNotifier;

  const AudioVaultApp({
    super.key,
    required this.audioHandler,
    required this.themeModeNotifier,
  });

  @override
  State<AudioVaultApp> createState() => _AudioVaultAppState();
}

class _AudioVaultAppState extends State<AudioVaultApp> {
  static final _lightTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF6B4C9A),
      brightness: Brightness.light,
    ),
    useMaterial3: true,
  );

  static final _darkTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF6B4C9A),
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  );

  @override
  Widget build(BuildContext context) {
    return AudioHandlerScope(
      audioHandler: widget.audioHandler,
      themeModeNotifier: widget.themeModeNotifier,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: widget.themeModeNotifier,
        builder: (context, themeMode, _) {
          return MaterialApp(
            title: 'AudioVault',
            debugShowCheckedModeBanner: false,
            theme: _lightTheme,
            darkTheme: _darkTheme,
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
      setState(() => _consentDecided = false);
      return;
    }

    // Consent already recorded — apply it and proceed.
    await TelemetryService.applyConsent(consent);
    if (consent) TelemetryService.enableCrashHandler();

    final path = await prefs.getLibraryPath();
    setState(() {
      _consentDecided = true;
      _hasLibrary = path != null && path.isNotEmpty;
    });
  }

  Future<void> _handleConsent(bool accepted) async {
    await locator<PreferencesService>().setAnalyticsConsent(accepted);
    await TelemetryService.applyConsent(accepted);
    if (accepted) TelemetryService.enableCrashHandler();

    final path = await locator<PreferencesService>().getLibraryPath();
    setState(() {
      _consentDecided = true;
      _hasLibrary = path != null && path.isNotEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Loading.
    if (_consentDecided == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    // First launch — show consent prompt.
    if (_consentDecided == false) {
      return ConsentScreen(onChoice: _handleConsent);
    }

    // Normal app flow.
    if (_hasLibrary == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    return _hasLibrary! ? const LibraryScreen() : const OnboardingScreen();
  }
}
