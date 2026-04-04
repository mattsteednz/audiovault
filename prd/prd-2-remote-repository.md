# PRD 2: Remote Repository / Public Audiobook Loading (XML/HTTP)

## Feature Overview
Allow users to load audiobooks from external XML-based repositories, supporting HTTP sources and public audiobook catalogs (e.g., Project Gutenberg, public domain feeds). Enable discovering, fetching metadata, and importing books from remote sources.

## User Stories

**US-2.1:** As a user, I want to add a remote audiobook catalog (XML feed URL) to the app so I can browse and download books from Project Gutenberg.

**US-2.2:** As a user, I want to search the remote catalog and see book title, author, duration, and cover art before downloading.

**US-2.3:** As a user, I want to queue multiple books for download and manage download priority.

**US-2.4:** As a user, I want to import audiobooks that are already in my library and have metadata synced from the remote source.

## Acceptance Criteria

- [ ] App supports adding custom XML feed URLs (feed validation required)
- [ ] XML parser correctly extracts title, author, duration, cover image, and audio file URL
- [ ] Remote catalog displays at least 50 books per page with pagination
- [ ] Search/filter by title and author works with <500ms latency
- [ ] Download manager shows progress, ETA, and allows pause/resume
- [ ] Downloaded books are automatically added to library
- [ ] Metadata updates when re-syncing remote feed (title, cover, duration changes)
- [ ] Graceful handling of invalid/malformed XML feeds (error message to user)
- [ ] Supports HTTP and HTTPS (no insecure HTTP for auth-required feeds)

## Technical Requirements

### XML Parser:
Use standard XML DOM parsing (validate against schema if provided)

### Feed format support:
- OPDS (Open Publication Distribution System) - primary format
- Atom/RSS with audiobook extensions
- Custom XML with configurable field mapping

### HTTP client:
Support redirects, resumable downloads, range requests

### Storage:
Cache feed metadata locally; versioning for incremental updates

### Network:
Timeout handling (30s for feed fetch, adaptive for large downloads)

### Validation:
Check for duplicate imports; prevent circular feed references

## Design Considerations

- Display "Add Catalog" UI with URL input and validation feedback
- Show feed source name/author in book cards (e.g., "Project Gutenberg")
- Implement breadcrumb navigation (feed → book list → book detail)
- Provide "Import All" option for smaller feeds; warn on large feeds (>500 books)
- Show download status per book (queued, downloading, complete)

## Success Metrics

- 40%+ users add at least one remote catalog
- Average remote catalog has >100 books imported per user
- <5% feed parsing failures
- Download completion rate >85% (not abandoned)

## Dependencies

- HTTP/HTTPS library with resumable download support
- XML parsing library
- Optional: OPDS server for testing

## Priority
**High** - Core feature for discoverability and user acquisition
