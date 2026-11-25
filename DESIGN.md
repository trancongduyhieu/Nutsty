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
  chart-1: "#3987E5"
  chart-2: "#D95926"
  chart-3: "#199E70"
  chart-4: "#C98500"
  chart-5: "#D55181"
  chart-other: "#5A5A5A"
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
  stat-card: "22px"
  setting-card: "20px"
  setting-sub: "12px"
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
  card-stat:
    rounded: "{rounded.stat-card}"
    padding: "18px 22px"
  card-setting:
    rounded: "{rounded.setting-card}"
    padding: "18px 20px"
  card-setting-sub:
    rounded: "{rounded.setting-sub}"
    padding: "8px 12px"
  value-display:
    typography: "{typography.headline}"
    textColor: "{colors.text-primary}"
  window:
    backgroundColor: "{colors.ink-app}"
    rounded: "{rounded.panel}"
---

# Design System: Nutsty

## Overview

**Creative North Star: "The Glass on Your Wallpaper"**

Nutsty is a sheet of glass resting on the user's desktop. While nothing plays, the window is a dark acrylic pane at 58% (`Qt.rgba(0.04, 0.04, 0.06, 0.58)`) and the wallpaper shows straight through. Once a song plays, a velvet backdrop fades in over 400ms, the album art blooms into a blurred aurora behind the content, and every interactive control takes on the song's colour. The interface never brings its own palette. It borrows one from the wallpaper and the cover art, through OKLAB chromatic salience extraction.

The UI is dense and quiet, made of small type (11 to 13px), hairline borders and concentric rounded corners. Expression goes into the large moments (the Now Playing view, the Instrument Serif lyrics, the recap, the listener card) and into previews that perform their setting live, as Mochy's customise screen does (see Signature Moments). Controls stay translucent and tinted. They brighten on hover instead of rising off the surface.

Motion is quick and soft. Most transitions run 100 to 160ms with `Easing.OutCubic`, or `InOutQuad` for opacity and colour. Playful entrances use `OutBack`. The backdrop crossfades over 400ms and the cover over 900ms. Long moves (page morphs, cards opening, charts growing, the welcome card's flight) use Mochy's emphasized decelerate `[0.2, 0, 0, 1]`: 420ms to open a card, 320ms for a chevron, 900ms for a chart to grow, 1400ms for a figure to roll. Older code still uses `[0.42, 0, 0.16, 1]`; new code uses the Mochy curve.

**Design lineage: Mochy for motion and layout, Swiftify for icons, the glass is Nutsty's own.** New screens take their layout and choreography from Mochy (`references/Mochy-Music/`): big bold titles that a scroll can collapse, cards that open in place into the detail behind them, figures that roll in, charts that grow in, and Material 3's emphasized-decelerate curve `[0.2, 0, 0, 1]` for anything that moves a long way. Swiftify (`references/swiftify/`) has no glass at all; it only sets the toggle icons and a few Material You motions, such as icon morphs. The Liquid Glass surfaces are Nutsty's own and owe nothing to either app. Both references are studied and rebuilt in QML, never pasted: their palettes give way to Nutsty's borrowed accent.

**Mochy's settings and library, as studied on the phone (Nov 2026).** Mochy's surfaces are opaque `#1C1C1E` cards on pure black and monochrome controls. Nutsty keeps Mochy's *structure* and swaps the *material*: every card is accent-tinted glass with a hairline, every lit control takes the accent. What Nutsty copies is the anatomy: one card per setting (never an iOS grouped list of thin rows), a bold title, a large live value, and a small preview of the result on the card's right half.

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

### Data
- **Mark** (derived): the accent lifted to 70% lightness (`Qt.hsla(hue, max(0.55, sat), 0.70)`), so peaks read on dark cards whatever the wallpaper. One mark per chart: the peak bar, the top rank's share bar, the line itself. Everything else is neutral white at 20 to 40%.
- **Chart 1 to 5 / Other**: the categorical order for genres, kept from Mochy because it is validated for colour blindness. Identity is never colour alone: a legend names the top five.

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
Settings cards (the Mochy anatomy, see Components) use 20px, and the sub-cards inside them 12px, which is 20 minus their 8px inset.

**The Anti-Capsule Rule.** Never use `radius = height / 2` on buttons, cards or badges. The exceptions are mood chips and, from Mochy, switches, filter chips and the segmented control's track and selected pill: those are capsules by nature.

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

### Signature: Setting Card (from Mochy)
The settings and sync screens are built from these, one card per setting, stacked with 12px gaps and grouped under a large bold section title (Headline) with a hairline divider between groups. Never an iOS grouped list of 60px rows with round icons: that read as generic and was rejected.
- **Anatomy:** title top-left (Title, Bold 17 to 20px), an optional reset icon right after it, the description under it in Text Secondary (12px, at most three lines), the switch top-right. The left half carries words, the right half a **preview**: a small schematic of what the setting changes (wireframe lines, a blurred thumbnail, the real cover art), drawn in white at 15 to 40% or the real image.
- **Value display:** a setting with a value shows it large at the bottom-left (Headline, Black 28 to 32px: "25px", "1x", "Flagship"). A slider setting puts the value right-aligned on the title line instead, with a 3px track (white 20%) filled with the accent, and min and max labels under its ends in 11px muted.
- **Sub-cards:** options that only matter when the parent is on sit in sub-cards inside it, inset 8px, radius 12, fill accent at 8% with a 7% hairline. One level only; this is the one sanctioned box-in-a-box.
- **Segmented control:** a capsule track (accent 12%) with a capsule selected pill (accent fill, white text), for two or three choices such as Low / High.
- **Style picker:** a horizontal carousel of preview cards (name large at the bottom-left, a wireframe of the layout on the right). The chosen card gets a 2px accent outline, and a muted caption sits under the strip ("vuốt, rồi chạm vào một kiểu để dùng").
- **Surface:** accent-tinted glass (accent at 8%, hairline white at 7%, 18% on hover), never Mochy's opaque grey.

### Signature: Source Tiles (from Mochy's library)
Content that comes from several services (Spotify, YouTube, Apple Music, Tidal) is a two-column grid of 16px tiles under an uppercase section label (Label, DemiBold 11px, tracking 0.08em). Each tile has the service mark and name in bold on top, a large count under it (Headline), and up to two covers peeking from the bottom-right corner. Service marks are the one place brand colour appears; the tile itself stays glass. Filter chips above the grid are capsules: glass at rest, accent fill when selected. A wide card with the service logos in a row invites an import when the library is empty.

### Signature Moments (read from Mochy's code, Nov 2026)
Read from `references/Mochy-Music` (v8.3.2 source; the phone runs 8.4.2). Mochy is **not** animated everywhere: only 25 of its 1036 Kotlin files run an endless animation, and the settings list (`MochySettingsScreen.kt`) has just a 180ms fade. What it does is narrower and is the thing to copy:
- **A preview performs the setting.** In the customise screen (`gesture/CustomisationLivePreviews.kt`) each card's right half shows the setting working: a dot hopping side to side at the chosen animation speed, a dot sharpening and blurring back like a lyric line, the real glass blurring a tiny screen, a lyric line singing in each style, the status bar sliding away when its switch goes off. Motion comes from the value, never decoration. The cover-rounding swatch is one big corner bleeding off the card's top-right edge, with a white arc hugging its bend, redrawn from the slider value.
- **Loops run only while seen.** Every looping preview waits until it is on screen (`rememberOnScreen`) and pauses while held; the marquee "stops with the banner, which leaves composition as it scrolls away". Nutsty: a loop binds `running` to the item's visibility and Lite mode.
- **Drifting strip** (`library/LibraryImport.kt`, `ProviderMarquee`): the four service icons as 56px squircles 14px apart, moving left linearly, 2.6s per icon, as many sets as cover the card plus one, so the wrap never shows; under it "Import your music here!" in Bold 21. While an import runs the banner crossfades into an 8px white bar (350ms) and "Adding 12 of 40 tracks from Spotify". Nutsty has only `spotify-symbolic.svg` so far; other marks are needed before building it.
- **Version ring** (`update/VersionRing.kt`): not a progress ring. A 46px band at white 8% with the version in bold monospace at 30% running round it ("8.4.2 · " repeated, the leftover space is the visible gap), one turn every 26s; scrolling the sheet zooms it 1.42x, lifts it 72px and blurs it out, and the turn stops once it is gone.
- **Nutsty already owns the rest of the kit**, ported from Mochy's recap and profile: `Odometer.qml` (Mochy's `OdometerNumber`), `ShapeLoader.qml`, `ShimmerText.qml`, the giant ghost word and dot grid, the card flight, scratch to reveal, the receipt. Settings, sync and import never used them; that, not the cards, is why they read generic.

### Signature Type (Mochy's text layouts)
From `settings/ProfileScreen.kt` (`ListeningTimeCard`, `TimeValue`, `VersionCard`) and the recap: a figure gets a layout of its own, never "Label: value".
- **Figure with a shrunk unit:** the number Bold 44 at -2 tracking, rolling as an odometer; the unit Bold 18 on its bottom edge ("23h"). Two figures are split by a 1px rule at white 40%, 34px tall ("23h | 29m"). Figures scale with the card width (0.72 to 1.2x) and step down 10 to 20% for 3 to 4 digit values.
- **Monospace side caption:** the caption in monospace 14, grey, right-aligned and broken by hand into lines, filling the space beside the figure ("Total Listening\ntime"). A hairline and a muted "View Stats  >" link close the card.
- **Version as a figure:** a small SemiBold 13 label over the version in Bold 44, build suffix dropped.
- **Tag on the title, story sentence, machine text, spaced-caps prompt:** as in the recap (`RecapStory.qml`): a small tag at the cap height beside a big title ("Thống kê" with "2026 Re'cap"); small lead line, one huge word, small follow-up; monospace IDs and timestamps, and a word turned 90 degrees along a card's edge; "CHẠM ĐỂ KẾT THÚC" tracked wide.
- Still through `I18n.tr()`: each layout must hold in both languages, so test the long one.

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

### Signature: Stats
`StatsPage.qml`, opened from the profile ("Xem thống kê chi tiết"), follows Mochy's Stats screen. A 44px "Thống kê" title with "{year} Re'cap >" opening a month or year picker. Under it a ruler: every month (or year) laid on one line with a tick a day, the chosen one named large at the left; dragging lifts the marker to the middle, letting go springs to the nearest period with something in it, and a tap or the wheel picks one. Nutsty's own touch is that each day's tick is as tall as that day's listening, in the mark colour, so the ruler doubles as a chart of the year. Then six cards (total, genre, artist, song, weekday, hour) of accent-tinted glass at 22px radius, each opening in place into its detail (a line of every day, the top ten with share bars, weekday bars, a 24-hour line), with an "Expand all" chip, a rolling odometer for the total and a note that nothing leaves the computer except artist names for genre lookup. Lite mode skips the rolls and grows.

### Version and About
A glass card under the listening total: "Phiên bản & thông tin ứng dụng", the version large in tabular figures, and an accent pill "Giới thiệu" that opens What's New.

### Signature: Desktop Lyrics
A layer-shell overlay (Linux) or frameless overlay (Windows) with four presets: Cinematic Serif, Apple Music DoF, Minimal Glide and Motion Typography. Legibility comes from layered cinematic shadows and never from a white halo.

## Do's and Don'ts

### Do:
- **Do** read `accentColor` from `win` and derive every control state from it at 12, 22, 26 or 45% alpha.
- **Do** put a 1px hairline on every card, row, chip and cover (white at 7% idle, 18% hover, accent at 45% active).
- **Do** compute inner radii concentrically, and use `RoundedImage.qml` for every rounded image.
- **Do** use SVG icons through `AppIcon.qml`, and pass all copy through `I18n.tr()`.
- **Do** provide a Lite mode path for any continuous or whole-window effect.
- **Do** give a setting card a preview of its effect and its value in large type, as Mochy does; words on the left, result on the right.
- **Do** make a setting's preview perform the setting from its live value, and run any loop only while it is on screen and Lite mode is off.

### Don't:
- **Don't** use emoji anywhere in the interface.
- **Don't** use dead grey buttons or popovers (white at 6 or 8%, `#18181b`, `#27272a`).
- **Don't** make capsules (`radius = height / 2`) except for mood chips.
- **Don't** nest boxes inside boxes. Separate with space and hairlines. The single exception is a setting card's sub-cards (one level, concentric).
- **Don't** build settings as iOS grouped lists of thin rows with round icons. Use one setting card per setting, Mochy's anatomy.
- **Don't** fake glass with a milky translucent rectangle, or hide the glass source with `visible: false`.
- **Don't** give lyrics a white halo. Use cinematic shadows.
- **Don't** add motion as decoration: in Mochy every loop shows something real (a setting, the services, the version).
