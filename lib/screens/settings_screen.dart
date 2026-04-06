import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/enrichment_service.dart';
import '../widgets/audio_handler_scope.dart';
import '../services/preferences_service.dart';
import '../services/telemetry_service.dart';

/// Returns [true] if the audiobooks folder was changed (triggers a rescan).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _folderPath;
  bool _telemetryEnabled = false;
  bool _metadataEnrichment = true;
  bool _folderChanged = false;
  bool _pickingFolder = false;
  String _themeMode = 'system';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = PreferencesService();
    final path = await prefs.getLibraryPath();
    final consent = await prefs.getAnalyticsConsent();
    final themeMode = await prefs.getThemeMode();
    final enrichment = await prefs.getMetadataEnrichment();
    setState(() {
      _folderPath = path;
      _telemetryEnabled = consent ?? false;
      _themeMode = themeMode ?? 'system';
      _metadataEnrichment = enrichment;
    });
  }

  Future<void> _selectFolder() async {
    setState(() => _pickingFolder = true);
    try {
      if (Platform.isAndroid) {
        final status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          final result = await Permission.manageExternalStorage.request();
          if (!result.isGranted) {
            if (result.isPermanentlyDenied) await openAppSettings();
            return;
          }
        }
      }
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select your audiobooks folder',
      );
      if (result != null && result != _folderPath) {
        await PreferencesService().setLibraryPath(result);
        setState(() {
          _folderPath = result;
          _folderChanged = true;
        });
      }
    } finally {
      setState(() => _pickingFolder = false);
    }
  }

  Future<void> _setThemeMode(String value) async {
    await PreferencesService().setThemeMode(value);
    ThemeMode themeMode;
    switch (value) {
      case 'light':
        themeMode = ThemeMode.light;
        break;
      case 'dark':
        themeMode = ThemeMode.dark;
        break;
      default:
        themeMode = ThemeMode.system;
    }
    AudioHandlerScope.of(context).themeModeNotifier.value = themeMode;
    setState(() => _themeMode = value);
  }

  Future<void> _setMetadataEnrichment(bool value) async {
    await PreferencesService().setMetadataEnrichment(value);
    if (!value) EnrichmentService().cancel();
    setState(() => _metadataEnrichment = value);
  }

  Future<void> _setTelemetry(bool value) async {
    await PreferencesService().setAnalyticsConsent(value);
    await TelemetryService.applyConsent(value);
    if (value) TelemetryService.enableCrashHandler();
    setState(() => _telemetryEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: BackButton(
          onPressed: () => Navigator.pop(context, _folderChanged),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
            // ── Appearance section ───────────────────────────────────────
            _sectionHeader('Appearance', theme),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'system',
                    label: Text('Follow system'),
                    icon: Icon(Icons.brightness_auto_rounded),
                  ),
                  ButtonSegment(
                    value: 'light',
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_rounded),
                  ),
                  ButtonSegment(
                    value: 'dark',
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_rounded),
                  ),
                ],
                selected: {_themeMode},
                onSelectionChanged: (selection) =>
                    _setThemeMode(selection.first),
              ),
            ),
            const Divider(height: 24),

            // ── Audiobooks section ───────────────────────────────────────
            _sectionHeader('Audiobooks', theme),
            SwitchListTile(
              value: _metadataEnrichment,
              onChanged: _setMetadataEnrichment,
              title: const Text('Get missing covers & metadata'),
              subtitle: const Text(
                  'Fetches covers from Open Library for books without artwork'),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            ),
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: Text(
                _folderPath ?? 'No folder selected',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface
                      .withValues(alpha: _folderPath != null ? 0.6 : 0.4),
                  fontFamily: 'monospace',
                ),
              ),
              trailing: _pickingFolder
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : IconButton(
                      icon: const Icon(Icons.folder_open_rounded),
                      tooltip: 'Select audiobooks folder',
                      onPressed: _selectFolder,
                    ),
              onTap: _pickingFolder ? null : _selectFolder,
            ),
            const Divider(height: 24),

            // ── Privacy section ──────────────────────────────────────────
            _sectionHeader('Privacy', theme),
            SwitchListTile(
              value: _telemetryEnabled,
              onChanged: _setTelemetry,
              title: const Text(
                  'Send crash reports and usage data to help improve AudioVault'),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                'Data sent to Google Firebase is anonymous and includes no '
                'personal information such as book titles or file names.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ),
          ],
        ),
      );
  }

  Widget _sectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
