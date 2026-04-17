import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault/services/enrichment_service.dart';

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
}
