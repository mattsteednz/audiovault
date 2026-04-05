# PRD 5: AZW3 Support

## Feature Overview
Enable the app to parse, decode, and play audiobooks in Amazon's AZW3 (KF8) format, including support for embedded audio, metadata, and DRM-protected content (where applicable).

## User Stories

**US-5.1:** As a user, I want to load an AZW3 audiobook from my device so I can listen to Kindle books I've purchased.

**US-5.2:** As a user, I want to see AZW3 metadata (title, author, cover art) displayed correctly in the library and player.

**US-5.3:** As a user, I want to listen to narrated AZW3 books (with embedded audio tracks) if available.

**US-5.4:** As a user, I want the app to handle DRM-protected AZW3 files gracefully (either support them or provide a clear error message).

## Acceptance Criteria

- [ ] App can detect and import .azw3 files from device storage or cloud
- [ ] AZW3 metadata (title, author, cover) is extracted and displayed accurately
- [ ] Audio tracks embedded in AZW3 can be decoded and played (lossless or MP3)
- [ ] Playback position syncs with text position if book has both audio and text
- [ ] DRM-protected files are either supported or gracefully rejected with user explanation
- [ ] File validation prevents corrupted/malformed AZW3 imports
- [ ] Performance: AZW3 parsing and import completes in <5 seconds for typical file (100MB)
- [ ] Supports AZW3 variants (fixed layout, reflowable, with/without embedded fonts)

## Technical Requirements

### AZW3 parser:
Support ZIP-based OEB format; extract .opf manifest and audio references

### Metadata extraction:
Parse OPF metadata (dc:title, dc:creator, dc:date, etc.)

### Audio codec support:
MP3, AAC, OGG/Vorbis, FLAC (minimum: MP3 and AAC)

### Cover art:
Extract from package or OPS folder

### DRM handling:
- If DRM-free: full support
- If DRM-protected: implement Kindle DRM (requires AWS Kindle SDK) OR reject with clear error

### Position mapping:
If audio + text, map audio timestamp to chapter/section in UI

### Error handling:
Validate file structure; report parsing errors to user

## Design Considerations

- Display AZW3 format badge/indicator in library (e.g., "Amazon KF8")
- Show warning icon if file has unrecognized codecs or DRM
- Provide in-app help: "AZW3 with narration detected—audio will play"
- Allow batch import of AZW3 files from folder
- Offer "Learn More" link explaining DRM limitations if file is unsupported

## Success Metrics

- 80%+ of AZW3 files import successfully on first attempt
- <2% crashes due to malformed AZW3 input
- Audio playback latency <500ms after file import
- Users importing AZW3 have 25%+ higher retention vs. other formats

## Dependencies

- AZW3 parser library (e.g., `kepubify`, custom ZIP + OPF parser)
- Audio codec libraries (libvorbis, libmp3, etc.)
- Optional: AWS Kindle SDK (if supporting DRM-protected content)

## Priority
**High** - Unlocks Kindle library integration; major user request
