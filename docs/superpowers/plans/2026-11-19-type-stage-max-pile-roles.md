# Type Stage Max Pile Roles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In preset 8 each pile gets a role from the singing tempo (peak / rush / duo / stack) and draws that role's own effects.

**Architecture:** `build()` in `components/kinetic_stage.js` measures each line's tempo, forces peak and rush lines into solo piles, and tags every pile with `role` and `fx`. New pure functions of t (`peakState`, `peakStrokes`, `wordStrokes`, `pileState`, `pileStrokes`) feed `components/KineticStageView.qml`, which adds a bulb/cone/peak-mark layer on the hero word, an ink layer under the line, and a pile overlay for duo/stack marks. Preset 7 (`max` false) is untouched.

**Tech Stack:** Quickshell QML (Qt 6.12), `.pragma library` JS, `PenMark.qml` (Shape + CurveRenderer), Node for the unit test.

**Spec:** `docs/superpowers/specs/2026-11-19-type-stage-max-pile-roles-design.md`

## Global Constraints

- Preset 7 output must not change: with `max` false, piles stay random solo (`M.r(seed,20,420) < 0.35`), no `role`/`fx` logic runs.
- Everything is a pure function of t (seek/loop never pops); hash noise from `M.r`/`M.rs`, no `Math.random`.
- No emoji, no hardcoded `/home` paths; no new UI strings (all drawing is strokes).
- New shared QML pieces go in their own file listed in `components/qmldir` (hot-reload footgun), never inline `component X:`.
- Tempo constants, verbatim from the spec: slow `<= 0.75 * med`, peak line `>= 1.2 s`, previous 1–2 lines mean `>= 1.1 * med`, rush `>= max(1.35 * med, 80th percentile)`, no rush right after a rush pile. Peak base x1.4 centred; rush base x1.22; duo/stack at most 5 doodles per pile; rush up to 10 word doodles.
- Before each commit: `python scripts/verify_codebase.py`, `python scripts/verify_qml_compat.py`, `qmllint components/KineticStageView.qml components/PenMark.qml`, `node scripts/test_kinetic_stage.js`. Commits: Conventional Commits, end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, push to `main`.

## Review Focus

- A song whose every line is fast (rap): rush must not swallow it; expect at most ~25% rush piles (test in Task 1).
- A line with no letters ("♪", "...") or near-zero duration: rate must be finite, never a peak or rush (test in Task 1).
- A peak whose hero is censored or on a decode line (no hero mark allowed): pool falls back to `ink` only, nothing NaN (test in Task 2).
- Very short lyrics (1–2 lines): no previous lines to compare, no crash, no peak (test in Task 1).
- The pile before a bulb peak with a pen exit leaves too little time: it must fall back to the lift as today and the bulb still drops (NaN sweep in Task 3 covers the timing).

---

### Task 1: Tempo roles and piling

**Files:**
- Create: `scripts/test_kinetic_stage.js`
- Modify: `components/kinetic_stage.js` (constants block near line 70; `build()` pile loop near lines 300–316)

**Interfaces:**
- Produces: `rateOf(L) -> number` (letters per second: `bare(text)` of non-paren words without whitespace, over `max(0.1, L.end - L.start)`); `tempoRoles(lines) -> string[]` (`"peak" | "rush" | ""` per line); `TEMPO = { slow: 0.75, prevFast: 1.1, fast: 1.35, fastPct: 0.8, peakMinDur: 1.2 }`. In max mode every pile has `P.role` in `"peak" | "rush" | "duo" | "stack"`; a peak or rush pile holds exactly one line; a pile ending with one ordinary line is `"stack"`.

- [ ] **Step 1: Write the failing test** — `scripts/test_kinetic_stage.js`, loading `motion_recipes.js` and `kinetic_stage.js` into `vm` contexts the way the scratchpad `ktest2.js` does (strip `.pragma`/`.import`, pass `M`). Helpers: `song(lines)` builds `[{time, text}]`. Tests:
  - `peak after fast`: 4 lines of ~40 letters each 1.6 s apart, then `"em vẫn ở đây"` with the next line 3.5 s later → the pile holding that line has `role === "peak"` and `lines.length === 1`.
  - `rush`: 6 medium lines (~20 letters / 2.5 s) and one line of ~60 letters in 2 s → its pile `role === "rush"`, `lines.length === 1`; two such fast lines in a row → the second is not `"rush"`.
  - `rap cap`: 20 lines of ~55 letters each 2 s apart → piles with role `"rush"` ≤ 25% of piles.
  - `no letters`: a song containing `"♪"` and `"..."` lines → `rateOf` finite for all, none of those lines is peak or rush.
  - `short songs`: 1-line and 2-line songs build with no role `"peak"`.
  - `no random solo in max`: 12 lines of equal tempo → no pile has role peak/rush; every pile role is `"duo"` when it has 2 lines, else `"stack"`.
  - `preset 7 unchanged`: `build(ly, {})` on the demo set → every pile's `solo === (M.r(P.lines[0].seed,20,420) < 0.35)` and `P.role === undefined`.
  Print `ok <name>` per test, `process.exit(1)` on any assert failure.

- [ ] **Step 2: Run test to verify it fails**
Run: `node scripts/test_kinetic_stage.js`
Expected: FAIL (`rateOf is not defined` / role undefined)

- [ ] **Step 3: Implement `rateOf`, `tempoRoles` and the max-mode piling in `build()`**
In max mode a line whose role is peak or rush always starts its own pile and closes it (`max: 1`); any other line joins the current non-solo pile as today (up to `PILE_MAX`, broken by `PILE_GAP`). Median and 80th percentile over all lines with rate > 0. Peak needs `i >= 1`. Base: peak `round(base * 1.4)`, rush `round(base * 1.22)`. Keep the old coin-toss branch verbatim for `!maxi`.

- [ ] **Step 4: Run test to verify it passes**
Run: `node scripts/test_kinetic_stage.js`
Expected: every line `ok ...`, exit 0

- [ ] **Step 5: Commit** — `feat(lyrics): preset 8 piles take a role from the singing tempo`

### Task 2: Role effect picks and dressing data

**Files:**
- Modify: `components/kinetic_stage.js` (constants; pile loop after `P.shot`; per-line doodle block)
- Test: `scripts/test_kinetic_stage.js`

**Interfaces:**
- Consumes: `P.role` from Task 1.
- Produces: `PEAK_FX = ["bulb","spot","rays","ink","stamp"]`, `DUO_FX = ["arrow","brace","versus","swoop","pair"]`, `STACK_FX = ["notebook","numbers","stairs","frame","draft"]`, `PILE_DOODLES = 5`, `RUSH_DOODLES = 10`. `P.fx` (string, `""` for rush); `L.wordMarks` (object `wi -> "tick" | "ring"`, rush only); `L.boil` (8, or 12 on rush); rush `L.lineMark = "rushline"`; peak lines: `L.doodles = []`, `L.lineMark = ""`, `L.hiWi = -1`, `P.frameX = 0`; peak exit `"smudge"`, rush exit `"strike"` (both still fall back to `"lift"` when tight); the pile right before a `bulb` peak always exits `"lift"` (the hard cut into the dark). `L.heroWi` (index of the top-scored word) on every line.

- [ ] **Step 1: Write the failing tests**
  - `fx never repeats per role`: a 60-line synthetic song mixing fast runs, slow lines and medium lines → for each role, consecutive piles of that role never share `fx`; all `fx` values come from their pool.
  - `pile doodle cap`: every duo/stack pile → sum of `L.doodles.length` over its lines ≤ 5.
  - `rush dressing`: the rush line has `doodles.length === min(10, mainIdx.length) + 2`, the last two of kind `"speed"` with spots `"left"`/`"right"`; each word doodle `at === word.start - LEAD` and spot in `above|below`; `Object.keys(wordMarks).length === mainIdx.length` (non-censored); `boil === 12`; `lineMark === "rushline"`.
  - `peak fallback`: a peak line whose top word is profane → `P.fx === "ink"`.

- [ ] **Step 2: Run to verify it fails** — `node scripts/test_kinetic_stage.js`, expected FAIL on `fx`.

- [ ] **Step 3: Implement** — pick per role with `M.r(P.seed, 31, 431)` into the pool, stepping past the last fx of the same role; peak pool is `["ink"]` when the line has no usable hero (`heroOk` false, kept on `L.heroOk`). Doodle cap: drop the latest-timed doodles of the pile until ≤ 5. Add `"rushline"` to `markShape` (a zigzag stroke plus a lower under stroke, 2 strokes) and give it `ld = 0.45` in `markProg`.

- [ ] **Step 4: Run to verify it passes** — all `ok`.

- [ ] **Step 5: Commit** — `feat(lyrics): preset 8 roles pick their own effects`

### Task 3: Peak runtime (bulb, spot, rays, ink, stamp)

**Files:**
- Modify: `components/kinetic_stage.js` (`markShape`, `wordFx`, `film`, `camera`, new functions)
- Test: `scripts/test_kinetic_stage.js`

**Interfaces:**
- Consumes: `P.fx`, `L.heroWi`.
- Produces:
  - `peakState(L, t) -> { on: bool, lit: 0..1, dark: 0..1, bulbY: em, bulbTilt: deg, cone: 0..1, heroS, restA }` — zero-effect defaults (`lit 1, dark 1, heroS 1, restA 1, cone 0`) for any non-peak line.
  - `peakStrokes(L, t, part, w, h) -> strokes` for `part` in `"bulb" | "cord" | "rays" | "ring" | "stamp" | "ink"`; `[]` when the pile's fx does not use that part.
  - Timing: `dropAt = L.enterAt`; `onAt = max(heroWord.start - LEAD, dropAt + 0.7)`.
- Bulb motion (pure, τ = t − dropAt, in hero-px units, rest = 0): `bulbY = -4.5 * exp(-4τ) * cos(7τ)`; `bulbTilt = 14 * exp(-2.5τ) * sin(6τ + 0.5)`. Before `onAt`, `dark = 0.25` (line drawn in the dark), `cone = 0`; after, `lit` eases to 1 over 0.12 s, `cone = lit`.
- `spot`: ring drawn over the hero's sung time; once closed `restA = 0.3` for non-hero words and `heroS = 1.5` (outBack over 0.3 s). `rays`/`ink` progress with `(t - L.start) / (L.end - L.start)`. `stamp`: thick tilted box, lands in 0.12 s at hero land, camera shake one beat (`camera` adds `±4 px` decaying over 0.25 s).
- `wordFx`: multiply `alpha` by `dark` (peak) and by `restA` for non-hero words; multiply `s` by `heroS` on the hero.
- `film`: at `onAt` (bulb) or hero land (others) → `chroma 5`, `bulge 0.07`, decaying like slam hits.

- [ ] **Step 1: Write the failing tests**
  - `bulb springs`: `peakState` at τ = 0 has `bulbY < -4`; some τ in (0, 0.6) has `bulbY > 0` (overshoot); at τ = 1.5 `|bulbY| < 0.05` and `|bulbTilt| < 0.5`.
  - `bulb lights on cue`: `on === false` at `onAt - 0.05`, `on === true` and `cone > 0.9` at `onAt + 0.2`.
  - `spot dims the rest`: after the ring closes, `wordFx` of a non-hero word has alpha ≤ 0.31 and the hero `s ≥ 1.45`.
  - `non-peak lines untouched`: for a duo line `peakState` returns the defaults and `peakStrokes` returns `[]` for every part.
  - `NaN sweep`: for both `max` true/false, t from 0 to 40 step 0.017, every number returned by `film`, `lineState`, `camera`, `wordFx`, `letterState`, `peakState`, `peakStrokes` (all parts, box 300×200) is finite.

- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement** the shapes (`"bulb"` round glass + 2-line screw base, `"cord"` a vertical wavy line from the top, `"rays"` 14 focus lines from 0.25–0.5 to 1.0 of the box radius, `"inkfill"` dense zigzag across the box, `"stamp"` the box shape with 3 passes) and the functions above.
- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Commit** — `feat(lyrics): preset 8 peak lines, a bulb, a spotlight, rays, ink and a stamp`

### Task 4: Rush runtime and per-word marks

**Files:**
- Modify: `components/kinetic_stage.js` (`drawStrokes`, `camera`, `film`, new `wordMarkKind`/`wordStrokes`)
- Test: `scripts/test_kinetic_stage.js`

**Interfaces:**
- Produces: `wordMarkKind(L, wi) -> string` (`L.heroMark` when `wi === L.ringWi`, else `L.wordMarks[wi]`, else `""`); `wordStrokes(L, t, wi, w, h) -> strokes` (the hero keeps today's `penStrokes(L,t,"hero",…)` timing; tick/ring marks draw in 0.18 s from that word's land). `drawStrokes` gains a 7th param `boilRate` (default 8; `penStrokes`/`doodleStrokes` pass `L.boil || 8`). Rush `camera`: per word land `rot += ±1.2°` and `s *= 1 + 0.02` decaying `exp(-since*14)`. Rush `film`: per word land `chroma = max(chroma, 2.5 * exp(-since*10))`.

- [ ] **Step 1: Write the failing tests** — `wordStrokes` is `[]` before a rush word lands and non-empty 0.2 s after; `wordMarkKind` on a duo line equals the old hero mark for `ringWi` and `""` elsewhere; boil: strokes of a rush line differ between t and t + 1/12 + ε but a normal line's are equal between t and t + 0.05 within one 1/8 slot; NaN sweep extended with `wordStrokes`.
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Commit** — `feat(lyrics): preset 8 rush lines, a mark on every word`

### Task 5: Duo and stack pile marks

**Files:**
- Modify: `components/kinetic_stage.js` (`markShape` digits, `lineState` versus offset, new pile functions)
- Test: `scripts/test_kinetic_stage.js`

**Interfaces:**
- Produces: `pileState(P, t, W, H, anchorY) -> { alpha, rects: [{ x, y, w, h }] }` — one rect per line already in, in stage px before the camera; `w = L.estW * L.base * fitOf(L, W) * s`, centre `(W/2, anchorY + lineState(L).y)`; `alpha` follows the pile's exit (1 − exit progress). `pileStrokes(P, t, W, H, anchorY) -> strokes` in stage px, `[]` unless role is duo/stack.
  - duo `arrow`: curve from the right end of rect 0 to the left start of rect 1, arrowhead, drawn as line 2 enters. `brace`: `}` right of the union of both rects plus a star at its tip. `versus`: `lineState` gives slot 0 `dx = -0.06 W`, slot 1 `dx = +0.06 W`, plus a `/` slash between the rects. `swoop`: S-curve from under rect 0 to under rect 1. `pair`: both lines get the hero `ring` (set in build), plus a dashed connector from rect 0's bottom to rect 1's top on the right.
  - stack `notebook`: left margin brace over the union, a tick right of each rect when its line ends. `numbers`: `"n1" | "n2" | "n3"` digit shapes left of each rect as it enters. `stairs`: small arrow from rect k−1 to rect k. `frame`: rough box round the union (pad `0.25 base`) with a star on a corner. `draft`: strike through rect 0 when line 3 lands, alpha handled by the view (0.5).
- [ ] **Step 1: Write the failing tests** — for a 2-line pile with each duo fx and a 3-line pile with each stack fx: `pileStrokes` is `[]` before line 2 (resp. 1) enters and non-empty after; every point lies within `[-0.1W, 1.1W] × [-0.1H, 1.1H]`; `pileState(...).rects.length` equals the lines already in; peak/rush piles give `[]`; NaN sweep extended with `pileState`/`pileStrokes`.
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Commit** — `feat(lyrics): preset 8 duo and stack piles get marks that tie their lines`

### Task 6: View wiring

**Files:**
- Modify: `components/KineticStageView.qml`

**Interfaces:**
- Consumes: everything above.
- In `wordComp`: the hero `PenMark` becomes `kind: Stage.wordMarkKind(line, wi)` and `strokes: Stage.wordStrokes(...)` (shows for rush ticks/rings too, box sized like `ticks` for `"tick"`, like `ring` for `"ring"`). On the hero word of a peak (`line.heroWi === wi && line.pile.role === "peak"`): `spot`/`stamp` `PenMark` (box `1.8×` / `1.25×` the word), `rays` `PenMark` (box `6 px × 3 px` centred, `z: -1`), and for `bulb` an `Item` at `y = bl - px*1.9 + peakState.bulbY*px`, rotated `bulbTilt` round its top, holding the cord, bulb and a lit ray burst (`PenMark`s), plus a `Shape` light cone (filled trapezoid, `LinearGradient` accent alpha `0.28 * cone` → 0) from the bulb down to the word.
- In `lineBody`: an ink `PenMark` (`peakStrokes(...,"ink",…)`, `z: -1`, accent alpha 0.22, `penW = base * 0.5`, FlatCap) over `wordsRow`.
- In `stage`: a second `Repeater { model: visibleLines }` whose delegate draws only when `line.slot === 0` and role is duo/stack — one full-size `PenMark` with the pile camera transform (`Stage.camera` of that line), `opacity: pileState.alpha`, `strokes: Stage.pileStrokes(...)`, ink accent 0.85 (`draft` at 0.5).

- [ ] **Step 1: Static checks** — `qmllint components/KineticStageView.qml components/PenMark.qml`, `python scripts/verify_codebase.py`, `python scripts/verify_qml_compat.py`: all clean.
- [ ] **Step 2: Render sheets** — in the scratchpad, `render8.qml` and `render8vn.qml` with `times` picked from `MAX=1 node ptimes.js` to hit one bulb peak (before light, mid-bounce, lit), one spot, one rush, one duo and one stack; `python render7.py …` then `python3 sheet.py …`; look at `sheet0.png`: bulb visible above the hero and lit cone on the word, rush doodles above/below only, pile marks lined up with the lines, letters readable.
- [ ] **Step 3: Hot reload** — `touch components/KineticStageView.qml`; `/run/user/1000/quickshell/by-id/*/log.log` shows `Configuration Loaded` and no `kinetic_stage.js` / `PenMark` errors.
- [ ] **Step 4: Commit and push** — `feat(lyrics): preset 8 draws peak, rush, duo and stack effects`; update the header comments of `kinetic_stage.js` and `KineticStageView.qml` to describe the roles.
