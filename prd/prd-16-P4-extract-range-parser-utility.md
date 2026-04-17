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
