# PRD 10: Settings Screen

## Feature Overview
Create a Settings screen accessible via a gear icon at the end of the Library tab icons. The Settings screen provides controls for folder selection (moved from Library icons) and telemetry preferences. Remove the history screen from Library icons.

## User Stories

**US-10.1:** As a user, I want to access app settings from a gear icon in the Library tab so I can manage my audiobook folder and preferences.

**US-10.2:** As a user, I want to select or change my audiobooks folder from Settings instead of cluttering the Library interface.

**US-10.3:** As a user, I want to see the currently selected audiobooks path in Settings so I know where the app is looking for books.

**US-10.4:** As a user, I want to toggle telemetry on/off in Settings to control what data is sent to Firebase.

## Acceptance Criteria

### Settings Screen Access:
- [ ] Gear icon ("⚙️") appears as the last icon in the Library tab icon row
- [ ] Tapping gear icon opens Settings screen
- [ ] Settings screen slides in from the right or appears as new view
- [ ] Gear icon is visually distinct but matches app design language
- [ ] Settings screen has a back button or swipe-to-dismiss to return to Library

### Folder Selection Section:
- [ ] Appears at the top of Settings screen under a "Audiobooks" heading
- [ ] Shows current selected folder path in readable format (e.g., "/storage/emulated/0/Documents/Audiobooks")
- [ ] "Select Audiobooks Folder" button with folder icon
- [ ] Tapping button opens file picker/folder browser
- [ ] User can select a new folder; current selection updates immediately
- [ ] Path persists across app sessions

### Telemetry Section:
- [ ] Appears below Folder Selection under a "Privacy" heading
- [ ] Checkbox: "Send crash reports and usage data to help improve AudioVault"
- [ ] Default state matches user's choice from first-run prompt
- [ ] Toggling updates Firebase telemetry state immediately
- [ ] Clear explanatory text: "Data sent to Google Firebase is anonymous and includes no personal information"

### Layout:
- [ ] Settings screen has clean, readable layout with sections and padding
- [ ] Each section has a heading and relevant controls
- [ ] Buttons and checkboxes are large enough for easy tapping
- [ ] Settings persist across app restarts

### History Screen Removal:
- [ ] History/timeline screen icon removed from Library tab
- [ ] Playback history functionality removed
- [ ] Library icons now only include: Browse, Search, (other non-history icons), Settings

## Technical Requirements

### Navigation:
- Settings screen accessible via gear icon in Library tab
- Use standard navigation pattern (push/slide transition)
- Back button or navigation bar for returning to Library

### Folder Selection:
- Use platform file picker (FilePicker package or similar)
- Validate selected folder exists and is readable
- Store selected path in app preferences/local storage
- Update app's audiobook scan directory on change

### Telemetry Preference:
- Read current telemetry state from local storage
- On toggle, immediately call `FirebaseAnalytics.setAnalyticsCollectionEnabled(enabled)`
- Persist preference to local storage
- Match first-run prompt selection by default

### Data Persistence:
- Settings changes saved to local database/preferences
- Folder path persisted across sessions
- Telemetry preference persisted across sessions

## Design Considerations

### Visual Design:
- Gear icon in Library tab using standard icon (circle with teeth)
- Icon color matches other Library tab icons
- Settings screen background and text color match app theme
- Section headings use slightly larger/bolder text than body text

### Folder Section Design:
- Current path displayed in a read-only text field or label
- Button text: "Select Audiobooks Folder" (clear, action-oriented)
- Show folder icon next to button for visual clarity
- Path truncation: show beginning and end if path is very long (e.g., "/storage/.../Audiobooks")

### Telemetry Section Design:
- Checkbox aligned with other toggles in app (if any)
- Label text clear and trustworthy in tone
- Optional: Small "?" icon with tooltip explaining Firebase/Google

### Spacing & Layout:
- Top section (Folder) has breathing room from navigation
- Sections separated by spacing or dividers
- Bottom of screen has padding (safe area for bottom navigation)

## Success Metrics

- Settings screen accessible in <2 taps from Library view
- 80%+ of users can successfully change folder without confusion
- Telemetry preference toggles correctly (verified via Firebase console)
- Settings persist across app close/reopen (100% reliability)

## Dependencies

- File picker library (FilePicker or similar)
- Local preferences/storage library (SharedPreferences, Hive, etc.)
- Firebase Analytics SDK (for telemetry toggle)

## Related Features

- PRD 3 (Position Persistence) — folder selection affects which books are scanned
- PRD 8 (Telemetry) — telemetry toggle controls Firebase data collection
- Follow-up: Settings screen can be expanded with additional preferences in future

## Priority

**High** - Essential for user control over folder selection and telemetry. Core to PRD 8 implementation.

## Implementation Notes

- Remove history/timeline feature completely (no UI, no data collection)
- Folder selection replaces the old "Select audiobooks" icon from Library tab
- Settings screen can be simple MVP (two sections) and expanded later with additional preferences
- Test that toggling telemetry immediately reflects in Firebase console
- Ensure folder path changes trigger app re-scan of audiobooks
