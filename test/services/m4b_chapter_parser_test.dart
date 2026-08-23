import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kowhai/services/m4b_chapter_parser.dart';

/// Builds a minimal MP4 box: 4-byte big-endian size + 4-byte type + [data].
Uint8List _box(String type, Uint8List data) {
  final size = 8 + data.length;
  final buf = ByteData(8);
  buf.setUint32(0, size, Endian.big);
  final header = Uint8List(8);
  for (int i = 0; i < 8; i++) { header[i] = buf.getUint8(i); }
  header[4] = type.codeUnitAt(0);
  header[5] = type.codeUnitAt(1);
  header[6] = type.codeUnitAt(2);
  header[7] = type.codeUnitAt(3);
  return Uint8List.fromList([...header, ...data]);
}

/// Wraps [inner] in a container box of the given [type].
Uint8List _containerBox(String type, List<Uint8List> children) {
  final inner = children.expand((c) => c).toList();
  return _box(type, Uint8List.fromList(inner));
}

/// Builds a Nero `chpl` box payload with the given chapter entries.
/// Each entry: 8-byte timestamp (100ns units) + 1-byte title length + title.
Uint8List _buildChplPayload(List<(Duration, String)> chapters) {
  final buf = BytesBuilder();
  // version (1 byte) + flags (3 bytes) + reserved (1 byte)
  buf.add([0, 0, 0, 0, 0]);
  // chapter count (4 bytes big-endian)
  final countBuf = ByteData(4);
  countBuf.setUint32(0, chapters.length, Endian.big);
  buf.add(countBuf.buffer.asUint8List());
  for (final (dur, title) in chapters) {
    // Timestamp in 100ns units
    final units100ns = dur.inMicroseconds * 10;
    final tsBuf = ByteData(8);
    tsBuf.setUint32(0, (units100ns >> 32) & 0xFFFFFFFF, Endian.big);
    tsBuf.setUint32(4, units100ns & 0xFFFFFFFF, Endian.big);
    buf.add(tsBuf.buffer.asUint8List());
    // Title length + title bytes
    final titleBytes = title.codeUnits;
    buf.addByte(titleBytes.length);
    buf.add(titleBytes);
  }
  return buf.toBytes();
}

/// Writes [bytes] to a temp file and returns the path.
Future<String> _writeTempFile(Directory dir, Uint8List bytes) async {
  final file = File('${dir.path}/test.m4b');
  await file.writeAsBytes(bytes);
  return file.path;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('m4b_parser_test_');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('M4bChapterParser — Nero chpl format', () {
    test('parses chapters from a minimal moov/udta/chpl structure', () async {
      final chplData = _buildChplPayload([
        (Duration.zero, 'Intro'),
        (const Duration(minutes: 5), 'Chapter 1'),
        (const Duration(minutes: 15, seconds: 30), 'Chapter 2'),
      ]);
      final chplBox = _box('chpl', chplData);
      final udtaBox = _containerBox('udta', [chplBox]);
      final moovBox = _containerBox('moov', [udtaBox]);
      // Add a minimal ftyp box before moov (standard MP4 structure).
      final ftypBox = _box('ftyp', Uint8List.fromList([
        // brand "M4B " + version 0
        0x4D, 0x34, 0x42, 0x20, 0x00, 0x00, 0x00, 0x00,
      ]));
      final fileBytes = Uint8List.fromList([...ftypBox, ...moovBox]);
      final path = await _writeTempFile(tempDir, fileBytes);

      final chapters = await M4bChapterParser.parseChapters(path);

      expect(chapters.length, 3);
      expect(chapters[0].title, 'Intro');
      expect(chapters[0].start, Duration.zero);
      expect(chapters[1].title, 'Chapter 1');
      expect(chapters[1].start, const Duration(minutes: 5));
      expect(chapters[2].title, 'Chapter 2');
      expect(chapters[2].start, const Duration(minutes: 15, seconds: 30));
    });

    test('returns empty list for truncated chpl payload', () async {
      // chpl box with only 3 bytes of data (too short for header)
      final chplBox = _box('chpl', Uint8List.fromList([0, 0, 0]));
      final udtaBox = _containerBox('udta', [chplBox]);
      final moovBox = _containerBox('moov', [udtaBox]);
      final path = await _writeTempFile(tempDir, moovBox);

      final chapters = await M4bChapterParser.parseChapters(path);
      expect(chapters, isEmpty);
    });

    test('parses chpl nested inside a FullBox meta container', () async {
      // iTunes-style layout: moov/udta/meta/chpl where `meta` carries a
      // 4-byte version/flags header between its own header and its children.
      final chplData = _buildChplPayload([
        (Duration.zero, 'Intro'),
        (const Duration(minutes: 5), 'Chapter 1'),
      ]);
      final chplBox = _box('chpl', chplData);
      final metaPayload =
          Uint8List.fromList([0, 0, 0, 0, ...chplBox]); // FullBox header
      final metaBox = _box('meta', metaPayload);
      final udtaBox = _containerBox('udta', [metaBox]);
      final moovBox = _containerBox('moov', [udtaBox]);
      final path = await _writeTempFile(tempDir, moovBox);

      final chapters = await M4bChapterParser.parseChapters(path);

      expect(chapters.length, 2);
      expect(chapters[0].title, 'Intro');
      expect(chapters[1].title, 'Chapter 1');
    });

    test('sorts out-of-order chpl entries chronologically', () async {
      final chplData = _buildChplPayload([
        (const Duration(minutes: 15), 'Late'),
        (Duration.zero, 'First'),
        (const Duration(minutes: 5), 'Middle'),
      ]);
      final chplBox = _box('chpl', chplData);
      final udtaBox = _containerBox('udta', [chplBox]);
      final moovBox = _containerBox('moov', [udtaBox]);
      final path = await _writeTempFile(tempDir, moovBox);

      final chapters = await M4bChapterParser.parseChapters(path);

      expect(
          chapters.map((c) => c.title).toList(), ['First', 'Middle', 'Late']);
    });
  });

  group('M4bChapterParser — edge cases', () {
    test('returns empty list for a non-MP4 file', () async {
      final path = await _writeTempFile(
          tempDir, Uint8List.fromList('not an mp4 file at all'.codeUnits));

      final chapters = await M4bChapterParser.parseChapters(path);
      expect(chapters, isEmpty);
    });

    test('returns empty list for an empty file', () async {
      final path = await _writeTempFile(tempDir, Uint8List(0));

      final chapters = await M4bChapterParser.parseChapters(path);
      expect(chapters, isEmpty);
    });

    test('returns empty list for a non-existent file', () async {
      final chapters = await M4bChapterParser.parseChapters(
          '${tempDir.path}/does_not_exist.m4b');
      expect(chapters, isEmpty);
    });

    test('returns empty list for moov with no chapter data', () async {
      // moov box with only a mvhd-like dummy box, no udta/chpl/trak
      final dummyBox = _box('mvhd', Uint8List(100));
      final moovBox = _containerBox('moov', [dummyBox]);
      final path = await _writeTempFile(tempDir, moovBox);

      final chapters = await M4bChapterParser.parseChapters(path);
      expect(chapters, isEmpty);
    });
  });
}
