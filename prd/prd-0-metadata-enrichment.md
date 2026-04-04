# PRD 0: Metadata Enrichment & Match Resolution

## Feature Overview
Automatically enrich audiobook metadata (cover art, author bio, description, publisher, publication date) from open metadata sources using ISBN, title, and author. Implement intelligent fuzzy matching and user-friendly UI for resolving ambiguous matches when multiple editions are found.

## User Stories

**US-0.1:** As a user, I want the app to automatically fetch a cover image, description, and author info for a book I import so I don't have to manually enter metadata.

**US-0.2:** As a user, I want to see multiple matching editions when I import a book so I can select the correct one (e.g., "2019 Audiobook Edition" vs. "2015 eBook Edition").

**US-0.3:** As a user, I want the app to show confidence scores or edition details (narrator, publisher, release date) to help me pick the right match.

**US-0.4:** As a user, I want to manually override or edit metadata if the auto-match is incorrect so my library stays accurate.

## Acceptance Criteria

- [ ] Metadata is fetched automatically on book import if ISBN, title, or ASIN is available
- [ ] Cover art is downloaded and cached (max 10MB per image; resize to 3 sizes: small, medium, large)
- [ ] App returns top 5 matches when multiple editions are found; display title, author, narrator, publisher, year, edition type
- [ ] Matches are ranked by confidence score (ISBN exact match > title+author fuzzy match > title-only match)
- [ ] User selection UI shows covers side-by-side with key differentiators (edition, narrator, publish date)
- [ ] Selected metadata is persisted; user can edit any field post-selection
- [ ] Fallback gracefully if no match found: allow manual entry of title/author/cover
- [ ] API failures (timeouts, rate limits) don't block book import; mark as "pending enrichment"
- [ ] Bulk import: batch queries to APIs to avoid rate limits; process <50ms per book average

## Technical Requirements

### Metadata sources (fallback chain):
1. **Open Library API** (primary) – free, no key, ISBN/title/author search
   - Returns title, author, cover, publish date, publisher, description
   - Endpoint: `GET /api/books?bibkeys=ISBN:{isbn}&jscmd=data&format=json`
2. **Google Books API** (secondary) – free tier, API key required
   - Returns description, cover, author, publication date, ISBN variants
   - Rate limit: 100 queries/day free; upgrade for more
3. **Internet Archive API** (tertiary) – free, backup for descriptions
   - Returns metadata and full-text preview
4. **OCLC Classify** (utility) – free, no key, for ISBN validation and cross-references

### Fuzzy matching:
- Normalize strings (lowercase, remove punctuation, extra spaces)
- Use Levenshtein distance or similar for title/author matching
- ISBN matching: exact match only (ISBN-10 and ISBN-13 variants)
- Scoring: ISBN match (score: 100), title+author match (50-90), title-only (30-50)

### Deduplication:
- Deduplicate by ISBN-13 > ISBN-10 > OCLC number > (title + author + year)
- Return top 5 unique results; filter out reprints/editions below confidence threshold (40%)

### Image handling:
- Download covers concurrently (max 3 simultaneous downloads)
- Cache locally in `{app_cache}/covers/{isbn}.{jpg|png}`
- Resize to S (200px), M (400px), L (600px) on import
- Fallback to placeholder if download fails

### Rate limiting & caching:
- Cache metadata for 30 days; check for updates weekly
- Open Library: no rate limit documented; safe for bulk queries
- Google Books: 100/day free tier (batch requests)
- Implement exponential backoff for 429/503 responses
- Store all metadata locally to avoid repeat queries

## Design Considerations

### Match selection UI:
- Show cover, title, author, narrator, publisher, release year for each match
- Highlight differences between editions (e.g., "Narrated by X" vs. "Narrated by Y")
- Display confidence score as visual indicator (e.g., "95% match")
- "Skip enrichment" option to proceed without metadata
- "Manual entry" option for non-ISBN lookups

### Edit metadata UI:
- Inline edit fields post-selection (title, author, narrator, publisher, description)
- Allow image upload/replacement for cover
- Show data source attribution (e.g., "Cover from Open Library")

### Bulk import:
- Progress indicator showing "Enriching X of Y books..."
- Allow pause/resume
- Show summary: "Successfully enriched 45, skipped 3, manual entry needed for 2"

## Success Metrics

- 80%+ of imported books successfully enriched with ≥1 source
- <5% of matches require manual correction (user acceptance rate >95%)
- Average metadata fetch time <2s per book
- Cover download success rate >90%
- Users skip manual entry 70%+ of the time (indicates good auto-match)

## Dependencies

- HTTP client library with timeout and retry logic
- Image processing library (resize, format conversion)
- Fuzzy string matching library (Levenshtein, tf-idf, or similar)
- ISBN validation library (for checksum verification)
- SQLite or equivalent for metadata caching

## API Endpoints (Reference)

**Open Library:**
```
GET /api/books?bibkeys=ISBN:{isbn}&jscmd=data&format=json
GET /search.json?title={title}&author={author}&limit=10
GET /isbn/{isbn}.json
```

**Google Books:**
```
GET /books/v1/volumes?q=isbn:{isbn}&key={API_KEY}
GET /books/v1/volumes?q={title}+{author}&key={API_KEY}
```

**Internet Archive:**
```
GET /metadata/{id}
GET /advancedsearch.php?q=isbn:{isbn}&output=json
```

## Priority
**High** – Core UX feature; enables quick library builds
