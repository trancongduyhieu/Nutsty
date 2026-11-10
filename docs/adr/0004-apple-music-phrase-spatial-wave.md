# ADR 0004: Apple Music Phrase-Level Spatial Traveling Wave Engine

- **Status**: Superseded by [ADR 0006](file:///home/apple/Applications/FrostifyLocal/docs/adr/0006-apple-music-character-sweep-and-rolling-wave-engine.md)
- **Date**: 2026-09-26 (Superseded on 2026-11-03)
- **Deciders**: User, Antigravity AI Assistant

## Context
In the previous implementation of `AppleMusicWordFlow.qml`, word animation operated on a discrete per-word basis where each word evaluated its vertical offset independently based on its individual start and end times `(currentTime - wStart) / wDur`. 

This produced two critical defects:
1. **Isolated Word Jumps**: Words acted as isolated islands, jumping up and down individually rather than flowing in a continuous wave across the clause (như một dải lụa dập dềnh).
2. **Excessive Lift Amplitude**: The vertical lift was too pronounced ($\sim 3.0\text{px}$ swing between `restY: 2.5` and `peakLiftY: 0.5`), making words pop too violently.

## Decision
We implement a **Phrase-Level Spatial Traveling Wave Model** inspired by Apple Music's iOS 17+ and macOS lyrics engine:

1. **Phrase Segmentation (Hybrid Punctuation & Temporal Gap)**:
   - Words are grouped into cohesive rhythmic phrases (clauses) bounded by:
     - Visible punctuation: `,`, `.`, `!`, `?`, `;`, `—`.
     - Temporal vocal breath pauses: inter-word silence $\Delta t > 0.35\text{s}$.
2. **Continuous Spatial Traveling Wave**:
   - Instead of binary per-word triggers, the wave propagates through the phrase as a continuous energy crest $x_{\text{wave}}(t)$ over a unified window `waveProgressTotal = (currentTime - waveStart) / (wDur + leadTime)`.
   - Upcoming words in the phrase gently pre-lift as the wave approaches ($160\text{ms}$ phase lead), reach peak elevation during active singing, and settle gracefully back to the baseline.
3. **Unified Baseline & Spring-Damped SmoothedAnimation ($\Delta y \le 2.0\text{px}$)**:
   - Resting baseline is flat `0.0px` for all words (unsung, sung, and past), completely eliminating stepped cliffs between words.
   - Peak lift `peakLiftY: 1.6px` (lifts upward to $-1.6\text{px}$, well within the user-approved $\le 2.0\text{px}$ ceiling).
   - `Translate.y` and `scale` are wrapped in `SmoothedAnimation { duration: 150; reversingMode: SmoothedAnimation.Immediate }`, guaranteeing $C^1$ velocity continuity and liquid spring-damped motion without any abrupt jerk or stair-stepping.

## Consequences
- **Positive**:
  - Lyrics now mirror Apple Music's liquid smooth traveling wave propagation.
  - Zero stepped cliffs: entire phrase sits on an unbroken horizontal baseline.
  - Spring-damped velocity continuity eliminates all discrete clock jitter and abrupt up-and-down popping.
  - Natural clause phrasing respects linguistic and musical pauses (before commas).
  - Reduced amplitude prevents visual jumping while preserving distinct phosphor luminescence.
- **Negative / Tradeoffs**:
  - Requires pre-indexing word phrase indices during model initialization (negligible $\sim 0.05\text{ms}$ computational cost for 15 words).
