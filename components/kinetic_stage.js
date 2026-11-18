.pragma library
.import "motion_recipes.js" as M

// Kinetic type stage for desktop lyrics preset 7.
//
// Lines pile up (at most three per pile): the newest is the hero, older lines shrink and dim to 40%,
// and the whole pile cuts away before the next one starts. Every line gets a different type
// treatment from the one before (slam, rise, decode, karaoke, soft, hand, marker) and its own
// letter case; inside a line the 1-2 hero words are set big (heavy, wide or condensed) and function
// words small, every word a little off-axis so it reads hand-set. Backing vocals in ( ) get their
// own look, profanity goes under a redaction bar, and long breaks show waiting dots. A held hero
// word echoes copies sliding down. Each pile is one camera shot with one gentle move; the only beat
// hit is a small scale punch when a slam word lands. film() drives the old-film pass (film_tv.frag).
//
// Craft rules after scenario-labs' kinetic music video motion library (MIT,
// github.com/scenario-labs/skills); hash noise and easing from motion_recipes.js (after JIZURA).
// Everything is a pure function of the clock, so seeking or looping never pops.
//
// build(lyrics, { max: true }) is the maximal cut (preset 8): every line gets a mark under it and
// one on its hero, a marker swipe behind the hero, a ring round the whole line now and then, and
// doodles (stars, bursts, spirals, hearts...) scattered round it, more of them on the loud lines.
// Every stroke is drawn twice, the second pass a little off, after rough.js (MIT, roughjs.com).
// In the maximal cut each pile also gets a role from the singing tempo (tempoRoles): a slow line
// right after fast ones is a peak (solo, big, one surprise from PEAK_FX: a bulb dropping on its
// cord and switching on, a spotlight ring, focus rays, an ink fill, a stamp, or a prop with its own
// motion from PROP_FX: a balloon, a sticky note, a paper plane, a tape roll, a vine, a jack-in-the-box,
// a folding paper, a hand with a sticker, drawn by peakPieces); a fast line alone is
// a rush (a tick or ring on every word, a doodle per word, camera jolts); the rest pile as duos and
// stacks, tied together by one pile mark from DUO_FX / STACK_FX (pileStrokes).

var LEAD = 0.05;          // visual hits land a touch before the sung onset
var PILE_MAX = 3;
var PILE_GAP = 2.6;       // a longer break than this starts a new pile
var EXIT_DUR = 0.22;      // the plain lift-and-blur exit; the pen exits take longer (EXITS)
var GAP_PX = 10;
var GAP_MIN = 3.5;        // a break this long shows the waiting dots

// Advance per letter in em, for estimating line widths before layout
var ADV = { heavy: 0.80, mono: 0.62, soft: 0.42, hand: 0.46, marker: 0.50 };

//   cases   letter case per line, picked by hash: upper, lower, or mixed (hero caps, rest lower)
//   jitter  how hand-made the line looks: per-word tilt, baseline wobble and size wobble
var TREAT = {
    slam:    { hero: "heavy",  minor: "mono",   minorSize: 0.36, base: 66, byWord: true,  cases: ["upper", "mixed"],          jitter: 0.8 },
    rise:    { hero: "heavy",  minor: "heavy",  minorSize: 0.60, base: 52, byWord: false, cases: ["upper", "lower", "mixed"], jitter: 0.3 },
    decode:  { hero: "mono",   minor: "mono",   minorSize: 0.66, base: 46, byWord: false, cases: ["upper", "lower"],          jitter: 0 },
    karaoke: { hero: "heavy",  minor: "heavy",  minorSize: 0.78, base: 46, byWord: false, cases: ["upper", "lower", "mixed"], jitter: 0.4 },
    soft:    { hero: "soft",   minor: "soft",   minorSize: 0.72, base: 64, byWord: true,  cases: ["lower"],                   jitter: 0.6 },
    hand:    { hero: "hand",   minor: "hand",   minorSize: 0.64, base: 62, byWord: true,  cases: ["lower", "mixed"],          jitter: 2.2 },
    marker:  { hero: "marker", minor: "marker", minorSize: 0.58, base: 64, byWord: true,  cases: ["upper"],                   jitter: 2.8 }
};
var TREAT_ORDER = ["slam", "rise", "decode", "karaoke", "hand", "marker"];
var SHOT_ORDER = ["push", "dutch", "orbit", "tiltUp", "drift", "dolly", "low", "roll", "crane"];
// Words in ( ) or [ ] are backing vocals and ad-libs; each line picks one look for them
// They leave the line: brackets dropped, stacked in a small column to its left or right, behind a
// thin accent rule. adlib is handwriting, hollow is outlined caps, shout is accent marker caps.
var PAREN = {
    adlib:   { font: "hand",   size: 0.46, upper: false, rot: -5, tone: 0.8,  hollow: false },
    hollow:  { font: "heavy",  size: 0.50, upper: true,  rot: 0,  tone: 0.95, hollow: true },
    shout:   { font: "marker", size: 0.52, upper: true,  rot: 4,  tone: 0.92, hollow: false }
};
var PAREN_ORDER = ["adlib", "hollow", "shout"];
// Pen marks drawn over the frame. Line marks run under the whole line as it is sung; hero marks
// sit on the hero word just after it lands.
var LINE_MARKS = ["coil", "under", "double", "zigzag", "wave"];
var HERO_MARKS = ["ring", "box", "ticks", "arrow"];
// How a pile leaves, and for how long: lift (rise and blur), strike (a pen line through each line,
// then fade), smudge (smeared sideways into a blur), scrawl (scribbled out, then fade)
var EXITS = { lift: 0.22, strike: 0.6, smudge: 0.42, scrawl: 0.66 };
var EXIT_ORDER = ["strike", "smudge", "scrawl", "lift", "strike", "scrawl"];
// The maximal cut: a ring round the whole line joins the line marks, the exits are all pen work,
// and doodles are scattered round each line
var LINE_MARKS_MAX = ["coil", "under", "double", "zigzag", "wave", "wrap"];
var EXIT_ORDER_MAX = ["scrawl", "strike", "smudge", "strike", "scrawl"];
var DOODLES = ["star", "sparkle", "burst", "speed", "spiral", "bang", "heart", "cross"];
var DOODLE_SPOTS = ["above", "above", "left", "right", "above", "below"];
// Pile roles in the maximal cut, from how fast each line is sung (letters per second against the
// song's median): a slow line straight after fast ones is a peak, a very fast line is a rush; both
// stand alone. Every other pile is a duo (two lines) or a stack.
var TEMPO = { slow: 0.75, prevFast: 1.0, minLines: 4, fast: 1.35, fastPct: 0.8, peakMinDur: 1.2 };
// What each role draws. A peak picks one big move; a duo or stack one mark that ties its lines
// together; a rush gets everything at once. Never the same pick twice running within a role.
// Props with their own motion (peakPieces): each arrives over PROP_D seconds and lands on the hero
var PROP_FX = ["balloon", "note", "plane", "roll", "vine", "jack", "fold", "hand"];
var PROP_D = { balloon: 0.9, note: 1.0, plane: 0.8, roll: 0.7, vine: 0, jack: 0, fold: 0.6, hand: 0.6 };
var PEAK_FX = ["bulb", "spot", "rays", "ink", "stamp"].concat(PROP_FX);
var DUO_FX = ["arrow", "brace", "versus", "swoop", "pair"];
var STACK_FX = ["notebook", "numbers", "stairs", "frame", "draft"];
var PILE_DOODLES = 5;     // doodles a whole duo or stack may carry
var RUSH_DOODLES = 10;    // one per word on a rush line, at most this many
var RUSH_KINDS = ["speed", "sparkle", "bang", "burst"];
// How the words of a line sit: level, a zigzag (one up, one down), stairs climbing, or an arc
var STAGGER_ORDER = ["zig", "stairs", "arc", "zig"];

var FUNC = {};
("a an the and or but so to of in on at by for from with as is am are was were be been it its i im " +
 "you your me my we our us he she they them his her this that these those there here do did not no " +
 "just oh yeah ooh la na " +
 "và là của cho thì mà những một cái đã sẽ đang có không với như này khi ta tôi em anh mình ai " +
 "được bị vì nên lại cũng còn rồi thôi đi nhé nha à ơi ừ").split(" ").forEach(function (w) { if (w) FUNC[w] = true; });

// Words hidden under a redaction bar
var PROFANE = {};
("fuck fucking fucked fucker fuckin motherfucker motherfuckin shit shitty bullshit bitch bitches ass asshole " +
 "dick pussy cunt bastard hoe hoes nigga niggas nigger " +
 "đm đmm dm dmm đcm dcm vcl vl vkl clm cmm đéo địt đĩ lồn cặc buồi đụ đù").split(" ").forEach(function (w) { if (w) PROFANE[w] = true; });

function bare(s) { return String(s).toLowerCase().replace(/[.,!?;:"'()\[\]\-…“”‘’*]/g, ""); }
function isProfane(text) {
    var b = bare(text);
    return PROFANE[b] === true || b.indexOf("fuck") >= 0 || b.indexOf("shit") >= 0;
}
function cased(text, up) { return Array.from(up ? text.toUpperCase() : text.toLowerCase()); }
function unbracket(text) { return String(text).replace(/[()\[\]]/g, ""); }

// Letters per second of a line (backing vocals left out); 0 for a line with no letters ("♪", "...")
function isLetter(c) {
    return c.toLowerCase() !== c.toUpperCase() || /[0-9\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]/.test(c);
}
function rateOf(L) {
    if (!L || !L.words) return 0;
    var n = 0;
    for (var w = 0; w < L.words.length; w++) {
        if (L.words[w].paren) continue;
        var cs = Array.from(String(L.words[w].text));
        for (var c = 0; c < cs.length; c++) if (isLetter(cs[c])) n++;
    }
    return n / Math.max(0.1, L.end - L.start);
}
function quantile(sorted, q) {
    if (sorted.length === 0) return 0;
    var x = (sorted.length - 1) * q, i = Math.floor(x), f = x - i;
    return i + 1 < sorted.length ? sorted[i] + (sorted[i + 1] - sorted[i]) * f : sorted[i];
}
// "peak" | "rush" | "" for each line
function tempoRoles(lines) {
    var rates = lines.map(rateOf);
    var sorted = rates.filter(function (r) { return r > 0; }).sort(function (a, b) { return a - b; });
    var med = quantile(sorted, 0.5), hi = Math.max(TEMPO.fast * med, quantile(sorted, TEMPO.fastPct));
    var roles = [];
    for (var i = 0; i < lines.length; i++) {
        var r = rates[i], role = "";
        if (r > 0 && med > 0 && sorted.length >= TEMPO.minLines) {
            var prev = [];
            for (var k = i - 1; k >= 0 && prev.length < 2; k--) if (rates[k] > 0) prev.push(rates[k]);
            var prevMean = prev.length ? prev.reduce(function (a, b) { return a + b; }, 0) / prev.length : 0;
            if (!lines[i].guessEnd && r <= TEMPO.slow * med && lines[i].end - lines[i].start >= TEMPO.peakMinDur && prev.length > 0 && prevMean >= TEMPO.prevFast * med)
                role = "peak";
            else if (r >= hi && r > med && roles[i - 1] !== "rush") role = "rush";
        }
        roles.push(role);
    }
    return roles;
}

// The maximal cut: give every pile its role and pick, then dress its lines for that role
function dressPiles(piles) {
    var lastFx = {};
    for (var q = 0; q < piles.length; q++) {
        var P = piles[q];
        if (!P.role) P.role = P.lines.length === 2 ? "duo" : "stack";
        var pool = P.role === "peak" ? (P.lines[0].heroOk ? PEAK_FX : ["ink"])
                 : P.role === "duo" ? DUO_FX : (P.role === "stack" ? STACK_FX : []);
        P.fx = "";
        if (pool.length > 0) {
            var k = Math.floor(M.r(P.seed, 31, 431) * pool.length);
            if (pool.length > 1 && pool[k] === lastFx[P.role]) k = (k + 1) % pool.length;
            P.fx = pool[k];
            lastFx[P.role] = P.fx;
        }
        if (P.role === "peak") dressPeak(P.lines[0]);
        else if (P.role === "rush") dressRush(P.lines[0]);
        else { capDoodles(P); if (P.role === "duo") dressDuo(P); }
    }
}

// A "pair" duo rings both heroes; the dashed line between them is a pile mark (pileStrokes)
function dressDuo(P) {
    if (P.fx !== "pair") return;
    for (var k = 0; k < P.lines.length; k++) {
        var L = P.lines[k];
        if (!L.heroOk) continue;
        L.heroMark = "ring";
        L.ringWi = L.heroWi;
        L.scribble = L.lineMark || L.heroMark;
    }
}

// A peak keeps its letters clear for its one big move
function dressPeak(L) {
    L.doodles = [];
    L.lineMark = "";
    L.heroMark = "";
    L.ringWi = -1;
    L.hiWi = -1;
    L.scribble = "";
}

// A rush throws a doodle off every word as it lands, speed lines both sides, a zigzag and a line
// under it, and a tick or a small ring on each word; its strokes boil half again as fast
function dressRush(L) {
    var main = L.mainIdx, n = Math.min(RUSH_DOODLES, main.length);
    L.doodles = [];
    for (var k = 0; k < n; k++) {
        var w = L.words[main[k]];
        L.doodles.push({
            kind: RUSH_KINDS[Math.floor(M.r(L.seed, k, 441) * RUSH_KINDS.length)],
            spot: k % 2 ? "below" : "above",
            u: (k + 0.5) / main.length,
            k: 0.5 + 0.2 * M.r(L.seed, k, 442),
            rot: 30 * M.rs(L.seed, k, 443),
            accent: k % 2 === 0,
            at: w.start - LEAD,
            dur: 0.18
        });
    }
    for (var sd = 0; sd < 2; sd++)
        L.doodles.push({ kind: "speed", spot: sd ? "right" : "left", u: 0.5, k: 0.9, rot: sd ? 0 : 180,
                         accent: false, at: L.start - 0.1, dur: 0.2 });
    L.wordMarks = {};
    for (var m = 0; m < main.length; m++)
        if (!L.words[main[m]].censor) L.wordMarks[main[m]] = m % 2 ? "ring" : "tick";
    L.lineMark = "rushline";
    L.scribble = "rushline";
    L.boil = 12;
}

// A duo or stack carries at most PILE_DOODLES doodles between its lines: the earliest ones stay
function capDoodles(P) {
    var all = [];
    P.lines.forEach(function (L) { L.doodles.forEach(function (d) { all.push(d); }); });
    if (all.length <= PILE_DOODLES) return;
    all.sort(function (a, b) { return a.at - b.at; });
    var keep = all.slice(0, PILE_DOODLES);
    P.lines.forEach(function (L) { L.doodles = L.doodles.filter(function (d) { return keep.indexOf(d) >= 0; }); });
}

function build(lyrics, opts) {
    lyrics = lyrics || [];
    var maxi = !!(opts && opts.max);
    var songSeed = 0;
    for (var s = 0; s < lyrics.length && s < 4; s++) songSeed ^= M.hashText(String(lyrics[s].text || "") + s);

    var lines = [];
    var prevTreat = "";
    var prevCase = "";
    var prevParen = "";
    var prevScribble = "", prevLineMark = "", prevHeroMark = "";
    for (var i = 0; i < lyrics.length; i++) {
        var start = M.toSec(lyrics[i].time !== undefined ? lyrics[i].time : lyrics[i].startTime);
        var nextStart = i + 1 < lyrics.length ? M.toSec(lyrics[i + 1].time !== undefined ? lyrics[i + 1].time : lyrics[i + 1].startTime) : start + 4;
        var words = M.wordsOf(lyrics[i], nextStart);
        if (words.length === 0) continue;
        var seed = (Math.imul(songSeed, 31) + i * 0x9e3779b1) | 0;
        var L = { start: start, end: words[words.length - 1].end, words: words, seed: seed, n: 0 };
        // line-synced lyrics spread words up to the next line; the last line's length is only a guess
        L.guessEnd = i + 1 >= lyrics.length && !(lyrics[i].words && lyrics[i].words.length > 0);

        // Treatment: tender, slow lines go soft; otherwise never the same as the line before
        var avg = 0;
        for (var a = 0; a < words.length; a++) avg += words[a].end - words[a].start;
        avg /= words.length;
        var treat;
        if (avg > 0.55 && prevTreat !== "soft" && M.r(seed, 1, 401) < 0.5) treat = "soft";
        else {
            var k = Math.floor(M.r(seed, 2, 402) * TREAT_ORDER.length);
            for (var tries = 0; tries < TREAT_ORDER.length && TREAT_ORDER[k] === prevTreat; tries++)
                k = (k + 1) % TREAT_ORDER.length;
            treat = TREAT_ORDER[k];
        }
        prevTreat = treat;
        var T = TREAT[treat];
        L.treat = treat;
        L.base = T.base;
        L.byWord = T.byWord;

        // Letter case: change it from the line before whenever the treatment allows
        var ci0 = Math.floor(M.r(seed, 9, 409) * T.cases.length);
        if (T.cases.length > 1 && T.cases[ci0] === prevCase) ci0 = (ci0 + 1) % T.cases.length;
        var lineCase = T.cases[ci0];
        prevCase = lineCase;
        // Slanted type now and then: the hero of a slam or rise, or the small words of a karaoke line
        var slantHero = (treat === "slam" || treat === "rise") && M.r(seed, 10, 410) < 0.4;
        var slantMinor = treat === "karaoke" && M.r(seed, 11, 411) < 0.35;
        var pk = Math.floor(M.r(seed, 12, 412) * PAREN_ORDER.length);
        if (PAREN_ORDER[pk] === prevParen) pk = (pk + 1) % PAREN_ORDER.length;
        var parenLook = PAREN_ORDER[pk];
        // Words off the level line, like hand-set type: decode stays on its grid
        var stagger = treat === "decode" || M.r(seed, 13, 413) < 0.3 ? ""
                    : STAGGER_ORDER[Math.floor(M.r(seed, 14, 414) * STAGGER_ORDER.length)];
        var stAmp = 0.12 + 0.1 * M.r(seed, 15, 415);
        var stDir = M.r(seed, 16, 416) < 0.5 ? -1 : 1;
        L.stagger = stagger;
        L.tilt = stagger === "" ? 0 : (2 + 3 * M.r(seed, 17, 417)) * (M.r(seed, 18, 418) < 0.5 ? -1 : 1);

        // Backing vocals: everything between ( ) or [ ]
        var depth = 0;
        for (var pw = 0; pw < words.length; pw++) {
            var tx = words[pw].text;
            var opens = (tx.match(/[(\[]/g) || []).length, closes = (tx.match(/[)\]]/g) || []).length;
            words[pw].paren = depth > 0 || opens > 0;
            depth = Math.max(0, depth + opens - closes);
        }

        // Hero words: the held and the long content words, one or two per line, never a backing vocal
        var scores = words.map(function (w, wi) {
            var len = Array.from(bare(w.text)).length;
            return { wi: wi, sc: (w.end - w.start) * 2 + len * 0.12 - (FUNC[bare(w.text)] ? 2 : 0) - (w.paren ? 50 : 0) };
        }).sort(function (x, y) { return y.sc - x.sc; });
        var heroes = {};
        if (!words[scores[0].wi].paren) heroes[scores[0].wi] = true;
        if (words.length >= 6 && scores.length > 1 && !words[scores[1].wi].paren && scores[1].sc > scores[0].sc * 0.75) heroes[scores[1].wi] = true;
        var heroSx = treat === "slam" ? (M.r(seed, 3, 403) < 0.5 ? 1.24 : 0.74)
                   : ((treat === "rise" || treat === "marker") && M.r(seed, 4, 404) < 0.5 ? 0.82 : 1);

        // A line that is all backing vocal is set bigger and level: nothing else to sit beside
        var allParen = words.every(function (x) { return x.paren; });

        var n = 0, estW = 0, sideW = 0, mainCount = 0, mainIdx = [], sideIdx = [];
        for (var c0 = 0; c0 < words.length; c0++) {
            if (words[c0].paren && !allParen) sideIdx.push(c0); else mainIdx.push(c0);
        }
        for (var w = 0; w < words.length; w++) {
            var wd = words[w];
            var hero = heroes[w] === true;
            var J = T.jitter;
            wd.hero = hero;
            wd.censor = isProfane(wd.text);
            if (wd.paren) {
                var PL = PAREN[parenLook];
                wd.look = parenLook;
                wd.font = PL.font;
                wd.size = PL.size * (allParen ? 1.9 : 1);
                wd.sx = 1;
                wd.italic = false;
                wd.hollow = PL.hollow;
                wd.chars = cased(unbracket(wd.text), PL.upper);
                wd.rot = allParen ? PL.rot : 2 * M.rs(seed, w, 501);
                wd.jy = 0;
                wd.tone = PL.tone;
            } else {
                wd.look = "";
                wd.hollow = false;
                wd.font = hero ? T.hero : T.minor;
                wd.size = (hero ? 1 : T.minorSize) * (1 + 0.05 * J * M.rs(seed, w, 503));
                wd.sx = hero ? heroSx : 1;
                wd.italic = hero ? slantHero : slantMinor;
                var up = lineCase === "upper" || (lineCase === "mixed" && hero);
                wd.chars = cased(wd.text, up);
                wd.rot = J * 2.2 * M.rs(seed, w, 501);
                wd.jy = J * 0.035 * M.rs(seed, w, 502);
                // Stagger in em of this word, against the line's own baseline
                var m = mainCount++, sj = 0;
                if (stagger === "zig") { sj = (m % 2 ? 1 : -1) * stAmp; wd.rot += (m % 2 ? 2.5 : -2.5) * stDir; }
                else if (stagger === "stairs") sj = stDir * stAmp * 0.9 * (m - (mainIdx.length - 1) / 2);
                else if (stagger === "arc") { var ax = mainIdx.length > 1 ? m / (mainIdx.length - 1) * 2 - 1 : 0; sj = -stAmp * 1.6 * (1 - ax * ax); wd.rot += ax * 5 * stDir; }
                wd.jy += sj / wd.size;
                wd.tone = 1;
            }
            wd.g0 = n;
            wd.echo = hero && !wd.censor && wd.end - wd.start >= 0.75 && treat !== "decode";
            wd.echoDir = 1;     // echoes slide down, into the free space under the newest line
            wd.underline = hero && treat === "hand";
            var nc = wd.chars.length;
            wd.step = Math.min(0.11, (wd.end - wd.start) * 0.85 / Math.max(1, nc));
            wd.estW = nc * ADV[wd.font] * wd.size * wd.sx;
            if (wd.paren && !allParen) sideW = Math.max(sideW, wd.estW);
            else estW += wd.estW + (w > 0 ? 0.3 * T.minorSize : 0);
            n += nc;
        }
        for (var hp = 0; hp < words.length; hp++) if (words[hp].paren) { prevParen = parenLook; break; }

        // Pen marks, as if someone drew on the frame. Most lines get one, never the same kind twice
        // in a row; never on decode lines (the machine look), and no line mark under echoes.
        var hasEcho = words.some(function (x) { return x.echo; });
        var heroWi = scores[0].wi;
        var heroOk = heroes[heroWi] === true && !words[heroWi].censor;
        L.scribble = "";
        L.lineMark = "";
        L.heroMark = "";
        L.ringWi = -1;
        L.hiWi = -1;
        L.doodles = [];
        L.rough = maxi;
        L.heroWi = heroWi;
        L.heroOk = heroOk;
        L.wordMarks = {};
        L.boil = 8;
        if (!maxi) {
            if (treat !== "decode" && M.r(seed, 23, 423) < 0.82) {
                var pool = [];
                if (heroOk) pool = pool.concat(HERO_MARKS);
                if (!hasEcho) pool = pool.concat(LINE_MARKS);
                pool = pool.filter(function (k) { return k !== prevScribble; });
                if (pool.length > 0) {
                    L.scribble = pool[Math.floor(M.r(seed, 24, 424) * pool.length)];
                    if (HERO_MARKS.indexOf(L.scribble) >= 0) { L.heroMark = L.scribble; L.ringWi = heroWi; }
                    else L.lineMark = L.scribble;
                }
            }
            prevScribble = L.scribble;
        } else {
            // Everything at once: a mark under the line and one on its hero, a marker swipe behind
            // the hero, and doodles round it. Decode lines keep their letters clean but still get doodles.
            var loud = treat === "slam" || treat === "marker" ? 1 : 0;
            if (treat !== "decode") {
                if (heroOk) {
                    var hp0 = HERO_MARKS.filter(function (k) { return k !== prevHeroMark; });
                    L.heroMark = hp0[Math.floor(M.r(seed, 26, 426) * hp0.length)];
                    L.ringWi = heroWi;
                    if (L.heroMark !== "box" && M.r(seed, 27, 427) < 0.8) L.hiWi = heroWi;
                }
                if (M.r(seed, 28, 428) < 0.9) {
                    // echo copies slide down under the hero, so those lines only get the ring round them
                    var lp0 = (hasEcho ? ["wrap", "", ""] : LINE_MARKS_MAX).filter(function (k) { return k !== prevLineMark; });
                    L.lineMark = lp0[Math.floor(M.r(seed, 29, 429) * lp0.length)];
                }
            }
            prevHeroMark = L.heroMark;
            prevLineMark = L.lineMark;
            L.scribble = L.lineMark || L.heroMark;
            // More doodles on the loud lines and the ones with two heroes
            var nd = Math.min(5, 2 + 2 * loud + (scores.length > 1 && heroes[scores[1].wi] ? 1 : 0) + (M.r(seed, 30, 430) < 0.4 ? 1 : 0));
            var span = Math.max(0.4, (words[words.length - 1].end - start) * 0.8);
            for (var di = 0; di < nd; di++) {
                var spot = DOODLE_SPOTS[Math.floor(M.r(seed, di, 431) * DOODLE_SPOTS.length)];
                if (spot === "below" && L.lineMark) spot = "above";
                L.doodles.push({
                    kind: DOODLES[Math.floor(M.r(seed, di, 432) * DOODLES.length)],
                    spot: spot,
                    u: 0.08 + 0.84 * ((di + 0.5 * M.r(seed, di, 433)) / nd),   // spread along the line
                    k: 0.75 + 0.4 * M.r(seed, di, 434) + 0.15 * loud,           // size, share of base
                    rot: 24 * M.rs(seed, di, 435),
                    accent: M.r(seed, di, 436) < 0.55,
                    at: start - 0.1 + span * di / nd + 0.15 * M.r(seed, di, 437),
                    dur: 0.22 + 0.14 * M.r(seed, di, 438)
                });
            }
        }
        L.n = n;
        L.mainIdx = mainIdx;
        L.sideIdx = sideIdx;
        L.side = M.r(seed, 19, 419) < 0.5 ? -1 : 1;      // backing vocals go left (-1) or right (1)
        L.sideRows = sideIdx.length;
        L.sideH = sideIdx.length * PAREN[parenLook].size * 1.05;   // in base px
        L.estW = estW + (sideIdx.length ? sideW + 0.5 : 0);        // in units of base px
        L.enterAt = start - (T.byWord ? 0.3 : 0.45);
        lines.push(L);
    }

    // Piles
    var piles = [];
    var pile = null;
    var roles = maxi ? tempoRoles(lines) : [];
    for (var p = 0; p < lines.length; p++) {
        var cur = lines[p];
        var prev = p > 0 ? lines[p - 1] : null;
        var tr = maxi ? roles[p] : "";
        if (!pile || pile.lines.length >= pile.max || (prev && cur.start - prev.end > PILE_GAP) || tr) {
            // A pile is either a stack of up to three lines or a single line on its own, set bigger.
            // In the maximal cut a line stands alone only when the tempo says so (a peak or a rush).
            var solo = maxi ? tr !== "" : M.r(cur.seed, 20, 420) < 0.35;
            pile = { lines: [], seed: cur.seed, max: solo ? 1 : PILE_MAX, solo: solo };
            if (maxi) pile.role = tr;
            piles.push(pile);
        }
        if (pile.solo) cur.base = Math.round(cur.base * (pile.role === "peak" ? 1.4 : 1.22));
        cur.pile = pile;
        cur.slot = pile.lines.length;
        pile.lines.push(cur);
    }
    if (maxi) dressPiles(piles);
    var prevShot = "", prevExit = "";
    for (var q = 0; q < piles.length; q++) {
        var P = piles[q];
        var last = P.lines[P.lines.length - 1];
        var next = q + 1 < piles.length ? piles[q + 1].lines[0] : null;
        // Hold the pile at least a beat after its last word, then cut before the next pile sings
        var XO = maxi ? EXIT_ORDER_MAX : EXIT_ORDER;
        var xk = Math.floor(M.r(P.seed, 25, 425) * XO.length);
        if (XO[xk] === prevExit) xk = (xk + 1) % XO.length;
        P.exitStyle = XO[xk];
        // a peak smudges away slowly, a rush is struck out; the pile before a bulb cuts to the dark
        if (P.role === "peak") P.exitStyle = "smudge";
        else if (P.role === "rush") P.exitStyle = "strike";
        if (next && next.pile.fx === "bulb") P.exitStyle = "lift";
        // A pen exit needs room before the next pile sings; a tight cut falls back to the lift
        if (next && next.start - 0.3 - (EXITS[P.exitStyle] - EXIT_DUR) < Math.max(last.start + 0.4, last.end - 0.8)) P.exitStyle = "lift";
        prevExit = P.exitStyle;
        P.exitDur = EXITS[P.exitStyle];
        var extra = P.exitDur - EXIT_DUR;
        if (!next) P.exitAt = last.end + 1.4;
        else P.exitAt = Math.max(last.start + 0.4, Math.min(next.start - 0.3 - extra, last.end + 1.6));
        P.goneAt = P.exitAt + P.exitDur + 0.04 * PILE_MAX + 0.05;
        if (next) next.enterAt = Math.min(next.start - 0.08, Math.max(next.enterAt, P.exitAt + P.exitDur * 0.8));
        var sk = Math.floor(M.r(P.seed, 6, 406) * SHOT_ORDER.length);
        if (SHOT_ORDER[sk] === prevShot) sk = (sk + 1) % SHOT_ORDER.length;
        P.shot = SHOT_ORDER[sk];
        prevShot = P.shot;
        P.side = M.r(P.seed, 7, 407) < 0.5 ? -1 : 1;
        P.frameX = 0.03 * M.r(P.seed, 8, 408);
        // A single line sits off-centre, left or right, the way a title card would
        if (P.solo && M.r(P.seed, 21, 421) < 0.6) P.frameX = 0.06 + 0.04 * M.r(P.seed, 22, 422);
        if (P.role === "peak") P.frameX = 0;      // the peak takes the middle of the frame
        P.startAt = P.lines[0].enterAt;
    }
    for (var g = 0; g < lines.length; g++) lines[g].goneAt = lines[g].pile.goneAt;

    // Waiting for the singer: the intro and any long break between piles
    var gaps = [];
    if (lines.length > 0 && lines[0].enterAt >= GAP_MIN) gaps.push({ from: 0, to: lines[0].enterAt });
    for (var gq = 0; gq + 1 < piles.length; gq++) {
        var from = piles[gq].goneAt, to = piles[gq + 1].lines[0].enterAt;
        if (to - from >= GAP_MIN) gaps.push({ from: from, to: to });
    }
    return { lines: lines, piles: piles, gaps: gaps, seed: songSeed, max: maxi };
}

// The waiting dots between piles: { alpha, prog (0..1 towards the next line), t0 }
function gapAt(motion, t) {
    var gaps = motion && motion.gaps ? motion.gaps : [];
    for (var i = 0; i < gaps.length; i++) {
        var G = gaps[i];
        if (t < G.from || t >= G.to) continue;
        var alpha = M.clamp((t - G.from - 0.3) / 0.5) * M.clamp((G.to - t) / 0.35);
        return { alpha: alpha, prog: M.clamp((t - G.from) / (G.to - G.from)), t0: G.from };
    }
    return { alpha: 0, prog: 0, t0: 0 };
}

// Old film look for the whole stage: grain, flicker, a tear and fringe on cuts, a hair, scratches
function film(motion, t) {
    var f = { frame: Math.floor(t * 24), grain: 0.32, scan: 0.12, flicker: 1, chroma: 0, tear: 0,
              hair: 0, hairX: 0.1, hairAmp: 0.01, hairPhase: 0, scratchX: 0.5, scratchA: 0,
              smear: 0, smearDir: 1, bulge: 0 };
    if (!motion || !motion.lines) return f;
    var seed = motion.seed | 0;
    f.flicker = 1 + 0.045 * M.rs(seed, f.frame, 601);

    // Fringe as each line arrives and as slam heroes land; a tear as each pile cuts away
    var lines = motion.lines;
    for (var i = 0; i < lines.length; i++) {
        var L = lines[i];
        if (L.enterAt > t + 0.01) break;
        if (L.goneAt < t - 1) continue;
        var since = t - L.enterAt;
        if (since >= 0 && since < 0.4) f.chroma = Math.max(f.chroma, 3.5 * Math.exp(-since * 9));
        if (L.treat === "slam" || L.treat === "marker") {
            for (var w = 0; w < L.words.length; w++) {
                if (!L.words[w].hero) continue;
                var sl = t - (L.words[w].start - LEAD);
                if (sl < 0 || sl >= 0.3) continue;
                var k = Math.exp(-sl * 12);
                f.chroma = Math.max(f.chroma, 4 * k);
                // light smears sideways off the word as it hits, and the frame swells a touch
                if (k * 18 > f.smear) { f.smear = 18 * k; f.smearDir = M.r(L.seed, w, 611) < 0.5 ? -1 : 1; }
                f.bulge = Math.max(f.bulge, 0.05 * k);
            }
        }
        // A rush flickers its colour fringe on every word
        if (L.pile.role === "rush") {
            for (var rw = 0; rw < L.words.length; rw++) {
                var rs = t - (L.words[rw].start - LEAD);
                if (rs >= 0 && rs < 0.3) f.chroma = Math.max(f.chroma, 2.5 * Math.exp(-rs * 10));
            }
        }
        // A peak's big moment: the bulb switching on, or the hero landing
        if (L.pile.role === "peak") {
            var hit = t - peakOnAt(L);
            if (hit >= 0 && hit < 0.5) {
                var kp = Math.exp(-hit * 10);
                f.chroma = Math.max(f.chroma, 5 * kp);
                f.bulge = Math.max(f.bulge, 0.07 * kp);
            }
        }
        var ex = t - L.pile.exitAt, xs = L.pile.exitStyle;
        if (L.slot === 0 && ex >= 0 && ex < 0.12 && (xs === "lift" || !xs)) { f.tear = 1 - ex / 0.12; f.smear = Math.max(f.smear, 14 * f.tear); }
        if (L.slot === 0 && xs === "smudge" && ex >= 0 && ex < L.pile.exitDur) {
            f.smear = Math.max(f.smear, 24 * Math.sin(Math.PI * ex / L.pile.exitDur));
            f.smearDir = L.pile.side || 1;
        }
    }

    // A projector hair in a quarter of the 2.5 s slots, for 0.8 to 1.6 s, mostly near an edge
    var hs = Math.floor(t / 2.5);
    var hLife = 0.8 + 0.8 * M.r(seed, hs, 608);
    var hStart = hs * 2.5 + (2.5 - hLife) * M.r(seed, hs, 609);
    if (M.r(seed, hs, 602) < 0.25 && t >= hStart && t < hStart + hLife) {
        var u = (t - hStart) / hLife;
        f.hair = M.clamp(u * 5) * M.clamp((1 - u) * 5);
        var edge = M.r(seed, hs, 603);
        f.hairX = edge < 0.5 ? 0.04 + 0.16 * M.r(seed, hs, 604) : 0.8 + 0.16 * M.r(seed, hs, 604);
        f.hairAmp = 0.006 + 0.012 * M.r(seed, hs, 605);
        // slow drift plus the frame-to-frame weave of a film gate
        f.hairPhase = t * 0.8 + M.r(seed, hs, 606) * 6.28;
        f.hairX += 0.0015 * M.rs(seed, f.frame, 607);
    }
    // Scratches flash for a few frames at a time
    var ss = Math.floor(t / 0.16);
    if (M.r(seed, ss, 608) < 0.18) {
        f.scratchX = 0.06 + 0.88 * M.r(seed, ss, 609);
        f.scratchA = 0.6 + 0.4 * M.r(seed, f.frame, 610);
    }
    return f;
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

// Share of the box width a line may fill: less when its pile is set off-centre
function roomOf(L) { return 0.84 - 2 * (L && L.pile ? L.pile.frameX : 0); }
function fitOf(L, W) { return Math.min(1, (W * roomOf(L)) / Math.max(1, L.estW * L.base)); }
function heightOf(L, W) { return L.base * Math.max(1.3, (L.sideH || 0) + 0.2) * fitOf(L, W); }

// Where a line sits in its pile: { y, s, alpha, blur, fit } (y is the offset of its centre)
function lineState(L, t, W) {
    var st = { y: 0, s: 1, alpha: 1, blur: 0, fit: fitOf(L, W), sx: 1, dx: 0 };
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
    // call and response: the two lines of a "versus" duo step apart, left and right
    if (P.role === "duo" && P.fx === "versus" && P.lines.length > 1) {
        var ev = M.E.outQuart((t - P.lines[1].enterAt) / 0.4);
        st.dx = (L.slot === 0 ? -0.06 : 0.06) * W * (L.slot === 0 ? ev : 1);
    }
    st.alpha = M.lerp(0.4, 1, M.clamp((s - 0.6) / 0.4));
    if (t >= P.exitAt) {
        var ex = t - P.exitAt - 0.04 * L.slot, dur = P.exitDur || EXIT_DUR;
        if (P.exitStyle === "strike" || P.exitStyle === "scrawl") {
            // the pen goes through first (penStrokes), then the crossed-out line fades
            var qf = M.E.inCubic((ex - 0.55 * dur) / (0.45 * dur));
            st.alpha *= 1 - qf;
            st.blur = 6 * qf;
            st.y += 8 * qf;
        } else if (P.exitStyle === "smudge") {
            // dragged sideways under a thumb: it stretches, slides and blurs out
            var qs = M.clamp(ex / dur);
            st.sx = 1 + 0.28 * qs * qs;
            st.dx += (P.side || 1) * 46 * qs * qs;
            st.blur = 26 * qs;
            st.alpha *= 1 - M.E.inCubic(qs);
        } else {
            var qx = M.E.inCubic(ex / dur);
            st.y -= 36 * qx;
            st.alpha *= 1 - qx;
            st.blur = 14 * qx;
        }
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
    // pulls back from close: the line starts cropped big and settles
    case "dolly":  cam.s = M.lerp(1.16, 1, M.E.outQuart((t - P.startAt) / 1.4)); break;
    // looking up at the words from below
    case "low":    cam.rx = M.lerp(-24, -12, M.E.outCubic(cu)); cam.s = 1.03; cam.rot = -d * 2; break;
    // a slow barrel roll that never quite levels out
    case "roll":   cam.rot = d * M.lerp(-9, -3, inOutSine(cu)); cam.ry = d * 10; cam.s = 1.02; break;
    // rises from below the line and tips forward
    case "crane":  cam.y = H * 0.07 * (1 - e); cam.rx = M.lerp(14, 4, e); cam.s = 1.01 + 0.03 * cu; break;
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
    // a rush jolts the camera on every word
    if (P.role === "rush") {
        var R = P.lines[0], jolt = 0, jw = 0;
        for (var rw = 0; rw < R.words.length; rw++) {
            var js = t - (R.words[rw].start - LEAD);
            if (js >= 0 && js < 0.3) { var jk = Math.exp(-js * 14); if (jk > jolt) { jolt = jk; jw = rw; } }
        }
        cam.rot += 1.2 * jolt * (M.r(R.seed, jw, 453) < 0.5 ? -1 : 1);
        cam.s *= 1 + 0.02 * jolt;
    }
    // the stamp slams down and the frame shakes for a beat
    if (P.role === "peak" && P.fx === "stamp") {
        var sh = t - peakOnAt(L);
        if (sh >= 0 && sh < 0.25) {
            var fr = Math.floor(t * 60), amp = 4 * (1 - sh / 0.25);
            cam.x += amp * M.rs(P.seed, fr, 451);
            cam.y += amp * M.rs(P.seed, fr, 452);
        }
    }
    return cam;
}

function inOutSine(x) { x = M.clamp(x); return -(Math.cos(Math.PI * x) - 1) / 2; }

// Pen marks: strokes (up to three) of { x, y } points in px for a box of w x h.
//   role "line"  under the line (coil, under, double, zigzag, wave), drawn as the line is sung
//   role "hero"  round the hero word (ring, box, ticks, arrow), drawn just after it lands
//   role "exit"  through the line as its pile leaves (strike, scrawl)
// Each stroke "boils" (redraws with fresh wobble eight times a second) like hand-drawn animation.
function markKind(L, role) {
    if (!L) return "";
    if (role === "exit") {
        var xs = L.pile ? L.pile.exitStyle : "";
        return xs === "strike" || xs === "scrawl" ? xs : "";
    }
    if (role === "line") return L.lineMark || "";
    if (role === "hero") return L.heroMark || "";
    if (role === "hilite") return L.hiWi >= 0 ? "hilite" : "";
    return "";
}
function markProg(L, t, role) {
    var kind = markKind(L, role);
    if (!kind) return 0;
    if (role === "exit") {
        var P = L.pile;
        return M.E.outQuad((t - P.exitAt - 0.04 * L.slot) / (0.55 * P.exitDur));
    }
    if (role === "hilite") {
        var hw = L.words[L.hiWi];
        return M.E.outCubic((t - (hw.start - LEAD - 0.04)) / 0.26);
    }
    if (role === "hero") {
        var w = L.words[L.ringWi];
        var dur = kind === "ticks" ? 0.3 : (kind === "arrow" ? 0.5 : 0.42);
        return M.E.outQuad((t - (w.start - LEAD + 0.12)) / dur);
    }
    var ld = kind === "coil" ? 0.8 : (kind === "double" || kind === "wrap" ? 0.6 : 0.45);
    // short marks wait for the line to get going; the coil runs along with it
    var at = kind === "coil" ? L.start + 0.15 : L.start + Math.min(0.5, (L.end - L.start) * 0.4);
    return inOutSine((t - at) / ld);
}

function markShape(kind, sd, w, h) {
    var S = [];
    var i, u, n, pts;
    switch (kind) {
    case "coil": {
        var loops = Math.max(3, Math.round(w / (h * 1.7)));
        var a = w / (loops * 2 * Math.PI);
        var steps = loops * 20;
        pts = [];
        for (i = 0; i <= steps; i++) {
            var th = i / steps * loops * 2 * Math.PI;
            var li = Math.floor(th / (2 * Math.PI));
            // every loop its own size and lean, the way a hand never repeats itself
            var hk = 0.6 + 0.5 * M.r(sd, li, 801);
            var b = a * (1.6 + 1.1 * M.r(sd, li, 807));           // b > a draws the loops
            var lean = 0.25 * M.rs(sd, li, 808);
            var cy0 = Math.cos(th);
            var x = a * th - b * Math.sin(th) + b + lean * h * (1 - cy0) * 0.5;
            pts.push({ x: x * (w / (w + 2 * a * 2.7)), y: h / 2 - h / 2 * hk * cy0 + h * 0.15 * M.rs(sd, li, 802) });
        }
        S.push(pts);
        break;
    }
    case "under":
    case "double": {
        var rows = kind === "double" ? 2 : 1;
        for (var r = 0; r < rows; r++) {
            pts = [];
            var x0 = r ? 0.12 + 0.08 * M.r(sd, r, 811) : 0.01, x1 = r ? 0.84 + 0.1 * M.r(sd, r, 812) : 0.99;
            var sag = 0.18 * M.rs(sd, r, 813), y0 = 0.32 + r * 0.38;
            for (i = 0; i <= 24; i++) {
                u = i / 24;
                var y = y0 + sag * Math.sin(Math.PI * u);
                // the pen flicks up as it leaves the paper
                if (u > 0.9) y -= 0.9 * Math.pow((u - 0.9) / 0.1, 2) * (r ? 0.5 : 1);
                pts.push({ x: w * (x0 + (x1 - x0) * u), y: h * y });
            }
            S.push(pts);
        }
        break;
    }
    case "n1":
        S.push([{ x: w * 0.3, y: h * 0.25 }, { x: w * 0.55, y: h * 0.05 }, { x: w * 0.55, y: h * 0.95 }]);
        break;
    case "n2":
        pts = [];
        for (i = 0; i <= 10; i++) {
            var a2 = Math.PI * (1.1 + 1.15 * i / 10);
            pts.push({ x: w * (0.5 + 0.36 * Math.cos(a2)), y: h * (0.3 + 0.26 * Math.sin(a2)) });
        }
        pts.push({ x: w * 0.12, y: h * 0.95 }, { x: w * 0.9, y: h * 0.93 });
        S.push(pts);
        break;
    case "n3":
        pts = [];
        for (i = 0; i <= 8; i++) {
            var a3 = Math.PI * (-0.85 + 1.35 * i / 8);
            pts.push({ x: w * (0.48 + 0.34 * Math.cos(a3)), y: h * (0.27 + 0.23 * Math.sin(a3)) });
        }
        for (i = 0; i <= 10; i++) {
            var a4 = Math.PI * (-0.5 + 1.35 * i / 10);
            pts.push({ x: w * (0.48 + 0.4 * Math.cos(a4)), y: h * (0.72 + 0.25 * Math.sin(a4)) });
        }
        S.push(pts);
        break;
    case "rushline":
        // a tight zigzag with a fast under stroke below it
        n = Math.max(8, Math.round(w / (h * 0.5)));
        pts = [];
        for (i = 0; i <= n; i++)
            pts.push({ x: w * (i / n) + h * 0.08 * M.rs(sd, i, 818), y: h * ((i % 2 ? 0.62 : 0.12) + 0.08 * M.rs(sd, i, 819)) });
        S.push(pts);
        S.push([{ x: w * 0.02, y: h * (0.9 + 0.04 * M.rs(sd, 1, 820)) }, { x: w * 0.5, y: h * (0.86 + 0.05 * M.rs(sd, 2, 821)) },
                { x: w * 0.98, y: h * (0.92 + 0.04 * M.rs(sd, 3, 822)) }]);
        break;
    case "zigzag":
        n = Math.max(6, Math.round(w / (h * 0.75)));
        pts = [];
        for (i = 0; i <= n; i++)
            pts.push({ x: w * (i / n) + h * 0.12 * M.rs(sd, i, 814), y: h * ((i % 2 ? 0.78 : 0.22) + 0.1 * M.rs(sd, i, 815)) });
        S.push(pts);
        break;
    case "wave": {
        var per = 2.5 + 1.5 * M.r(sd, 1, 816), ph = M.r(sd, 2, 817) * 6.28;
        pts = [];
        for (i = 0; i <= 64; i++) {
            u = i / 64;
            pts.push({ x: w * u, y: h * (0.5 + 0.32 * Math.sin(u * per * 2 * Math.PI + ph) * (0.7 + 0.3 * Math.sin(u * 3.1 + ph))) });
        }
        S.push(pts);
        break;
    }
    case "hilite": {
        // a marker swipe through the middle of the word, a touch uphill
        pts = [];
        for (i = 0; i <= 8; i++) { u = i / 8; pts.push({ x: w * (-0.02 + 1.04 * u), y: h * (0.55 - 0.1 * u + 0.06 * M.rs(sd, i, 825)) }); }
        S.push(pts);
        break;
    }
    case "star": {
        // five points drawn in one go, the way a doodled star is
        pts = [];
        var a0 = -Math.PI / 2 + 0.3 * M.rs(sd, 1, 826);
        for (i = 0; i <= 5; i++) {
            var sa = a0 + i * 4 * Math.PI / 5;
            pts.push({ x: w / 2 + w * 0.48 * Math.cos(sa), y: h / 2 + h * 0.48 * Math.sin(sa) });
        }
        S.push(pts);
        break;
    }
    case "sparkle": {
        // a four-point twinkle with pinched sides, plus a tiny one beside it
        pts = [];
        for (i = 0; i <= 32; i++) {
            var ta = i / 32 * 2 * Math.PI;
            var rr = 0.12 + 0.38 * Math.pow(Math.abs(Math.cos(2 * ta)), 3);
            pts.push({ x: w / 2 + w * rr * Math.cos(ta), y: h / 2 + h * rr * Math.sin(ta) });
        }
        S.push(pts);
        S.push([{ x: w * 0.88, y: h * 0.02 }, { x: w * 0.88, y: h * 0.24 }]);
        S.push([{ x: w * 0.77, y: h * 0.13 }, { x: w * 0.99, y: h * 0.13 }]);
        break;
    }
    case "burst": {
        // a jagged comic burst
        n = 18;
        pts = [];
        for (i = 0; i <= n; i++) {
            var ba = i / n * 2 * Math.PI;
            var br = (i % 2 ? 0.26 : 0.5) * (0.85 + 0.25 * M.r(sd, i % n, 827));
            pts.push({ x: w / 2 + w * br * Math.cos(ba), y: h / 2 + h * br * Math.sin(ba) });
        }
        S.push(pts);
        break;
    }
    case "speed":
        // three motion lines, ragged at the back
        for (i = 0; i < 3; i++) {
            var sy = h * (0.25 + 0.25 * i), sx0 = w * (0.1 + 0.25 * M.r(sd, i, 828));
            S.push([{ x: sx0, y: sy }, { x: w * 0.98, y: sy - h * 0.06 }]);
        }
        break;
    case "spiral": {
        pts = [];
        for (i = 0; i <= 40; i++) {
            u = i / 40;
            var pa = u * 2.6 * 2 * Math.PI, pr = 0.04 + 0.46 * u;
            pts.push({ x: w / 2 + w * pr * Math.cos(pa), y: h / 2 + h * pr * Math.sin(pa) });
        }
        S.push(pts);
        break;
    }
    case "bang":
        // two exclamation marks, the dots as tiny loops
        for (i = 0; i < 2; i++) {
            var bx0 = w * (0.3 + 0.38 * i), lean0 = w * 0.06;
            S.push([{ x: bx0 + lean0, y: h * 0.02 }, { x: bx0 + lean0 * 0.4, y: h * 0.4 }, { x: bx0, y: h * 0.66 }]);
            var dpts = [];
            for (var dk = 0; dk <= 8; dk++) { var da = dk / 8 * 2 * Math.PI; dpts.push({ x: bx0 + w * 0.045 * Math.cos(da), y: h * 0.88 + h * 0.06 * Math.sin(da) }); }
            S.push(dpts);
        }
        break;
    case "heart": {
        pts = [];
        for (i = 0; i <= 40; i++) {
            var hta = i / 40 * 2 * Math.PI;
            var hx = 16 * Math.pow(Math.sin(hta), 3);
            var hy = 13 * Math.cos(hta) - 5 * Math.cos(2 * hta) - 2 * Math.cos(3 * hta) - Math.cos(4 * hta);
            pts.push({ x: w / 2 + w * 0.48 * hx / 16, y: h * 0.46 - h * 0.48 * hy / 16 });
        }
        S.push(pts);
        break;
    }
    case "cross":
        S.push([{ x: w * 0.1, y: h * 0.15 }, { x: w * 0.9, y: h * 0.85 }]);
        S.push([{ x: w * 0.88, y: h * 0.12 }, { x: w * 0.12, y: h * 0.9 }]);
        break;
    case "wrap":
    case "ring": {
        var th0 = -2.2 + 0.6 * M.rs(sd, 1, 803);
        pts = [];
        for (i = 0; i <= 64; i++) {
            u = i / 64;
            var ang = th0 + u * 1.18 * 2 * Math.PI;
            var grow = 1 + 0.1 * u + 0.05 * Math.sin(3 * ang + M.r(sd, 2, 804) * 6);
            pts.push({ x: w / 2 + w / 2 * grow * Math.cos(ang), y: h / 2 + h / 2 * grow * Math.sin(ang) });
        }
        S.push(pts);
        break;
    }
    case "box":
        // a rough box gone round twice, the second time a little off
        for (var bx = 0; bx < 2; bx++) {
            var o = bx * 0.05, k = bx ? 0.78 : 1.06;
            var cs = [[o, 0.04 - o], [1 + o * 0.5, o], [1 - o, 1 + o], [-o * 0.5, 0.96 + o * 0.3], [o + 0.04, -0.02]];
            pts = [];
            for (i = 0; i < 4; i++) {
                var c0 = cs[i], c1 = cs[i + 1];
                for (var sgi = 0; sgi < 8; sgi++) {
                    u = sgi / 8;
                    pts.push({ x: w * (c0[0] + (c1[0] - c0[0]) * u), y: h * (c0[1] + (c1[1] - c0[1]) * u) });
                }
            }
            pts.push({ x: w * cs[4][0], y: h * cs[4][1] });
            S.push(pts.slice(0, Math.max(2, Math.round(pts.length * k))));
        }
        break;
    case "ticks": {
        // three short emphasis strokes off one top corner, like a comic shout
        var right = M.r(sd, 3, 818) < 0.5;
        var ox = right ? w + h * 0.04 : -h * 0.04, oy = h * 0.08;
        for (var tk = 0; tk < 3; tk++) {
            var an = (right ? -1 : -1) * (Math.PI / 2) + (right ? 1 : -1) * (0.25 + tk * 0.42);
            var d0 = h * 0.12, d1 = h * (0.38 + 0.08 * M.r(sd, tk, 819));
            S.push([{ x: ox + Math.cos(an) * d0, y: oy + Math.sin(an) * d0 }, { x: ox + Math.cos(an) * (d0 + d1) * 0.5, y: oy + Math.sin(an) * (d0 + d1) * 0.5 },
                    { x: ox + Math.cos(an) * d1, y: oy + Math.sin(an) * d1 }]);
        }
        break;
    }
    case "arrow": {
        // a swoosh in from below-left (or right) that ends in an arrowhead at the word
        var fl = M.r(sd, 4, 820) < 0.5;
        var P0 = { x: -h * 0.95, y: h * 1.35 }, C = { x: -h * 0.85, y: h * 0.45 }, P1 = { x: -h * 0.08, y: h * 0.55 };
        pts = [];
        for (i = 0; i <= 20; i++) {
            u = i / 20;
            var q0 = (1 - u) * (1 - u), q1 = 2 * u * (1 - u), q2 = u * u;
            pts.push({ x: q0 * P0.x + q1 * C.x + q2 * P1.x, y: q0 * P0.y + q1 * C.y + q2 * P1.y });
        }
        var dxA = P1.x - C.x, dyA = P1.y - C.y, lA = Math.sqrt(dxA * dxA + dyA * dyA);
        dxA /= lA; dyA /= lA;
        var hl = h * 0.2;
        function rot(dx, dy, a) { return { x: dx * Math.cos(a) - dy * Math.sin(a), y: dx * Math.sin(a) + dy * Math.cos(a) }; }
        var hA = rot(-dxA, -dyA, 0.55), hB = rot(-dxA, -dyA, -0.55);
        S.push(pts);
        S.push([{ x: P1.x + hA.x * hl, y: P1.y + hA.y * hl }, P1, { x: P1.x + hB.x * hl, y: P1.y + hB.y * hl }]);
        if (fl) S = S.map(function (st) { return st.map(function (p) { return { x: w - p.x, y: p.y }; }); });
        break;
    }
    case "bulb": {
        // a bulb hanging from its cord: screw base on top, the glass below
        for (i = 0; i < 2; i++) S.push([{ x: w * 0.36, y: h * (0.06 + 0.1 * i) }, { x: w * 0.64, y: h * (0.04 + 0.1 * i) }]);
        pts = [];
        var gr = Math.min(w * 0.44, h * 0.36), gy = h * 0.6;
        var ga0 = -Math.PI / 2 + 0.55;
        pts.push({ x: w * 0.36, y: h * 0.24 });
        for (i = 0; i <= 36; i++) {
            var gang = ga0 + i / 36 * (2 * Math.PI - 1.1);
            pts.push({ x: w / 2 + gr * Math.cos(gang), y: gy + gr * Math.sin(gang) });
        }
        pts.push({ x: w * 0.64, y: h * 0.24 });
        S.push(pts);
        break;
    }
    case "tick":
        S.push([{ x: w * 0.08, y: h * 0.55 }, { x: w * 0.36, y: h * 0.88 }, { x: w * 0.94, y: h * 0.08 }]);
        break;
    case "cord":
        pts = [];
        for (i = 0; i <= 24; i++) { u = i / 24; pts.push({ x: w / 2 + w * 0.12 * Math.sin(u * 9 + M.r(sd, 1, 841) * 6) * u, y: h * u }); }
        S.push(pts);
        break;
    case "rays": {
        // focus lines out from the middle, like a manga panel
        n = 14;
        for (i = 0; i < n; i++) {
            var ra = (i + 0.4 * M.rs(sd, i, 842)) / n * 2 * Math.PI, r0 = 0.25 + 0.25 * M.r(sd, i, 843);
            S.push([{ x: w / 2 + w / 2 * r0 * Math.cos(ra), y: h / 2 + h / 2 * r0 * Math.sin(ra) },
                    { x: w / 2 + w / 2 * Math.cos(ra), y: h / 2 + h / 2 * Math.sin(ra) }]);
        }
        break;
    }
    case "inkfill":
        // a marker scribbled back and forth behind the whole line
        n = Math.max(12, Math.round(w / (h * 0.12)));
        pts = [];
        for (i = 0; i <= n; i++)
            pts.push({ x: w * (i / n) + h * 0.06 * M.rs(sd, i, 844), y: h * ((i % 2 ? 0.88 : 0.12) + 0.06 * M.rs(sd, i, 845)) });
        S.push(pts);
        break;
    case "strike": {
        // a fast line through the middle of the letters, sometimes back again
        var sl = 0.12 * M.rs(sd, 5, 821);
        pts = [];
        for (i = 0; i <= 20; i++) { u = i / 20; pts.push({ x: w * (-0.03 + 1.06 * u), y: h * (0.6 + sl * (u - 0.5)) }); }
        S.push(pts);
        if (M.r(sd, 6, 822) < 0.5) {
            pts = [];
            for (i = 0; i <= 20; i++) { u = i / 20; pts.push({ x: w * (1.02 - 1.0 * u), y: h * (0.68 - sl * (0.5 - u) + 0.04 * u) }); }
            S.push(pts);
        }
        break;
    }
    case "scrawl":
        // scribbled out: tight back-and-forth strokes marching across the line
        n = Math.max(10, Math.round(w / (h * 0.16)));
        pts = [];
        for (i = 0; i <= n; i++)
            pts.push({ x: w * (i / n) + h * 0.08 * M.rs(sd, i, 823), y: h * ((i % 2 ? 0.84 : 0.3) + 0.08 * M.rs(sd, i, 824)) });
        S.push(pts);
        break;
    }
    return S;
}

// Draws the strokes of one mark up to prog (0..1), one stroke after another. A rough mark (the
// maximal cut) gets a second pass of every stroke, wobblier and a little off, after rough.js.
function drawStrokes(shape, prog, sd, t, h, rough, boilRate) {
    var out = [];
    var boil = Math.floor(t * (boilRate || 8));
    var amp = Math.min(2.2, Math.max(0.8, h * 0.03));
    var ns = shape.length;
    var passes = rough && ns <= 3 ? 2 : 1;
    for (var pass = 0; pass < passes; pass++) {
        var pa = pass ? amp * 1.6 : amp;
        var ox = pass ? amp * 1.3 * M.rs(sd, 9, 829) : 0, oy = pass ? amp * 1.3 * M.rs(sd, 10, 830) : 0;
        for (var si = 0; si < ns; si++) {
            // strokes are drawn one after another; the second pass trails its first a little
            var sp = M.clamp(prog * ns - si);
            if (pass) sp = M.clamp(sp * 1.25 - 0.25);
            if (sp <= 0) break;
            var pts = shape[si], st = [];
            var last = (pts.length - 1) * sp, full = Math.floor(last);
            var ks = sd + boil + si * 31 + pass * 977;
            for (var k = 0; k <= full; k++)
                st.push({ x: pts[k].x + ox + pa * M.rs(ks, k, 805), y: pts[k].y + oy + pa * M.rs(ks, k, 806) });
            if (full < pts.length - 1 && last > full) {
                var f = last - full, p0 = pts[full], p1 = pts[full + 1];
                st.push({ x: p0.x + ox + (p1.x - p0.x) * f, y: p0.y + oy + (p1.y - p0.y) * f });
            }
            if (st.length > 1) out.push(st);
        }
    }
    return out;
}

function penStrokes(L, t, role, w, h) {
    var kind = markKind(L, role);
    var prog = markProg(L, t, role);
    if (!kind || prog <= 0 || w < 2 || h < 2) return [];
    var sd = L.seed + 77 + (role === "exit" ? 5 : 0) + (role === "hilite" ? 11 : 0);
    return drawStrokes(markShape(kind, sd, w, h), prog, sd, t, h, L.rough === true, L.boil);
}

// The mark on word wi: the hero mark on the hero, or a rush line's tick / small ring on any word
function wordMarkKind(L, wi) {
    if (!L) return "";
    if (wi === L.ringWi && L.heroMark) return L.heroMark;
    return (L.wordMarks && L.wordMarks[wi]) || "";
}
function wordStrokes(L, t, wi, w, h) {
    var kind = wordMarkKind(L, wi);
    if (!kind || w < 2 || h < 2) return [];
    if (wi === L.ringWi && kind === L.heroMark) return penStrokes(L, t, "hero", w, h);
    var prog = M.E.outQuad((t - (L.words[wi].start - LEAD)) / 0.18);
    if (prog <= 0) return [];
    var sd = L.seed + 900 + wi * 23;
    return drawStrokes(markShape(kind, sd, w, h), prog, sd, t, h, true, L.boil);
}

// Doodle di of a maximal line, in a w x h box: drawn quickly once its moment comes, then it stays
function doodleStrokes(L, t, di, w, h) {
    var d = L && L.doodles ? L.doodles[di] : null;
    if (!d || w < 2 || h < 2) return [];
    var prog = M.E.outQuad((t - d.at) / d.dur);
    if (prog <= 0) return [];
    var sd = L.seed + 300 + di * 17;
    return drawStrokes(markShape(d.kind, sd, w, h), prog, sd, t, h, true, L.boil);
}

// Where the lines of a pile sit, in stage px before the camera: one rect per line already in.
// alpha follows the pile's exit. bodyW (optional, per slot) is each line's measured width in px
// before scaling; the view passes it, since the script's width estimate is rough.
function pileState(P, t, W, H, anchorY, bodyW) {
    var out = { alpha: 1, rects: [] };
    if (!P) return out;
    if (t >= P.exitAt) out.alpha = 1 - M.clamp((t - P.exitAt) / (P.exitDur || EXIT_DUR));
    for (var k = 0; k < P.lines.length; k++) {
        var L = P.lines[k];
        if (L.enterAt > t) break;
        var ls = lineState(L, t, W);
        var sc = ls.fit * ls.s, w;
        var bw = bodyW && bodyW[k] > 0 ? bodyW[k] : 0;
        if (bw > 0) w = bw * ls.s * Math.min(ls.fit, W * roomOf(L) / bw) * ls.sx;
        else w = L.estW * L.base * sc * ls.sx;
        var h = L.base * sc;
        out.rects.push({ x: W / 2 + ls.dx - w / 2, y: anchorY + ls.y - h / 2, w: w, h: h });
    }
    return out;
}

function shiftShape(S, x, y) {
    return S.map(function (st) { return st.map(function (p) { return { x: p.x + x, y: p.y + y }; }); });
}
function bezier(p0, c0, c1, p1, n) {
    var pts = [];
    for (var i = 0; i <= n; i++) {
        var u = i / n, v = 1 - u;
        pts.push({ x: v * v * v * p0.x + 3 * v * v * u * c0.x + 3 * v * u * u * c1.x + u * u * u * p1.x,
                   y: v * v * v * p0.y + 3 * v * v * u * c0.y + 3 * v * u * u * c1.y + u * u * u * p1.y });
    }
    return pts;
}
function arrowHead(pts, len) {
    var a = pts[pts.length - 1], b = pts[pts.length - 2];
    var dx = a.x - b.x, dy = a.y - b.y, l = Math.max(0.001, Math.sqrt(dx * dx + dy * dy));
    dx /= l; dy /= l;
    function side(r) {
        var c = Math.cos(r), sn = Math.sin(r);
        return { x: a.x - len * (dx * c - dy * sn), y: a.y - len * (dx * sn + dy * c) };
    }
    return [side(0.5), a, side(-0.5)];
}

// The marks that tie a duo or a stack together, in stage px; [] for any other pile.
// Each part draws on its own clock, so a mark for line k waits for line k.
function pileStrokes(P, t, W, H, anchorY, bodyW) {
    if (!P || (P.role !== "duo" && P.role !== "stack") || !P.fx || P.lines.length < 2) return [];
    var R = pileState(P, t, W, H, anchorY, bodyW).rects;
    if (R.length === 0) return [];
    var b = P.lines[0].base, sd = P.seed + 600, out = [];
    function draw(S, prog, k) {
        if (prog <= 0) return;
        out = out.concat(drawStrokes(S, prog, sd + 37 * k, t, b, true, 8));
    }
    function grow(at, dur) { return M.E.outQuad((t - at) / dur); }
    function right(r) { return r.x + r.w; }
    function cy(r) { return r.y + r.h / 2; }
    var n = R.length, k, r0 = R[0], r1 = R[1];
    var minX = Math.min.apply(null, R.map(function (r) { return r.x; }));
    var maxX = Math.max.apply(null, R.map(right));
    var top = r0.y, bot = R[n - 1].y + R[n - 1].h;
    if (P.role === "duo") {
        if (n < 2) return [];
        var at = P.lines[1].enterAt, pd = 0.25 * b;
        switch (P.fx) {
        case "arrow": {
            // from line 1's end, out round the right side, back into line 2's end
            var a0 = { x: right(r0) + pd, y: cy(r0) }, a1 = { x: right(r1) + pd, y: cy(r1) };
            var bx = Math.max(a0.x, a1.x) + 1.4 * b;
            var pts = bezier(a0, { x: bx, y: a0.y - 0.3 * b }, { x: bx, y: a1.y + 0.3 * b }, a1, 22);
            draw([pts, arrowHead(pts, 0.35 * b)], grow(at, 0.5), 0);
            break;
        }
        case "brace": {
            var x0 = maxX + pd, xm = x0 + 0.45 * b, ym = (top + bot) / 2;
            var br = [{ x: x0, y: top }].concat(bezier({ x: x0, y: top }, { x: xm - 0.1 * b, y: top }, { x: xm - 0.25 * b, y: ym }, { x: xm, y: ym }, 8),
                     bezier({ x: xm, y: ym }, { x: xm - 0.25 * b, y: ym }, { x: xm - 0.1 * b, y: bot }, { x: x0, y: bot }, 8));
            draw([br], grow(at, 0.45), 0);
            draw(shiftShape(markShape("star", sd, 0.8 * b, 0.8 * b), xm + 0.15 * b, ym - 0.4 * b), grow(at + 0.35, 0.25), 1);
            break;
        }
        case "versus":
            // a slash before the reply
            draw([[{ x: r1.x - 0.55 * b, y: r1.y + r1.h }, { x: r1.x - 0.15 * b, y: r1.y }]], grow(at, 0.22), 0);
            break;
        case "swoop": {
            var s0 = { x: r0.x + 0.05 * r0.w, y: r0.y + r0.h + 2 }, s1 = { x: right(r1), y: r1.y + r1.h + 0.15 * b };
            draw([bezier(s0, { x: minX - 1.2 * b, y: (s0.y + s1.y) / 2 }, { x: r1.x + 0.2 * r1.w, y: s1.y + 0.45 * b }, s1, 26)],
                 grow(at, 0.6), 0);
            break;
        }
        case "pair": {
            // a dashed line out on the right joining the two ringed heroes' lines
            var d0 = { x: right(r0) + pd, y: cy(r0) }, d1 = { x: right(r1) + pd, y: cy(r1) };
            var dx = Math.max(d0.x, d1.x) + 0.8 * b;
            var path = bezier(d0, { x: dx, y: d0.y }, { x: dx, y: d1.y }, d1, 24), dash = [];
            for (k = 0; k + 1 < path.length; k += 3) dash.push([path[k], path[k + 1]]);
            draw(dash, grow(at, 0.45), 0);
            break;
        }
        }
    } else {
        var pd2 = 0.25 * b;
        switch (P.fx) {
        case "notebook": {
            // a margin brace down the left, and a tick at the end of each line once it is sung
            var xl = minX - pd2, xb = xl - 0.4 * b, ymid = (top + bot) / 2;
            var lb = bezier({ x: xl, y: top }, { x: xb + 0.1 * b, y: top }, { x: xb + 0.25 * b, y: ymid }, { x: xb, y: ymid }, 8)
                     .concat(bezier({ x: xb, y: ymid }, { x: xb + 0.25 * b, y: ymid }, { x: xb + 0.1 * b, y: bot }, { x: xl, y: bot }, 8));
            draw([lb], grow(P.lines[0].enterAt + 0.2, 0.4), 0);
            for (k = 0; k < n; k++)
                draw(shiftShape(markShape("tick", sd + k, 0.5 * b, 0.5 * b), right(R[k]) + pd2, R[k].y),
                     grow(P.lines[k].end, 0.18), 1 + k);
            break;
        }
        case "numbers":
            for (k = 0; k < n; k++)
                draw(shiftShape(markShape("n" + (k + 1), sd + k, 0.5 * b, 0.75 * b), R[k].x - 0.85 * b, cy(R[k]) - 0.375 * b),
                     grow(P.lines[k].enterAt + 0.1, 0.3), k);
            break;
        case "stairs":
            for (k = 1; k < n; k++) {
                var p0 = { x: R[k - 1].x - 0.15 * b, y: cy(R[k - 1]) }, p1 = { x: R[k].x - 0.15 * b, y: cy(R[k]) };
                var lx = Math.min(p0.x, p1.x) - 0.7 * b;
                var sp = bezier(p0, { x: lx, y: p0.y }, { x: lx, y: p1.y }, p1, 14);
                draw([sp, arrowHead(sp, 0.28 * b)], grow(P.lines[k].enterAt, 0.35), k);
            }
            break;
        case "frame": {
            var fx0 = minX - pd2, fx1 = maxX + pd2, fy0 = top - pd2, fy1 = bot + pd2;
            draw([[{ x: fx0, y: fy0 }, { x: fx1, y: fy0 }, { x: fx1, y: fy1 }, { x: fx0, y: fy1 }, { x: fx0 + 0.3 * b, y: fy0 - 0.1 * b }]],
                 grow(P.lines[0].enterAt + 0.2, 0.6), 0);
            draw(shiftShape(markShape("star", sd, 0.9 * b, 0.9 * b), fx1 - 0.45 * b, fy0 - 0.45 * b),
                 grow(P.lines[n - 1].enterAt + 0.2, 0.25), 1);
            break;
        }
        case "draft": {
            // the first line struck out when the last one lands (drawn at half alpha by the view)
            var last = P.lines[P.lines.length - 1];
            if (n < P.lines.length) break;
            draw([[{ x: r0.x - 0.05 * b, y: cy(r0) + 0.05 * b }, { x: right(r0) + 0.05 * b, y: cy(r0) - 0.05 * b }]],
                 grow(last.words[0].start - LEAD, 0.3), 0);
            break;
        }
        }
    }
    return out;
}

// A peak line's big move. The bulb drops on its cord from enterAt (a damped spring, overshooting and
// bouncing back up, swinging as it settles) and switches on at peakOnAt; until then the line sits
// in the dark. A spotlight ring closes over the hero's sung time, then dims the rest of the line.
function peakOnAt(L) {
    if (!L) return 0;
    var hw = L.words[L.heroWi >= 0 ? L.heroWi : 0];
    var land = hw.start - LEAD;
    var fx = L.pile ? L.pile.fx : "";
    var d = fx === "bulb" ? 0.7 : (PROP_D[fx] || 0);
    return d > 0 ? Math.max(land, L.enterAt + d) : land;
}
// When the balloon pops: near the end of the line, but never before it has lifted the word a while
function balloonPop(L) { return Math.max(peakOnAt(L) + 0.8, L.end - 0.1); }
//   { on, lit (0..1), dark (alpha multiplier), bulbY (hero em, 0 = rest), bulbTilt (deg), cone, heroS, restA,
//     heroDy (em), heroRot (deg), heroA (alpha multiplier) }
function peakState(L, t) {
    var st = { on: false, lit: 1, dark: 1, bulbY: 0, bulbTilt: 0, cone: 0, heroS: 1, restA: 1, heroDy: 0, heroRot: 0, heroA: 1 };
    if (!L || !L.pile || L.pile.role !== "peak") return st;
    var fx = L.pile.fx, on = peakOnAt(L);
    if (fx === "bulb") {
        var tau = Math.max(0, t - L.enterAt);
        st.bulbY = -4.5 * Math.exp(-4 * tau) * Math.cos(7 * tau);
        st.bulbTilt = 14 * Math.exp(-2.5 * tau) * Math.sin(6 * tau + 0.5);
        st.on = t >= on;
        st.lit = st.on ? M.E.outQuad((t - on) / 0.12) : 0;
        st.dark = st.on ? 1 : 0.25;
        st.cone = st.lit;
    } else if (fx === "spot") {
        var hw = L.words[L.heroWi];
        var close = hw.start - LEAD + Math.max(0.3, hw.end - hw.start);
        st.restA = M.lerp(1, 0.3, M.E.outQuad((t - close) / 0.25));
        st.heroS = 1 + 0.5 * M.E.outBack(M.clamp((t - close) / 0.3), 1.7);
        st.on = t >= on;
    } else {
        st.on = t >= on;
        var pw = L.words[L.heroWi >= 0 ? L.heroWi : 0], tp = t - on;
        switch (fx) {
        case "balloon": {
            // the balloon tugs the word up a little; when it pops the word drops back with a wobble
            var pop = balloonPop(L);
            if (t < pop) st.heroDy = -0.14 * M.E.outQuad(tp / 0.5);
            else { var tq = t - pop; st.heroDy = -0.14 * Math.exp(-10 * tq) * Math.cos(14 * tq); }
            break;
        }
        case "note": if (tp >= 0) st.heroS = 1 - 0.07 * Math.exp(-7 * tp) * Math.sin(16 * tp); break;
        case "plane": if (tp >= 0) st.heroRot = 5 * Math.exp(-6 * tp) * Math.sin(28 * tp); break;
        case "vine": {
            var tb = tp - Math.max(0.4, pw.end - pw.start);
            if (tb >= 0 && tb < 0.35) st.heroS = 1 + 0.12 * Math.sin(Math.PI * tb / 0.35);
            break;
        }
        case "fold":
            // the word waits faint inside the folded paper, then comes out big as it opens
            st.heroA = tp < 0 ? 0.3 : M.lerp(0.3, 1, M.clamp(tp / 0.15));
            if (tp >= 0) st.heroS = 1 + 0.35 * M.E.outBack(tp / 0.3, 1.8);
            st.restA = M.lerp(1, 0.55, M.E.outQuad(tp / 0.3));
            break;
        case "hand": if (tp >= 0) st.heroS = 1 - 0.05 * Math.sin(Math.PI * M.clamp(tp / 0.18)); break;
        }
    }
    return st;
}

// How far a jack-in-the-box hero is split open (0 closed .. ~1.1 overshooting); it shuts again a
// second after it bursts
function jackSplit(L, t) {
    var land = peakOnAt(L), tau = t - land;
    if (tau < 0) return 0;
    return M.E.outBack(tau / 0.16, 2.4) * (1 - M.E.outQuad((t - land - 1.0) / 0.22));
}
// The roll's place across the hero, 0 (left edge) .. 1 (right edge), as the word is sung
function rollAt(L, t) {
    var hw = L.words[L.heroWi >= 0 ? L.heroWi : 0];
    return M.clamp((t - peakOnAt(L)) / Math.max(0.4, hw.end - hw.start));
}

// Shapes for the props, in units of the hero's font size (1 = px), around their own origin
function place(S, cx, cy, rot, s) {
    var a = rot * Math.PI / 180, c = Math.cos(a), sn = Math.sin(a);
    return S.map(function (st) { return st.map(function (p) { return { x: cx + s * (p.x * c - p.y * sn), y: cy + s * (p.x * sn + p.y * c) }; }); });
}
function ellipsePts(cx, cy, rx, ry, a0, a1, n) {
    var pts = [];
    for (var i = 0; i <= n; i++) { var a = a0 + (a1 - a0) * i / n; pts.push({ x: cx + rx * Math.cos(a), y: cy + ry * Math.sin(a) }); }
    return pts;
}
function starPts(r, ri) {
    var pts = [];
    for (var i = 0; i <= 10; i++) { var a = -Math.PI / 2 + i * Math.PI / 5, rr = i % 2 ? ri : r; pts.push({ x: rr * Math.cos(a), y: rr * Math.sin(a) }); }
    return pts;
}
function cubicAt(p0, c0, c1, p1, u) {
    var v = 1 - u;
    return { x: v * v * v * p0.x + 3 * v * v * u * c0.x + 3 * v * u * u * c1.x + u * u * u * p1.x,
             y: v * v * v * p0.y + 3 * v * v * u * c0.y + 3 * v * u * u * c1.y + u * u * u * p1.y,
             dx: 3 * v * v * (c0.x - p0.x) + 6 * v * u * (c1.x - c0.x) + 3 * u * u * (p1.x - c1.x),
             dy: 3 * v * v * (c0.y - p0.y) + 6 * v * u * (c1.y - c0.y) + 3 * u * u * (p1.y - c1.y) };
}
function propShape(kind) {
    switch (kind) {
    case "balloon":
        return [ellipsePts(0, 0, 0.42, 0.52, -Math.PI / 2, 1.5 * Math.PI + 0.25, 40),
                [{ x: -0.07, y: 0.62 }, { x: 0, y: 0.52 }, { x: 0.07, y: 0.62 }, { x: -0.07, y: 0.62 }],
                ellipsePts(-0.02, -0.02, 0.26, 0.34, Math.PI * 1.08, Math.PI * 1.4, 8)];
    case "note":
        return [[{ x: -0.55, y: -0.5 }, { x: 0.55, y: -0.5 }, { x: 0.55, y: 0.3 }, { x: 0.35, y: 0.5 }, { x: -0.55, y: 0.5 }, { x: -0.55, y: -0.5 }],
                [{ x: 0.55, y: 0.3 }, { x: 0.4, y: 0.34 }, { x: 0.35, y: 0.5 }]];
    case "tape":
        return place([[{ x: -0.2, y: -0.07 }, { x: 0.2, y: -0.07 }, { x: 0.2, y: 0.07 }, { x: -0.2, y: 0.07 }, { x: -0.2, y: -0.07 }]], -0.47, -0.5, -35, 1)
            .concat(place([[{ x: -0.2, y: -0.07 }, { x: 0.2, y: -0.07 }, { x: 0.2, y: 0.07 }, { x: -0.2, y: 0.07 }, { x: -0.2, y: -0.07 }]], 0.47, -0.5, 35, 1));
    case "scribble": {
        var S = [];
        for (var r = 0; r < 3; r++) {
            var pts = [], x1 = r === 2 ? 0.05 : 0.38;
            for (var i = 0; i <= 12; i++) { var u = i / 12; pts.push({ x: -0.4 + (x1 + 0.4) * u, y: -0.22 + 0.2 * r + 0.035 * Math.sin(u * 19 + r) }); }
            S.push(pts);
        }
        return S;
    }
    case "plane":
        // nose at the origin pointing along +x; the first point is the nose
        return [[{ x: 0, y: 0 }, { x: -1, y: -0.38 }, { x: -0.78, y: 0 }, { x: -1, y: 0.22 }, { x: 0, y: 0 }],
                [{ x: 0, y: 0 }, { x: -0.78, y: 0 }, { x: -0.92, y: 0.12 }]];
    case "roll":
        return [ellipsePts(0, 0, 1, 1, 0, 2 * Math.PI + 0.2, 28), ellipsePts(0, 0, 0.42, 0.42, 0, 2 * Math.PI + 0.3, 16),
                [{ x: 0.5, y: 0 }, { x: 0.92, y: 0 }]];
    case "leaf":
        return [ellipsePts(0.5, 0, 0.5, 0.3, Math.PI, 3 * Math.PI, 16), [{ x: 0.05, y: 0 }, { x: 0.8, y: 0 }]];
    case "flower": {
        var F = [];
        for (var k = 0; k < 5; k++) {
            var a = -Math.PI / 2 + k * 2 * Math.PI / 5;
            F.push(ellipsePts(0.42 * Math.cos(a), 0.42 * Math.sin(a), 0.26, 0.26, a + Math.PI, a + 3 * Math.PI, 12));
        }
        F.push(ellipsePts(0, 0, 0.16, 0.16, 0, 2 * Math.PI, 10));
        return F;
    }
    case "hand":
        // a pointing hand, fingertip at the origin pointing along -x, the wrist off to +x
        return [[{ x: 0.6, y: -0.12 }, { x: 0.06, y: -0.1 }, { x: -0.02, y: -0.04 }, { x: 0, y: 0.04 }, { x: 0.06, y: 0.09 }, { x: 0.5, y: 0.09 }],
                [{ x: 0.6, y: -0.12 }, { x: 0.75, y: -0.28 }, { x: 0.92, y: -0.22 }, { x: 1.02, y: -0.04 }, { x: 1.1, y: 0.2 },
                 { x: 1.05, y: 0.45 }, { x: 0.8, y: 0.56 }, { x: 0.56, y: 0.46 }, { x: 0.5, y: 0.3 }, { x: 0.5, y: 0.09 }],
                [{ x: 0.5, y: 0.2 }, { x: 0.64, y: 0.21 }], [{ x: 0.52, y: 0.33 }, { x: 0.66, y: 0.35 }],
                [{ x: 1.02, y: -0.04 }, { x: 4.6, y: 1.3 }], [{ x: 1.05, y: 0.45 }, { x: 4.4, y: 1.8 }]];
    case "sticker":
        return [ellipsePts(0, 0, 1, 1, 0, 2 * Math.PI + 0.25, 24), starPts(0.58, 0.25)];
    }
    return [];
}

// The prop moves, as up to four pieces already placed in the hero word's own box (W wide, font
// size px, baseline at bl), so they move, scale and fade with the word:
//   [{ strokes, accent (accent ink, else text ink), a (alpha), pen (px), z, flat (flat caps) } x4]
// Nothing shows before the prop sets off at peakOnAt - PROP_D.
function noPiece() { return { strokes: [], accent: false, a: 0, pen: 1.5, z: 2, flat: false }; }
function peakPieces(L, t, W, px, bl) {
    var out = [noPiece(), noPiece(), noPiece(), noPiece()];
    if (!L || !L.pile || L.pile.role !== "peak" || PROP_FX.indexOf(L.pile.fx) < 0 || !(W > 1) || !(px > 1)) return out;
    var fx = L.pile.fx, hw = L.words[L.heroWi >= 0 ? L.heroWi : 0];
    var on = peakOnAt(L), start = on - PROP_D[fx], tau = t - start, tp = t - on;
    var sung = Math.max(0.4, hw.end - hw.start), sd = L.seed + 900;
    if (tau < 0) return out;
    function put(k, shape, prog, accent, a, penK, z, flat) {
        if (prog <= 0 || a <= 0.003) return;
        var S = drawStrokes(shape, prog, sd + k * 17, t, px, !flat, L.boil);
        if (S.length) out[k] = { strokes: S, accent: accent, a: Math.min(1, a), pen: Math.max(1.5, px * penK), z: z, flat: !!flat };
    }
    function fade(x, d) { return 1 - M.clamp(x / d); }
    switch (fx) {
    case "balloon": {
        // rises from below the line on a damped spring, swaying; its string ties to the word top
        var pop = balloonPop(L);
        var bAt = function (ta) {
            return { x: W / 2 + 0.25 * px + 0.2 * px * Math.sin(2.1 * ta),
                     y: bl - 2.3 * px + 4.0 * px * Math.exp(-3 * ta) * Math.cos(4 * ta), tilt: 6 * Math.sin(2.1 * ta + 0.8) };
        };
        if (t < pop) {
            var b = bAt(tau);
            put(0, place(propShape("balloon"), b.x, b.y, b.tilt, px), 1, true, 0.95, 0.05, 3);
            var knot = place([[{ x: 0, y: 0.62 }]], b.x, b.y, b.tilt, px)[0][0];
            var end = t >= on ? { x: W / 2, y: bl - 0.8 * px } : { x: knot.x - 0.15 * px * Math.sin(2.1 * tau), y: knot.y + 1.3 * px };
            var mid = { x: (knot.x + end.x) / 2 + 0.22 * px * Math.sin(3 * tau + 1), y: (knot.y + end.y) / 2 };
            put(1, [bezier(knot, mid, mid, end, 16)], 1, false, 0.7, 0.025, 2);
        } else {
            // pop: confetti flies out from where the balloon was and falls away
            var c = bAt(pop - start), q = (t - pop) / 0.8;
            if (q < 1) {
                var C = [];
                for (var i = 0; i < 14; i++) {
                    var ang = i / 14 * 2 * Math.PI + 0.3 * M.rs(sd, i, 911), dist = (1.0 + 0.9 * M.r(sd, i, 912)) * px * M.E.outQuad(q * 1.6);
                    var cx = c.x + Math.cos(ang) * dist, cy = c.y + Math.sin(ang) * dist + 1.6 * px * q * q;
                    var spin = ang + q * 9 * M.rs(sd, i, 913), len = 0.08 * px;
                    C.push([{ x: cx - len * Math.cos(spin), y: cy - len * Math.sin(spin) }, { x: cx + len * Math.cos(spin), y: cy + len * Math.sin(spin) }]);
                }
                put(2, C, 1, true, 1 - q * q, 0.05, 3);
            }
        }
        break;
    }
    case "note": {
        // flutters down side to side like a leaf, lands above the word, gets taped, then scribbled on
        var rx = W / 2 + 0.1 * px, ry = bl - 1.45 * px, rr = -5 + 4 * M.rs(sd, 1, 914);
        var u = M.clamp(tau / PROP_D.note), fall = 1 - (1 - u) * (1 - u), sw = Math.sin(u * 2.6 * Math.PI) * (1 - u);
        var nx = rx + 1.0 * px * sw, ny = ry - 3.4 * px * (1 - fall);
        var nr = rr + 40 * Math.sin(u * 2.6 * Math.PI + 0.4) * (1 - u) + (tp >= 0 ? 3 * Math.exp(-8 * tp) * Math.sin(20 * tp) : 0);
        put(0, place(propShape("note"), nx, ny, nr, px), 1, false, 0.85, 0.035, 2);
        if (tp >= 0) {
            put(1, place(propShape("tape"), nx, ny, nr, px), M.clamp(tp / 0.25), true, 0.75, 0.03, 3);
            put(2, place(propShape("scribble"), nx, ny, nr, px), M.clamp((tp - 0.2) / sung), true, 0.9, 0.035, 3);
        }
        break;
    }
    case "plane": {
        // a paper plane swoops in over the word, nose first, and sticks in its top right corner
        var p0 = { x: -2.5 * px, y: bl - 3.4 * px }, c0 = { x: W + 4.5 * px, y: bl - 4.6 * px };
        var c1 = { x: W + 0.7 * px, y: bl - 2.4 * px }, p1 = { x: W - 0.02 * px, y: bl - 0.7 * px };
        var fu = 1 - Math.pow(1 - M.clamp(tau / PROP_D.plane), 1.7);
        var P = cubicAt(p0, c0, c1, p1, fu);
        var head = Math.atan2(P.dy, P.dx) * 180 / Math.PI;
        if (tp >= 0) head += 9 * Math.exp(-5 * tp) * Math.sin(26 * tp);
        put(0, place(propShape("plane"), P.x, P.y, head, 0.9 * px), 1, false, 0.9, 0.035, 3);
        // a dashed trail behind it, fading once it has landed
        var T = [], u0 = Math.max(0, fu - 0.55);
        for (var d = 0; d < 12; d++) {
            var ua = u0 + (fu - u0) * d / 12, ub = u0 + (fu - u0) * (d + 0.5) / 12;
            var qa = cubicAt(p0, c0, c1, p1, ua), qb = cubicAt(p0, c0, c1, p1, ub);
            T.push([{ x: qa.x, y: qa.y }, { x: qb.x, y: qb.y }]);
        }
        if (fu - u0 > 0.02) put(1, T, 1, true, 0.55 * fade(tp, 0.5), 0.025, 1);
        if (tp >= 0) {
            var I = [];
            for (var k = 0; k < 3; k++) {
                var ia = -2.2 + k * 0.7;
                I.push([{ x: p1.x + 0.25 * px * Math.cos(ia), y: p1.y + 0.25 * px * Math.sin(ia) },
                        { x: p1.x + 0.5 * px * Math.cos(ia), y: p1.y + 0.5 * px * Math.sin(ia) }]);
            }
            put(2, I, M.clamp(tp / 0.12), true, fade(tp - 0.4, 0.3), 0.04, 3);
        }
        break;
    }
    case "roll": {
        // a tape roll rolls in from the left, crosses under the word as it is sung, then rolls off
        var r = 0.28 * px, yc = bl + 0.34 * px, yT = yc + r;
        var xc = tp < 0 ? -2.6 * px * (1 - M.E.outQuad(tau / PROP_D.roll)) : W * rollAt(L, t);
        var off = tp - sung, ra = 1;
        if (off > 0) { xc = W + 3 * px * M.E.inCubic(off / 0.6); ra = fade(off - 0.2, 0.4); }
        put(0, place(propShape("roll"), xc, yc, (xc + 2.6 * px) / r * 180 / Math.PI, r), 1, false, 0.85 * ra, 0.035, 3);
        var tx = Math.min(xc, W + 0.05 * px);
        if (tx > 0) {
            var tape = [];
            for (var j = 0; j <= 10; j++) tape.push({ x: -0.05 * px + (tx + 0.05 * px) * j / 10, y: yT - 0.08 * px + 0.02 * px * Math.sin(j * 1.7) });
            put(1, [tape], 1, true, 0.5, 0.16, -1, true);
        }
        break;
    }
    case "vine": {
        // grows from the word's bottom left, under it and up its right side; leaves on the way, and a
        // flower that blooms as the word ends
        var V = bezier({ x: -0.12 * px, y: bl + 0.18 * px }, { x: W * 0.35, y: bl + 0.42 * px }, { x: W * 0.65, y: bl + 0.05 * px }, { x: W + 0.2 * px, y: bl + 0.26 * px }, 24)
            .concat(bezier({ x: W + 0.2 * px, y: bl + 0.26 * px }, { x: W + 0.42 * px, y: bl + 0.1 * px }, { x: W + 0.3 * px, y: bl - 0.9 * px }, { x: W - 0.2 * px, y: bl - 1.05 * px }, 16).slice(1));
        var tipC = { x: W - 0.32 * px, y: bl - 1.3 * px };
        var g = M.clamp(tp / sung);
        put(0, [V], g, false, 0.75, 0.035, 1);
        var Lv = [];
        for (var lk = 0; lk < 4; lk++) {
            var fk = 0.18 + 0.19 * lk, le = M.E.outBack((g - fk) / 0.12, 2);
            if (g <= fk) continue;
            var vi = Math.round(fk * (V.length - 1)), va = V[vi], vb = V[Math.min(V.length - 1, vi + 1)];
            var tang = Math.atan2(vb.y - va.y, vb.x - va.x) * 180 / Math.PI, side = lk % 2 ? 1 : -1;
            Lv = Lv.concat(place(propShape("leaf"), va.x, va.y, tang + side * 55, 0.38 * px * Math.max(0.01, le)));
        }
        if (Lv.length) put(1, Lv, 1, true, 0.7, 0.03, 1);
        var tb = tp - sung;
        if (tb >= 0) put(2, place(propShape("flower"), tipC.x, tipC.y, 20 * tb, 0.45 * px * Math.max(0.01, M.E.outBack(tb / 0.3, 2.2))), 1, true, 1, 0.04, 3);
        break;
    }
    case "jack": {
        // the word splits open and a spring with a star boings out of the gap, wobbles, and goes back
        var sp = jackSplit(L, t);
        if (sp < 0.02) break;
        var nc = hw.chars.length, gx = W * (nc > 1 ? Math.ceil(nc / 2) / nc : 0.5), base = bl - 0.25 * px;
        var ext = sp * Math.max(0, 1 - Math.exp(-5 * tp) * Math.cos(13 * tp)), hgt = 1.15 * px * ext;
        var tilt = 9 * Math.exp(-3.5 * tp) * Math.sin(11 * tp);
        var Z = [];
        for (var z = 0; z <= 9; z++) Z.push({ x: (z === 0 || z === 9 ? 0 : (z % 2 ? -0.2 : 0.2)), y: -z / 9 * hgt / px });
        put(0, place([Z], gx, base, tilt, px), 1, false, 0.85, 0.035, 3);
        var top = place([[{ x: 0, y: -hgt / px - 0.42 }]], gx, base, tilt, px)[0][0];
        put(1, place([starPts(0.42, 0.18)], top.x, top.y, tilt * 1.5, px), 1, true, 1, 0.045, 3);
        var B = [];
        for (var bk = 0; bk < 4; bk++) {
            var ba = -Math.PI * (0.15 + 0.233 * bk);
            B.push([{ x: gx + 0.45 * px * Math.cos(ba), y: base - 0.3 * px + 0.45 * px * Math.sin(ba) },
                    { x: gx + 0.75 * px * Math.cos(ba), y: base - 0.3 * px + 0.75 * px * Math.sin(ba) }]);
        }
        put(2, B, M.clamp(tp / 0.1), true, fade(tp - 0.3, 0.3), 0.035, 2);
        break;
    }
    case "fold": {
        // a folded paper behind the word opens out panel by panel, an accordion pulled flat
        var Wp = W + 0.7 * px, cxf = W / 2, topY = bl - 1.05 * px, Hp = 1.35 * px, pw = Wp / 4;
        var widths = [pw], all = 0;
        for (var pk = 1; pk < 4; pk++) { var e = M.E.outBack((tau - (pk - 1) * 0.2) / 0.2, 1.4); widths.push(pw * Math.max(0, e)); all += M.clamp(e) / 3; }
        var cur = widths.reduce(function (a, b2) { return a + b2; }, 0);
        var xs = [cxf - cur / 2];
        for (var wk = 0; wk < 4; wk++) xs.push(xs[wk] + widths[wk]);
        var dip = function (j) { return (j % 2 ? 1 : -1) * 0.14 * px * (1 - all); };
        var outline = [], creases = [];
        for (var j2 = 0; j2 <= 4; j2++) outline.push({ x: xs[j2], y: topY + dip(j2) });
        for (var j3 = 4; j3 >= 0; j3--) outline.push({ x: xs[j3], y: topY + Hp + dip(j3) });
        outline.push(outline[0]);
        for (var j4 = 1; j4 < 4; j4++) if (widths[j4] > 0.02 * px) creases.push([{ x: xs[j4], y: topY + dip(j4) }, { x: xs[j4], y: topY + Hp + dip(j4) }]);
        put(0, [outline], 1, false, 0.8, 0.035, -1);
        if (creases.length) put(1, creases, 1, false, 0.4, 0.025, -1);
        if (tp >= 0) put(2, [[{ x: xs[4] - 0.3 * px, y: topY }, { x: xs[4] - 0.3 * px, y: topY + 0.3 * px }, { x: xs[4], y: topY + 0.3 * px }]], M.clamp(tp / 0.2), true, 0.8, 0.035, -1);
        break;
    }
    case "hand": {
        // a drawn hand reaches in from the bottom right, presses a sticker on the word's top right
        // corner, and pulls back; the sticker stays
        var sx = W - 0.05 * px, sy = bl - 0.8 * px;
        var away = tp < 0 ? 1 - M.E.outCubic(tau / PROP_D.hand) : M.E.inCubic((tp - 0.35) / 0.45);
        var press = tp >= 0 ? 1 - 0.08 * Math.sin(Math.PI * M.clamp(tp / 0.18)) : 1;
        if (away < 0.999) put(0, place(propShape("hand"), sx + 0.08 * px + 3.5 * px * away, sy + 0.05 * px + 3.2 * px * away, 30, px * press), 1, false, 0.9, 0.035, 4);
        if (tp >= 0) {
            put(1, place(propShape("sticker"), sx, sy, -14, 0.32 * px * Math.max(0.01, M.E.outBack(tp / 0.18, 2.5))), 1, true, 1, 0.04, 3);
            var Sp = [];
            for (var sk = 0; sk < 3; sk++) {
                var sa = -2.4 + sk * 0.75;
                Sp.push([{ x: sx + 0.45 * px * Math.cos(sa), y: sy + 0.45 * px * Math.sin(sa) }, { x: sx + 0.7 * px * Math.cos(sa), y: sy + 0.7 * px * Math.sin(sa) }]);
            }
            put(2, Sp, M.clamp((tp - 0.05) / 0.12), true, fade(tp - 0.5, 0.3), 0.035, 3);
        }
        break;
    }
    }
    return out;
}
var PEAK_PARTS = { bulb: ["bulb", "cord", "glow"], spot: ["ring"], rays: ["rays"], ink: ["ink"], stamp: ["stamp"] };
// Strokes for one part of a peak's move in a w x h box; [] when the pile's fx has no such part
function peakStrokes(L, t, part, w, h) {
    if (!L || !L.pile || L.pile.role !== "peak" || w < 2 || h < 2) return [];
    var parts = PEAK_PARTS[L.pile.fx];
    if (!parts || parts.indexOf(part) < 0) return [];
    var hw = L.words[L.heroWi >= 0 ? L.heroWi : 0], land = hw.start - LEAD, on = peakOnAt(L);
    var kind = part, prog = 0;
    switch (part) {
    case "bulb":
    case "cord": prog = M.clamp((t - L.enterAt) / 0.2); break;
    case "glow": kind = "rays"; prog = M.E.outQuad((t - on) / 0.2); break;
    case "rays": prog = inOutSine((t - land + 0.05) / Math.max(0.6, L.end - land)); break;
    case "ring": prog = M.E.outQuad((t - land) / Math.max(0.3, hw.end - hw.start)); break;
    case "stamp": kind = "box"; prog = M.E.outQuad((t - land + 0.04) / 0.12); break;
    case "ink": kind = "inkfill"; prog = M.clamp((t - L.start) / Math.max(0.4, L.end - L.start)); break;
    }
    if (prog <= 0) return [];
    var sd = L.seed + 500 + part.length * 13;
    return drawStrokes(markShape(kind, sd, w, h), prog, sd, t, h, true, L.boil);
}

// One word: { s, alpha, rot (deg), dx, dy (em), ghosts: [{ dx, dy (em), a } x4], bar, barDx [3] (em), under }
//   bar      0..1 how far the redaction bar has slid across a profane word
//   barDx    the bar's three strips glitch sideways now and then, showing scraps underneath
//   under    0..1 hand-drawn underline under a hand-lettered hero
function wordFx(L, t, wi) {
    var fx = wordFxBase(L, t, wi);
    if (!L || !L.pile || L.pile.role !== "peak") return fx;
    // A peak: the line waits in the dark for the bulb, and a spotlight dims all but the hero
    var ps = peakState(L, t);
    fx.alpha *= ps.dark;
    if (wi === L.heroWi) { fx.s *= ps.heroS; fx.dy += ps.heroDy; fx.rot += ps.heroRot; fx.alpha *= ps.heroA; }
    else fx.alpha *= ps.restA;
    return fx;
}
function wordFxBase(L, t, wi) {
    var fx = { s: 1, alpha: 1, rot: 0, dx: 0, dy: 0, ghosts: [g0(), g0(), g0(), g0()], bar: 0, barDx: [0, 0, 0], under: 0 };
    if (!L || !L.words[wi]) return fx;
    var w = L.words[wi];
    var land = w.start - LEAD;

    if (w.censor) {
        fx.bar = M.E.outExpo((t - land + 0.1) / 0.14);
        var slot = Math.floor(t * 7);
        for (var b = 0; b < 3; b++)
            if (M.r(L.seed + wi, slot * 3 + b, 701) < 0.28) fx.barDx[b] = 0.32 * M.rs(L.seed + wi, slot * 3 + b, 702);
    }

    if (w.paren) {
        // Backing vocals come in on their own words, sliding out from the line's side
        var qp = (t - (land - 0.2)) / 0.2;
        if (qp <= 0) { fx.alpha = 0; return fx; }
        var ep = M.E.outQuart(qp);
        fx.alpha = ep;
        fx.dx = (L.side || 1) * 0.6 * (1 - ep);
        return fx;
    }

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
    } else if (L.treat === "marker") {
        // Sticker stamp: drops in big and twisted, settles with a little overshoot
        var qm = (t - (land - 0.12)) / 0.12;
        if (qm <= 0) { fx.alpha = 0; return fx; }
        var em = M.E.outBack(qm, 2.2);
        fx.s = M.lerp(1.45, 1, em);
        fx.alpha = M.clamp(qm * 3);
        fx.rot = (1 - M.clamp(qm)) * 14 * M.rs(L.seed, wi, 703);
    } else if (L.treat === "hand") {
        // Letters write themselves (letterState); the word only needs to exist from its first stroke
        if (t < land - 0.04) { fx.alpha = 0; return fx; }
        if (w.underline) fx.under = M.E.outCubic((t - w.end + 0.1) / 0.32);
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

// One letter: { glyph ("" = real letter), alpha, dx, dy (em), rot (deg), clip, reveal (0..1 from the
// left), tone (0.42 waiting .. 1 sung), flash }
function letterState(L, t, wi, ci) {
    var st = letterStateBase(L, t, wi, ci);
    if (!L || !L.pile || L.pile.role !== "peak" || wi !== L.heroWi) return st;
    var nc = L.words[wi].chars.length;
    if (L.pile.fx === "jack") {
        // the two halves of the word part for the spring
        if (nc > 1) st.dx += (ci < nc / 2 ? -1 : 1) * 0.28 * jackSplit(L, t);
        else st.dx -= 0.28 * jackSplit(L, t);
    } else if (L.pile.fx === "roll") {
        // each letter hops as the roll passes under it
        var p = rollAt(L, t);
        if (p > 0 && p < 1) { var d = (p - (ci + 0.5) / nc) * nc; st.dy -= 0.16 * Math.exp(-d * d * 1.5); }
    }
    return st;
}
function letterStateBase(L, t, wi, ci) {
    var st = { glyph: "", alpha: 1, dx: 0, dy: 0, rot: 0, clip: false, reveal: 1, tone: 1, flash: 0 };
    if (!L || !L.words[wi]) return st;
    var w = L.words[wi];
    var nc = w.chars.length;
    var i = w.g0 + ci;
    var span = Math.max(1, L.n - 1);
    var land = w.start - LEAD;

    // Sung fill (line-triggered treatments show the line before it is sung)
    var wp = (t - land) / Math.max(0.05, w.end - w.start);
    if (!L.byWord) st.tone = 0.42 + 0.58 * M.clamp(wp * nc - ci);

    // A profane word never shows its letters: noise glyphs under the bar
    if (w.censor) {
        st.glyph = M.poolGlyph(L.seed, i, Math.floor(t * 12));
        st.tone = 0.85;
    }

    if (w.paren) { st.tone *= w.tone; return st; }

    if (L.treat === "rise") {
        // Letters rise from a baseline mask, cascading across the line within half a second
        var t0 = L.enterAt + Math.min(0.033, 0.5 / span) * i;
        var e = M.E.outQuint((t - t0) / 0.24);
        if (e <= 0) { st.alpha = 0; return st; }
        if (e < 1) { st.clip = true; st.dy = 1.15 * (1 - e); }
    } else if (L.treat === "decode" && !w.censor) {
        var ta = L.enterAt + 0.3 * i / span;
        if (t < ta) { st.alpha = 0; return st; }
        var tl = land + (ci + 1) * w.step;
        if (t < tl - 0.12) { st.glyph = M.poolGlyph(L.seed, i, Math.floor(t * 5)); st.tone = 0.3; }
        else if (t < tl) { st.glyph = M.poolGlyph(L.seed, i, Math.floor(t * 30)); st.tone = 0.7; }
        else { var f = 1 - M.clamp((t - tl) / 0.35); st.flash = f * f; st.tone = 1; }
    } else if (L.treat === "soft") {
        // Tracking closes in as the word fades up
        var es = M.E.outQuart((t - (land - 0.42)) / 0.42);
        st.dx = (ci - (nc - 1) / 2) * 0.16 * (1 - es);
    } else if (L.treat === "hand" && !w.paren) {
        // Handwriting: each letter is drawn left to right in the time it is sung, never quite level
        var ts = land + ci * w.step * 0.9;
        var rv = (t - ts) / Math.max(0.05, w.step * 1.1);
        if (rv <= 0) { st.alpha = 0; return st; }
        st.reveal = M.E.outQuad(rv);
        st.rot = 4 * M.rs(L.seed, i, 704);
        st.dy = 0.04 * M.rs(L.seed, i, 705);
    } else if (L.treat === "marker") {
        st.rot = 3 * M.rs(L.seed, i, 706);
        st.dy = 0.03 * M.rs(L.seed, i, 707);
    }
    return st;
}
