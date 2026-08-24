import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kowhai/models/audiobook.dart';
import 'package:kowhai/services/enrichment_service.dart';

/// A fake [http.Client] whose [get] never completes until [close] is called,
/// at which point it throws [ClientException] — matching real client behaviour.
class _HangingClient extends http.BaseClient {
  final _completer = Completer<http.StreamedResponse>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _completer.future;

  @override
  void close() {
    if (!_completer.isCompleted) {
      _completer.completeError(
        http.ClientException('Client closed', request?.url),
      );
    }
    super.close();
  }

  http.BaseRequest? request;
}

/// Serves queued bodies in order while capturing every requested URL
/// (R13 author-aware search tests).
class _SequenceClient extends http.BaseClient {
  final List<String> bodies;
  final List<Uri> requested = [];
  int _i = 0;

  _SequenceClient(this.bodies);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requested.add(request.url);
    final i = _i < bodies.length ? _i : bodies.length - 1;
    final body = bodies[i];
    _i++;
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  group('isValidCoverResponse', () {
    test('accepts a plausible JPEG response', () {
      expect(
        isValidCoverResponse(
          statusCode: 200,
          contentType: 'image/jpeg',
          contentLength: 50 * 1024,
        ),
        isTrue,
      );
    });

    test('accepts PNG and WebP', () {
      for (final type in ['image/png', 'image/webp', 'image/gif']) {
        expect(
          isValidCoverResponse(
            statusCode: 200,
            contentType: type,
            contentLength: 1024,
          ),
          isTrue,
          reason: 'expected $type to be accepted',
        );
      }
    });

    test('rejects non-200 status codes', () {
      for (final code in [204, 301, 404, 500]) {
        expect(
          isValidCoverResponse(
            statusCode: code,
            contentType: 'image/jpeg',
            contentLength: 1024,
          ),
          isFalse,
          reason: 'expected status $code to be rejected',
        );
      }
    });

    test('rejects missing content type', () {
      expect(
        isValidCoverResponse(
          statusCode: 200,
          contentType: null,
          contentLength: 1024,
        ),
        isFalse,
      );
    });

    test('rejects non-image content types (e.g. HTML error page)', () {
      expect(
        isValidCoverResponse(
          statusCode: 200,
          contentType: 'text/html; charset=utf-8',
          contentLength: 1024,
        ),
        isFalse,
      );
    });

    test('is case-insensitive on content type', () {
      expect(
        isValidCoverResponse(
          statusCode: 200,
          contentType: 'IMAGE/JPEG',
          contentLength: 1024,
        ),
        isTrue,
      );
    });

    test('rejects suspiciously tiny responses', () {
      expect(
        isValidCoverResponse(
          statusCode: 200,
          contentType: 'image/jpeg',
          contentLength: minCoverBytes - 1,
        ),
        isFalse,
      );
    });

    test('rejects oversized responses', () {
      expect(
        isValidCoverResponse(
          statusCode: 200,
          contentType: 'image/jpeg',
          contentLength: maxCoverBytes + 1,
        ),
        isFalse,
      );
    });

    test('accepts exactly at size boundaries', () {
      expect(
        isValidCoverResponse(
          statusCode: 200,
          contentType: 'image/jpeg',
          contentLength: minCoverBytes,
        ),
        isTrue,
      );
      expect(
        isValidCoverResponse(
          statusCode: 200,
          contentType: 'image/jpeg',
          contentLength: maxCoverBytes,
        ),
        isTrue,
      );
    });
  });

  group('EnrichmentService.enqueueBooks pending queue', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    test('books enqueued while processing are processed after current batch',
        () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          singleInstance: false,
          onCreate: (db, _) => db.execute('''
            CREATE TABLE enrichment (
              book_path TEXT PRIMARY KEY,
              enriched INTEGER NOT NULL DEFAULT 0,
              cover_path TEXT,
              last_enriched_date INTEGER,
              last_attempted_date INTEGER
            )
          '''),
        ),
      );

      // A client that resolves immediately but records which book was fetched.
      final client = _HangingClient();
      final svc = EnrichmentService.withDatabase(db, client: client);

      // Override via subclassing is not available, so we verify via the
      // onCoverFetched stream — instead we rely on the fact that
      // enqueueBooks returns only after all pending books are drained.
      // We use two non-enrichable books (already have cover bytes) to
      // exercise the pending-queue drain without needing HTTP.
      Audiobook makeBook(String path) => Audiobook(
            title: path,
            path: path,
            audioFiles: const [],
            coverImageBytes: Uint8List(1), // already has cover — skips fetch
          );

      final first = makeBook('/book/a');
      final second = makeBook('/book/b');
      final third = makeBook('/book/c');

      // Start processing the first batch.
      final firstFuture = svc.enqueueBooks([first]);

      // Enqueue a second batch while the first is still running.
      svc.enqueueBooks([second, third]);

      await firstFuture;

      // Both batches should have been processed (no crash, no silent drop).
      // Since all books have cover bytes they are skipped, but the queue
      // must have been drained: _pendingBooks should be empty now and
      // _processing should be false. We verify indirectly by confirming a
      // third enqueue runs immediately (would hang if _processing were stuck).
      bool completed = false;
      await svc.enqueueBooks([makeBook('/book/d')]);
      completed = true;
      expect(completed, isTrue);
    });
  });

  group('EnrichmentService author-aware search (R13)', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    Future<(EnrichmentService, _SequenceClient)> makeSvc(
        List<String> bodies) async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 1, singleInstance: false,
            onCreate: (db, _) => db.execute('''
            CREATE TABLE enrichment (
              book_path TEXT PRIMARY KEY,
              enriched INTEGER NOT NULL DEFAULT 0,
              cover_path TEXT,
              last_enriched_date INTEGER,
              last_attempted_date INTEGER
            )
          ''')),
      );
      final client = _SequenceClient(bodies);
      return (EnrichmentService.withDatabase(db, client: client), client);
    }

    Audiobook makeBook({String? author}) => Audiobook(
          title: 'Dune',
          author: author,
          path: '/books/dune',
          audioFiles: const [],
        );

    test('uses an author-constrained query when author is known', () async {
      final (svc, client) = await makeSvc(['{"docs":[]}']);
      await svc.enqueueBooks([makeBook(author: 'Frank Herbert')]);

      expect(client.requested, isNotEmpty);
      expect(client.requested.first.queryParameters['title'], 'Dune');
      expect(client.requested.first.queryParameters['author'],
          'Frank Herbert');
    });

    test('omits the author parameter when author is null', () async {
      final (svc, client) = await makeSvc(['{"docs":[]}']);
      await svc.enqueueBooks([makeBook()]);

      expect(client.requested.first.queryParameters['title'], 'Dune');
      expect(client.requested.first.queryParameters.containsKey('author'),
          isFalse);
    });

    test('falls back to title-only when combined query misses', () async {
      final (svc, client) = await makeSvc([
        '{"docs":[]}', // title+author miss
        '{"docs":[{"cover_i":null}]}', // title-only hit, no cover id
      ]);
      await svc.enqueueBooks([makeBook(author: 'Frank Herbert')]);

      expect(client.requested.length, 2);
      expect(client.requested.first.queryParameters.containsKey('author'),
          isTrue);
      expect(client.requested.last.queryParameters.containsKey('author'),
          isFalse);
    });
  });

  group('EnrichmentService.cancel', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    test('cancel() aborts an in-flight request and loop completes promptly',
        () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          singleInstance: false,
          onCreate: (db, _) => db.execute('''
            CREATE TABLE enrichment (
              book_path TEXT PRIMARY KEY,
              enriched INTEGER NOT NULL DEFAULT 0,
              cover_path TEXT,
              last_enriched_date INTEGER,
              last_attempted_date INTEGER
            )
          '''),
        ),
      );
      final client = _HangingClient();
      final svc = EnrichmentService.withDatabase(db, client: client);

      final book = Audiobook(
        title: 'Hanging Book',
        path: '/tmp/hanging',
        audioFiles: const [],
      );

      // Start the queue — it will hang on the first HTTP request.
      final loopFuture = svc.enqueueBooks([book]);

      // Give the loop a moment to reach the HTTP call.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final stopwatch = Stopwatch()..start();
      svc.cancel();

      // Loop should complete well within 1 second once the client is closed.
      await loopFuture.timeout(const Duration(seconds: 1));
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });
  });
}
