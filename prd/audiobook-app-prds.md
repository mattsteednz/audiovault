# Audiobook App - Product Requirements Documents

---

## PRD 0: Metadata Enrichment & Match Resolution

### Feature Overview
Automatically enrich audiobook metadata (cover art, author bio, description, publisher, publication date) from open metadata sources using ISBN, title, and author. Implement intelligent fuzzy matching and user-friendly UI for resolving ambiguous matches when multiple editions are found.

### User Stories

**US-0.1:** As a user, I want the app to automatically fetch a cover image, description, and author info for a book I import so I don't have to manually enter metadata.

**US-0.2:** As a user, I want to see multiple matching editions when I import a book so I can select the correct one (e.g., "2019 Audiobook Edition" vs. "2015 eBook Edition").

**US-0.3:** As a user, I want the app to show confidence scores or edition details (narrator, publisher, release date) to help me pick the right match.

**US-0.4:** As a user, I want to manually override or edit metadata if the auto-match is incorrect so my library stays accurate.

### Acceptance Criteria

- [ ] Metadata is fetched automatically on book import if ISBN, title, or ASIN is available
- [ ] Cover art is downloaded and cached (max 10MB per image; resize to 3 sizes: small, medium, large)
- [ ] App returns top 5 matches when multiple editions are found; display title, author, narrator, publisher, year, edition type
- [ ] Matches are ranked by confidence score (ISBN exact match > title+author fuzzy match > title-only match)
- [ ] User selection UI shows covers side-by-side with key differentiators (edition, narrator, publish date)
- [ ] Selected metadata is persisted; user can edit any field post-selection
- [ ] Fallback gracefully if no match found: allow manual entry of title/author/cover
- [ ] API failures (timeouts, rate limits) don't block book import; mark as "pending enrichment"
- [ ] Bulk import: batch queries to APIs to avoid rate limits; process <50ms per book average

### Technical Requirements

- **Metadata sources (fallback chain):**
  1. **Open Library API** (primary) – free, no key, ISBN/title/author search
     - Returns title, author, cover, publish date, publisher, description
     - Endpoint: `GET /api/books?bibkeys=ISBN:{isbn}&jscmd=data&format=json`
  2. **Google Books API** (secondary) – free tier, API key required
     - Returns description, cover, author, publication date, ISBN variants
     - Rate limit: 100 queries/day free; upgrade for more
  3. **Internet Archive API** (tertiary) – free, backup for descriptions
     - Returns metadata and full-text preview
  4. **OCLC Classify** (utility) – free, no key, for ISBN validation and cross-references

- **Fuzzy matching:**
  - Normalize strings (lowercase, remove punctuation, extra spaces)
  - Use Levenshtein distance or similar for title/author matching
  - ISBN matching: exact match only (ISBN-10 and ISBN-13 variants)
  - Scoring: ISBN match (score: 100), title+author match (50-90), title-only (30-50)

- **Deduplication:**
  - Deduplicate by ISBN-13 > ISBN-10 > OCLC number > (title + author + year)
  - Return top 5 unique results; filter out reprints/editions below confidence threshold (40%)

- **Image handling:**
  - Download covers concurrently (max 3 simultaneous downloads)
  - Cache locally in `{app_cache}/covers/{isbn}.{jpg|png}`
  - Resize to S (200px), M (400px), L (600px) on import
  - Fallback to placeholder if download fails

- **Rate limiting & caching:**
  - Cache metadata for 30 days; check for updates weekly
  - Open Library: no rate limit documented; safe for bulk queries
  - Google Books: 100/day free tier (batch requests)
  - Implement exponential backoff for 429/503 responses
  - Store all metadata locally to avoid repeat queries

### Design Considerations

- **Match selection UI:**
  - Show cover, title, author, narrator, publisher, release year for each match
  - Highlight differences between editions (e.g., "Narrated by X" vs. "Narrated by Y")
  - Display confidence score as visual indicator (e.g., "95% match")
  - "Skip enrichment" option to proceed without metadata
  - "Manual entry" option for non-ISBN lookups

- **Edit metadata UI:**
  - Inline edit fields post-selection (title, author, narrator, publisher, description)
  - Allow image upload/replacement for cover
  - Show data source attribution (e.g., "Cover from Open Library")

- **Bulk import:**
  - Progress indicator showing "Enriching X of Y books..."
  - Allow pause/resume
  - Show summary: "Successfully enriched 45, skipped 3, manual entry needed for 2"

### Success Metrics

- 80%+ of imported books successfully enriched with ≥1 source
- <5% of matches require manual correction (user acceptance rate >95%)
- Average metadata fetch time <2s per book
- Cover download success rate >90%
- Users skip manual entry 70%+ of the time (indicates good auto-match)

### Dependencies

- HTTP client library with timeout and retry logic
- Image processing library (resize, format conversion)
- Fuzzy string matching library (Levenshtein, tf-idf, or similar)
- ISBN validation library (for checksum verification)
- SQLite or equivalent for metadata caching

### API Endpoints (Reference)

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

### Priority
**High** – Core UX feature; enables quick library builds

---

## PRD 1: Google Cast Support for Local Listening

### Feature Overview
Enable users to cast audiobook playback to Google Cast–compatible devices (e.g., Chromecast, Google Home, smart speakers) while maintaining synchronized playback controls and audio output from remote devices.

### User Stories

**US-1.1:** As a user, I want to cast my current audiobook to a Chromecast device in my living room so I can listen to the book on my home speaker system.

**US-1.2:** As a user, I want to see available Cast devices listed in the app UI so I can select where to send audio.

**US-1.3:** As a user, I want to pause, play, and skip forward/backward on the Cast device from the app UI so I maintain playback control.

**US-1.4:** As a user, I want the Cast session to maintain my current position when I disconnect so I can resume from the same place later.

### Acceptance Criteria

- [ ] Cast device discovery works on local network (mDNS)
- [ ] App displays available Cast devices in a dedicated UI panel/dropdown
- [ ] User can select a Cast device and initiate playback routing within 2 seconds
- [ ] Audio streams to Cast device without app audio playback
- [ ] Playback controls (play, pause, seek, volume) are responsive (<500ms latency)
- [ ] Current position is persisted when Cast session ends
- [ ] Graceful error handling if device becomes unreachable (retry logic + user notification)
- [ ] Supports standard Google Cast API protocols

### Technical Requirements

- **Implement Google Cast SDK** for Android/iOS
- **Network requirements:** Local network access; mDNS service discovery
- **Protocol:** Cast Control Protocol v2 (CCP)
- **Playback:** Stream audio via RSTP or HTTP (must support AZW3 decoded audio format)
- **Session management:** Store Cast device UID and resume capability
- **Error handling:** Detect network disconnection, device unavailability, casting errors
- **Permissions:** Network access, local service discovery permissions

### Design Considerations

- Display Cast icon in playback controls only when devices are detected
- Show device selection UI in-player (not modal overlay)
- Indicate active Cast device with visual indicator (blue icon or name display)
- Provide reconnect option if Cast session drops
- Disable Cast UI if playback source is incompatible (e.g., DRM content)

### Success Metrics

- 60%+ of users with Cast devices attempt casting within first month
- <2% error rate on Cast session initiation
- <1% of sessions drop unexpectedly after 5 minutes
- Average Cast session duration >15 minutes

### Dependencies

- Google Cast SDK (Android: libcast, iOS: GoogleCastSDK)
- Network layer: mDNS/Bonjour support
- Audio decoding pipeline (must produce raw PCM for streaming)

### Priority
**High** - Differentiates product, enables multi-room listening

---

## PRD 2: Remote Repository / Public Audiobook Loading (XML/HTTP)

### Feature Overview
Allow users to load audiobooks from external XML-based repositories, supporting HTTP sources and public audiobook catalogs (e.g., Project Gutenberg, public domain feeds). Enable discovering, fetching metadata, and importing books from remote sources.

### User Stories

**US-2.1:** As a user, I want to add a remote audiobook catalog (XML feed URL) to the app so I can browse and download books from Project Gutenberg.

**US-2.2:** As a user, I want to search the remote catalog and see book title, author, duration, and cover art before downloading.

**US-2.3:** As a user, I want to queue multiple books for download and manage download priority.

**US-2.4:** As a user, I want to import audiobooks that are already in my library and have metadata synced from the remote source.

### Acceptance Criteria

- [ ] App supports adding custom XML feed URLs (feed validation required)
- [ ] XML parser correctly extracts title, author, duration, cover image, and audio file URL
- [ ] Remote catalog displays at least 50 books per page with pagination
- [ ] Search/filter by title and author works with <500ms latency
- [ ] Download manager shows progress, ETA, and allows pause/resume
- [ ] Downloaded books are automatically added to library
- [ ] Metadata updates when re-syncing remote feed (title, cover, duration changes)
- [ ] Graceful handling of invalid/malformed XML feeds (error message to user)
- [ ] Supports HTTP and HTTPS (no insecure HTTP for auth-required feeds)

### Technical Requirements

- **XML Parser:** Use standard XML DOM parsing (validate against schema if provided)
- **Feed format support:**
  - OPDS (Open Publication Distribution System) - primary format
  - Atom/RSS with audiobook extensions
  - Custom XML with configurable field mapping
- **HTTP client:** Support redirects, resumable downloads, range requests
- **Storage:** Cache feed metadata locally; versioning for incremental updates
- **Network:** Timeout handling (30s for feed fetch, adaptive for large downloads)
- **Validation:** Check for duplicate imports; prevent circular feed references

### Design Considerations

- Display "Add Catalog" UI with URL input and validation feedback
- Show feed source name/author in book cards (e.g., "Project Gutenberg")
- Implement breadcrumb navigation (feed → book list → book detail)
- Provide "Import All" option for smaller feeds; warn on large feeds (>500 books)
- Show download status per book (queued, downloading, complete)

### Success Metrics

- 40%+ users add at least one remote catalog
- Average remote catalog has >100 books imported per user
- <5% feed parsing failures
- Download completion rate >85% (not abandoned)

### Dependencies

- HTTP/HTTPS library with resumable download support
- XML parsing library
- Optional: OPDS server for testing

### Priority
**High** - Core feature for discoverability and user acquisition

---

## PRD 3: Persistent Memory for Current Position

### Feature Overview
Track and persist the current playback position (timestamp) for each audiobook so users can seamlessly resume from their last listened position across sessions and devices.

### User Stories

**US-3.1:** As a user, I want the app to remember my position in a book so I can close the app and resume exactly where I left off.

**US-3.2:** As a user, I want my reading position synced across my phone and tablet so I can switch devices mid-listen.

**US-3.3:** As a user, I want to manually bookmark a position (e.g., "Chapter 5") for quick jumping back.

**US-3.4:** As a user, I want to see a playback history/timeline showing how much of each book I've completed.

### Acceptance Criteria

- [ ] Current playback position is saved every 5 seconds during playback
- [ ] Position is persisted to local database with atomic writes (no corruption on crash)
- [ ] App restores to saved position within 2 seconds on launch
- [ ] Supports position sync across devices (via cloud/iCloud/Google Drive if enabled)
- [ ] Position tracking works for all supported formats (AZW3, MP3, M4A, etc.)
- [ ] Manual bookmarks store timestamp + user-defined label
- [ ] Bookmarks are sortable and searchable by label
- [ ] Playback history shows % completion per book; sortable by date last played
- [ ] Handles edge cases: file duration changes, large gaps in position (>1 hour), out-of-order position updates

### Technical Requirements

- **Database:** SQLite or equivalent; schema includes book_id, position_ms, timestamp, device_id
- **Sync mechanism:** If cloud sync enabled, implement conflict resolution (last-write-wins or user choice)
- **Performance:** Write I/O should not block playback thread (<1ms latency)
- **Backup:** Position data should be included in app backup/export
- **Retention:** Keep position history for 12+ months per book
- **Format support:** Position tracking format-agnostic (works with all audio containers)

### Design Considerations

- Show current position in player as HH:MM:SS / Total Duration
- Display progress bar with scrubbing to jump to position
- Show bookmark list in a collapsible panel within player
- Indicate unsync'd position data with warning icon if multi-device sync is enabled
- Provide manual "Save Position" option for paranoid users

### Success Metrics

- 99%+ accurate position tracking (within 2 seconds of user's actual position)
- 95%+ successful resume on app reopen
- <1% data loss due to crashes/corruption
- Users with bookmarks have 30%+ higher session completion rate

### Dependencies

- SQLite or similar embedded database
- Cloud storage API (optional): Google Drive, iCloud, Dropbox
- Sync conflict resolution library

### Priority
**Critical** - Core UX feature; table stakes for audiobook apps

---

## PRD 4: Last Played Book at Top of Library List

### Feature Overview
Automatically sort the audiobook library to display the most recently played book at the top, with secondary sorting by last play date. Provides quick access to the current book without scrolling.

### User Stories

**US-4.1:** As a user, I want to open the app and immediately see the book I'm currently reading at the top of my library so I can tap and resume in one action.

**US-4.2:** As a user, I want the "last played" sorting to update every time I play a book so my library reflects actual listening habits.

**US-4.3:** As a user, I want the ability to toggle between "Last Played" and other sort orders (alphabetical, author, date added) so I can organize my library as I prefer.

**US-4.4:** As a user, I want to see the last play date and time under each book title in the library so I know when I last listened.

### Acceptance Criteria

- [ ] Library defaults to "Last Played" sort order on first launch
- [ ] Last play timestamp is updated every time playback starts (≥1 second of playback)
- [ ] Changes to sort order persist across sessions
- [ ] "Last Played" sort is always available as an option alongside other sort orders
- [ ] Books never played do not appear above books that have been played
- [ ] Never-played books are sorted alphabetically within the "never played" section (if applicable)
- [ ] Last play date is displayed in human-readable format (e.g., "Yesterday", "3 days ago", "Jan 15")
- [ ] Sorting update is instant (<100ms) when playback starts

### Technical Requirements

- **Data model:** Add last_played_timestamp field to book record
- **Sort logic:** ORDER BY last_played_timestamp DESC, title ASC (for secondary sort)
- **Update trigger:** Increment timestamp on playback start event
- **UI update:** Refresh list when sort order changes; lazy-load if library is large (>1000 books)
- **Performance:** Library list should scroll smoothly even with 10,000+ books
- **Persistence:** Sort preference stored in app settings (default: last_played)

### Design Considerations

- Display "Last Played" as the default tab or highlighted sort option
- Show last play time in a muted secondary text color (gray)
- Use relative date formatting for last play ("Today", "Yesterday", "2 weeks ago")
- Highlight the currently playing book with a small play icon or badge
- Allow drag-to-reorder only if not in "Last Played" sort mode (to avoid confusion)

### Success Metrics

- 70%+ of sessions start by tapping the top book (Last Played book)
- Users with >50 books spend 30% less time searching for current book
- Sorting preference changes <5% of the time (indicates good UX)

### Dependencies

- Database query optimization for large result sets
- UI list virtualization (if library is very large)

### Priority
**Medium** - Improves UX for power users; table stakes feature

---

## PRD 5: AZW3 Support

### Feature Overview
Enable the app to parse, decode, and play audiobooks in Amazon's AZW3 (KF8) format, including support for embedded audio, metadata, and DRM-protected content (where applicable).

### User Stories

**US-5.1:** As a user, I want to load an AZW3 audiobook from my device so I can listen to Kindle books I've purchased.

**US-5.2:** As a user, I want to see AZW3 metadata (title, author, cover art) displayed correctly in the library and player.

**US-5.3:** As a user, I want to listen to narrated AZW3 books (with embedded audio tracks) if available.

**US-5.4:** As a user, I want the app to handle DRM-protected AZW3 files gracefully (either support them or provide a clear error message).

### Acceptance Criteria

- [ ] App can detect and import .azw3 files from device storage or cloud
- [ ] AZW3 metadata (title, author, cover) is extracted and displayed accurately
- [ ] Audio tracks embedded in AZW3 can be decoded and played (lossless or MP3)
- [ ] Playback position syncs with text position if book has both audio and text
- [ ] DRM-protected files are either supported or gracefully rejected with user explanation
- [ ] File validation prevents corrupted/malformed AZW3 imports
- [ ] Performance: AZW3 parsing and import completes in <5 seconds for typical file (100MB)
- [ ] Supports AZW3 variants (fixed layout, reflowable, with/without embedded fonts)

### Technical Requirements

- **AZW3 parser:** Support ZIP-based OEB format; extract .opf manifest and audio references
- **Metadata extraction:** Parse OPF metadata (dc:title, dc:creator, dc:date, etc.)
- **Audio codec support:** MP3, AAC, OGG/Vorbis, FLAC (minimum: MP3 and AAC)
- **Cover art:** Extract from package or OPS folder
- **DRM handling:** 
  - If DRM-free: full support
  - If DRM-protected: implement Kindle DRM (requires AWS Kindle SDK) OR reject with clear error
- **Position mapping:** If audio + text, map audio timestamp to chapter/section in UI
- **Error handling:** Validate file structure; report parsing errors to user

### Design Considerations

- Display AZW3 format badge/indicator in library (e.g., "Amazon KF8")
- Show warning icon if file has unrecognized codecs or DRM
- Provide in-app help: "AZW3 with narration detected—audio will play"
- Allow batch import of AZW3 files from folder
- Offer "Learn More" link explaining DRM limitations if file is unsupported

### Success Metrics

- 80%+ of AZW3 files import successfully on first attempt
- <2% crashes due to malformed AZW3 input
- Audio playback latency <500ms after file import
- Users importing AZW3 have 25%+ higher retention vs. other formats

### Dependencies

- AZW3 parser library (e.g., `kepubify`, custom ZIP + OPF parser)
- Audio codec libraries (libvorbis, libmp3, etc.)
- Optional: AWS Kindle SDK (if supporting DRM-protected content)

### Priority
**High** - Unlocks Kindle library integration; major user request

---

## PRD 6: Google Drive Integration with Mobile Data Warning

### Feature Overview
Enable users to browse, download, and stream audiobooks stored in their Google Drive. Provide intelligent warnings and data usage estimates for mobile networks to prevent unexpected data overage.

### User Stories

**US-6.1:** As a user, I want to authorize the app to access my Google Drive so I can load audiobooks I've stored in the cloud.

**US-6.2:** As a user, I want to stream a book from Google Drive without downloading it first so I can save device storage.

**US-6.3:** As a user, I want to download a book from Google Drive to my device for offline listening so I can use the app on flights.

**US-6.4:** As a user on a mobile network, I want to see a warning showing the estimated data usage before downloading a large book so I don't accidentally consume my data plan.

**US-6.5:** As a user, I want to set a mobile data threshold (e.g., "warn if >500MB") so the app respects my data limits.

### Acceptance Criteria

- [ ] OAuth 2.0 authentication with Google Drive scope
- [ ] App displays list of .azw3, .mp3, .m4a, .flac files from Google Drive root and subfolders
- [ ] Streaming playback from Google Drive works without pre-download (adaptive bitrate)
- [ ] Download function with progress bar; pause/resume supported
- [ ] Mobile data warning triggers on cellular networks (not WiFi)
- [ ] Warning displays file size, estimated download time, and current network type
- [ ] User can set mobile data threshold in settings (default: 100MB)
- [ ] Threshold enforcement: block download if file size exceeds threshold (with override option)
- [ ] Streamed files use adaptive bitrate to minimize data consumption (<64 kbps default on cellular)
- [ ] Data usage tracking: show cumulative download/stream data in session and monthly views
- [ ] Graceful handling of network interruption: resume download on reconnection
- [ ] Cache streamed files temporarily for offline access (max 24 hours or 5GB total)

### Technical Requirements

- **Authentication:** Google OAuth 2.0 (drive.readonly scope minimum)
- **API calls:** Use Google Drive API v3 for file listing and metadata
- **Streaming:** Implement HTTP range requests for partial content downloads; adaptive bitrate codec
- **Network detection:** Use platform APIs to detect cellular vs. WiFi (Android: ConnectivityManager, iOS: NWPathMonitor)
- **Threshold logic:** Configurable mobile data limit; stored in app settings
- **Warning UI:** Modal/alert showing file size, ETA, and network type before download
- **Caching:** LRU cache for streamed files; evict oldest when cache exceeds limit
- **Logging:** Track downloads, streaming sessions, and data usage for analytics
- **Error handling:** Timeout (30s for metadata, 60s for download stalls), 404/403 errors, quota limits

### Design Considerations

- Display Google Drive as a separate "Browse" tab or section in library
- Show folder structure with breadcrumb navigation
- Add file metadata: size (GB/MB), duration, last modified date
- Display mobile data icon next to network type in warning dialog
- Provide "Settings" quick link in warning to adjust threshold
- Show data usage summary in Settings (e.g., "Downloaded: 2.3 GB, Streamed: 1.1 GB this month")
- Offer bulk download option for multiple files (with warning)

### Success Metrics

- 50%+ of users with Google Drive linked sync within first week
- 60%+ of linked users download ≥1 book from Drive
- <5% accidental overage complaints (indicates effective warnings)
- Average streaming session lasts >10 minutes (indicates acceptable quality)
- 80%+ of downloads complete successfully on first attempt

### Dependencies

- Google Drive API SDK (Android: Google API Client Library, iOS: GTMSessionFetcher)
- Network detection library (platform-specific)
- Adaptive bitrate codec (e.g., HLS or DASH for streaming)
- SQLite or equivalent for usage tracking

### Priority
**High** - Major competitive feature; cloud-first users expect this

---

## Implementation Roadmap

### Phase 1 (Weeks 1-4)
- PRD 0 (Metadata Enrichment) - Foundation; unblocks import workflows
- PRD 3 (Position Persistence) - Foundation for all other features
- PRD 4 (Last Played Sort) - Quick win; improves UX

### Phase 2 (Weeks 5-10)
- PRD 2 (Remote Repository) - Unlock user-generated content
- PRD 5 (AZW3 Support) - Unlock Kindle ecosystem

### Phase 3 (Weeks 11-16)
- PRD 1 (Google Cast) - Premium feature
- PRD 6 (Google Drive) - Cloud integration

---

## Cross-Feature Dependencies

| Feature | Depends On | Reason |
|---------|-----------|--------|
| Remote Repo (2) | Metadata Enrichment (0) | Must fetch metadata from remote sources before displaying books |
| AZW3 (5) | Metadata Enrichment (0) | Must extract/enrich metadata from AZW3 files |
| Google Cast (1) | Position Persistence (3) | Must resume from saved position on Cast device |
| Google Drive (6) | Metadata Enrichment (0) | Must enrich Drive files with cover/author/description |
| Google Drive (6) | Remote Repo (2) | File loading infrastructure shared |
| Remote Repo (2) | AZW3 Support (5) | Must support AZW3 files from feeds |
| AZW3 (5) | Position Persistence (3) | Must track position in AZW3 books |

---

## Success Criteria (Overall Product)

- **Feature adoption:** 70%+ of users have ≥1 feature enabled within 3 months
- **Retention:** 40% Day-30 retention for users who use all 6 features vs. 25% for new users
- **User sentiment:** 4.5+ star rating on app stores; NPS >50
- **Performance:** 99%+ uptime; <2% crash rate on feature-heavy paths
- **Data safety:** Zero user data loss incidents; 99.99% position sync accuracy

