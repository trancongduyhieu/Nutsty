// Unit tests for components/lyrics_offset_logic.js (per-song lyrics offset, liner style):
//   node scripts/test_lyrics_offset_logic.cjs
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const src = fs.readFileSync(__dirname + '/../components/lyrics_offset_logic.js', 'utf8').replace(/^\.pragma.*$/m, '');
const L = vm.createContext({});
vm.runInContext(src, L);

// Badge text: one decimal on whole tenths, two otherwise, explicit sign when positive
assert.strictEqual(L.formatBadge(0), '0.0s');
assert.strictEqual(L.formatBadge(100), '+0.1s');
assert.strictEqual(L.formatBadge(-1500), '-1.5s');
assert.strictEqual(L.formatBadge(250), '+0.25s');
assert.strictEqual(L.formatBadge(-50), '-0.05s');

// Clamped to +-60 s and whole milliseconds
assert.strictEqual(L.clampMs(90000), 60000);
assert.strictEqual(L.clampMs(-90000), -60000);
assert.strictEqual(L.clampMs(12.6), 13);
assert.strictEqual(L.clampMs(NaN), 0);

// Song key: video id first, else title|artist lowercased, "" with nothing to key on
assert.strictEqual(L.trackKey({ videoId: 'abc', title: 'X' }), 'yt:abc');
assert.strictEqual(L.trackKey({ path: 'ytdl://zzz' }), 'yt:zzz');
assert.strictEqual(L.trackKey({ title: 'Song ', artist: 'Me' }), 't:song|me');
assert.strictEqual(L.trackKey(null), '');
assert.strictEqual(L.trackKey({}), '');

// Positive offset shows lyrics later: the lyric clock runs behind the song
assert.strictEqual(L.lyricTime(10, 500), 9.5);
assert.strictEqual(L.lyricTime(10, -1000), 11);
assert.strictEqual(L.lyricTime(10, 0), 10);

// Store: new map each time (QML var bindings only fire on reassignment), 0 removes the entry
let m = {};
const m1 = L.withOffset(m, 'yt:a', 300);
assert.notStrictEqual(m1, m);
assert.strictEqual(m1['yt:a'], 300);
assert.strictEqual(L.offsetFor(m1, 'yt:a'), 300);
assert.strictEqual(L.offsetFor(m1, 'yt:b'), 0);
assert.strictEqual(L.offsetFor(null, 'yt:a'), 0);
const m2 = L.withOffset(m1, 'yt:a', 0);
assert.ok(!('yt:a' in m2));
assert.strictEqual(L.withOffset(m1, '', 100), m1);          // nothing to key on: unchanged
// Capped: the oldest entries go first so settings never grow without bound
let big = {};
for (let i = 0; i < L.MAX_ENTRIES + 5; ++i) big = L.withOffset(big, 'k' + i, 100);
assert.strictEqual(Object.keys(big).length, L.MAX_ENTRIES);
assert.ok(!('k0' in big) && ('k' + (L.MAX_ENTRIES + 4)) in big);
// Re-setting a song moves it to the newest end
big = L.withOffset(big, 'k5', 200);
big = L.withOffset(big, 'new', 100);
assert.ok('k5' in big && !('k6' in big));

console.log('lyrics_offset_logic: OK');
