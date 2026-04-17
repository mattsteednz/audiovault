# PRD-10 (P2): Enforce HTTPS and validate responses for Open Library enrichment

## Problem
Metadata and cover fetches from Open Library use unencrypted endpoints (or rely on default-scheme URLs). A MITM on an untrusted network could replace cover bytes with malicious content saved to disk as a JPEG. Even public metadata benefits from TLS integrity.

## Evidence
- `lib/services/enrichment_service.dart:141-142` — metadata GET
- `lib/services/enrichment_service.dart:159-160` — cover bytes GET
- `lib/services/enrichment_service.dart:165-171` — bytes written to disk without content-type/length validation

## Proposed Solution
- Force `https://` scheme for both hosts.
- Check `response.statusCode == 200`, `Content-Type` starts with `image/`, and bytes are a plausible size (<10 MB) before writing.
- Skip enrichment silently on validation failure; do not cache a bad cover.

## Acceptance Criteria
- [ ] All Open Library URLs are https
- [ ] Cover download rejects non-image responses
- [ ] Oversized responses rejected with a debug log
- [ ] Existing enrichment still populates covers/titles on happy path

## Out of Scope
- Certificate pinning.
