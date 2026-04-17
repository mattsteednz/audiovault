# PRD-21 (P2): Tests for CastServer

## Problem
The local HTTP server for Cast has no tests. Range handling, MIME detection, 404s, and concurrent requests are all untested code paths despite being network-facing.

## Evidence
- `lib/services/cast_server.dart`
- No `test/services/cast_server_test.dart`

## Proposed Solution
- Bring server up on an ephemeral port in the test, issue real HTTP requests via `package:http` to `127.0.0.1`.
- Cover:
  - full file fetch (200 + correct `Content-Type`)
  - valid range → 206 + `Content-Range`
  - open-ended range → 206 to EOF
  - malformed range → 416 (see PRD-9)
  - unknown path → 404
  - two concurrent range requests against the same file succeed

## Acceptance Criteria
- [ ] New test file, all cases green on CI
- [ ] Tests clean up the server and temp files

## Out of Scope
- Cast receiver integration.
