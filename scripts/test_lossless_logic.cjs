// Unit tests for components/lossless_logic.js (Tidal lossless settings and Listen Along suspension):
//   node scripts/test_lossless_logic.cjs
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const src = fs.readFileSync(__dirname + '/../components/lossless_logic.js', 'utf8').replace(/^\.pragma.*$/m, '');
const L = vm.createContext({});
vm.runInContext(src, L);

const st = (a, b, c) => JSON.parse(JSON.stringify(L.suspendTransition(a, b, c)));
// The flag follows Listen Along whatever lossless is, so turning lossless on or off mid-session
// cannot leave it stale or missing; only the notice depends on lossless being on.
assert.deepStrictEqual(st(false, true, true), { command: "suspend", notify: true });
assert.deepStrictEqual(st(true, false, true), { command: "resume", notify: true });
assert.deepStrictEqual(st(false, true, false), { command: "suspend", notify: false });
assert.deepStrictEqual(st(true, false, false), { command: "resume", notify: false });
assert.deepStrictEqual(st(true, true, true), { command: "", notify: false });
assert.deepStrictEqual(st(false, false, true), { command: "", notify: false });

assert.deepStrictEqual(Array.from(L.dacModesFor(true)), ["shared", "exclusive"]);
// PipeWire refuses an exclusive stream while the shell keeps its own stream on the DAC
assert.deepStrictEqual(Array.from(L.dacModesFor(false)), ["shared", "rate_match"]);

assert.strictEqual(L.normalizeLosslessSettings({dacOutputMode: "rate_match"}, true).dacOutputMode, "shared");
assert.strictEqual(L.normalizeLosslessSettings({dacOutputMode: "rate_match", dacModeStandalone: true}, false).dacOutputMode, "rate_match");
// DAC mode no longer needs Tidal: local FLAC goes to the DAC too. A mode saved before that
// (no dacModeStandalone) only counted while lossless was on, so it stays off when lossless was off.
assert.strictEqual(L.normalizeLosslessSettings({dacOutputMode: "exclusive", losslessEnabled: false}, false).dacOutputMode, "shared");
assert.strictEqual(L.normalizeLosslessSettings({dacOutputMode: "exclusive", losslessEnabled: true}, true).dacOutputMode, "exclusive");
assert.strictEqual(L.normalizeLosslessSettings({dacOutputMode: "exclusive", dacModeStandalone: true}, true).dacOutputMode, "exclusive");
assert.strictEqual(L.normalizeLosslessSettings({dacOutputMode: "exclusive", dacModeStandalone: true}, false).dacOutputMode, "shared");
assert.strictEqual(L.normalizeLosslessSettings({losslessQuality: "ultra"}, false).losslessQuality, "lossless");
assert.strictEqual(L.normalizeLosslessSettings({losslessQuality: "hires"}, false).losslessQuality, "hires");
assert.deepStrictEqual(JSON.parse(JSON.stringify(L.normalizeLosslessSettings(null, false))),
    {losslessEnabled: false, losslessQuality: "lossless", dacOutputMode: "shared", losslessQualityChosen: false});
assert.strictEqual(L.normalizeLosslessSettings({losslessEnabled: "yes"}, false).losslessEnabled, false);
assert.strictEqual(L.normalizeLosslessSettings({losslessEnabled: true}, false).losslessEnabled, true);
assert.strictEqual(L.normalizeLosslessSettings({losslessQuality: "hires"}, false).losslessQualityChosen, true);

// first successful login picks the best quality the plan allows, unless the user already chose
assert.strictEqual(L.defaultQualityAfterLogin({can_hires: true}, false, "lossless"), "hires");
assert.strictEqual(L.defaultQualityAfterLogin({can_hires: false}, false, "lossless"), "lossless");
assert.strictEqual(L.defaultQualityAfterLogin({can_hires: true}, true, "lossless"), "lossless");
// a plan without hires never keeps hires
assert.strictEqual(L.effectiveQuality("hires", {can_hires: false}), "lossless");
assert.strictEqual(L.effectiveQuality("hires", {can_hires: true}), "hires");

console.log("ALL LOSSLESS LOGIC TESTS PASSED");

// --- dacTransition: the DAC mode alone decides, Tidal on or off does not matter ---
{
    const d = (a, b) => JSON.parse(JSON.stringify(L.dacTransition(a, b)));
    assert.deepStrictEqual(d({ mode: "shared" }, { mode: "exclusive" }),
        { restartMpv: true, autoMixLocked: true, restoreAutoMix: false });
    assert.deepStrictEqual(d({ mode: "exclusive" }, { mode: "shared" }),
        { restartMpv: true, autoMixLocked: false, restoreAutoMix: true });
    assert.deepStrictEqual(d({ mode: "shared" }, { mode: "rate_match" }),
        { restartMpv: false, autoMixLocked: false, restoreAutoMix: false });
    assert.deepStrictEqual(d({ mode: "exclusive" }, { mode: "exclusive" }),
        { restartMpv: false, autoMixLocked: true, restoreAutoMix: false });
    // turning Tidal off keeps the DAC mode, so nothing restarts and AutoMix stays as it is
    assert.deepStrictEqual(d({ enabled: true, mode: "exclusive" }, { enabled: false, mode: "exclusive" }),
        { restartMpv: false, autoMixLocked: true, restoreAutoMix: false });
    console.log("dacTransition: all passed");
}
