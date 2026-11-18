.pragma library

// Built-in demo song for the desktop lyrics preset previews, used when nothing is playing.
// The lines are Nutsty's own placeholder words, written to a mid-80s dance-pop pulse
// (about 114 BPM); no real lyrics are bundled.
var LINES = [
    "Lights go down and the city starts to move",
    "Every step is louder than the last",
    "Turn it up, there is nothing left to prove",
    "Shake the floor and leave it in the past",
    "Hands up high, the bass is coming through",
    "One more time, I am calling out to you"
];

var LEAD_IN = 0.6;      // seconds before the first line
var LINE_SPAN = 3.15;   // one line every ~1.5 bars
var SING_SHARE = 0.82;  // the rest of each span is a breath before the next line

// Spread a line's words over its sung part, longer words taking longer; the last one is held
function timedWords(text, start, sung) {
    var parts = text.split(" ");
    var weights = parts.map(function (w) { return 0.6 + w.length; });
    var total = weights.reduce(function (a, b) { return a + b; }, 0);
    var t = start;
    var out = [];
    for (var i = 0; i < parts.length; i++) {
        var d = sung * weights[i] / total;
        if (i === parts.length - 1) d = Math.max(d, 0.9);
        out.push({ text: parts[i], start: t, end: t + d, duration: d, hasSpace: i < parts.length - 1, isHeld: d >= 0.85 });
        t += d;
    }
    return out;
}

function build() {
    var lyrics = [];
    for (var i = 0; i < LINES.length; i++) {
        var start = LEAD_IN + i * LINE_SPAN;
        lyrics.push({
            time: start,
            endTime: start + LINE_SPAN,
            text: LINES[i],
            hasWords: true,
            isSynthetic: false,
            words: timedWords(LINES[i], start, LINE_SPAN * SING_SHARE)
        });
    }
    return lyrics;
}

// One full pass, then the clock wraps to 0
var DURATION = LEAD_IN + LINES.length * LINE_SPAN + 0.8;
