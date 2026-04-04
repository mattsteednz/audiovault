# PRD 0: Metadata Enrichment from Open Library

## Feature Overview
Automatically enrich audiobook metadata (cover art and author) for books missing this information by querying Open Library. When books are scanned into the library, create a background queue to fetch missing covers and author info. Users can toggle this feature on/off in Settings.

## User Stories

**US-0.1:** As a user, I want the app to automatically fetch cover art for books without one so my library looks complete.

**US-0.2:** As a user, I want the app to fetch author information for books missing it.

**US-0.3:** As a user, I want to toggle whether the app fetches missing metadata so I can control background activity.

## Acceptance Criteria

- [ ] When books are scanned into the library, identify books missing cover art or author info
- [ ] On rescan, only queue books that are new or have not yet been enriched
- [ ] Skip re-enriching books that already have metadata from previous scans
- [ ] Create a queue of books needing enrichment
- [ ] Query Open Library API to fetch cover and author for each book in queue
- [ ] Match by ISBN first; fallback to title + author search
- [ ] Download and cache cover images locally
- [ ] Store fetched author info in book database
- [ ] Track enrichment status per book (enriched: true/false, last_enriched_date)
- [ ] Settings includes toggle: "Get missing covers/metadata" (enabled by default)
- [ ] If toggle is off, no Open Library requests are made
- [ ] Toggling setting on/off immediately starts or stops the enrichment queue
- [ ] Failed API requests don't block app or book import
- [ ] Gracefully handle missing results (book not found in Open Library)

## Technical Requirements

### Metadata Source:
- **Open Library API** – free, no authentication required
  - ISBN lookup: `GET /api/books?bibkeys=ISBN:{isbn}&jscmd=data&format=json`
  - Title + Author search: `GET /search.json?title={title}&author={author}&limit=1`
  - Response includes: title, author, cover image URL, publish date

### Implementation:
- On initial library scan: identify books with missing cover or author
- Create background queue of enrichment tasks
- Process queue asynchronously (no blocking UI)
- For each book: try ISBN first, then title + author
- Download cover image and store locally
- Store author name in book record
- Cache Open Library responses to avoid duplicate requests

### Image Handling:
- Download covers concurrently (max 3 simultaneous downloads)
- Cache locally in `{app_cache}/covers/{isbn_or_title_hash}.{jpg|png}`
- Store reference to cached image in book database
- Fallback to placeholder image if download fails

### Settings Integration:
- Add checkbox in Settings under "Library" section
- Label: "Get missing covers/metadata"
- Default: enabled (on)
- Toggling immediately affects queue processing

### Data Persistence:
- Store enrichment status per book: enriched (boolean), last_enriched_date (timestamp), last_attempted_date (timestamp)
- Cache Open Library responses locally to prevent repeat requests
- On rescan: only queue books that are new or have enriched=false
- If a book failed enrichment, retry on next rescan (but not more than once per day)
- Already enriched books are skipped entirely on rescan (no API calls)
- Persist user's toggle preference in app settings

## Design Considerations

- Enrichment happens silently in background
- No progress UI or notifications needed
- User controls feature via single Settings toggle
- No manual match selection or edit UI
- Simple, non-intrusive implementation

## Success Metrics

- 70%+ of books with ISBN successfully enriched
- 60%+ of books with title + author match successfully enriched
- Cover download success rate >85%
- Enrichment completes within 24 hours of library scan
- No performance impact on app startup or navigation

## Dependencies

- HTTP client library with timeout and retry logic
- Image caching library (local file storage)
- SQLite or equivalent for book database

## Related Features

- PRD 2 (Remote Repository) – imported books may also need enrichment
- PRD 5 (AZW3 Support) – AZW3 files may have embedded metadata to extract before enrichment
- Settings (PRD 10) – includes toggle for this feature

## Priority

**High** – Improves library appearance without user effort; quick win for UX.

## Implementation Notes

- Open Library has no rate limit, safe for bulk requests
- Start with ISBN matching; title + author is fallback
- Cache responses to avoid redundant requests
- Keep queue simple: process one book at a time or in small batches
- Handle network errors gracefully (mark as "retry later" instead of failing)
- Test with books that don't exist in Open Library (should not error)
