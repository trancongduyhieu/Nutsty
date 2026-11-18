---
name: Nutsty
description: Desktop music player whose glass window takes its colour from your wallpaper and the song playing.
colors:
  honey-amber: "#deb06c"
  honey-amber-hover: "#eed08c"
  ink-app: "#121212"
  ink-card: "#181818"
  ink-elevated: "#242424"
  ink-card-hover: "#282828"
  ink-highlight: "#2a2a2a"
  hairline: "#282828"
  divider: "#1f1f1f"
  velvet-backdrop: "#0a0b0e"
  text-primary: "#ffffff"
  text-secondary: "#b3b3b3"
  text-muted: "#727272"
  muted-rose: "#f43f5e"
  muted-rose-text: "#fda4af"
  muted-rose-text-hover: "#ffe4e6"
typography:
  display:
    fontFamily: "Instrument Serif, Noto Serif, serif"
    fontSize: "34px"
    fontWeight: 400
    lineHeight: 1.1
  headline:
    fontFamily: "Inter, SF Pro Display, sans-serif"
    fontSize: "28px"
    fontWeight: 900
    lineHeight: 1.15
  title:
    fontFamily: "Inter, SF Pro Display, sans-serif"
    fontSize: "15px"
    fontWeight: 700
    lineHeight: 1.3
  body:
    fontFamily: "Inter, SF Pro Display, sans-serif"
    fontSize: "13px"
    fontWeight: 500
    lineHeight: 1.4
  label:
    fontFamily: "Inter, SF Pro Display, sans-serif"
    fontSize: "11px"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "0.5px"
rounded:
  badge: "4px"
  button: "8px"
  card: "12px"
  pill: "16px"
  panel: "24px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "24px"
components:
  button-accent:
    backgroundColor: "{colors.honey-amber}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.button}"
    padding: "8px 16px"
    typography: "{typography.label}"
  button-destructive:
    backgroundColor: "{colors.muted-rose}"
    textColor: "{colors.muted-rose-text}"
    rounded: "{rounded.button}"
    padding: "8px 16px"
  card-track:
    backgroundColor: "{colors.ink-card}"
    rounded: "{rounded.card}"
    padding: "8px"
  card-track-hover:
    backgroundColor: "{colors.ink-card-hover}"
  chip-mood:
    backgroundColor: "{colors.honey-amber}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.pill}"
    padding: "6px 14px"
  nav-arrow:
    backgroundColor: "{colors.honey-amber}"
    size: "32px"
  window:
    backgroundColor: "{colors.ink-app}"
    rounded: "{rounded.panel}"
---

# Design System: Nutsty

## Overview

**Creative North Star: "The Glass on Your Wallpaper"**

Nutsty is a sheet of glass resting on the user's desktop. While nothing plays, the window is a dark acrylic pane at 58% (`Qt.rgba(0.04, 0.04, 0.06, 0.58)`) and the wallpaper shows straight through. Once a song plays, a velvet backdrop fades in over 400ms, the album art blooms into a blurred aurora behind the content, and every interactive control takes on the song's colour. The interface never brings its own palette. It borrows one from the wallpaper and the cover art, through OKLAB chromatic salience extraction.

The UI is dense and quiet, made of small type (11 to 13px), hairline borders and concentric rounded corners. Expression goes into the large moments: the Now Playing view, the Instrument Serif lyrics and the Spotify import stage. Controls stay translucent and tinted. They brighten on hover instead of rising off the surface.

Motion is quick and soft. Most transitions run 100 to 160ms with `Easing.OutCubic`, or `InOutQuad` for opacity and colour. Playful entrances use `OutBack`. The backdrop crossfades over 400ms and the cover over 900ms. Emphasized moves use the bezier `[0.42, 0, 0.16, 1]` or Material standard `[0.4, 0, 0.2, 1]`.

Confirmed rejections: emoji anywhere in the UI, dead grey buttons, capsule shapes used by default, and box-in-a-box nesting.

**Key Characteristics:**
- The accent is dynamic: the song's colour while playing, the wallpaper's colour while paused, and Honey Amber only as a fallback.
- Layered translucency (wallpaper, then cover aurora, then content) instead of opaque panels.
- Hairline 1px borders on every card, row, chip and cover.
- Concentric radii: inner radius = outer radius minus padding.
- Icons are SVG (`AppIcon.qml`, `assets/icons/*.svg`). Toggle icons are moving to animated Material Symbols (see Icons).

## Colors

The neutrals are near-black inks under one borrowed accent, plus muted rose reserved for danger.

### Primary
- **Honey Amber** (`honey-amber`): only the fallback accent. At runtime, `accentColor` comes from `nutsty_palette.json` (wallpaper) or the current cover (song). Controls use the accent at low alpha: 12% fill and 25% border at rest, 22% fill and 45% border on hover. A playing row's border is the accent at 45%.

### Neutral
- **Ink App** (`ink-app`): window base when glass is unavailable.
- **Ink Card / Card Hover / Elevated / Highlight**: tonal steps for cards, hover, floating surfaces and the active row.
- **Velvet Backdrop** (`velvet-backdrop`): the opaque layer that fades in under the cover aurora while playing.
- **Hairline** (`hairline`) and **Divider** (`divider`): structural lines. Over glass, use white at 7% (idle), 18% (hover) or 8% (planar dividers).
- **Text Primary / Secondary / Muted**: white for titles, about 70% grey for subtitles, about 45% grey for counters and dim icons.

### Danger
- **Muted Rose** (`muted-rose`): used for delete, sign-out and destructive actions only. The fill is 12% at rest and 24% on hover (shifting to `rgb(239,68,68)`). Text is `muted-rose-text`, or `muted-rose-text-hover` on hover.

### Named Rules
**The Borrowed Colour Rule.** Interactive colour always comes from `accentColor` (or `effectiveAccentColor`). Never hardcode a brand hue on a control.

**The No Dead Grey Rule.** Buttons, pills, selectors and popovers never use flat greys such as white at 6 or 8%, `#18181b` or `#27272a`. Tint them with the accent instead.

**The Pause Shows the Wallpaper Rule.** Backdrop opacity is tied to `win.currentTrack && win.isPlaying`, never to `currentTrack` alone, otherwise pausing locks the window to opaque black.

## Typography

**Display Font:** Instrument Serif (Noto Serif when the line contains Vietnamese diacritics)
**Body Font:** Inter (with SF Pro Display, then the system sans)
**Mono:** system `monospace` for timecodes and debug-style counters

**Character:** a compact, heavy-weighted sans runs the app, while an editorial italic serif takes over only for lyrics and cinematic moments.

### Hierarchy
- **Display** (Instrument Serif, about 34px): desktop lyrics, Now Playing lyric lines and cinematic headings.
- **Headline** (Black or Bold, 22 to 28px): page titles and greetings.
- **Title** (Bold or DemiBold, 14 to 16px): card titles and section headers.
- **Body** (Medium, 12 to 13px): track titles, list rows and settings labels.
- **Label** (DemiBold, 10 to 11px, slight tracking): artists, metadata, chips and counters.

### Named Rules
**The Diacritic Fallback Rule.** Any serif display text must switch to Noto Serif when the string contains Vietnamese diacritics, as `EnchantingSentence.qml` does. Instrument Serif renders them wrong.

## Layout

The window is a floating panel with a 24px outer radius. Inside it sit the sidebar (Playlists and Queue), a scrolling content column (home feed carousels and grids) and an optional right side panel (lyrics, queue, comments) that matches the content area's height. Spacing follows a 4/8pt rhythm, mostly 8 and 16. Regions are separated by whitespace and hairlines, not nested boxes. Scrolling lists fade at their edges when they can scroll further. That fade can be switched off in Settings, and Lite mode switches it off too. Horizontal carousels page with `NavArrowButton`, except in categorized search, which uses filter chips instead. On narrow widths, headers wrap rather than clip.

## Elevation & Depth

Depth comes from layered translucency and blur, not from drop shadows. There are three tiers: desktop wallpaper, then the cover art crossfade (900ms play/pause), then scrolling content. The Liquid Glass shader (`LiquidGlassContainer.qml`, `liquid_glass.frag`) adds SDF-rounded refraction, chromatic aberration at the rim and a rim sheen. Blur radii come in fixed buckets: 16 (subtle), 24 (medium), 48 (atmosphere) and 64 (deep). Shadows are rare and soft. They are used on toasts, the notification centre, generated covers and lyrics, where they serve legibility rather than lift.

### Named Rules
**The Never Fake Glass Rule.** Never replace Liquid Glass with a plain `Rectangle` of milky white at 10%. The glass backdrop source stays `visible: true` with `opacity: 0.001`. With `visible: false` the shader samples black.

**The Lite Mode Rule.** Every whole-window or per-frame effect must have a Lite mode path that keeps it static or switches it off.

## Shapes

Corners are gentle and concentric. Badges use 4 to 6px, buttons 8px, cards 10 to 12px, side panels and modals 16 to 18px, and the main window 24px. A child's radius equals its parent's radius minus the padding between them. Every card, row, chip and cover image has a 1px hairline. Images get their corners only from `RoundedImage.qml`, which handles HiDPI `sourceSize`, lazy layers, fallback icons and the border. Circles are kept for round icon buttons (nav arrows, play buttons) and avatars.

### Named Rules
**The Anti-Capsule Rule.** Never use `radius = height / 2` on buttons, cards or badges. Mood chips are the explicit exception.

## Components

### Buttons
- **Shape:** gently rounded (8px). Round icon buttons are circles.
- **Accent (default):** accent fill at 12% with a 25% accent hairline, white text and an accent-tinted icon. On hover the fill rises to 22% and the border to 45%, with colour transitions of 150 to 200ms.
- **Destructive:** Muted Rose, as described under Colors.
- **Shuffle:** `ShuffleButton.qml`, a Liquid Glass control with dynamic accent.

### Chips
- **Mood chips:** pill-shaped (the one capsule exception). The selected chip is filled with the accent and unselected chips are tinted. Switching a chip snapshots and resets the queue safely.

### Cards / Containers
- **Track card:** dark ink card (`TrackCard.qml`) with a full-bleed cover (`PreserveAspectCrop`) and a concentric inner radius. The hairline steps from 7% to 18% white on hover and becomes the accent at 45% while the track plays.
- **Popover / menu:** dark organic glass, `Qt.rgba(0.06 + a.r*0.08, 0.06 + a.g*0.08, 0.08 + a.b*0.12, 0.96)` with a 35% accent border. The selected item uses a 26% accent fill and a checkmark SVG. Hovered items use 14%.

### Navigation
- **Carousel arrows:** `NavArrowButton.qml` is a circle tinted with the accent. It scales to 1.06 on hover and fades to 28% opacity, disabled, at the scroll limit.
- **Sidebar and segmented tabs:** a rounded segmented bar with a highlight that slides to the selected item. The library remembers the last section.

### Icons
- **Static icons** stay SVG through `AppIcon.qml`.
- **Toggle icons** (like, shuffle, repeat, play state, nav tabs) follow Swiftify (`references/`): the variable font Material Symbols Rounded, bundled with the app and loaded with `FontLoader`, never a system install.
- A toggle animates the `FILL` axis from 0 (outline) to 1 (filled) and nudges `wght`, so the icon fills in rather than swapping. A press adds a small bounce (scale 0.9, then an `OutBack` spring back).
- Axes are set through `font.variableAxes`, which needs Qt 6.7. Set them from script inside `try`, so an older Qt keeps the outline icon instead of failing to load the file.

### Signature: Listener Card
A brushed-gold ID card (`ListenerCard.qml`) built from Honey Amber. A light band follows the tilt, and a strip on the right slides the owner's name past. Clicking it flips it to a Code 128 barcode on the back. The face renders into one supersampled layer with a transparent margin, so its edges stay clean while it turns in 3D. It appears in the first-run welcome (`WelcomeCardOverlay.qml`: the card flies in with gold confetti and a big "Chào xìn!" / "Hello!", then flies into the header avatar) and on the profile page. On the profile page it sits in a header of accent-tinted glass (never an opaque panel, since the wallpaper and song colours vary endlessly) over a white dot grid, with a giant NUTSTY in white at 6% drifting up the right edge.

### Signature: Desktop Lyrics
A layer-shell overlay (Linux) or frameless overlay (Windows) with four presets: Cinematic Serif, Apple Music DoF, Minimal Glide and Motion Typography. Legibility comes from layered cinematic shadows and never from a white halo.

## Do's and Don'ts

### Do:
- **Do** read `accentColor` from `win` and derive every control state from it at 12, 22, 26 or 45% alpha.
- **Do** put a 1px hairline on every card, row, chip and cover (white at 7% idle, 18% hover, accent at 45% active).
- **Do** compute inner radii concentrically, and use `RoundedImage.qml` for every rounded image.
- **Do** use SVG icons through `AppIcon.qml`, and pass all copy through `I18n.tr()`.
- **Do** provide a Lite mode path for any continuous or whole-window effect.

### Don't:
- **Don't** use emoji anywhere in the interface.
- **Don't** use dead grey buttons or popovers (white at 6 or 8%, `#18181b`, `#27272a`).
- **Don't** make capsules (`radius = height / 2`) except for mood chips.
- **Don't** nest boxes inside boxes. Separate with space and hairlines.
- **Don't** fake glass with a milky translucent rectangle, or hide the glass source with `visible: false`.
- **Don't** give lyrics a white halo. Use cinematic shadows.
