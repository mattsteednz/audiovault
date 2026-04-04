import 'dart:typed_data';

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

  const Audiobook({
    required this.title,
    this.author,
    this.duration,
    required this.path,
    this.coverImagePath,
    this.coverImageBytes,
    required this.audioFiles,
    this.chapterDurations = const [],
  });
}
