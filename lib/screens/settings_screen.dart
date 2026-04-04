import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
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
  bool _folderChanged = false;
  bool _pickingFolder = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = PreferencesService();
    final path = await prefs.getLibraryPath();
    final consent = await prefs.getAnalyticsConsent();
    setState(() {
      _folderPath = path;
      _telemetryEnabled = consent ?? false;
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

  Future<void> _setTelemetry(bool value) async {
    await PreferencesService().setAnalyticsConsent(value);
    await TelemetryService.applyConsent(value);
    if (value) TelemetryService.enableCrashHandler();
    setState(() => _telemetryEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      onPopInvokedWithResult: (_, __) {},
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          leading: BackButton(
            onPressed: () => Navigator.pop(context, _folderChanged),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // ── Audiobooks section ───────────────────────────────────────
            _sectionHeader('Audiobooks', theme),
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
