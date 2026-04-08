import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/preferences_service.dart';
import 'library_screen.dart';
import '../locator.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _loading = false;
  String? _error;

  /// On Android 11+ we need MANAGE_EXTERNAL_STORAGE to list folder contents.
  /// Returns true if permission is already granted or not required.
  Future<bool> _ensureStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // Android 11+ (API 30+) uses MANAGE_EXTERNAL_STORAGE for broad access.
    if (await Permission.manageExternalStorage.isGranted) return true;

    final status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;

    // Permission denied — send user to settings if permanently denied.
    if (status.isPermanentlyDenied) await openAppSettings();
    return false;
  }

  Future<void> _selectFolder() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final hasPermission = await _ensureStoragePermission();
      if (!hasPermission) {
        setState(() {
          _error = 'Storage permission is required to read your audiobooks folder.';
          _loading = false;
        });
        return;
      }

      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select your audiobooks folder',
      );
      if (result == null) {
        setState(() => _loading = false);
        return;
      }
      await locator<PreferencesService>().setLibraryPath(result);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LibraryScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Could not access folder: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.menu_book_rounded,
                size: 96,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 28),
              Text(
                'Welcome to AudioVault',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Select the folder on your device where your audiobooks are stored.\n\n'
                'AudioVault looks for subfolders containing audio files.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],
              FilledButton.icon(
                onPressed: _loading ? null : _selectFolder,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.folder_open_rounded),
                label: Text(_loading ? 'Opening…' : 'Select Audiobooks Folder'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
