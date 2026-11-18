// Unit tests for components/kinetic_stage.js (desktop lyrics presets 7 and 8), run with Node:
//   node scripts/test_kinetic_stage.cjs
const fs = require('fs');
const vm = require('vm');
const assert = require('assert');

const dir = __dirname + '/../components/';
function load(file, ctx) {
    const src = fs.readFileSync(dir + file, 'utf8').replace(/^\.pragma.*$/m, '').replace(/^\.import.*$/m, '');
    vm.runInContext(src, ctx);
}
const M = vm.createContext({});
load('motion_recipes.js', M);
const K = vm.createContext({ M: M });
load('kinetic_stage.js', K);
const D = vm.createContext({});
load('lyrics_demo.js', D);
const demo = vm.runInContext('build()', D);

// [[time, text], ...] -> lyrics entries (line-synced, words spread by M.wordsOf)
function song(rows) { return rows.map(r => ({ time: r[0], text: r[1] })); }
const FAST = ["chạy đi chạy mãi không ngừng nghỉ ngơi một chút thôi",
              "từng con phố cũ vẫn chờ mình quay về nơi đây",
              "đếm từng ngày trôi qua thật nhanh như một giấc mơ",
              "tay trong tay mình bước qua bao nhiêu là mùa mưa"];
function pileOf(m, text) {
    return m.piles.find(P => P.lines.some(L => L.words.map(w => w.text).join(" ") === text));
}

const tests = [];
function test(name, fn) { tests.push([name, fn]); }

test("peak after fast", () => {
    const ly = song([[0, FAST[0]], [1.6, FAST[1]], [3.2, FAST[2]], [4.8, FAST[3]], [6.4, "em vẫn ở đây"], [9.9, FAST[0]], [11.5, FAST[1]]]);
    const P = pileOf(K.build(ly, { max: true }), "em vẫn ở đây");
    assert.strictEqual(P.role, "peak");
    assert.strictEqual(P.lines.length, 1);
});

test("rush", () => {
    const mid = "ngày mai nắng lên rồi";
    const fast = "nói đi nói đi nói đi em ơi đừng im lặng mãi như thế nữa mà anh chờ";
    const rows = [];
    let t = 0;
    for (let i = 0; i < 6; i++) { rows.push([t, mid]); t += 2.5; }
    rows.push([t, fast]); t += 2;
    for (let i = 0; i < 3; i++) { rows.push([t, mid]); t += 2.5; }
    let m = K.build(song(rows), { max: true });
    let P = pileOf(m, fast);
    assert.strictEqual(P.role, "rush");
    assert.strictEqual(P.lines.length, 1);
    // two fast lines in a row: the second is not a rush
    const fast2 = "chạy đi chạy đi chạy đi em ơi đừng dừng lại nữa mà anh vẫn còn đây";
    rows.splice(7, 0, [13.8, fast2]);
    rows.forEach((r, i) => { if (i > 7) r[0] += 2; });
    m = K.build(song(rows), { max: true });
    assert.strictEqual(pileOf(m, fast).role, "rush");
    assert.notStrictEqual(pileOf(m, fast2).role, "rush");
});

test("rap cap", () => {
    const rows = [];
    for (let i = 0; i < 20; i++)
        rows.push([i * 2, FAST[i % 4] + (i % 3 ? " nữa" : "") + (i % 5 ? "" : " đi đi đi")]);
    const m = K.build(song(rows), { max: true });
    const rush = m.piles.filter(P => P.role === "rush").length;
    assert.ok(rush <= m.piles.length * 0.25, rush + " of " + m.piles.length + " piles are rush");
});

test("no letters", () => {
    const ly = song([[0, FAST[0]], [1.6, FAST[1]], [3.2, "♪"], [6, "..."], [9, FAST[2]], [10.6, FAST[3]]]);
    const m = K.build(ly, { max: true });
    m.lines.forEach(L => assert.ok(isFinite(K.rateOf(L)), "rate not finite"));
    m.lines.filter(L => /^[♪.]+$/.test(L.words.map(w => w.text).join(""))).forEach(L =>
        assert.ok(L.pile.role !== "peak" && L.pile.role !== "rush", "a letterless line got " + L.pile.role));
});

test("short songs", () => {
    for (const ly of [song([[0, "em vẫn ở đây"]]), song([[0, FAST[0]], [1.6, "em vẫn ở đây"]])]) {
        const m = K.build(ly, { max: true });
        assert.ok(m.piles.every(P => P.role !== "peak"));
    }
});

test("no random solo in max", () => {
    const rows = [];
    for (let i = 0; i < 12; i++) rows.push([i * 2.2, ["ngày mai nắng lên rồi", "mình đi qua phố nhỏ", "em ơi đừng khóc nữa"][i % 3]]);
    const m = K.build(song(rows), { max: true });
    m.piles.forEach(P => {
        assert.ok(P.role !== "peak" && P.role !== "rush", "unexpected " + P.role);
        assert.strictEqual(P.role, P.lines.length === 2 ? "duo" : "stack");
    });
});

test("preset 7 unchanged", () => {
    const m = K.build(demo, {});
    m.piles.forEach(P => {
        assert.strictEqual(P.solo, M.r(P.lines[0].seed, 20, 420) < 0.35);
        assert.strictEqual(P.role, undefined);
    });
});

// A long song: runs of fast lines, a slow line after them, medium lines, and a very fast line
const MID = ["ngày mai nắng lên rồi", "mình đi qua phố nhỏ", "em ơi đừng khóc nữa", "gió vẫn thổi bên thềm"];
const SLOW = ["em vẫn ở đây", "đừng đi xa", "mãi mãi thôi", "nhớ không em", "về với nhau"];
const RUSH = "nói đi nói đi nói đi em ơi đừng im lặng mãi như thế nữa mà anh chờ";
function longSong() {
    const rows = [];
    let t = 0;
    for (let b = 0; b < 5; b++) {
        for (let i = 0; i < 3; i++) { rows.push([t, FAST[(b + i) % 4]]); t += 1.6; }
        rows.push([t, SLOW[b]]); t += 3.5;
        for (let i = 0; i < 4; i++) { rows.push([t, MID[(b + i) % 4]]); t += 2.5; }
        rows.push([t, RUSH]); t += 2;
        for (let i = 0; i < 3; i++) { rows.push([t, MID[(b + i + 1) % 4]]); t += 2.5; }
    }
    return song(rows);
}

test("fx never repeats per role", () => {
    const m = K.build(longSong(), { max: true });
    const pools = { peak: K.PEAK_FX, duo: K.DUO_FX, stack: K.STACK_FX };
    const last = {};
    const seen = {};
    m.piles.forEach(P => {
        seen[P.role] = (seen[P.role] || 0) + 1;
        if (P.role === "rush") { assert.strictEqual(P.fx, ""); return; }
        assert.ok(pools[P.role].indexOf(P.fx) >= 0, P.role + " fx " + P.fx);
        assert.notStrictEqual(P.fx, last[P.role], P.role + " repeated " + P.fx);
        last[P.role] = P.fx;
    });
    assert.ok(seen.peak >= 3 && seen.rush >= 3 && seen.stack >= 3, JSON.stringify(seen));
});

test("pile doodle cap", () => {
    const m = K.build(longSong(), { max: true });
    m.piles.filter(P => P.role === "duo" || P.role === "stack").forEach(P => {
        const n = P.lines.reduce((a, L) => a + L.doodles.length, 0);
        assert.ok(n <= K.PILE_DOODLES, n + " doodles in a " + P.role);
    });
});

test("rush dressing", () => {
    const m = K.build(longSong(), { max: true });
    const L = m.piles.find(P => P.role === "rush").lines[0];
    const n = Math.min(K.RUSH_DOODLES, L.mainIdx.length);
    assert.strictEqual(L.doodles.length, n + 2);
    const sides = L.doodles.slice(n);
    assert.ok(sides.every(d => d.kind === "speed"));
    assert.strictEqual(sides.map(d => d.spot).sort().join(","), "left,right");
    L.doodles.slice(0, n).forEach((d, k) => {
        assert.ok(d.spot === "above" || d.spot === "below");
        assert.ok(Math.abs(d.at - (L.words[L.mainIdx[k]].start - K.LEAD)) < 1e-9);
    });
    assert.strictEqual(Object.keys(L.wordMarks).length, L.mainIdx.length);
    assert.strictEqual(L.boil, 12);
    assert.strictEqual(L.lineMark, "rushline");
});

test("peak dressing and fallback", () => {
    const m = K.build(longSong(), { max: true });
    m.piles.filter(P => P.role === "peak").forEach(P => {
        const L = P.lines[0];
        assert.strictEqual(L.doodles.length, 0);
        assert.strictEqual(L.lineMark, "");
        assert.strictEqual(L.hiWi, -1);
        assert.strictEqual(P.frameX, 0);
        assert.ok(L.heroWi >= 0);
    });
    // a peak whose words are all hidden under the redaction bar has no hero to light
    const rows = [[0, FAST[0]], [1.6, FAST[1]], [3.2, FAST[2]], [4.8, FAST[3]], [6.4, "fuck fuck fuck"], [9.9, FAST[0]], [11.5, FAST[1]]];
    const P = pileOf(K.build(song(rows), { max: true }), "fuck fuck fuck");
    assert.strictEqual(P.role, "peak");
    assert.strictEqual(P.fx, "ink");
});

let failed = 0;
for (const [name, fn] of tests) {
    try { fn(); console.log("ok " + name); }
    catch (e) { failed++; console.log("FAIL " + name + ": " + e.message); }
}
console.log((tests.length - failed) + "/" + tests.length + " passed");
process.exit(failed ? 1 : 0);
