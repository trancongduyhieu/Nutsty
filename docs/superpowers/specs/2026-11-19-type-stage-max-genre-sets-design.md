# Type Stage Max: a set of doodles and peaks for each kind of song

Follow-up to `2026-11-19-type-stage-max-peak-props-design.md`. Preset 8 draws the same doodles
(stars, hearts, sparkles...) and the same 13 peak moves on every song. That fits sweet pop and
romance songs and not rock, rap or a club track. The user wants the song itself to pick a set:
the artist's genre is the base, and the lyrics and singing tempo correct it.

## Goals, non-goals

- Goals: 8 sets. Each set has its own doodles and its own peak moves. A sweet ballad by a rock
  band still gets the sweet set, and a song still gets a fitting set when there is no network.
- Not in scope: motion, camera, type, exits, duo and stack marks and line marks all stay as they
  are (the user picked "doodles + peaks" over "change the whole feel"). Only preset 8 changes,
  and preset 7 stays as it is. No manual set picker in settings for now.
- Anti-goals: no emoji anywhere (every shape is a pen stroke from `kinetic_stage.js`). A wrong
  guess must never look broken: the worst case is the sweet set, which is today's look.

## Approaches

1. **Genre plus lyrics and tempo (picked).** The artist's genre is looked up on iTunes (the same
   lookup and on-disk cache the stats page uses), and love words and tempo correct it.
2. Lyrics and tempo only: this works offline, but rock and pop lyrics read alike, so it cannot
   tell rough from sweet. It is kept as the fallback when the genre is unknown.
3. A per-song genre from YouTube Music: YouTube Music has no per-song genre, so this is ruled out.

## Where the genre comes from

- New route `GET /api/listening/genre?artist=<name>` next to `/api/listening/genres` in
  `backend/listening_routes.py`, registered in `backend/auth_server.py`.
  - It uses the same `nutsty_artist_genres.json` cache and `_lookup_genre`, under the same lock.
  - It answers `{ success, genre }`, with `genre` empty when the genre is unknown or the lookup
    failed.
  - It never looks up more than once per artist per run when the lookup fails, so it does not
    hammer the API.
- Windows runs `auth_server` in-process, so the route works there too, the same as the stats page
  today. The opt-in Rust daemon has no genre routes today and gets none here.
- Only the artist name is sent to iTunes, the same as the stats page.
- `LyricsPresetView` passes `currentTrack.artist` to `KineticStageView`. When the artist changes,
  the view asks the route once and keeps the answer for that artist.
- The preset preview card plays a demo song with no artist, so it uses lyrics and tempo only.

## Picking the set (pure JS in `kinetic_stage.js`, unit-tested with node)

1. `familyOf(genre)`: map the iTunes genre name, top level or subgenre (the full tree has
   about 525 names), to a family.
   - Use an explicit table for the 51 top-level names and their common subgenres.
   - Fall back to keyword rules (`rock`, `metal`, `punk`, `rap`, `hip-hop`, `house`, `techno`,
     `jazz`, `folk`...).
   - Anything else gives `null`.
2. `loveScore(lyrics)`: love words (vi + en: yêu, thương, nhớ, tim, hôn, em yêu, love, baby,
   heart, kiss, darling...) per content word over the whole song.
   - `sweetLyrics` = the score is over a threshold. The threshold is tuned on the 14 real `.lrc`
     files in the library.
3. `slow` / `fast` = the song's median letters per second against fixed bounds, using `rateOf`,
   which already exists.
4. The rule:
   - **Rough, street or dance family, and `sweetLyrics` and not `fast`:** sweet (a rock ballad
     gets hearts).
   - **Pop family (Pop, K-Pop, J-Pop, C-Pop...):** dance when `fast` and not `sweetLyrics`,
     otherwise sweet.
   - **`null` family:** sweet when `sweetLyrics`, dance when `fast`, otherwise sweet.
   - **Any other family:** keep it.
5. The set is picked once per song and passed in with `build(lyrics, { max: true, set })`. It is
   the same every time the song plays. If the genre answer comes after the lyrics, the view
   rebuilds once with the new set. This only happens the first time an artist is ever played.

## The 8 sets

Each set has 4 to 5 doodle kinds, which `doodle` and rush lines draw from, and 3 peak moves of
its own. Every set except sweet also has the 4 shared peaks: spot, rays, ink and stamp. The
existing rule against picking the same move twice in a row still applies.

| Set | Families | Doodles | Its own peaks (arrives, then payoff on the hero) |
|---|---|---|---|
| sweet | Pop slow/love, Singer/Songwriter, Vocal, Easy Listening, R&B soft, Christian, Children's | today's 8 | today's 13 (bulb + spot, rays, ink, stamp + 8 props) |
| rough | Rock, Metal, Punk, Grunge, EMO, Goth, Hard Rock | bolt, crack, spike, cross, bang | **shatter**: cracks run out from the hero, shards drop · **snap**: a string stretched over the word snaps, both ends curl back · **rip**: the word tears along a jagged line, the halves slip apart, then close |
| street | Hip-Hop/Rap and all its subgenres | crown, drip, arrow, tag, burst | **spray**: a spray can flies in, sprays a tag behind the word, the paint drips · **micdrop**: a mic drops onto the baseline, bounces, sound lines · **tapex**: two tape strips slap on crosswise over the corner |
| dance | Dance, Electronic, House, Techno, Trance, DnB, Dubstep, fast Pop | wave, dots, beam, grid, sparkle | **disco**: a disco ball lowers on its cord, turns, throws light flecks · **eq**: equalizer bars behind the word jump with the singing · **laser**: two beams sweep across the word and cross on it |
| calm | New Age, Ambient, Downtempo, Instrumental, Classical, Orchestral | cloud, drop, ripple, leaf, moon | **leaf**: a leaf drifts down side to side and lands on the word · **droplet**: a drop falls, ripples spread under the word · **moonrise**: a crescent rises behind the word |
| classic | Jazz, Blues, Funk, Disco, Motown, Soul, Doo Wop | note, notes, smoke, vinyl, swing | **vinyl**: a record rolls in, stops behind the word, spins · **smoke**: a curl of smoke rises off the word · **horn**: a horn pokes in and blows notes over the word |
| anime | Anime, Soundtrack, Disney, Kayokyoku, Enka | star4, speed, sweat, anger, sparkle | **flash**: a four-point star flashes on the hero with glints · **focus**: manga focus lines close in from the frame edges · **sakura**: petals drift across the word |
| folk | Folk, Country, Latin, Reggae, Worldwide, African, Brazilian, Indian and the other regional families | sun, sprout, bird, hill, star | **sunrise**: the sun rises behind the word, rays open · **flock**: a few birds fly over the word · **sprout**: a shoot grows out of the word top and opens two leaves |

That is 21 new peaks and about 30 new doodle shapes. Where it helps, the anger, sweat and star4
marks are drawn as plain pen shapes (curves and lines), never characters.

## How it is built (builder's calls, following preset 8 today)

- New doodles go into `markShape` / `doodleStrokes` as new `kind` cases. The doodle pool and
  `RUSH_KINDS` come from the set instead of the fixed arrays.
- New peaks go through the existing prop pipeline: entries in `PROP_D` and `PROP_FX`-style lists,
  shapes in `propShape`, and motion in `peakPieces` (up to 4 `PenMark` pieces in the hero word's
  box), plus hooks through `peakState` (`heroDy`, `heroRot`, `heroS`) and `letterState` when the
  word itself moves (rip). Then `KineticStageView.qml` needs no new items. If a move needs more
  than 4 pieces (flock, sakura, eq), merge its strokes into fewer pieces.
- Peaks respect `PROP_SETTLE` and land on the hero, and props never sit on other words' letters,
  as in the peak-props design.
- Sets live in one table `SETS = { sweet: { doodles, rush, peaks }, ... }`. Sweet is exactly
  today's arrays, so songs that resolve to sweet look the same as now.

## Verification

- Node tests:
  - `familyOf` on a sample of real iTunes names.
  - The rule table, with the user's real cache (Pop, Hip-Hop/Rap, J-Pop, Hard Rock, K-Pop, New
    Age).
  - `loveScore` on the 14 local `.lrc` files.
  - For every new peak: nothing before the start, it lands on the hero, and values stay finite.
  - Every doodle stays finite.
  - The NaN sweep extended over all sets.
- A Python test for the route, with the lookup mocked and no network.
- Render sheets of every new doodle and peak for the user to look at.
- `verify_codebase.py`, `verify_qml_compat.py`, qmllint, and a live look at one song per set.
