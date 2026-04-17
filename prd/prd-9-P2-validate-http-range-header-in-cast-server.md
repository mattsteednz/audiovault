# PRD-9 (P2): Validate HTTP Range header in CastServer

## Problem
The local HTTP server used for Google Cast parses `Range` headers with bare `int.parse()` and passes the result directly to `file.openRead(start, end + 1)`. Malformed or out-of-bounds ranges cause unhandled exceptions; the server never returns the RFC-7233 `416 Range Not Satisfiable` response.

## Evidence
- `lib/services/cast_server.dart:93-96` — `int.parse(parts[0])`, `int.parse(parts[1])` with no try/catch and no bounds check

## Proposed Solution
- Wrap parse in `int.tryParse`; reject on null.
- Validate `0 <= start <= end < fileLength`.
- On invalid range, respond `416` with `Content-Range: bytes */<length>` per spec.
- On open-ended range (`bytes=500-`), clamp `end` to `length-1`.
- Add unit tests (see PRD-21) covering these branches.

## Acceptance Criteria
- [ ] Malformed Range header returns 416, not 500
- [ ] Open-ended ranges serve to EOF
- [ ] Existing cast playback continues to work on a real receiver
- [ ] Tests cover valid, open-ended, malformed, and out-of-bounds ranges

## Out of Scope
- Authenticated access (see PRD-11).
