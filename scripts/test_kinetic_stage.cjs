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
    for (const fx of K.PROP_FX) uses[fx] = [];
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


// The prop moves: pieces drawn in the hero word's own box (W x px, baseline bl)
const PW_ = 160, PX = 40, BL = 36;
const pcs = (L, t) => K.peakPieces(L, t, PW_, PX, BL);
const drawn = (pc) => pc.strokes.length > 0;
const pts = (pc) => [].concat(...pc.strokes);
const meanY = (pc) => { const p = pts(pc); return p.reduce((a, q) => a + q.y, 0) / p.length; };
const maxX = (pc) => Math.max(...pts(pc).map(q => q.x));
test("props join the peak pool", () => {
    assert.strictEqual(K.PROP_FX.length, 8);
    K.PROP_FX.forEach(fx => assert.ok(K.PEAK_FX.indexOf(fx) >= 0, fx));
});
test("props: nothing before start, something on cue, four finite pieces", () => {
    for (const fx of K.PROP_FX) {
        const { L } = peakWith(fx);
        const on = K.peakOnAt(L), start = on - K.PROP_D[fx];
        assert.ok(start >= L.enterAt - 1e-9, fx + " starts before its line");
        const before = pcs(L, start - 0.05);
        assert.strictEqual(before.length, 4);
        assert.ok(before.every(pc => !drawn(pc)), fx + " draws before start");
        assert.ok(pcs(L, on + 0.1).some(drawn), fx + " draws nothing on cue");
        for (let t = L.enterAt - 0.5; t < L.pile.exitAt + 1; t += 0.03) {
            const P = pcs(L, t);
            assert.strictEqual(P.length, 4);
            finiteDeep(P, fx);
            finiteDeep(K.peakState(L, t), fx + " state");
            L.words[L.heroWi].chars.forEach((c, ci) => finiteDeep(K.letterState(L, t, L.heroWi, ci), fx + " letter"));
        }
        // other peaks draw no pieces
        assert.ok(pcs(peakWith("bulb").L, on + 0.1).every(pc => !drawn(pc)));
    }
});
test("balloon rises, lifts the word, then pops", () => {
    const { L } = peakWith("balloon");
    const on = K.peakOnAt(L), start = on - K.PROP_D.balloon, pop = K.balloonPop(L);
    assert.ok(meanY(pcs(L, start + 0.02)[0]) > meanY(pcs(L, on)[0]) + PX, "does not rise");
    assert.ok(K.peakState(L, on + 0.6).heroDy < -0.1, "word not lifted");
    assert.ok(pop >= on + 0.8 - 1e-9);
    const after = pcs(L, pop + 0.1);
    assert.ok(!drawn(after[0]) && drawn(after[2]), "no pop into confetti");
    assert.ok(Math.abs(K.peakState(L, pop + 0.8).heroDy) < 0.01, "word not back down");
});
test("note flutters down and gets taped", () => {
    const { L } = peakWith("note");
    const on = K.peakOnAt(L), start = on - K.PROP_D.note;
    assert.ok(meanY(pcs(L, start + 0.05)[0]) < meanY(pcs(L, on)[0]) - PX, "does not come down");
    assert.ok(!drawn(pcs(L, on - 0.05)[1]), "taped in the air");
    assert.ok(drawn(pcs(L, on + 0.4)[1]), "never taped");
});
test("plane sticks its nose in the hero's top right corner", () => {
    const { L } = peakWith("plane");
    const on = K.peakOnAt(L);
    const nose = pcs(L, on + 0.6)[0].strokes[0][0];
    assert.ok(Math.abs(nose.x - PW_) < PX * 0.3 && Math.abs(nose.y - (BL - 0.7 * PX)) < PX * 0.3, JSON.stringify(nose));
    assert.ok(Math.abs(K.peakState(L, on + 0.05).heroRot) > 0.5, "word does not shake");
    assert.ok(Math.abs(K.peakState(L, on + 1.5).heroRot) < 0.1);
});
test("roll lays its tape under the hero as it is sung", () => {
    const { L } = peakWith("roll");
    const on = K.peakOnAt(L), hw = L.words[L.heroWi], sung = Math.max(0.4, hw.end - hw.start);
    const mid = maxX(pcs(L, on + sung / 2)[1]), end = maxX(pcs(L, on + sung + 0.05)[1]);
    assert.ok(Math.abs(mid - PW_ / 2) < PW_ * 0.2, "mid " + mid);
    assert.ok(Math.abs(end - PW_) < PW_ * 0.1, "end " + end);
    assert.ok(drawn(pcs(L, on + sung + 2)[1]) && !drawn(pcs(L, on + sung + 2)[0]), "tape stays, roll leaves");
    const nc = hw.chars.length;
    if (nc > 1) assert.ok(K.letterState(L, on + sung * 0.5 / nc, L.heroWi, 0).dy < -0.05, "letters do not hop");
});
test("vine grows and blooms as the hero ends", () => {
    const { L } = peakWith("vine");
    const hw = L.words[L.heroWi], land = K.peakOnAt(L), bloom = land + Math.max(0.4, hw.end - hw.start);
    assert.ok(drawn(pcs(L, land + 0.1)[0]));
    assert.ok(!drawn(pcs(L, bloom - 0.05)[2]), "blooms early");
    assert.ok(drawn(pcs(L, bloom + 0.2)[2]), "never blooms");
});
test("jack splits the word, springs out, then closes", () => {
    const { L } = peakWith("jack");
    const on = K.peakOnAt(L), nc = L.words[L.heroWi].chars.length;
    const a = K.letterState(L, on + 0.3, L.heroWi, 0).dx, b = K.letterState(L, on + 0.3, L.heroWi, nc - 1).dx;
    assert.ok(a < -0.15 && (nc < 2 || b > 0.15), a + " " + b);
    assert.ok(drawn(pcs(L, on + 0.3)[0]) && drawn(pcs(L, on + 0.3)[1]), "no spring and star");
    assert.ok(Math.abs(K.letterState(L, on + 1.8, L.heroWi, 0).dx) < 0.01, "never closes");
    assert.ok(pcs(L, on + 1.8).every(pc => !drawn(pc)));
});
test("fold opens, then the word grows inside", () => {
    const { L } = peakWith("fold");
    const on = K.peakOnAt(L), start = on - K.PROP_D.fold;
    const w0 = maxX(pcs(L, start + 0.1)[0]), w1 = maxX(pcs(L, on)[0]);
    assert.ok(w1 > w0 + PX * 0.5, "does not open " + w0 + " " + w1);
    assert.ok(K.peakState(L, on - 0.05).heroS === 1);
    assert.ok(K.peakState(L, on + 0.5).heroS > 1.3);
    assert.ok(pcs(L, on).every(pc => pc.z < 0 || !drawn(pc)), "paper not behind the word");
});
test("hand places a sticker and pulls back", () => {
    const { L } = peakWith("hand");
    const on = K.peakOnAt(L);
    assert.ok(!drawn(pcs(L, on - 0.05)[1]), "sticker before the press");
    const later = pcs(L, on + 1.5);
    assert.ok(drawn(later[1]) && !drawn(later[0]), "sticker stays, hand leaves");
});

test("props wait for the line to finish coming in", () => {
    for (const fx of K.PROP_FX) {
        const { L } = peakWith(fx);
        L.words[L.heroWi].start = L.enterAt + 0.1;   // hero sung right as the line comes in
        assert.ok(K.peakOnAt(L) >= L.enterAt + K.PROP_SETTLE - 1e-9, fx + " lands mid-entry");
    }
});
test("balloon stays as low as the bulb", () => {
    const { L } = peakWith("balloon");
    const on = K.peakOnAt(L), pop = K.balloonPop(L);
    for (let t = on - K.PROP_D.balloon; t < pop; t += 0.02) {
        const pc = pcs(L, t)[0];
        if (drawn(pc)) assert.ok(Math.min(...pts(pc).map(q => q.y)) > BL - 2.35 * PX, "too high at " + (t - on).toFixed(2));
    }
});
test("stuck plane keeps clear of the next word", () => {
    const { L } = peakWith("plane");
    const on = K.peakOnAt(L);
    for (const dt of [0.3, 1, 2]) assert.ok(maxX(pcs(L, on + dt)[0]) < PW_ + 0.5 * PX, "tail over the next word " + dt);
});

test("rough set entry has doodles, rush, and peaks", () => {
    assert.deepStrictEqual(Array.from(K.SETS.rough.doodles), ["bolt", "crack", "spike", "cross", "bang"]);
    assert.deepStrictEqual(Array.from(K.SETS.rough.rush), ["bolt", "crack", "spike", "bang"]);
    assert.deepStrictEqual(Array.from(K.SETS.rough.peaks), ["shatter", "snap", "rip", "spot", "rays", "ink", "stamp"]);
});

test("rough doodles: bolt, crack, spike finite at several sizes", () => {
    for (const kind of ["bolt", "crack", "spike"]) {
        for (const [w, h] of [[12, 12], [24, 24], [48, 48], [120, 60]]) {
            const S = K.markShape(kind, 888, w, h);
            assert.ok(S.length > 0, kind + " has no strokes at " + w + "x" + h);
            for (const st of S) {
                assert.ok(st.length > 1, kind + " stroke too short");
                for (const p of st) {
                    assert.ok(isFinite(p.x) && isFinite(p.y), kind + " non-finite point");
                    assert.ok(p.x >= -w * 0.5 && p.x <= w * 1.5, kind + " x out of bounds: " + p.x);
                    assert.ok(p.y >= -h * 0.5 && p.y <= h * 1.5, kind + " y out of bounds: " + p.y);
                }
            }
        }
    }
});

test("rough peaks: nothing before start, something on cue, four finite pieces", () => {
    for (const fx of ["shatter", "snap", "rip"]) {
        const { L } = peakWith(fx);
        const on = K.peakOnAt(L), start = on - K.PROP_D[fx];
        assert.ok(start >= L.enterAt - 1e-9, fx + " starts before its line");
        const before = pcs(L, start - 0.05);
        assert.strictEqual(before.length, 4);
        assert.ok(before.every(pc => !drawn(pc)), fx + " draws before start");
        assert.ok(pcs(L, on + 0.1).some(drawn), fx + " draws nothing on cue");
        for (let t = L.enterAt - 0.5; t < L.pile.exitAt + 1; t += 0.03) {
            const P = pcs(L, t);
            assert.strictEqual(P.length, 4);
            finiteDeep(P, fx);
            finiteDeep(K.peakState(L, t), fx + " state");
            L.words[L.heroWi].chars.forEach((c, ci) => finiteDeep(K.letterState(L, t, L.heroWi, ci), fx + " letter"));
        }
    }
});

test("shatter: cracks spread, shards drop", () => {
    const { L } = peakWith("shatter");
    const on = K.peakOnAt(L);
    assert.ok(drawn(pcs(L, on + 0.05)[0]), "cracks not drawn");
    const y0 = meanY(pcs(L, on + 0.1)[1]);
    const y1 = meanY(pcs(L, on + 0.35)[1]);
    assert.ok(y1 > y0 + PX * 0.2, "shards do not drop: " + y0 + " vs " + y1);
    assert.ok(Math.abs(K.peakState(L, on + 0.05).heroDy) > 0.04, "word does not shake");
});

test("snap: string snaps and both ends curl back", () => {
    const { L } = peakWith("snap");
    const on = K.peakOnAt(L), start = on - K.PROP_D.snap;
    assert.ok(drawn(pcs(L, start + 0.3)[0]), "string not drawn before snap");
    assert.ok(drawn(pcs(L, on + 0.1)[0]), "curls not drawn after snap");
    assert.ok(Math.abs(K.peakState(L, on + 0.05).heroDy) > 0.02, "word does not twang");
});

test("rip: letters slip apart then close", () => {
    const { L } = peakWith("rip");
    const on = K.peakOnAt(L);
    assert.ok(drawn(pcs(L, on)[0]), "incision not drawn");
    const nc = L.words[L.heroWi].chars.length;
    const l0 = K.letterState(L, on + 0.2, L.heroWi, 0);
    const l1 = K.letterState(L, on + 0.2, L.heroWi, nc - 1);
    assert.ok(l0.dy < -0.05, "left letter not slipped up: " + l0.dy);
    assert.ok(l1.dy > 0.05, "right letter not slipped down: " + l1.dy);
    const closed = K.letterState(L, on + 2.0, L.heroWi, 0);
    assert.strictEqual(K.ripSplit(L, on + 2.0), 0, "ripSplit not 0");
    assert.ok(Math.abs(closed.dx) < 0.01, "letters dx does not close: " + closed.dx);
    assert.ok(Math.abs(closed.dy) < 0.05, "letters dy does not close: " + closed.dy);
});

test("street set entry has doodles, rush, and peaks", () => {
    assert.deepStrictEqual(Array.from(K.SETS.street.doodles), ["crown", "drip", "arrow", "tag", "burst"]);
    assert.deepStrictEqual(Array.from(K.SETS.street.rush), ["crown", "drip", "arrow", "burst"]);
    assert.deepStrictEqual(Array.from(K.SETS.street.peaks), ["spray", "micdrop", "tapex", "spot", "rays", "ink", "stamp"]);
});

test("street doodles: crown, drip, arrow, tag finite at several sizes", () => {
    for (const kind of ["crown", "drip", "arrow", "tag"]) {
        for (const [w, h] of [[12, 12], [24, 24], [48, 48], [120, 60]]) {
            const S = K.markShape(kind, 888, w, h);
            assert.ok(S.length > 0, kind + " has no strokes at " + w + "x" + h);
            for (const st of S) {
                assert.ok(st.length > 1, kind + " stroke too short");
                for (const p of st) {
                    assert.ok(isFinite(p.x) && isFinite(p.y), kind + " non-finite point");
                    assert.ok(p.x >= -w * 0.5 && p.x <= w * 1.5, kind + " x out of bounds: " + p.x);
                    assert.ok(p.y >= -h * 0.5 && p.y <= h * 1.5, kind + " y out of bounds: " + p.y);
                }
            }
        }
    }
});

test("street peaks: nothing before start, something on cue, four finite pieces", () => {
    for (const fx of ["spray", "micdrop", "tapex"]) {
        const { L } = peakWith(fx);
        const on = K.peakOnAt(L), start = on - K.PROP_D[fx];
        assert.ok(start >= L.enterAt - 1e-9, fx + " starts before its line");
        const before = pcs(L, start - 0.05);
        assert.strictEqual(before.length, 4);
        assert.ok(before.every(pc => !drawn(pc)), fx + " draws before start");
        assert.ok(pcs(L, on + 0.1).some(drawn), fx + " draws nothing on cue");
        for (let t = L.enterAt - 0.5; t < L.pile.exitAt + 1; t += 0.03) {
            const P = pcs(L, t);
            assert.strictEqual(P.length, 4);
            finiteDeep(P, fx);
            finiteDeep(K.peakState(L, t), fx + " state");
            L.words[L.heroWi].chars.forEach((c, ci) => finiteDeep(K.letterState(L, t, L.heroWi, ci), fx + " letter"));
        }
    }
});

test("spray: can shakes and flies in, tag sprayed behind, paint drips", () => {
    const { L } = peakWith("spray");
    const on = K.peakOnAt(L), start = on - K.PROP_D.spray;
    assert.ok(drawn(pcs(L, start + 0.3)[0]), "spray can not drawn during fly-in");
    assert.ok(drawn(pcs(L, on + 0.15)[1]), "tag not drawn behind hero word on cue");
    assert.ok(drawn(pcs(L, on + 0.25)[2]), "drips not drawn on cue");
    assert.ok(Math.abs(K.peakState(L, on + 0.05).heroDy) > 0.01, "word does not react to spray");
});

test("micdrop: mic drops, bounces on baseline, sound lines radiate", () => {
    const { L } = peakWith("micdrop");
    const on = K.peakOnAt(L), start = on - K.PROP_D.micdrop;
    assert.ok(drawn(pcs(L, start + 0.2)[0]), "mic not drawn falling");
    const y0 = meanY(pcs(L, start + 0.2)[0]);
    const y1 = meanY(pcs(L, on)[0]);
    assert.ok(y1 > y0 + PX * 0.5, "mic does not fall: " + y0 + " vs " + y1);
    assert.ok(drawn(pcs(L, on + 0.05)[1]), "sound lines not drawn on impact");
    assert.ok(Math.abs(K.peakState(L, on + 0.05).heroDy) > 0.03, "word does not bounce with mic impact");
});

test("tapex: tape strips slap on crosswise over corner", () => {
    const { L } = peakWith("tapex");
    const on = K.peakOnAt(L), start = on - K.PROP_D.tapex;
    assert.ok(drawn(pcs(L, start + 0.3)[0]), "strip 1 not drawn before on");
    assert.ok(drawn(pcs(L, on + 0.05)[1]), "strip 2 not drawn on cue");
    assert.ok(Math.abs(K.peakState(L, on + 0.05).heroDy) > 0.01, "word does not react to tape slap");
});

test("dance set entry has doodles, rush, and peaks", () => {
    assert.deepStrictEqual(Array.from(K.SETS.dance.doodles), ["wave", "dots", "beam", "grid", "sparkle"]);
    assert.deepStrictEqual(Array.from(K.SETS.dance.rush), ["wave", "dots", "beam", "sparkle"]);
    assert.deepStrictEqual(Array.from(K.SETS.dance.peaks), ["disco", "eq", "laser", "spot", "rays", "ink", "stamp"]);
});

test("dance doodles: wave, dots, beam, grid finite at several sizes", () => {
    for (const kind of ["wave", "dots", "beam", "grid"]) {
        for (const [w, h] of [[12, 12], [24, 24], [48, 48], [120, 60]]) {
            const S = K.markShape(kind, 888, w, h);
            assert.ok(S.length > 0, kind + " has no strokes at " + w + "x" + h);
            for (const st of S) {
                assert.ok(st.length > 1, kind + " stroke too short");
                for (const p of st) {
                    assert.ok(isFinite(p.x) && isFinite(p.y), kind + " non-finite point");
                    assert.ok(p.x >= -w * 0.5 && p.x <= w * 1.5, kind + " x out of bounds: " + p.x);
                    assert.ok(p.y >= -h * 0.5 && p.y <= h * 1.5, kind + " y out of bounds: " + p.y);
                }
            }
        }
    }
});

test("dance peaks: nothing before start, something on cue, four finite pieces", () => {
    for (const fx of ["disco", "eq", "laser"]) {
        const { L } = peakWith(fx);
        const on = K.peakOnAt(L), start = on - K.PROP_D[fx];
        assert.ok(start >= L.enterAt - 1e-9, fx + " starts before its line");
        const before = pcs(L, start - 0.05);
        assert.strictEqual(before.length, 4);
        assert.ok(before.every(pc => !drawn(pc)), fx + " draws before start");
        assert.ok(pcs(L, on + 0.1).some(drawn), fx + " draws nothing on cue");
        for (let t = L.enterAt - 0.5; t < L.pile.exitAt + 1; t += 0.03) {
            const P = pcs(L, t);
            assert.strictEqual(P.length, 4);
            finiteDeep(P, fx);
            finiteDeep(K.peakState(L, t), fx + " state");
            L.words[L.heroWi].chars.forEach((c, ci) => finiteDeep(K.letterState(L, t, L.heroWi, ci), fx + " letter"));
        }
    }
});

test("disco: disco ball lowers on cord, turns, light flecks radiate", () => {
    const { L } = peakWith("disco");
    const on = K.peakOnAt(L), start = on - K.PROP_D.disco;
    assert.ok(drawn(pcs(L, start + 0.3)[0]), "disco ball not drawn lowering");
    const y0 = meanY(pcs(L, start + 0.1)[0]);
    const y1 = meanY(pcs(L, on)[0]);
    assert.ok(y1 > y0 + PX * 0.5, "disco ball does not lower: " + y0 + " vs " + y1);
    assert.ok(drawn(pcs(L, on + 0.1)[1]), "facets not drawn on cue");
    assert.ok(drawn(pcs(L, on + 0.15)[2]), "light flecks not drawn on cue");
    assert.ok(Math.abs(K.peakState(L, on + 0.05).heroDy) > 0.01, "word does not react to disco beat");
});

test("eq: equalizer bars jump behind word with singing", () => {
    const { L } = peakWith("eq");
    const on = K.peakOnAt(L), start = on - K.PROP_D.eq;
    assert.ok(drawn(pcs(L, start + 0.2)[1]), "eq bars not rising before on");
    assert.ok(drawn(pcs(L, on + 0.1)[1]), "eq bars not drawn jumping on cue");
    assert.ok(drawn(pcs(L, on + 0.1)[2]), "eq peak caps not drawn on cue");
    assert.ok(Math.abs(K.peakState(L, on + 0.05).heroDy) > 0.01, "word does not react to eq bass");
});

test("laser: two beams sweep across and cross on word", () => {
    const { L } = peakWith("laser");
    const on = K.peakOnAt(L), start = on - K.PROP_D.laser;
    assert.ok(drawn(pcs(L, start + 0.2)[0]), "laser beams not drawn sweeping");
    assert.ok(drawn(pcs(L, on + 0.05)[1]), "laser flare star not drawn on cue");
    assert.ok(Math.abs(K.peakState(L, on + 0.05).heroS - 1) > 0.01, "word does not react to laser cross");
});

test("calm set entry has doodles, rush, and peaks", () => {
    assert.deepStrictEqual(Array.from(K.SETS.calm.doodles), ["cloud", "drop", "ripple", "leaf", "moon"]);
    assert.deepStrictEqual(Array.from(K.SETS.calm.rush), ["cloud", "drop", "ripple", "leaf"]);
    assert.deepStrictEqual(Array.from(K.SETS.calm.peaks), ["calm_leaf", "droplet", "moonrise", "spot", "rays", "ink", "stamp"]);
});

test("calm doodles: cloud, drop, ripple, leaf, moon finite at several sizes", () => {
    for (const kind of ["cloud", "drop", "ripple", "leaf", "moon"]) {
        for (const [w, h] of [[12, 12], [24, 24], [48, 48], [120, 60]]) {
            const S = K.markShape(kind, 888, w, h);
            assert.ok(S.length > 0, kind + " has no strokes at " + w + "x" + h);
            for (const st of S) {
                assert.ok(st.length > 1, kind + " stroke too short");
                for (const p of st) {
                    assert.ok(isFinite(p.x) && isFinite(p.y), kind + " non-finite point");
                    assert.ok(p.x >= -w * 0.5 && p.x <= w * 1.5, kind + " x out of bounds: " + p.x);
                    assert.ok(p.y >= -h * 0.5 && p.y <= h * 1.5, kind + " y out of bounds: " + p.y);
                }
            }
        }
    }
});

test("calm peaks: nothing before start, something on cue, four finite pieces", () => {
    for (const fx of ["calm_leaf", "droplet", "moonrise"]) {
        const { L } = peakWith(fx);
        const on = K.peakOnAt(L), start = on - K.PROP_D[fx];
        assert.ok(start >= L.enterAt - 1e-9, fx + " starts before its line");
        const before = pcs(L, start - 0.05);
        assert.strictEqual(before.length, 4);
        assert.ok(before.every(pc => !drawn(pc)), fx + " draws before start");
        assert.ok(pcs(L, on + 0.1).some(drawn), fx + " draws nothing on cue");
        for (let t = L.enterAt - 0.5; t < L.pile.exitAt + 1; t += 0.03) {
            const P = pcs(L, t);
            assert.strictEqual(P.length, 4);
            finiteDeep(P, fx);
            finiteDeep(K.peakState(L, t), fx + " state");
            L.words[L.heroWi].chars.forEach((c, ci) => finiteDeep(K.letterState(L, t, L.heroWi, ci), fx + " letter"));
        }
    }
});

test("calm_leaf: leaf drifts down side to side and lands on word", () => {
    const { L } = peakWith("calm_leaf");
    const on = K.peakOnAt(L), start = on - K.PROP_D.calm_leaf;
    assert.ok(drawn(pcs(L, start + 0.3)[0]), "leaf not drawn drifting");
    const y0 = meanY(pcs(L, start + 0.1)[0]);
    const y1 = meanY(pcs(L, on)[0]);
    assert.ok(y1 > y0 + PX * 0.5, "leaf does not drift down: " + y0 + " vs " + y1);
    assert.ok(drawn(pcs(L, on + 0.1)[0]), "leaf not drawn on cue");
    assert.ok(drawn(pcs(L, on + 0.1)[2]), "dewdrop not drawn on cue");
    assert.ok(Math.abs(K.peakState(L, on + 0.05).heroDy) > 0.01, "word does not react to leaf landing");
});

test("droplet: drop falls, ripples spread under word", () => {
    const { L } = peakWith("droplet");
    const on = K.peakOnAt(L), start = on - K.PROP_D.droplet;
    assert.ok(drawn(pcs(L, start + 0.2)[0]), "drop not drawn falling");
    const y0 = meanY(pcs(L, start + 0.1)[0]);
    const y1 = meanY(pcs(L, on)[0]);
    assert.ok(y1 > y0 + PX * 0.5, "drop does not fall: " + y0 + " vs " + y1);
    assert.ok(drawn(pcs(L, on + 0.1)[1]), "ripples not drawn spreading on cue");
    assert.ok(Math.abs(K.peakState(L, on + 0.05).heroDy) > 0.01, "word does not react to droplet splash");
});

test("moonrise: crescent rises behind word", () => {
    const { L } = peakWith("moonrise");
    const on = K.peakOnAt(L), start = on - K.PROP_D.moonrise;
    assert.ok(drawn(pcs(L, start + 0.2)[0]), "moon not drawn rising");
    const y0 = meanY(pcs(L, start + 0.1)[0]);
    const y1 = meanY(pcs(L, on)[0]);
    assert.ok(y1 < y0 - PX * 0.5, "moon does not rise: " + y0 + " vs " + y1);
    assert.ok(drawn(pcs(L, on + 0.3)[2]), "stars not out on cue");
    assert.ok(Math.abs(K.peakState(L, on + 0.05).heroDy) > 0.01, "word does not react to moonrise");
});

test("classic set entry has doodles, rush, and peaks", () => {
    assert.deepStrictEqual(Array.from(K.SETS.classic.doodles), ["note", "notes", "smoke", "vinyl", "mic"]);
    assert.deepStrictEqual(Array.from(K.SETS.classic.rush), ["note", "notes", "smoke", "vinyl"]);
    assert.deepStrictEqual(Array.from(K.SETS.classic.peaks), ["classic_vinyl", "classic_smoke", "horn", "spot", "rays", "ink", "stamp"]);
});

test("classic doodles: note, notes, smoke, vinyl, swing finite at several sizes", () => {
    for (const kind of ["note", "notes", "smoke", "vinyl", "mic"]) {
        for (const [w, h] of [[12, 12], [24, 24], [48, 48], [120, 60]]) {
            const S = K.markShape(kind, 888, w, h);
            assert.ok(S.length > 0, kind + " has no strokes at " + w + "x" + h);
            for (const st of S) {
                assert.ok(st.length > 1, kind + " stroke too short");
                for (const p of st) {
                    assert.ok(isFinite(p.x) && isFinite(p.y), kind + " non-finite point");
                    assert.ok(p.x >= -w * 0.5 && p.x <= w * 1.5, kind + " x out of bounds: " + p.x);
                    assert.ok(p.y >= -h * 0.5 && p.y <= h * 1.5, kind + " y out of bounds: " + p.y);
                }
            }
        }
    }
});

test("classic peaks: nothing before start, something on cue, four finite pieces", () => {
    for (const fx of ["classic_vinyl", "classic_smoke", "horn"]) {
        const { L } = peakWith(fx);
        const on = K.peakOnAt(L), start = on - K.PROP_D[fx];
        assert.ok(start >= L.enterAt - 1e-9, fx + " starts before its line");
        const before = pcs(L, start - 0.05);
        assert.strictEqual(before.length, 4);
        assert.ok(before.every(pc => !drawn(pc)), fx + " draws before start");
        assert.ok(pcs(L, on + 0.1).some(drawn), fx + " draws nothing on cue");
        for (let t = L.enterAt - 0.5; t < L.pile.exitAt + 1; t += 0.03) {
            const P = pcs(L, t);
            assert.strictEqual(P.length, 4);
            finiteDeep(P, fx);
            finiteDeep(K.peakState(L, t), fx + " state");
            L.words[L.heroWi].chars.forEach((c, ci) => finiteDeep(K.letterState(L, t, L.heroWi, ci), fx + " letter"));
        }
    }
});

test("classic_vinyl: record rolls in, stops behind word, spins", () => {
    const { L } = peakWith("classic_vinyl");
    const on = K.peakOnAt(L), start = on - K.PROP_D.classic_vinyl;
    assert.ok(drawn(pcs(L, start + 0.2)[0]), "disc not drawn rolling");
    const p0 = pts(pcs(L, start + 0.1)[0]);
    const p1 = pts(pcs(L, on)[0]);
    const x0 = p0.reduce((a, q) => a + q.x, 0) / p0.length;
    const x1 = p1.reduce((a, q) => a + q.x, 0) / p1.length;
    assert.ok(x1 > x0 + PX * 0.5, "disc does not roll in: " + x0 + " vs " + x1);
    assert.strictEqual(pcs(L, on + 0.1)[0].z < 0, true, "disc not behind the letters");
    assert.ok(drawn(pcs(L, on + 0.1)[0]), "disc not drawn on cue");
    assert.ok(drawn(pcs(L, on + 0.1)[1]), "sheen arcs not drawn on cue");
    assert.ok(Math.abs(K.peakState(L, on + 0.05).heroS - 1) > 0.01, "word does not react to vinyl stop");
});

test("classic_smoke: curl of smoke rises off word", () => {
    const { L } = peakWith("classic_smoke");
    const on = K.peakOnAt(L), start = on - K.PROP_D.classic_smoke;
    assert.ok(drawn(pcs(L, start + 0.2)[0]), "smoke not drawn wafting");
    const y0 = meanY(pcs(L, start + 0.1)[0]);
    const y1 = meanY(pcs(L, on)[0]);
    assert.ok(y1 < y0 - PX * 0.1, "smoke does not rise: " + y0 + " vs " + y1);
    assert.ok(drawn(pcs(L, on + 0.1)[0]), "smoke plume not drawn on cue");
    assert.ok(drawn(pcs(L, on + 0.1)[1]), "smoke rings not drawn on cue");
    assert.ok(Math.abs(K.peakState(L, on + 0.05).heroDy) > 0.01, "word does not react to smoke rising");
});

test("horn: horn pokes in and blows notes over word", () => {
    const { L } = peakWith("horn");
    const on = K.peakOnAt(L), start = on - K.PROP_D.horn;
    assert.ok(drawn(pcs(L, start + 0.2)[0]), "horn not drawn poking in");
    const p0 = pts(pcs(L, start + 0.1)[0]);
    const p1 = pts(pcs(L, on)[0]);
    const x0 = p0.reduce((a, q) => a + q.x, 0) / p0.length;
    const x1 = p1.reduce((a, q) => a + q.x, 0) / p1.length;
    assert.ok(x1 > x0 + PX * 0.5, "horn does not poke in: " + x0 + " vs " + x1);
    assert.ok(drawn(pcs(L, on + 0.1)[0]), "horn not drawn on cue");
    assert.ok(drawn(pcs(L, on + 0.1)[1]), "blast waves not drawn on cue");
    assert.ok(drawn(pcs(L, on + 0.1)[2]), "musical notes not blown on cue");
    assert.ok(Math.abs(K.peakState(L, on + 0.05).heroS - 1) > 0.01, "word does not react to horn blast");
});

test("anime set entry has doodles, rush, and peaks", () => {
    assert.deepStrictEqual(Array.from(K.SETS.anime.doodles), ["star4", "speed", "sweat", "anger", "sparkle"]);
    assert.deepStrictEqual(Array.from(K.SETS.anime.rush), ["star4", "speed", "sweat", "anger"]);
    assert.deepStrictEqual(Array.from(K.SETS.anime.peaks), ["flash", "focus", "sakura", "spot", "rays", "ink", "stamp"]);
});

test("anime doodles: star4, speed, sweat, anger, sparkle finite at several sizes", () => {
    for (const kind of ["star4", "speed", "sweat", "anger", "sparkle"]) {
        for (const [w, h] of [[12, 12], [24, 24], [48, 48], [120, 60]]) {
            const S = K.markShape(kind, 888, w, h);
            assert.ok(S.length > 0, kind + " has no strokes at " + w + "x" + h);
            for (const st of S) {
                assert.ok(st.length > 1, kind + " stroke too short");
                for (const p of st) {
                    assert.ok(isFinite(p.x) && isFinite(p.y), kind + " non-finite point");
                    assert.ok(p.x >= -w * 0.5 && p.x <= w * 1.5, kind + " x out of bounds: " + p.x);
                    assert.ok(p.y >= -h * 0.5 && p.y <= h * 1.5, kind + " y out of bounds: " + p.y);
                }
            }
        }
    }
});

test("anime peaks: nothing before start, something on cue, four finite pieces", () => {
    for (const fx of ["flash", "focus", "sakura"]) {
        const { L } = peakWith(fx);
        const on = K.peakOnAt(L), start = on - K.PROP_D[fx];
        assert.ok(start >= L.enterAt - 1e-9, fx + " starts before its line");
        const before = pcs(L, start - 0.05);
        assert.strictEqual(before.length, 4);
        assert.ok(before.every(pc => !drawn(pc)), fx + " draws before start");
        assert.ok(pcs(L, on + 0.1).some(drawn), fx + " draws nothing on cue");
        for (let t = L.enterAt - 0.5; t < L.pile.exitAt + 1; t += 0.03) {
            const P = pcs(L, t);
            assert.strictEqual(P.length, 4);
            finiteDeep(P, fx);
            finiteDeep(K.peakState(L, t), fx + " state");
            L.words[L.heroWi].chars.forEach((c, ci) => finiteDeep(K.letterState(L, t, L.heroWi, ci), fx + " letter"));
        }
    }
});

test("flash: a four-point star flashes on hero with glints", () => {
    const { L } = peakWith("flash");
    const on = K.peakOnAt(L), start = on - K.PROP_D.flash;
    assert.ok(drawn(pcs(L, start + 0.2)[0]), "flash star not drawn charging");
    assert.ok(drawn(pcs(L, on + 0.05)[1]), "glint beams not drawn on cue");
    assert.ok(drawn(pcs(L, on + 0.08)[2]), "sparkles not drawn on cue");
    assert.ok(Math.abs(K.peakState(L, on + 0.05).heroS - 1) > 0.01, "word does not react to flash");
});

test("focus: manga focus lines close in from frame edges", () => {
    const { L } = peakWith("focus");
    const on = K.peakOnAt(L), start = on - K.PROP_D.focus;
    assert.ok(drawn(pcs(L, start + 0.2)[0]), "focus lines not drawn rushing in");
    const p0 = pts(pcs(L, start + 0.1)[0]);
    const p1 = pts(pcs(L, on)[0]);
    const x0 = p0.reduce((a, q) => a + q.x, 0) / p0.length;
    const x1 = p1.reduce((a, q) => a + q.x, 0) / p1.length;
    assert.ok(x1 > x0 + PX * 0.15, "focus lines do not close in: " + x0 + " vs " + x1);
    assert.ok(drawn(pcs(L, on + 0.05)[1]), "right focus lines not drawn on cue");
    assert.ok(drawn(pcs(L, on + 0.05)[3]), "impact brackets not drawn on cue");
    assert.ok(Math.abs(K.peakState(L, on + 0.05).heroS - 1) > 0.01, "word does not react to focus lines");
});

test("sakura: petals drift across word", () => {
    const { L } = peakWith("sakura");
    const on = K.peakOnAt(L), start = on - K.PROP_D.sakura;
    assert.ok(drawn(pcs(L, start + 0.2)[0]), "sakura petal not drawn drifting");
    const p0 = pts(pcs(L, start + 0.1)[0]);
    const p1 = pts(pcs(L, on)[0]);
    const y0 = meanY(pcs(L, start + 0.1)[0]);
    const y1 = meanY(pcs(L, on)[0]);
    assert.ok(y1 > y0 + PX * 0.5, "sakura petal does not drift down: " + y0 + " vs " + y1);
    const x0 = p0.reduce((a, q) => a + q.x, 0) / p0.length;
    const x1 = p1.reduce((a, q) => a + q.x, 0) / p1.length;
    assert.ok(x1 > x0 + PX * 0.5, "sakura petal does not drift across: " + x0 + " vs " + x1);
    assert.ok(drawn(pcs(L, on + 0.1)[0]), "main petal not drawn on cue");
    assert.ok(drawn(pcs(L, on + 0.1)[1]), "companion petals not drawn on cue");
    assert.ok(drawn(pcs(L, on + 0.1)[2]), "breeze lines not drawn on cue");
    assert.ok(Math.abs(K.peakState(L, on + 0.05).heroDy) > 0.01, "word does not react to sakura drift");
});

test("folk set entry has doodles, rush, and peaks", () => {
    assert.deepStrictEqual(Array.from(K.SETS.folk.doodles), ["sun", "sprout", "bird", "hill", "star"]);
    assert.deepStrictEqual(Array.from(K.SETS.folk.rush), ["sun", "sprout", "bird", "hill"]);
    assert.deepStrictEqual(Array.from(K.SETS.folk.peaks), ["sunrise", "flock", "folk_sprout", "spot", "rays", "ink", "stamp"]);
});

test("folk doodles: sun, sprout, bird, hill, star finite at several sizes", () => {
    for (const kind of ["sun", "sprout", "bird", "hill", "star"]) {
        for (const [w, h] of [[12, 12], [24, 24], [48, 48], [120, 60]]) {
            const S = K.markShape(kind, 888, w, h);
            assert.ok(S.length > 0, kind + " has no strokes at " + w + "x" + h);
            for (const st of S) {
                assert.ok(st.length > 1, kind + " stroke too short");
                for (const p of st) {
                    assert.ok(isFinite(p.x) && isFinite(p.y), kind + " non-finite point");
                    assert.ok(p.x >= -w * 0.5 && p.x <= w * 1.5, kind + " x out of bounds: " + p.x);
                    assert.ok(p.y >= -h * 0.5 && p.y <= h * 1.5, kind + " y out of bounds: " + p.y);
                }
            }
        }
    }
});

test("folk peaks: nothing before start, something on cue, four finite pieces", () => {
    for (const fx of ["sunrise", "flock", "folk_sprout"]) {
        const { L } = peakWith(fx);
        const on = K.peakOnAt(L), start = on - K.PROP_D[fx];
        assert.ok(start >= L.enterAt - 1e-9, fx + " starts before its line");
        const before = pcs(L, start - 0.05);
        assert.strictEqual(before.length, 4);
        assert.ok(before.every(pc => !drawn(pc)), fx + " draws before start");
        assert.ok(pcs(L, on + 0.1).some(drawn), fx + " draws nothing on cue");
        for (let t = L.enterAt - 0.5; t < L.pile.exitAt + 1; t += 0.03) {
            const P = pcs(L, t);
            assert.strictEqual(P.length, 4);
            finiteDeep(P, fx);
            finiteDeep(K.peakState(L, t), fx + " state");
            L.words[L.heroWi].chars.forEach((c, ci) => finiteDeep(K.letterState(L, t, L.heroWi, ci), fx + " letter"));
        }
    }
});

test("sunrise: the sun rises behind the word, rays open", () => {
    const { L } = peakWith("sunrise");
    const on = K.peakOnAt(L), start = on - K.PROP_D.sunrise;
    assert.ok(drawn(pcs(L, start + 0.2)[0]), "sun not drawn rising");
    const y0 = meanY(pcs(L, start + 0.1)[0]);
    const y1 = meanY(pcs(L, on)[0]);
    assert.ok(y1 < y0 - PX * 0.2, "sun does not rise: " + y0 + " vs " + y1);
    assert.strictEqual(pcs(L, on + 0.1)[0].z < 0, true, "sun not behind the letters");
    assert.ok(drawn(pcs(L, on + 0.05)[1]), "rays not drawn opening on cue");
    assert.ok(drawn(pcs(L, on + 0.05)[2]), "horizon not drawn on cue");
    assert.ok(Math.abs(K.peakState(L, on + 0.05).heroDy) > 0.005, "word does not react to sunrise");
});

test("flock: a few birds fly over the word", () => {
    const { L } = peakWith("flock");
    const on = K.peakOnAt(L), start = on - K.PROP_D.flock;
    assert.ok(drawn(pcs(L, start + 0.2)[0]), "lead bird not drawn in flight");
    const p0 = pts(pcs(L, start + 0.1)[0]);
    const p1 = pts(pcs(L, on)[0]);
    const x0 = p0.reduce((a, q) => a + q.x, 0) / p0.length;
    const x1 = p1.reduce((a, q) => a + q.x, 0) / p1.length;
    assert.ok(x1 > x0 + PX * 0.2, "birds do not fly across: " + x0 + " vs " + x1);
    assert.ok(drawn(pcs(L, on + 0.05)[1]), "flock companions not drawn on cue");
    assert.ok(drawn(pcs(L, on + 0.05)[3]), "slipstream not drawn on cue");
    assert.ok(Math.abs(K.peakState(L, on + 0.05).heroDy) > 0.005, "word does not react to flock flying overhead");
});

test("sprout: a shoot grows out of the word top and opens two leaves", () => {
    const { L } = peakWith("folk_sprout");
    const on = K.peakOnAt(L), start = on - K.PROP_D.folk_sprout;
    assert.ok(drawn(pcs(L, start + 0.2)[0]), "shoot not drawn growing");
    const p0 = pts(pcs(L, start + 0.1)[0]);
    const p1 = pts(pcs(L, on)[0]);
    const y0 = Math.min(...p0.map(q => q.y));
    const y1 = Math.min(...p1.map(q => q.y));
    assert.ok(y1 < y0 - PX * 0.1, "shoot does not grow upward: " + y0 + " vs " + y1);
    assert.ok(drawn(pcs(L, on + 0.05)[1]), "two leaves not open on cue");
    assert.ok(drawn(pcs(L, on + 0.08)[2]), "sparkles/dewdrop not drawn on cue");
    assert.ok(Math.abs(K.peakState(L, on + 0.05).heroS - 1) > 0.01, "word does not react to sprout");
});

test("familyOf on real names", () => {
    assert.strictEqual(K.familyOf("Pop"), "pop");
    assert.strictEqual(K.familyOf("Hip-Hop/Rap"), "street");
    assert.strictEqual(K.familyOf("J-Pop"), "pop");
    assert.strictEqual(K.familyOf("Hard Rock"), "rough");
    assert.strictEqual(K.familyOf("K-Pop"), "pop");
    assert.strictEqual(K.familyOf("New Age"), "calm");
    assert.strictEqual(K.familyOf("Death Metal/Black Metal"), "rough");
    assert.strictEqual(K.familyOf("House"), "dance");
    assert.strictEqual(K.familyOf("Smooth Jazz"), "classic");
    assert.strictEqual(K.familyOf("Anime"), "anime");
    assert.strictEqual(K.familyOf("Country"), "folk");
    assert.strictEqual(K.familyOf("Unknown Genre"), null);
    assert.strictEqual(K.familyOf(""), null);
    assert.strictEqual(K.familyOf(null), null);
});

test("pickSet covers every branch of the rule", () => {
    // 1. Sweet slow ballad lyrics (high love score, slow tempo)
    const sweetBallad = song([
        [0, "anh yêu em nhiều lắm em ơi"],
        [3.0, "thương nhớ từng phút giây bên em"],
        [6.0, "trái tim này trao trọn về em"]
    ]);
    assert.ok(K.loveScore(sweetBallad) >= 0.035, "sweetBallad should have sweet lyrics");
    assert.ok(K.songMedianRate(sweetBallad) < 11.0, "sweetBallad should not be fast");

    // 2. Fast non-sweet lyrics (low love score, fast tempo)
    const fastNonSweet = song([
        [0, FAST[0]],
        [1.6, FAST[1]],
        [3.2, FAST[2]],
        [4.8, FAST[3]]
    ]);
    assert.ok(K.loveScore(fastNonSweet) < 0.035, "fastNonSweet should not have sweet lyrics");
    assert.ok(K.songMedianRate(fastNonSweet) >= 11.0, "fastNonSweet should be fast");

    // 3. Mid non-sweet lyrics (low love score, not fast)
    const midNonSweet = song([
        [0, "ngày mai nắng lên rồi trên phố xưa"],
        [3.0, "bước chân ai đi về miền xa xôi"],
        [6.0, "mây trôi lững lờ qua khung cửa sổ"]
    ]);
    assert.ok(K.loveScore(midNonSweet) < 0.035, "midNonSweet should not have sweet lyrics");
    assert.ok(K.songMedianRate(midNonSweet) < 11.0, "midNonSweet should not be fast");

    // 4. Fast sweet lyrics (high love score, fast tempo)
    const fastSweet = song([
        [0, "yêu em yêu em yêu em chạy thật nhanh không ngừng nghỉ"],
        [1.5, "thương em thương em thương em vội vàng qua bao mùa mưa"],
        [3.0, "nhớ em nhớ em nhớ em từng ngày trôi qua thật nhanh"]
    ]);
    assert.ok(K.loveScore(fastSweet) >= 0.035, "fastSweet should have sweet lyrics");
    assert.ok(K.songMedianRate(fastSweet) >= 11.0, "fastSweet should be fast");

    // Branch: Rough, street or dance family, and sweetLyrics and not fast -> sweet
    assert.strictEqual(K.pickSet("Hard Rock", sweetBallad), "sweet");
    assert.strictEqual(K.pickSet("Hip-Hop/Rap", sweetBallad), "sweet");
    assert.strictEqual(K.pickSet("House", sweetBallad), "sweet");

    // Fast rough/street/dance with sweet lyrics stays rough/street/dance
    assert.strictEqual(K.pickSet("Hard Rock", fastSweet), "rough");
    assert.strictEqual(K.pickSet("Hip-Hop/Rap", fastSweet), "street");
    assert.strictEqual(K.pickSet("House", fastSweet), "dance");

    // Non-sweet rough/street/dance stays rough/street/dance
    assert.strictEqual(K.pickSet("Hard Rock", midNonSweet), "rough");
    assert.strictEqual(K.pickSet("Hip-Hop/Rap", fastNonSweet), "street");
    assert.strictEqual(K.pickSet("House", fastNonSweet), "dance");

    // Branch: Pop family: dance when fast and not sweetLyrics, otherwise sweet
    assert.strictEqual(K.pickSet("Pop", fastNonSweet), "dance");
    assert.strictEqual(K.pickSet("K-Pop", fastNonSweet), "dance");
    assert.strictEqual(K.pickSet("J-Pop", fastNonSweet), "dance");
    assert.strictEqual(K.pickSet("Pop", fastSweet), "sweet");
    assert.strictEqual(K.pickSet("Pop", midNonSweet), "sweet");
    assert.strictEqual(K.pickSet("Pop", sweetBallad), "sweet");

    // Branch: null family: sweet when sweetLyrics, dance when fast, otherwise sweet
    assert.strictEqual(K.pickSet(null, sweetBallad), "sweet");
    assert.strictEqual(K.pickSet(null, fastSweet), "sweet");
    assert.strictEqual(K.pickSet(null, fastNonSweet), "dance");
    assert.strictEqual(K.pickSet(null, midNonSweet), "sweet");

    // Branch: Any other family: keep it
    assert.strictEqual(K.pickSet("New Age", fastNonSweet), "calm");
    assert.strictEqual(K.pickSet("Smooth Jazz", sweetBallad), "classic");
    assert.strictEqual(K.pickSet("Anime", sweetBallad), "anime");
    assert.strictEqual(K.pickSet("Country", fastSweet), "folk");
    assert.strictEqual(K.pickSet("Singer/Songwriter", fastNonSweet), "sweet");
});

test("sweet set builds identical piles and fx", () => {
    const ly = longSong();
    const mSweet = K.build(ly, { max: true, set: "sweet" });
    const mDefault = K.build(ly, { max: true }); // defaults to pickSet(null, ly) -> sweet
    assert.strictEqual(mSweet.set, "sweet");
    assert.strictEqual(mDefault.set, "sweet");
    assert.strictEqual(mSweet.piles.length, mDefault.piles.length);
    for (let i = 0; i < mSweet.piles.length; i++) {
        assert.strictEqual(mSweet.piles[i].role, mDefault.piles[i].role);
        assert.strictEqual(mSweet.piles[i].fx, mDefault.piles[i].fx);
        assert.strictEqual(mSweet.piles[i].exitStyle, mDefault.piles[i].exitStyle);
    }
});

test("NaN sweep", () => {
    const fullSong = longSong().concat(demo.map(e => Object.assign({}, e, { time: (e.time !== undefined ? e.time : 0) + 200 })));
    function sweep(m) {
        for (let t = 0; t < 230; t += 0.1) {
            finiteDeep(K.film(m, t), "film");
            for (const li of K.visibleAt(m.lines, t)) {
                const L = m.lines[li];
                finiteDeep(K.lineState(L, t, 880), "lineState");
                finiteDeep(K.camera(L, t, 880, 300), "camera");
                finiteDeep(K.peakState(L, t), "peakState");
                finiteDeep(K.peakPieces(L, t, 160, 40, 36), "peakPieces");
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
    // preset 7
    sweep(K.build(fullSong, { max: false }));
    // preset 8 over every set in SETS
    for (const set of Object.keys(K.SETS)) {
        sweep(K.build(fullSong, { max: true, set: set }));
        sweep(K.build(fullSong, { max: true, set: set, alwaysPeak: true }));
        sweep(K.build(fullSong, { max: true, set: set, peaks: "more", doodles: "lots", film: false }));
        sweep(K.build(fullSong, { max: true, set: set, doodles: "few" }));
    }
});

test("maximal cut never decodes, preset 7 still does", () => {
    const rows = [];
    for (let i = 0; i < 60; i++) rows.push([i * 2.5, FAST[i % 4]]);
    const ly = song(rows);
    assert.ok(!K.build(ly, { max: true }).lines.some(L => L.treat === "decode"));
    assert.ok(K.build(ly).lines.some(L => L.treat === "decode"));
    assert.ok(!K.build(demo, { max: true }).lines.some(L => L.treat === "decode"));
});

test("alwaysPeak makes every line a solo peak, only in preset 8", () => {
    const ly = song(Array.from({ length: 24 }, (_, i) => [i * 2.5, FAST[i % 4]]));
    for (const set of Object.keys(K.SETS)) {
        const m = K.build(ly, { max: true, set: set, alwaysPeak: true });
        assert.ok(m.lines.length > 0);
        m.lines.forEach(L => {
            assert.strictEqual(L.pile.role, "peak");
            assert.strictEqual(L.pile.lines.length, 1);
            assert.ok(L.pile.fx, "peak has a move");
        });
    }
    const off = K.build(ly, { max: true, set: "sweet" });
    assert.ok(off.lines.some(L => L.pile.role !== "peak"), "off by default");
    assert.ok(!K.build(ly, { alwaysPeak: true }).lines.some(L => L.pile.role === "peak"), "preset 7 untouched");
});

test("preset 8 options: peaks, doodles, film", () => {
    const ly = longSong();
    const count = (m, role) => m.piles.filter(P => P.role === role).length;
    const nat = K.build(ly, { max: true, set: "sweet" });
    const more = K.build(ly, { max: true, set: "sweet", peaks: "more" });
    const every = K.build(ly, { max: true, set: "sweet", peaks: "every" });
    assert.ok(count(more, "peak") > count(nat, "peak"), "more gives more peaks: " + count(nat, "peak") + " vs " + count(more, "peak"));
    assert.strictEqual(count(every, "peak"), every.lines.length);
    assert.ok(!more.piles.some((P, i) => i > 0 && P.role === "peak" && more.piles[i - 1].role === "peak"), "more never stacks two peaks");
    const dsum = m => m.lines.reduce((n, L) => n + L.doodles.length, 0);
    const few = K.build(ly, { max: true, set: "rough", doodles: "few" });
    const norm = K.build(ly, { max: true, set: "rough" });
    const lots = K.build(ly, { max: true, set: "rough", doodles: "lots" });
    assert.ok(dsum(few) < dsum(norm) && dsum(norm) < dsum(lots), [dsum(few), dsum(norm), dsum(lots)].join(" "));
    const off = K.build(ly, { max: true, film: false });
    const f = K.film(off, 12.3);
    assert.strictEqual(f.grain, 0);
    assert.strictEqual(f.scratchA, 0);
    assert.ok(K.film(nat, 12.3).grain > 0);
    // the old switch still means every line
    assert.strictEqual(count(K.build(ly, { max: true, alwaysPeak: true }), "peak"), every.lines.length);
});

let failed = 0;
for (const [name, fn] of tests) {
    try { fn(); console.log("ok " + name); }
    catch (e) { failed++; console.log("FAIL " + name + ": " + e.message); }
}
console.log((tests.length - failed) + "/" + tests.length + " passed");
process.exit(failed ? 1 : 0);
