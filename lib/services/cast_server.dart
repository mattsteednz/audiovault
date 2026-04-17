import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Lightweight HTTP server that serves local audio files over the LAN
/// so a Google Cast device can stream them.
class CastServer {
  HttpServer? _server;

  /// Files currently being served, indexed by list position.
  List<String> _files = [];

  /// Optional cover image path served at `/cover`.
  String? _coverPath;

  /// Whether the server is running.
  bool get isRunning => _server != null;

  /// Start serving [audioFiles] and return the base URL
  /// (e.g. `http://192.168.1.5:8080`).
  ///
  /// Audio files are available at `<baseUrl>/audio/<index>`.
  /// Cover art (if provided) is at `<baseUrl>/cover`.
  Future<String> start(List<String> audioFiles, {String? coverPath}) async {
    _files = audioFiles;
    _coverPath = coverPath;

    final ip = await _localIp();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final port = _server!.port;
    debugPrint('[CastServer] Serving ${_files.length} file(s) on $ip:$port');

    _server!.listen(_handleRequest);
    return 'http://$ip:$port';
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _files = [];
    _coverPath = null;
  }

  // ── Request handling ──────────────────────────────────────────────────────

  void _handleRequest(HttpRequest request) async {
    try {
      final segments = request.uri.pathSegments;

      if (segments.length == 2 && segments[0] == 'audio') {
        final index = int.tryParse(segments[1]);
        if (index != null && index >= 0 && index < _files.length) {
          await _serveFile(request, _files[index]);
          return;
        }
      }

      if (segments.length == 1 && segments[0] == 'cover' && _coverPath != null) {
        await _serveFile(request, _coverPath!);
        return;
      }

      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
    } catch (e) {
      debugPrint('[CastServer] Error handling request: $e');
      try {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..close();
      } catch (_) {}
    }
  }

  /// Serve a local file, supporting HTTP range requests for seeking.
  Future<void> _serveFile(HttpRequest request, String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
      return;
    }

    final length = await file.length();
    final contentType = mimeType(filePath);
    final response = request.response;

    // Parse Range header for partial content (required for seeking).
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null) {
      final parsed = parseByteRange(rangeHeader, length);
      if (parsed == null) {
        // RFC 7233: invalid / unsatisfiable range → 416 with Content-Range: */<length>.
        response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
        await response.close();
        return;
      }
      final (start, end) = parsed;

      response
        ..statusCode = HttpStatus.partialContent
        ..headers.contentType = ContentType.parse(contentType)
        ..headers.contentLength = end - start + 1
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..headers.set(
            HttpHeaders.contentRangeHeader, 'bytes $start-$end/$length');

      await response.addStream(file.openRead(start, end + 1));
      await response.close();
    } else {
      response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.parse(contentType)
        ..headers.contentLength = length
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

      await response.addStream(file.openRead());
      await response.close();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String mimeType(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.mp3':
        return 'audio/mpeg';
      case '.m4a':
      case '.m4b':
      case '.mp4':
        return 'audio/mp4';
      case '.ogg':
      case '.opus':
        return 'audio/ogg';
      case '.flac':
        return 'audio/flac';
      case '.wav':
        return 'audio/wav';
      case '.aac':
        return 'audio/aac';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      default:
        return 'application/octet-stream';
    }
  }

  /// Parses an HTTP `Range` header into `(start, end)` inclusive byte offsets,
  /// or returns `null` if the header is malformed or unsatisfiable for a file
  /// of [length] bytes. Only single-range `bytes=start-end` and open-ended
  /// `bytes=start-` forms are supported.
  static (int, int)? parseByteRange(String header, int length) {
    if (!header.startsWith('bytes=')) return null;
    if (length <= 0) return null;
    final rangeStr = header.substring(6);
    // Multi-range not supported.
    if (rangeStr.contains(',')) return null;
    final parts = rangeStr.split('-');
    if (parts.length != 2) return null;
    final start = int.tryParse(parts[0]);
    if (start == null || start < 0) return null;
    final end = parts[1].isEmpty ? length - 1 : int.tryParse(parts[1]);
    if (end == null || end < start) return null;
    if (start >= length) return null;
    final clampedEnd = end >= length ? length - 1 : end;
    return (start, clampedEnd);
  }

  static Future<String> _localIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }
}
