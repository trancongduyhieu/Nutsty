.pragma library
.import "motion_recipes.js" as M

// Kinetic type stage for desktop lyrics preset 7.
//
// Lines pile up (at most three per pile): the newest is the hero, older lines shrink and dim to 40%,
// and the whole pile cuts away before the next one starts. Every line gets a different type
// treatment from the one before (slam, rise, decode, karaoke, soft); inside a line the 1-2 hero
// words are set big (heavy, wide or condensed) and function words small. A held hero word echoes
// copies sliding away from it. Each pile is one camera shot with one gentle move; the only beat
// hit is a small scale punch when a slam word lands.
//
// Craft rules after scenario-labs' kinetic music video motion library (MIT,
// github.com/scenario-labs/skills); hash noise and easing from motion_recipes.js (after JIZURA).
// Everything is a pure function of the clock, so seeking or looping never pops.

var LEAD = 0.05;          // visual hits land a touch before the sung onset
var PILE_MAX = 3;
var PILE_GAP = 2.6;       // a longer break than this starts a new pile
var EXIT_DUR = 0.22;
var GAP_PX = 10;

// Advance per letter in em, for estimating line widths before layout
var ADV = { heavy: 0.80, mono: 0.62, soft: 0.42 };

var TREAT = {
    slam:    { hero: "heavy", minor: "mono",  minorSize: 0.36, base: 66, upper: true,  byWord: true },
    rise:    { hero: "heavy", minor: "heavy", minorSize: 0.60, base: 52, upper: true,  byWord: false },
    decode:  { hero: "mono",  minor: "mono",  minorSize: 0.66, base: 46, upper: true,  byWord: false },
    karaoke: { hero: "heavy", minor: "heavy", minorSize: 0.78, base: 46, upper: true,  byWord: false },
    soft:    { hero: "soft",  minor: "soft",  minorSize: 0.72, base: 64, upper: false, byWord: true }
};
var TREAT_ORDER = ["slam", "rise", "decode", "karaoke", "soft"];
var SHOT_ORDER = ["push", "dutch", "orbit", "tiltUp", "drift"];

var FUNC = {};
("a an the and or but so to of in on at by for from with as is am are was were be been it its i im " +
 "you your me my we our us he she they them his her this that these those there here do did not no " +
 "just oh yeah ooh la na " +
 "và là của cho thì mà những một cái đã sẽ đang có không với như này khi ta tôi em anh mình ai " +
 "được bị vì nên lại cũng còn rồi thôi đi nhé nha à ơi ừ").split(" ").forEach(function (w) { if (w) FUNC[w] = true; });

function bare(s) { return String(s).toLowerCase().replace(/[.,!?;:"'()\[\]\-…“”‘’]/g, ""); }

function build(lyrics) {
    lyrics = lyrics || [];
    var songSeed = 0;
    for (var s = 0; s < lyrics.length && s < 4; s++) songSeed ^= M.hashText(String(lyrics[s].text || "") + s);

    var lines = [];
    var prevTreat = "";
    for (var i = 0; i < lyrics.length; i++) {
        var start = M.toSec(lyrics[i].time !== undefined ? lyrics[i].time : lyrics[i].startTime);
        var nextStart = i + 1 < lyrics.length ? M.toSec(lyrics[i + 1].time !== undefined ? lyrics[i + 1].time : lyrics[i + 1].startTime) : start + 4;
        var words = M.wordsOf(lyrics[i], nextStart);
        if (words.length === 0) continue;
        var seed = (Math.imul(songSeed, 31) + i * 0x9e3779b1) | 0;
        var L = { start: start, end: words[words.length - 1].end, words: words, seed: seed, n: 0 };

        // Treatment: tender, slow lines go soft; otherwise never the same as the line before
        var avg = 0;
        for (var a = 0; a < words.length; a++) avg += words[a].end - words[a].start;
        avg /= words.length;
        var treat;
        if (avg > 0.55 && prevTreat !== "soft" && M.r(seed, 1, 401) < 0.6) treat = "soft";
        else {
            var k = Math.floor(M.r(seed, 2, 402) * TREAT_ORDER.length);
            for (var tries = 0; tries < TREAT_ORDER.length && (TREAT_ORDER[k] === prevTreat || TREAT_ORDER[k] === "soft"); tries++)
                k = (k + 1) % TREAT_ORDER.length;
            treat = TREAT_ORDER[k];
        }
        prevTreat = treat;
        var T = TREAT[treat];
        L.treat = treat;
        L.base = T.base;
        L.byWord = T.byWord;

        // Hero words: the held and the long content words, one or two per line
        var scores = words.map(function (w, wi) {
            var len = Array.from(bare(w.text)).length;
            return { wi: wi, sc: (w.end - w.start) * 2 + len * 0.12 - (FUNC[bare(w.text)] ? 2 : 0) };
        }).sort(function (x, y) { return y.sc - x.sc; });
        var heroes = {};
        heroes[scores[0].wi] = true;
        if (words.length >= 6 && scores.length > 1 && scores[1].sc > scores[0].sc * 0.75) heroes[scores[1].wi] = true;
        var heroSx = treat === "slam" ? (M.r(seed, 3, 403) < 0.5 ? 1.24 : 0.74) : (treat === "rise" && M.r(seed, 4, 404) < 0.5 ? 0.82 : 1);
        var echoDir = 1;     // echoes slide down, into the free space under the newest line

        var n = 0, estW = 0;
        for (var w = 0; w < words.length; w++) {
            var wd = words[w];
            var hero = heroes[w] === true;
            wd.hero = hero;
            wd.font = hero ? T.hero : T.minor;
            wd.size = hero ? 1 : T.minorSize;
            wd.sx = hero ? heroSx : 1;
            wd.chars = Array.from(T.upper ? wd.text.toUpperCase() : wd.text.toLowerCase());
            wd.g0 = n;
            wd.echo = hero && wd.end - wd.start >= 0.75 && treat !== "decode";
            wd.echoDir = echoDir;
            var nc = wd.chars.length;
            wd.step = Math.min(0.11, (wd.end - wd.start) * 0.85 / Math.max(1, nc));
            wd.estW = nc * ADV[wd.font] * wd.size * wd.sx;
            estW += wd.estW + (w > 0 ? 0.3 * T.minorSize : 0);
            n += nc;
        }
        L.n = n;
        L.estW = estW;        // in units of base px
        L.enterAt = start - (T.byWord ? 0.3 : 0.45);
        lines.push(L);
    }

    // Piles
    var piles = [];
    var pile = null;
    for (var p = 0; p < lines.length; p++) {
        var cur = lines[p];
        var prev = p > 0 ? lines[p - 1] : null;
        if (!pile || pile.lines.length >= PILE_MAX || (prev && cur.start - prev.end > PILE_GAP)) {
            pile = { lines: [], seed: cur.seed };
            piles.push(pile);
        }
        cur.pile = pile;
        cur.slot = pile.lines.length;
        pile.lines.push(cur);
    }
    var prevShot = "";
    for (var q = 0; q < piles.length; q++) {
        var P = piles[q];
        var last = P.lines[P.lines.length - 1];
        var next = q + 1 < piles.length ? piles[q + 1].lines[0] : null;
        // Hold the pile at least a beat after its last word, then cut before the next pile sings
        if (!next) P.exitAt = last.end + 1.4;
        else P.exitAt = Math.max(last.start + 0.4, Math.min(next.start - 0.3, last.end + 1.6));
        P.goneAt = P.exitAt + EXIT_DUR + 0.04 * PILE_MAX + 0.05;
        if (next) next.enterAt = Math.min(next.start - 0.08, Math.max(next.enterAt, P.exitAt + EXIT_DUR * 0.8));
        var sk = Math.floor(M.r(P.seed, 6, 406) * SHOT_ORDER.length);
        if (SHOT_ORDER[sk] === prevShot) sk = (sk + 1) % SHOT_ORDER.length;
        P.shot = SHOT_ORDER[sk];
        prevShot = P.shot;
        P.side = M.r(P.seed, 7, 407) < 0.5 ? -1 : 1;
        P.frameX = 0.03 * M.r(P.seed, 8, 408);
        P.startAt = P.lines[0].enterAt;
    }
    for (var g = 0; g < lines.length; g++) lines[g].goneAt = lines[g].pile.goneAt;
    return { lines: lines, piles: piles, seed: songSeed };
}

// Lines on screen at t: the current pile, plus the previous one while it cuts away
function visibleAt(lines, t) {
    var out = [];
    for (var i = lines.length - 1; i >= 0 && out.length < PILE_MAX * 2; i--) {
        var L = lines[i];
        if (L.enterAt <= t && t < L.goneAt) out.unshift(i);
        if (L.goneAt <= t && out.length > 0) break;
    }
    return out;
}

function fitOf(L, W) { return Math.min(1, (W * 0.84) / Math.max(1, L.estW * L.base)); }
function heightOf(L, W) { return L.base * 1.3 * fitOf(L, W); }

// Where a line sits in its pile: { y, s, alpha, blur, fit } (y is the offset of its centre)
function lineState(L, t, W) {
    var st = { y: 0, s: 1, alpha: 1, blur: 0, fit: fitOf(L, W) };
    if (!L) return st;
    var P = L.pile;
    // Walk from the newest line already in down to this one; each newer line pushes the ones above it
    var y = 0, s = 1, hPrev = 0, prevIdx = -1;
    for (var k = P.lines.length - 1; k >= L.slot; k--) {
        var N = P.lines[k];
        if (N.enterAt > t) continue;
        var hN = heightOf(N, W);
        if (prevIdx >= 0) {
            var e = M.E.outQuart((t - P.lines[prevIdx].enterAt) / 0.4);
            var sN = s * M.lerp(1, 0.6, e);
            y -= e * (0.5 * hPrev * s + GAP_PX + 0.5 * hN * sN);
            s = sN;
        }
        hPrev = hN;
        prevIdx = k;
    }
    st.y = y;
    st.s = s;
    st.alpha = M.lerp(0.4, 1, M.clamp((s - 0.6) / 0.4));
    if (t >= P.exitAt) {
        var qx = M.E.inCubic((t - P.exitAt - 0.04 * L.slot) / EXIT_DUR);
        st.y -= 36 * qx;
        st.alpha *= 1 - qx;
        st.blur = 14 * qx;
    }
    // Karaoke lines arrive whole, focusing in
    if (L.treat === "karaoke") {
        var ek = M.E.outQuart((t - L.enterAt) / 0.32);
        st.alpha *= ek;
        st.s *= 1.05 - 0.05 * ek;
        st.blur += 10 * (1 - ek);
    }
    return st;
}

// One camera shot per pile, one gentle move, plus a small punch as slam hero words land
function camera(L, t, W, H) {
    var cam = { x: 0, y: 0, s: 1, rot: 0, rx: 0, ry: 0 };
    if (!L) return cam;
    var P = L.pile, d = P.side;
    var dur = Math.max(1, P.exitAt - P.startAt);
    var cu = M.clamp((t - P.startAt) / dur);
    var e = M.E.outCubic((t - P.startAt) / 0.8);
    switch (P.shot) {
    case "push":   cam.s = 1 + 0.06 * cu; break;
    case "dutch":  cam.rot = d * M.lerp(6, 3.5, e); cam.s = 1.01 + 0.03 * cu; break;
    case "orbit":  cam.ry = d * M.lerp(26, 6, inOutSine(cu)); cam.s = 1.02; break;
    case "tiltUp": cam.rx = M.lerp(20, 8, M.E.outCubic(cu)); cam.s = 1.01 + 0.02 * cu; break;
    case "drift":  cam.x = d * W * 0.03 * (cu * 2 - 1); cam.rot = d * 1.5; break;
    }
    cam.x += d * W * P.frameX;
    var punch = 0;
    for (var i = 0; i < P.lines.length; i++) {
        var N = P.lines[i];
        if (N.treat !== "slam") continue;
        for (var w = 0; w < N.words.length; w++) {
            if (!N.words[w].hero) continue;
            var since = t - (N.words[w].start - LEAD);
            if (since >= 0 && since < 0.4) punch = Math.max(punch, Math.exp(-since * 12));
        }
    }
    cam.s *= 1 + 0.035 * punch;
    return cam;
}

function inOutSine(x) { x = M.clamp(x); return -(Math.cos(Math.PI * x) - 1) / 2; }

// One word: { s, alpha, dx, dy (em), ghosts: [{ dx, dy (em), a } x4] }
function wordFx(L, t, wi) {
    var fx = { s: 1, alpha: 1, dx: 0, dy: 0, ghosts: [g0(), g0(), g0(), g0()] };
    if (!L || !L.words[wi]) return fx;
    var w = L.words[wi];
    var land = w.start - LEAD;

    if (L.treat === "slam") {
        var dur = w.hero ? 0.13 : 0.2;
        var q = (t - (land - dur)) / dur;
        if (q <= 0) { fx.alpha = 0; return fx; }
        if (w.hero) {
            // Smear slam: in from 1.6x with three trailing ghosts that collapse into it
            fx.s = M.lerp(1.6, 1, M.E.outExpo(q));
            fx.alpha = M.clamp(q * 4);
            var c = 1 - M.clamp(q * 1.3);
            if (c > 0) {
                var wEm = w.estW / w.size;
                for (var k = 0; k < 3; k++) fx.ghosts[k] = { dx: -0.06 * (k + 1) * wEm * 1.6 * c, dy: 0, a: [0.35, 0.2, 0.1][k] * c };
                return fx;
            }
        } else {
            var e = M.E.outQuart(q);
            fx.alpha = e;
            fx.dy = 0.35 * (1 - e);
        }
    } else if (L.treat === "soft") {
        var qs = (t - (land - 0.42)) / 0.42;
        if (qs <= 0) { fx.alpha = 0; return fx; }
        var es = M.E.outQuart(qs);
        fx.alpha = es;
        fx.dy = 0.22 * (1 - es);
    }

    // Echo: a held hero word throws copies that slide away from it, then fade as the note ends
    if (w.echo && t > land) {
        var fade = 1 - M.clamp((t - w.end) / 0.6);
        for (var j = 0; j < 4; j++) {
            var ej = M.E.outExpo((t - land - 0.07 * (j + 1)) / 0.5);
            if (ej <= 0) continue;
            fx.ghosts[j] = { dx: 0, dy: w.echoDir * (j + 1) * 0.62 * ej, a: [0.42, 0.27, 0.16, 0.08][j] * ej * fade };
        }
    }
    return fx;
}
function g0() { return { dx: 0, dy: 0, a: 0 }; }

// One letter: { glyph ("" = real letter), alpha, dx, dy (em), clip, tone (0.42 waiting .. 1 sung), flash }
function letterState(L, t, wi, ci) {
    var st = { glyph: "", alpha: 1, dx: 0, dy: 0, clip: false, tone: 1, flash: 0 };
    if (!L || !L.words[wi]) return st;
    var w = L.words[wi];
    var nc = w.chars.length;
    var i = w.g0 + ci;
    var span = Math.max(1, L.n - 1);

    // Sung fill (line-triggered treatments show the line before it is sung)
    var wp = (t - (w.start - LEAD)) / Math.max(0.05, w.end - w.start);
    if (!L.byWord) st.tone = 0.42 + 0.58 * M.clamp(wp * nc - ci);

    if (L.treat === "rise") {
        // Letters rise from a baseline mask, cascading across the line within half a second
        var t0 = L.enterAt + Math.min(0.033, 0.5 / span) * i;
        var e = M.E.outQuint((t - t0) / 0.24);
        if (e <= 0) { st.alpha = 0; return st; }
        if (e < 1) { st.clip = true; st.dy = 1.15 * (1 - e); }
    } else if (L.treat === "decode") {
        var ta = L.enterAt + 0.3 * i / span;
        if (t < ta) { st.alpha = 0; return st; }
        var tl = w.start - LEAD + (ci + 1) * w.step;
        if (t < tl - 0.12) { st.glyph = M.poolGlyph(L.seed, i, Math.floor(t * 5)); st.tone = 0.3; }
        else if (t < tl) { st.glyph = M.poolGlyph(L.seed, i, Math.floor(t * 30)); st.tone = 0.7; }
        else { var f = 1 - M.clamp((t - tl) / 0.35); st.flash = f * f; st.tone = 1; }
    } else if (L.treat === "soft") {
        // Tracking closes in as the word fades up
        var es = M.E.outQuart((t - (w.start - LEAD - 0.42)) / 0.42);
        st.dx = (ci - (nc - 1) / 2) * 0.16 * (1 - es);
    }
    return st;
}
