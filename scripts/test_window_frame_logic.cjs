// Unit tests for components/window_frame_logic.js (maximized-window frame and notches):
//   node scripts/test_window_frame_logic.cjs
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const src = fs.readFileSync(__dirname + '/../components/window_frame_logic.js', 'utf8').replace(/^\.pragma.*$/m, '');
const L = vm.createContext({});
vm.runInContext(src, L);

assert.strictEqual(L.B, 6); assert.strictEqual(L.H, 30); assert.strictEqual(L.R, 8);
assert.strictEqual(L.BR, 15); assert.strictEqual(L.RC, 12);

// Outer width of each notch kind for a given content width (content rounded up to even)
assert.strictEqual(L.notchOuterWidth("center", 228), 244);  // content + 2 flares
assert.strictEqual(L.notchOuterWidth("center", 227), 244);
assert.strictEqual(L.notchOuterWidth("end", 60), 68);       // content + 1 flare
assert.strictEqual(L.notchOuterWidth("start", 34), 42);
assert.strictEqual(L.notchOuterWidth("start", 0), 0);       // no notch at all

// Numbers of every command in path order, to check monotonic runs
function points(d) {
    const out = [];
    const re = /([MLHVAZ])([^MLHVAZ]*)/g; let m, x = 0, y = 0;
    while ((m = re.exec(d))) {
        const n = m[2].trim().split(/[\s,]+/).filter(Boolean).map(Number);
        if (m[1] === 'M' || m[1] === 'L') { x = n[0]; y = n[1]; }
        else if (m[1] === 'H') x = n[0];
        else if (m[1] === 'V') y = n[0];
        else if (m[1] === 'A') { x = n[5]; y = n[6]; }
        else continue;
        out.push({ c: m[1], x, y });
    }
    return out;
}

// No left notch: rounded top-left inner corner; outer rect present
let d = L.framePath(1600, 1000, 0, 228, 60);
assert.ok(d.startsWith('M 0 0 H 1600 V 1000 H 0 Z'), d);
let inner = L.innerPath(1600, 1000, 0, 228, 60);
assert.ok(inner.includes('A 12 12 0 0 1 18 6'), inner);          // top-left corner closes the hole
// center notch: x1 = 800 - 244/2 = 678, flare to 686,14, bottom at y = 36
assert.ok(inner.includes('L 678 6 A 8 8 0 0 1 686 14'), inner);
assert.ok(inner.includes('A 15 15 0 0 0 701 36'), inner);
// end notch flush with the right band, concave join into the right side
assert.ok(inner.includes('A 8 8 0 0 1 1594 44'), inner);
// bottom corners rounded
assert.ok(inner.includes('A 12 12 0 0 1 1582 994'), inner);
assert.ok(inner.includes('A 12 12 0 0 1 6 982'), inner);

// Left notch: no rounded top-left corner, concave join from the left side
inner = L.innerPath(1600, 1000, 34, 228, 60);
assert.ok(!inner.includes('A 12 12 0 0 1 18 6'), inner);
assert.ok(inner.includes('A 8 8 0 0 1 14 36'), inner);
assert.ok(inner.startsWith('M 48 6'), inner);                     // 6 + 42

// No notches at all: plain rounded hole
inner = L.innerPath(800, 600, 0, 0, 0);
assert.ok(inner.includes('A 12 12 0 0 1 794 18'), inner);

// Top edge never runs backwards (notches never overlap), even in a narrow window
for (const W of [1600, 600, 360, 200]) {
    const pts = points(L.innerPath(W, 500, 34, 228, 60)).filter(p => p.y <= 6 + 30 + 8);
    // walk until the path turns down the right side
    let lastX = -Infinity;
    for (const p of pts) {
        if (p.x >= W - 6) break;
        assert.ok(p.x >= lastX - 1e-6, `W=${W} top edge goes back at ${JSON.stringify(p)}`);
        lastX = p.x;
    }
}
// centerNotchX: centered normally, clamped between the side notches when the window is narrow
assert.strictEqual(L.centerNotchX(1600, 34, 228, 60), 678);
// 500 wide, 356 outer: centered (72) its right edge would run into the end notch (starts at 426)
assert.strictEqual(L.centerNotchX(500, 34, 340, 60), 426 - 356);
// Too narrow for all three: the center notch is dropped (-1) and the hole has no center dip
assert.strictEqual(L.centerNotchX(200, 34, 228, 60), -1);
// one convex bottom corner per side notch, none from the dropped center
assert.strictEqual((L.innerPath(200, 500, 34, 228, 60).match(/A 15 15 0 0 0/g) || []).length, 2);
assert.strictEqual((L.innerPath(1600, 1000, 34, 228, 60).match(/A 15 15 0 0 0/g) || []).length, 4);

// Windowed (24px outer corners): hole corners stay concentric, 24 - 6 = 18
inner = L.innerPath(800, 600, 0, 228, 60, 18);
assert.ok(inner.includes('A 18 18 0 0 1 24 6'), inner);
assert.ok(inner.includes('A 18 18 0 0 1 776 594'), inner);
assert.ok(L.framePath(800, 600, 0, 228, 60, 18).includes('A 18 18 0 0 1 24 6'));

// Expanded center notch (mood chips open): only the center dips deeper, by the extra height
inner = L.innerPath(1600, 1000, 0, 228, 60, 12, 44);
assert.ok(inner.includes('A 15 15 0 0 0 701 80'), inner);          // bottom at 6 + 30 + 44
assert.ok(inner.includes('V 65'), inner);                            // side runs down to 80 - 15
assert.ok(inner.includes('A 8 8 0 0 1 1594 44'), inner);            // right notch unchanged
assert.strictEqual(L.innerPath(1600, 1000, 0, 228, 60, 12, 0), L.innerPath(1600, 1000, 0, 228, 60, 12));

// The open center notch alone (band strip above it included), for a deeper tint while open
const cn = L.centerNotchPath(1600, 0, 228, 60, 44);
assert.ok(cn.startsWith('M 678 0 H 922'), cn);                       // 678 + 244
assert.ok(cn.includes('A 15 15 0 0 1 899 80'), cn);                  // right bottom corner, drawn the other way
assert.ok(cn.includes('A 8 8 0 0 0 678 6'), cn);
assert.strictEqual(L.centerNotchPath(200, 34, 228, 60, 44), '');      // dropped notch: nothing to tint

console.log('window_frame_logic: OK');
