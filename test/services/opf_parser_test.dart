import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kowhai/services/opf_parser.dart';
import 'package:kowhai/services/scanner_service.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _fullOpf = '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>The Way of Kings</dc:title>
    <dc:creator opf:role="aut">Brandon Sanderson</dc:creator>
    <dc:creator opf:role="nrt">Michael Kramer</dc:creator>
    <dc:description>A sweeping epic fantasy.</dc:description>
    <dc:publisher>Tor Books</dc:publisher>
    <dc:language>en</dc:language>
    <dc:date>2010-08-31</dc:date>
    <meta name="calibre:series" content="The Stormlight Archive"/>
    <meta name="calibre:series_index" content="1.0"/>
  </metadata>
</package>''';

const _partialOpf = '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>Unknown Book</dc:title>
    <dc:creator opf:role="aut">Some Author</dc:creator>
  </metadata>
</package>''';

const _noRoleOpf = '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>My Book</dc:title>
    <dc:creator>Default Author</dc:creator>
  </metadata>
</package>''';

const _malformedOpf = 'this is not xml <<< !!!';

/// Dublin Core declared as the DEFAULT namespace (no `dc:` prefixes) — the
/// layout produced by some minimal EPUB-derived OPF writers.
const _defaultNamespaceOpf = '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns="http://purl.org/dc/elements/1.1/">
    <title>Default Namespace Book</title>
    <creator>Default Ns Author</creator>
    <creator role="nrt">Default Ns Narrator</creator>
    <description>Desc</description>
    <publisher>Pub</publisher>
    <language>en</language>
    <date>1999-01-01</date>
    <meta name="calibre:series" content="Series X"/>
    <meta name="calibre:series_index" content="2.0"/>
  </metadata>
</package>''';

const _emptyMetadataOpf = '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"/>
</package>''';

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('parseOpf', () {
    test('full OPF populates all fields', () {
      final opf = parseOpf(_fullOpf);
      expect(opf.title, 'The Way of Kings');
      expect(opf.author, 'Brandon Sanderson');
      expect(opf.narrator, 'Michael Kramer');
      expect(opf.description, 'A sweeping epic fantasy.');
      expect(opf.publisher, 'Tor Books');
      expect(opf.language, 'en');
      expect(opf.releaseDate, '2010');
      expect(opf.series, 'The Stormlight Archive');
      expect(opf.seriesIndex, 1);
    });

    test('partial OPF leaves missing fields null', () {
      final opf = parseOpf(_partialOpf);
      expect(opf.title, 'Unknown Book');
      expect(opf.author, 'Some Author');
      expect(opf.narrator, isNull);
      expect(opf.description, isNull);
      expect(opf.publisher, isNull);
      expect(opf.language, isNull);
      expect(opf.releaseDate, isNull);
      expect(opf.series, isNull);
      expect(opf.seriesIndex, isNull);
    });

    test('creator with no role defaults to author', () {
      final opf = parseOpf(_noRoleOpf);
      expect(opf.author, 'Default Author');
      expect(opf.narrator, isNull);
    });

    test('default-namespace OPF (no dc: prefixes) populates all fields', () {
      final opf = parseOpf(_defaultNamespaceOpf);
      expect(opf.title, 'Default Namespace Book');
      expect(opf.author, 'Default Ns Author');
      expect(opf.narrator, 'Default Ns Narrator');
      expect(opf.description, 'Desc');
      expect(opf.publisher, 'Pub');
      expect(opf.language, 'en');
      expect(opf.releaseDate, '1999');
      expect(opf.series, 'Series X');
      expect(opf.seriesIndex, 2);
    });

    test('malformed XML returns empty OpfMetadata without throwing', () {
      final opf = parseOpf(_malformedOpf);
      expect(opf.isEmpty, isTrue);
    });

    test('empty metadata element returns empty OpfMetadata', () {
      final opf = parseOpf(_emptyMetadataOpf);
      expect(opf.isEmpty, isTrue);
    });

    test('series_index float is rounded to int', () {
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>T</dc:title>
    <meta name="calibre:series" content="S"/>
    <meta name="calibre:series_index" content="2.0"/>
  </metadata>
</package>''';
      expect(parseOpf(xml).seriesIndex, 2);
    });

    test('multiple creators: first aut and first nrt are used', () {
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>T</dc:title>
    <dc:creator opf:role="aut">Author One</dc:creator>
    <dc:creator opf:role="aut">Author Two</dc:creator>
    <dc:creator opf:role="nrt">Narrator One</dc:creator>
    <dc:creator opf:role="nrt">Narrator Two</dc:creator>
  </metadata>
</package>''';
      final opf = parseOpf(xml);
      expect(opf.author, 'Author One');
      expect(opf.narrator, 'Narrator One');
    });

    test('dc:date with only year still extracts year', () {
      const xml = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>T</dc:title>
    <dc:date>2023</dc:date>
  </metadata>
</package>''';
      expect(parseOpf(xml).releaseDate, '2023');
    });
  });

  group('ScannerService OPF integration', () {
    late Directory tempDir;
    late ScannerService scanner;

    setUp(() async {
      scanner = ScannerService();
      tempDir = await Directory.systemTemp.createTemp('kowhai_opf_test_');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('scanner uses OPF author and narrator over audio-tag fallback',
        () async {
      final bookDir = Directory('${tempDir.path}/My Book');
      await bookDir.create();
      await File('${bookDir.path}/chapter.mp3').writeAsBytes([]);
      await File('${bookDir.path}/metadata.opf').writeAsString(_fullOpf);

      final books = await scanner.scanFolder(tempDir.path);
      expect(books.length, 1);
      expect(books.first.title, 'The Way of Kings');
      expect(books.first.author, 'Brandon Sanderson');
      expect(books.first.narrator, 'Michael Kramer');
      expect(books.first.series, 'The Stormlight Archive');
      expect(books.first.seriesIndex, 1);
      expect(books.first.publisher, 'Tor Books');
      expect(books.first.language, 'en');
    });

    test('scanner works normally when no OPF is present', () async {
      final bookDir = Directory('${tempDir.path}/Plain Book');
      await bookDir.create();
      await File('${bookDir.path}/chapter.mp3').writeAsBytes([]);

      final books = await scanner.scanFolder(tempDir.path);
      expect(books.length, 1);
      expect(books.first.title, 'Plain Book');
      expect(books.first.series, isNull);
      expect(books.first.seriesIndex, isNull);
    });
  });
}
