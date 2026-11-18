# Type Stage Max: more peak moves (props with their own motion)

Follow-up to `2026-11-19-type-stage-max-pile-roles-design.md`. The user liked the bulb (a drawn
object with real motion that lands, then pays off on the hero word) and asked for all of these,
with motion that is not "falls from above" every time. They join `PEAK_FX`, so a song's peaks
rarely repeat (a pile never repeats the previous peak's fx, as before).

## The eight moves

Each prop arrives over a fixed time D and lands exactly when the hero word is sung
(`on = max(hero land, enterAt + D)`, the prop starts at `on - D`, nothing shows before that).

| fx | arrives | payoff on the hero |
|---|---|---|
| balloon | rises from below on a damped spring, sways on its string tied to the word top | lifts the word a little; pops into confetti near the end of the line, the word drops back |
| note | a sticky note flutters in from above, side to side, tilting | taped down above the word (two tape strips) |
| plane | a paper plane flies a looping path in from the right, dashed trail behind it | nose sticks into the word's top-right corner, tail wobbles, word shakes |
| roll | a tape roll rolls in from the left along the baseline | rolls across under the word as it is sung, laying a tape underline, then rolls off |
| vine | grows from the word's bottom-left along its sung time | wraps under and up the right side with leaves; a flower blooms as the word ends |
| jack | (none: it bursts out of the word) | the word splits in two, a spring with a star boings up, wobbles, then retracts and the word closes |
| fold | a folded paper behind the word opens panel by panel | when fully open the word grows x1.35 inside it |
| hand | a drawn hand reaches in from the bottom right holding a sticker | presses the sticker onto the word's corner and pulls back; the sticker stays |

## Approach (my calls)

- Motion lives in `kinetic_stage.js` as pure functions of t, like the bulb:
  `peakPieces(L, t, wordW, px, bl)` returns up to 4 pieces `{ strokes, accent, pen, alpha, z }`
  already placed in the hero word's own coordinates (rotation and scale applied in JS), so the view
  is one fixed `Repeater { model: 4 }` of `PenMark`s inside the hero word. Pieces move, scale and
  fade with the word.
- Effects on the word itself go through the existing hooks: `peakState` gains `heroDy` (em) and
  `heroRot` (deg) next to `heroS`; the jack split is a per-letter `dx` in `letterState`.
- Props never sit on top of the letters of other words: they live above, under, or on the right
  edge of the hero word. Bulb, spot, rays, ink and stamp stay as they are.

## Verification

Unit tests per move (arrival timing, payoff, nothing before start, finite everywhere), render
sheets of each move, the usual verify scripts, qmllint, and a hot reload.
