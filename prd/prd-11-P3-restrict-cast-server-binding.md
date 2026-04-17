# PRD-11 (P3): Restrict CastServer network exposure

## Problem
The Cast HTTP server binds to `InternetAddress.anyIPv4` with no authentication. Any device on the same LAN can enumerate and download the user's audio and cover files while casting is active.

## Evidence
- `lib/services/cast_server.dart:29` — `HttpServer.bind(InternetAddress.anyIPv4, 0)`
- No Authorization header check in request handler

## Proposed Solution
- Generate a random per-session path token; include it in URLs handed to the Cast receiver.
- Reject requests whose path does not contain the token with `404`.
- Only start server while a Cast session is active; stop immediately on disconnect.
- Document LAN-only assumption in README.

## Acceptance Criteria
- [ ] Requests without the session token return 404
- [ ] Server is stopped when no Cast session is active
- [ ] Cast playback still works end-to-end on a real receiver

## Out of Scope
- TLS on the local server (receivers typically don't trust self-signed certs).
