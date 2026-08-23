import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'position_service.dart';
import 'drive_service.dart';
import 'preferences_service.dart';
import '../locator.dart';
import '../models/audiobook.dart';

/// Handles local JSON backup of listening positions and optional Drive sync.
///
/// Layer 1 — Local JSON (always active when a library folder is configured):
///   Writes `<audiobooksRoot>/positions.json` within 30 s of any position
///   change, and immediately on app background.
///
/// Layer 2 — Drive sync (opt-in):
///   Uploads the local JSON to `Kowhai/positions.json` in the user's
///   chosen Drive backup folder. Debounced to at most once every 5 minutes
///   while playing; fires immediately on app background.
class PositionBackupService {
  static void _log(String msg) =>
      debugPrint('[Kowhai:Backup] $msg');

  Timer? _exportTimer;
  Timer? _uploadTimer;

  static const _exportDebounce = Duration(seconds: 30);
  static const _uploadDebounce = Duration(minutes: 5);
  static const backupFileName = 'positions.json';
  static const driveFolderName = 'Kowhai';

  // Keep private aliases for internal use.
  static const _backupFileName = backupFileName;

  // ── Export (local JSON) ───────────────────────────────────────────────────

  /// Schedules a debounced export. Call after every position save.
  void scheduleExport() {
    _exportTimer?.cancel();
    _exportTimer = Timer(_exportDebounce, _runExport);
  }

  /// Fires export (and upload if enabled) immediately, bypassing debounce.
  /// Call on app background.
  Future<void> onAppBackground() async {
    _exportTimer?.cancel();
    _uploadTimer?.cancel();
    await _runExport();
    await _runUpload();
  }

  Future<void> _runExport() async {
    final root = await locator<PreferencesService>().getLibraryPath();
    if (root == null) return;
    try {
      await exportToJson(root);
    } catch (e) {
      _log('Export failed: $e');
    }
  }

  /// Exports all positions to `<audiobooksRoot>/positions.json`.
  /// book_path values are stored relative to [audiobooksRoot].
  Future<void> exportToJson(String audiobooksRoot) async {
    final positions = await locator<PositionService>().getAllPositions();
    final statuses = await locator<PositionService>().getAllStatuses();

    final entries = positions.map((pos) {
      final rel = _toRelative(pos.bookPath, audiobooksRoot);
      return {
        'book_path': rel,
        'global_position_ms': pos.globalPositionMs,
        'total_duration_ms': pos.totalDurationMs,
        'status': statuses[pos.bookPath]?.name ?? 'notStarted',
        'updated_at': pos.updatedAt,
      };
    }).toList();

    final json = jsonEncode({
      'version': 1,
      'exported_at': DateTime.now().millisecondsSinceEpoch,
      'positions': entries,
    });

    final file = File(p.join(audiobooksRoot, _backupFileName));
    await file.writeAsString(json);
    _log('Exported ${entries.length} position(s) to ${file.path}');
  }

  /// Imports positions from `<audiobooksRoot>/positions.json`.
  /// Only applies rows where the JSON updated_at is newer than the local row.
  /// Malformed JSON or missing file → no-op, no throw.
  Future<void> importFromJson(String audiobooksRoot) async {
    final file = File(p.join(audiobooksRoot, _backupFileName));
    if (!await file.exists()) return;

    Map<String, dynamic> data;
    try {
      data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      _log('Import failed (malformed JSON): $e');
      return;
    }

    final entries = data['positions'] as List?;
    if (entries == null) return;

    final svc = locator<PositionService>();
    int applied = 0;

    // Load all existing positions once for efficient last-write-wins comparison.
    final existing = await svc.getAllPositions();
    final existingByPath = {for (final p in existing) p.bookPath: p.updatedAt};

    for (final entry in entries) {
      try {
        final rel = entry['book_path'] as String;
        final absPath = _toAbsolute(rel, audiobooksRoot);
        final updatedAt = entry['updated_at'] as int;
        final globalMs = entry['global_position_ms'] as int;
        final totalMs = entry['total_duration_ms'] as int;
        final statusStr = entry['status'] as String? ?? 'notStarted';

        // Last-write-wins: skip if local row is newer or equal.
        final localUpdatedAt = existingByPath[absPath];
        if (localUpdatedAt != null && localUpdatedAt >= updatedAt) continue;

        await svc.savePosition(
          bookPath: absPath,
          chapterIndex: 0,
          position: Duration.zero,
          globalPositionMs: globalMs,
          totalDurationMs: totalMs,
        );

        final status = BookStatus.values.firstWhere(
          (s) => s.name == statusStr,
          orElse: () => BookStatus.notStarted,
        );
        await svc.updateBookStatus(absPath, status);
        applied++;
      } catch (e) {
        _log('Skipping entry: $e');
      }
    }

    _log('Imported $applied position(s) from ${file.path}');
  }

  // ── Drive upload ──────────────────────────────────────────────────────────

  /// Schedules a debounced Drive upload.
  void scheduleUpload() {
    _uploadTimer?.cancel();
    _uploadTimer = Timer(_uploadDebounce, _runUpload);
  }

  Future<void> _runUpload() async {
    final prefs = locator<PreferencesService>();
    if (!await prefs.getDriveProgressSync()) return;
    final root = await prefs.getLibraryPath();
    if (root == null) return;
    try {
      await uploadToDrive(root);
    } catch (e) {
      _log('Drive upload failed: $e');
    }
  }

  /// Uploads the local positions.json to Drive.
  /// Throws on permission error so the caller can handle it.
  Future<void> uploadToDrive(String audiobooksRoot) async {
    final prefs = locator<PreferencesService>();
    final backup = await prefs.getDriveBackupFolder();
    if (backup == null) return;

    final file = File(p.join(audiobooksRoot, _backupFileName));
    if (!await file.exists()) await exportToJson(audiobooksRoot);

    final bytes = await file.readAsBytes();
    await locator<DriveService>()
        .uploadFile(backup.id, _backupFileName, bytes);
    _log('Uploaded positions.json to Drive folder "${backup.name}"');
  }

  /// Downloads positions.json from Drive and merges into local DB.
  Future<void> restoreFromDrive(String audiobooksRoot) async {
    final prefs = locator<PreferencesService>();
    final backup = await prefs.getDriveBackupFolder();
    if (backup == null) return;

    final bytes = await locator<DriveService>()
        .downloadFileByName(backup.id, _backupFileName);
    if (bytes == null) {
      _log('No positions.json found in Drive backup folder');
      return;
    }

    final file = File(p.join(audiobooksRoot, _backupFileName));
    await file.writeAsBytes(bytes);
    await importFromJson(audiobooksRoot);
    _log('Restored positions from Drive');
  }

  void dispose() {
    _exportTimer?.cancel();
    _uploadTimer?.cancel();
  }

  // ── Path helpers ──────────────────────────────────────────────────────────

  /// Converts an absolute [path] to a path relative to [root].
  /// If [path] doesn't start with [root], returns [path] unchanged.
  static String _toRelative(String path, String root) {
    // Normalise separators to forward slash for cross-platform consistency.
    final normPath = path.replaceAll('\\', '/');
    var normRoot = root.replaceAll('\\', '/');
    if (!normRoot.endsWith('/')) normRoot = '$normRoot/';
    if (normPath.startsWith(normRoot)) {
      return normPath.substring(normRoot.length);
    }
    return normPath;
  }

  /// Converts a relative [path] back to absolute by joining with [root].
  /// If [path] is already absolute, returns it unchanged.
  static String _toAbsolute(String path, String root) {
    // Normalise to forward slash.
    final normPath = path.replaceAll('\\', '/');
    final normRoot = root.replaceAll('\\', '/');
    if (p.isAbsolute(normPath)) return normPath;
    final joined = normRoot.endsWith('/')
        ? '$normRoot$normPath'
        : '$normRoot/$normPath';
    return joined;
  }

  /// Exposed for testing.
  @visibleForTesting
  static String toRelativeForTesting(String path, String root) =>
      _toRelative(path, root);

  @visibleForTesting
  static String toAbsoluteForTesting(String path, String root) =>
      _toAbsolute(path, root);
}
