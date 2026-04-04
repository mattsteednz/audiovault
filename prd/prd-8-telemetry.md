# PRD 8: Telemetry & Analytics with Firebase

## Feature Overview
Implement opt-in telemetry using Firebase Crashlytics and Analytics to track app opens and crashes. Show a permission prompt on first app launch asking users to opt-in. Emphasize privacy: no personal data is collected, only anonymous usage metrics to help improve the app.

## User Stories

**US-8.1:** As a developer, I want to automatically capture crashes so I can identify critical bugs and prioritize fixes.

**US-8.2:** As a developer, I want to track app opens so I can understand how many users are actively using the app.

**US-8.3:** As a user, I want to be asked for permission on first launch before any telemetry is collected.

**US-8.4:** As a user, I want clear transparency about what data is collected and how it's used.

## Acceptance Criteria

### First-Run Permission Prompt:
- [ ] Permission prompt appears as the very first screen on app launch (before any other UI)
- [ ] Title: "Help us improve AudioVault"
- [ ] Body text: "We use Google Firebase to collect crash reports and track that you're using the app. No personal data like book titles or files are ever sent. You can opt out anytime."
- [ ] Two buttons: "Accept" (primary), "Decline" (secondary)
- [ ] Choice is saved and persists across app sessions
- [ ] If user accepts, Firebase telemetry is enabled
- [ ] If user declines, no telemetry data is collected or sent

### Firebase Integration:
- [ ] Firebase SDK initialized on app startup (Crashlytics + Analytics)
- [ ] Crash reporting automatically enabled via Firebase Crashlytics
- [ ] App open event tracked in Firebase Analytics
- [ ] Events flow to GA4 Property `531271091`
- [ ] Both Android and iOS apps report to their respective Measurement IDs

### Events Tracked (if user accepts):
- [ ] App open — recorded on launch to count active users
- [ ] Crash events — automatically captured by Firebase Crashlytics with stack traces
- [ ] No other custom events tracked at this stage

### Data Privacy:
- [ ] No file paths, book titles, author names, or other personal data sent to Firebase
- [ ] No user identification beyond anonymous app installs
- [ ] Firebase default retention policy respected

## Technical Requirements

### Firebase Configuration:
- **Project ID:** `audiovault-7c0de`
- **Project Name:** AudioVault
- **Registered Apps:**
  - Android: `com.mattsteed.audiovault`
  - iOS: `com.mattsteed.audiovault`

### Configuration Files:
- Android: `android/app/google-services.json`
- iOS: `ios/Runner/GoogleService-Info.plist`

### Google Analytics 4:
- **Account ID:** `389904839`
- **Property ID:** `531271091`
- **Measurement IDs:** (create data streams in GA4 console)
  - Android: `G-XXXXXXXXXX` (TBD)
  - iOS: `G-XXXXXXXXXX` (TBD)

### Firebase Services:
- **Firebase Analytics** — Tracks app opens, event logging, GA4 integration
- **Firebase Crashlytics** — Automatic crash reporting with stack traces

### Implementation:
- Initialize Firebase on app startup (before showing any UI)
- Show permission prompt immediately
- Call `FirebaseAnalytics.setAnalyticsCollectionEnabled(enabled)` based on user choice
- If enabled, automatically log "app_open" event on each launch
- Crashlytics automatically captures all exceptions

## Design Considerations

### Permission Prompt Design:
- Full-screen modal that appears before any app content
- Clear, honest messaging about data collection
- Mention "Google Firebase" to indicate who handles the data
- Emphasize no personal data is collected
- Make both options equally accessible (not dark patterns)

### Visual Style:
- Professional, trustworthy appearance
- Use app's primary colors/branding
- Clear readable text, adequate contrast

## Success Metrics

- 95%+ of crashes automatically captured by Crashlytics
- App open events visible in GA4 within 24 hours
- 50%+ of users opt-in to telemetry

## Dependencies

- Firebase SDK for Flutter (firebase_core, firebase_analytics, firebase_crashlytics)

## Related Features

- Follow-up PRD: Settings screen with telemetry on/off toggle and opt-out option
- Custom event tracking (app-specific events added in future PRDs)

## Priority

**Medium** - Important for crash tracking and understanding basic engagement, but not core to MVP. Implement after Phase 1 core features are stable.

## Implementation Notes

- Firebase Crashlytics automatically captures crashes without additional code
- App open events are tracked automatically by Firebase Analytics
- Always respect user's choice on the permission prompt
- Test with both opt-in and opt-out states to verify behavior
- Measurement IDs must be created as data streams in GA4 console before they start receiving events
