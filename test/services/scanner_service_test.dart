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
