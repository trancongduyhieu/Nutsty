# Type Stage Max genre sets: implementation plan

**Spec (binding):** `docs/superpowers/specs/2026-11-19-type-stage-max-genre-sets-design.md`. Read it
first, whole. Also read `AGENTS.md`, plus `components/kinetic_stage.js` and
`components/KineticStageView.qml` around `PEAK_FX`, `PROP_FX`, `PROP_D`, `PROP_SETTLE`,
`peakOnAt`, `peakState`, `propShape`, `peakPieces`, `letterState`, `markShape`, `doodleStrokes`,
`DOODLES`, `RUSH_KINDS` and `tempoRoles`. The 8 existing props (balloon ... hand) are the model
to copy for every new peak.

## Global rules (every phase)

- One phase per run. Do only the phase you were given, then stop.
- **No emoji anywhere.** Every shape is pen strokes (lists of `{x, y}` points).
- Never hardcode `/home/...` paths. Every on-screen string goes through `I18n.tr(vi, en)`.
- Tests: `node scripts/test_kinetic_stage.cjs` must stay all green, with new tests added for the
  phase.
  - `scripts/` is gitignored, so add test files with `git add -f`.
- Before the commit, run all of these and get them clean:
  - `python scripts/verify_codebase.py`
  - `python scripts/verify_qml_compat.py`
  - `qmllint components/KineticStageView.qml components/LyricsPresetView.qml`
- Commit once at the end of the phase, Conventional Commits, on `main`.
  - Commit only the files you changed.
  - **Do not push.** Do not stash, reset or switch branches.
  - Do not edit `CHANGELOG.md` or `AGENTS.md`.
- If a test or check fails and you cannot fix it properly, stop without committing and write what
  failed to `scripts/render_peaks/out/PHASE_<n>_FAILED.txt`.
- Render sheets: the tools are in `scripts/render_peaks/`.
  - `gen_props.py`: renders a peak at 4 moments into `rp/` and pastes them into `props_*.png`
    sheets. It needs PySide6.
  - `render7.py` loads a QML file.
  - `long.json` is a sample song.
  - Adapt them as needed, for example by adding a per-fx "payoff time" for new peaks. Save every
    sheet to `scripts/render_peaks/out/<set>_*.png`.
  - Open each sheet and check it yourself. Props must not cover other words, must land on the hero
    word, must stay inside the frame, and must read as the object at a glance. Fix anything that
    does not before you commit.

## Phase 1: plumbing (no new drawings)

- **Backend:** `GET /api/listening/genre?artist=` in `backend/listening_routes.py`, registered in
  `backend/auth_server.py`.
  - It uses the same cache file, lock and `_lookup_genre` as `handle_get_listening_genres`.
  - It remembers failed artists in memory for this run, so it never retries them.
  - It returns `{success, genre}`.
  - Python test `scripts/test_genre_route.py` with `_lookup_genre` mocked and no network: a cache
    hit, a miss that gets saved, and a failure that is not retried.
- **`kinetic_stage.js`:**
  - `SETS` table: `sweet` = exactly today's `DOODLES`, `RUSH_KINDS` and `PEAK_FX`.
  - The other 7 sets for now = their shared peaks `["spot","rays","ink","stamp"]` plus today's
    doodles, as placeholders until their phase.
  - `familyOf(genre)` maps to `sweet|rough|street|dance|calm|classic|anime|folk|pop|null` (`pop`
    is a family, not a set).
  - `loveScore(lyrics)`, `pickSet(genre, lyrics)` with the rule from the spec, and
    `build(lyrics, {max, set})`.
    - When `set` is missing, use `pickSet(null, lyrics)`.
    - The doodle pool, rush kinds and peak pool all come from `SETS[set]`. Export these
      functions.
  - The `loveScore` threshold: tune it on real lyrics. Convert the `.lrc` files under `~/Music`
    with `scripts/render_peaks/lrc2json.py`, and record the scores you saw in a comment.
- **View:**
  - `KineticStageView` gets `property string artist`. When it changes, the view fetches the genre
    from the route; reuse the API base URL the app already uses elsewhere.
  - Keep the answer per artist and rebuild with the picked set when it arrives.
  - `LyricsPresetView` passes the current track's artist, wired from `DesktopLyricsWidget`'s
    `currentTrack`. Preview cards have no artist, and that is fine.
- **Tests:**
  - `familyOf` on real names: Pop, Hip-Hop/Rap, J-Pop, Hard Rock, K-Pop, New Age, Death
    Metal/Black Metal, House, Smooth Jazz, Anime, Country, and an unknown one.
  - `pickSet` covers every branch of the rule.
  - A song whose set is `sweet` builds the same piles and fx as before this phase.
  - The NaN sweep runs over every set.
- Commit: `feat(lyrics): preset 8 picks an effect set from genre, lyrics and tempo`

## Phases 2 to 8: one set each

| Phase | Set | Doodle kinds | Peaks |
|---|---|---|---|
| 2 | rough | bolt, crack, spike, cross, bang | shatter, snap, rip |
| 3 | street | crown, drip, arrow, tag, burst | spray, micdrop, tapex |
| 4 | dance | wave, dots, beam, grid, sparkle | disco, eq, laser |
| 5 | calm | cloud, drop, ripple, leaf, moon | leaf, droplet, moonrise |
| 6 | classic | note, notes, smoke, vinyl, swing | vinyl, smoke, horn |
| 7 | anime | star4, speed, sweat, anger, sparkle | flash, focus, sakura |
| 8 | folk | sun, sprout, bird, hill, star | sunrise, flock, sprout |

The motion for each peak is in the spec table.

- A doodle kind and a peak can share a name, for example leaf or vinyl. Keep them apart, by
  prefixing peak fx ids with the set where needed (`calm_leaf`).
- Reuse the existing kinds (cross, bang, burst, sparkle, speed, star) as they are.

For each set:

1. **Doodles.** Add the new kinds as `markShape` cases. They are drawn in one go like the
   existing ones, they grow in, and they stay finite.
2. **Peaks.** Each peak gets:
   - A `PROP_D` entry and a `propShape` shape.
   - Motion in `peakPieces`, at most 4 pieces; merge strokes when a move needs more.
   - Hooks through `peakState` and `letterState` when the word itself moves (rip).
   - It must respect `PROP_SETTLE`, land on the hero, and show nothing before its start.
   - The view needs no new items. If it truly does, keep the change small and say why in the
     commit body.
3. **Set entry.** Update the `SETS` entry: its doodles, rush kinds picked from its doodles, and
   peaks = its 3 + the 4 shared ones.
4. **Tests,** per new peak:
   - Nothing before the start.
   - At the hero time it is on the hero word.
   - Values stay finite over the whole line.

   Per doodle kind: finite at several sizes.
5. **Render sheets.** Render each peak and one sheet of all the set's doodles, look at them, and
   fix them.
6. **Commit:** `feat(lyrics): preset 8 <set> set, its doodles and peaks`.
