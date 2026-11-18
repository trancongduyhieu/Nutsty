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

// A built long song with its first peak forced to one fx (the runtime reads P.fx each frame)
function peakWith(fx) {
    const m = K.build(longSong(), { max: true });
    const P = m.piles.find(P => P.role === "peak");
    P.fx = fx;
    return { m: m, P: P, L: P.lines[0] };
}
function finiteDeep(o, where) {
    if (typeof o === "number") { assert.ok(isFinite(o), "non-finite number in " + where); return; }
    if (o && typeof o === "object") for (const k in o) finiteDeep(o[k], where + "." + k);
}

test("bulb springs", () => {
    const { L } = peakWith("bulb");
    const at = tau => K.peakState(L, L.enterAt + tau);
    assert.ok(at(0).bulbY < -4, "starts high: " + at(0).bulbY);
    let over = false;
    for (let tau = 0.01; tau < 0.6; tau += 0.01) if (at(tau).bulbY > 0) over = true;
    assert.ok(over, "never overshoots its rest");
    assert.ok(Math.abs(at(1.5).bulbY) < 0.05 && Math.abs(at(1.5).bulbTilt) < 0.5, "not settled");
});

test("bulb lights on cue", () => {
    const { L } = peakWith("bulb");
    const on = K.peakOnAt(L);
    assert.strictEqual(K.peakState(L, on - 0.05).on, false);
    assert.ok(K.peakState(L, on - 0.05).dark <= 0.25 + 1e-9);
    const s = K.peakState(L, on + 0.2);
    assert.strictEqual(s.on, true);
    assert.ok(s.cone > 0.9);
    assert.strictEqual(s.dark, 1);
});

test("spot dims the rest", () => {
    const { L } = peakWith("spot");
    const t = K.peakOnAt(L) + Math.max(0.3, L.words[L.heroWi].end - L.words[L.heroWi].start) + 0.5;
    const other = L.mainIdx.find(wi => wi !== L.heroWi);
    assert.ok(K.wordFx(L, t, other).alpha <= 0.31, "rest alpha " + K.wordFx(L, t, other).alpha);
    assert.ok(K.wordFx(L, t, L.heroWi).s >= 1.45, "hero scale " + K.wordFx(L, t, L.heroWi).s);
});

test("peak parts follow the fx", () => {
    const parts = ["bulb", "cord", "glow", "rays", "ring", "stamp", "ink"];
    const uses = { bulb: ["bulb", "cord", "glow"], spot: ["ring"], rays: ["rays"], ink: ["ink"], stamp: ["stamp"] };
    for (const fx of K.PEAK_FX) {
        const { L } = peakWith(fx);
        const t = L.end + 0.2;
        for (const part of parts) {
            const n = K.peakStrokes(L, t, part, 300, 200).length;
            if (uses[fx].indexOf(part) >= 0) assert.ok(n > 0, fx + " draws no " + part);
            else assert.strictEqual(n, 0, fx + " draws " + part);
        }
    }
});

test("non-peak lines untouched", () => {
    const m = K.build(longSong(), { max: true });
    const L = m.piles.find(P => P.role === "stack" || P.role === "duo").lines[0];
    for (let t = L.enterAt; t < L.end + 1; t += 0.1) {
        const s = K.peakState(L, t);
        assert.ok(s.lit === 1 && s.dark === 1 && s.heroS === 1 && s.restA === 1 && s.cone === 0);
        for (const part of ["bulb", "cord", "glow", "rays", "ring", "stamp", "ink"])
            assert.strictEqual(K.peakStrokes(L, t, part, 300, 200).length, 0);
    }
});

test("rush word marks", () => {
    const m = K.build(longSong(), { max: true });
    const L = m.piles.find(P => P.role === "rush").lines[0];
    const wi = L.mainIdx.find(i => i !== L.ringWi);
    const land = L.words[wi].start - K.LEAD;
    assert.ok(["tick", "ring"].indexOf(K.wordMarkKind(L, wi)) >= 0);
    assert.strictEqual(K.wordStrokes(L, land - 0.05, wi, 120, 60).length, 0);
    assert.ok(K.wordStrokes(L, land + 0.2, wi, 120, 60).length > 0);
    // a duo keeps the old hero mark on its hero and nothing elsewhere
    const D = m.piles.find(P => P.role === "duo" || P.role === "stack").lines.find(L => L.ringWi >= 0);
    assert.strictEqual(K.wordMarkKind(D, D.ringWi), D.heroMark);
    D.mainIdx.filter(i => i !== D.ringWi).forEach(i => assert.strictEqual(K.wordMarkKind(D, i), ""));
});

test("rush line mark draws", () => { const m=K.build(longSong(),{max:true}); const R=m.piles.find(P=>P.role==="rush").lines[0];
  assert.strictEqual(R.lineMark,"rushline");
  const S=K.penStrokes(R,R.end,"line",400,40); assert.ok(S.length>=2, "zigzag and under stroke"); });
test("rush boils faster", () => {
    const m = K.build(longSong(), { max: true });
    const R = m.piles.find(P => P.role === "rush").lines[0];
    const wi = R.mainIdx[0];
    const t0 = Math.ceil((R.end + 0.3) * 12) / 12 + 0.001;
    assert.notStrictEqual(JSON.stringify(K.wordStrokes(R, t0, wi, 120, 60)), JSON.stringify(K.wordStrokes(R, t0 + 1 / 12, wi, 120, 60)));
    const N = m.piles.find(P => P.role === "stack").lines.find(L => L.lineMark);
    const t1 = Math.ceil((N.end + 1) * 8) / 8 + 0.01;
    assert.strictEqual(JSON.stringify(K.penStrokes(N, t1, "line", 400, 40)), JSON.stringify(K.penStrokes(N, t1 + 0.05, "line", 400, 40)));
});

// A duo (2 lines) or stack (3 lines) pile from longSong with its fx forced
function pileWith(n, fx) {
    const m = K.build(longSong(), { max: true });
    const P = m.piles.find(P => (P.role === "duo" || P.role === "stack") && P.lines.length === n);
    P.fx = fx;
    if (P.role === "duo") K.dressDuo(P);
    return P;
}
const PW = 1000, PH = 300, PA = 0.64 * PH;
function inFrame(S, where) {
    S.forEach(st => st.forEach(p => {
        assert.ok(p.x >= -0.1 * PW && p.x <= 1.1 * PW && p.y >= -0.1 * PH && p.y <= 1.1 * PH,
                  where + " point out of frame: " + p.x.toFixed(1) + "," + p.y.toFixed(1));
    }));
}
test("duo pile marks", () => {
    for (const fx of K.DUO_FX) {
        const P = pileWith(2, fx), L1 = P.lines[1];
        assert.strictEqual(K.pileStrokes(P, L1.enterAt - 0.01, PW, PH, PA).length, 0, fx + " before line 2");
        const t = Math.min(L1.end, P.exitAt - 0.01);
        const S = K.pileStrokes(P, t, PW, PH, PA);
        assert.ok(S.length > 0, fx + " after line 2");
        inFrame(S, fx);
        assert.strictEqual(K.pileState(P, t, PW, PH, PA).rects.length, 2);
        assert.strictEqual(K.pileState(P, L1.enterAt - 0.01, PW, PH, PA).rects.length, 1);
    }
});
test("duo versus and pair", () => {
    let P = pileWith(2, "versus"); const t = Math.min(P.lines[1].end, P.exitAt - 0.01);
    assert.ok(K.lineState(P.lines[0], t, PW).dx < -0.05 * PW && K.lineState(P.lines[1], t, PW).dx > 0.05 * PW);
    P = pileWith(2, "pair");
    P.lines.filter(L => L.heroOk).forEach(L => { assert.strictEqual(L.heroMark, "ring"); assert.strictEqual(L.ringWi, L.heroWi); });
});
test("stack pile marks", () => {
    for (const fx of K.STACK_FX) {
        const P = pileWith(3, fx), L0 = P.lines[0], L2 = P.lines[2];
        assert.strictEqual(K.pileStrokes(P, L0.enterAt - 0.01, PW, PH, PA).length, 0, fx + " before line 1");
        const t = Math.min(L2.end, P.exitAt - 0.01);
        const S = K.pileStrokes(P, t, PW, PH, PA);
        assert.ok(S.length > 0, fx + " after line 3");
        inFrame(S, fx);
        assert.strictEqual(K.pileState(P, t, PW, PH, PA).rects.length, 3);
    }
});
test("pile rects use measured widths", () => {
    const P = pileWith(2, "brace"), t = Math.min(P.lines[1].end, P.exitAt - 0.01);
    const est = K.pileState(P, t, PW, PH, PA).rects, got = K.pileState(P, t, PW, PH, PA, [200, 300]).rects;
    const s1 = K.lineState(P.lines[1], t, PW);
    assert.ok(Math.abs(got[1].w - 300 * s1.s * Math.min(s1.fit, PW * K.roomOf(P.lines[1]) / 300)) < 0.01);
    assert.ok(Math.abs(got[0].w - est[0].w) > 1);
    assert.strictEqual(K.pileState(P, t, PW, PH, PA, [0, 0]).rects[1].w, est[1].w);
});
test("solo piles carry no pile marks", () => {
    const m = K.build(longSong(), { max: true });
    m.piles.filter(P => P.role === "peak" || P.role === "rush" || P.lines.length < 2)
        .forEach(P => assert.strictEqual(K.pileStrokes(P, P.lines[0].end, PW, PH, PA).length, 0));
});

test("NaN sweep", () => {
    for (const max of [false, true]) {
        const m = K.build(longSong().concat(demo.map(e => Object.assign({}, e, { time: (e.time !== undefined ? e.time : 0) + 200 }))), { max: max });
        for (let t = 0; t < 230; t += 0.05) {
            finiteDeep(K.film(m, t), "film");
            for (const li of K.visibleAt(m.lines, t)) {
                const L = m.lines[li];
                finiteDeep(K.lineState(L, t, 880), "lineState");
                finiteDeep(K.camera(L, t, 880, 300), "camera");
                finiteDeep(K.peakState(L, t), "peakState");
                for (const part of ["bulb", "cord", "glow", "rays", "ring", "stamp", "ink"]) finiteDeep(K.peakStrokes(L, t, part, 300, 200), part);
                for (const role of ["line", "hero", "hilite", "exit"]) finiteDeep(K.penStrokes(L, t, role, 400, 40), role);
                L.words.forEach((w, wi) => {
                    finiteDeep(K.wordFx(L, t, wi), "wordFx");
                    finiteDeep(K.wordStrokes(L, t, wi, 120, 60), "wordStrokes");
                    w.chars.forEach((c, ci) => finiteDeep(K.letterState(L, t, wi, ci), "letterState"));
                });
            }
        }
    }
});

let failed = 0;
for (const [name, fn] of tests) {
    try { fn(); console.log("ok " + name); }
    catch (e) { failed++; console.log("FAIL " + name + ": " + e.message); }
}
console.log((tests.length - failed) + "/" + tests.length + " passed");
process.exit(failed ? 1 : 0);
