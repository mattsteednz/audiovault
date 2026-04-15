import 'dart:typed_data';

/// A single chapter within an audiobook.
///
/// For multi-file books (MP3) [start] is always [Duration.zero] and [index]
/// is the position in [Audiobook.audioFiles].
/// For single-file books (M4B) [start] is the absolute seek offset into the file.
class Chapter {
  final String title;
  final Duration start;

  const Chapter({required this.title, required this.start});
}

/// Where the audiobook's source files originate.
enum AudiobookSource { local, drive }

/// Metadata specific to a Google Drive–sourced book.
class DriveBookMeta {
  final String folderId;    // Drive folder ID (the "book folder")
  final String folderName;  // Original Drive folder name
  final bool isShared;      // true = "Shared with me"
  final int totalFileCount; // Total number of audio files in the Drive folder

  const DriveBookMeta({
    required this.folderId,
    required this.folderName,
    required this.isShared,
    required this.totalFileCount,
  });
}

class Audiobook {
  final String title;
  final String? author;
  final Duration? duration;

  /// Path to the book folder.
  final String path;

  /// Path to a cover image file on disk, if one was found.
  final String? coverImagePath;

  /// Embedded cover art bytes extracted from audio metadata.
  final Uint8List? coverImageBytes;

  final List<String> audioFiles;

  /// Duration of each individual audio file, in the same order as [audioFiles].
  final List<Duration> chapterDurations;

  /// Embedded chapters parsed from a single M4B file (empty for multi-file books).
  final List<Chapter> chapters;

  /// Display names for each audio file in a multi-file book, derived from
  /// the `title` metadata tag via a heuristic (see ScannerService).
  /// Empty when no usable title metadata was found — player falls back to
  /// the filename in that case. Always empty for M4B/CUE books (which use
  /// [chapters] instead).
  final List<String> chapterNames;

  /// True when the folder contains only DRM-locked files (e.g. .aax, .aa)
  /// that cannot be played by the app.
  final bool isDrmLocked;

  /// Source of the audiobook files (local filesystem or Google Drive).
  final AudiobookSource source;

  /// Drive-specific metadata. Non-null only when [source] == [AudiobookSource.drive].
  final DriveBookMeta? driveMetadata;

  const Audiobook({
    required this.title,
    this.author,
    this.duration,
    required this.path,
    this.coverImagePath,
    this.coverImageBytes,
    required this.audioFiles,
    this.chapterDurations = const [],
    this.chapters = const [],
    this.chapterNames = const [],
    this.isDrmLocked = false,
    this.source = AudiobookSource.local,
    this.driveMetadata,
  });

  /// Returns the index of the M4B embedded chapter that contains [position].
  /// Returns 0 if [chapters] is empty.
  int chapterIndexAt(Duration position) {
    if (chapters.isEmpty) return 0;
    int current = 0;
    for (int i = 0; i < chapters.length; i++) {
      if (position >= chapters[i].start) {
        current = i;
      } else {
        break;
      }
    }
    return current;
  }

  Audiobook copyWith({
    String? coverImagePath,
    Uint8List? coverImageBytes,
    List<String>? audioFiles,
    List<Duration>? chapterDurations,
    List<Chapter>? chapters,
    List<String>? chapterNames,
    String? title,
    String? author,
    Duration? duration,
  }) {
    return Audiobook(
      title: title ?? this.title,
      author: author ?? this.author,
      duration: duration ?? this.duration,
      path: path,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      coverImageBytes: coverImageBytes ?? this.coverImageBytes,
      audioFiles: audioFiles ?? this.audioFiles,
      chapterDurations: chapterDurations ?? this.chapterDurations,
      chapters: chapters ?? this.chapters,
      chapterNames: chapterNames ?? this.chapterNames,
      isDrmLocked: isDrmLocked,
      source: source,
      driveMetadata: driveMetadata,
    );
  }
}
