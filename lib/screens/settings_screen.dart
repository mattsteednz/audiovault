import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/enrichment_service.dart';
import '../widgets/audio_handler_scope.dart';
import '../services/preferences_service.dart';
import '../services/telemetry_service.dart';
import '../locator.dart';

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
  bool _autoRewind = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = locator<PreferencesService>();
    final path = await prefs.getLibraryPath();
    final consent = await prefs.getAnalyticsConsent();
    final themeMode = await prefs.getThemeMode();
    final enrichment = await prefs.getMetadataEnrichment();
    final autoRewind = await prefs.getAutoRewind();
    setState(() {
      _folderPath = path;
      _telemetryEnabled = consent ?? false;
      _themeMode = themeMode ?? 'system';
      _metadataEnrichment = enrichment;
      _autoRewind = autoRewind;
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
        await locator<PreferencesService>().setLibraryPath(result);
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
    await locator<PreferencesService>().setThemeMode(value);
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
    await locator<PreferencesService>().setMetadataEnrichment(value);
    if (!value) locator<EnrichmentService>().cancel();
    setState(() => _metadataEnrichment = value);
  }

  Future<void> _setAutoRewind(bool value) async {
    await locator<PreferencesService>().setAutoRewind(value);
    setState(() => _autoRewind = value);
  }

  Future<void> _setTelemetry(bool value) async {
    await locator<PreferencesService>().setAnalyticsConsent(value);
    await TelemetryService.applyConsent(value);
    if (value) TelemetryService.enableCrashHandler();
    setState(() => _telemetryEnabled = value);
  }

  void _showColorModeDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => _ColorModeDialog(
        current: _themeMode,
        onSelected: (value) {
          Navigator.pop(context);
          _setThemeMode(value);
        },
      ),
    );
  }

  String get _themeModeLabel {
    switch (_themeMode) {
      case 'light':
        return 'Light';
      case 'dark':
        return 'Dark';
      default:
        return 'Follow system';
    }
  }

  IconData get _themeModeIcon {
    switch (_themeMode) {
      case 'light':
        return Icons.wb_sunny_rounded;
      case 'dark':
        return Icons.dark_mode_rounded;
      default:
        return Icons.phone_android_rounded;
    }
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
        children: [
          // ── Appearance ───────────────────────────────────────────────────
          ListTile(
            leading: Icon(_themeModeIcon),
            title: const Text('Color mode'),
            subtitle: Text(_themeModeLabel),
            onTap: _showColorModeDialog,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          ),
          const Divider(),

          // ── Audiobooks ───────────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.folder_rounded),
            title: const Text('Audiobooks folder'),
            subtitle: Text(
              _folderPath ?? 'No folder selected',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _pickingFolder
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _pickingFolder ? null : _selectFolder,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_rounded),
            title: const Text('Get missing covers & metadata'),
            subtitle: const Text(
                'Fetches covers from Open Library for books without artwork'),
            trailing: Switch(
              value: _metadataEnrichment,
              onChanged: _setMetadataEnrichment,
            ),
            onTap: () => _setMetadataEnrichment(!_metadataEnrichment),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          ),
          ListTile(
            leading: const Icon(Icons.fast_rewind_rounded),
            title: const Text('Smart rewind on resume'),
            subtitle: const Text(
                'Jumps back a few seconds if you haven\'t listened in a while'),
            trailing: Switch(
              value: _autoRewind,
              onChanged: _setAutoRewind,
            ),
            onTap: () => _setAutoRewind(!_autoRewind),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          ),
          const Divider(),

          // ── Privacy ──────────────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.shield_rounded),
            title: const Text('Analytics & crash reports'),
            subtitle: const Text(
                'Send anonymous usage data to help improve AudioVault'),
            trailing: Switch(
              value: _telemetryEnabled,
              onChanged: _setTelemetry,
            ),
            onTap: () => _setTelemetry(!_telemetryEnabled),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(
              'Data sent to Google Firebase is anonymous and includes no '
              'personal information such as book titles or file names.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorModeDialog extends StatelessWidget {
  final String current;
  final void Function(String) onSelected;

  const _ColorModeDialog({required this.current, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = [
      (value: 'system', label: 'Follow system', icon: Icons.phone_android_rounded),
      (value: 'light', label: 'Light', icon: Icons.wb_sunny_rounded),
      (value: 'dark', label: 'Dark', icon: Icons.dark_mode_rounded),
    ];

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Color mode', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            ...options.map((opt) {
              final selected = opt.value == current;
              return InkWell(
                onTap: () => onSelected(opt.value),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 14, horizontal: 8),
                  child: Row(
                    children: [
                      Icon(
                        opt.icon,
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        opt.label,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                          fontWeight: selected ? FontWeight.w600 : null,
                        ),
                      ),
                      const Spacer(),
                      if (selected)
                        Icon(Icons.check_rounded,
                            color: theme.colorScheme.primary),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
