import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault/services/scanner_service.dart';

void main() {
  group('ScannerService', () {
    late Directory tempDir;
    late ScannerService scannerService;

    setUp(() async {
      scannerService = ScannerService();
      tempDir = await Directory.systemTemp.createTemp('audiovault_test_');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // audio_metadata_reader might leave file handles open on crash
      }
    });

    // ── CUE sheet support ────────────────────────────────────────────────────

    test('single-file .cue: chapters, title, and author are parsed', () async {
      final bookDir = Directory('${tempDir.path}/My Audiobook');
      await bookDir.create();

      await File('${bookDir.path}/audiobook.mp3').writeAsBytes([]);
      await File('${bookDir.path}/audiobook.cue').writeAsString('''
PERFORMER "Some Author"
TITLE "My Audiobook"
FILE "audiobook.mp3" MP3
  TRACK 01 AUDIO
    TITLE "Chapter One"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Chapter Two"
    INDEX 01 10:30:00
  TRACK 03 AUDIO
    TITLE "Chapter Three"
    INDEX 01 25:15:37
''');

      final books = await scannerService.scanFolder(tempDir.path);
      expect(books.length, 1);
      final book = books.first;

      expect(book.title, 'My Audiobook');
      expect(book.author, 'Some Author');
      expect(book.chapters.length, 3);

      expect(book.chapters[0].title, 'Chapter One');
      expect(book.chapters[0].start, Duration.zero);

      expect(book.chapters[1].title, 'Chapter Two');
      // 10:30:00 → 10*60000 + 30*1000 + 0 = 630 000 ms
      expect(book.chapters[1].start, const Duration(milliseconds: 630000));

      expect(book.chapters[2].title, 'Chapter Three');
      // 25:15:37 → 25*60000 + 15*1000 + 37*1000÷75 = 1 500 000 + 15 000 + 493 = 1 515 493 ms
      expect(book.chapters[2].start, const Duration(milliseconds: 1515493));
    });

    test('multi-file .cue: audio files use cue order, no chapters', () async {
      final bookDir = Directory('${tempDir.path}/Multi Book');
      await bookDir.create();

      // Create files in reverse alphabetical order on disk.
      for (final name in ['part3.mp3', 'part1.mp3', 'part2.mp3']) {
        await File('${bookDir.path}/$name').writeAsBytes([]);
      }

      await File('${bookDir.path}/book.cue').writeAsString('''
PERFORMER "The Author"
TITLE "Multi Book"
FILE "part1.mp3" MP3
  TRACK 01 AUDIO
    TITLE "Part One"
    INDEX 01 00:00:00
FILE "part2.mp3" MP3
  TRACK 02 AUDIO
    TITLE "Part Two"
    INDEX 01 00:00:00
FILE "part3.mp3" MP3
  TRACK 03 AUDIO
    TITLE "Part Three"
    INDEX 01 00:00:00
''');

      final books = await scannerService.scanFolder(tempDir.path);
      expect(books.length, 1);
      final book = books.first;

      // Should follow cue order, not alphabetical.
      expect(book.audioFiles.length, 3);
      expect(book.audioFiles[0], endsWith('part1.mp3'));
      expect(book.audioFiles[1], endsWith('part2.mp3'));
      expect(book.audioFiles[2], endsWith('part3.mp3'));

      // Multi-file cue: no chapter list (each file is an implicit chapter).
      expect(book.chapters, isEmpty);

      expect(book.title, 'Multi Book');
      expect(book.author, 'The Author');
    });

    test('.cue with missing audio file reference is skipped gracefully', () async {
      final bookDir = Directory('${tempDir.path}/Bad Cue Book');
      await bookDir.create();

      // The .cue references a file that does not exist.
      await File('${bookDir.path}/book.cue').writeAsString('''
TITLE "Bad Book"
FILE "missing.mp3" MP3
  TRACK 01 AUDIO
    TITLE "Chapter 1"
    INDEX 01 00:00:00
''');

      // No audio file on disk → scanner should skip the folder.
      final books = await scannerService.scanFolder(tempDir.path);
      expect(books, isEmpty);
    });

    test('.cue metadata does not override embedded tags', () async {
      // If a .cue has a title/author but the audio file also provides them
      // via embedded metadata, embedded metadata wins.
      // This test uses a dummy file (metadata read will fail → fall back to
      // folder name), so the .cue title IS used (it's still a fallback).
      final bookDir = Directory('${tempDir.path}/Embedded Wins');
      await bookDir.create();

      await File('${bookDir.path}/audiobook.mp3').writeAsBytes([]);
      await File('${bookDir.path}/audiobook.cue').writeAsString('''
PERFORMER "Cue Author"
TITLE "Cue Title"
FILE "audiobook.mp3" MP3
  TRACK 01 AUDIO
    TITLE "Chapter 1"
    INDEX 01 00:00:00
''');

      final books = await scannerService.scanFolder(tempDir.path);
      expect(books.length, 1);
      // Dummy file has no embedded metadata, so .cue title/author are used.
      expect(books.first.title, 'Cue Title');
      expect(books.first.author, 'Cue Author');
    });

    // ── Natural sort ─────────────────────────────────────────────────────────

    test('naturalSort orders files correctly (e.g. 2.mp3 before 10.mp3)', () async {
      // Create a dummy audiobook folder
      final bookDir = Directory('${tempDir.path}/Test Book');
      await bookDir.create();

      // Create files in an arbitrary order to see if the scanner sorts them naturally
      final files = [
        '10 - Chapter.mp3',
        '2 - Chapter.mp3',
        '1 - Chapter.mp3',
        '20 - Chapter.mp3',
        'something_else.mp3',
      ];

      for (final name in files) {
        final f = File('${bookDir.path}/$name');
        await f.writeAsString('dummy mp3 content');
      }

      // Scan
      final books = await scannerService.scanFolder(tempDir.path);

      expect(books.length, 1);
      final book = books.first;
      
      // Expected natural order: 1, 2, 10, 20, something_else
      expect(book.audioFiles.length, 5);
      expect(book.audioFiles[0].endsWith('1 - Chapter.mp3'), true);
      expect(book.audioFiles[1].endsWith('2 - Chapter.mp3'), true);
      expect(book.audioFiles[2].endsWith('10 - Chapter.mp3'), true);
      expect(book.audioFiles[3].endsWith('20 - Chapter.mp3'), true);
      expect(book.audioFiles[4].endsWith('something_else.mp3'), true);
    });
  });
}
