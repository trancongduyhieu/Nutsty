.pragma library

// Per-letter lyric motion recipes for the desktop lyrics (preset 6 and any preset built on
// MotionLyricsView.qml).
//
// The motion model and many of the formulas follow JIZURA's lyric motion engine
// (https://github.com/852wa/JIZURA, src/05_anim.js, 11p_enter*.js, 11p_exit*.js):
//   Copyright (c) 2026 hakoniwa. MIT License.
//
// Each recipe is a pure function of progress: it adds to a letter's state
// { dx, dy, s, sx, sy, rot, alpha, blur, glyph, clip, clipDy } and keeps nothing between frames,
// so seeking or looping always lands on the right picture. Randomness is a hash of
// (seed, letter, salt), so a line moves the same way every time it plays.
//
// Adding a move: write it into ENTER, HOLD or EXIT below, then list it in a FAMILIES entry.
//   ENTER  runs when the line comes in ("line" trigger) or as each word is sung ("word" trigger)
//   HOLD   runs on the word being sung, p = 0..1 across the word
//   EXIT   runs when the line leaves

// ---------------------------------------------------------------------------
// Maths
// ---------------------------------------------------------------------------
var TAU = Math.PI * 2;

function clamp(x) { return x < 0 ? 0 : (x > 1 ? 1 : x); }
function lerp(a, b, t) { return a + (b - a) * t; }
function smooth(a, b, x) { var t = clamp((x - a) / (b - a)); return t * t * (3 - 2 * t); }

var E = {
    outQuad: function (x) { x = clamp(x); return 1 - (1 - x) * (1 - x); },
    inCubic: function (x) { x = clamp(x); return x * x * x; },
    outCubic: function (x) { x = clamp(x); return 1 - Math.pow(1 - x, 3); },
    outExpo: function (x) { x = clamp(x); return x >= 1 ? 1 : 1 - Math.pow(2, -10 * x); },
    outBack: function (x, s) { x = clamp(x); s = s === undefined ? 1.9 : s; var c = s + 1; return 1 + c * Math.pow(x - 1, 3) + s * Math.pow(x - 1, 2); },
    outBounce: function (x) {
        x = clamp(x);
        var n1 = 7.5625, d1 = 2.75;
        if (x < 1 / d1) return n1 * x * x;
        if (x < 2 / d1) { x -= 1.5 / d1; return n1 * x * x + 0.75; }
        if (x < 2.5 / d1) { x -= 2.25 / d1; return n1 * x * x + 0.9375; }
        x -= 2.625 / d1; return n1 * x * x + 0.984375;
    }
};

// Deterministic hash -> [0, 1); rs() is the signed version in [-1, 1)
function r(a, b, c) {
    var h = Math.imul((a | 0) ^ 0x9e3779b9, 0x85ebca6b);
    h = Math.imul(h ^ (h >>> 13) ^ ((b | 0) * 0x27d4eb2d), 0xc2b2ae35);
    h = Math.imul(h ^ (h >>> 16) ^ ((c | 0) * 0x165667b1), 0x85ebca6b);
    h ^= h >>> 15;
    return (h >>> 0) / 4294967296;
}
function rs(a, b, c) { return r(a, b, c) * 2 - 1; }

function hashText(s) {
    var h = 2166136261 >>> 0;
    for (var i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); }
    return h >>> 0;
}

// Latin, digits and symbols only: the desktop font has them all
var POOL = "ABCDEFGHJKLMNPQRSTUVWXYZ0123456789#$%&*+=<>/\\|";
function poolGlyph(seed, i, tick) { return POOL.charAt(Math.floor(r(seed, i, tick) * POOL.length)); }

// ---------------------------------------------------------------------------
// Recipes. c = { i: letter in line, n: letters in line, ci: letter in word, nc: letters in word,
//                seed, size: font px, t: clock seconds }
// ---------------------------------------------------------------------------
var ENTER = {
    pop: { trigger: "line", dur: 0.55,
        stagger: function (i, n) { return (n > 1 ? i / (n - 1) : 0) * 0.35; },
        apply: function (st, q, c) {
            st.s *= Math.max(0, E.outBack(q, 2.6));
            st.rot += (1 - E.outCubic(q)) * rs(c.seed, c.i, 9) * 28;
        } },
    drop: { trigger: "line", dur: 0.65,
        stagger: function (i, n, seed) { return r(seed, i, 4) * 0.3; },
        apply: function (st, q, c) {
            st.dy -= (1 - E.outBounce(q)) * c.size * 1.6;
            st.sy *= 1 + (1 - q) * 0.4;
            st.sx *= 1 - (1 - q) * 0.15;
            st.alpha *= clamp(q * 4);
        } },
    springIn: { trigger: "line", dur: 0.85,
        stagger: function (i) { return i * 0.028; },
        apply: function (st, q, c) {
            var d = Math.exp(-5 * q);
            st.s *= Math.max(0, 1 - d * Math.cos(11 * q));
            st.rot += d * Math.sin(11 * q) * rs(c.seed, c.i, 3) * 20;
        } },
    zoomOut: { trigger: "line", dur: 0.5,
        stagger: function (i) { return i * 0.012; },
        apply: function (st, q) {
            var e = E.outExpo(q);
            st.s *= lerp(3.2, 1, e);
            st.alpha *= e;
            st.blur += (1 - e) * 0.8;
        } },
    slideL: { trigger: "line", dur: 0.55,
        stagger: function (i) { return i * 0.02; },
        apply: function (st, q, c) {
            var e = E.outExpo(q);
            st.dx -= (1 - e) * c.size * 3;
            st.sx *= 1 + (1 - e) * 0.6;
            st.alpha *= e;
        } },
    riseMask: { trigger: "line", dur: 0.5,
        stagger: function (i) { return i * 0.025; },
        apply: function (st, q) {
            st.clip = true;
            st.clipDy += (1 - E.outExpo(q)) * 1.15;
        } },
    blurIn: { trigger: "line", dur: 0.7,
        stagger: function (i) { return i * 0.02; },
        apply: function (st, q) {
            var e = E.outCubic(q);
            st.blur += 1 - e;
            st.alpha *= Math.pow(e, 0.7);
            st.s *= 1 + 0.18 * (1 - e);
        } },
    trackIn: { trigger: "line", dur: 0.7,
        stagger: function () { return 0; },
        apply: function (st, q, c) {
            var e = E.outExpo(q);
            st.dx += (c.i - (c.n - 1) / 2) * (1 - e) * c.size * 0.5;
            st.alpha *= e;
        } },
    flipX: { trigger: "line", dur: 0.55,
        stagger: function (i) { return i * 0.03; },
        apply: function (st, q) {
            st.sx *= Math.max(0.001, E.outBack(q, 1.6));
            st.alpha *= clamp(q * 3);
        } },
    spiralIn: { trigger: "line", dur: 0.85,
        stagger: function (i) { return i * 0.02; },
        apply: function (st, q, c) {
            var e = E.outCubic(q);
            var a = rs(c.seed, c.i, 6) * Math.PI + (1 - e) * Math.PI * 1.5;
            var d = (1 - e) * c.size * 2.2;
            st.dx += Math.cos(a) * d;
            st.dy += Math.sin(a) * d;
            st.rot += (1 - e) * 180 * rs(c.seed, c.i, 7);
            st.alpha *= e;
        } },
    // Word triggers: the line waits as noise or blanks, each word resolves as it is sung
    scramble: { trigger: "word", dur: 0.42,
        stagger: function (ci, nc, seed, wordDur) { return (nc > 1 ? ci / (nc - 1) : 0) * Math.min(0.3, wordDur * 0.6); },
        before: function (st, c) {
            st.glyph = poolGlyph(c.seed, c.i, Math.floor(c.t * 8));
            st.alpha *= 0.32;
        },
        apply: function (st, q, c) {
            if (q < 1) st.glyph = poolGlyph(c.seed, c.i, Math.floor(c.t * 24));
            st.alpha *= lerp(0.6, 1, q);
        } },
    type: { trigger: "word", dur: 0.12,
        stagger: function (ci, nc, seed, wordDur) { return (nc > 0 ? ci / nc : 0) * Math.min(0.45, wordDur * 0.8); },
        before: function (st) { st.alpha = 0; },
        apply: function (st, q) { st.s *= 1 + (1 - q) * 0.35; } }
};

var HOLD = {
    none: function () {},
    bounce: function (st, p, c) { st.dy -= Math.sin(Math.PI * p) * c.size * 0.18; },
    wave: function (st, p, c) {
        var ph = clamp(p * 1.5 - (c.nc > 1 ? c.ci / (c.nc - 1) : 0) * 0.5);
        st.dy -= Math.sin(Math.PI * ph) * c.size * 0.16;
    },
    breathe: function (st, p) { st.s *= 1 + 0.12 * Math.sin(Math.PI * p); },
    tilt: function (st, p, c) { st.rot += Math.sin(Math.PI * p) * rs(c.seed, c.i, 11) * 9; },
    jitter: function (st, p, c) {
        var tick = Math.floor(c.t * 14);
        st.dx += rs(c.seed, c.i * 31 + tick, 5) * c.size * 0.05;
        st.dy += rs(c.seed, c.i * 17 + tick, 6) * c.size * 0.04;
    }
};

var EXIT = {
    sink: { dur: 0.5, stagger: function (i) { return i * 0.015; },
        apply: function (st, q, c) {
            st.dy += E.inCubic(q) * c.size * 0.9;
            st.alpha *= 1 - q;
            st.blur += q * 0.5;
        } },
    scatter: { dur: 0.55, stagger: function () { return 0; },
        apply: function (st, q, c) {
            var e = E.outCubic(q);
            var a = r(c.seed, c.i, 21) * TAU;
            var d = c.size * (1.5 + 2 * r(c.seed, c.i, 22));
            st.dx += Math.cos(a) * d * e;
            st.dy += Math.sin(a) * d * e;
            st.rot += rs(c.seed, c.i, 23) * 120 * e;
            st.alpha *= 1 - Math.pow(q, 1.5);
        } },
    gravity: { dur: 0.8, stagger: function (i, n, seed) { return r(seed, i, 7) * 0.25; },
        apply: function (st, q, c) {
            st.dy += q * q * c.size * 3.5;
            st.rot += rs(c.seed, c.i, 8) * 50 * q * q;
            st.alpha *= 1 - smooth(0.5, 1, q);
        } },
    shrink: { dur: 0.4, stagger: function (i) { return i * 0.012; },
        apply: function (st, q) {
            st.s *= 1 - E.inCubic(q);
            st.alpha *= 1 - q;
        } },
    blurOut: { dur: 0.5, stagger: function (i) { return i * 0.01; },
        apply: function (st, q) {
            st.blur += q;
            st.alpha *= 1 - q;
            st.s *= 1 + 0.15 * q;
        } },
    fold: { dur: 0.45, stagger: function (i) { return i * 0.015; },
        apply: function (st, q) {
            st.sy *= Math.max(0.001, 1 - q * q);
            st.alpha *= 1 - q * 0.5;
        } },
    backspace: { dur: 0.45, stagger: function () { return 0; },
        apply: function (st, q, c) { if (c.i >= c.n * (1 - q)) st.alpha = 0; } },
    glitchOut: { dur: 0.42, stagger: function () { return 0; },
        apply: function (st, q, c) {
            var tick = Math.floor(c.t * 24);
            if (r(c.seed, c.i, tick) < q) st.glyph = poolGlyph(c.seed, c.i, tick);
            st.dx += rs(c.seed, c.i * 13 + tick, 9) * c.size * 0.15 * q;
            st.alpha *= r(c.seed, c.i * 7 + tick, 10) > q ? 1 : 0;
        } }
};

// A song keeps one mood; each line picks its own moves inside it
var FAMILIES = {
    energetic: { enter: ["pop", "drop", "springIn", "zoomOut", "slideL"], hold: ["bounce", "breathe", "tilt"], exit: ["scatter", "gravity", "shrink"] },
    calm: { enter: ["riseMask", "blurIn", "trackIn", "flipX"], hold: ["wave", "breathe"], exit: ["sink", "blurOut", "fold"] },
    glitch: { enter: ["scramble", "type", "slideL", "zoomOut"], hold: ["jitter", "bounce"], exit: ["glitchOut", "backspace", "shrink"] },
    orbit: { enter: ["spiralIn", "springIn", "pop", "flipX"], hold: ["wave", "tilt"], exit: ["scatter", "blurOut", "sink"] }
};
var FAMILY_ORDER = ["energetic", "calm", "glitch", "orbit"];

function pick(list, seed, i, salt, avoid) {
    var k = Math.floor(r(seed, i, salt) * list.length);
    if (list.length > 1 && list[k] === avoid) k = (k + 1) % list.length;
    return list[k];
}

// ---------------------------------------------------------------------------
// Line timetable
// ---------------------------------------------------------------------------
function toSec(v) {
    var n = Number(v);
    if (v === undefined || v === null || isNaN(n)) return 0;
    return n > 10000 ? n / 1000 : n;
}

function wordsOf(entry, nextStart) {
    var out = [];
    if (!entry || entry.isInterlude) return out;
    var start = toSec(entry.time !== undefined ? entry.time : entry.startTime);
    if (entry.words && entry.words.length > 0) {
        for (var w = 0; w < entry.words.length; w++) {
            var wd = entry.words[w];
            var text = (wd && wd.text) ? String(wd.text).trim() : "";
            if (!text) continue;
            var s = wd.start !== undefined ? toSec(wd.start) : (wd.startTime !== undefined ? toSec(wd.startTime) : start);
            var e = wd.end !== undefined ? toSec(wd.end) : (wd.endTime !== undefined ? toSec(wd.endTime) : s + 0.25);
            out.push({ text: text, start: s, end: Math.max(e, s + 0.05) });
        }
        return out;
    }
    var parts = String(entry.text || "").trim().split(/\s+/).filter(function (p) { return p.length > 0; });
    if (parts.length === 0) return out;
    var span = Math.min(Math.max(nextStart, start + 0.6) - start, parts.length * 0.9) * 0.86;
    var total = 0;
    for (var k = 0; k < parts.length; k++) total += parts[k].length + 1.5;
    var cur = start;
    for (var p = 0; p < parts.length; p++) {
        var len = span * (parts[p].length + 1.5) / total;
        out.push({ text: parts[p], start: cur, end: cur + len });
        cur += len;
    }
    return out;
}

function fontFor(letters, words) {
    if (words >= 12 || letters >= 42) return 30;
    if (words >= 9 || letters >= 30) return 34;
    if (words >= 6 || letters >= 20) return 40;
    return 46;
}

// family: one of FAMILY_ORDER, or "" to let the song pick its own
function build(lyrics, family) {
    lyrics = lyrics || [];
    var songSeed = 0;
    for (var s = 0; s < lyrics.length && s < 4; s++) songSeed ^= hashText(String(lyrics[s].text || "") + s);
    var fam = FAMILIES[family] || FAMILIES[FAMILY_ORDER[Math.floor(r(songSeed, 1, 1) * FAMILY_ORDER.length)]];

    var lines = [];
    var prev = { enter: "", hold: "", exit: "" };
    for (var i = 0; i < lyrics.length; i++) {
        var start = toSec(lyrics[i].time !== undefined ? lyrics[i].time : lyrics[i].startTime);
        var nextStart = i + 1 < lyrics.length ? toSec(lyrics[i + 1].time !== undefined ? lyrics[i + 1].time : lyrics[i + 1].startTime) : start + 4;
        var words = wordsOf(lyrics[i], nextStart);
        var n = 0;
        for (var w = 0; w < words.length; w++) {
            words[w].chars = Array.from(words[w].text);
            words[w].g0 = n;
            n += words[w].chars.length;
        }
        var seed = (Math.imul(songSeed, 31) + i * 0x9e3779b1) | 0;
        var plan = {
            enter: pick(fam.enter, songSeed, i, 101, prev.enter),
            hold: pick(fam.hold, songSeed, i, 102, ""),
            exit: pick(fam.exit, songSeed, i, 103, prev.exit)
        };
        prev = plan;
        lines.push({
            start: start,
            end: words.length > 0 ? words[words.length - 1].end : start,
            words: words, n: n, seed: seed, plan: plan,
            font: fontFor(n, words.length),
            enterAt: start - 0.3, exitAt: -1, goneAt: Number.POSITIVE_INFINITY
        });
    }
    // Leave as the next sung line arrives, or soon after singing when a long break follows
    for (var a = 0; a < lines.length; a++) {
        var L = lines[a];
        if (L.n === 0) continue;
        var next = null;
        for (var b = a + 1; b < lines.length; b++) if (lines[b].n > 0) { next = lines[b]; break; }
        if (!next) L.exitAt = L.end + 1.2;
        else if (next.start - L.end > 3.0) L.exitAt = L.end + 0.6;
        else L.exitAt = Math.max(L.start + 0.3, next.start - 0.4);
        var ex = EXIT[L.plan.exit], maxStagger = 0;
        for (var k2 = 0; k2 < L.n; k2++) maxStagger = Math.max(maxStagger, ex.stagger(k2, L.n, L.seed));
        L.goneAt = L.exitAt + ex.dur + maxStagger + 0.08;
    }
    return { lines: lines, seed: songSeed };
}

// Lines on screen at t (at most the two newest)
function visibleAt(lines, t) {
    var out = [];
    for (var i = lines.length - 1; i >= 0 && out.length < 2; i--) {
        var L = lines[i];
        if (L.n > 0 && L.enterAt <= t && t < L.goneAt) out.unshift(i);
        if (L.goneAt <= t && L.n > 0 && out.length > 0) break;
    }
    return out;
}

// ---------------------------------------------------------------------------
// One letter at time t
// ---------------------------------------------------------------------------
function letterState(L, t, wi, ci) {
    var st = { dx: 0, dy: 0, s: 1, sx: 1, sy: 1, rot: 0, alpha: 1, blur: 0, glyph: "", clip: false, clipDy: 0, sung: 0, lit: false };
    if (!L || !L.words[wi]) return st;
    var w = L.words[wi];
    var nc = w.chars.length;
    var c = { i: w.g0 + ci, n: L.n, ci: ci, nc: nc, seed: L.seed, size: L.font, t: t };

    // Entrance
    var en = ENTER[L.plan.enter];
    var t0, q;
    if (en.trigger === "word") {
        st.alpha *= clamp((t - L.enterAt) / 0.2);
        t0 = w.start - 0.04 + en.stagger(ci, nc, L.seed, w.end - w.start);
    } else {
        t0 = L.enterAt + en.stagger(c.i, L.n, L.seed);
    }
    q = (t - t0) / en.dur;
    if (q <= 0) {
        if (en.before) en.before(st, c);
        else st.alpha = 0;
    } else if (q < 1) {
        en.apply(st, q, c);
    }

    // Singing
    var wp = (t - w.start) / Math.max(0.05, w.end - w.start);
    st.sung = clamp(wp * nc - ci);
    st.lit = wp > 0 && wp < 1;
    if (st.lit && (L.exitAt < 0 || t < L.exitAt)) HOLD[L.plan.hold](st, wp, c);

    // Exit
    if (L.exitAt >= 0 && t >= L.exitAt) {
        var ex = EXIT[L.plan.exit];
        var qx = (t - L.exitAt - ex.stagger(c.i, L.n, L.seed)) / ex.dur;
        if (qx > 0) ex.apply(st, clamp(qx), c);
    }
    return st;
}

// Line blur follows its middle letter (one blur layer per line)
function lineBlur(L, t) {
    if (!L || L.n === 0) return 0;
    var mid = Math.floor(L.n / 2);
    for (var w = 0; w < L.words.length; w++) {
        var wd = L.words[w];
        if (mid < wd.g0 + wd.chars.length) return clamp(letterState(L, t, w, mid - wd.g0).blur);
    }
    return 0;
}
