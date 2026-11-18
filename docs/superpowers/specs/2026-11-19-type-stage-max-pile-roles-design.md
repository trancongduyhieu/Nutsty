# Type Stage Max: pile roles driven by singing tempo

Preset 8 ("Sân khấu chữ tối đa / Type Stage Max") is the maximal cut of the kinetic stage
(`components/kinetic_stage.js`, `components/KineticStageView.qml`). Today every line is dressed
the same way whatever pile it sits in, and a line stands alone by a 35% coin toss. This design
gives each pile a role chosen from the singing tempo, and each role its own pool of effects.

## Intent

- A line on its own must mean something. In preset 8 a line stands alone only for a tempo reason.
- **Peak** (khoảnh khắc đỉnh): the singer runs through fast lines, then one line slows down.
  That line is the moment of the song: varied effects that surprise, "wow".
- **Rush** (câu chuyển nhịp nhanh): a line sung fast, alone. As dense as the frame can hold.
- **Duo** (pile 2 câu) and **Stack** (pile 3 câu) get pile-level marks that tie their lines
  together, each from its own pool.
- Within a role, a pile never repeats the effect the previous pile of the same role used.

Non-goals: preset 7 keeps its random solo piles and current dressing. No change to the film
shader's contract beyond what the existing uniforms already allow.

Anti-goals: lyrics becoming hard to read (doodles never sit on top of letters; the "draft
strike" stays faint); the rush role swallowing a whole rap song.

## Tempo (decided)

- Rate of a line = letters (no spaces or punctuation) / (L.end - L.start). Letters, not words,
  so Vietnamese (one syllable per word) and English compare fairly. Works the same for word-synced
  and line-synced lyrics (line-synced words are spread evenly by `M.wordsOf`).
- `med` = median rate of the song.
- Peak: rate <= 0.75 * med, line lasts >= 1.2 s, and the mean rate of the 1–2 lines before it
  >= 1.1 * med.
- Rush: rate >= max(1.35 * med, 80th percentile of the song), and the previous pile was not rush.
- Every other line piles as today (up to 3, broken by `PILE_GAP`). Thresholds are constants at
  the top of the file so they can be tuned.

## Roles and effect pools

**Peak** (solo, base x1.4, centred). Pool, one per peak:
1. *Bóng đèn* (the user's pick for the blackout idea): the previous pile cuts out and the frame
   dims for ~0.25 s. A hand-drawn bulb on its cord drops from above the hero word with a springy
   yo-yo bounce (damped spring, overshoots and bounces back up, not a straight fall), swings and
   tilts as it settles (damped pendulum), then switches on: a soft accent light cone falls on the
   hero word, short rays flick around the bulb, the hero brightens, frame bulge + chroma flash.
2. *Đèn rọi*: a very large ring drawn round the hero; the rest of the line dims to ~30%; the hero
   scales x1.5 as the ring closes.
3. *Tia nổ*: manga focus lines radiate from the hero across the frame, drawn over the sung length,
   with a light smear.
4. *Mực tràn*: a dense zigzag highlighter fill sweeps behind the whole line at the singing speed.
5. *Đóng dấu*: a thick, tilted stamp box slams round the hero; the frame shakes for one beat.
Marks that track the voice (rings, fills, rays) progress with the sung time of the line, so a
long held note draws slowly. Exit: slow smudge.

**Rush** (solo, base x1.22 as today):
- Each word that lands fires one small doodle (speed, sparkle, bang, burst), up to ~10, placed
  only above or below the line.
- Speed lines on both sides; zigzag plus double underline; a tick or small ring on each word.
- Boil 1.5x faster (12/s), camera jolt per word, chroma flicker. Exit: strike.

**Duo** (2-line pile). Pool: curved arrow from hero 1 to hero 2; right-side "}" with a star at
its tip; call-and-response (lines offset left/right with a "/" slash between); S-curve underline
from under line 1 swooping under line 2; both heroes ringed and joined by a dashed line.

**Stack** (3-line pile). Pool: notebook (left margin brace, tick when a line is sung); hand-drawn
numbers 1 2 3 in the margin (drawn as pen strokes, not text); staircase arrows 1 -> 2 -> 3;
rough frame round the whole pile with a star sticker on a corner; draft edit (line 1 struck at
50% alpha when line 3 lands).

Duo and Stack: at most ~5 doodles for the whole pile (today it is per line, up to ~15 a pile).
Per-line hero mark / highlighter / line mark stay as now.

## Approach (decided)

One way fits: `build()` tags each pile with `role` (peak / rush / duo / stack) and `fx` (the pool
pick); the view reads them. Four separate views were rejected: all roles share letters, film
pass, entries and exits, so every tweak would land in four places.

## Left to the builder (my calls, marked)

- A pile that ends up with one ordinary line (gap, or the next line is a peak) is a stack of one:
  per-line maximal dressing, no pile mark, normal size.
- Pile-level marks are drawn in a pile overlay in `KineticStageView.qml` using `PenMark`, from
  the line and hero word positions mapped into the stage. The bulb's light cone is a filled
  `Shape` with a gradient; the bulb and cord are pen strokes.
- Bulb motion is a pure function of t (damped spring for y, damped sine for tilt), like the
  rest of `kinetic_stage.js`.

## Verification

`scratchpad` harnesses (`ktest2.js` NaN check with `MAX=1`, render sheets of preset 8 on an
English and a Vietnamese song, including a peak, a rush, a duo and a stack), then
`verify_codebase.py`, `verify_qml_compat.py`, `qmllint`, and a hot reload in the running Nutsty.
