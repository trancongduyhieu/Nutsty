.pragma library
.import "motion_recipes.js" as M

// Decode motion for desktop lyrics preset 7: one line at a time, set in monospace caps.
//   lock-on   a block cursor scans the line in, leaving dim noise glyphs; corner brackets snap shut
//   decode    as each word is sung its letters scramble and lock left to right under the cursor,
//             each lock flashing in the accent with a chromatic ghost
//   hold      now and then the whole line tears sideways for a frame
//   exit      letters scramble again right to left, flatten to a scanline and shoot off sideways
// Every value is a pure function of the clock (hash noise from motion_recipes.js, after JIZURA),
// so seeking or looping never pops.

var SCAN_IN = 0.30;      // lock-on scan across the whole line
var SCAN_CELL = 0.07;    // how long the scan block sits on a letter
var DECODE = 0.13;       // scramble before a letter locks
var STEP_MAX = 0.11;     // slowest per-letter lock, so long held notes still decode briskly
var FLASH = 0.42;        // accent flash after a lock
var EXIT_SWEEP = 0.16;   // right-to-left spread of the exit
var EXIT_DUR = 0.26;     // one letter's exit

function build(lyrics) {
    lyrics = lyrics || [];
    var songSeed = 0;
    for (var s = 0; s < lyrics.length && s < 4; s++) songSeed ^= M.hashText(String(lyrics[s].text || "") + s);

    var lines = [];
    for (var i = 0; i < lyrics.length; i++) {
        var start = M.toSec(lyrics[i].time !== undefined ? lyrics[i].time : lyrics[i].startTime);
        var nextStart = i + 1 < lyrics.length ? M.toSec(lyrics[i + 1].time !== undefined ? lyrics[i + 1].time : lyrics[i + 1].startTime) : start + 4;
        var words = M.wordsOf(lyrics[i], nextStart);
        var n = 0;
        for (var w = 0; w < words.length; w++) {
            var wd = words[w];
            wd.chars = Array.from(wd.text.toUpperCase());
            wd.g0 = n;
            var nc = wd.chars.length;
            wd.step = Math.min(STEP_MAX, (wd.end - wd.start) * 0.85 / Math.max(1, nc));
            n += nc;
        }
        lines.push({
            start: start,
            end: words.length > 0 ? words[words.length - 1].end : start,
            words: words, n: n,
            seed: (Math.imul(songSeed, 31) + i * 0x9e3779b1) | 0,
            enterAt: start - 0.42, exitAt: -1, goneAt: Number.POSITIVE_INFINITY
        });
    }
    var sung = 0;
    for (var c = 0; c < lines.length; c++) if (lines[c].n > 0) lines[c].number = ++sung;
    for (var a = 0; a < lines.length; a++) {
        var L = lines[a];
        L.total = sung;
        if (L.n === 0) continue;
        var next = null;
        for (var b = a + 1; b < lines.length; b++) if (lines[b].n > 0) { next = lines[b]; break; }
        if (!next) L.exitAt = L.end + 1.4;
        else if (next.start - L.end > 3.0) L.exitAt = L.end + 0.8;
        // Hold the finished line a beat (its cursor blinks) but clear before the next is sung
        else L.exitAt = Math.max(L.start + 0.3, Math.min(next.start - 0.12, Math.max(L.end + 0.2, next.start - 0.8)));
        L.goneAt = L.exitAt + EXIT_SWEEP + EXIT_DUR + 0.05;
        // The next line scans in once this one has mostly cleared, so the two rarely overlap
        if (next) next.enterAt = Math.min(next.start - 0.12, Math.max(next.start - 0.42, L.goneAt - 0.1));
    }
    planShots(lines, songSeed);
    return { lines: lines, seed: songSeed };
}

// Lines on screen at t (at most two: one leaving while the next scans in)
function visibleAt(lines, t) {
    var out = [];
    for (var i = lines.length - 1; i >= 0 && out.length < 2; i--) {
        var L = lines[i];
        if (L.n > 0 && L.enterAt <= t && t < L.goneAt) out.unshift(i);
        if (L.goneAt <= t && L.n > 0 && out.length > 0) break;
    }
    return out;
}

// Whole-line tear: a frame or two of sideways offset at lock-on and at rare moments while held
function lineGlitch(L, t) {
    if (!L || L.n === 0) return 0;
    var k = t - L.enterAt;
    if (k > SCAN_IN && k < SCAN_IN + 0.09) return M.rs(L.seed, 3, Math.floor(t * 30)) * 10;
    if (t > L.start && (L.exitAt < 0 || t < L.exitAt)) {
        var bin = Math.floor(t * 14);
        if (M.r(L.seed, bin, 7) > 0.972) return M.rs(L.seed, bin, 8) * 9;
    }
    return 0;
}

// Brackets and HUD: { pad, alpha } around the line
function frame(L, t) {
    if (!L) return { pad: 0, alpha: 0 };
    var e = M.E.outExpo((t - L.enterAt) / 0.34);
    var out = { pad: M.lerp(46, 12, e), alpha: e, pulse: 0 };
    // Payoff: the frame kicks outward and settles once the last letter locks
    if (L.n > 0) {
        var lw = L.words[L.words.length - 1];
        var done = lw.start + lw.chars.length * lw.step;
        var k = (t - done) / 0.55;
        if (k > 0 && k < 1) out.pulse = Math.sin(Math.PI * Math.min(1, k * 2.2)) * (1 - k);
    }
    if (L.exitAt >= 0 && t >= L.exitAt) {
        var q = M.clamp((t - L.exitAt) / 0.22);
        out.pad = M.lerp(out.pad, -4, M.E.inCubic(q));
        out.alpha *= 1 - q;
    }
    return out;
}

// Share of the line's letters already locked
function progress(L, t) {
    if (!L || L.n === 0) return 0;
    var locked = 0;
    for (var w = 0; w < L.words.length; w++) {
        var wd = L.words[w];
        locked += Math.max(0, Math.min(wd.chars.length, Math.floor((t - wd.start) / wd.step)));
    }
    return M.clamp(locked / L.n);
}

// Blinking end-of-line cursor, shown once the whole line is sung and before it leaves
function tailCursor(L, t) {
    if (!L || L.n === 0 || t < L.end) return false;
    if (L.exitAt >= 0 && t >= L.exitAt) return false;
    return Math.floor((t - L.end) * 2.6) % 2 === 0;
}

// One letter at time t:
// { glyph ("" = the real letter), alpha, noise (0 dim waiting .. 1 decoded), flash, cursor, ghost, dx, dy, sy }
function letterState(L, t, wi, ci) {
    var st = { glyph: "", alpha: 1, noise: 1, flash: 0, cursor: false, ghost: 0, dx: 0, dy: 0, sy: 1 };
    if (!L || !L.words[wi]) return st;
    var w = L.words[wi];
    var i = w.g0 + ci;
    var span = Math.max(1, L.n - 1);

    // Lock-on scan: the block runs left to right and leaves noise behind it
    var ta = L.enterAt + SCAN_IN * i / span;
    if (t < ta) { st.alpha = 0; return st; }
    if (t < ta + SCAN_CELL) { st.cursor = true; st.glyph = " "; }

    // Decode under the singing
    var tl = w.start + (ci + 1) * w.step;
    if (t < tl - DECODE) {
        if (!st.cursor) st.glyph = M.poolGlyph(L.seed, i, Math.floor(t * 5));
        st.noise = 0;
    } else if (t < tl) {
        st.glyph = M.poolGlyph(L.seed, i, Math.floor(t * 32));
        st.noise = 0.55;
        st.cursor = t >= tl - Math.min(w.step, DECODE);
    } else {
        var f = 1 - M.clamp((t - tl) / FLASH);
        st.flash = f * f;
        st.ghost = f * f * f;
        st.dy = -3 * f * f * f;
    }

    var g = lineGlitch(L, t);
    if (g !== 0) st.ghost = Math.max(st.ghost, 0.9);

    // Exit: scramble right to left, flatten, shoot sideways
    if (L.exitAt >= 0 && t >= L.exitAt) {
        var tx = L.exitAt + EXIT_SWEEP * (L.n - 1 - i) / span;
        if (t >= tx) {
            var q = M.clamp((t - tx) / EXIT_DUR);
            st.glyph = M.poolGlyph(L.seed, i + 97, Math.floor(t * 30));
            st.cursor = false;
            st.flash = 0;
            st.noise = 1 - q;
            st.ghost = 0.6 * (1 - q);
            var e = M.E.inCubic(q);
            st.sy = 1 - 0.88 * M.E.outCubic(q * 1.4);
            st.dx = (M.r(L.seed, i, 11) > 0.5 ? 1 : -1) * (40 + 140 * M.r(L.seed, i, 12)) * e;
            st.alpha = 1 - e;
        }
    }
    return st;
}

// ---------------------------------------------------------------------------
// Camera: every line is its own shot, picked from the set below (after JIZURA's camera moves,
// src/11p_bgcamB.js) so the viewer cannot guess the next angle. Each shot returns
// { x, y, s, rot, rx, ry, skx, blur }: rx / ry are perspective tilts in degrees.
// On top: a small jolt as each word lands, a punch on the line's longest held word, and a whip
// out as the line leaves.
// ---------------------------------------------------------------------------
function inOutSine(x) { x = M.clamp(x); return -(Math.cos(Math.PI * x) - 1) / 2; }
function inOutCubic(x) { x = M.clamp(x); return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; }

var SHOTS = {
    // Dutch angle: whips in from a hard lean and settles on a tilt, slowly pushing in
    dutch: function (c) {
        var e = M.E.outExpo(c.lt / 0.55);
        var lean = c.d * (8 + 6 * c.r1);
        return { rot: M.lerp(lean + c.d * 16, lean, e), ry: -c.d * (18 + 12 * c.r2), x: c.d * c.W * 0.05 * (1 - e),
                 s: 1 + 0.06 * c.cu, blur: 12 * (1 - e) * (1 - e) };
    },
    // Crash zoom: the lens slams in from far too close, then breathes forward
    crash: function (c) {
        var e = M.E.outExpo(c.lt / 0.5);
        return { s: 1 + 0.8 * (1 - e) + 0.05 * c.cu, rx: 10 * (1 - e), rot: c.d * 3 * (1 - e) + c.d * 1.5 * c.cu,
                 blur: 22 * Math.pow(1 - e, 2) };
    },
    // Barrel roll: a quick roll that overshoots a touch and lands level
    roll: function (c) {
        var q = M.clamp(c.lt / 0.55);
        return { rot: c.d * 85 * (1 - M.E.outBack(q, 1.3)), s: 1 - 0.14 * Math.sin(Math.PI * Math.min(1, q * 1.25)) + 0.04 * c.cu,
                 blur: 10 * M.clamp(1 - q * 2.2) };
    },
    // Orbit: the camera travels around the line, the perspective swinging from one side to the other
    orbit: function (c) {
        var k = inOutSine(c.cu);
        return { ry: M.lerp(-c.d * 52, c.d * 20, k), rx: 5 * Math.sin(c.lt * 1.4), x: M.lerp(c.d * c.W * 0.04, -c.d * c.W * 0.015, k),
                 s: 1.02, blur: 8 * Math.pow(1 - M.E.outCubic(c.lt / 0.4), 2) };
    },
    // Low angle: looking up at the line like a hero shot, rising into frame
    lowAngle: function (c) {
        var e = M.E.outCubic(c.lt / 0.8);
        return { rx: M.lerp(55, 24, M.E.outCubic(c.cu)), y: c.H * 0.12 * (1 - e), rot: c.d * 4, ry: c.d * 8, s: 1.0 + 0.08 * c.cu,
                 blur: 6 * (1 - e) };
    },
    // High angle: looking down on it, tipping forward
    highAngle: function (c) {
        var e = M.E.outCubic(c.lt / 0.8);
        return { rx: M.lerp(-50, -20, M.E.outCubic(c.cu)), ry: c.d * 14, y: -c.H * 0.1 * (1 - e), s: 1.04 - 0.03 * c.cu,
                 blur: 6 * (1 - e) };
    },
    // Snap pan: holds one framing, whips to the other side mid-line and holds again
    snapPan: function (c) {
        var at = Math.max(0.5, c.dur * (0.45 + 0.15 * c.r1));
        var dt = c.lt - at, q = inOutCubic(dt / 0.18), bell = dt > 0 && dt < 0.18 ? Math.sin(Math.PI * dt / 0.18) : 0;
        var A = c.W * 0.05 * c.d;
        return { x: A * (1 - 2 * q), ry: -c.d * 12 * (1 - 2 * q), s: 1.03 + 0.03 * bell, skx: -c.d * 9 * bell, blur: 16 * bell };
    },
    // Vertigo: a creeping dolly-in whose perspective keeps warping
    vertigo: function (c) {
        var z = inOutSine(c.cu), w = Math.sin(c.lt * 2.3);
        return { s: 1 + 0.1 * z, ry: c.d * 9 * z * Math.sin(c.lt * 1.3), skx: 4 * z * Math.sin(c.lt * 1.7) * c.d, rot: 1.6 * z * w * c.d,
                 blur: 6 * Math.pow(1 - M.E.outCubic(c.lt / 0.4), 2) };
    },
    // Quake: a low rumble, kicked hard by every word
    quake: function (c) {
        var tick = Math.floor(c.t * 24), amp = 0.25 + c.hit * 1.4;
        return { x: M.rs(c.seed, tick, 11) * c.W * 0.006 * amp, y: M.rs(c.seed, tick, 12) * c.H * 0.03 * amp,
                 rot: c.d * 3 + M.rs(c.seed, tick, 13) * 1.2 * amp, s: 1.03 + 0.03 * c.hit, blur: 3 * c.hit };
    }
};
var SHOT_ORDER = ["dutch", "crash", "orbit", "lowAngle", "roll", "snapPan", "highAngle", "vertigo", "quake"];

// Give each line a shot, never the same twice in a row, and flip the lean side often
function planShots(lines, songSeed) {
    var prev = "", side = 1;
    for (var i = 0; i < lines.length; i++) {
        var L = lines[i];
        if (L.n === 0) continue;
        var k = Math.floor(M.r(songSeed, i, 201) * SHOT_ORDER.length);
        if (SHOT_ORDER[k] === prev) k = (k + 1 + Math.floor(M.r(songSeed, i, 202) * (SHOT_ORDER.length - 1))) % SHOT_ORDER.length;
        // Very short lines get the snappy shots; snap pans need room for both framings
        if (L.goneAt - L.enterAt < 1.6 && (SHOT_ORDER[k] === "snapPan" || SHOT_ORDER[k] === "orbit")) k = (k + 1) % SHOT_ORDER.length;
        side = M.r(songSeed, i, 203) < 0.7 ? -side : side;
        L.shot = SHOT_ORDER[k];
        L.side = side;
        prev = L.shot;
        // The longest held word gets a punch-in
        var best = -1, bestDur = 0.55;
        for (var w = 0; w < L.words.length; w++) {
            var d = L.words[w].end - L.words[w].start;
            if (d > bestDur) { bestDur = d; best = w; }
        }
        L.punch = best;
        L.frameX = 0.02 + 0.07 * M.r(songSeed, i, 204);
        L.frameY = 0.13 * M.rs(songSeed, i, 205);
    }
}

function camera(L, t, W, H) {
    var cam = { x: 0, y: 0, s: 1, rot: 0, rx: 0, ry: 0, skx: 0, blur: 0 };
    if (!L || L.n === 0 || !L.shot) return cam;
    var dur = Math.max(0.6, (L.exitAt >= 0 ? L.exitAt : L.end + 1) - L.enterAt);
    // Jolt as each word lands (decays fast), alternating sides
    var hit = 0, hitSign = 1, punch = 0;
    for (var w = 0; w < L.words.length; w++) {
        var since = t - L.words[w].start;
        if (since >= 0 && since < 0.5) { var h = Math.exp(-since * 9); if (h > hit) { hit = h; hitSign = w % 2 ? -1 : 1; } }
        if (w === L.punch && since >= 0) punch = Math.max(punch, Math.sin(Math.PI * M.clamp(since / 0.7)) * Math.exp(-since * 1.5));
    }
    var c = { lt: t - L.enterAt, t: t, dur: dur, cu: M.clamp((t - L.enterAt) / dur), d: L.side, W: W, H: H, seed: L.seed, hit: hit,
              r1: M.r(L.seed, 1, 301), r2: M.r(L.seed, 2, 302) };
    var s = SHOTS[L.shot](c);
    for (var k in s) cam[k] = s[k];
    // Off-centre framing per line: left or right, high or low
    cam.x += L.side * W * L.frameX;
    cam.y += H * L.frameY;
    cam.s *= 1 + 0.022 * hit + 0.1 * punch;
    cam.rot += hitSign * 0.7 * hit;
    cam.blur += 3 * punch;

    // Whip out: the camera swings away as the line leaves
    if (L.exitAt >= 0 && t >= L.exitAt) {
        var q = M.E.inCubic((t - L.exitAt) / (EXIT_SWEEP + EXIT_DUR));
        var d2 = -L.side;
        cam.x += d2 * W * 0.12 * q;
        cam.rot += d2 * 10 * q;
        cam.ry += d2 * 30 * q;
        cam.blur += 14 * q;
    }
    return cam;
}
