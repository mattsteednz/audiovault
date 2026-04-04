# PRD 3: Persistent Memory for Current Position

## Feature Overview

Track and persist the current playback position (timestamp) for each audiobook so users can seamlessly resume from their last listened position when reopening the app. Show a mini player at the bottom of the library list for quick resume if a book was playing when the app closed.

## User Stories

**US-3.1:** As a user, I want the app to remember my position in a book so I can close the app and resume exactly where I left off.

**US-3.2:** As a user, I want to see a mini player at the bottom of the library when I reopen the app if a book was playing, so I can quickly resume without navigating.

**US-3.3:** As a user, I want to see a playback history/timeline showing how much of each book I've completed.

## Acceptance Criteria

- [ ] Current playback position is saved every 5 seconds during playback
- [ ] Position is persisted to local database with atomic writes (no corruption on crash)
- [ ] App restores to saved position within 2 seconds on launch
- [ ] Position tracking works for all supported formats (AZW3, MP3, M4A, etc.)
- [ ] If a book was playing when the app closed, a mini player appears at the bottom of the library list
- [ ] Mini player shows book cover, title, remaining time ("00h 00m left"), and play/pause controls
- [ ] Tapping mini player launches full player and resumes from saved position
- [ ] Mini player persists across library navigation (visible on all library views/sorts)
- [ ] Playback history shows % completion per book; sortable by date last played
- [ ] Handles edge cases: file duration changes, large gaps in position (>1 hour), out-of-order position updates

## Technical Requirements

### Database:

SQLite or equivalent; schema includes book\_id, position\_ms, last\_position\_update\_timestamp
- Internally store position as milliseconds from start (position_ms) for technical efficiency
- All user-facing displays calculate and show time remaining (total duration - current position)

### Mini player persistence:

Store last\_playing\_book\_id to identify which book was active when app closed; restore on app launch

### Performance:

Write I/O should not block playback thread (<1ms latency)

### Retention:

Keep position history for 12+ months per book

### Format support:

Position tracking format-agnostic (works with all audio containers)

## Design Considerations

### Player UI:
- Show current position as HH:MM:SS / Total Duration in player header
- Display progress bar with scrubbing to jump to position

### Mini player (library view):
- Position at bottom of library list, above any floating action buttons
- Display book cover thumbnail (100px), title (2-line truncate), and remaining time ("00h 00m left")
- Include play/pause button; pause state shows resume icon
- Use subtle shadow/border to distinguish from library content
- Show loading state if position is being restored
- Collapse/dismiss option with swipe or X button (but restore if book still playing)

### Playback history view:
- Show list of books with % completion per book
- Display last play date in human-readable format (e.g., "Today", "3 days ago", "Jan 15")
- Sort by date last played (most recent first)
- Include duration and current position for quick context

## Success Metrics

- 99%+ accurate position tracking (within 2 seconds of user's actual position)
- 95%+ successful resume on app reopen
- <1% data loss due to crashes/corruption
- 70%+ of sessions with active playback use mini player to resume (indicates good discoverability)
- Mini player remains visible across 95%+ of library navigation actions (no accidental dismissals)

## Dependencies

- SQLite or similar embedded database

## Priority

**Critical** - Core UX feature; table stakes for audiobook apps

