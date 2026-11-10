# ADR 0005: Mochy Poster Side Panel and Playerbar Shifting

- **Status**: Accepted
- **Date**: 2026-11-09
- **Deciders**: User, Antigravity AI Assistant

## Context
In the previous implementation of Nutsty (`shell.qml`), opening Now Playing (`isNowPlayingOpen = true`) completely replaces the browsing surface (`browsingContainer` opacity becomes 0.0), obscuring HomeFeed, Search, and Library navigation. Additionally, the bottom playerbar remains pinned to the bottom-center of the entire window, with no support for a persistent side-by-side inspection experience like desktop music applications (e.g., SimpMusic Desktop).

Furthermore, the user requested integrating Mochy-Music's signature "Poster" player aesthetic—featuring an asymmetrical circular arc artwork cut and dynamic, non-uniform random word scaling (`ExpressiveLyrics` / `wordScales`)—into this desktop inspection panel.

## Decision
We implement a dual-pane desktop architecture combining SimpMusic's side-by-side layout ergonomics with Mochy-Music's minimalist Poster and Expressive Typography style:

1. **Side-by-Side Coexistence**:
   - The main browsing area (`browsingContainer`) narrows smoothly when the side panel is open, occupying the remaining width (`parent.width - sidePanelWidth - gap`).
   - The new `MochySidePanel.qml` opens on the right side (~34% width, clamped `[380px, 440px]` according to the Swiss 12-column grid: 8 cols left, 4 cols right).
   - `PlayerBarBottom` dynamically shifts to horizontally center on the left browsing pane, providing visual harmony and space for the right panel.

2. **PlayerBar Click & Hover Differentiation**:
   - Clicking on the playerbar body (background, metadata, empty padding) toggles `MochySidePanel`. Hovering displays `Qt.PointingHandCursor` and a subtle luminance highlight.
   - Hovering over the center progress scrubber displays the time scrubber for seeking.
   - Clicking directly on the album artwork (`miniCover`) opens the full-screen view (`YTMusicNowPlayingView`).
   - Dismissing the side panel can be achieved by clicking the playerbar again, clicking the panel's close button ($\times$), or pressing `Escape`.

3. **Mochy Minimalist Poster Style**:
   - Top section features `CircleCover`: Album artwork clipped by an asymmetrical circular arc contour ($R \approx 1.14 \times W$) sweeping from the top-left corner.
   - Redundant transport controls are omitted because `PlayerBarBottom` remains fully accessible and active at the bottom left.
   - High-contrast poster typography for song title and artist.
   - Focused active lyric line presentation with Mochy's `wordScales` algorithm: shortest word ($\ge 3$ chars) scaled to 1.55x, words $\ge 11$ chars scaled to 0.74x, words $\ge 9$ chars scaled to 0.86x.
   - Active singing words glow in pure white (`#ffffff`) with phosphor bloom, with unsung words dimmed at 40% opacity.
   - Fallback when synced lyrics are absent: Renders an expressive poster title (`ExpressiveTitle`).

4. **Visual & Design System Compliance**:
   - Dark glass surface `Qt.rgba(0.06, 0.07, 0.09, 0.78)` with 1px hairline border `Qt.rgba(1, 1, 1, 0.12)`.
   - Concentric corner radius $R = 16\text{px}$ adhering to $R_{\text{con}} = R_{\text{mẹ}} - \text{Padding}$.
   - Strict bilingual `I18n.tr` support, zero emojis.

## Consequences
- **Positive**:
  - Uninterrupted browsing: Users can explore songs, playlists, and recommendations while simultaneously viewing the stylish poster and lyrics.
  - Optical balance: The playerbar is always centered relative to the active browsing content rather than floating awkwardly across panel boundaries.
  - Mochy's kinetic typography delivers an engaging, artistic lyric experience without clutter.
- **Tradeoffs**:
  - Requires responsive coordinate mapping for `PlayerBarBottom`'s `horizontalCenter` or `x` translation.
  - Smooth simultaneous resize animation for the browsing container and slide-in for the side panel.
