# Nutsty / FrostifyLocal — Domain Glossary (CONTEXT.md)

This document establishes the **Ubiquitous Language** for the Nutsty codebase. Every module, interface, route, and test must use these terms consistently. Do not invent synonyms or use overloaded terms.

---

## 1. Identity & Social Domain

### `User`
- **Definition**: An active entity in the Nutsty network identified strictly and uniquely by their **`canonical_user_id`** (UUID string).
- **Attributes**:
  - `canonical_user_id`: Immutable primary key (UUIDv4).
  - `username`: Alphanumeric display handle chosen by user (e.g., `thieucute`).
  - `discriminator`: 4-digit collision resolver (e.g., `1234`), forming `thieucute#1234`.
  - `avatar_url`: URL or local path to circular profile image.
  - `email`: Optional Google Account email used solely during initial auth linking.
- **Rule**: Never use `username` or `email` as a dictionary cache key or foreign key; always resolve to `canonical_user_id`.

### `Note`
- **Definition**: A temporary 24-hour status story published by a User.
- **Payload**: Short text snippet (max 120 chars) and an optional attached `Track` payload (`title`, `artist`, `cover_url`, `video_id`).
- **Lifecycle**: Self-expires after 24 hours. Cached in memory with an eviction timestamp.

### `Co-Listening` (Listen Along)
- **Definition**: A real-time synchronization session between two or more Users.
- **`Host`**: The user broadcasting their current track, playback state (`isPlaying`), and seek position.
- **`Guest`**: A user attached to a Host, whose local playback engine synchronizes passively with the Host's broadcast.
- **`Chat Bubble`**: A transient floating text message exchanged during co-listening, deduplicated by `(message_id, sender_user_id, timestamp)`.

---

## 2. Audio & Playback Domain

### `Track`
- **Definition**: A playable unit of music.
- **Types**:
  - `LocalTrack`: Resolved to a filesystem path (`/path/to/song.flac`), read via Mutagen metadata.
  - `OnlineTrack`: Identified by YouTube Music `video_id`, resolved dynamically to a streaming URL.

### `Queue`
- **Definition**: The active sequence of tracks currently managed for linear or shuffled playback.
- **Rule**: Distinct from `browsingTracks` (what the user is looking at on screen). Mutating the view must never mutate the active queue without explicit user playback action.

### `PlaybackState`
- **Attributes**: `isPlaying` (boolean), `currentPosition` (float seconds), `duration` (float seconds), `volume` (0-100), `isMuted` (boolean).

---

## 3. Architecture Vocabulary (`codebase-design`)

- **`Module`**: Any coherent body of code behind an interface (e.g., `SocialRelayCore`, `AudioPlaybackEngine`).
- **`Interface`**: Everything a caller must know to use the module correctly (methods, arguments, return types, invariants).
- **`Depth`**: The ratio of capability provided to the surface area exposed. A module is **deep** when it hides substantial logic (caching, polling, serialization) behind a tiny interface.
- **`Seam`**: The precise location where an interface lives and where an adapter can be substituted (e.g., `CloudRelayAdapter`).
- **`Adapter`**: A concrete implementation plugging into a seam (e.g., `CloudflareWorkerTransport` vs `InMemoryFakeTransport`).
- **`Locality`**: The degree to which related changes, bug fixes, and knowledge concentrate in a single module rather than scattering across callers.

---

## 4. YouTube Music Subsystems (Phase 2)

### `AudioStreamResolver`
- **Definition**: The subsystem responsible for converting a YouTube `video_id` into a direct, playable audio stream URL.
- **Responsibilities**: Android/iOS client spoofing, yt-dlp fallback, anti-bot challenge bypass, stream caching (`StreamResolverCache` with 5h TTL), and 403 CDN auto-recovery.

### `CatalogEngine`
- **Definition**: The subsystem responsible for catalog discovery, home shelves, mood pills, and categorized search.
- **Responsibilities**: Personalized home feed retrieval, mood feeds, radio queues, artist discographies, album details, and shelf item normalization.

### `SongEnrichment`
- **Definition**: The subsystem responsible for enriching track metadata beyond basic stream URLs.
- **Responsibilities**: Track credits/details, related track recommendations, like/dislike rating, Apple Music animated video artwork extraction, and synchronized lyrics.

### `YtmusicAuth`
- **Definition**: The subsystem responsible for managing Google Account session credentials.
- **Responsibilities**: Cookie validation, SAPISID hashing, authenticated client initialization (`ytmusicapi`), and credential export for `mpv` / `yt-dlp`.

---

## 5. Playback & Queue Subsystems (Phase 3)

### `PlaybackEngine`
- **Definition**: The dedicated frontend JavaScript engine (`components/playback_engine.js`) responsible for all audio playback orchestration, queue lifecycle management, and MPV daemon status reconciliation.
- **Responsibilities**: Track resolution (`isSameTrack`, `findLocalDownloadedTrack`), playback execution (`playOnlineTrack`, `playTrack`, `togglePlay`), queue navigation (`playNext`, `playPrev`, `seekAudio`), queue manipulation (`insertTrackPlayNext`, `appendTrackToQueue`, `removeTrackFromQueue`, `deleteLocalTrack`, `shufflePlayBrowsing`), and status event processing (`handlePlayerStatus`, `handleRadioResponse`).

---

## 6. Lyrics & Kinetic Typography Domain

### `SpatialTravelingWave`
- **Definition**: A continuous wave propagation model across a rhythmic phrase where adjacent words anticipate and follow the wave crest with smooth phase offsets and spring-damped velocity continuity (`SmoothedAnimation`), rather than jumping individually.
- **Attributes**:
  - `baselineY`: Resting baseline for all words ($0.0\text{px}$), eliminating stepped cliffs and trenches.
  - `peakLiftY`: Maximum crest elevation above baseline ($1.6\text{px}$).
  - `dynamicRange`: Total vertical swing capped at $1.6\text{px}$ (within user $\le 2.0\text{px}$ limit).
  - `smoothing`: 150ms critically damped spring animation on vertical translation and breathing scale.

### `Phrase`
- **Definition**: A cohesive rhythmic clause within a lyric line bounded by punctuation (`,`, `.`, `!`, `?`, `;`, `—`) or an inter-word vocal breath pause ($\Delta t > 0.35\text{s}$). Each phrase functions as an independent wave propagation envelope.

---

## 7. Synchronized Lyrics & Pipeline Domain

### `LyricsPipeline`
- **Definition**: The multi-tier progressive fallback resolution pipeline for obtaining lyrics with the highest possible timing fidelity.
- **Resolution Order (Auto Mode)**:
  1. `LocalDatabase` (Tier 0) / `LocalLrcFile` (Tier 1) / `DiskCache` (Tier 2).
  2. `SpotifySpclient` (Tier 3): Word-level timestamps via `spclient.wg.spotify.com` (active only when `SpotifySpdcCredential` is configured).
  3. `BetterLyricsTtml` (Tier 4): Word-level Apple Music TTML via reverse-engineered proxy endpoints.
  4. `LrclibApi` (Tier 5): Line-synchronized lyrics with strict duration-window matching ($\pm 12\text{s}$).
  5. `NeteaseCloudMusic` (Tier 6): Broad Asian pop / V-Pop coverage via `syncedlyrics`.

### `LyricsSourcePreference`
- **Definition**: The user-selected preference in settings controlling the priority strategy:
  - `"auto"`: Follows the canonical 7-tier pipeline order above.
  - `"spotify"` / `"betterlyrics"` / `"lrclib"` / `"netease"`: Forces the selected provider as primary, with graceful fallback to ensure lyrics are never lost.

### `SpotifySpdcCredential`
- **Definition**: The `sp_dc` cookie parameter extracted from Spotify Web Player. Exchanged dynamically for an ephemeral bearer `accessToken` to access `spclient.wg.spotify.com/color-lyrics/v2/`.
- **Validation**: Verified via a lightweight probe to `open.spotify.com/get_access_token` to confirm active status without exposing sensitive user telemetry.
