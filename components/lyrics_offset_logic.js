.pragma library
// Per-song lyrics offset (liner's "Lyrics offset"): negative shows lyrics earlier, positive later.
// Pure helpers, no access to `win`, so Node tests load this file as is
// (scripts/test_lyrics_offset_logic.cjs).

var MAX_MS = 60000;
var MAX_ENTRIES = 300;   // songs remembered in settings; the oldest is dropped first

function clampMs(ms) {
    var v = Math.round(Number(ms));
    if (!isFinite(v)) return 0;
    return Math.max(-MAX_MS, Math.min(MAX_MS, v));
}

// "0.0s", "+0.1s", "-1.5s", "+0.25s"
function formatBadge(ms) {
    var v = clampMs(ms);
    if (v === 0) return "0.0s";
    var sign = v > 0 ? "+" : "";
    return sign + (v / 1000).toFixed(Math.abs(v) % 100 === 0 ? 1 : 2) + "s";
}

// Stable key for a song: the YouTube id when there is one, else title|artist
function trackKey(track) {
    if (!track) return "";
    var vid = track.videoId || "";
    if (!vid && track.path && String(track.path).indexOf("ytdl://") === 0) vid = String(track.path).substring(7);
    if (vid) return "yt:" + vid;
    var title = String(track.title || track.name || "").trim().toLowerCase();
    if (!title) return "";
    return "t:" + title + "|" + String(track.artist || "").trim().toLowerCase();
}

// The clock lyrics follow: a positive offset makes them run behind the song
function lyricTime(seconds, offsetMs) {
    return seconds - (offsetMs || 0) / 1000;
}

function offsetFor(map, key) {
    if (!map || !key) return 0;
    var v = map[key];
    return typeof v === "number" ? v : 0;
}

// A new map with `key` set (0 removes it), newest last, capped at MAX_ENTRIES
function withOffset(map, key, ms) {
    if (!key) return map;
    var out = {}, k;
    for (k in (map || {})) if (k !== key) out[k] = map[k];
    var v = clampMs(ms);
    if (v !== 0) out[key] = v;
    var keys = Object.keys(out);
    for (var i = 0; i < keys.length - MAX_ENTRIES; ++i) delete out[keys[i]];
    return out;
}
