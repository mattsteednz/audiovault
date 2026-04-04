# PRD 4: Last Played Book at Top of Library List

## Feature Overview
Automatically sort the audiobook library to display the most recently played book at the top, with secondary sorting by last play date. Provides quick access to the current book without scrolling.

## User Stories

**US-4.1:** As a user, I want to open the app and immediately see the book I'm currently reading at the top of my library so I can tap and resume in one action.

**US-4.2:** As a user, I want the "last played" sorting to update every time I play a book so my library reflects actual listening habits.

**US-4.3:** As a user, I want to see the last play date and time under each book title in the library so I know when I last listened.

## Acceptance Criteria

- [ ] Library displays in "Last Played" sort order (most recently played book at top)
- [ ] Last play timestamp is updated every time playback starts (≥1 second of playback)
- [ ] Books never played do not appear above books that have been played
- [ ] Never-played books are sorted alphabetically within the "never played" section (if applicable)
- [ ] Last play date is displayed under each book title in muted secondary text
- [ ] Sorting update is instant (<100ms) when playback starts

## Technical Requirements

### Data model:
Add last_played_timestamp field to book record

### Sort logic:
ORDER BY last_played_timestamp DESC, title ASC (for secondary sort)

### Update trigger:
Increment timestamp on playback start event

### UI update:
Refresh list position when last played timestamp updates; lazy-load if library is large (>1000 books)

### Performance:
Library list should scroll smoothly even with 10,000+ books

### Persistence:
Last played timestamp persisted to database; library always displays in Last Played order

## Design Considerations

- Show last play time in a muted secondary text color (gray) beneath book title
- Highlight the currently playing book with a small play icon or badge
- Ensure visual distinction between recently played and older books

## Success Metrics

- 70%+ of sessions start by tapping the top book (Last Played book)
- Users with >50 books spend 30% less time searching for current book

## Dependencies

- Database query optimization for large result sets
- UI list virtualization (if library is very large)

## Priority
**Medium** - Improves UX for power users; table stakes feature
