import 'package:audio_service/audio_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/consent_screen.dart';
import 'screens/library_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/audio_handler.dart';
import 'services/preferences_service.dart';
import 'services/telemetry_service.dart';

late AudioVaultHandler audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise audio service.
  audioHandler = await AudioService.init<AudioVaultHandler>(
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

  // Initialise Firebase — silently ignored if config files are placeholders.
  try {
    await Firebase.initializeApp();
    TelemetryService.markAvailable();
  } catch (_) {
    // Firebase not yet configured — app continues without telemetry.
  }

  runApp(const AudioVaultApp());
}

class AudioVaultApp extends StatelessWidget {
  const AudioVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AudioVault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B4C9A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _AppEntryPoint(),
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
    final prefs = PreferencesService();
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
    await PreferencesService().setAnalyticsConsent(accepted);
    await TelemetryService.applyConsent(accepted);
    if (accepted) TelemetryService.enableCrashHandler();

    final path = await PreferencesService().getLibraryPath();
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
