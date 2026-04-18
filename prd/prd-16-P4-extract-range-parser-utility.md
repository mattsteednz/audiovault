# PRD-16 (P4): Extract a reusable HTTP Range parser utility

## Problem
Range-header parsing lives inline in `CastServer`. If another local-server feature appears (e.g. cover proxy, debug server), the parsing will be duplicated or re-implemented badly.

## Evidence
- `lib/services/cast_server.dart:93-96` — inline parse

## Proposed Solution
- Create `lib/services/http/range_header.dart` with `ByteRange.parse(String header, int fileLength)` returning `ByteRange?` (null on invalid).
- Replace the inline parse in `CastServer`.
- Cover the util with unit tests (valid, open-ended, invalid, overflow).

## Acceptance Criteria
- [ ] `CastServer` imports and uses the new util
- [ ] Util has exhaustive unit tests
- [ ] No behavioural change

## Out of Scope
- Multi-range responses.

## Implementation Plan
1. Create `lib/services/http/range_header.dart` containing:
   ```dart
   class ByteRange {
     final int start;
     final int end; // inclusive
     const ByteRange(this.start, this.end);
     int get length => end - start + 1;
     static ByteRange? parse(String? header, int fileLength) { ... }
   }
   ```
2. Parser rules: accept `bytes=<start>-<end>`, `bytes=<start>-` (open-ended → end = fileLength-1), `bytes=-<suffix>` (last N bytes). Reject invalid / multi-range. Clamp overflow to fileLength-1. Return null on any parse failure.
3. Replace inline parse in `lib/services/cast_server.dart:93-96` with `ByteRange.parse(req.headers.value('range'), fileLength)`.
4. Add `test/services/http/range_header_test.dart` with cases: full range, open-ended, suffix, invalid (`bytes=abc`), overflow (`bytes=0-999999999`), missing header, multi-range (`bytes=0-10,20-30` → null).
5. Confirm Cast streaming still works end-to-end on device (single seek + resume).

## Files Impacted
- `lib/services/http/range_header.dart` (new)
- `lib/services/cast_server.dart` (use util)
- `test/services/http/range_header_test.dart` (new)
