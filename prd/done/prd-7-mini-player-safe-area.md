# PRD 7: Mini Player Safe Area & Android Gesture Bar Awareness

## Feature Overview
Ensure the mini player respects Android's gesture navigation bar and provides appropriate spacing to prevent content from being hard up against the bottom edge of the screen. The full player screen already displays correctly and does not require changes.

## User Stories

**US-7.1:** As a user with gesture navigation enabled, I want the mini player to avoid being hidden behind or obstructed by the Android gesture bar so I can see and interact with it clearly.

**US-7.2:** As a user, I want the mini player to have proper spacing from the bottom of the screen so it doesn't feel cramped or difficult to interact with.

## Acceptance Criteria

- [ ] Mini player detects when Android gesture navigation bar is active
- [ ] Mini player insets content with appropriate bottom padding/margin when gesture bar is present (minimum 48dp)
- [ ] Mini player is fully visible and interactable above the gesture bar area
- [ ] Safe area insets are applied correctly on devices with and without gesture navigation
- [ ] Play/pause button and other touch targets remain easily accessible with minimum 44dp touch target size
- [ ] Mini player layout does not break or overflow on any common Android screen size (4.5" to 6.7")
- [ ] Gesture bar awareness works on Android 9+ (API 28+)
- [ ] Full player screen behavior is unchanged (already displays correctly)

## Technical Requirements

### Android gesture bar detection:
- Use `WindowInsets` (API 30+) or `ViewCompat.getRootWindowInsets()` for gesture bar height detection
- Fallback to `Display.getSize()` vs. `getDecorView().getHeight()` for older Android versions
- Detect gesture navigation mode from `NavigationBarMode` (if available)

### Safe area insets:
- Apply bottom padding equal to gesture bar height + 8dp safety margin
- Update insets dynamically if configuration changes (rotation, gesture bar toggle)
- Use `WindowCompat.setOnApplyWindowInsetsListener()` to handle inset changes

### Compatibility:
- Test on devices with navigation buttons (traditional Android bar)
- Test on devices with gesture navigation (Android 9+)
- Test on devices with notches/punch holes (ensure no overlap)

### Performance:
- Inset detection should not cause layout thrashing or jank
- Minimal overhead when mini player is collapsed/hidden

## Design Considerations

- Minimum 8dp safety margin below mini player (beyond gesture bar height)
- Consider visual separator/divider above mini player to define boundary
- Ensure book cover thumbnail and text remain proportional when padded
- Play/pause button should remain centered within the safe area
- Dismiss/collapse button (if included) should be easily reachable without hitting gesture bar

## Success Metrics

- 100% of mini player interactions remain accessible on all Android 9+ devices
- Zero reports of mini player being obscured by gesture bar
- Touch accuracy unaffected by safe area insets (same as player screen)

## Dependencies

- Android ViewCompat or WindowCompat compatibility libraries
- Device configuration change handling

## Related Features

- PRD 3 (Position Persistence) - defines mini player base functionality
- Full player screen - already handles safe areas correctly

## Priority
**Medium** - Polish/UX refinement; ensures consistent behavior across all Android devices
