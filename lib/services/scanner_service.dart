import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/audiobook.dart';

/// Parsed result from a `.cue` sheet file.
class _CueSheet {
  final String? title;
  final String? author;

  /// Resolved, on-disk audio file paths in cue-sheet order.
  final List<String> audioFiles;

  /// Chapter list — only populated for single-file cue sheets.
  /// Multi-file cue sheets leave this empty (each file is its own chapter).
  final List<Chapter> chapters;

  const _CueSheet({
    this.title,
    this.author,
    required this.audioFiles,
    required this.chapters,
  });
}

class ScannerService {
  static const _audioExtensions = {'.mp3', '.m4a', '.aac', '.m4b', '.flac', '.ogg'};
  static const _imageExtensions = {'.jpg', '.jpeg', '.png', '.webp'};
  // Audible formats — detected but not playable due to DRM.
  static const _drmExtensions = {'.aax', '.aa'};

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
    final subdirs = entries
        .whereType<Directory>()
        .where((d) => !p.basename(d.path).startsWith('.'))
        .toList();
    final rootFiles = entries
        .whereType<File>()
        .where((f) => !p.basename(f.path).startsWith('.'))
        .toList();

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

    final allFiles = entries
        .whereType<File>()
        .where((f) => !p.basename(f.path).startsWith('.'))
        .toList();
    final audioFiles = allFiles
        .where((f) => _isAudio(f.path))
        .map((f) => f.path)
        .toList()
      ..sort(_naturalSort);

    final imageFiles = allFiles.where((f) => _isImage(f.path)).toList();

    // Parse .cue sheet if one exists (takes precedence over natural-sort order).
    _CueSheet? cueSheet;
    final cueFiles = allFiles
        .where((f) => p.extension(f.path).toLowerCase() == '.cue')
        .toList();
    if (cueFiles.isNotEmpty) {
      try {
        final content = await cueFiles.first.readAsString();
        cueSheet = _parseCueSheet(content, dir.path);
        _log('    CUE: ${cueSheet?.audioFiles.length ?? 0} file(s), '
            '${cueSheet?.chapters.length ?? 0} chapter(s)');
      } catch (e) {
        _log('    CUE parse error: $e');
      }
    }

    // If the .cue sheet resolved audio files, use that ordered list; otherwise
    // fall back to the naturally-sorted files found on disk.
    if (cueSheet != null && cueSheet.audioFiles.isNotEmpty) {
      audioFiles
        ..clear()
        ..addAll(cueSheet.audioFiles);
    }

    _log('    Audio (${audioFiles.length}): ${audioFiles.map(p.basename).join(', ')}');
    _log('    Images(${imageFiles.length}): ${imageFiles.map((f) => p.basename(f.path)).join(', ')}');

    if (audioFiles.isEmpty) {
      // Check for DRM-locked Audible files before skipping.
      final drmFiles = allFiles.where((f) => _isDrm(f.path)).toList();
      if (drmFiles.isNotEmpty) {
        // Use the filename (minus extension) as title when there is only one
        // file; otherwise fall back to the folder name.
        final title = drmFiles.length == 1
            ? p.basenameWithoutExtension(drmFiles.first.path)
            : name;
        _log('    → DRM-LOCKED (${drmFiles.length} file(s): '
            '${drmFiles.map((f) => p.basename(f.path)).join(', ')})');
        return Audiobook(
          title: title,
          path: dir.path,
          audioFiles: const [],
          isDrmLocked: true,
        );
      }
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

    // .cue metadata fills in what embedded tags didn't provide.
    if (cueSheet?.title != null && title == name) title = cueSheet!.title!;
    if (cueSheet?.author != null && author == null) author = cueSheet!.author;

    // Chapter parsing: embedded M4B takes priority; .cue is second choice.
    List<Chapter> chapters = const [];
    if (audioFiles.length == 1 &&
        p.extension(audioFiles.first).toLowerCase() == '.m4b') {
      chapters = await _parseM4bChapters(audioFiles.first);
      _log('    M4B chapters: ${chapters.length}');
    } else if (cueSheet != null && cueSheet.chapters.isNotEmpty) {
      chapters = cueSheet.chapters;
      _log('    CUE chapters: ${chapters.length}');
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
      chapters: chapters,
    );
  }

  // ── M4B chapter parsing ───────────────────────────────────────────────────

  /// Entry point: tries Nero `chpl` first, then QuickTime chapter track.
  Future<List<Chapter>> _parseM4bChapters(String filePath) async {
    RandomAccessFile? raf;
    try {
      raf = await File(filePath).open();
      final fileSize = await raf.length();

      // Try Nero chpl (less common)
      final nero = await _scanForChpl(raf, 0, fileSize);
      if (nero.isNotEmpty) {
        _log('    M4B chapters (Nero): ${nero.length}');
        return nero;
      }

      // Try QuickTime chapter track (iTunes / Audible format)
      final qt = await _parseQTChapters(raf, fileSize);
      _log('    M4B chapters (QT): ${qt.length}');
      return qt;
    } catch (e) {
      _log('    M4B chapter parse error: $e');
      return const [];
    } finally {
      await raf?.close();
    }
  }

  // ── Shared MP4 box utilities ──────────────────────────────────────────────

  /// Returns all direct child boxes within [start, end] as (type, dataStart, boxEnd).
  Future<List<(String, int, int)>> _listBoxes(
      RandomAccessFile raf, int start, int end) async {
    final result = <(String, int, int)>[];
    var pos = start;
    while (pos + 8 <= end) {
      await raf.setPosition(pos);
      final hdr = await raf.read(8);
      if (hdr.length < 8) break;
      final bd = ByteData.sublistView(Uint8List.fromList(hdr));
      var sz = bd.getUint32(0, Endian.big);
      final type = String.fromCharCodes(hdr.sublist(4, 8));
      int dataStart = pos + 8;
      if (sz == 1) {
        final ext = await raf.read(8);
        if (ext.length < 8) break;
        final ebd = ByteData.sublistView(Uint8List.fromList(ext));
        sz = (ebd.getUint32(0, Endian.big) << 32) | ebd.getUint32(4, Endian.big);
        dataStart = pos + 16;
      } else if (sz == 0) {
        sz = end - pos;
      }
      if (sz < 8) break;
      result.add((type, dataStart, pos + sz));
      pos += sz;
    }
    return result;
  }

  /// First box matching [type] in [boxes], or null.
  (String, int, int)? _firstBox(List<(String, int, int)> boxes, String type) {
    for (final b in boxes) {
      if (b.$1 == type) return b;
    }
    return null;
  }

  /// Reads the data portion of [box] into memory.
  Future<Uint8List> _readBox(RandomAccessFile raf, (String, int, int) box) async {
    final len = box.$3 - box.$2;
    await raf.setPosition(box.$2);
    return Uint8List.fromList(await raf.read(len));
  }

  // ── Nero chpl format ──────────────────────────────────────────────────────

  Future<List<Chapter>> _scanForChpl(
      RandomAccessFile raf, int start, int end) async {
    final boxes = await _listBoxes(raf, start, end);
    for (final box in boxes) {
      if (box.$1 == 'chpl') {
        return _parseChpl(await _readBox(raf, box));
      }
      if (box.$1 == 'moov' || box.$1 == 'udta' || box.$1 == 'meta') {
        final result = await _scanForChpl(raf, box.$2, box.$3);
        if (result.isNotEmpty) return result;
      }
    }
    return const [];
  }

  List<Chapter> _parseChpl(Uint8List data) {
    if (data.length < 9) return const [];
    final bd = ByteData.sublistView(data);
    int offset = 5; // version(1) + flags(3) + reserved(1)
    if (offset + 4 > data.length) return const [];
    final count = bd.getUint32(offset, Endian.big);
    offset += 4;
    final chapters = <Chapter>[];
    for (int i = 0; i < count; i++) {
      if (offset + 9 > data.length) break;
      final hi = bd.getUint32(offset, Endian.big);
      final lo = bd.getUint32(offset + 4, Endian.big);
      final units100ns = (hi << 32) | lo;
      offset += 8;
      final titleLen = data[offset++];
      if (offset + titleLen > data.length) break;
      chapters.add(Chapter(
        title: utf8.decode(data.sublist(offset, offset + titleLen),
            allowMalformed: true),
        start: Duration(microseconds: units100ns ~/ 10),
      ));
      offset += titleLen;
    }
    return chapters;
  }

  // ── QuickTime chapter track format ────────────────────────────────────────
  //
  // iTunes M4B files store chapters as a separate text `trak` identified by
  // a `gmhd` (generic media header) inside its `minf`. The audio trak has a
  // `tref/chap` reference pointing to this track. Chapter timestamps come
  // from `stts` (time-to-sample table) and titles are text samples read via
  // `stco` (chunk offsets) + `stsz` (sample sizes).

  Future<List<Chapter>> _parseQTChapters(
      RandomAccessFile raf, int fileSize) async {
    final top = await _listBoxes(raf, 0, fileSize);
    final moov = _firstBox(top, 'moov');
    if (moov == null) return const [];

    final moovBoxes = await _listBoxes(raf, moov.$2, moov.$3);
    for (final box in moovBoxes) {
      if (box.$1 != 'trak') continue;
      final chapters = await _tryQTChapterTrak(raf, box);
      if (chapters.isNotEmpty) return chapters;
    }
    return const [];
  }

  Future<List<Chapter>> _tryQTChapterTrak(
      RandomAccessFile raf, (String, int, int) trak) async {
    final trakBoxes = await _listBoxes(raf, trak.$2, trak.$3);
    final mdia = _firstBox(trakBoxes, 'mdia');
    if (mdia == null) return const [];

    final mdiaBoxes = await _listBoxes(raf, mdia.$2, mdia.$3);
    final mdhd = _firstBox(mdiaBoxes, 'mdhd');
    final minf = _firstBox(mdiaBoxes, 'minf');
    if (mdhd == null || minf == null) return const [];

    final minfBoxes = await _listBoxes(raf, minf.$2, minf.$3);
    // gmhd = generic media header; present in chapter/text tracks
    if (_firstBox(minfBoxes, 'gmhd') == null) return const [];

    final stbl = _firstBox(minfBoxes, 'stbl');
    if (stbl == null) return const [];

    final stblBoxes = await _listBoxes(raf, stbl.$2, stbl.$3);
    final stts = _firstBox(stblBoxes, 'stts');
    final stsz = _firstBox(stblBoxes, 'stsz');
    final stco = _firstBox(stblBoxes, 'stco');
    final co64 = _firstBox(stblBoxes, 'co64');
    final stsc = _firstBox(stblBoxes, 'stsc');
    if (stts == null || stsz == null || (stco == null && co64 == null)) {
      return const [];
    }

    return await _extractQTChapters(raf, mdhd, stts, stsz, stco ?? co64!, stsc,
        isco64: stco == null);
  }

  Future<List<Chapter>> _extractQTChapters(
    RandomAccessFile raf,
    (String, int, int) mdhd,
    (String, int, int) stts,
    (String, int, int) stsz,
    (String, int, int) stco,
    (String, int, int)? stsc, {
    bool isco64 = false,
  }) async {
    final mdhdData = await _readBox(raf, mdhd);
    final sttsData = await _readBox(raf, stts);
    final stszData = await _readBox(raf, stsz);
    final stcoData = await _readBox(raf, stco);
    final stscData = stsc != null ? await _readBox(raf, stsc) : null;

    // Time scale from mdhd (version 0: offset 12; version 1: offset 20)
    final mdhdBD = ByteData.sublistView(mdhdData);
    final timeScale = mdhdBD.getUint32(mdhdData[0] == 1 ? 20 : 12, Endian.big);
    if (timeScale == 0) return const [];

    // Sample start times from stts (time-to-sample table)
    final sttsBD = ByteData.sublistView(sttsData);
    final sttsCount = sttsBD.getUint32(4, Endian.big);
    final sampleStarts = <int>[];
    int ticks = 0, off = 8;
    for (int i = 0; i < sttsCount && off + 8 <= sttsData.length; i++) {
      final n = sttsBD.getUint32(off, Endian.big);     // sample count in run
      final d = sttsBD.getUint32(off + 4, Endian.big); // duration per sample
      for (int j = 0; j < n; j++) {
        sampleStarts.add(ticks);
        ticks += d;
      }
      off += 8;
    }

    // Sample sizes from stsz
    final stszBD = ByteData.sublistView(stszData);
    final defSz = stszBD.getUint32(4, Endian.big);
    final sampleCount = stszBD.getUint32(8, Endian.big);
    final sizes = <int>[];
    if (defSz == 0) {
      off = 12;
      for (int i = 0; i < sampleCount && off + 4 <= stszData.length; i++, off += 4) {
        sizes.add(stszBD.getUint32(off, Endian.big));
      }
    } else {
      sizes.addAll(List.filled(sampleCount, defSz));
    }

    // Chunk file offsets from stco (32-bit) or co64 (64-bit)
    final stcoBD = ByteData.sublistView(stcoData);
    final chunkCount = stcoBD.getUint32(4, Endian.big);
    final chunkOffsets = <int>[];
    off = 8;
    if (isco64) {
      for (int i = 0; i < chunkCount && off + 8 <= stcoData.length; i++, off += 8) {
        final hi = stcoBD.getUint32(off, Endian.big);
        final lo = stcoBD.getUint32(off + 4, Endian.big);
        chunkOffsets.add((hi << 32) | lo);
      }
    } else {
      for (int i = 0; i < chunkCount && off + 4 <= stcoData.length; i++, off += 4) {
        chunkOffsets.add(stcoBD.getUint32(off, Endian.big));
      }
    }

    // Map sample index → file offset using stsc (sample-to-chunk table)
    final sampleOffsets = <int>[];
    if (stscData != null && stscData.length >= 8) {
      final stscBD = ByteData.sublistView(stscData);
      final stscCount = stscBD.getUint32(4, Endian.big);
      // Each stsc entry: firstChunk(4) + samplesPerChunk(4) + descIndex(4)
      final runs = <(int, int)>[]; // (firstChunk 0-based, samplesPerChunk)
      off = 8;
      for (int i = 0; i < stscCount && off + 12 <= stscData.length; i++, off += 12) {
        runs.add((stscBD.getUint32(off, Endian.big) - 1,
                  stscBD.getUint32(off + 4, Endian.big)));
      }
      int sIdx = 0;
      for (int c = 0; c < chunkOffsets.length; c++) {
        // Find samples-per-chunk for this chunk from the run table
        int spc = 1;
        for (int e = runs.length - 1; e >= 0; e--) {
          if (c >= runs[e].$1) { spc = runs[e].$2; break; }
        }
        int chunkOff = chunkOffsets[c];
        for (int j = 0; j < spc && sIdx < sizes.length; j++, sIdx++) {
          sampleOffsets.add(chunkOff);
          chunkOff += sizes[sIdx];
        }
      }
    } else {
      // No stsc: assume one sample per chunk
      sampleOffsets.addAll(chunkOffsets.take(sizes.length));
    }

    // Read each chapter text sample and build Chapter list
    final chapters = <Chapter>[];
    for (int i = 0;
        i < sizes.length && i < sampleOffsets.length && i < sampleStarts.length;
        i++) {
      await raf.setPosition(sampleOffsets[i]);
      final data = await raf.read(sizes[i]);
      if (data.length < 3) continue;

      // QuickTime text sample: 2-byte big-endian length + UTF-8 string
      final len = (data[0] << 8) | data[1];
      if (len == 0 || 2 + len > data.length) continue;

      final titleBytes = data.sublist(2, 2 + len);
      String title;
      try {
        title = utf8.decode(titleBytes);
      } catch (_) {
        // Fall back to UTF-16BE
        final chars = <int>[];
        for (int j = 0; j + 1 < titleBytes.length; j += 2) {
          chars.add((titleBytes[j] << 8) | titleBytes[j + 1]);
        }
        title = String.fromCharCodes(chars);
      }

      chapters.add(Chapter(
        title: title,
        start: Duration(microseconds: sampleStarts[i] * 1000000 ~/ timeScale),
      ));
    }
    return chapters;
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

  /// Natural sort: compares strings by splitting into numeric and non-numeric
  /// segments so that "2.mp3" < "10.mp3" < "100.mp3".
  int _naturalSort(String a, String b) {
    final nameA = p.basename(a).toLowerCase();
    final nameB = p.basename(b).toLowerCase();
    final re = RegExp(r'(\d+)|(\D+)');
    final segA = re.allMatches(nameA).toList();
    final segB = re.allMatches(nameB).toList();
    final len = segA.length < segB.length ? segA.length : segB.length;
    for (var i = 0; i < len; i++) {
      final sa = segA[i].group(0)!;
      final sb = segB[i].group(0)!;
      final na = int.tryParse(sa);
      final nb = int.tryParse(sb);
      final cmp = (na != null && nb != null)
          ? na.compareTo(nb)
          : sa.compareTo(sb);
      if (cmp != 0) return cmp;
    }
    return segA.length.compareTo(segB.length);
  }

  // ── CUE sheet parser ─────────────────────────────────────────────────────
  //
  // Parses a Red Book / CD-DA cue sheet into a [_CueSheet].
  //
  // Supported subset:
  //   FILE "name" <type>   – audio file reference (quoted or unquoted)
  //   PERFORMER "..."      – global author (ignored at track level)
  //   TITLE "..."          – global title or per-track chapter name
  //   TRACK nn AUDIO       – track declaration
  //   INDEX 01 MM:SS:FF    – chapter start (75 frames/sec)
  //
  // Multi-file cue sheets (more than one FILE directive) are supported for
  // ordering and metadata, but chapters are only extracted for single-file
  // sheets because track timestamps are relative to each file's start.

  _CueSheet? _parseCueSheet(String content, String folderPath) {
    String? globalTitle;
    String? globalPerformer;

    // Accumulate per-FILE sections.
    final fileSections = <({String path, List<Chapter> chapters})>[];
    String? currentFilePath; // null if file was missing from disk
    final pendingChapters = <Chapter>[];
    String? pendingTrackTitle;

    void commitFile() {
      if (currentFilePath != null) {
        fileSections.add((
          path: currentFilePath!,
          chapters: List.of(pendingChapters),
        ));
      }
      pendingChapters.clear();
      currentFilePath = null;
      pendingTrackTitle = null;
    }

    for (var line in content.split('\n')) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('REM')) continue;

      if (line.startsWith('FILE ')) {
        commitFile();
        final match = RegExp(r'^FILE\s+"(.+?)"\s+\S+').firstMatch(line) ??
            RegExp(r'^FILE\s+(\S+)\s+\S+').firstMatch(line);
        if (match == null) continue;
        // Normalise path separators for the current platform.
        final filename = match.group(1)!.replaceAll('\\', p.separator);
        final resolved = p.join(folderPath, filename);
        currentFilePath = File(resolved).existsSync() ? resolved : null;
        pendingTrackTitle = null;
      } else if (line.startsWith('TITLE ')) {
        final title = _cueUnquote(line.substring(6));
        if (currentFilePath == null && fileSections.isEmpty) {
          globalTitle = title;
        } else {
          pendingTrackTitle = title;
        }
      } else if (line.startsWith('PERFORMER ')) {
        final performer = _cueUnquote(line.substring(10));
        if (currentFilePath == null && fileSections.isEmpty) {
          globalPerformer = performer;
        }
      } else if (line.startsWith('INDEX 01 ') && pendingTrackTitle != null) {
        final dur = _parseCueTime(line.substring(9).trim());
        if (dur != null && currentFilePath != null) {
          pendingChapters.add(Chapter(title: pendingTrackTitle!, start: dur));
        }
        pendingTrackTitle = null; // consumed
      }
    }
    commitFile();

    if (fileSections.isEmpty) return null;

    final audioPaths = fileSections.map((s) => s.path).toList();

    // Only expose chapters for single-file sheets; multi-file track timestamps
    // are relative to their respective file — not yet supported.
    final chapters = fileSections.length == 1
        ? fileSections.first.chapters
        : const <Chapter>[];

    return _CueSheet(
      title: globalTitle,
      author: globalPerformer,
      audioFiles: audioPaths,
      chapters: chapters,
    );
  }

  /// Strips surrounding quotes from a cue-sheet string value.
  String _cueUnquote(String s) {
    s = s.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  /// Parses a CUE timestamp `MM:SS:FF` (75 frames/sec) to [Duration].
  Duration? _parseCueTime(String s) {
    final parts = s.split(':');
    if (parts.length != 3) return null;
    final mm = int.tryParse(parts[0]);
    final ss = int.tryParse(parts[1]);
    final ff = int.tryParse(parts[2]);
    if (mm == null || ss == null || ff == null) return null;
    return Duration(milliseconds: mm * 60000 + ss * 1000 + ff * 1000 ~/ 75);
  }

  bool _isAudio(String path) => _audioExtensions.contains(p.extension(path).toLowerCase());
  bool _isImage(String path) => _imageExtensions.contains(p.extension(path).toLowerCase());
  bool _isDrm(String path) => _drmExtensions.contains(p.extension(path).toLowerCase());
}
