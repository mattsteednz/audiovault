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

## Implementation Plan
1. In `EnrichmentService`, replace ad-hoc HTTP calls with a field `http.Client _client = http.Client();` reused across requests.
2. Wrap each request in `.timeout(const Duration(seconds: 10))` and catch `TimeoutException` as a non-fatal skip.
3. Add `void cancel() { _cancelled = true; _client.close(); }` — closing the client aborts in-flight requests, which surface as `ClientException` in the loop and break out.
4. Ensure the background loop checks `_cancelled` immediately after each `await` so it exits within one iteration.
5. On `dispose()`, call `cancel()` and `await _loopCompleter.future.timeout(Duration(seconds: 1), onTimeout: () {})`.
6. On rescan, instantiate a fresh `http.Client` (create in `enqueueBooks` if disposed).
7. Add test with a mock client that hangs forever; call `cancel()` and assert the loop future completes in < 1s.

## Files Impacted
- `lib/services/enrichment_service.dart` (client lifecycle + cancel)
- `test/services/enrichment_service_test.dart` (new cancel test)
