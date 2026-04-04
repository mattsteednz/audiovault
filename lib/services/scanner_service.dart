import 'dart:io';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/audiobook.dart';

class ScannerService {
  static const _audioExtensions = {'.mp3', '.m4a', '.aac', '.m4b'};
  static const _imageExtensions = {'.jpg', '.jpeg', '.png', '.webp'};

  static void _log(String msg) => debugPrint('[AudioVault:Scanner] $msg');

  Future<List<Audiobook>> scanFolder(String folderPath) async {
    final dir = Directory(folderPath);
    _log('── SCAN START ──────────────────────────────');
    _log('Root path : $folderPath');
    _log('Exists    : ${await dir.exists()}');

    if (!await dir.exists()) {
      _log('Root does not exist — aborting.');
      return [];
    }

    final entries = await dir.list().toList();
    final subdirs = entries.whereType<Directory>().toList();
    final rootFiles = entries.whereType<File>().toList();

    _log('Entries   : ${entries.length} total '
        '(${subdirs.length} dirs, ${rootFiles.length} files)');
    _log('Subdirs   : ${subdirs.map((d) => p.basename(d.path)).join(', ')}');

    final books = <Audiobook>[];
    for (final subdir in subdirs) {
      final book = await _scanSubfolder(subdir);
      if (book != null) books.add(book);
    }

    books.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    _log('── SCAN END — ${books.length} book(s) found ──');
    return books;
  }

  Future<Audiobook?> _scanSubfolder(Directory dir) async {
    final name = p.basename(dir.path);
    _log('  Folder: "$name"');

    List<FileSystemEntity> entries;
    try {
      entries = await dir.list().toList();
    } catch (e) {
      _log('    ERROR listing folder: $e');
      return null;
    }

    final allFiles = entries.whereType<File>().toList();
    final audioFiles = allFiles
        .where((f) => _isAudio(f.path))
        .map((f) => f.path)
        .toList()
      ..sort();

    final imageFiles = allFiles.where((f) => _isImage(f.path)).toList();

    _log('    Audio (${audioFiles.length}): ${audioFiles.map(p.basename).join(', ')}');
    _log('    Images(${imageFiles.length}): ${imageFiles.map((f) => p.basename(f.path)).join(', ')}');

    if (audioFiles.isEmpty) {
      _log('    → SKIP (no recognised audio files)');
      return null;
    }

    final coverPath = _pickBestCover(imageFiles);
    String title = name;
    String? author;
    Duration totalDuration = Duration.zero;
    final chapterDurations = <Duration>[];
    Uint8List? coverBytes;
    bool foundCoverInMetadata = false;

    // Read metadata from each audio file.
    // – Duration is always summed across all files.
    // – Title/author are taken from the first file that has them.
    // – Embedded art is taken from the first file that has it
    //   (only sought when no image file exists on disk).
    for (final filePath in audioFiles) {
      try {
        final needArt = coverPath == null && !foundCoverInMetadata;
        final metadata = readMetadata(File(filePath), getImage: needArt);

        // Sum durations.
        final fileDur = metadata.duration ?? Duration.zero;
        chapterDurations.add(fileDur);
        totalDuration += fileDur;

        // Use album tag as book title (track title is a chapter name, not the book).
        if (title == name) {
          final album = metadata.album;
          if (album != null && album.isNotEmpty) title = album;
        }

        // Use first non-empty artist as author.
        if (author == null) {
          final a = metadata.artist;
          if (a != null && a.isNotEmpty) author = a;
        }

        // Extract embedded cover art.
        if (needArt && metadata.pictures.isNotEmpty) {
          coverBytes = metadata.pictures.first.bytes;
          foundCoverInMetadata = true;
          _log('    Embedded art found in ${p.basename(filePath)}: '
              '${coverBytes.length} bytes');
        }
      } catch (e) {
        _log('    Metadata error for ${p.basename(filePath)}: $e');
        chapterDurations.add(Duration.zero); // keep list in sync with audioFiles
      }
    }

    final duration = totalDuration == Duration.zero ? null : totalDuration;
    _log('    title="$title" author="${author ?? 'none'}" '
        'duration=${duration?.toString() ?? 'unknown'} '
        'cover=${coverPath != null ? p.basename(coverPath) : coverBytes != null ? '<embedded>' : 'none'}');
    _log('    → HIT');

    return Audiobook(
      title: title,
      author: author,
      duration: duration,
      path: dir.path,
      coverImagePath: coverPath,
      coverImageBytes: coverBytes,
      audioFiles: audioFiles,
      chapterDurations: chapterDurations,
    );
  }

  /// Cover priority:
  ///   1. cover.jpg or Cover.jpg (exact filename)
  ///   2. Any image whose base name contains "cover" (case-insensitive)
  ///   3. First image found
  String? _pickBestCover(List<File> images) {
    if (images.isEmpty) return null;
    for (final file in images) {
      final name = p.basename(file.path);
      if (name == 'cover.jpg' || name == 'Cover.jpg') return file.path;
    }
    for (final file in images) {
      if (p.basenameWithoutExtension(file.path).toLowerCase().contains('cover')) {
        return file.path;
      }
    }
    return images.first.path;
  }

  bool _isAudio(String path) => _audioExtensions.contains(p.extension(path).toLowerCase());
  bool _isImage(String path) => _imageExtensions.contains(p.extension(path).toLowerCase());
}
