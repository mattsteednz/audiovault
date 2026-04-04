import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/audiobook.dart';

class EnrichmentService {
  static final EnrichmentService _instance = EnrichmentService._();
  EnrichmentService._();
  factory EnrichmentService() => _instance;

  static void _log(String msg) => debugPrint('[AudioVault:Enrichment] $msg');

  Database? _db;
  bool _processing = false;
  bool _cancelled = false;

  final _controller =
      StreamController<({String bookPath, String coverPath})>.broadcast();
  Stream<({String bookPath, String coverPath})> get onCoverFetched =>
      _controller.stream;

  Future<Database> get _database async {
    _db ??= await _openDb();
    return _db!;
  }

  Future<Database> _openDb() async {
    final dir = await getApplicationDocumentsDirectory();
    return openDatabase(
      '${dir.path}/audiovault_enrichment.db',
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE enrichment (
          book_path TEXT PRIMARY KEY,
          enriched INTEGER NOT NULL DEFAULT 0,
          cover_path TEXT,
          last_enriched_date INTEGER,
          last_attempted_date INTEGER
        )
      '''),
    );
  }

  Future<({bool enriched, String? coverPath, DateTime? lastAttempted})>
      getStatus(String bookPath) async {
    final db = await _database;
    final rows = await db.query(
      'enrichment',
      where: 'book_path = ?',
      whereArgs: [bookPath],
      limit: 1,
    );
    if (rows.isEmpty) {
      return (enriched: false, coverPath: null, lastAttempted: null);
    }
    final row = rows.first;
    final ms = row['last_attempted_date'] as int?;
    return (
      enriched: (row['enriched'] as int) == 1,
      coverPath: row['cover_path'] as String?,
      lastAttempted:
          ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
    );
  }

  /// Returns all previously enriched cover paths keyed by book path.
  Future<Map<String, String>> getAllEnrichedCovers() async {
    final db = await _database;
    final rows = await db.query(
      'enrichment',
      where: 'enriched = 1 AND cover_path IS NOT NULL',
    );
    return {
      for (final row in rows)
        row['book_path'] as String: row['cover_path'] as String,
    };
  }

  /// Processes [books] in the background, fetching covers for those missing one.
  Future<void> enqueueBooks(List<Audiobook> books) async {
    if (_processing) return;
    _processing = true;
    _cancelled = false;
    try {
      for (final book in books) {
        if (_cancelled) break;

        // Skip if the book already has a local cover.
        if (book.coverImagePath != null || book.coverImageBytes != null) {
          continue;
        }

        final status = await getStatus(book.path);
        if (status.enriched) continue;

        // Don't retry more than once per day.
        if (status.lastAttempted != null &&
            DateTime.now().difference(status.lastAttempted!).inHours < 24) {
          continue;
        }

        await _enrichBook(book);
      }
    } finally {
      _processing = false;
    }
  }

  /// Stop any in-progress enrichment queue.
  void cancel() => _cancelled = true;

  Future<void> _enrichBook(Audiobook book) async {
    await _recordAttempt(book.path);
    _log('Fetching cover for "${book.title}"');

    try {
      final coverPath = await _fetchCoverForTitle(book.title);
      if (coverPath != null) {
        await _recordSuccess(book.path, coverPath);
        _controller.add((bookPath: book.path, coverPath: coverPath));
        _log('Cover saved for "${book.title}"');
      } else {
        _log('No cover found for "${book.title}"');
      }
    } catch (e) {
      _log('Error enriching "${book.title}": $e');
    }
  }

  Future<String?> _fetchCoverForTitle(String title) async {
    final encodedTitle = Uri.encodeComponent(title);
    final searchResp = await http
        .get(Uri.parse(
            'https://openlibrary.org/search.json?title=$encodedTitle&limit=1'))
        .timeout(const Duration(seconds: 10));

    if (searchResp.statusCode != 200) return null;

    final data = jsonDecode(searchResp.body) as Map<String, dynamic>;
    final docs = data['docs'] as List?;
    if (docs == null || docs.isEmpty) return null;

    final coverId = docs.first['cover_i'];
    if (coverId == null) return null;

    return await _downloadCover(coverId.toString());
  }

  Future<String?> _downloadCover(String coverId) async {
    final coverResp = await http
        .get(Uri.parse(
            'https://covers.openlibrary.org/b/id/$coverId-L.jpg'))
        .timeout(const Duration(seconds: 15));

    if (coverResp.statusCode != 200) return null;

    final cacheDir = await getApplicationCacheDirectory();
    final coversDir = Directory('${cacheDir.path}/covers');
    await coversDir.create(recursive: true);

    final file = File('${coversDir.path}/$coverId.jpg');
    await file.writeAsBytes(coverResp.bodyBytes);
    return file.path;
  }

  Future<void> _recordAttempt(String bookPath) async {
    final db = await _database;
    await db.insert(
      'enrichment',
      {
        'book_path': bookPath,
        'enriched': 0,
        'last_attempted_date': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _recordSuccess(String bookPath, String coverPath) async {
    final db = await _database;
    await db.update(
      'enrichment',
      {
        'enriched': 1,
        'cover_path': coverPath,
        'last_enriched_date': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'book_path = ?',
      whereArgs: [bookPath],
    );
  }
}
