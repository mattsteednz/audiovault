import 'package:path/path.dart' as p;

/// Windows reserved device names that cannot be used as a filename.
const _reserved = {
  'CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5',
  'COM6', 'COM7', 'COM8', 'COM9', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5',
  'LPT6', 'LPT7', 'LPT8', 'LPT9',
};

/// Sanitises an externally-supplied name (e.g. a Google Drive folder or file
/// name) for safe use as a single filesystem path segment.
///
/// Drive names are user-controlled and may contain `/`, `\`, or `..`, all of
/// which would otherwise escape the intended parent directory when joined.
/// The original name should still be used for display and Drive API matching;
/// sanitisation applies only at the point a path is constructed.
///
/// Rules applied:
/// - path separators (`/`, `\`) → `_`
/// - control characters stripped; whitespace runs collapsed to one space
/// - trailing dots/spaces removed (Windows); dot-only names → `_`
/// - Windows reserved device names prefixed with `_`
/// - length capped at [maxLength], preserving the extension where possible
String safeFsName(String name, {int maxLength = 100}) {
  var s = name.replaceAll('/', '_').replaceAll('\\', '_');
  s = s.replaceAll(RegExp(r'[\x00-\x1f]'), '');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  while (s.endsWith('.') || s.endsWith(' ')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.isEmpty) return '_';
  final stem = p.basenameWithoutExtension(s);
  if (_reserved.contains(stem.toUpperCase())) s = '_$s';
  if (s.length > maxLength) {
    final ext = p.extension(s);
    s = s.substring(0, maxLength - ext.length) + ext;
  }
  return s.isEmpty ? '_' : s;
}
