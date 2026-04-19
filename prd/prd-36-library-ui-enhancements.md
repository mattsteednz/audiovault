\# My Library – Header \& Filter Redesign

\*\*Product Requirements Document\*\*

\*AudioVault · April 2026\*



\---



\## Overview



Simplify the My Library screen header by reducing 6 toolbar icons down to 2, and replace the filter chip row with a single contextual toolbar containing a consolidated Filter \& Sort sheet.



\---



\## Problem



The existing header contains 6 icons in a single row (Search, Listen History, Sort, View Toggle, Rescan Library, Settings), which:

\- Truncates the screen title to "My Lib..." on standard screen widths

\- Presents equal visual weight to rarely-used actions (Rescan, Settings) and frequent ones (Search)

\- Provides no contextual feedback about which filters are active



\---



\## Changes



\### 1. Header — reduce to 2 icons



\*\*Before:\*\* Search · History · Sort · View Toggle · Rescan · Settings



\*\*After:\*\* Search · ⋯ (overflow menu)



\- The title "My Library" should always render in full — do not truncate

\- \*\*Search\*\* stays as a visible icon (highest frequency action). Tapping expands an inline search bar below the header with an auto-focused text input and a close (✕) button. Use `AnimatedSize` (or `AnimatedSwitcher`) so the bar slides in/out smoothly and the view bar shifts down with a short animation rather than jumping

\- \*\*⋯ (vertical ellipsis)\*\* opens a dropdown menu containing:

&#x20; - Listen history

&#x20; - Rescan library

&#x20; - Settings

\- The ⋯ icon turns accent-coloured when the menu is open



\---



\### 2. Library view bar — replaces filter chip row



Add a single \*\*pinned\*\* row below the header (and below the search bar when expanded) — it does not scroll with the grid/list. It contains:



| Slot | Content |

|------|---------|

| Left (flex) | View toggle button, then `{n} book(s)` count label, followed by an active filter summary if any filters are set (e.g. `· In progress · Title A–Z`) in accent colour |

| Right | Filter button + Sort button |



\#### View toggle button (left)

\- Single button that switches between grid and list view

\- Shows the \*opposite\* icon to the current state (i.e. when in grid view, show the list icon as the affordance)

\- Sits before the book count



\#### Filter button

\- Icon: funnel / filter icon

\- When \*\*no filter active\*\* (`\_statusFilter == null`): muted colour, neutral background

\- When \*\*filter active\*\*: accent-tinted background (no separate dot badge — the tint alone signals active state)

\- Tapping opens the \*\*Filter bottom sheet\*\* (Progress pills only)



\#### Sort button

\- Icon: sort icon (e.g. `Icons.sort` or equivalent). A label caret is acceptable if the team prefers a more discoverable affordance

\- When sort is the default (`.lastPlayed`): muted colour, neutral background

\- When a non-default sort is active: accent-tinted background

\- Tapping opens the \*\*Sort bottom sheet\*\* (Sort pills only)



\---



\### 3. Bottom sheets (Filter and Sort — separate)



Two modal bottom sheets, each triggered by its own view-bar button. Both render \*\*outside\*\* any overflow-hidden scroll containers so they are not clipped — use `showModalBottomSheet` which mounts at the root `Navigator`.



\#### Filter sheet



```

\[drag handle]

Filter                  ← sheet title



PROGRESS                ← section label

\[All] \[Not started] \[In progress] \[Finished]   ← pill toggles (single-select)



\[Clear all]            ← action button

```



\- \*\*All pill\*\* is selected by default and represents "no filter" (`\_statusFilter == null`). Selecting another pill deselects All. Selecting All clears the filter.

\- Tapping a pill \*\*auto-applies\*\* the filter to the underlying state immediately; the view bar (visible behind the backdrop) updates live.

\- \*\*Clear all\*\* re-selects the All pill (equivalent to clearing `\_statusFilter`). Does not close the sheet.

\- \*\*Backdrop tap / drag-down / close X\*\* dismisses the sheet. There is no explicit Apply button — changes are already applied.



\#### Sort sheet



```

\[drag handle]

Sort                    ← sheet title



SORT BY                 ← section label  

\[Last played] \[Title A–Z] \[Author A–Z] \[Recently added] \[Longest first] ← pill toggles (single-select)
```



\- \*\*Last played\*\* is the default and is shown as an explicit pill (selected by default). The sort always has exactly one active pill — pills are not deselectable; tapping a different pill switches the sort.

\- Pill values map to `LibrarySortOrder`: `.lastPlayed`, `.titleAsc`, `.authorAsc`, `.dateAdded`, `.durationDesc`.

\- Tapping a pill \*\*auto-applies\*\* via `\_setSortOrder()` (persists + re-sorts). View bar updates live.

\- \*\*Backdrop tap / drag-down / close X\*\* dismisses the sheet.



\#### Visual spec

\- Sheet background: dark surface (`#1a1c22` or equivalent)

\- Pill border: `1.5px` subtle border, rounded-full

\- Active pill: accent-tinted background + accent border + accent text

\- "Clear all" button (Filter sheet only): ghost style (subtle fill, muted text)

\- Drag handle: short pill at top centre



\---



\### 4. Dynamic book count



\- The `{n} books` label in the view bar reflects the \*\*currently filtered count\*\*, not the total library size

\- When a progress filter is active, only books matching that progress state are shown in the grid/list

\- Singular form: `1 book` / plural: `{n} books`



\---



\### 5. Empty state



When the active filters produce zero results:



\- Hide the grid/list

\- Show a centred empty state with:

&#x20; - A muted book icon (low-opacity stroke illustration)

&#x20; - Primary text: `No books match`

&#x20; - Secondary text: `Try adjusting your filters`

&#x20; - A ghost `Clear filters` button that resets all filters



\---



\### 6. Mini player — frosted glass treatment



Apply a backdrop blur to the mini player bar so it reads as a floating layer above the content:



```css

background: rgba(22, 22, 28, 0.9);

backdrop-filter: blur(20px) saturate(1.4);

\-webkit-backdrop-filter: blur(20px) saturate(1.4);

border-top: 1px solid rgba(255, 255, 255, 0.07);

```



\---



\## Clarifications \& implementation notes  \*(updated after codebase review)\*



\### Sort is already fully implemented

Sort logic is \*\*not\*\* UI-only. `LibrarySortOrder` enum and `sortBooks()` are already complete in `library\_screen.dart`. The sort pills in the Filter \& Sort sheet should map directly to the existing enum values:



| Sheet pill label | `LibrarySortOrder` value |

|---|---|

| Last played \*(default, no pill selected)\* | `.lastPlayed` |

| Title A–Z | `.titleAsc` |

| Author A–Z | `.authorAsc` |

| Recently added | `.dateAdded` |

| Longest first | `.durationDesc` |



Persist the selected sort via the existing `PreferencesService.setLibrarySort()` / `getLibrarySort()` calls. Call `\_setSortOrder()` on apply — this already handles persistence + re-sort.



\### Sort default behaviour

`LibrarySortOrder.lastPlayed` is the default (loaded from prefs via `\_initLibrary()`). When no Sort pill is selected in the sheet, the sort remains `.lastPlayed`. Do not pre-select any pill — the default is implicit. Show the sort label in the view bar summary only when a non-default sort is active (i.e. not `.lastPlayed`).



\### Duration sort data

`Audiobook.duration` is a `Duration?` field containing the total book duration — use `a.duration?.inMilliseconds` directly. The `sortBooks()` function already handles this. `chapterDurations` is a `List<Duration>` for chapter-level seeking; it is not used for sort.



\### Status filter — existing implementation

`BookStatus` enum: `notStarted`, `inProgress`, `finished`. The current `\_statusFilter` state variable and `applyStatusFilter()` function already handle filtering. The existing `\_filterPillsRow()` `FilterChip` row should be \*\*removed\*\* and replaced by the new library view bar. Status filtering moves into the Filter \& Sort sheet.



\### Sleep timer indicator

The current AppBar includes a `SleepTimerIndicator` widget. This must be \*\*preserved\*\* in the new header. Add it as the first trailing action (before the Search icon):

```dart

SleepTimerIndicator(onTap: \_openCurrentBookPlayer)

```



\### "Listen history" menu label

Use \*\*"Listen history"\*\* in the ⋯ menu. Routes to the existing `HistoryScreen(books: \_rawBooks)`.



\### Rescan — spinner state

The existing rescan icon shows a `CircularProgressIndicator` while `\_syncing` is true. Preserve this behaviour in the ⋯ menu item: show a small inline spinner next to "Rescan library" when `\_syncing`, and disable the tap target.



\### Search bar — implementation approach

The current implementation transforms the AppBar `title` into a `TextField` (replacing the screen title in-place). The redesign moves search to an \*\*inline bar below the AppBar\*\* (a `TextField` in an `AnimatedSwitcher` or `AnimatedSize` between the AppBar and the filter row). The AppBar title always shows "My Library". Use `\_searchController`, `\_isSearching`, and `\_searchQuery` — these state variables already exist and can be reused as-is.



\### Search bar persistence

\- When the search bar is open and the user opens the ⋯ menu, the bar stays open

\- When the filter sheet opens, the search bar stays visible behind the sheet backdrop

\- An active search query does \*\*not\*\* count toward the filter badge or dot — the badge reflects only `\_statusFilter` and non-default `\_sortOrder`



\### Empty state — no-matches view

The existing `\_noMatchesView()` already produces context-aware messages. Preserve its logic:

\- Search only: `No results for "{query}".`

\- Filter only: `No {status} books.`

\- Search + filter: `No {status} books match "{query}".`

\- Clear action: calls existing `\_clearSearchAndFilters()` — clears both search and `\_statusFilter` (does \*\*not\*\* reset sort)



\### Active filter summary wording

\- Show progress label when `\_statusFilter != null` (e.g. `· In progress`)

\- Show sort label when `\_sortOrder != LibrarySortOrder.lastPlayed` (e.g. `· Title A–Z`)

\- Both can appear together: `· In progress · Title A–Z`



\### Frosted mini player — Flutter implementation

The mini player is `\_MiniPlayer` — a `StatelessWidget` rendered in a `Column` at the bottom of `\_LibraryScreenState`. Currently uses `theme.colorScheme.surfaceContainerHigh` as its `Material` colour. Apply frosted glass by wrapping with `ClipRect` + `BackdropFilter`:



```dart

ClipRect(

&#x20; child: BackdropFilter(

&#x20;   filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),

&#x20;   child: Material(

&#x20;     color: theme.colorScheme.surface.withValues(alpha: 0.85),

&#x20;     child: ... // existing mini player content

&#x20;   ),

&#x20; ),

)

```



On low-end devices, `BackdropFilter` can be expensive. Acceptable fallback: omit the `BackdropFilter` and use a solid `theme.colorScheme.surfaceContainerHigh` — the existing colour — with no blur.



\### Light / dark mode — use theme tokens, not hex

The hex values in the Visual spec (`#c9aaff`, `#1a1c22`, `rgba(22,22,28,0.9)`, etc.) are dark-mode reference values. Implement against `Theme.of(context).colorScheme` tokens so both modes work:

| PRD reference (dark) | Use theme token |
|---|---|
| Accent `#c9aaff` | `colorScheme.primary` |
| Accent-tinted background | `colorScheme.primaryContainer` (or `primary.withValues(alpha: 0.12)`) |
| Sheet background `#1a1c22` | `colorScheme.surfaceContainerHigh` |
| Mini player bg `rgba(22,22,28,0.9)` | `colorScheme.surface.withValues(alpha: 0.85)` |
| Border `rgba(255,255,255,0.07)` | `colorScheme.outlineVariant.withValues(alpha: 0.4)` |
| Muted pill border | `colorScheme.outlineVariant` |
| Muted text | `colorScheme.onSurfaceVariant` |
| Filter dot badge | `colorScheme.primary` |

Placeholder palette (coloured tiles) is used in \*\*both\*\* modes unchanged — icon on top stays `colorScheme.onSurfaceVariant` with sufficient opacity for contrast.

\### ⋯ overflow menu accent state

Flutter's `PopupMenuButton` does not expose its open state. To tint the ⋯ icon while open, replace with a `MenuAnchor` (Flutter 3.13+) or use a `ValueNotifier<bool>` toggled via `onOpened` / `onCanceled` / `onSelected` callbacks on `PopupMenuButton`.



\---



\## Coloured placeholder tiles



When no cover art is available (`coverImageBytes` and `coverImagePath` are both null), replace the current flat `surfaceContainerHighest` background in `BookCover.\_placeholder()` with a \*\*deterministic per-book colour\*\* derived from the book's title. This makes the library visually varied and interesting without requiring real artwork.



\### Implementation — `book\_cover.dart`



Generate a colour by hashing the book title and selecting from a curated palette. Colours are allocated \*\*sequentially by render position\*\* — `palette[renderIndex % palette.length]` — so that no two adjacent tiles within a row of 8 ever share a colour. A given book's placeholder colour may change when the list is re-sorted or filtered; this is acceptable because placeholders are fallbacks, not book identity.

Requirements:

\- \*\*No on-screen collisions within each palette-length run\*\* — sequential allocation guarantees this

\- \*\*Legible\*\* — the icon on top must remain readable against every palette colour



\#### Suggested approach



```dart

static const List<Color> \_placeholderPalette = \[

&#x20; Color(0xFF1A3A5C), // deep navy

&#x20; Color(0xFF2A1A3A), // deep plum

&#x20; Color(0xFF1A2A1A), // dark forest

&#x20; Color(0xFF3A2A1A), // dark amber

&#x20; Color(0xFF2A3A1A), // dark moss

&#x20; Color(0xFF3A1A1A), // dark crimson

&#x20; Color(0xFF1A3A3A), // dark teal

&#x20; Color(0xFF2A2A3A), // dark slate

];



// Allocated by render position — pass the index of the tile in the
// currently-rendered grid/list so adjacent tiles never collide.
Color \_placeholderColor(int renderIndex) {

&#x20; return \_placeholderPalette\[renderIndex % \_placeholderPalette.length];

}

```



Then in `\_placeholder()`, replace:

```dart

ColoredBox(color: theme.colorScheme.surfaceContainerHighest, ...)

```

with:

```dart

ColoredBox(color: \_placeholderColor(renderIndex), ...)

```



The icon colour should remain `theme.colorScheme.onSurfaceVariant` — it will be legible against all palette colours above. Adjust opacity to `0.6` if needed for contrast on lighter themes.



\### Notes

\- The `isEnriching` spinner overlay and `enrichmentFailed` icon logic are \*\*unchanged\*\*

\- This affects both `AudiobookCard` (grid) and `AudiobookListTile` (list) since both use `BookCover`

\- The palette can be tuned to match the app's colour system; the values above are a starting point matching the mockup



\---



\## Out of scope

\- Changes to any screen other than My Library

\- Changes to the mini player controls or playback behaviour

\- Changes to the Settings, History, or Rescan screens themselves

\- Light-mode-specific placeholder palette — the jewel-tone palette is used in both light and dark modes (matches how music apps handle fallback artwork)



\---



\## Acceptance criteria



\- \[ ] Header title "My Library" never truncates at any standard screen width

\- \[ ] Header contains: `SleepTimerIndicator`, Search, ⋯ — in that order

\- \[ ] ⋯ menu contains: Listen history, Rescan library (with spinner when `\_syncing`), Settings

\- \[ ] Search icon expands an inline bar \*\*below\*\* the AppBar (AppBar title stays "My Library")

\- \[ ] Search uses existing `\_searchController`, `\_isSearching`, `\_searchQuery` state

\- \[ ] Existing `\_filterPillsRow()` `FilterChip` row is removed

\- \[ ] View bar shows live filtered book count (`\_displayedBooks.length`) with correct singular/plural

\- \[ ] View bar shows active filter summary in accent colour: progress label + sort label when non-default (e.g. `· In progress · Title A–Z`)

\- \[ ] View bar left-to-right order: view toggle, book count, filter summary

\- \[ ] View bar right-side order: Filter button, Sort button

\- \[ ] Filter button shows accent-tinted background (no dot badge) when `\_statusFilter != null`

\- \[ ] Sort button shows accent-tinted background when `\_sortOrder != LibrarySortOrder.lastPlayed`

\- \[ ] View toggle switches between `\_ViewMode.grid` and `\_ViewMode.list` with a single button

\- \[ ] Sheets open above all content (not clipped by scroll containers)

\- \[ ] Filter sheet: Progress pills include an \*\*All\*\* pill (default-selected) plus `.notStarted`, `.inProgress`, `.finished`; single-select; auto-applies on tap

\- \[ ] Sort sheet: pills include `.lastPlayed` (default-selected) plus `.titleAsc`, `.authorAsc`, `.dateAdded`, `.durationDesc`; single-select; not deselectable; auto-applies via `\_setSortOrder()` on tap

\- \[ ] Filter sheet Clear all re-selects the All pill (clears `\_statusFilter`)

\- \[ ] Backdrop tap, drag-down, and close X all dismiss the sheets; state is already live-applied so nothing to cancel

\- \[ ] Search bar expand/collapse animates (no layout jump)

\- \[ ] All colours use `colorScheme` tokens so light and dark themes both render correctly

\- \[ ] Placeholder colours allocated by render index (no on-screen collisions within each 8-tile run)

\- \[ ] Empty state messages use existing `\_noMatchesView()` logic

\- \[ ] Mini player wrapped in `BackdropFilter(ImageFilter.blur(...))` with solid-colour fallback

\- \[ ] `BookCover.\_placeholder()` renders a deterministic per-book colour (hashed from title) instead of a flat `surfaceContainerHighest` background

\- \[ ] The same book always gets the same placeholder colour across sessions

\- \[ ] `isEnriching` spinner and `enrichmentFailed` icon overlays are unaffected



