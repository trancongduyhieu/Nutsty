// Unit tests for components/lossless_logic.js (Tidal lossless settings and Listen Along suspension):
//   node scripts/test_lossless_logic.cjs
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const src = fs.readFileSync(__dirname + '/../components/lossless_logic.js', 'utf8').replace(/^\.pragma.*$/m, '');
const L = vm.createContext({});
vm.runInContext(src, L);

assert.strictEqual(L.suspendTransition(false, true, true), "suspend");
assert.strictEqual(L.suspendTransition(true, false, true), "resume");
assert.strictEqual(L.suspendTransition(false, true, false), "");
assert.strictEqual(L.suspendTransition(true, false, false), "");
assert.strictEqual(L.suspendTransition(true, true, true), "");

assert.deepStrictEqual(Array.from(L.dacModesFor(true)), ["shared", "exclusive"]);
assert.deepStrictEqual(Array.from(L.dacModesFor(false)), ["shared", "rate_match", "exclusive"]);

assert.strictEqual(L.normalizeLosslessSettings({dacOutputMode: "rate_match"}, true).dacOutputMode, "shared");
assert.strictEqual(L.normalizeLosslessSettings({dacOutputMode: "rate_match"}, false).dacOutputMode, "rate_match");
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
