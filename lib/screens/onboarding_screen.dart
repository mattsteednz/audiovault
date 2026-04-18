import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/drive_library_service.dart';
import '../services/drive_service.dart';
import '../services/preferences_service.dart';
import '../widgets/drive_folder_picker.dart';
import 'library_screen.dart';
import '../locator.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _loadingLocal = false;
  bool _loadingDrive = false;
  bool _metadataEnrichment = true;
  bool _driveAvailable = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkDriveAvailability();
  }

  Future<void> _checkDriveAvailability() async {
    final available = await locator<DriveService>().isAvailable();
    if (mounted) setState(() => _driveAvailable = available);
  }

  Future<bool> _ensureStoragePermission() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;
    final status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) await openAppSettings();
    return false;
  }

  Future<void> _selectFolder() async {
    setState(() {
      _loadingLocal = true;
      _error = null;
    });
    try {
      final hasPermission = await _ensureStoragePermission();
      if (!hasPermission) {
        setState(() {
          _error = 'Storage permission is required to read your audiobooks folder.';
          _loadingLocal = false;
        });
        return;
      }
      final result = await FilePicker.getDirectoryPath(
        dialogTitle: 'Select your audiobooks folder',
      );
      if (result == null) {
        setState(() => _loadingLocal = false);
        return;
      }
      final prefs = locator<PreferencesService>();
      await prefs.setLibraryPath(result);
      await prefs.setMetadataEnrichment(_metadataEnrichment);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LibraryScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Could not access folder: $e';
        _loadingLocal = false;
      });
    }
  }

  Future<void> _connectDrive() async {
    setState(() {
      _loadingDrive = true;
      _error = null;
    });
    try {
      final driveService = locator<DriveService>();
      final account = await driveService.signIn();
      if (account == null) {
        setState(() => _loadingDrive = false);
        return;
      }

      if (!mounted) return;
      final folder = await showDriveFolderPicker(context, driveService);
      if (folder == null) {
        setState(() => _loadingDrive = false);
        return;
      }

      final prefs = locator<PreferencesService>();
      await prefs.setDriveRootFolder(folder.id, folder.name, isShared: folder.isShared);
      await prefs.setMetadataEnrichment(_metadataEnrichment);

      // Kick off initial Drive scan in the background — library screen will load results
      unawaited(locator<DriveLibraryService>().rescanDrive());

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LibraryScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Could not connect to Google Drive: $e';
        _loadingDrive = false;
      });
    }
  }

  bool get _busy => _loadingLocal || _loadingDrive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),

              // Icon + heading
              Icon(
                Icons.menu_book_rounded,
                size: 80,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                "Let's get started",
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Where are your audiobooks?',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),

              // Error
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],

              // Local folder button
              _SourceButton(
                icon: Icons.folder_rounded,
                label: 'Choose local folder',
                subtitle: 'Audio files stored on this device',
                loading: _loadingLocal,
                enabled: !_busy,
                onTap: _selectFolder,
              ),

              if (_driveAvailable) ...[
                const SizedBox(height: 12),
                _SourceButton(
                  icon: Icons.cloud_rounded,
                  label: 'Connect to Google Drive',
                  subtitle: 'Stream and download from your Drive',
                  loading: _loadingDrive,
                  enabled: !_busy,
                  onTap: _connectDrive,
                ),
              ],

              const SizedBox(height: 28),

              // Metadata enrichment checkbox
              InkWell(
                onTap: _busy ? null : () => setState(() => _metadataEnrichment = !_metadataEnrichment),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _metadataEnrichment,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _metadataEnrichment = v ?? true),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Download missing metadata from Open Library',
                              style: theme.textTheme.bodyMedium,
                            ),
                            Text(
                              'Fetches covers and author info for books without artwork',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  const _SourceButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveEnabled = enabled && !loading;

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: effectiveEnabled ? 1.0 : 0.5),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: effectiveEnabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: loading
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : Icon(icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }
}
