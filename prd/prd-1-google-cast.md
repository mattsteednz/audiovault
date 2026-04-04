# PRD 1: Google Cast Support for Local Listening

## Feature Overview
Enable users to cast audiobook playback to Google Cast–compatible devices (e.g., Chromecast, Google Home, smart speakers) while maintaining synchronized playback controls and audio output from remote devices.

## User Stories

**US-1.1:** As a user, I want to cast my current audiobook to a Chromecast device in my living room so I can listen to the book on my home speaker system.

**US-1.2:** As a user, I want to see available Cast devices listed in the app UI so I can select where to send audio.

**US-1.3:** As a user, I want to pause, play, and skip forward/backward on the Cast device from the app UI so I maintain playback control.

**US-1.4:** As a user, I want the Cast session to maintain my current position when I disconnect so I can resume from the same place later.

## Acceptance Criteria

- [ ] Cast device discovery works on local network (mDNS)
- [ ] App displays available Cast devices in a dedicated UI panel/dropdown
- [ ] User can select a Cast device and initiate playback routing within 2 seconds
- [ ] Audio streams to Cast device without app audio playback
- [ ] Playback controls (play, pause, seek, volume) are responsive (<500ms latency)
- [ ] Current position is persisted when Cast session ends
- [ ] Graceful error handling if device becomes unreachable (retry logic + user notification)
- [ ] Supports standard Google Cast API protocols

## Technical Requirements

- **Implement Google Cast SDK** for Android/iOS
- **Network requirements:** Local network access; mDNS service discovery
- **Protocol:** Cast Control Protocol v2 (CCP)
- **Playback:** Stream audio via RSTP or HTTP (must support AZW3 decoded audio format)
- **Session management:** Store Cast device UID and resume capability
- **Error handling:** Detect network disconnection, device unavailability, casting errors
- **Permissions:** Network access, local service discovery permissions

## Design Considerations

- Display Cast icon in playback controls only when devices are detected
- Show device selection UI in-player (not modal overlay)
- Indicate active Cast device with visual indicator (blue icon or name display)
- Provide reconnect option if Cast session drops
- Disable Cast UI if playback source is incompatible (e.g., DRM content)

## Success Metrics

- 60%+ of users with Cast devices attempt casting within first month
- <2% error rate on Cast session initiation
- <1% of sessions drop unexpectedly after 5 minutes
- Average Cast session duration >15 minutes

## Dependencies

- Google Cast SDK (Android: libcast, iOS: GoogleCastSDK)
- Network layer: mDNS/Bonjour support
- Audio decoding pipeline (must produce raw PCM for streaming)

## Priority
**High** - Differentiates product, enables multi-room listening
