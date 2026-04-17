# PRD-15 (P3): Guarantee timely cancellation of enrichment work

## Problem
`EnrichmentService.enqueueBooks()` runs a background loop gated by a `_cancelled` boolean. In-flight HTTP calls are not cancelled and the loop checks the flag only between iterations, so a cancel during a slow network request can hang for tens of seconds.

## Evidence
- `lib/services/enrichment_service.dart:82-108` — boolean cancel flag, no HTTP cancellation

## Proposed Solution
- Use an `http.Client` that can be closed on cancel to abort in-flight requests.
- Add a per-request timeout (e.g. 10s) so hung requests don't starve the queue.
- `dispose()` / `cancel()` closes the client and awaits the loop's exit with a short grace period.

## Acceptance Criteria
- [ ] Cancelling enrichment terminates the loop within 1s of any in-flight request completing or timing out
- [ ] No zombie HTTP clients after cancel
- [ ] Rescan after cancel starts cleanly

## Out of Scope
- Persistent queue across app restarts.
