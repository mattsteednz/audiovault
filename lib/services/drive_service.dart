import 'package:flutter/foundation.dart';
import 'package:google_api_availability/google_api_availability.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import '../utils/cover_picker.dart';
import '../utils/natural_sort.dart';

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
    return _inner.send(request).timeout(const Duration(seconds: 30));
  }

  @override
  void close() => _inner.close();
}

class DriveService {
  static const _readScope = drive.DriveApi.driveReadonlyScope;
  static const _writeScope = drive.DriveApi.driveFileScope;

  // google_sign_in 7.x: singleton, requires initialize() exactly once, and
  // separates AUTHENTICATION (who you are) from AUTHORIZATION (scopes).
  GoogleSignIn get _signIn => GoogleSignIn.instance;
  bool _initialized = false;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await _signIn.initialize();
    _initialized = true;
  }

  GoogleSignInAccount? _account;
  GoogleSignInAccount? get currentAccount => _account;

  /// Silently restores a previously signed-in account. Call once on app startup.
  ///
  /// v7 note: [attemptLightweightAuthentication] is no longer guaranteed
  /// silent nor to return a Future (web). On mobile it returns
  /// `Future<GoogleSignInAccount?>`; on platforms without a definitive answer
  /// we simply start unauthenticated and rely on the interactive path.
  Future<void> restoreSession() async {
    try {
      await _ensureInit();
      final result = _signIn.attemptLightweightAuthentication();
      if (result is Future<GoogleSignInAccount?>) {
        _account = await result;
      }
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
  ///
  /// [authenticate]'s scopeHint lets supporting platforms combine the
  /// authentication + read-scope authorization into one flow; platforms that
  /// cannot combine fall back to the separate authorization request made by
  /// [getAccessToken].
  Future<GoogleSignInAccount?> signIn() async {
    try {
      await _ensureInit();
      _account = await _signIn.authenticate(scopeHint: [_readScope]);
      if (_account == null) {
        debugPrint(
            '[Drive] authenticate() returned null (user cancelled or no account selected)');
      } else {
        debugPrint('[Drive] authenticate() succeeded');
      }
      return _account;
    } catch (e, st) {
      debugPrint('[Drive] authenticate() threw: $e\n$st');
      rethrow;
    }
  }

  /// Signs out and clears the stored account.
  Future<void> signOut() async {
    await _ensureInit();
    await _signIn.signOut();
    _account = null;
  }

  /// Returns a fresh access token for the current account, or null if not
  /// signed in / not authorized for the read scope.
  Future<String?> getAccessToken() async {
    await _ensureInit();
    var account = _account;
    if (account == null) {
      final result = _signIn.attemptLightweightAuthentication();
      if (result is Future<GoogleSignInAccount?>) {
        account = await result;
      }
      if (account == null) return null;
      _account = account;
    }
    final authorization = await account.authorizationClient
        .authorizationForScopes([_readScope]);
    return authorization?.accessToken;
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

    folders.sort((a, b) => naturalCompare(a.name, b.name));
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
      ..sort((a, b) => naturalCompare(a.name, b.name));
    final images = files.where((f) => f.isImage).toList();

    return [...audio, ...images];
  }

  /// Scans [rootFolderId] for audiobook folders, mirroring the local
  /// scanner's nesting support (R22): a folder containing audio files is a
  /// book; a folder without audio but with subfolders is treated as an
  /// author/series grouping and descended into, up to [maxScanDepth] levels
  /// below the root (matching ScannerService.maxScanDepth semantics).
  ///
  /// NOTE (architect risk flag): this walks the Drive tree sequentially with
  /// one list call per folder — fine for personal libraries, but very deep
  /// wide trees cost N+1 API round-trips. Depth cap bounds the worst case.
  Future<List<DriveFolderScan>> scanRootFolder(String rootFolderId, bool isShared) async {
    return _scanFolderLevel(rootFolderId, isShared, maxScanDepth);
  }

  /// Maximum folder depth below the Drive root that scanning descends into.
  /// Mirrors [ScannerService.maxScanDepth] so local and Drive libraries
  /// support the same layouts: flat / author/book / author/series/book.
  static const int maxScanDepth = 3;

  Future<List<DriveFolderScan>> _scanFolderLevel(
      String parentId, bool parentIsShared, int remainingDepth) async {
    final subfolders = await listSubfolders(parentId, isShared: parentIsShared);
    final scans = <DriveFolderScan>[];

    for (final folder in subfolders) {
      final contents = await listFolderContents(folder.id);
      final audio = contents.where((f) => f.isAudio).toList();

      if (audio.isNotEmpty) {
        final images = contents.where((f) => f.isImage).toList();
        final cover = _pickCover(images);
        scans.add(DriveFolderScan(
            folder: folder, audioFiles: audio, coverFile: cover));
        continue;
      }

      // No audio here — treat as grouping folder and descend.
      if (remainingDepth > 0) {
        scans.addAll(await _scanFolderLevel(
            folder.id, folder.isShared, remainingDepth - 1));
      }
    }

    return scans;
  }

  DriveFileInfo? _pickCover(List<DriveFileInfo> images) {
    return pickBestCover(images, (img) => img.name);
  }

  // ── Write operations (requires driveFileScope) ─────────────────────────────────────

  /// Requests the write scope interactively. Returns true if granted.
  /// Call this only when the user explicitly enables Drive sync.
  Future<bool> requestWriteScope() async {
    final account = _account;
    if (account == null) return false;
    try {
      // authorizeScopes is non-nullable: it resolves with the authorization
      // or throws (cancelled / denied).
      await account.authorizationClient.authorizeScopes([_writeScope]);
      return true;
    } catch (e) {
      debugPrint('[Drive] requestWriteScope failed: $e');
      return false;
    }
  }

  /// Returns true if the write scope has already been granted, without
  /// prompting. v7 note: canAccessScopes is web-only; authorizationForScopes
  /// returning a token is the cross-platform equivalent of "already granted".
  Future<bool> hasWriteScope() async {
    final account = _account;
    if (account == null) return false;
    try {
      final authorization = await account.authorizationClient
          .authorizationForScopes([_writeScope]);
      return authorization != null;
    } catch (_) {
      return false;
    }
  }

  /// Finds or creates a folder named [name] inside [parentId].
  /// Returns the folder ID.
  Future<String> findOrCreateFolder(String parentId, String name) async {
    final api = await _driveApi();
    if (api == null) throw Exception('Not signed in');

    // Check if it already exists.
    final resp = await api.files.list(
      q: "'${escapeQ(parentId)}' in parents and name = '${escapeQ(name)}' and "
          "mimeType = 'application/vnd.google-apps.folder' and trashed = false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    final existing = resp.files?.firstOrNull;
    if (existing?.id != null) return existing!.id!;

    // Create it.
    final created = await api.files.create(
      drive.File()
        ..name = name
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [parentId],
      $fields: 'id',
    );
    if (created.id == null) throw Exception('Failed to create folder');
    return created.id!;
  }

  /// Uploads [bytes] as [fileName] inside [parentFolderId], replacing any
  /// existing file with the same name.
  Future<void> uploadFile(
      String parentFolderId, String fileName, List<int> bytes) async {
    final api = await _driveApi();
    if (api == null) throw Exception('Not signed in');

    // Check for existing file to update.
    final resp = await api.files.list(
      q: "'${escapeQ(parentFolderId)}' in parents and name = '${escapeQ(fileName)}' and trashed = false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    final existingId = resp.files?.firstOrNull?.id;

    final media = drive.Media(
      Stream.value(bytes),
      bytes.length,
      contentType: 'application/json',
    );

    if (existingId != null) {
      await api.files.update(drive.File(), existingId, uploadMedia: media);
    } else {
      await api.files.create(
        drive.File()
          ..name = fileName
          ..parents = [parentFolderId],
        uploadMedia: media,
      );
    }
  }

  /// Downloads the first file named [fileName] inside [parentFolderId].
  /// Returns null if not found or on error.
  Future<List<int>?> downloadFileByName(
      String parentFolderId, String fileName) async {
    final api = await _driveApi();
    if (api == null) return null;

    final resp = await api.files.list(
      q: "'${escapeQ(parentFolderId)}' in parents and name = '${escapeQ(fileName)}' and trashed = false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    final fileId = resp.files?.firstOrNull?.id;
    if (fileId == null) return null;

    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    return bytes;
  }
}

/// Escapes a string for use inside single-quoted Drive API query literals.
///
/// Drive's `q` parameter uses single quotes for string values; a literal `'`
/// or `\` inside a name would break the query or match unintended files.
@visibleForTesting
String escapeQ(String s) => s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
