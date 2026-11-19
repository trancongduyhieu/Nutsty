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
// The maximal cut drops decode: its scrambling glyphs fight the pen marks
var TREAT_ORDER_MAX = ["slam", "rise", "karaoke", "hand", "marker"];
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
var PROP_D = {
    balloon: 0.9, note: 1.0, plane: 0.8, roll: 0.7, vine: 0, jack: 0, fold: 0.6, hand: 0.6,
    shatter: 0.6, snap: 0.7, rip: 0.5,
    spray: 0.7, micdrop: 0.6, tapex: 0.5,
    disco: 0.8, eq: 0.6, laser: 0.6,
    calm_leaf: 0.8, droplet: 0.6, moonrise: 0.7,
    classic_vinyl: 0.8, vinyl: 0.8, classic_smoke: 0.7, smoke: 0.7, horn: 0.7,
    flash: 0.6, focus: 0.7, sakura: 0.8,
    sunrise: 0.8, flock: 0.8, folk_sprout: 0.7, sprout: 0.7
};
// a prop lands no sooner than this after its line starts coming in, so the line is whole by then
var PROP_SETTLE = 0.6;
var PEAK_FX = ["bulb", "spot", "rays", "ink", "stamp"].concat(PROP_FX);
var SHARED_PEAKS = ["spot", "rays", "ink", "stamp"];
var DUO_FX = ["arrow", "brace", "versus", "swoop", "pair"];
var STACK_FX = ["notebook", "numbers", "stairs", "frame", "draft"];
var PILE_DOODLES = 5;     // doodles a whole duo or stack may carry
var RUSH_DOODLES = 10;    // one per word on a rush line, at most this many
var RUSH_KINDS = ["speed", "sparkle", "bang", "burst"];
var SETS = {
    sweet: { doodles: DOODLES, rush: RUSH_KINDS, peaks: PEAK_FX },
    rough: {
        doodles: ["bolt", "crack", "spike", "cross", "bang"],
        rush: ["bolt", "crack", "spike", "bang"],
        peaks: ["shatter", "snap", "rip"].concat(SHARED_PEAKS)
    },
    street: {
        doodles: ["crown", "drip", "arrow", "tag", "burst"],
        rush: ["crown", "drip", "arrow", "burst"],
        peaks: ["spray", "micdrop", "tapex"].concat(SHARED_PEAKS)
    },
    dance: {
        doodles: ["wave", "dots", "beam", "grid", "sparkle"],
        rush: ["wave", "dots", "beam", "sparkle"],
        peaks: ["disco", "eq", "laser"].concat(SHARED_PEAKS)
    },
    calm: {
        doodles: ["cloud", "drop", "ripple", "leaf", "moon"],
        rush: ["cloud", "drop", "ripple", "leaf"],
        peaks: ["calm_leaf", "droplet", "moonrise"].concat(SHARED_PEAKS)
    },
    classic: {
        doodles: ["note", "notes", "smoke", "vinyl", "mic"],
        rush: ["note", "notes", "smoke", "vinyl"],
        peaks: ["classic_vinyl", "classic_smoke", "horn"].concat(SHARED_PEAKS)
    },
    anime: {
        doodles: ["star4", "speed", "sweat", "anger", "sparkle"],
        rush: ["star4", "speed", "sweat", "anger"],
        peaks: ["flash", "focus", "sakura"].concat(SHARED_PEAKS)
    },
    folk: {
        doodles: ["sun", "sprout", "bird", "hill", "star"],
        rush: ["sun", "sprout", "bird", "hill"],
        peaks: ["sunrise", "flock", "folk_sprout"].concat(SHARED_PEAKS)
    }
};
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
// "more" peaks: any line sung slower than the song's median, after lines no slower than it
var TEMPO_MORE = { slow: 0.95, prevFast: 0.85, peakMinDur: 0.9 };
function tempoRoles(lines, more) {
    var T = more ? TEMPO_MORE : TEMPO;
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
            if (!lines[i].guessEnd && r <= T.slow * med && lines[i].end - lines[i].start >= T.peakMinDur && prev.length > 0 && prevMean >= T.prevFast * med
                && !(more && roles[i - 1] === "peak"))
                role = "peak";
            else if (r >= hi && r > med && roles[i - 1] !== "rush") role = "rush";
        }
        roles.push(role);
    }
    return roles;
}

// Rate of a whole song: median letters per second across non-empty lines
function songMedianRate(lyrics) {
    if (!lyrics || lyrics.length === 0) return 0;
    var rates = [];
    for (var i = 0; i < lyrics.length; i++) {
        var entry = lyrics[i];
        if (!entry) continue;
        if (entry.words && entry.words.length > 0) {
            var r = rateOf(entry);
            if (r > 0) rates.push(r);
        } else {
            var start = M.toSec(entry.time !== undefined ? entry.time : entry.startTime);
            var nextStart = i + 1 < lyrics.length ? M.toSec(lyrics[i + 1].time !== undefined ? lyrics[i + 1].time : lyrics[i + 1].startTime) : start + 4;
            var words = M.wordsOf(entry, nextStart);
            if (words && words.length > 0) {
                var L = { start: start, end: words[words.length - 1].end, words: words };
                var r2 = rateOf(L);
                if (r2 > 0) rates.push(r2);
            }
        }
    }
    if (rates.length === 0) return 0;
    rates.sort(function (a, b) { return a - b; });
    return quantile(rates, 0.5);
}

var LOVE_WORDS = {};
("yêu thương nhớ tim hôn love loving lover loves loved baby babe heart hearts kiss kisses kissing kissed darling sweetheart honey")
    .split(" ").forEach(function (w) { if (w) LOVE_WORDS[w] = true; });

// Love-word threshold tuned on the 14 real .lrc files in ~/Music/Downloads_Phone/:
//   0.1044 (26/249) Beggin'
//   0.0556 (14/252) Từng Quen
//   0.0544 (24/441) Dù Cho Mai Về Sau
//   0.0543 (14/258) Không Buông
//   0.0538 ( 5/ 93) Overdose
//   0.0441 (12/272) Overthink
//   0.0320 ( 4/125) Earrings
//   0.0286 (15/524) Chúng Ta Của Tương Lai
//   0.0255 ( 4/157) Self Aware
//   0.0216 ( 5/232) giữ lấy làm gì
//   0.0106 ( 2/189) 05 (Không Phai)
//   0.0000 ( 0/151) Let me battle
//   0.0000 ( 0/ 75) 死神
//   0.0000 ( 0/ 57) 西楼别序
// Threshold 0.035 cleanly separates romantic ballads (>= 4.4%) from non-ballads.
var SWEET_LOVE_THRESHOLD = 0.035;

function loveScore(lyrics) {
    if (!lyrics || lyrics.length === 0) return 0;
    var loveCount = 0, contentCount = 0;
    function addWord(w) {
        var b = bare(w).replace(/\u0443/g, "y");
        if (!b) return;
        var isLove = LOVE_WORDS[b] === true;
        var isFunc = FUNC[b] === true;
        if (!isFunc || isLove) contentCount++;
        if (isLove) loveCount++;
    }
    for (var i = 0; i < lyrics.length; i++) {
        var entry = lyrics[i];
        if (!entry) continue;
        if (entry.words && entry.words.length > 0) {
            for (var w = 0; w < entry.words.length; w++) {
                var wd = entry.words[w];
                var t = (wd && wd.text) ? String(wd.text) : "";
                if (t) addWord(t);
            }
            continue;
        }
        var text = String(entry.text || "");
        var parts = text.split(/\s+/);
        for (var p = 0; p < parts.length; p++) {
            if (parts[p]) addWord(parts[p]);
        }
    }
    return contentCount > 0 ? (loveCount / contentCount) : 0;
}

var GENRE_MAP = {
    // Pop family (maps to 'pop', which is a family, not a set)
    "pop": "pop", "k-pop": "pop", "j-pop": "pop", "c-pop": "pop", "cantopop": "pop", "mandopop": "pop",
    "teen pop": "pop", "britpop": "pop", "dance-pop": "pop", "electropop": "pop", "synthpop": "pop",
    "indie pop": "pop", "power pop": "pop", "v-pop": "pop",

    // Rough set (rock, metal, punk, etc.)
    "rock": "rough", "hard rock": "rough", "metal": "rough", "heavy metal": "rough",
    "death metal/black metal": "rough", "death metal": "rough", "black metal": "rough",
    "punk": "rough", "punk rock": "rough", "alternative": "rough", "alternative rock": "rough",
    "grunge": "rough", "emo": "rough", "goth": "rough", "gothic": "rough", "industrial": "rough",
    "hardcore": "rough", "rock & roll": "rough", "psychedelic": "rough", "garage rock": "rough",
    "post-punk": "rough", "metalcore": "rough", "thrash metal": "rough",

    // Street set (hip-hop, rap, trap)
    "hip-hop/rap": "street", "hip-hop": "street", "rap": "street", "hip hop": "street",
    "gangsta rap": "street", "trap": "street", "east coast rap": "street", "west coast rap": "street",
    "underground rap": "street", "old school rap": "street", "urban": "street", "hardcore rap": "street",
    "uk drill": "street", "drill": "street",

    // Dance set (electronic, house, techno...)
    "dance": "dance", "electronic": "dance", "house": "dance", "techno": "dance", "trance": "dance",
    "dubstep": "dance", "drum & bass": "dance", "dnb": "dance", "edm": "dance", "club": "dance",
    "breakbeat": "dance", "idm": "dance", "hardstyle": "dance", "electronica": "dance",
    "ambient house": "dance", "deep house": "dance", "tech house": "dance", "garage": "dance",

    // Calm set (ambient, new age, classical...)
    "new age": "calm", "ambient": "calm", "downtempo": "calm", "chillout": "calm", "instrumental": "calm",
    "classical": "calm", "orchestral": "calm", "opera": "calm", "chamber music": "calm", "meditation": "calm",
    "relaxation": "calm", "healing": "calm", "sleep": "calm", "choral": "calm", "piano": "calm",

    // Classic set (jazz, blues, funk, soul...)
    "jazz": "classic", "smooth jazz": "classic", "big band": "classic", "bebop": "classic",
    "blues": "classic", "contemporary blues": "classic", "delta blues": "classic", "chicago blues": "classic",
    "funk": "classic", "disco": "classic", "motown": "classic", "soul": "classic", "r&b/soul": "classic",
    "neo-soul": "classic", "doo wop": "classic", "rhythm and blues": "classic", "traditional pop": "classic",

    // Anime set (soundtracks, anime, game...)
    "anime": "anime", "soundtrack": "anime", "soundtracks": "anime", "original score": "anime",
    "film score": "anime", "tv soundtrack": "anime", "video game": "anime", "video game music": "anime",
    "disney": "anime", "kayokyoku": "anime", "enka": "anime", "musicals": "anime",

    // Folk set (folk, country, regional, world...)
    "folk": "folk", "country": "folk", "contemporary country": "folk", "country & western": "folk",
    "americana": "folk", "bluegrass": "folk", "latin": "folk", "latin urban": "folk",
    "reggae": "folk", "dancehall": "folk", "ska": "folk", "roots reggae": "folk", "dub": "folk",
    "worldwide": "folk", "world": "folk", "african": "folk", "afrobeats": "folk", "afro-pop": "folk",
    "brazilian": "folk", "samba": "folk", "bossa nova": "folk", "indian": "folk", "bollywood": "folk",
    "celtic": "folk", "flamenco": "folk", "tango": "folk", "regional mexican": "folk", "traditional folk": "folk",

    // Sweet family (vocal, easy listening, singer/songwriter, christian...)
    "singer/songwriter": "sweet", "vocal": "sweet", "vocals": "sweet", "easy listening": "sweet",
    "lounge": "sweet", "christian": "sweet", "gospel": "sweet", "christian & gospel": "sweet",
    "children's music": "sweet", "kids": "sweet", "holiday": "sweet", "lullabies": "sweet"
};

function familyOf(genre) {
    if (!genre || typeof genre !== "string") return null;
    var s = genre.toLowerCase().trim();
    if (!s) return null;
    if (GENRE_MAP[s]) return GENRE_MAP[s];

    // Keyword fallbacks
    if (/\b(metal|rock|punk|grunge|emo|goth|hardcore)\b/.test(s) || s.indexOf("metal") >= 0 || s.indexOf("rock") >= 0) return "rough";
    if (/\b(rap|hip-hop|hip hop|trap|drill)\b/.test(s)) return "street";
    if (/\b(dance|house|techno|trance|dubstep|edm|dnb|electronic)\b/.test(s)) return "dance";
    if (/\b(ambient|classical|new age|orchestral|downtempo|meditation|instrumental)\b/.test(s)) return "calm";
    if (/\b(jazz|blues|funk|disco|motown|soul)\b/.test(s)) return "classic";
    if (/\b(anime|soundtrack|score|disney|kayokyoku|enka)\b/.test(s)) return "anime";
    if (/\b(folk|country|latin|reggae|african|brazilian|indian|world|celtic|samba|bossa)\b/.test(s)) return "folk";
    if (/\b(singer\/songwriter|vocal|easy listening|christian|gospel|children|lullab)\b/.test(s)) return "sweet";
    if (/\b(pop|k-pop|j-pop|c-pop)\b/.test(s)) return "pop";

    return null;
}

function pickSet(genre, lyrics) {
    var family = familyOf(genre);
    var love = loveScore(lyrics);
    var sweetLyrics = love >= SWEET_LOVE_THRESHOLD;
    var med = songMedianRate(lyrics);
    var fast = med >= 11.0;

    if (family === "rough" || family === "street" || family === "dance") {
        return (sweetLyrics && !fast) ? "sweet" : family;
    }
    if (family === "pop") {
        return (fast && !sweetLyrics) ? "dance" : "sweet";
    }
    if (family === null) {
        if (sweetLyrics) return "sweet";
        if (fast) return "dance";
        return "sweet";
    }
    return family;
}

// The maximal cut: give every pile its role and pick, then dress its lines for that role
function dressPiles(piles, set, cap) {
    var setCfg = (set && SETS[set]) ? SETS[set] : SETS.sweet;
    var lastFx = {};
    for (var q = 0; q < piles.length; q++) {
        var P = piles[q];
        if (!P.role) P.role = P.lines.length === 2 ? "duo" : "stack";
        var pool = P.role === "peak" ? (P.lines[0].heroOk ? setCfg.peaks : ["ink"])
                 : P.role === "duo" ? DUO_FX : (P.role === "stack" ? STACK_FX : []);
        P.fx = "";
        if (pool.length > 0) {
            var k = Math.floor(M.r(P.seed, 31, 431) * pool.length);
            if (pool.length > 1 && pool[k] === lastFx[P.role]) k = (k + 1) % pool.length;
            P.fx = pool[k];
            lastFx[P.role] = P.fx;
        }
        if (P.role === "peak") dressPeak(P.lines[0]);
        else if (P.role === "rush") dressRush(P.lines[0], set);
        else { capDoodles(P, cap); if (P.role === "duo") dressDuo(P); }
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
function dressRush(L, set) {
    var setCfg = (set && SETS[set]) ? SETS[set] : SETS.sweet;
    var main = L.mainIdx, n = Math.min(RUSH_DOODLES, main.length);
    L.doodles = [];
    for (var k = 0; k < n; k++) {
        var w = L.words[main[k]];
        L.doodles.push({
            kind: setCfg.rush[Math.floor(M.r(L.seed, k, 441) * setCfg.rush.length)],
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
function capDoodles(P, cap) {
    var maxD = cap > 0 ? cap : PILE_DOODLES;
    var all = [];
    P.lines.forEach(function (L) { L.doodles.forEach(function (d) { all.push(d); }); });
    if (all.length <= maxD) return;
    all.sort(function (a, b) { return a.at - b.at; });
    var keep = all.slice(0, maxD);
    P.lines.forEach(function (L) { L.doodles = L.doodles.filter(function (d) { return keep.indexOf(d) >= 0; }); });
}

function build(lyrics, opts) {
    lyrics = lyrics || [];
    var maxi = !!(opts && opts.max);
    var set = (opts && opts.set) ? opts.set : pickSet(null, lyrics);
    // Preset 8 settings: peaks "natural" | "more" | "every", doodles "few" | "normal" | "lots", film on/off
    var peaksMode = opts && opts.alwaysPeak ? "every" : (opts && opts.peaks) || "natural";
    var doodleMode = (opts && opts.doodles) || "normal";
    var doodleDelta = doodleMode === "few" ? -2 : (doodleMode === "lots" ? 2 : 0);
    if (!SETS[set]) set = "sweet";
    var setCfg = SETS[set];
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
            var order = maxi ? TREAT_ORDER_MAX : TREAT_ORDER;
            var k = Math.floor(M.r(seed, 2, 402) * order.length);
            for (var tries = 0; tries < order.length && order[k] === prevTreat; tries++)
                k = (k + 1) % order.length;
            treat = order[k];
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
            nd = Math.max(doodleMode === "few" ? 0 : 1, Math.min(doodleMode === "lots" ? 7 : 5, nd + doodleDelta));
            var span = Math.max(0.4, (words[words.length - 1].end - start) * 0.8);
            for (var di = 0; di < nd; di++) {
                var spot = DOODLE_SPOTS[Math.floor(M.r(seed, di, 431) * DOODLE_SPOTS.length)];
                if (spot === "below" && L.lineMark) spot = "above";
                L.doodles.push({
                    kind: setCfg.doodles[Math.floor(M.r(seed, di, 432) * setCfg.doodles.length)],
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
    var roles = !maxi ? [] : peaksMode === "every" ? lines.map(function () { return "peak"; }) : tempoRoles(lines, peaksMode === "more");
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
    if (maxi) dressPiles(piles, set, doodleMode === "lots" ? 8 : (doodleMode === "few" ? 2 : PILE_DOODLES));
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
    return { lines: lines, piles: piles, gaps: gaps, seed: songSeed, max: maxi, set: set,
             film: !(opts && opts.film === false) };
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
    if (motion.film === false) { f.grain = 0; f.scan = 0; return f; }
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
        if (w / Math.max(1, h) < 2.5) {
            // doodle: 3 stacked synth/audio waves
            for (var dwi = 0; dwi < 3; dwi++) {
                var wpts = [];
                var wPhase = M.r(sd, dwi, 817) * 6.28 + dwi * 0.8;
                var wFreq = 2.2 + 0.8 * M.r(sd, dwi + 5, 818);
                var midY = h * (0.24 + 0.26 * dwi);
                var ampY = h * 0.14;
                for (i = 0; i <= 32; i++) {
                    u = i / 32;
                    var env = Math.sin(u * Math.PI);
                    wpts.push({
                        x: w * (0.06 + 0.88 * u),
                        y: midY + ampY * env * Math.sin(u * wFreq * 2 * Math.PI + wPhase)
                    });
                }
                S.push(wpts);
            }
        } else {
            var per = 2.5 + 1.5 * M.r(sd, 1, 816), ph = M.r(sd, 2, 817) * 6.28;
            pts = [];
            for (i = 0; i <= 64; i++) {
                u = i / 64;
                pts.push({ x: w * u, y: h * (0.5 + 0.32 * Math.sin(u * per * 2 * Math.PI + ph) * (0.7 + 0.3 * Math.sin(u * 3.1 + ph))) });
            }
            S.push(pts);
        }
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
    case "bolt": {
        // a jagged lightning bolt with a sharp spark branch
        var bx1 = w * (0.6 + 0.06 * M.rs(sd, 1, 831));
        var bx2 = w * (0.34 + 0.05 * M.rs(sd, 2, 832));
        var bx3 = w * (0.58 + 0.05 * M.rs(sd, 3, 833));
        var bx4 = w * (0.26 + 0.06 * M.rs(sd, 4, 834));
        var byMid = h * (0.44 + 0.04 * M.rs(sd, 5, 835));
        S.push([
            { x: bx1, y: h * 0.05 },
            { x: bx2, y: byMid },
            { x: bx3, y: byMid },
            { x: bx4, y: h * 0.95 }
        ]);
        S.push([
            { x: (bx2 + bx3) * 0.5, y: byMid },
            { x: w * (0.7 + 0.08 * M.rs(sd, 6, 836)), y: h * (0.58 + 0.06 * M.rs(sd, 7, 837)) }
        ]);
        break;
    }
    case "crack": {
        // glass hit: a small impact star, then jagged fractures running out with little forks
        var ccx = w * (0.46 + 0.06 * M.rs(sd, 1, 841)), ccy = h * (0.44 + 0.06 * M.rs(sd, 2, 842));
        var arms = 5;
        for (n = 0; n < arms; n++) {
            var ca = -Math.PI / 2 + n * 2 * Math.PI / arms + 0.35 * M.rs(sd, n, 843);
            var clen = 0.5 * (0.75 + 0.35 * M.r(sd, n, 844));
            pts = [{ x: ccx, y: ccy }];
            var segs = 4;
            for (i = 1; i <= segs; i++) {
                u = i / segs;
                var off = (i % 2 ? 1 : -1) * 0.09 * (1 - 0.5 * u) * (0.6 + 0.6 * M.r(sd, n * 7 + i, 845));
                var ra = ca + off;
                pts.push({ x: ccx + Math.cos(ra) * w * clen * u, y: ccy + Math.sin(ra) * h * clen * u });
            }
            S.push(pts);
            // a fork off the second joint
            if (M.r(sd, n, 846) < 0.7) {
                var fp = pts[2], fa = ca + (M.r(sd, n, 847) < 0.5 ? 0.7 : -0.7);
                S.push([fp, { x: fp.x + Math.cos(fa) * w * 0.13, y: fp.y + Math.sin(fa) * h * 0.13 }]);
            }
        }
        // the dented ring round the hit point
        pts = [];
        for (i = 0; i <= 10; i++) {
            var ka = i / 10 * 2 * Math.PI, kr = (i % 2 ? 0.06 : 0.09);
            pts.push({ x: ccx + Math.cos(ka) * w * kr, y: ccy + Math.sin(ka) * h * kr });
        }
        S.push(pts);
        break;
    }
    case "spike": {
        // a row of three sharp punk/metal spikes with a baseline
        var spBaseY = h * 0.88;
        S.push([
            { x: w * 0.08, y: spBaseY },
            { x: w * 0.24, y: h * 0.22 },
            { x: w * 0.38, y: spBaseY - h * 0.12 },
            { x: w * 0.52, y: h * 0.1 },
            { x: w * 0.66, y: spBaseY - h * 0.12 },
            { x: w * 0.8, y: h * 0.22 },
            { x: w * 0.94, y: spBaseY }
        ]);
        S.push([
            { x: w * 0.05, y: spBaseY },
            { x: w * 0.95, y: spBaseY }
        ]);
        break;
    }
    case "crown": {
        // a 3-pointed graffiti crown with a base band and jewel accents
        var bx0 = w * (0.16 + 0.04 * M.rs(sd, 1, 851));
        var bx1 = w * (0.84 + 0.04 * M.rs(sd, 2, 852));
        var by = h * (0.82 + 0.03 * M.rs(sd, 3, 853));
        var p1x = w * (0.18 + 0.03 * M.rs(sd, 4, 854)), p1y = h * (0.36 + 0.04 * M.rs(sd, 5, 855));
        var v1x = w * (0.36 + 0.03 * M.rs(sd, 6, 856)), v1y = h * (0.58 + 0.04 * M.rs(sd, 7, 857));
        var p2x = w * (0.50 + 0.03 * M.rs(sd, 8, 858)), p2y = h * (0.18 + 0.04 * M.rs(sd, 9, 859));
        var v2x = w * (0.64 + 0.03 * M.rs(sd, 10, 860)), v2y = h * (0.58 + 0.04 * M.rs(sd, 11, 861));
        var p3x = w * (0.82 + 0.03 * M.rs(sd, 12, 862)), p3y = h * (0.36 + 0.04 * M.rs(sd, 13, 863));
        S.push([
            { x: bx0, y: by },
            { x: p1x, y: p1y },
            { x: v1x, y: v1y },
            { x: p2x, y: p2y },
            { x: v2x, y: v2y },
            { x: p3x, y: p3y },
            { x: bx1, y: by },
            { x: bx0, y: by }
        ]);
        S.push([
            { x: bx0 + w * 0.02, y: by - h * 0.12 },
            { x: bx1 - w * 0.02, y: by - h * 0.12 }
        ]);
        var jr = Math.min(w, h) * 0.04;
        S.push([{ x: p1x - jr, y: p1y - jr }, { x: p1x + jr, y: p1y - jr }]);
        S.push([{ x: p2x, y: p2y - jr * 2 }, { x: p2x, y: p2y - jr * 0.5 }]);
        S.push([{ x: p3x - jr, y: p3y - jr }, { x: p3x + jr, y: p3y - jr }]);
        break;
    }
    case "drip": {
        // graffiti paint drips: pool across the top with teardrop drips falling
        var poolY = h * (0.24 + 0.03 * M.rs(sd, 1, 865));
        var dx1 = w * (0.32 + 0.04 * M.rs(sd, 2, 866));
        var d1Bot = h * (0.76 + 0.05 * M.rs(sd, 3, 867));
        var dx2 = w * (0.68 + 0.04 * M.rs(sd, 4, 868));
        var d2Bot = h * (0.58 + 0.05 * M.rs(sd, 5, 869));
        S.push([
            { x: w * 0.12, y: poolY },
            { x: w * 0.24, y: poolY - h * 0.06 },
            { x: w * 0.50, y: poolY + h * 0.04 },
            { x: w * 0.78, y: poolY - h * 0.05 },
            { x: w * 0.88, y: poolY }
        ]);
        var rw1 = w * 0.05;
        S.push([
            { x: dx1 - rw1, y: poolY },
            { x: dx1 - rw1, y: d1Bot - h * 0.08 },
            { x: dx1 - rw1 * 1.5, y: d1Bot - h * 0.03 },
            { x: dx1, y: d1Bot },
            { x: dx1 + rw1 * 1.5, y: d1Bot - h * 0.03 },
            { x: dx1 + rw1, y: d1Bot - h * 0.08 },
            { x: dx1 + rw1, y: poolY }
        ]);
        var rw2 = w * 0.045;
        S.push([
            { x: dx2 - rw2, y: poolY },
            { x: dx2 - rw2, y: d2Bot - h * 0.06 },
            { x: dx2 - rw2 * 1.4, y: d2Bot - h * 0.02 },
            { x: dx2, y: d2Bot },
            { x: dx2 + rw2 * 1.4, y: d2Bot - h * 0.02 },
            { x: dx2 + rw2, y: d2Bot - h * 0.06 },
            { x: dx2 + rw2, y: poolY }
        ]);
        var dropY = Math.min(h * 0.94, d1Bot + h * 0.12);
        S.push([
            { x: dx1, y: dropY - h * 0.04 },
            { x: dx1 + rw1 * 0.8, y: dropY },
            { x: dx1, y: dropY + h * 0.03 },
            { x: dx1 - rw1 * 0.8, y: dropY },
            { x: dx1, y: dropY - h * 0.04 }
        ]);
        break;
    }
    case "tag": {
        // a graffiti tag signature flourish: stylized lettering loops, underline sweep, and quote accents
        var yBase = h * (0.52 + 0.04 * M.rs(sd, 1, 881));
        var t1 = { x: w * 0.14, y: yBase + h * 0.08 };
        var t2 = { x: w * 0.24, y: yBase - h * 0.32 };
        var t3 = { x: w * 0.30, y: yBase + h * 0.16 };
        var t4 = { x: w * 0.44, y: yBase - h * 0.26 };
        var t5 = { x: w * 0.52, y: yBase + h * 0.18 };
        var t6 = { x: w * 0.64, y: yBase - h * 0.28 };
        var t7 = { x: w * 0.58, y: yBase - h * 0.04 };
        var t8 = { x: w * 0.76, y: yBase - h * 0.18 };
        var t9 = { x: w * 0.86, y: yBase + h * 0.04 };
        S.push([t1, t2, t3, t4, t5, t6, t7, t8, t9]);
        var unY = h * (0.80 + 0.03 * M.rs(sd, 2, 882));
        S.push([
            { x: w * 0.12, y: unY },
            { x: w * 0.50, y: unY + h * 0.04 },
            { x: w * 0.84, y: unY },
            { x: w * 0.90, y: unY - h * 0.08 }
        ]);
        var qY = h * (0.18 + 0.03 * M.rs(sd, 3, 883));
        S.push([{ x: w * 0.74, y: qY + h * 0.06 }, { x: w * 0.78, y: qY }]);
        S.push([{ x: w * 0.82, y: qY + h * 0.06 }, { x: w * 0.86, y: qY }]);
        break;
    }
    case "dots": {
        // a rhythm dot matrix: 3 rows of 3 pulsed LED beat dots with an accent spark
        var dotR = Math.min(w, h) * 0.055;
        for (var row = 0; row < 3; row++) {
            for (var col = 0; col < 3; col++) {
                var dcx = w * (0.24 + 0.26 * col + 0.02 * M.rs(sd, row * 3 + col, 891));
                var dcy = h * (0.24 + 0.26 * row + 0.02 * M.rs(sd, row * 3 + col + 10, 892));
                var curR = dotR * (0.85 + 0.3 * M.r(sd, row * 3 + col + 20, 893));
                var dpts = [];
                for (var dk = 0; dk <= 8; dk++) {
                    var da = dk / 8 * 2 * Math.PI;
                    dpts.push({ x: dcx + curR * Math.cos(da), y: dcy + curR * Math.sin(da) });
                }
                S.push(dpts);
            }
        }
        S.push([
            { x: w * 0.88, y: h * 0.16 },
            { x: w * 0.88, y: h * 0.28 }
        ]);
        S.push([
            { x: w * 0.82, y: h * 0.22 },
            { x: w * 0.94, y: h * 0.22 }
        ]);
        break;
    }
    case "beam": {
        // a stage light: lamp head top left, a cone of light opening down to the right, dashes inside
        var lx = w * 0.2, ly = h * 0.16;
        S.push(ellipsePts(lx, ly, w * 0.11, h * 0.08, 0, 2 * Math.PI, 18));
        S.push([{ x: lx - w * 0.04, y: ly - h * 0.1 }, { x: lx - w * 0.1, y: ly - h * 0.17 }]);
        var ex0 = { x: w * 0.5, y: h * 0.95 }, ex1 = { x: w * 0.95, y: h * 0.62 };
        S.push([{ x: lx + w * 0.02, y: ly + h * 0.08 }, ex0]);
        S.push([{ x: lx + w * 0.1, y: ly + h * 0.01 }, ex1]);
        for (i = 1; i <= 3; i++) {
            u = 0.35 + i * 0.15;
            var bx = lx + (0.5 * (ex0.x + ex1.x) - lx) * u, by = ly + (0.5 * (ex0.y + ex1.y) - ly) * u;
            S.push([{ x: bx - w * 0.04, y: by - h * 0.03 }, { x: bx + w * 0.04, y: by + h * 0.03 }]);
        }
        break;
    }
    case "grid": {
        // synthwave / club perspective wireframe grid
        var vpx = w * (0.50 + 0.04 * M.rs(sd, 1, 901));
        var vpy = h * 0.16;
        var horizY = h * 0.34;
        S.push([{ x: w * 0.06, y: horizY }, { x: w * 0.94, y: horizY }]);
        var xTargets = [0.08, 0.26, 0.42, 0.58, 0.74, 0.92];
        for (var gi = 0; gi < xTargets.length; gi++) {
            var tx = w * xTargets[gi];
            var uH = (horizY - vpy) / (h * 0.94 - vpy);
            var hx = vpx + (tx - vpx) * uH;
            S.push([{ x: hx, y: horizY }, { x: tx, y: h * 0.94 }]);
        }
        var horizLines = [0.46, 0.62, 0.78, 0.94];
        for (var hi = 0; hi < horizLines.length; hi++) {
            var hy = h * horizLines[hi];
            var uHy = (hy - vpy) / (h * 0.94 - vpy);
            var xL = vpx + (w * 0.08 - vpx) * uHy;
            var xR = vpx + (w * 0.92 - vpx) * uHy;
            S.push([{ x: xL, y: hy }, { x: xR, y: hy }]);
        }
        break;
    }
    case "cloud": {
        // a puffy cloud: three bumps over a flat underside, one curl inside
        pts = [{ x: w * 0.12, y: h * 0.72 }];
        pts = pts.concat(ellipsePts(w * 0.24, h * 0.58, w * 0.14, h * 0.16, Math.PI * 0.85, Math.PI * 1.75, 8));
        pts = pts.concat(ellipsePts(w * 0.48, h * 0.42, w * 0.2, h * 0.24, Math.PI * 1.0, Math.PI * 1.95, 10));
        pts = pts.concat(ellipsePts(w * 0.74, h * 0.56, w * 0.15, h * 0.17, Math.PI * 1.25, Math.PI * 2.2, 8));
        pts.push({ x: w * 0.86, y: h * 0.72 });
        pts.push({ x: w * 0.12, y: h * 0.72 });
        S.push(pts);
        S.push(ellipsePts(w * 0.44, h * 0.5, w * 0.08, h * 0.07, Math.PI * 1.1, Math.PI * 1.8, 6));
        break;
    }
    case "drop": {
        // a water teardrop tapering smoothly from pointed apex to bulbous rounded bottom
        var dApexX = w * 0.5, dApexY = h * 0.14;
        var dBotCx = w * 0.5, dBotCy = h * 0.64;
        var dRx = w * 0.26, dRy = h * 0.26;
        var DropContour = [{ x: dApexX, y: dApexY }];
        // Right flank to round bottom
        for (i = 0; i <= 16; i++) {
            u = i / 16;
            var aDrop = -Math.PI * 0.12 + u * Math.PI * 1.24;
            DropContour.push({
                x: dBotCx + dRx * Math.cos(aDrop),
                y: dBotCy + dRy * Math.sin(aDrop)
            });
        }
        DropContour.push({ x: dApexX, y: dApexY });
        S.push(DropContour);

        // Specular curved reflection shine on upper-left flank
        var Shine = [];
        for (i = 0; i <= 8; i++) {
            u = i / 8;
            Shine.push({
                x: w * (0.40 - 0.08 * Math.sin(u * Math.PI)),
                y: h * (0.36 + 0.26 * u)
            });
        }
        S.push(Shine);
        S.push([
            { x: w * 0.34, y: h * 0.68 },
            { x: w * 0.36, y: h * 0.72 }
        ]);
        break;
    }
    case "ripple": {
        // concentric elliptical water ripples with center droplet splash
        var rcx = w * 0.5, rcy = h * 0.56;
        S.push(ellipsePts(rcx, rcy, w * 0.42, h * 0.24, 0, 2 * Math.PI, 28));
        S.push(ellipsePts(rcx, rcy, w * 0.26, h * 0.15, 0, 2 * Math.PI, 22));
        S.push(ellipsePts(rcx, rcy, w * 0.12, h * 0.07, 0, 2 * Math.PI, 16));
        S.push([
            { x: rcx, y: rcy - h * 0.02 },
            { x: rcx, y: rcy - h * 0.24 }
        ]);
        S.push(ellipsePts(rcx, rcy - h * 0.30, w * 0.04, h * 0.06, 0, 2 * Math.PI, 12));
        break;
    }
    case "leaf": {
        // an organic botanical leaf with curved stem and branching side veins
        var stemBase = { x: w * 0.14, y: h * 0.84 };
        var leafBase = { x: w * 0.24, y: h * 0.74 };
        var leafTip = { x: w * 0.86, y: h * 0.16 };
        S.push([stemBase, leafBase]);
        var Blade = [leafBase];
        for (i = 1; i <= 16; i++) {
            u = i / 16;
            var bxT = leafBase.x + (leafTip.x - leafBase.x) * u - w * 0.22 * Math.sin(u * Math.PI);
            var byT = leafBase.y + (leafTip.y - leafBase.y) * u - h * 0.18 * Math.sin(u * Math.PI);
            Blade.push({ x: bxT, y: byT });
        }
        Blade.push(leafTip);
        for (i = 1; i <= 16; i++) {
            u = i / 16;
            var bxB = leafTip.x + (leafBase.x - leafTip.x) * u + w * 0.20 * Math.sin(u * Math.PI);
            var byB = leafTip.y + (leafBase.y - leafTip.y) * u + h * 0.20 * Math.sin(u * Math.PI);
            Blade.push({ x: bxB, y: byB });
        }
        Blade.push(leafBase);
        S.push(Blade);

        var Midrib = [];
        for (i = 0; i <= 12; i++) {
            u = i / 12;
            Midrib.push({
                x: leafBase.x + (leafTip.x - leafBase.x) * u - w * 0.04 * Math.sin(u * Math.PI),
                y: leafBase.y + (leafTip.y - leafBase.y) * u - h * 0.02 * Math.sin(u * Math.PI)
            });
        }
        S.push(Midrib);

        var veinU = [0.28, 0.50, 0.72];
        for (var vi = 0; vi < veinU.length; vi++) {
            var vu = veinU[vi];
            var vx = leafBase.x + (leafTip.x - leafBase.x) * vu;
            var vy = leafBase.y + (leafTip.y - leafBase.y) * vu;
            S.push([
                { x: vx, y: vy },
                { x: vx - w * 0.10 * (1 - vu * 0.5), y: vy - h * 0.10 * (1 - vu * 0.5) }
            ]);
            S.push([
                { x: vx, y: vy },
                { x: vx + w * 0.09 * (1 - vu * 0.5), y: vy + h * 0.08 * (1 - vu * 0.5) }
            ]);
        }
        break;
    }
    case "moon": {
        // a glowing crescent moon with surrounding calm starlight sparkles
        var mcx = w * 0.54, mcy = h * 0.50;
        var rOuter = Math.min(w, h) * 0.38;
        var rInner = rOuter * 0.88;
        var innerOffX = w * 0.14;
        var MoonCrescent = [];
        for (i = 0; i <= 20; i++) {
            u = i / 20;
            var aOut = -Math.PI * 0.42 + u * Math.PI * 0.84;
            MoonCrescent.push({
                x: mcx + rOuter * Math.cos(aOut),
                y: mcy + rOuter * Math.sin(aOut)
            });
        }
        for (i = 0; i <= 20; i++) {
            u = i / 20;
            var aIn = Math.PI * 0.42 - u * Math.PI * 0.84;
            MoonCrescent.push({
                x: mcx - innerOffX + rInner * Math.cos(aIn),
                y: mcy + rInner * Math.sin(aIn)
            });
        }
        MoonCrescent.push(MoonCrescent[0]);
        S.push(MoonCrescent);

        var s1x = w * 0.28, s1y = h * 0.38;
        S.push([{ x: s1x - w * 0.06, y: s1y }, { x: s1x + w * 0.06, y: s1y }]);
        S.push([{ x: s1x, y: s1y - h * 0.08 }, { x: s1x, y: s1y + h * 0.08 }]);

        var s2x = w * 0.32, s2y = h * 0.65;
        S.push([{ x: s2x - w * 0.04, y: s2y }, { x: s2x + w * 0.04, y: s2y }]);
        S.push([{ x: s2x, y: s2y - h * 0.05 }, { x: s2x, y: s2y + h * 0.05 }]);
        break;
    }
    case "note": {
        // a classic single musical note with tilted oval notehead, upright stem and curved flag
        var ncx = w * 0.38, ncy = h * 0.70;
        var nrx = w * 0.18, nry = h * 0.13;
        var NoteHead = [];
        for (i = 0; i <= 16; i++) {
            u = i / 16;
            var a = u * 2 * Math.PI;
            var cosT = 0.894, sinT = -0.447; // cos(-26.5 deg), sin(-26.5 deg)
            var ex = nrx * Math.cos(a), ey = nry * Math.sin(a);
            NoteHead.push({ x: ncx + ex * cosT - ey * sinT, y: ncy + ex * sinT + ey * cosT });
        }
        S.push(NoteHead);
        S.push([
            { x: ncx - nrx * 0.45, y: ncy + nry * 0.25 },
            { x: ncx + nrx * 0.45, y: ncy - nry * 0.25 }
        ]);

        var stemX = ncx + nrx * 0.75;
        var stemTopY = h * 0.18;
        S.push([
            { x: stemX, y: ncy },
            { x: stemX, y: stemTopY }
        ]);

        var Flag = [
            { x: stemX, y: stemTopY },
            { x: stemX + w * 0.14, y: stemTopY + h * 0.08 },
            { x: stemX + w * 0.22, y: stemTopY + h * 0.22 },
            { x: stemX + w * 0.18, y: stemTopY + h * 0.36 },
            { x: stemX + w * 0.10, y: stemTopY + h * 0.38 }
        ];
        S.push(Flag);
        break;
    }
    case "notes": {
        // beamed pair of musical eighth notes connected across the top
        var n1x = w * 0.26, n1y = h * 0.74;
        var n2x = w * 0.66, n2y = h * 0.65;
        var brx = w * 0.15, bry = h * 0.11;
        var cosB = 0.906, sinB = -0.422;

        var Head1 = [];
        for (i = 0; i <= 16; i++) {
            u = i / 16;
            var a1 = u * 2 * Math.PI;
            var e1x = brx * Math.cos(a1), e1y = bry * Math.sin(a1);
            Head1.push({ x: n1x + e1x * cosB - e1y * sinB, y: n1y + e1x * sinB + e1y * cosB });
        }
        S.push(Head1);
        S.push([
            { x: n1x - brx * 0.45, y: n1y + bry * 0.25 },
            { x: n1x + brx * 0.45, y: n1y - bry * 0.25 }
        ]);

        var Head2 = [];
        for (i = 0; i <= 16; i++) {
            u = i / 16;
            var a2 = u * 2 * Math.PI;
            var e2x = brx * Math.cos(a2), e2y = bry * Math.sin(a2);
            Head2.push({ x: n2x + e2x * cosB - e2y * sinB, y: n2y + e2x * sinB + e2y * cosB });
        }
        S.push(Head2);
        S.push([
            { x: n2x - brx * 0.45, y: n2y + bry * 0.25 },
            { x: n2x + brx * 0.45, y: n2y - bry * 0.25 }
        ]);

        var stem1X = n1x + brx * 0.75, stem1TopY = h * 0.24;
        var stem2X = n2x + brx * 0.75, stem2TopY = h * 0.15;
        S.push([{ x: stem1X, y: n1y }, { x: stem1X, y: stem1TopY }]);
        S.push([{ x: stem2X, y: n2y }, { x: stem2X, y: stem2TopY }]);

        // Primary and secondary beams
        S.push([{ x: stem1X, y: stem1TopY }, { x: stem2X, y: stem2TopY }]);
        S.push([{ x: stem1X, y: stem1TopY + h * 0.08 }, { x: stem2X, y: stem2TopY + h * 0.08 }]);
        break;
    }
    case "smoke": {
        // an elegant atmospheric curl of rising smoke with graceful S-curves
        var Smoke1 = [];
        for (i = 0; i <= 24; i++) {
            u = i / 24;
            var sx = w * (0.48 - 0.24 * Math.sin(u * Math.PI * 1.5) + 0.12 * Math.sin(u * Math.PI * 3.0));
            var sy = h * (0.86 - 0.70 * u);
            Smoke1.push({ x: sx, y: sy });
        }
        S.push(Smoke1);

        var Smoke2 = [];
        for (i = 0; i <= 20; i++) {
            u = i / 20;
            var s2x = w * (0.54 + 0.18 * Math.sin(u * Math.PI * 1.8) - 0.10 * Math.sin(u * Math.PI * 3.2));
            var s2y = h * (0.80 - 0.58 * u);
            Smoke2.push({ x: s2x, y: s2y });
        }
        S.push(Smoke2);

        // Top dispersing swirl
        var SwirlSmoke = [];
        for (i = 0; i <= 14; i++) {
            u = i / 14;
            var aSm = u * 1.6 * Math.PI;
            var rSmX = w * (0.12 * (1 - 0.45 * u));
            var rSmY = h * (0.08 * (1 - 0.45 * u));
            SwirlSmoke.push({
                x: w * 0.46 + rSmX * Math.cos(aSm),
                y: h * 0.18 - rSmY * Math.sin(aSm)
            });
        }
        S.push(SwirlSmoke);
        break;
    }
    case "vinyl": {
        // a vinyl record disc with concentric sound grooves, center label and radial sheen
        var vcx = w * 0.50, vcy = h * 0.50;
        var rDisc = Math.min(w, h) * 0.44;
        S.push(ellipsePts(vcx, vcy, rDisc, rDisc, 0, 2 * Math.PI, 28));
        S.push(ellipsePts(vcx, vcy, rDisc * 0.82, rDisc * 0.82, 0, 2 * Math.PI, 24));
        S.push(ellipsePts(vcx, vcy, rDisc * 0.64, rDisc * 0.64, 0, 2 * Math.PI, 20));
        S.push(ellipsePts(vcx, vcy, rDisc * 0.36, rDisc * 0.36, 0, 2 * Math.PI, 16));
        S.push(ellipsePts(vcx, vcy, rDisc * 0.10, rDisc * 0.10, 0, 2 * Math.PI, 10));

        // Specular sheen radial glints
        S.push([
            { x: vcx - rDisc * 0.72, y: vcy - rDisc * 0.45 },
            { x: vcx - rDisc * 0.40, y: vcy - rDisc * 0.25 }
        ]);
        S.push([
            { x: vcx + rDisc * 0.72, y: vcy + rDisc * 0.45 },
            { x: vcx + rDisc * 0.40, y: vcy + rDisc * 0.25 }
        ]);
        break;
    }
    case "mic": {
        // a vintage jazz mic: a rounded head with grille lines on a short stand and base
        var mcx = w * 0.5, mcy = h * 0.32, mrx = w * 0.17, mry = h * 0.22;
        S.push(ellipsePts(mcx, mcy, mrx, mry, 0, 2 * Math.PI, 24));
        for (i = -1; i <= 1; i++) S.push([{ x: mcx - mrx * 0.8, y: mcy + i * mry * 0.42 }, { x: mcx + mrx * 0.8, y: mcy + i * mry * 0.42 }]);
        S.push(ellipsePts(mcx, mcy + mry * 0.2, mrx * 1.35, mry * 1.05, Math.PI * 0.05, Math.PI * 0.95, 10));
        S.push([{ x: mcx, y: mcy + mry * 1.25 }, { x: mcx, y: h * 0.88 }]);
        S.push([{ x: mcx - w * 0.16, y: h * 0.9 }, { x: mcx + w * 0.16, y: h * 0.9 }]);
        break;
    }
    case "star4": {
        // an anime four-point sparkling star with pinched waist and companion twinkle
        pts = [];
        var a0 = -Math.PI / 2 + 0.15 * M.rs(sd, 1, 881);
        for (i = 0; i <= 8; i++) {
            var sa = a0 + i * Math.PI / 4;
            var sr = (i % 2 ? 0.20 : 0.46) * (0.92 + 0.16 * M.r(sd, i % 8, 882));
            pts.push({ x: w / 2 + w * sr * Math.cos(sa), y: h / 2 + h * sr * Math.sin(sa) });
        }
        S.push(pts);
        // companion tiny diamond glint
        var gx = w * 0.82, gy = h * 0.22, gr = Math.min(w, h) * 0.10;
        S.push([
            { x: gx, y: gy - gr }, { x: gx + gr * 0.4, y: gy },
            { x: gx, y: gy + gr }, { x: gx - gr * 0.4, y: gy },
            { x: gx, y: gy - gr }
        ]);
        break;
    }
    case "sweat": {
        // a manga sweat drop: a fat teardrop leaning right, a glint, two little flick lines
        var sd0 = place([(function () {
            var c = [{ x: 0, y: -0.5 }];
            for (var k = 0; k <= 16; k++) { var a = -0.15 * Math.PI + k / 16 * 1.3 * Math.PI; c.push({ x: 0.3 * Math.cos(a), y: 0.16 + 0.3 * Math.sin(a) }); }
            c.push({ x: 0, y: -0.5 });
            return c;
        })()], w * 0.56, h * 0.48, 18, Math.min(w, h) * 0.95)[0];
        S.push(sd0);
        S.push(place([[{ x: -0.16, y: 0.08 }, { x: -0.13, y: 0.24 }]], w * 0.56, h * 0.48, 18, Math.min(w, h) * 0.95)[0]);
        S.push([{ x: w * 0.12, y: h * 0.36 }, { x: w * 0.22, y: h * 0.42 }]);
        S.push([{ x: w * 0.12, y: h * 0.56 }, { x: w * 0.22, y: h * 0.56 }]);
        break;
    }
    case "anger": {
        // the manga anger mark: four short arcs bowing in toward a cross-shaped gap, open between them
        var ar = Math.min(w, h) * 0.5, acx = w / 2, acy = h / 2;
        for (n = 0; n < 4; n++) {
            var qa = Math.PI / 4 + n * Math.PI / 2;
            var ox = acx + Math.cos(qa) * ar * 1.98, oy = acy + Math.sin(qa) * ar * 1.98;
            pts = [];
            for (i = 0; i <= 10; i++) {
                var ta = qa + Math.PI + (i / 10 - 0.5) * Math.PI * 0.26;
                pts.push({ x: ox + Math.cos(ta) * ar * 1.35, y: oy + Math.sin(ta) * ar * 1.35 });
            }
            S.push(pts);
        }
        break;
    }
    case "sun": {
        // a warm folk sun with circular center, radiating sunbeams and gentle inner warmth arc
        var scx = w * 0.50, scy = h * 0.50;
        var rSun = Math.min(w, h) * 0.26;
        // Central sun disc
        S.push(ellipsePts(scx, scy, rSun, rSun, 0, 2 * Math.PI, 22));

        // Radiating sunbeams
        var numRays = 8;
        var aRay0 = M.r(sd, 1, 951) * 0.5;
        for (i = 0; i < numRays; i++) {
            var aRay = aRay0 + i * (2 * Math.PI / numRays);
            var isLong = (i % 2 === 0);
            var rIn = rSun * 1.22;
            var rOut = rSun * (isLong ? 1.75 : 1.48);
            var rx0 = scx + rIn * Math.cos(aRay), ry0 = scy + rIn * Math.sin(aRay);
            var rx1 = scx + rOut * Math.cos(aRay), ry1 = scy + rOut * Math.sin(aRay);
            S.push([{ x: rx0, y: ry0 }, { x: rx1, y: ry1 }]);
        }

        // Inner warmth spiral / crescent arc
        S.push(ellipsePts(scx, scy, rSun * 0.55, rSun * 0.55, -Math.PI * 0.2, Math.PI * 1.1, 14));
        break;
    }
    case "sprout": {
        // a shoot: a curved stem out of a soil line, two leaves opening left and right
        var gx = w * 0.5, gy = h * 0.86;
        S.push([{ x: w * 0.2, y: gy }, { x: w * 0.42, y: gy + h * 0.02 }, { x: w * 0.62, y: gy - h * 0.01 }, { x: w * 0.8, y: gy }]);
        pts = [];
        for (i = 0; i <= 10; i++) { u = i / 10; pts.push({ x: gx + w * 0.05 * Math.sin(u * Math.PI), y: gy - h * 0.5 * u }); }
        S.push(pts);
        var tip = pts[pts.length - 1];
        function leaf(dir) {
            var L1 = [], L2 = [], ex = tip.x + dir * w * 0.34, ey = tip.y - h * 0.16;
            for (var k = 0; k <= 8; k++) {
                var v = k / 8, bx = tip.x + (ex - tip.x) * v, by = tip.y + (ey - tip.y) * v, bulge = Math.sin(v * Math.PI) * h * 0.11;
                L1.push({ x: bx, y: by - bulge }); L2.push({ x: bx, y: by + bulge });
            }
            return L1.concat(L2.reverse());
        }
        S.push(leaf(-1));
        S.push(leaf(1));
        break;
    }
    case "bird": {
        // two gulls in flight, each two curved wings meeting at a point
        function gull(cx, cy, s) {
            var g = [];
            for (var k = 0; k <= 8; k++) { var v = k / 8; g.push({ x: cx - s + s * v, y: cy - s * 0.45 * Math.sin(v * Math.PI) + s * 0.25 * v }); }
            for (k = 1; k <= 8; k++) { v = k / 8; g.push({ x: cx + s * v, y: cy + s * 0.25 * (1 - v) - s * 0.45 * Math.sin(v * Math.PI) }); }
            return g;
        }
        S.push(gull(w * 0.38, h * 0.5, w * 0.3));
        S.push(gull(w * 0.8, h * 0.24, w * 0.15));
        break;
    }
    case "hill": {
        // two low rolling hills running off the edges; the far one hides behind the near one,
        // a small tree stands on the near crest
        function hy(x, x0, x1, top) {
            if (x <= x0 || x >= x1) return h * 0.86;
            return h * 0.86 - top * (0.5 - 0.5 * Math.cos(2 * Math.PI * (x - x0) / (x1 - x0)));
        }
        var nearP = [], farP = [];
        for (i = 0; i <= 32; i++) {
            var hx = w * i / 32, yn = hy(hx, -w * 0.3, w * 0.9, h * 0.36), yf = hy(hx, w * 0.3, w * 1.5, h * 0.3);
            nearP.push({ x: hx, y: yn });
            if (yf < yn - 0.5) farP.push({ x: hx, y: yf });
            else if (farP.length) { farP.push({ x: hx, y: yn }); S.push(farP); farP = []; }
        }
        if (farP.length > 1) S.push(farP);
        S.push(nearP);
        var tx = w * 0.3, ty = h * 0.51;
        S.push([{ x: tx, y: ty }, { x: tx, y: ty - h * 0.09 }]);
        S.push(ellipsePts(tx, ty - h * 0.15, w * 0.05, h * 0.065, 0, 2 * Math.PI, 14));
        break;
    }
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
        // a dynamic street graffiti arrow arching across the box with a barbed head and tail flick
        var fl = M.r(sd, 4, 820) < 0.5;
        var pStart = { x: w * 0.16, y: h * (0.82 + 0.04 * M.rs(sd, 1, 871)) };
        var cMid = { x: w * (0.38 + 0.05 * M.rs(sd, 2, 872)), y: h * (0.55 + 0.05 * M.rs(sd, 3, 873)) };
        var pEnd = { x: w * (0.82 + 0.04 * M.rs(sd, 4, 874)), y: h * (0.24 + 0.04 * M.rs(sd, 5, 875)) };
        pts = [];
        for (i = 0; i <= 20; i++) {
            u = i / 20;
            var q0 = (1 - u) * (1 - u), q1 = 2 * u * (1 - u), q2 = u * u;
            pts.push({ x: q0 * pStart.x + q1 * cMid.x + q2 * pEnd.x, y: q0 * pStart.y + q1 * cMid.y + q2 * pEnd.y });
        }
        var dxA = pEnd.x - cMid.x, dyA = pEnd.y - cMid.y, lA = Math.sqrt(dxA * dxA + dyA * dyA);
        dxA = (lA > 1e-4 ? dxA / lA : 1); dyA = (lA > 1e-4 ? dyA / lA : 0);
        var hl = Math.min(w, h) * 0.28;
        function rotA(dx, dy, a) { return { x: dx * Math.cos(a) - dy * Math.sin(a), y: dx * Math.sin(a) + dy * Math.cos(a) }; }
        var hA = rotA(-dxA, -dyA, 0.65), hB = rotA(-dxA, -dyA, -0.65);
        S.push(pts);
        var barbA = { x: pEnd.x + hA.x * hl, y: pEnd.y + hA.y * hl };
        var barbB = { x: pEnd.x + hB.x * hl, y: pEnd.y + hB.y * hl };
        var notchA = { x: pEnd.x + hA.x * hl * 0.5 + hB.x * hl * 0.2, y: pEnd.y + hA.y * hl * 0.5 + hB.y * hl * 0.2 };
        var notchB = { x: pEnd.x + hB.x * hl * 0.5 + hA.x * hl * 0.2, y: pEnd.y + hB.y * hl * 0.5 + hA.x * hl * 0.2 };
        S.push([barbA, pEnd, barbB, notchB, notchA, barbA]);
        S.push([
            { x: pStart.x - w * 0.05, y: pStart.y - h * 0.08 },
            { x: pStart.x + w * 0.08, y: pStart.y + h * 0.08 }
        ]);
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
    var d = fx === "bulb" ? 0.7 : (fx in PROP_D ? Math.max(PROP_D[fx], PROP_SETTLE) : 0);
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
        case "shatter":
            if (tp >= 0) {
                st.heroDy = 0.14 * Math.exp(-9 * tp) * Math.sin(32 * tp);
                st.heroRot = 4.5 * Math.exp(-8 * tp) * Math.sin(26 * tp);
            }
            break;
        case "snap":
            if (tp >= 0) {
                st.heroDy = 0.1 * Math.exp(-8 * tp) * Math.sin(28 * tp);
                st.heroRot = 3 * Math.exp(-7 * tp) * Math.sin(22 * tp);
            }
            break;
        case "rip":
            if (tp >= 0) st.heroS = 1 + 0.08 * Math.exp(-6 * tp) * Math.sin(18 * tp);
            break;
        case "spray":
            if (tp >= 0) {
                st.heroDy = -0.04 * Math.exp(-6 * tp) * Math.sin(18 * tp);
            }
            break;
        case "micdrop":
            if (tp >= 0) {
                st.heroDy = -0.12 * Math.exp(-8 * tp) * Math.sin(24 * tp);
                st.heroRot = 2.0 * Math.exp(-7 * tp) * Math.sin(18 * tp);
            }
            break;
        case "tapex":
            if (tp >= 0) {
                st.heroS = 1 - 0.05 * Math.exp(-12 * tp) * Math.sin(22 * tp);
                st.heroDy = 0.03 * Math.exp(-9 * tp) * Math.cos(18 * tp);
            }
            break;
        case "disco":
            if (tp >= 0) {
                st.heroS = 1 + 0.06 * Math.exp(-6 * tp) * Math.sin(20 * tp);
                st.heroDy = -0.05 * Math.exp(-7 * tp) * Math.cos(22 * tp);
            }
            break;
        case "eq":
            if (tp >= 0) {
                var eqSung = Math.max(0.4, pw ? pw.end - pw.start : 0.4);
                st.heroDy = -0.06 * Math.sin(tp * 16) * Math.exp(-2.5 * tp / eqSung);
                st.heroS = 1 + 0.04 * Math.abs(Math.cos(tp * 16)) * Math.exp(-2.5 * tp / eqSung);
            }
            break;
        case "laser":
            if (tp >= 0) {
                st.heroS = 1 + 0.08 * Math.exp(-8 * tp) * Math.cos(22 * tp);
                st.heroDy = 0.04 * Math.exp(-9 * tp) * Math.sin(26 * tp);
            }
            break;
        case "calm_leaf":
            if (tp >= 0) {
                st.heroDy = 0.04 * Math.exp(-6 * tp) * Math.sin(18 * tp);
                st.heroRot = 1.5 * Math.exp(-5 * tp) * Math.sin(14 * tp);
            }
            break;
        case "droplet":
            if (tp >= 0) {
                st.heroDy = -0.06 * Math.exp(-8 * tp) * Math.sin(22 * tp);
                st.heroS = 1 + 0.04 * Math.exp(-7 * tp) * Math.cos(18 * tp);
            }
            break;
        case "moonrise":
            if (tp >= 0) {
                st.heroDy = -0.05 * M.E.outCubic(M.clamp(tp / 0.35));
                st.heroS = 1 + 0.05 * Math.exp(-5 * tp) * Math.sin(16 * tp);
            }
            break;
        case "classic_vinyl":
        case "vinyl":
            if (tp >= 0) {
                st.heroS = 1 + 0.05 * Math.exp(-6 * tp) * Math.sin(18 * tp);
                st.heroDy = 0.04 * Math.exp(-7 * tp) * Math.cos(18 * tp);
                st.heroRot = 1.2 * Math.exp(-6 * tp) * Math.sin(16 * tp);
            }
            break;
        case "classic_smoke":
        case "smoke":
            if (tp >= 0) {
                st.heroDy = -0.05 * Math.sin(tp * 8) * Math.exp(-tp * 0.8);
                st.heroRot = 1.0 * Math.sin(tp * 3.5) * Math.exp(-tp * 0.8);
                st.heroS = 1 + 0.03 * Math.cos(tp * 5) * Math.exp(-tp * 1.2);
            }
            break;
        case "horn":
            if (tp >= 0) {
                st.heroS = 1 + 0.07 * Math.exp(-7 * tp) * Math.cos(20 * tp);
                st.heroDy = -0.05 * Math.exp(-7 * tp) * Math.sin(20 * tp);
                st.heroRot = -1.8 * Math.exp(-6 * tp) * Math.sin(16 * tp);
            }
            break;
        case "flash":
            if (tp >= 0) {
                st.heroS = 1 + 0.08 * Math.exp(-8 * tp) * Math.cos(22 * tp);
                st.heroDy = -0.04 * Math.exp(-8 * tp) * Math.sin(20 * tp);
                st.heroRot = 1.0 * Math.exp(-7 * tp) * Math.sin(18 * tp);
            }
            break;
        case "focus":
            if (tp >= 0) {
                st.heroS = 1 + 0.09 * Math.exp(-6 * tp) * Math.sin(16 * tp);
                st.heroDy = -0.05 * Math.exp(-6 * tp) * Math.cos(16 * tp);
                st.heroRot = -1.2 * Math.exp(-6 * tp) * Math.sin(14 * tp);
            }
            break;
        case "sakura":
            if (tp >= 0) {
                st.heroDy = -0.05 * Math.sin(tp * 8) * Math.exp(-tp * 0.7);
                st.heroRot = 0.8 * Math.sin(tp * 2.8) * Math.exp(-tp * 0.7);
                st.heroS = 1 + 0.03 * Math.cos(tp * 4) * Math.exp(-tp * 1.0);
            }
            break;
        case "sunrise":
            if (tp >= 0) {
                st.heroS = 1 + 0.07 * Math.exp(-6 * tp) * Math.sin(16 * tp);
                st.heroDy = -0.06 * Math.exp(-5 * tp) * Math.cos(14 * tp);
                st.heroRot = 0.8 * Math.exp(-6 * tp) * Math.sin(12 * tp);
            }
            break;
        case "flock":
            if (tp >= 0) {
                st.heroDy = -0.05 * Math.sin(tp * 8) * Math.exp(-tp * 0.8);
                st.heroRot = -1.0 * Math.sin(tp * 6) * Math.exp(-tp * 0.8);
                st.heroS = 1 + 0.04 * Math.cos(tp * 7) * Math.exp(-tp * 0.9);
            }
            break;
        case "folk_sprout":
        case "sprout":
            if (tp >= 0) {
                st.heroS = 1 + 0.09 * Math.exp(-7 * tp) * Math.cos(18 * tp);
                st.heroDy = 0.05 * Math.exp(-7 * tp) * Math.sin(16 * tp);
                st.heroRot = 1.0 * Math.exp(-6 * tp) * Math.sin(14 * tp);
            }
            break;
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
// How far a ripped hero is torn open and slipped apart; it closes back as the word ends
function ripSplit(L, t) {
    var land = peakOnAt(L), tau = t - land;
    if (tau < 0) return 0;
    var hw = L.words[L.heroWi >= 0 ? L.heroWi : 0];
    var sung = Math.max(0.4, hw.end - hw.start);
    var open = M.E.outBack(M.clamp(tau / 0.18), 1.8);
    var shut = M.clamp((tau - (sung + 0.1)) / 0.25);
    return Math.max(0, open * (1 - M.E.outQuad(shut)));
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
function star4Pts(r, ri) {
    var pts = [];
    for (var i = 0; i <= 8; i++) {
        var a = -Math.PI / 2 + i * Math.PI / 4, rr = i % 2 ? ri : r;
        pts.push({ x: rr * Math.cos(a), y: rr * Math.sin(a) });
    }
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
    case "shard":
        return [[{ x: -0.15, y: -0.1 }, { x: 0.18, y: -0.05 }, { x: 0.02, y: 0.18 }, { x: -0.15, y: -0.1 }]];
    case "shatter":
        return [[{ x: -0.5, y: -0.4 }, { x: -0.2, y: -0.15 }, { x: 0, y: 0 }, { x: 0.25, y: -0.2 }, { x: 0.5, y: -0.4 }],
                [{ x: -0.4, y: 0.35 }, { x: 0, y: 0 }, { x: 0.38, y: 0.38 }]];
    case "snap":
        return [[{ x: -0.4, y: 0 }, { x: -0.1, y: 0 }, { x: 0.1, y: -0.1 }, { x: 0.22, y: -0.25 }, { x: 0.1, y: -0.32 }, { x: 0.02, y: -0.22 }]];
    case "rip":
        return [[{ x: 0, y: -0.5 }, { x: 0.08, y: -0.25 }, { x: -0.08, y: 0 }, { x: 0.08, y: 0.25 }, { x: 0, y: 0.5 }]];
    case "spray":
        return [
            [{ x: -0.22, y: 0.5 }, { x: -0.22, y: -0.25 }, { x: -0.15, y: -0.38 },
             { x: 0.15, y: -0.38 }, { x: 0.22, y: -0.25 }, { x: 0.22, y: 0.5 }, { x: -0.22, y: 0.5 }],
            [{ x: -0.22, y: 0.44 }, { x: 0, y: 0.48 }, { x: 0.22, y: 0.44 }],
            [{ x: -0.09, y: -0.38 }, { x: -0.09, y: -0.5 }, { x: 0.09, y: -0.5 }, { x: 0.09, y: -0.38 }],
            [{ x: -0.05, y: -0.47 }, { x: -0.15, y: -0.47 }, { x: -0.15, y: -0.42 }],
            [{ x: -0.22, y: 0.1 }, { x: 0.22, y: 0.1 }]
        ];
    case "micdrop":
        return [
            [{ x: -0.16, y: -0.32 }, { x: -0.15, y: -0.48 }, { x: -0.08, y: -0.58 },
             { x: 0.08, y: -0.58 }, { x: 0.15, y: -0.48 }, { x: 0.16, y: -0.32 }, { x: -0.16, y: -0.32 }],
            [{ x: 0, y: -0.58 }, { x: 0, y: -0.32 }],
            [{ x: -0.15, y: -0.42 }, { x: 0.15, y: -0.42 }],
            [{ x: -0.13, y: -0.32 }, { x: 0.13, y: -0.32 }],
            [{ x: -0.11, y: -0.32 }, { x: -0.06, y: 0.38 }, { x: 0.06, y: 0.38 }, { x: 0.11, y: -0.32 }],
            [{ x: -0.04, y: 0.38 }, { x: -0.04, y: 0.48 }, { x: 0.04, y: 0.48 }, { x: 0.04, y: 0.38 }]
        ];
    case "tapex":
        return [
            [{ x: -0.45, y: -0.12 }, { x: 0.45, y: -0.12 },
             { x: 0.48, y: -0.05 }, { x: 0.43, y: 0.03 }, { x: 0.47, y: 0.12 },
             { x: -0.45, y: 0.12 },
             { x: -0.48, y: 0.05 }, { x: -0.43, y: -0.03 }, { x: -0.45, y: -0.12 }],
            [{ x: -0.22, y: -0.09 }, { x: -0.18, y: 0.09 }],
            [{ x: 0.18, y: -0.09 }, { x: 0.22, y: 0.09 }]
        ];
    case "disco":
        return [
            ellipsePts(0, 0, 0.45, 0.45, 0, 2 * Math.PI, 24),
            [{ x: -0.06, y: -0.45 }, { x: 0, y: -0.55 }, { x: 0.06, y: -0.45 }],
            ellipsePts(0, 0, 0.45, 0.14, 0, 2 * Math.PI, 16),
            ellipsePts(0, -0.22, 0.38, 0.11, 0, 2 * Math.PI, 16),
            ellipsePts(0, 0.22, 0.38, 0.11, 0, 2 * Math.PI, 16),
            ellipsePts(0, 0, 0.18, 0.45, 0, 2 * Math.PI, 16)
        ];
    case "eq":
        return [
            [{ x: -0.5, y: 0.5 }, { x: 0.5, y: 0.5 }],
            [{ x: -0.35, y: 0.5 }, { x: -0.35, y: -0.2 }],
            [{ x: -0.12, y: 0.5 }, { x: -0.12, y: -0.5 }],
            [{ x: 0.12, y: 0.5 }, { x: 0.12, y: -0.35 }],
            [{ x: 0.35, y: 0.5 }, { x: 0.35, y: -0.1 }],
            [{ x: -0.42, y: -0.3 }, { x: -0.28, y: -0.3 }],
            [{ x: -0.19, y: -0.6 }, { x: -0.05, y: -0.6 }],
            [{ x: 0.05, y: -0.45 }, { x: 0.19, y: -0.45 }],
            [{ x: 0.28, y: -0.2 }, { x: 0.42, y: -0.2 }]
        ];
    case "laser":
        return [
            [{ x: -0.45, y: -0.45 }, { x: 0.45, y: 0.45 }],
            [{ x: -0.45, y: 0.45 }, { x: 0.45, y: -0.45 }],
            starPts(0.4, 0.12),
            ellipsePts(0, 0, 0.25, 0.25, 0, 2 * Math.PI, 16)
        ];
    case "calm_leaf":
        return [
            [{ x: 0, y: 0 }, { x: 0.15, y: -0.22 }, { x: 0.45, y: -0.28 }, { x: 0.82, y: -0.12 },
             { x: 0.58, y: 0.18 }, { x: 0.22, y: 0.16 }, { x: 0, y: 0 }],
            [{ x: -0.18, y: 0.08 }, { x: 0, y: 0 }],
            [{ x: 0, y: 0 }, { x: 0.40, y: -0.06 }, { x: 0.82, y: -0.12 }],
            [{ x: 0.25, y: -0.04 }, { x: 0.18, y: -0.16 }],
            [{ x: 0.25, y: -0.04 }, { x: 0.32, y: 0.12 }],
            [{ x: 0.50, y: -0.08 }, { x: 0.44, y: -0.22 }],
            [{ x: 0.50, y: -0.08 }, { x: 0.55, y: 0.08 }]
        ];
    case "droplet":
        return [
            [{ x: 0, y: -0.52 }, { x: 0.18, y: -0.12 }, { x: 0.26, y: 0.18 }, { x: 0.15, y: 0.38 },
             { x: 0, y: 0.45 }, { x: -0.15, y: 0.38 }, { x: -0.26, y: 0.18 }, { x: -0.18, y: -0.12 },
             { x: 0, y: -0.52 }],
            [{ x: -0.10, y: 0.0 }, { x: -0.14, y: 0.22 }],
            ellipsePts(0, 0.15, 0.08, 0.08, 0, 2 * Math.PI, 10)
        ];
    case "moonrise": {
        // a fat crescent opening right: the outer rim round the left, the inner rim back
        var Cr = ellipsePts(0, 0, 0.5, 0.5, Math.PI * 0.3, Math.PI * 1.7, 26);
        return [Cr.concat(ellipsePts(0.213, 0, 0.413, 0.413, 2 * Math.PI - 1.373, 1.373, 22))];
    }
    case "classic_vinyl":
    case "vinyl":
        // rim, two broken grooves (so the spin shows), the label and the spindle hole
        return [
            ellipsePts(0, 0, 0.48, 0.48, 0, 2 * Math.PI, 30),
            ellipsePts(0, 0, 0.38, 0.38, 0.4, 2 * Math.PI - 0.5, 24),
            ellipsePts(0, 0, 0.29, 0.29, 2.2, 2 * Math.PI + 1.6, 20),
            ellipsePts(0, 0, 0.15, 0.15, 0, 2 * Math.PI, 16),
            ellipsePts(0, 0, 0.03, 0.03, 0, 2 * Math.PI, 8)
        ];
    case "classic_smoke":
    case "smoke":
        return [
            bezier({ x: 0, y: 0.35 }, { x: -0.22, y: 0.12 }, { x: 0.18, y: -0.15 }, { x: -0.06, y: -0.48 }, 20),
            bezier({ x: -0.22, y: 0.32 }, { x: -0.35, y: 0.08 }, { x: -0.12, y: -0.18 }, { x: -0.26, y: -0.42 }, 18),
            bezier({ x: 0.22, y: 0.32 }, { x: 0.35, y: 0.08 }, { x: 0.12, y: -0.18 }, { x: 0.26, y: -0.42 }, 18),
            ellipsePts(-0.06, -0.48, 0.10, 0.07, 0, Math.PI * 1.6, 12)
        ];
    case "horn":
        // a trumpet side on, mouthpiece left, bell flaring right to x = 0.56
        return [
            [{ x: -0.62, y: -0.05 }, { x: -0.57, y: 0 }, { x: -0.62, y: 0.05 }],
            [{ x: -0.57, y: -0.025 }, { x: -0.2, y: -0.025 }], [{ x: -0.57, y: 0.025 }, { x: -0.2, y: 0.025 }],
            [{ x: -0.2, y: -0.08 }, { x: -0.02, y: -0.08 }, { x: -0.02, y: 0.1 }, { x: -0.2, y: 0.1 }, { x: -0.2, y: -0.08 }],
            [{ x: -0.165, y: -0.08 }, { x: -0.165, y: -0.17 }], [{ x: -0.19, y: -0.17 }, { x: -0.14, y: -0.17 }],
            [{ x: -0.11, y: -0.08 }, { x: -0.11, y: -0.17 }], [{ x: -0.135, y: -0.17 }, { x: -0.085, y: -0.17 }],
            [{ x: -0.055, y: -0.08 }, { x: -0.055, y: -0.17 }], [{ x: -0.08, y: -0.17 }, { x: -0.03, y: -0.17 }],
            bezier({ x: -0.18, y: 0.1 }, { x: -0.2, y: 0.24 }, { x: 0.02, y: 0.24 }, { x: 0.02, y: 0.1 }, 12),
            bezier({ x: -0.02, y: -0.025 }, { x: 0.3, y: -0.03 }, { x: 0.46, y: -0.08 }, { x: 0.56, y: -0.24 }, 16),
            bezier({ x: -0.02, y: 0.025 }, { x: 0.3, y: 0.03 }, { x: 0.46, y: 0.08 }, { x: 0.56, y: 0.24 }, 16),
            ellipsePts(0.56, 0, 0.05, 0.24, 0, 2 * Math.PI, 20)
        ];
    case "flash":
        return [
            star4Pts(0.50, 0.12),
            star4Pts(0.22, 0.05),
            [{ x: -0.65, y: 0 }, { x: 0.65, y: 0 }],
            [{ x: 0, y: -0.65 }, { x: 0, y: 0.65 }]
        ];
    case "focus": {
        var Foc = [];
        for (var fi = 0; fi < 16; fi++) {
            var fa = fi * (2 * Math.PI / 16);
            Foc.push([
                { x: 0.50 * Math.cos(fa), y: 0.50 * Math.sin(fa) },
                { x: 0.22 * Math.cos(fa), y: 0.22 * Math.sin(fa) }
            ]);
        }
        return Foc;
    }
    case "sakura":
        return [
            [
                { x: 0, y: 0.45 },
                { x: -0.22, y: 0.18 },
                { x: -0.25, y: -0.15 },
                { x: -0.14, y: -0.38 },
                { x: -0.06, y: -0.45 },
                { x: 0, y: -0.32 },
                { x: 0.06, y: -0.45 },
                { x: 0.14, y: -0.38 },
                { x: 0.25, y: -0.15 },
                { x: 0.22, y: 0.18 },
                { x: 0, y: 0.45 }
            ],
            [{ x: 0, y: 0.35 }, { x: 0, y: -0.12 }]
        ];
    case "sunrise":
        // the top half of the sun, an inner rim, cut flat at the horizon (y = 0)
        return [
            ellipsePts(0, 0, 0.5, 0.5, Math.PI, 2 * Math.PI, 26),
            ellipsePts(0, 0, 0.36, 0.36, Math.PI * 1.12, Math.PI * 1.88, 18)
        ];
    case "flock":
        return [
            // Outstretched folk bird in flight
            [
                { x: -0.48, y: -0.20 },
                { x: -0.22, y: -0.04 },
                { x: 0, y: 0 },
                { x: 0.22, y: -0.04 },
                { x: 0.48, y: -0.20 }
            ],
            // Lower wing and body
            [
                { x: -0.48, y: -0.20 },
                { x: -0.20, y: 0.08 },
                { x: 0, y: 0.22 },
                { x: 0.20, y: 0.08 },
                { x: 0.48, y: -0.20 }
            ],
            // Head and swallow tail
            [
                { x: 0, y: -0.14 },
                { x: 0, y: 0.28 },
                { x: -0.08, y: 0.40 }
            ],
            [
                { x: 0, y: 0.28 },
                { x: 0.08, y: 0.40 }
            ]
        ];
    case "folk_sprout":
    case "sprout":
        return [
            // Central stem
            [{ x: 0, y: 0.50 }, { x: 0, y: 0 }],
            // Left cotyledon leaf
            [
                { x: 0, y: 0 },
                { x: -0.22, y: -0.12 },
                { x: -0.38, y: -0.22 },
                { x: -0.32, y: -0.04 },
                { x: 0, y: 0 }
            ],
            // Right cotyledon leaf
            [
                { x: 0, y: 0 },
                { x: 0.22, y: -0.12 },
                { x: 0.38, y: -0.22 },
                { x: 0.32, y: -0.04 },
                { x: 0, y: 0 }
            ],
            // Seedling base
            [{ x: -0.12, y: 0.48 }, { x: 0.12, y: 0.48 }]
        ];
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
    if (!L || !L.pile || L.pile.role !== "peak" || !(L.pile.fx in PROP_D) || !(W > 1) || !(px > 1)) return out;
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
            // it floats off to the word's upper right, no higher than the bulb hangs
            return { x: W / 2 + 0.9 * px + 0.2 * px * Math.sin(2.1 * ta),
                     y: bl - 1.6 * px + 3.5 * px * Math.exp(-5 * ta) * Math.cos(4 * ta), tilt: 6 * Math.sin(2.1 * ta + 0.8) };
        };
        if (t < pop) {
            var b = bAt(tau);
            put(0, place(propShape("balloon"), b.x, b.y, b.tilt, 0.8 * px), 1, true, 0.95, 0.05, 3);
            var knot = place([[{ x: 0, y: 0.62 }]], b.x, b.y, b.tilt, 0.8 * px)[0][0];
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
        // it comes down nearly straight at the end, so once stuck its tail stands up clear of the next word
        var c1 = { x: W - 0.1 * px, y: bl - 2.6 * px }, p1 = { x: W - 0.12 * px, y: bl - 0.72 * px };
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
    case "shatter": {
        // the hero hits like a stone through glass: a cracked pane behind the word with arms running
        // well past its edges and two broken rings, shards break off the rim and tumble away
        var ix = W * 0.58, iy = bl - 0.42 * px, rxS = W * 0.5 + 0.95 * px, ryS = 1.2 * px;
        var nArm = 9, arms = [];
        for (var ak = 0; ak < nArm; ak++) {
            var aa = (ak + 0.5 + 0.35 * M.rs(sd, ak, 921)) / nArm * 2 * Math.PI;
            var reach = 0.8 + 0.2 * M.r(sd, ak, 922), arm = [];
            for (var ai = 0; ai <= 5; ai++) {
                var av = ai / 5, jit = ai > 0 && ai < 5 ? 0.07 * px * M.rs(sd, ak * 7 + ai, 923) : 0;
                arm.push({ x: ix + Math.cos(aa) * rxS * reach * av - Math.sin(aa) * jit,
                           y: iy + Math.sin(aa) * ryS * reach * av + Math.cos(aa) * jit });
            }
            arms.push(arm);
        }
        function armAt(k, v) { var A = arms[k % nArm], f = v * 5, i0 = Math.min(4, Math.floor(f)), fr = f - i0;
            return { x: A[i0].x + (A[i0 + 1].x - A[i0].x) * fr, y: A[i0].y + (A[i0 + 1].y - A[i0].y) * fr }; }
        var crackFade = fade(tp - 0.75, 0.35);
        if (tp < 0) {
            // a hairline star at the impact point just before the hit
            if (tp > -0.2) put(0, arms, 0.1 * M.clamp((tp + 0.2) / 0.2), true, 0.7, 0.03, -1);
        } else {
            var grow = M.E.outCubic(M.clamp(tp / 0.14)), Pane = arms.slice();
            if (tp > 0.05) {
                // two broken rings, every third span missing
                [0.42, 0.78].forEach(function (rv, ri) {
                    for (var k = 0; k < nArm; k++) {
                        if ((k + ri) % 3 === 2) continue;
                        var a0 = armAt(k, rv), a1 = armAt(k + 1, rv * (0.95 + 0.1 * M.r(sd, k, 924)));
                        var mid = { x: (a0.x + a1.x) / 2 + 0.05 * px * M.rs(sd, k + ri * 9, 925), y: (a0.y + a1.y) / 2 + 0.05 * px * M.rs(sd, k + ri * 9, 926) };
                        Pane.push([a0, mid, a1]);
                    }
                });
            }
            put(0, Pane, grow, true, 0.8 * crackFade, 0.032, -1);
            // shards break off the outer ring and tumble down and out
            var Shards = [];
            for (var sk = 0; sk < 7; sk++) {
                var sa = (sk + 0.5) / 7 * Math.PI * 1.15 - 0.075 * Math.PI;
                var sx0 = ix + Math.cos(sa) * rxS * 0.95, sy0 = iy + Math.sin(sa) * ryS * 0.7;
                var dir = sx0 < ix ? -1 : 1, q = Math.max(0, tp - 0.04);
                var ssz = px * (0.9 + 0.5 * M.r(sd, sk, 927));
                Shards = Shards.concat(place(propShape("shard"), sx0 + dir * (0.5 + 0.4 * M.r(sd, sk, 928)) * px * q,
                                             sy0 - 0.6 * px * q + 4.2 * px * q * q,
                                             dir * (200 + 160 * M.r(sd, sk, 929)) * q + 40 * M.rs(sd, sk, 930), ssz));
            }
            put(1, Shards, 1, false, 0.95 * fade(tp - 0.45, 0.4), 0.035, 3);
            // the hit: short flicks bursting out of the impact point
            var Sp = [];
            for (var spk = 0; spk < 8; spk++) {
                var spa = spk / 8 * 2 * Math.PI + 0.2, r0 = (0.18 + 0.9 * M.E.outQuad(M.clamp(tp / 0.2))) * px;
                Sp.push([{ x: ix + r0 * Math.cos(spa), y: iy + r0 * Math.sin(spa) * 0.8 },
                         { x: ix + (r0 + 0.22 * px) * Math.cos(spa), y: iy + (r0 + 0.22 * px) * Math.sin(spa) * 0.8 }]);
            }
            put(2, Sp, 1, true, fade(tp - 0.08, 0.14), 0.04, 4);
        }
        break;
    }
    case "snap": {
        // a guitar string pegged above the word pulls taut and hums, then snaps over the hero:
        // both halves whip back toward their pegs and coil up
        var ySn = bl - 1.38 * px, x0 = -0.45 * px, x1 = W + 0.45 * px, xBrk = W / 2;
        var snapFade = fade(tp - 0.75, 0.35);
        var Pegs = [];
        [x0, x1].forEach(function (xp) {
            Pegs.push(ellipsePts(xp, ySn, 0.08 * px, 0.08 * px, 0, 2 * Math.PI, 12));
            Pegs.push([{ x: xp, y: ySn + 0.08 * px }, { x: xp, y: ySn + 0.3 * px }]);
        });
        put(1, Pegs, M.clamp(tau / 0.15), false, 0.85 * snapFade, 0.035, 3);
        if (tp < 0) {
            // drawn across peg to peg, then plucked: it hums wider and faster up to the snap
            var uSn = M.clamp(tau / (PROP_D.snap * 0.45)), hum = M.clamp((tau - PROP_D.snap * 0.45) / (PROP_D.snap * 0.55));
            var amp = 0.12 * px * hum * hum, Str = [];
            for (var si = 0; si <= 24; si++) {
                var su = si / 24;
                Str.push({ x: x0 + (x1 - x0) * su, y: ySn + amp * Math.sin(su * Math.PI) * Math.sin(tau * (30 + 30 * hum)) });
            }
            put(0, [Str], uSn, false, 0.9, 0.035, 3);
            if (hum > 0.6) {
                // the strand frays at the middle just before it goes
                var Fr = [];
                for (var fk = 0; fk < 3; fk++) {
                    var fa = -Math.PI / 2 + (fk - 1) * 0.6;
                    Fr.push([{ x: xBrk, y: ySn }, { x: xBrk + 0.16 * px * Math.cos(fa), y: ySn + 0.16 * px * Math.sin(fa) }]);
                }
                put(2, Fr, 1, true, (hum - 0.6) / 0.4, 0.03, 4);
            }
        } else {
            var rec = M.E.outCubic(M.clamp(tp / 0.28)), whip = Math.sin(Math.PI * M.clamp(tp / 0.4)) * Math.exp(-2.5 * tp);
            var halves = [];
            [[x0, 1], [x1, -1]].forEach(function (hs) {
                var xp = hs[0], dir = hs[1], len = Math.abs(xBrk - xp), H = [];
                for (var j = 0; j <= 24; j++) {
                    var sj = j / 24, along = len * (1 - 0.55 * rec) * sj, hx = xp + dir * along, hy = ySn;
                    hy -= 0.45 * px * whip * Math.sin(Math.PI * sj * 0.8);
                    if (sj > 0.55) {
                        // the loose end coils back on itself
                        var cf = (sj - 0.55) / 0.45, ang = rec * 2.4 * Math.PI * cf, rc = 0.24 * px * rec * cf;
                        hx += dir * (rc * Math.sin(ang) - rc * ang * 0.15);
                        hy -= rc * (1 - Math.cos(ang));
                    }
                    H.push({ x: hx, y: hy });
                }
                halves.push(H);
            });
            put(0, halves, 1, false, 0.9 * snapFade, 0.035, 3);
            // the break: a star of flicks where it went
            var Bk = [];
            for (var bk = 0; bk < 7; bk++) {
                var ba = bk / 7 * 2 * Math.PI - Math.PI / 2, b0 = (0.1 + 0.5 * M.E.outQuad(M.clamp(tp / 0.18))) * px;
                Bk.push([{ x: xBrk + b0 * Math.cos(ba), y: ySn + b0 * Math.sin(ba) * 0.7 },
                         { x: xBrk + (b0 + 0.2 * px) * Math.cos(ba), y: ySn + (b0 + 0.2 * px) * Math.sin(ba) * 0.7 }]);
            }
            put(2, Bk, 1, true, fade(tp - 0.06, 0.16), 0.04, 4);
        }
        break;
    }
    case "rip": {
        // the word tears along a jagged line, the halves slip apart, then close
        var ncRip = hw.chars.length;
        var midRip = ncRip > 1 ? Math.ceil(ncRip / 2) : 0.5;
        var gxRip = W * (ncRip > 1 ? midRip / ncRip : 0.5);
        var yTop = bl - 0.95 * px, yBot = bl + 0.18 * px;
        var ripPts = [
            { x: gxRip, y: yTop },
            { x: gxRip + 0.06 * px, y: yTop + 0.22 * px },
            { x: gxRip - 0.06 * px, y: yTop + 0.44 * px },
            { x: gxRip + 0.07 * px, y: yTop + 0.66 * px },
            { x: gxRip - 0.05 * px, y: yTop + 0.88 * px },
            { x: gxRip, y: yBot }
        ];
        if (tp < 0) {
            put(0, [ripPts], M.clamp(tau / PROP_D.rip), true, 0.85, 0.035, 2);
        } else {
            var spRip = ripSplit(L, t);
            var shiftXL = -0.18 * px * spRip, shiftYL = -0.16 * px * spRip;
            var shiftXR = 0.18 * px * spRip, shiftYR = 0.16 * px * spRip;
            var edgeL = ripPts.map(function (p) { return { x: p.x + shiftXL, y: p.y + shiftYL }; });
            var edgeR = ripPts.map(function (p) { return { x: p.x + shiftXR, y: p.y + shiftYR }; });
            put(0, [edgeL], 1, true, 0.85 * fade(tp - sung - 0.4, 0.3), 0.035, 2);
            put(1, [edgeR], 1, true, 0.85 * fade(tp - sung - 0.4, 0.3), 0.035, 2);
            if (spRip > 0.05) {
                var Fibers = [];
                for (var fi = 1; fi < ripPts.length - 1; fi++) {
                    Fibers.push([edgeL[fi], edgeR[fi]]);
                }
                put(2, Fibers, 1, false, 0.6 * spRip, 0.02, 1);
            }
            if (tp < 0.25) {
                var Flecks = [
                    [{ x: gxRip - 0.05 * px - 0.2 * px * tp, y: yTop + 0.1 * px }, { x: gxRip - 0.15 * px - 0.3 * px * tp, y: yTop + 0.05 * px }],
                    [{ x: gxRip + 0.05 * px + 0.2 * px * tp, y: yBot - 0.1 * px }, { x: gxRip + 0.15 * px + 0.3 * px * tp, y: yBot - 0.05 * px }]
                ];
                put(3, Flecks, 1, true, fade(tp, 0.25), 0.03, 3);
            }
        }
        break;
    }
    case "spray": {
        // a spray can flies in, shakes, sprays a tag behind the word, paint drips down
        var canX0 = W + 2.0 * px, canY0 = bl - 1.6 * px;
        var canTargetX = W + 0.35 * px, canTargetY = bl - 0.52 * px;
        var canX, canY, canRot = -20;
        if (tp < 0) {
            var uSpray = M.clamp(tau / PROP_D.spray);
            var inS = M.E.outCubic(uSpray);
            canX = canX0 + (canTargetX - canX0) * inS;
            canY = canY0 + (canTargetY - canY0) * inS;
            if (uSpray > 0.4) {
                var rattle = 0.03 * px * Math.sin(tau * 40) * (uSpray - 0.4) / 0.6;
                canX += rattle;
                canY += rattle * 0.6;
                canRot += 4 * Math.sin(tau * 40);
            }
            put(0, place(propShape("spray"), canX, canY, canRot, px * 0.72), 1, false, 0.9, 0.035, 3);
        } else {
            var spraySung = Math.max(0.4, sung);
            var recoil = tp < 0.35 ? 0.02 * px * Math.sin(tp * 48) : 0;
            canX = canTargetX + recoil;
            canY = canTargetY;
            var canFade = fade(tp - spraySung - 0.2, 0.35);
            put(0, place(propShape("spray"), canX, canY, canRot, px * 0.72), 1, false, 0.9 * canFade, 0.035, 3);

            // Piece 1: Sprayed graffiti bubble tag behind the word (z: -1, behind the letters)
            var tagProg = M.clamp(tp / 0.22);
            var Tag = [];
            var padX = 0.12 * px, tagTop = bl - 0.9 * px, tagBot = bl + 0.12 * px;
            var wL = -padX, wR = W + padX;
            // puffy graffiti throw-up cloud outline behind word
            var cloud = [
                { x: wL, y: bl - 0.4 * px },
                { x: wL + 0.1 * px, y: tagTop },
                { x: wL + (wR - wL) * 0.3, y: tagTop - 0.08 * px },
                { x: wL + (wR - wL) * 0.5, y: tagTop + 0.04 * px },
                { x: wL + (wR - wL) * 0.7, y: tagTop - 0.06 * px },
                { x: wR - 0.1 * px, y: tagTop },
                { x: wR, y: bl - 0.4 * px },
                { x: wR - 0.05 * px, y: tagBot },
                { x: wL + (wR - wL) * 0.7, y: tagBot + 0.06 * px },
                { x: wL + (wR - wL) * 0.3, y: tagBot + 0.04 * px },
                { x: wL, y: tagBot - 0.04 * px },
                { x: wL, y: bl - 0.4 * px }
            ];
            Tag.push(cloud);
            // dynamic street tag slash underline
            Tag.push([
                { x: wL - 0.06 * px, y: bl + 0.08 * px },
                { x: wR + 0.06 * px, y: bl + 0.05 * px }
            ]);
            put(1, Tag, tagProg, true, 0.8 * fade(tp - spraySung - 0.4, 0.4), 0.045, -1);

            // Piece 2: Paint drips running down below the baseline (z: 1)
            var Drips = [];
            var dripXs = [W * 0.25, W * 0.55, W * 0.85];
            for (var dri = 0; dri < dripXs.length; dri++) {
                var dx = dripXs[dri] + 0.04 * px * M.rs(sd, dri, 933);
                var maxDripH = (0.35 + 0.15 * dri) * px;
                var curDripH = maxDripH * M.clamp((tp - 0.08 * dri) / 0.3);
                if (curDripH > 0.01) {
                    var dy0 = bl + 0.06 * px, dy1 = dy0 + curDripH;
                    var rw = 0.035 * px;
                    Drips.push([
                        { x: dx - rw, y: dy0 },
                        { x: dx - rw, y: dy1 - rw },
                        { x: dx, y: dy1 },
                        { x: dx + rw, y: dy1 - rw },
                        { x: dx + rw, y: dy0 }
                    ]);
                    if (tp > 0.3 + 0.08 * dri) {
                        var dropY = dy1 + 0.09 * px;
                        Drips.push([
                            { x: dx, y: dropY - rw },
                            { x: dx + rw, y: dropY },
                            { x: dx, y: dropY + rw },
                            { x: dx - rw, y: dropY },
                            { x: dx, y: dropY - rw }
                        ]);
                    }
                }
            }
            put(2, Drips, 1, true, 0.9 * fade(tp - spraySung - 0.5, 0.4), 0.035, 1);

            if (tp < 0.42) {
                var nozX = canX - 0.14 * px, nozY = canY - 0.35 * px;
                var Mist = [];
                for (var mi = 0; mi < 6; mi++) {
                    var mAngle = Math.PI + 0.22 * (mi - 2.5);
                    var mDist = (0.28 + 0.3 * M.r(sd, mi, 934)) * px * M.clamp(tp / 0.15);
                    Mist.push([
                        { x: nozX, y: nozY },
                        { x: nozX + Math.cos(mAngle) * mDist, y: nozY + Math.sin(mAngle) * mDist }
                    ]);
                }
                put(3, Mist, 1, true, fade(tp, 0.42), 0.03, 3);
            }
        }
        break;
    }
    case "micdrop": {
        // a mic drops onto the baseline, bounces, sound lines radiate
        var micX = W + 0.05 * px;
        var landY = bl - 0.08 * px;
        if (tp < 0) {
            var uMic = M.clamp(tau / PROP_D.micdrop);
            var dropY = (bl - 2.2 * px) + (2.12 * px) * (uMic * uMic);
            var dropRot = -20 + 35 * uMic;
            put(0, place(propShape("micdrop"), micX, dropY, dropRot, px * 0.72), 1, false, 0.9, 0.035, 2);
            var cable = bezier({ x: micX, y: dropY + 0.32 * px },
                               { x: micX + 0.35 * px, y: dropY + 0.9 * px },
                               { x: micX + 0.65 * px, y: bl - 1.8 * px },
                               { x: micX + 0.95 * px, y: bl - 2.2 * px }, 12);
            put(3, [cable], 1, false, 0.65, 0.025, 1);
        } else {
            var bounce = Math.abs(Math.exp(-8 * tp) * Math.cos(16 * tp));
            var curY = landY - 0.28 * px * bounce;
            var curRot = 65 + 16 * Math.exp(-6 * tp) * Math.sin(14 * tp);
            var micFade = fade(tp - sung - 0.4, 0.4);
            put(0, place(propShape("micdrop"), micX, curY, curRot, px * 0.72), 1, false, 0.9 * micFade, 0.035, 2);

            var SoundLines = [];
            for (var si = 0; si < 3; si++) {
                var sDelay = si * 0.06;
                var stp = tp - sDelay;
                if (stp > 0 && stp < 0.42) {
                    var sRad = (0.2 + 0.85 * (stp / 0.35)) * px;
                    var arcPts = [];
                    for (var ai = 0; ai <= 12; ai++) {
                        var ang = -Math.PI * 0.95 + (ai / 12) * Math.PI * 0.65;
                        arcPts.push({ x: micX + sRad * Math.cos(ang), y: bl + sRad * Math.sin(ang) * 0.65 });
                    }
                    SoundLines.push(arcPts);
                }
            }
            if (SoundLines.length) put(1, SoundLines, 1, true, fade(tp, 0.42), 0.035, 3);

            if (tp < 0.28) {
                var Ticks = [
                    [{ x: micX - 0.28 * px, y: bl }, { x: micX + 0.28 * px, y: bl }],
                    [{ x: micX - 0.15 * px, y: bl }, { x: micX - 0.24 * px, y: bl - 0.12 * px }],
                    [{ x: micX + 0.15 * px, y: bl }, { x: micX + 0.24 * px, y: bl - 0.12 * px }]
                ];
                put(2, Ticks, 1, true, fade(tp, 0.28), 0.035, 2);
            }

            var restCable = bezier({ x: micX + 0.22 * px, y: curY + 0.08 * px },
                                   { x: micX + 0.5 * px, y: bl + 0.06 * px },
                                   { x: micX + 0.85 * px, y: bl - 0.02 * px },
                                   { x: micX + 1.2 * px, y: bl + 0.04 * px }, 12);
            put(3, [restCable], 1, false, 0.7 * micFade, 0.025, 1);
        }
        break;
    }
    case "tapex": {
        // two tape strips slap on crosswise over the corner
        var cxTape = 0.06 * W;
        var cyTape = bl - 0.82 * px;
        var ang1 = 38, ang2 = -42;
        var tapeFade = fade(tp - sung - 0.4, 0.35);

        var tStrip1 = tau / (PROP_D.tapex * 0.6);
        if (tStrip1 > 0.05) {
            var s1Prog = M.clamp(tStrip1);
            var s1X = cxTape - 0.4 * px * (1 - M.E.outBack(s1Prog, 1.5));
            var s1Y = cyTape - 0.4 * px * (1 - M.E.outBack(s1Prog, 1.5));
            var s1Shape = place(propShape("tapex"), s1X, s1Y, ang1, px * 0.75);
            put(0, s1Shape, 1, false, 0.85 * tapeFade, 0.035, 3);
        }

        if (tp >= -0.2) {
            var s2Prog = M.clamp((tau - PROP_D.tapex * 0.6) / (PROP_D.tapex * 0.4));
            var s2X = cxTape + 0.35 * px * (1 - M.E.outBack(s2Prog, 1.8));
            var s2Y = cyTape - 0.45 * px * (1 - M.E.outBack(s2Prog, 1.8));
            var s2Shape = place(propShape("tapex"), s2X, s2Y, ang2, px * 0.75);
            put(1, s2Shape, 1, false, 0.85 * tapeFade, 0.035, 3);
        }

        if (tp >= 0) {
            var Creases = [
                [{ x: cxTape - 0.12 * px, y: cyTape - 0.08 * px }, { x: cxTape + 0.12 * px, y: cyTape + 0.08 * px }],
                [{ x: cxTape - 0.08 * px, y: cyTape + 0.12 * px }, { x: cxTape + 0.08 * px, y: cyTape - 0.12 * px }]
            ];
            put(2, Creases, 1, true, 0.8 * tapeFade, 0.025, 4);

            if (tp < 0.22) {
                var SnapTicks = [];
                for (var sti = 0; sti < 4; sti++) {
                    var stAng = sti * (Math.PI / 2) + Math.PI / 4;
                    SnapTicks.push([
                        { x: cxTape + 0.15 * px * Math.cos(stAng), y: cyTape + 0.15 * px * Math.sin(stAng) },
                        { x: cxTape + 0.35 * px * Math.cos(stAng), y: cyTape + 0.35 * px * Math.sin(stAng) }
                    ]);
                }
                put(3, SnapTicks, 1, true, fade(tp, 0.22), 0.035, 4);
            }
        }
        break;
    }
    case "disco": {
        // a disco ball lowers on its cord, turns, throws light flecks
        var cxDisco = W * 0.5;
        var cyTop = bl - 3.2 * px;
        var cyRest = bl - 1.45 * px;
        var rDisco = 0.42 * px;
        var cyDisco;
        var discoFade = fade(tp - sung - 0.5, 0.4);

        if (tp < 0) {
            var uDisco = M.clamp(tau / PROP_D.disco);
            cyDisco = cyTop + (cyRest - cyTop) * M.E.outBack(uDisco, 1.4);
        } else {
            var bob = 0.04 * px * Math.exp(-4 * tp) * Math.sin(16 * tp);
            cyDisco = cyRest + bob;
        }

        // Piece 0: Hanging cord + ball outer contour and hanger cap (z: 3)
        var Ball = [
            [{ x: cxDisco, y: cyTop }, { x: cxDisco, y: cyDisco - rDisco }],
            [{ x: cxDisco - 0.07 * px, y: cyDisco - rDisco }, { x: cxDisco, y: cyDisco - rDisco - 0.08 * px }, { x: cxDisco + 0.07 * px, y: cyDisco - rDisco }],
            ellipsePts(cxDisco, cyDisco, rDisco, rDisco, 0, 2 * Math.PI, 28)
        ];
        put(0, Ball, 1, false, 0.95 * discoFade, 0.035, 3);

        // Piece 1: Rotating facet grid (latitude rings + spinning longitude meridians) (z: 3)
        var spinAng = tau * 3.8;
        var Facets = [
            ellipsePts(cxDisco, cyDisco, rDisco * 0.98, rDisco * 0.28, 0, 2 * Math.PI, 20),
            ellipsePts(cxDisco, cyDisco - rDisco * 0.46, rDisco * 0.88, rDisco * 0.22, 0, 2 * Math.PI, 18),
            ellipsePts(cxDisco, cyDisco + rDisco * 0.46, rDisco * 0.88, rDisco * 0.22, 0, 2 * Math.PI, 18)
        ];
        for (var mi = 0; mi < 4; mi++) {
            var mPh = spinAng + mi * (Math.PI / 4);
            var mRx = rDisco * Math.sin(mPh);
            if (Math.abs(mRx) > 0.02 * px) {
                Facets.push(ellipsePts(cxDisco, cyDisco, Math.abs(mRx), rDisco, -Math.PI / 2, Math.PI / 2, 14));
            }
        }
        put(1, Facets, 1, false, 0.78 * discoFade, 0.025, 3);

        // Piece 2: Light flecks / specular reflections dancing across the hero word (z: 2)
        if (tp >= 0) {
            var Flecks = [];
            for (var fi = 0; fi < 8; fi++) {
                var fAng = spinAng * 1.5 + fi * (Math.PI / 4) + 0.2 * M.rs(sd, fi, 921);
                var fDist = (0.7 + 0.9 * M.r(sd, fi, 922)) * px;
                var fxX = cxDisco + fDist * Math.cos(fAng);
                var fxY = bl - 0.45 * px + 0.35 * px * Math.sin(fAng * 2 + tp * 6);
                var flkLen = 0.06 * px;
                Flecks.push([
                    { x: fxX - flkLen, y: fxY },
                    { x: fxX + flkLen, y: fxY }
                ]);
                Flecks.push([
                    { x: fxX, y: fxY - flkLen },
                    { x: fxX, y: fxY + flkLen }
                ]);
            }
            put(2, Flecks, 1, true, 0.9 * fade(tp - sung - 0.3, 0.4), 0.035, 2);

            // Piece 3: Star sparkle glints on ball highlight (z: 4)
            var glintPhase = tp * 5;
            var gx = cxDisco + rDisco * 0.55 * Math.cos(glintPhase);
            var gy = cyDisco - rDisco * 0.35;
            var Glints = [
                [{ x: gx - 0.12 * px, y: gy }, { x: gx + 0.12 * px, y: gy }],
                [{ x: gx, y: gy - 0.12 * px }, { x: gx, y: gy + 0.12 * px }]
            ];
            put(3, Glints, 1, true, fade(tp - sung - 0.2, 0.3), 0.04, 4);
        }
        break;
    }
    case "eq": {
        // a row of LED equalizer bars stands behind the word, wider than it, and jumps with the
        // singing; the tall middle bars rise clear above the letters, peak dashes ride on top
        var eqFade = fade(tp - sung - 0.5, 0.4);
        var eqX0 = -1.1 * px, eqX1 = W + 1.1 * px, eqBaseY = bl + 0.1 * px, rung = 0.17 * px;
        var nBars = Math.max(7, Math.round((eqX1 - eqX0) / (0.34 * px))), bHalf = 0.11 * px;
        var BarStrokes = [], PeakHold = [], grow = M.E.outCubic(M.clamp(tau / PROP_D.eq));
        for (var bi = 0; bi < nBars; bi++) {
            var bv = (bi + 0.5) / nBars, bx = eqX0 + (eqX1 - eqX0) * bv;
            var env = 0.45 + 0.55 * Math.sin(Math.PI * bv), lvl;
            if (tp < 0) lvl = grow * (0.25 + 0.15 * Math.sin(tau * 11 + bi * 1.3));
            else {
                var jump = Math.abs(Math.sin(tp * (13 + 4 * M.r(sd, bi, 941)) + bi * 1.7) * Math.cos(tp * 6.5 + bi * 0.9));
                lvl = 0.35 + 0.65 * jump;
            }
            var barH = 2.1 * px * env * lvl, nOn = Math.max(1, Math.floor(barH / rung));
            for (var ri = 0; ri < nOn; ri++) {
                var ry = eqBaseY - (ri + 0.5) * rung;
                BarStrokes.push([{ x: bx - bHalf, y: ry }, { x: bx + bHalf, y: ry }]);
            }
            var peakY = eqBaseY - (nOn + 0.9) * rung;
            PeakHold.push([{ x: bx - bHalf, y: peakY }, { x: bx + bHalf, y: peakY }]);
        }
        put(1, BarStrokes, 1, true, 0.75 * eqFade, 0.07, -1, true);
        if (tp >= 0) put(2, PeakHold, 1, false, 0.85 * eqFade, 0.04, -1, true);
        break;
    }
    case "laser": {
        // two beams sweep across the word and cross on it
        var laserFade = fade(tp - sung - 0.4, 0.35);
        var e1X = -0.6 * px, e1Y = bl - 2.0 * px;
        var e2X = W + 0.6 * px, e2Y = bl - 2.0 * px;
        var targetMidX = W * 0.5, targetMidY = bl - 0.45 * px;

        var t1X, t1Y, t2X, t2Y;
        if (tp < 0) {
            var uLaser = M.clamp(tau / PROP_D.laser);
            var swp = M.E.outCubic(uLaser);
            var start1X = W * 1.15, start1Y = bl + 0.15 * px;
            var start2X = -0.15 * px, start2Y = bl + 0.15 * px;
            t1X = start1X + (targetMidX - start1X) * swp;
            t1Y = start1Y + (targetMidY - start1Y) * swp;
            t2X = start2X + (targetMidX - start2X) * swp;
            t2Y = start2Y + (targetMidY - start2Y) * swp;
        } else {
            var scan = 0.08 * px * Math.sin(tp * 20);
            t1X = targetMidX + scan;
            t1Y = targetMidY;
            t2X = targetMidX - scan;
            t2Y = targetMidY;
        }

        // Piece 0: The two sweeping laser beams and their emitter heads (z: 3)
        var Beams = [
            [{ x: e1X, y: e1Y }, { x: t1X, y: t1Y }],
            [{ x: e2X, y: e2Y }, { x: t2X, y: t2Y }],
            [{ x: e1X - 0.06 * px, y: e1Y - 0.04 * px }, { x: e1X + 0.06 * px, y: e1Y + 0.04 * px }],
            [{ x: e2X + 0.06 * px, y: e2Y - 0.04 * px }, { x: e2X - 0.06 * px, y: e2Y + 0.04 * px }]
        ];
        put(0, Beams, 1, true, 0.95 * laserFade, 0.038, 3);

        // Piece 1: Intersection flare / star burst at the crossing point (z: 4)
        if (tp >= 0) {
            var cxLaser = (t1X + t2X) * 0.5;
            var cyLaser = (t1Y + t2Y) * 0.5;
            var flareR = 0.22 * px * (1 + 0.2 * Math.sin(tp * 30));
            var Star = starPts(flareR, flareR * 0.32);
            var Flare = place([Star], cxLaser, cyLaser, tp * 40, 1)[0];
            var Ring = ellipsePts(cxLaser, cyLaser, flareR * 0.6, flareR * 0.6, 0, 2 * Math.PI, 16);
            put(1, [Flare, Ring], 1, true, 0.95 * laserFade, 0.035, 4);

            // Piece 2: Horizontal laser scan / burn underline across the hero word (z: 1)
            var Burn = [
                [{ x: -0.08 * px, y: bl + 0.06 * px }, { x: W + 0.08 * px, y: bl + 0.06 * px }],
                [{ x: -0.04 * px, y: bl + 0.10 * px }, { x: W + 0.04 * px, y: bl + 0.10 * px }]
            ];
            put(2, Burn, 1, false, 0.8 * laserFade, 0.03, 1);

            // Piece 3: Laser sparks scattering from the intersection point (z: 4)
            if (tp < 0.35) {
                var Sparks = [];
                for (var spi = 0; spi < 6; spi++) {
                    var spAng = spi * (Math.PI / 3) + 0.2 * M.rs(sd, spi, 951);
                    var spDist = (0.12 + 0.25 * (tp / 0.35)) * px;
                    Sparks.push([
                        { x: cxLaser + 0.05 * px * Math.cos(spAng), y: cyLaser + 0.05 * px * Math.sin(spAng) },
                        { x: cxLaser + spDist * Math.cos(spAng), y: cyLaser + spDist * Math.sin(spAng) }
                    ]);
                }
                put(3, Sparks, 1, true, fade(tp, 0.35), 0.032, 4);
            }
        }
        break;
    }
    case "calm_leaf": {
        // a leaf drifts down side to side and lands on the word
        var leafFade = fade(tp - sung - 0.45, 0.35);
        var landX = W * 0.5 + 0.05 * px;
        var landY = bl - 0.88 * px;
        var startY = bl - 2.8 * px;

        var xLeaf, yLeaf, tiltLeaf;
        if (tp < 0) {
            var uLeaf = M.clamp(tau / PROP_D.calm_leaf);
            yLeaf = startY + (landY - startY) * inOutSine(uLeaf);
            var sway = Math.sin(uLeaf * Math.PI * 3.5) * (1 - 0.35 * uLeaf) * 0.65 * px;
            xLeaf = landX + sway;
            tiltLeaf = -15 + 32 * Math.cos(uLeaf * Math.PI * 3.5);
        } else {
            var settleY = 0.04 * px * Math.exp(-6 * tp) * Math.sin(16 * tp);
            var settleRot = 12 + 6 * Math.exp(-5 * tp) * Math.cos(14 * tp);
            xLeaf = landX;
            yLeaf = landY + settleY;
            tiltLeaf = settleRot;
        }

        // Piece 0: The leaf itself (z: 3)
        var LeafShape = place(propShape("calm_leaf"), xLeaf, yLeaf, tiltLeaf, px * 0.72);
        put(0, LeafShape, 1, false, 0.95 * leafFade, 0.035, 3);

        // Piece 1: Air breeze trail stream floating above during drift (z: 2)
        if (tp < 0.1) {
            var Trail = [];
            var trProg = M.clamp(tau / (PROP_D.calm_leaf * 0.6));
            if (trProg > 0.05) {
                var pMidTrail = { x: landX + 0.3 * px * Math.sin(tau * 4), y: (startY + yLeaf) * 0.5 };
                Trail.push(bezier({ x: landX - 0.2 * px, y: startY + 0.2 * px },
                                  pMidTrail, pMidTrail,
                                  { x: xLeaf, y: yLeaf - 0.25 * px }, 16));
            }
            if (Trail.length) put(1, Trail, 1, true, 0.75 * fade(-tp, 0.2), 0.025, 2);
        } else {
            // Soft resting breeze underline under leaf
            var Breeze = [
                [{ x: landX - 0.35 * px, y: landY + 0.05 * px },
                 { x: landX + 0.35 * px, y: landY + 0.05 * px }]
            ];
            put(1, Breeze, 1, true, 0.7 * leafFade, 0.025, 2);
        }

        // Piece 2: Dewdrop & landing sparkle glints (z: 4)
        if (tp >= 0) {
            var Dew = [
                ellipsePts(xLeaf + 0.12 * px, yLeaf - 0.05 * px, 0.06 * px, 0.06 * px, 0, 2 * Math.PI, 12),
                [{ x: xLeaf + 0.10 * px, y: yLeaf - 0.07 * px }, { x: xLeaf + 0.14 * px, y: yLeaf - 0.07 * px }]
            ];
            if (tp < 0.35) {
                Dew.push([
                    { x: xLeaf - 0.18 * px, y: yLeaf - 0.15 * px },
                    { x: xLeaf - 0.06 * px, y: yLeaf - 0.15 * px }
                ]);
                Dew.push([
                    { x: xLeaf - 0.12 * px, y: yLeaf - 0.21 * px },
                    { x: xLeaf - 0.12 * px, y: yLeaf - 0.09 * px }
                ]);
            }
            put(2, Dew, 1, true, 0.9 * leafFade, 0.035, 4);

            // Piece 3: Soft contact shadow along hero word top (z: 1)
            var Shadow = [
                [{ x: landX - 0.28 * px, y: bl - 0.82 * px },
                 { x: landX + 0.28 * px, y: bl - 0.82 * px }]
            ];
            put(3, Shadow, 1, false, 0.65 * leafFade, 0.03, 1);
        }
        break;
    }
    case "droplet": {
        // a drop falls, ripples spread under the word
        var dropFade = fade(tp - sung - 0.45, 0.35);
        var cxDrop = W * 0.5;
        var yTop = bl - 2.6 * px;
        var yLand = bl + 0.05 * px;

        if (tp < 0) {
            var uDrop = M.clamp(tau / PROP_D.droplet);
            var yDrop = yTop + (yLand - yTop) * (uDrop * uDrop);
            var sDropY = px * (0.65 + 0.25 * uDrop);

            // Piece 0: Falling teardrop (z: 3)
            var Drop = place(propShape("droplet"), cxDrop, yDrop, 0, sDropY);
            put(0, Drop, 1, false, 0.95, 0.035, 3);

            // Piece 3: Vertical descent wake streak (z: 2)
            var Wake = [
                [{ x: cxDrop, y: Math.max(yTop, yDrop - 0.45 * px) }, { x: cxDrop, y: yDrop }]
            ];
            put(3, Wake, 1, true, 0.65 * uDrop, 0.025, 2);
        } else {
            // Piece 0: Splash crown & rebound droplet on impact (z: 3)
            if (tp < 0.42) {
                var reboundH = 0.35 * px * Math.exp(-8 * tp) * Math.sin(16 * tp);
                var curRebY = yLand - Math.max(0, reboundH);
                var Splash = [
                    ellipsePts(cxDrop, curRebY, 0.05 * px, 0.07 * px, 0, 2 * Math.PI, 12),
                    [{ x: cxDrop - 0.14 * px, y: yLand }, { x: cxDrop - 0.24 * px, y: yLand - 0.16 * px }],
                    [{ x: cxDrop + 0.14 * px, y: yLand }, { x: cxDrop + 0.24 * px, y: yLand - 0.16 * px }]
                ];
                put(0, Splash, 1, true, fade(tp, 0.42), 0.035, 3);
            }

            // Piece 1: Primary ripple expanding under the word (z: -1, behind the letters)
            var uRip1 = M.clamp(tp / 0.55);
            var rx1 = (0.15 + 1.25 * M.E.outCubic(uRip1)) * px;
            var ry1 = rx1 * 0.26;
            var Rip1 = [ellipsePts(cxDrop, yLand, rx1, ry1, 0, 2 * Math.PI, 28)];
            put(1, Rip1, 1, true, (1 - uRip1 * uRip1) * 0.95 * dropFade, 0.038, -1);

            // Piece 2: Secondary and tertiary ripples lagging behind (z: -1, behind the letters)
            var SubRipples = [];
            var tp2 = tp - 0.08;
            if (tp2 > 0) {
                var uRip2 = M.clamp(tp2 / 0.50);
                var rx2 = (0.12 + 0.95 * M.E.outCubic(uRip2)) * px;
                var ry2 = rx2 * 0.26;
                SubRipples.push(ellipsePts(cxDrop, yLand, rx2, ry2, 0, 2 * Math.PI, 24));
            }
            var tp3 = tp - 0.16;
            if (tp3 > 0) {
                var uRip3 = M.clamp(tp3 / 0.45);
                var rx3 = (0.10 + 0.65 * M.E.outCubic(uRip3)) * px;
                var ry3 = rx3 * 0.26;
                SubRipples.push(ellipsePts(cxDrop, yLand, rx3, ry3, 0, 2 * Math.PI, 20));
            }
            if (SubRipples.length) put(2, SubRipples, 1, false, 0.85 * dropFade, 0.028, -1);

            // Piece 3: Splash flecks scattering upward on impact (z: 4)
            if (tp < 0.28) {
                var Flecks = [];
                for (var fki = 0; fki < 6; fki++) {
                    var fkAng = -Math.PI * 0.85 + fki * (Math.PI * 0.7 / 5) + 0.1 * M.rs(sd, fki, 961);
                    var fkDist = (0.12 + 0.28 * (tp / 0.28)) * px;
                    Flecks.push([
                        { x: cxDrop + 0.05 * px * Math.cos(fkAng), y: yLand + 0.03 * px * Math.sin(fkAng) },
                        { x: cxDrop + fkDist * Math.cos(fkAng), y: yLand + fkDist * Math.sin(fkAng) * 0.8 }
                    ]);
                }
                put(3, Flecks, 1, true, fade(tp, 0.28), 0.032, 4);
            }
        }
        break;
    }
    case "moonrise": {
        // a crescent rises from behind the word and hangs over its upper right, stars come out
        var moonFade = fade(tp - sung - 0.5, 0.4);
        var cxMoon = W * 0.5 + 0.35 * px, startY = bl - 0.2 * px, restY = bl - 1.6 * px;
        var cyMoon, sMoon;
        if (tp < 0) {
            var uMoon = M.clamp(tau / PROP_D.moonrise);
            cyMoon = startY + (restY - startY) * M.E.outCubic(uMoon);
            sMoon = px * (0.9 + 0.25 * uMoon);
        } else {
            cyMoon = restY + 0.03 * px * Math.sin(tp * 3.5);
            sMoon = px * 1.15;
        }
        // Piece 0: the crescent, behind the letters while it climbs past them
        var Moon = place(propShape("moonrise"), cxMoon, cyMoon, -18 + 3 * Math.sin(tp * 2), sMoon);
        put(0, Moon, 1, true, 0.95 * moonFade, 0.04, -1);

        // Piece 2: Night stars & sparkles twinkling around the moon (z: 2)
        if (tp >= -0.2) {
            var starProg = M.clamp((tau - PROP_D.moonrise * 0.6) / (PROP_D.moonrise * 0.4));
            var Stars = [];
            var starCoords = [
                { dx: -0.95, dy: -0.3, sz: 0.11 },
                { dx: 0.85, dy: -0.45, sz: 0.1 },
                { dx: -0.7, dy: 0.35, sz: 0.08 },
                { dx: 0.95, dy: 0.25, sz: 0.08 }
            ];
            for (var sti = 0; sti < starCoords.length; sti++) {
                var sc = starCoords[sti];
                var sx = cxMoon + sc.dx * px;
                var sy = cyMoon + sc.dy * px;
                var tw = (1 + 0.25 * Math.sin(tp * 5 + sti * 1.5)) * sc.sz * px;
                Stars.push([
                    { x: sx - tw, y: sy },
                    { x: sx + tw, y: sy }
                ]);
                Stars.push([
                    { x: sx, y: sy - tw },
                    { x: sx, y: sy + tw }
                ]);
            }
            put(2, Stars, 1, true, 0.9 * starProg * moonFade, 0.03, 2);
        }

        // Piece 3: Soft night cloud wisp drifting across crescent base (z: 2)
        var cloudX = cxMoon - 0.15 * px + 0.12 * px * Math.sin(tp * 2);
        var cloudY = cyMoon + 0.32 * px;
        var CloudWisp = [
            bezier({ x: cloudX - 0.55 * px, y: cloudY },
                   { x: cloudX - 0.18 * px, y: cloudY - 0.06 * px },
                   { x: cloudX + 0.18 * px, y: cloudY + 0.06 * px },
                   { x: cloudX + 0.55 * px, y: cloudY }, 16),
            bezier({ x: cloudX - 0.35 * px, y: cloudY + 0.08 * px },
                   { x: cloudX, y: cloudY + 0.04 * px },
                   { x: cloudX + 0.15 * px, y: cloudY + 0.12 * px },
                   { x: cloudX + 0.38 * px, y: cloudY + 0.06 * px }, 14)
        ];
        put(3, CloudWisp, 1, false, 0.75 * moonFade, 0.028, 2);
        break;
    }
    case "classic_vinyl":
    case "vinyl": {
        // a record rolls in, stops behind the word, spins
        var vinylFade = fade(tp - sung - 0.5, 0.4);
        var landX = W * 0.5;
        var landY = bl - 0.7 * px;
        var startX = -2.6 * px;
        var sDisc = px * 2.1;
        var rDisc = sDisc * 0.48;

        var cxDisc, cyDisc, discRot;
        if (tp < 0) {
            var uDisc = M.clamp(tau / PROP_D.classic_vinyl);
            cxDisc = startX + (landX - startX) * M.E.outCubic(uDisc);
            cyDisc = landY;
            discRot = ((cxDisc - startX) / rDisc) * (180 / Math.PI);
        } else {
            var settleX = 0.03 * px * Math.exp(-6 * tp) * Math.sin(18 * tp);
            cxDisc = landX + settleX;
            cyDisc = landY;
            discRot = ((landX - startX) / rDisc) * (180 / Math.PI) + tp * 360;
        }

        // Piece 0: The vinyl record disc (behind the letters, z: -1)
        var DiscShape = place(propShape("classic_vinyl"), cxDisc, cyDisc, discRot, sDisc);
        put(0, DiscShape, 1, false, 0.7 * vinylFade, 0.035, -1);

        // Piece 1: Rotating groove sheen arcs (z: -1, behind the letters)
        var radRot = discRot * Math.PI / 180;
        var Sheen = [
            ellipsePts(cxDisc, cyDisc, rDisc * 0.75, rDisc * 0.75, radRot - 0.28, radRot + 0.28, 14),
            ellipsePts(cxDisc, cyDisc, rDisc * 0.75, rDisc * 0.75, radRot + Math.PI - 0.28, radRot + Math.PI + 0.28, 14),
            ellipsePts(cxDisc, cyDisc, rDisc * 0.52, rDisc * 0.52, radRot + Math.PI * 0.5 - 0.24, radRot + Math.PI * 0.5 + 0.24, 12),
            ellipsePts(cxDisc, cyDisc, rDisc * 0.52, rDisc * 0.52, radRot - Math.PI * 0.5 - 0.24, radRot - Math.PI * 0.5 + 0.24, 12)
        ];
        put(1, Sheen, 1, true, 0.85 * vinylFade, 0.032, -1);

        // Piece 2: Tonearm swinging in and dropping on the spinning record (z: 2)
        if (tp >= -0.15) {
            var uArm = M.clamp((tp + 0.15) / 0.35);
            var armPivotX = cxDisc + rDisc * 0.92, armPivotY = cyDisc - rDisc * 0.80;
            var armHeadRestX = cxDisc + rDisc * 0.55, armHeadRestY = cyDisc - rDisc * 0.30;
            var armHeadStartX = armPivotX - 0.15 * px, armHeadStartY = armPivotY - 0.40 * px;
            var curHeadX = armHeadStartX + (armHeadRestX - armHeadStartX) * M.E.outBack(uArm, 1.2);
            var curHeadY = armHeadStartY + (armHeadRestY - armHeadStartY) * M.E.outBack(uArm, 1.2);
            var Tonearm = [
                ellipsePts(armPivotX, armPivotY, 0.06 * px, 0.06 * px, 0, 2 * Math.PI, 12),
                [{ x: armPivotX, y: armPivotY }, { x: (armPivotX + curHeadX) * 0.5 + 0.05 * px, y: (armPivotY + curHeadY) * 0.5 - 0.08 * px }, { x: curHeadX, y: curHeadY }],
                [{ x: curHeadX - 0.04 * px, y: curHeadY - 0.02 * px }, { x: curHeadX + 0.04 * px, y: curHeadY + 0.02 * px }],
                [{ x: curHeadX, y: curHeadY }, { x: curHeadX - 0.02 * px, y: curHeadY + 0.06 * px }]
            ];
            put(2, Tonearm, 1, false, 0.90 * vinylFade, 0.035, 2);
        }

        // Piece 3: Groove musical vibes / sparkles floating off spinning disc (z: 3)
        if (tp >= 0) {
            var Vibes = [];
            for (var vi = 0; vi < 5; vi++) {
                var vPhase = tp * 4.5 + vi * 1.3;
                var vDist = (0.35 + 0.45 * Math.sin(vPhase * 0.7)) * rDisc;
                var vAng = radRot * 1.5 + vi * (Math.PI * 2 / 5);
                var vx = cxDisc + vDist * Math.cos(vAng);
                var vy = cyDisc - 0.15 * px - (0.25 * px * (tp / 0.8)) + vDist * 0.3 * Math.sin(vAng);
                var vLen = 0.05 * px;
                Vibes.push([
                    { x: vx - vLen, y: vy },
                    { x: vx + vLen, y: vy }
                ]);
                Vibes.push([
                    { x: vx, y: vy - vLen },
                    { x: vx, y: vy + vLen }
                ]);
            }
            put(3, Vibes, 1, true, 0.85 * fade(tp - sung - 0.2, 0.3), 0.032, 3);
        }
        break;
    }
    case "classic_smoke":
    case "smoke": {
        // three ribbons of smoke curl up off the top of the word, each ending in a little curl,
        // and smoke rings drift up above them; none of it crosses the letters
        var smokeFade = fade(tp - sung - 0.5, 0.4);
        var cxSmoke = W * 0.5, topY = bl - 0.98 * px;
        var growS = M.E.outCubic(M.clamp(tau / PROP_D.classic_smoke));
        var Ribbons = [];
        [[0.28, 0], [0.52, 1], [0.76, 2]].forEach(function (rb) {
            var bxR = W * rb[0], k = rb[1], len = (1.0 + 0.35 * (k % 2)) * px * growS * (0.75 + 0.25 * Math.min(1, Math.max(0, tp + 0.3)));
            if (len < 0.05 * px) return;
            var R = [], ex = 0, ey = 0, last = null;
            for (var j = 0; j <= 18; j++) {
                var u = j / 18, ampR = 0.14 * px * u;
                ex = bxR + ampR * Math.sin(u * 2.4 * Math.PI - t * 3.2 + k * 1.7);
                ey = topY - 0.05 * px - u * len;
                R.push({ x: ex, y: ey });
            }
            // the curl at the top end
            last = R[R.length - 1];
            var dirC = k % 2 ? -1 : 1, rc = 0.11 * px * growS;
            for (var c = 1; c <= 10; c++) {
                var ca = c / 10 * 1.6 * Math.PI, rr = rc * (1 - 0.5 * c / 10);
                R.push({ x: last.x + dirC * (rc - rr * Math.cos(ca)), y: last.y - rr * Math.sin(ca) });
            }
            Ribbons.push(R);
        });
        put(0, Ribbons, 1, false, 0.85 * smokeFade, 0.035, 3);
        // smoke rings, one after another, rising and widening above the ribbons
        if (tp >= 0) {
            var Rings = [];
            for (var ri = 0; ri < 3; ri++) {
                var rtp = tp - ri * 0.22;
                if (rtp <= 0) continue;
                var uRing = M.clamp(rtp / 0.9);
                var rxRing = (0.12 + 0.26 * M.E.outCubic(uRing)) * px;
                Rings.push(ellipsePts(cxSmoke + 0.25 * px * Math.sin(rtp * 2.5 + ri * 2), topY - 1.25 * px - uRing * 0.9 * px,
                                      rxRing, rxRing * 0.4, 0, 2 * Math.PI, 18));
            }
            if (Rings.length) put(1, Rings, 1, true, 0.8 * smokeFade, 0.03, 3);
        }
        break;
    }
    case "horn": {
        // a trumpet slides in from the left, tilted up, its bell just short of the word, and blows:
        // sound arcs open from the bell and notes sail over the top of the word
        var hornFade = fade(tp - sung - 0.45, 0.35);
        var sHorn = px * 1.3, tiltH = -14, hornY = bl - 0.95 * px;
        var targetHornX = -0.32 * px - 0.52 * sHorn, startHornX = -2.6 * px;
        var curHornX;
        if (tp < 0) curHornX = startHornX + (targetHornX - startHornX) * M.E.outBack(M.clamp(tau / PROP_D.horn), 1.4);
        else curHornX = targetHornX - 0.08 * px * Math.exp(-6 * tp) * Math.sin(20 * tp);
        put(0, place(propShape("horn"), curHornX, hornY, tiltH, sHorn), 1, false, 0.95 * hornFade, 0.038, 3);
        if (tp >= 0) {
            var mouth = place([[{ x: 0.56, y: 0 }]], curHornX, hornY, tiltH, sHorn)[0][0];
            var ta = tiltH * Math.PI / 180;
            var Blast = [];
            for (var bi = 0; bi < 3; bi++) {
                var btp = tp - bi * 0.1;
                if (btp <= 0) continue;
                var rBlast = (0.15 + 0.6 * M.E.outCubic(M.clamp(btp / 0.45))) * px;
                Blast.push(ellipsePts(mouth.x, mouth.y, rBlast, rBlast, ta - 0.5, ta + 0.5, 12));
            }
            if (Blast.length) put(1, Blast, 1, true, 0.85 * fade(tp - sung - 0.2, 0.3), 0.034, 3);
            // notes sail out of the bell and over the top of the word
            var Notes = [], lane = Math.min(mouth.y, bl - 1.3 * px);
            for (var ni = 0; ni < 3; ni++) {
                var ntp = tp - ni * 0.12;
                if (ntp <= 0) continue;
                var uN = M.E.outCubic(M.clamp(ntp / 0.8));
                var nx = mouth.x + 0.2 * px + (W + 0.4 * px) * uN * (1 - 0.18 * ni);
                var ny = lane - (0.15 + 0.2 * ni) * px * uN + M.lerp(mouth.y - lane, 0, M.clamp(uN * 3)) + 0.06 * px * Math.sin(ntp * 10 + ni * 2);
                Notes = Notes.concat(place(markShape(ni === 1 ? "notes" : "note", sd + ni, 1, 1).map(function (st) { return st.map(function (q) { return { x: q.x - 0.5, y: q.y - 0.5 }; }); }), nx, ny, -8 + 10 * Math.sin(ntp * 6 + ni), px * 0.42));
            }
            if (Notes.length) put(2, Notes, 1, true, 0.95 * fade(tp - sung - 0.25, 0.35), 0.035, 4);
            var Glint = place([[{ x: -0.1, y: 0 }, { x: 0.1, y: 0 }], [{ x: 0, y: -0.1 }, { x: 0, y: 0.1 }]], mouth.x - 0.05 * px, mouth.y - 0.36 * px, 0, px);
            put(3, Glint, 1, true, 0.9 * fade(tp - 0.25, 0.25), 0.035, 4);
        }
        break;
    }
    case "flash": {
        // an anime glint: a four-point star pops on the word's top right corner and spins,
        // a shine sweeps across behind the letters, small stars wink round the word
        var flashFade = fade(tp - sung - 0.4, 0.35);
        var cxFlash = W + 0.05 * px, cyFlash = bl - 1.15 * px;
        var sFlash, rotFlash;
        if (tp < 0) {
            var uFlash = M.clamp(tau / PROP_D.flash);
            sFlash = px * 0.55 * M.E.outBack(uFlash, 1.6);
            rotFlash = -45 + uFlash * 45;
        } else {
            sFlash = px * (1.1 + 0.4 * Math.exp(-7 * tp) * Math.cos(14 * tp));
            rotFlash = 12 * Math.sin(tp * 3);
        }
        put(0, place(propShape("flash"), cxFlash, cyFlash, rotFlash, sFlash), 1, true, 0.95 * flashFade, 0.04, 3);
        if (tp >= 0) {
            // needles flick out of the star
            var bLen = px * (0.3 + 0.6 * M.E.outCubic(M.clamp(tp / 0.2)));
            var Glints = [];
            for (var gk = 0; gk < 4; gk++) {
                var ga = Math.PI / 4 + gk * Math.PI / 2;
                Glints.push([{ x: cxFlash + 0.35 * px * Math.cos(ga), y: cyFlash + 0.35 * px * Math.sin(ga) },
                             { x: cxFlash + (0.35 * px + bLen) * Math.cos(ga), y: cyFlash + (0.35 * px + bLen) * Math.sin(ga) }]);
            }
            put(1, Glints, 1, false, 0.9 * fade(tp - 0.15, 0.25), 0.03, 3);
            // small stars wink in one after another, clear of the letters
            var Sparkles = [], spots = [[-0.45 * px, bl - 1.05 * px, 0.04], [W * 0.3, bl - 1.5 * px, 0.12], [W + 0.5 * px, bl - 0.2 * px, 0.2]];
            for (var si = 0; si < spots.length; si++) {
                var stp = tp - spots[si][2];
                if (stp <= 0) continue;
                var sS = px * 0.42 * Math.sin(Math.PI * M.clamp(stp / 0.6));
                if (sS > 0.02 * px) Sparkles = Sparkles.concat(place([star4Pts(0.5, 0.12)], spots[si][0], spots[si][1], stp * 90, sS));
            }
            if (Sparkles.length) put(2, Sparkles, 1, true, 0.9 * flashFade, 0.03, 3);
            // the shine: two thin diagonals sweep left to right behind the letters
            var sw = M.clamp(tp / 0.32);
            if (sw < 1) {
                var sx = -0.4 * px + (W + 0.8 * px) * sw;
                put(3, [[{ x: sx, y: bl + 0.15 * px }, { x: sx + 0.5 * px, y: bl - 1.0 * px }],
                        [{ x: sx + 0.22 * px, y: bl + 0.15 * px }, { x: sx + 0.5 * px, y: bl - 0.5 * px }]], 1, true, 0.7 * Math.sin(Math.PI * sw), 0.05, -1);
            }
        }
        break;
    }
    case "focus": {
        // manga focus lines close in from the frame edges
        var focusFade = fade(tp - sung - 0.45, 0.35);
        var cxFocus = W * 0.5;
        var cyFocus = bl - 0.35 * px;

        // Outer radius at frame boundary; inner radius converges toward word
        var rOuter = Math.max(W * 0.9, 3.2 * px);
        var rInnerLand = Math.max(W * 0.52, 0.75 * px);
        var rInnerStart = rOuter * 0.85;

        var curRInner;
        if (tp < 0) {
            var uFocus = M.clamp(tau / PROP_D.focus);
            curRInner = rInnerStart + (rInnerLand - rInnerStart) * M.E.outCubic(uFocus);
        } else {
            // Speed line boil vibration on cue
            var jitter = 0.03 * px * Math.sin(tp * 45);
            curRInner = rInnerLand + jitter;
        }

        // Piece 0: Left-side focus lines converging from left frame (z: 1)
        var LeftLines = [];
        for (var lfi = 0; lfi < 6; lfi++) {
            var lfa = Math.PI * 0.65 + (lfi / 5) * Math.PI * 0.70;
            var lJitter = 0.04 * px * M.rs(sd, lfi, 941);
            var lx0 = cxFocus + (curRInner + lJitter) * Math.cos(lfa);
            var ly0 = cyFocus + (curRInner * 0.65 + lJitter) * Math.sin(lfa);
            var lx1 = cxFocus + (rOuter + lJitter) * Math.cos(lfa);
            var ly1 = cyFocus + (rOuter * 0.65 + lJitter) * Math.sin(lfa);
            LeftLines.push([{ x: lx0, y: ly0 }, { x: lx1, y: ly1 }]);
        }
        put(0, LeftLines, 1, false, 0.90 * focusFade, 0.035, 1);

        // Piece 1: Right-side focus lines converging from right frame (z: 1)
        var RightLines = [];
        for (var rfi = 0; rfi < 6; rfi++) {
            var rfa = -Math.PI * 0.35 + (rfi / 5) * Math.PI * 0.70;
            var rJitter = 0.04 * px * M.rs(sd, rfi, 942);
            var rx0 = cxFocus + (curRInner + rJitter) * Math.cos(rfa);
            var ry0 = cyFocus + (curRInner * 0.65 + rJitter) * Math.sin(rfa);
            var rx1 = cxFocus + (rOuter + rJitter) * Math.cos(rfa);
            var ry1 = cyFocus + (rOuter * 0.65 + rJitter) * Math.sin(rfa);
            RightLines.push([{ x: rx0, y: ry0 }, { x: rx1, y: ry1 }]);
        }
        put(1, RightLines, 1, false, 0.90 * focusFade, 0.035, 1);

        // Piece 2: Top and bottom vertical focus lines (z: 1)
        var VertLines = [];
        for (var vfi = 0; vfi < 4; vfi++) {
            var vfaTop = -Math.PI * 0.75 + (vfi / 3) * Math.PI * 0.50;
            var vfaBot = Math.PI * 0.25 + (vfi / 3) * Math.PI * 0.50;
            VertLines.push([
                { x: cxFocus + curRInner * Math.cos(vfaTop), y: cyFocus + curRInner * 0.65 * Math.sin(vfaTop) },
                { x: cxFocus + rOuter * Math.cos(vfaTop), y: cyFocus + rOuter * 0.65 * Math.sin(vfaTop) }
            ]);
            VertLines.push([
                { x: cxFocus + curRInner * Math.cos(vfaBot), y: cyFocus + curRInner * 0.65 * Math.sin(vfaBot) },
                { x: cxFocus + rOuter * Math.cos(vfaBot), y: cyFocus + rOuter * 0.65 * Math.sin(vfaBot) }
            ]);
        }
        put(2, VertLines, 1, false, 0.85 * focusFade, 0.032, 1);

        // Piece 3: Impact frame corner brackets framing the hero word on cue (z: 2, accent ink)
        if (tp >= 0) {
            var bLenK = 0.18 * px;
            var bw = W * 0.52 + 0.08 * px;
            var bh = 0.45 * px;
            var Brackets = [
                // Top-left corner bracket
                [{ x: cxFocus - bw + bLenK, y: cyFocus - bh }, { x: cxFocus - bw, y: cyFocus - bh }, { x: cxFocus - bw, y: cyFocus - bh + bLenK }],
                // Top-right corner bracket
                [{ x: cxFocus + bw - bLenK, y: cyFocus - bh }, { x: cxFocus + bw, y: cyFocus - bh }, { x: cxFocus + bw, y: cyFocus - bh + bLenK }],
                // Bottom-left corner bracket
                [{ x: cxFocus - bw + bLenK, y: cyFocus + bh }, { x: cxFocus - bw, y: cyFocus + bh }, { x: cxFocus - bw, y: cyFocus + bh - bLenK }],
                // Bottom-right corner bracket
                [{ x: cxFocus + bw - bLenK, y: cyFocus + bh }, { x: cxFocus + bw, y: cyFocus + bh }, { x: cxFocus + bw, y: cyFocus + bh - bLenK }]
            ];
            put(3, Brackets, 1, true, 0.95 * fade(tp - sung - 0.2, 0.3), 0.038, 2);
        }
        break;
    }
    case "sakura": {
        // petals drift across the word
        var sakuraFade = fade(tp - sung - 0.5, 0.4);
        var cxSakura = W * 0.5;
        var cySakura = bl - 0.35 * px;

        // Start at top-left above hero word; drift down and across to lower-right
        var startSakuraX = cxSakura - W * 0.5 - 1.0 * px;
        var startSakuraY = bl - 2.3 * px;
        var landSakuraX = cxSakura + 0.2 * W;
        var landSakuraY = bl - 1.08 * px;

        var mainX, mainY, mainRot;
        if (tp < 0) {
            var uSakura = M.clamp(tau / PROP_D.sakura);
            mainX = startSakuraX + (landSakuraX - startSakuraX) * M.E.outCubic(uSakura) + 0.08 * px * Math.sin(uSakura * Math.PI * 3);
            mainY = startSakuraY + (landSakuraY - startSakuraY) * M.E.outCubic(uSakura);
            mainRot = -30 + uSakura * 75 + 15 * Math.sin(uSakura * Math.PI * 4);
        } else {
            mainX = landSakuraX + 0.06 * px * Math.sin(tp * 3.5);
            mainY = landSakuraY - 0.03 * px * Math.abs(Math.sin(tp * 4));
            mainRot = 45 + tp * 40 + 15 * Math.sin(tp * 4);
        }

        // Piece 0: Main fluttering hero sakura petal (z: 3)
        var MainPetal = place(propShape("sakura"), mainX, mainY, mainRot, px * 0.8);
        put(0, MainPetal, 1, false, 0.95 * sakuraFade, 0.035, 3);

        // Piece 1: Companion swarm of sakura petals drifting at various depths (z: -1, behind the letters)
        var Companions = [];
        var petalConfigs = [
            { offX: -0.9 * px, offY: -0.35 * px, s: 0.6, rotOff: 20, speedX: 0.9, speedY: 0.5, delay: 0.05 },
            { offX: 0.6 * px, offY: -0.6 * px, s: 0.5, rotOff: -35, speedX: 1.1, speedY: 0.45, delay: 0.12 },
            { offX: -0.4 * px, offY: 1.25 * px, s: 0.55, rotOff: 50, speedX: 0.8, speedY: 0.55, delay: 0.18 },
            { offX: W * 0.5 + 0.7 * px, offY: 0.6 * px, s: 0.48, rotOff: -15, speedX: 1.0, speedY: 0.5, delay: 0.08 }
        ];
        for (var pi = 0; pi < petalConfigs.length; pi++) {
            var pcg = petalConfigs[pi];
            var ptp = tp - pcg.delay;
            var ptau = tau - pcg.delay;
            if (ptau > 0) {
                var pxX, pxY, pxRot;
                if (ptp < 0) {
                    var pu = M.clamp(ptau / (PROP_D.sakura * 0.9));
                    pxX = (startSakuraX + pcg.offX) + ((landSakuraX + pcg.offX) - (startSakuraX + pcg.offX)) * M.E.outCubic(pu);
                    pxY = (startSakuraY + pcg.offY) + ((landSakuraY + pcg.offY) - (startSakuraY + pcg.offY)) * M.E.outCubic(pu);
                    pxRot = pcg.rotOff + pu * 60;
                } else {
                    pxX = landSakuraX + pcg.offX + ptp * pcg.speedX * px;
                    pxY = landSakuraY + pcg.offY + ptp * pcg.speedY * px;
                    pxRot = pcg.rotOff + 60 + ptp * 35;
                }
                Companions = Companions.concat(place(propShape("sakura"), pxX, pxY, pxRot, px * pcg.s));
            }
        }
        if (Companions.length) put(1, Companions, 1, false, 0.88 * sakuraFade, 0.03, -1);

        // Piece 2: Gentle wind breeze slipstream trails (z: 2, accent ink)
        var Breeze = [];
        for (var bi = 0; bi < 3; bi++) {
            var bY = bl - 1.75 * px + (bi - 1) * 0.28 * px, bx0 = -0.8 * px + bi * 0.35 * px;
            var bWisp = bezier(
                { x: bx0, y: bY - 0.1 * px },
                { x: bx0 + 0.5 * px, y: bY + 0.08 * px * Math.sin(tp * 3 + bi) },
                { x: bx0 + 1.0 * px, y: bY - 0.08 * px * Math.sin(tp * 3 + bi) },
                { x: bx0 + 1.5 * px, y: bY + 0.1 * px },
                16
            );
            Breeze.push(bWisp);
        }
        put(2, Breeze, 1, true, 0.55 * sakuraFade, 0.026, 2);

        // Piece 3: Floating petal settle & subtle pollen sparkles on the hero word (z: 4)
        if (tp >= 0) {
            var Pollen = [];
            for (var pli = 0; pli < 5; pli++) {
                var plAng = pli * (Math.PI * 2 / 5) + tp * 2;
                var plDist = (0.25 + 0.18 * Math.sin(tp * 3 + pli)) * px;
                var plx = mainX + plDist * Math.cos(plAng);
                var ply = mainY + plDist * Math.sin(plAng);
                var plS = 0.03 * px;
                Pollen.push([
                    { x: plx - plS, y: ply },
                    { x: plx + plS, y: ply }
                ]);
                Pollen.push([
                    { x: plx, y: ply - plS },
                    { x: plx, y: ply + plS }
                ]);
            }
            put(3, Pollen, 1, true, 0.82 * fade(tp - sung - 0.2, 0.3), 0.028, 4);
        }
        break;
    }
    case "sunrise": {
        // the sun rises behind the word, rays open
        var sunriseFade = fade(tp - sung - 0.45, 0.35);
        var cxSun = W * 0.5;

        // Position: rising from below baseline to crest behind the hero word
        var sunStartY = bl + 0.6 * px;
        var sunLandY = bl - 0.3 * px;

        var curSunY, curSunS;
        if (tp < 0) {
            var uSun = M.clamp(tau / PROP_D.sunrise);
            curSunY = sunStartY + (sunLandY - sunStartY) * M.E.outCubic(uSun);
            curSunS = px * (1.4 + 0.6 * M.E.outCubic(uSun));
        } else {
            curSunY = sunLandY + 0.02 * px * Math.sin(tp * 2.5);
            curSunS = px * (2.0 + 0.04 * Math.sin(tp * 3));
        }

        // Piece 0: Sun disc cresting behind the hero word (z: -1, behind the letters)
        var SunShape = place(propShape("sunrise"), cxSun, curSunY, 0, curSunS);
        put(0, SunShape, 1, false, 0.95 * sunriseFade, 0.035, -1);

        // Piece 1: Fan of radiating sunbeams spreading open on cue (z: 1, accent ink)
        if (tp >= 0) {
            var rIn = curSunS * 0.6;
            var rOut = curSunS * (0.62 + 0.3 * M.E.outCubic(M.clamp(tp / 0.25)));
            var Rays = [];
            for (var ri = 0; ri < 7; ri++) {
                var ra = Math.PI * 1.08 + (ri / 6) * Math.PI * 0.84;
                var rx0 = cxSun + rIn * Math.cos(ra), ry0 = curSunY + rIn * Math.sin(ra);
                var rx1 = cxSun + rOut * Math.cos(ra), ry1 = curSunY + rOut * Math.sin(ra);
                Rays.push([{ x: rx0, y: ry0 }, { x: rx1, y: ry1 }]);
            }
            put(1, Rays, 1, true, 0.90 * fade(tp - sung - 0.2, 0.3), 0.035, -1);
        }

        // Piece 2: Horizon line and dawn landscape contour behind word (z: -1, behind the letters)
        var horizY = bl + 0.08 * px;
        var Horizon = [
            [{ x: cxSun - W * 0.5 - 1.1 * px, y: horizY }, { x: cxSun + W * 0.5 + 1.1 * px, y: horizY }],
            bezier(
                { x: cxSun - W * 0.5 - 0.9 * px, y: horizY + 0.16 * px },
                { x: cxSun - 0.3 * W, y: horizY + 0.1 * px },
                { x: cxSun + 0.3 * W, y: horizY + 0.22 * px },
                { x: cxSun + W * 0.5 + 0.9 * px, y: horizY + 0.16 * px },
                16
            )
        ];
        put(2, Horizon, 1, false, 0.88 * sunriseFade, 0.032, -1);

        // Piece 3: Morning solar flare sparkles / dawn glints over the hero word on cue (z: 3, accent ink)
        if (tp >= 0) {
            var DawnGlints = [];
            var gOff = [
                { dx: -W * 0.5 - 0.7 * px, dy: -0.75 * px, phase: 0.03 },
                { dx: W * 0.5 + 0.7 * px, dy: -0.85 * px, phase: 0.07 },
                { dx: 0.0, dy: -2.1 * px, phase: 0.01 }
            ];
            for (var gi = 0; gi < gOff.length; gi++) {
                var go = gOff[gi];
                var gtp = tp - go.phase;
                if (gtp > 0) {
                    var gr = 0.08 * px * (1 - fade(gtp, 0.35));
                    var gx = cxSun + go.dx, gy = curSunY + go.dy;
                    DawnGlints.push([
                        { x: gx - gr, y: gy }, { x: gx + gr, y: gy }
                    ]);
                    DawnGlints.push([
                        { x: gx, y: gy - gr }, { x: gx, y: gy + gr }
                    ]);
                }
            }
            if (DawnGlints.length) put(3, DawnGlints, 1, true, 0.85 * fade(tp - sung - 0.2, 0.3), 0.028, 3);
        }
        break;
    }
    case "flock": {
        // a few birds fly over the word
        var flockFade = fade(tp - sung - 0.45, 0.35);
        var cxFlock = W * 0.5;
        var cyFlock = bl - 1.7 * px;

        var leadX, leadY, leadRot;
        if (tp < 0) {
            var uFlock = M.clamp(tau / PROP_D.flock);
            leadX = (cxFlock - W * 0.5 - 1.2 * px) + (W * 0.5 + 1.2 * px) * M.E.outQuad(uFlock);
            leadY = (cyFlock + 0.35 * px) - 0.35 * px * M.E.outQuad(uFlock) + 0.04 * px * Math.sin(uFlock * Math.PI * 6);
            var flap0 = Math.sin(uFlock * Math.PI * 10);
            leadRot = -10 + 6 * flap0;
        } else {
            leadX = cxFlock + tp * 0.75 * px;
            leadY = cyFlock - tp * 0.15 * px + 0.04 * px * Math.sin(tp * 14);
            var flap1 = Math.sin(tp * 14);
            leadRot = -8 + 6 * flap1;
        }

        // Piece 0: Lead folk bird in flight over the hero word (z: 3)
        var LeadBird = place(propShape("flock"), leadX, leadY, leadRot, px * 0.65);
        put(0, LeadBird, 1, false, 0.95 * flockFade, 0.035, 3);

        // Piece 1: V-formation companion birds (z: 2)
        var Companions = [];
        var cLeft = place(propShape("flock"), leadX - 0.38 * px, leadY + 0.22 * px, leadRot + 4, px * 0.52);
        var cRight = place(propShape("flock"), leadX - 0.42 * px, leadY - 0.18 * px, leadRot - 4, px * 0.48);
        Companions = Companions.concat(cLeft).concat(cRight);
        put(1, Companions, 1, false, 0.90 * flockFade, 0.032, 2);

        // Piece 2: Trailing distance birds (z: 1)
        var DistBirds = [];
        var d1 = place(propShape("flock"), leadX - 0.75 * px, leadY + 0.10 * px, leadRot + 2, px * 0.38);
        var d2 = place(propShape("flock"), leadX - 0.85 * px, leadY - 0.25 * px, leadRot - 3, px * 0.34);
        DistBirds = DistBirds.concat(d1).concat(d2);
        put(2, DistBirds, 1, false, 0.82 * flockFade, 0.026, 3);

        // Piece 3: Flight wind currents and slipstream trails (z: 2, accent ink)
        var Slipstream = [
            bezier(
                { x: leadX - 0.5 * px, y: leadY + 0.04 * px },
                { x: leadX - 0.8 * px, y: leadY + 0.06 * px },
                { x: leadX - 1.1 * px, y: leadY + 0.02 * px },
                { x: leadX - 1.4 * px, y: leadY + 0.05 * px },
                12
            ),
            bezier(
                { x: leadX - 0.6 * px, y: leadY - 0.08 * px },
                { x: leadX - 0.9 * px, y: leadY - 0.06 * px },
                { x: leadX - 1.2 * px, y: leadY - 0.10 * px },
                { x: leadX - 1.5 * px, y: leadY - 0.07 * px },
                12
            )
        ];
        put(3, Slipstream, 1, true, 0.80 * flockFade, 0.026, 2);
        break;
    }
    case "folk_sprout":
    case "sprout": {
        // a shoot grows out of the word top and opens two leaves
        var sproutFade = fade(tp - sung - 0.45, 0.35);
        var cxSprout = W * 0.5;
        var topY = bl - 0.82 * px;

        var curStemH, tipY, leavesOpen;
        if (tp < 0) {
            var uSprout = M.clamp(tau / PROP_D.folk_sprout);
            curStemH = (0.55 * px) * M.E.outCubic(uSprout);
            tipY = topY - curStemH;
            leavesOpen = 0;
        } else {
            curStemH = 0.55 * px;
            tipY = topY - curStemH;
            leavesOpen = M.E.outBack(M.clamp(tp / 0.22), 2.2);
        }

        // Piece 0: Shoot stem growing upward from hero word top (z: 2)
        var ShootStem = [
            [
                { x: cxSprout, y: topY },
                { x: cxSprout - 0.03 * px, y: topY - curStemH * 0.5 },
                { x: cxSprout + 0.02 * px, y: tipY }
            ]
        ];
        put(0, ShootStem, 1, false, 0.95 * sproutFade, 0.036, 2);

        // Piece 1: Two opening cotyledon leaves unfurling on cue (z: 3, accent ink)
        if (tp >= 0 && leavesOpen > 0.01) {
            var lSize = px * 0.42 * Math.min(1.0, leavesOpen);
            var lRot = 35 * leavesOpen;
            var Leaves = [];
            // Left leaf
            var LeftLeaf = [
                { x: cxSprout, y: tipY },
                { x: cxSprout - lSize * 0.65, y: tipY - lSize * 0.25 },
                { x: cxSprout - lSize * 1.15, y: tipY - lSize * 0.65 * (lRot / 35) },
                { x: cxSprout - lSize * 0.85, y: tipY + lSize * 0.10 },
                { x: cxSprout, y: tipY }
            ];
            // Right leaf
            var RightLeaf = [
                { x: cxSprout, y: tipY },
                { x: cxSprout + lSize * 0.65, y: tipY - lSize * 0.25 },
                { x: cxSprout + lSize * 1.15, y: tipY - lSize * 0.65 * (lRot / 35) },
                { x: cxSprout + lSize * 0.85, y: tipY + lSize * 0.10 },
                { x: cxSprout, y: tipY }
            ];
            // Central bud tip
            var Bud = [
                { x: cxSprout, y: tipY },
                { x: cxSprout, y: tipY - 0.12 * px * Math.min(1.0, leavesOpen) }
            ];
            Leaves.push(LeftLeaf);
            Leaves.push(RightLeaf);
            Leaves.push(Bud);
            put(1, Leaves, 1, true, 0.95 * sproutFade, 0.035, 3);
        }

        // Piece 2: Dewdrop sparkles and morning pollen on cue (z: 4, accent ink)
        if (tp >= 0) {
            var Dewdrops = [];
            var dOff = [
                { dx: -0.42 * px, dy: -0.22 * px, phase: 0.04 },
                { dx: 0.42 * px, dy: -0.22 * px, phase: 0.06 },
                { dx: 0.0, dy: -0.15 * px, phase: 0.02 }
            ];
            for (var di = 0; di < dOff.length; di++) {
                var dof = dOff[di];
                var dtp = tp - dof.phase;
                if (dtp > 0) {
                    var dr = 0.04 * px * (1 - fade(dtp, 0.35));
                    var dx = cxSprout + dof.dx, dy = tipY + dof.dy;
                    Dewdrops.push(ellipsePts(dx, dy, dr, dr, 0, 2 * Math.PI, 10));
                    Dewdrops.push([{ x: dx - dr * 1.5, y: dy }, { x: dx + dr * 1.5, y: dy }]);
                }
            }
            if (Dewdrops.length) put(2, Dewdrops, 1, true, 0.88 * fade(tp - sung - 0.2, 0.3), 0.028, 4);
        }

        // Piece 3: Seedling base anchor mound on hero word top (z: 2)
        var BaseAnchor = [
            [{ x: cxSprout - 0.18 * px, y: topY }, { x: cxSprout + 0.18 * px, y: topY }],
            [{ x: cxSprout - 0.12 * px, y: topY - 0.04 * px }, { x: cxSprout, y: topY }, { x: cxSprout + 0.12 * px, y: topY - 0.04 * px }]
        ];
        put(3, BaseAnchor, 1, false, 0.88 * sproutFade, 0.032, 2);
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
    } else if (L.pile.fx === "rip") {
        var sp = ripSplit(L, t);
        if (sp > 0.001) {
            var left = (nc > 1 ? ci < Math.ceil(nc / 2) : true);
            var dir = left ? -1 : 1;
            st.dx += dir * 0.18 * sp;
            st.dy += dir * 0.16 * sp;
            st.rot += dir * 3.0 * sp;
        }
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
