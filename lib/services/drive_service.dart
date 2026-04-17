import 'package:flutter/foundation.dart';
import 'package:google_api_availability/google_api_availability.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

/// A simple audio/image file extension check.
const _audioExtensions = {'.mp3', '.m4a', '.aac', '.m4b', '.flac', '.ogg'};
const _imageExtensions = {'.jpg', '.jpeg', '.png', '.webp'};

/// A Drive folder descriptor.
class DriveFolder {
  final String id;
  final String name;
  final bool isShared;

  const DriveFolder({required this.id, required this.name, required this.isShared});
}

/// A file inside a Drive folder.
class DriveFileInfo {
  final String id;
  final String name;
  final String mimeType;
  final int sizeBytes;

  const DriveFileInfo({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
  });

  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot == -1) return '';
    return name.substring(dot).toLowerCase();
  }

  bool get isAudio => _audioExtensions.contains(extension);
  bool get isImage => _imageExtensions.contains(extension);
}

/// Result of scanning a single Drive folder as an audiobook.
class DriveFolderScan {
  final DriveFolder folder;
  final List<DriveFileInfo> audioFiles; // naturally sorted
  final DriveFileInfo? coverFile;

  const DriveFolderScan({
    required this.folder,
    required this.audioFiles,
    this.coverFile,
  });
}

/// HTTP client that injects a Bearer token into every request.
class _BearerClient extends http.BaseClient {
  final String token;
  final http.Client _inner;

  _BearerClient(this.token) : _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $token';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

class DriveService {
  static const _scope = drive.DriveApi.driveReadonlyScope;

  final GoogleSignIn _signIn = GoogleSignIn(scopes: [_scope]);

  GoogleSignInAccount? _account;
  GoogleSignInAccount? get currentAccount => _account;
  Stream<GoogleSignInAccount?> get accountStream => _signIn.onCurrentUserChanged;

  /// Silently restores a previously signed-in account. Call once on app startup.
  Future<void> restoreSession() async {
    try {
      _account = await _signIn.signInSilently();
      if (_account != null) debugPrint('[Drive] Session restored');
    } catch (_) {
      // No previous session or token expired — user will sign in manually.
    }
  }

  /// Returns true if Google Play Services are available on this device.
  Future<bool> isAvailable() async {
    final availability = await GoogleApiAvailability.instance
        .checkGooglePlayServicesAvailability();
    return availability == GooglePlayServicesAvailability.success;
  }

  /// Signs in interactively. Returns the account, or null if cancelled/failed.
  Future<GoogleSignInAccount?> signIn() async {
    try {
      _account = await _signIn.signIn();
      if (_account == null) {
        debugPrint('[Drive] signIn() returned null (user cancelled or no account selected)');
      } else {
        debugPrint('[Drive] signIn() succeeded');
      }
      return _account;
    } catch (e, st) {
      debugPrint('[Drive] signIn() threw: $e\n$st');
      rethrow;
    }
  }

  /// Signs out and clears the stored account.
  Future<void> signOut() async {
    await _signIn.signOut();
    _account = null;
  }

  /// Returns a fresh access token for the current account, or null if not signed in.
  Future<String?> getAccessToken() async {
    final account = _account ?? await _signIn.signInSilently();
    if (account == null) return null;
    _account = account;
    final auth = await account.authentication;
    return auth.accessToken;
  }

  Future<drive.DriveApi?> _driveApi() async {
    final token = await getAccessToken();
    if (token == null) return null;
    return drive.DriveApi(_BearerClient(token));
  }

  /// Lists the "My Drive" root folder and top-level "Shared with me" folders.
  Future<List<DriveFolder>> listRoots() async {
    final api = await _driveApi();
    if (api == null) return [];

    final results = <DriveFolder>[
      const DriveFolder(id: 'root', name: 'My Drive', isShared: false),
    ];

    // Shared with me: top-level folders shared directly
    String? pageToken;
    do {
      final resp = await api.files.list(
        q: "sharedWithMe = true and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
        spaces: 'drive',
        $fields: 'nextPageToken, files(id, name)',
        pageToken: pageToken,
      );
      for (final f in resp.files ?? []) {
        if (f.id != null && f.name != null) {
          results.add(DriveFolder(id: f.id!, name: f.name!, isShared: true));
        }
      }
      pageToken = resp.nextPageToken;
    } while (pageToken != null);

    return results;
  }

  /// Lists immediate subfolders of [parentId].
  Future<List<DriveFolder>> listSubfolders(String parentId, {bool isShared = false}) async {
    final api = await _driveApi();
    if (api == null) return [];

    final folders = <DriveFolder>[];
    String? pageToken;
    do {
      final resp = await api.files.list(
        q: "'$parentId' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
        spaces: 'drive',
        $fields: 'nextPageToken, files(id, name)',
        pageToken: pageToken,
      );
      for (final f in resp.files ?? []) {
        if (f.id != null && f.name != null) {
          folders.add(DriveFolder(id: f.id!, name: f.name!, isShared: isShared));
        }
      }
      pageToken = resp.nextPageToken;
    } while (pageToken != null);

    folders.sort((a, b) => _naturalCompare(a.name, b.name));
    return folders;
  }

  /// Lists all files (audio + images) in a single folder.
  Future<List<DriveFileInfo>> listFolderContents(String folderId) async {
    final api = await _driveApi();
    if (api == null) return [];

    final files = <DriveFileInfo>[];
    String? pageToken;
    do {
      final resp = await api.files.list(
        q: "'$folderId' in parents and mimeType != 'application/vnd.google-apps.folder' and trashed = false",
        spaces: 'drive',
        $fields: 'nextPageToken, files(id, name, mimeType, size)',
        pageToken: pageToken,
      );
      for (final f in resp.files ?? []) {
        if (f.id == null || f.name == null) continue;
        final size = int.tryParse(f.size ?? '0') ?? 0;
        files.add(DriveFileInfo(
          id: f.id!,
          name: f.name!,
          mimeType: f.mimeType ?? '',
          sizeBytes: size,
        ));
      }
      pageToken = resp.nextPageToken;
    } while (pageToken != null);

    // Filter to audio/image, natural sort audio files
    final audio = files.where((f) => f.isAudio).toList()
      ..sort((a, b) => _naturalCompare(a.name, b.name));
    final images = files.where((f) => f.isImage).toList();

    return [...audio, ...images];
  }

  /// Scans the immediate subfolders of [rootFolderId], treating each as one book.
  Future<List<DriveFolderScan>> scanRootFolder(String rootFolderId, bool isShared) async {
    final subfolders = await listSubfolders(rootFolderId, isShared: isShared);
    final scans = <DriveFolderScan>[];

    for (final folder in subfolders) {
      final contents = await listFolderContents(folder.id);
      final audio = contents.where((f) => f.isAudio).toList();
      if (audio.isEmpty) continue; // skip folders without audio

      final images = contents.where((f) => f.isImage).toList();
      final cover = _pickCover(images);

      scans.add(DriveFolderScan(folder: folder, audioFiles: audio, coverFile: cover));
    }

    return scans;
  }

  DriveFileInfo? _pickCover(List<DriveFileInfo> images) => pickCover(images);
}

/// Chooses the most likely cover image from a list of image files.
///
/// Priority: exact `cover.jpg`/`.jpeg`/`.png`, then any filename containing
/// `cover`, then the first image. Returns null if [images] is empty.
DriveFileInfo? pickCover(List<DriveFileInfo> images) {
  if (images.isEmpty) return null;
  for (final img in images) {
    final lower = img.name.toLowerCase();
    if (lower == 'cover.jpg' || lower == 'cover.jpeg' || lower == 'cover.png') {
      return img;
    }
  }
  for (final img in images) {
    if (img.name.toLowerCase().contains('cover')) return img;
  }
  return images.first;
}

/// Natural sort comparator — numbers within strings sort numerically.
@visibleForTesting
int naturalCompare(String a, String b) => _naturalCompare(a, b);

int _naturalCompare(String a, String b) {
  final aLow = a.toLowerCase();
  final bLow = b.toLowerCase();
  final aSegments = _splitNatural(aLow);
  final bSegments = _splitNatural(bLow);
  final len = aSegments.length < bSegments.length ? aSegments.length : bSegments.length;
  for (int i = 0; i < len; i++) {
    final aS = aSegments[i];
    final bS = bSegments[i];
    final aNum = int.tryParse(aS);
    final bNum = int.tryParse(bS);
    int cmp;
    if (aNum != null && bNum != null) {
      cmp = aNum.compareTo(bNum);
    } else {
      cmp = aS.compareTo(bS);
    }
    if (cmp != 0) return cmp;
  }
  return aSegments.length.compareTo(bSegments.length);
}

List<String> _splitNatural(String s) {
  final segments = <String>[];
  final re = RegExp(r'(\d+|\D+)');
  for (final m in re.allMatches(s)) {
    segments.add(m.group(0)!);
  }
  return segments;
}
