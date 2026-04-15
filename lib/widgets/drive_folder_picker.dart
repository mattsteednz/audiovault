import 'package:flutter/material.dart';

import '../services/drive_service.dart';

/// Shows a Drive folder browser dialog and returns the selected [DriveFolder],
/// or null if the user cancelled.
Future<DriveFolder?> showDriveFolderPicker(
    BuildContext context, DriveService driveService) {
  return showDialog<DriveFolder>(
    context: context,
    builder: (_) => _DriveFolderPickerDialog(driveService: driveService),
  );
}

class _DriveFolderPickerDialog extends StatefulWidget {
  final DriveService driveService;
  const _DriveFolderPickerDialog({required this.driveService});

  @override
  State<_DriveFolderPickerDialog> createState() =>
      _DriveFolderPickerDialogState();
}

class _DriveFolderPickerDialogState extends State<_DriveFolderPickerDialog> {
  // Breadcrumb stack: list of (folder, children)
  final List<_BreadcrumbEntry> _stack = [];
  List<DriveFolder> _current = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRoots();
  }

  Future<void> _loadRoots() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final roots = await widget.driveService.listRoots();
      setState(() {
        _current = roots;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _enterFolder(DriveFolder folder) async {
    setState(() => _loading = true);
    try {
      final children =
          await widget.driveService.listSubfolders(folder.id, isShared: folder.isShared);
      setState(() {
        _stack.add(_BreadcrumbEntry(folder: folder, siblings: _current));
        _current = children;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _goBack() {
    if (_stack.isEmpty) return;
    final entry = _stack.removeLast();
    setState(() => _current = entry.siblings);
  }

  String get _breadcrumb {
    if (_stack.isEmpty) return 'Select folder';
    return _stack.map((e) => e.folder.name).join(' › ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
              child: Row(
                children: [
                  if (_stack.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: _goBack,
                      tooltip: 'Back',
                    ),
                  Expanded(
                    child: Text(
                      _breadcrumb,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Body
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('Error: $_error',
                                style: TextStyle(color: theme.colorScheme.error)),
                          ),
                        )
                      : _current.isEmpty
                          ? const Center(child: Text('No subfolders found'))
                          : ListView.builder(
                              itemCount: _current.length,
                              itemBuilder: (_, i) {
                                final folder = _current[i];
                                return ListTile(
                                  leading: Icon(
                                    folder.isShared
                                        ? Icons.folder_shared
                                        : Icons.folder,
                                    color: theme.colorScheme.primary,
                                  ),
                                  title: Text(folder.name),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _enterFolder(folder),
                                );
                              },
                            ),
            ),
            const Divider(height: 1),
            // Footer — select current level's folder (if inside one)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _stack.isEmpty
                        ? 'Drill into a folder to select it'
                        : 'Select: ${_stack.last.folder.name}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (_stack.isNotEmpty)
                    FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, _stack.last.folder),
                      child: const Text('Select'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BreadcrumbEntry {
  final DriveFolder folder;
  final List<DriveFolder> siblings; // the list we were showing before entering this folder
  _BreadcrumbEntry({required this.folder, required this.siblings});
}
