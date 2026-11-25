// node scripts/test_quality_label.cjs : the one formatter behind every quality label.
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const src = fs.readFileSync(path.join(__dirname, "..", "components", "quality_label.js"), "utf8")
    .replace(/^\.pragma library\s*$/m, "");
const Q = new Function(src + "\nreturn { formatQualityLabel, dashIfEmpty };")();
const vi = (a, b) => a, en = (a, b) => b;

const flac = { codec: "FLAC", lossless: true, bit_depth: 24, sample_rate: 96000, bitrate_kbps: 2800 };
assert.strictEqual(Q.formatQualityLabel(flac, en), "FLAC 24-bit · 96 kHz");
assert.strictEqual(Q.formatQualityLabel(Object.assign({}, flac, { output_rate: 48000 }), en), "FLAC 24-bit · 96 kHz → 48 kHz");
assert.strictEqual(Q.formatQualityLabel(Object.assign({}, flac, { via_windows_mixer: true }), vi), "FLAC 24-bit · 96 kHz · qua Windows");
assert.strictEqual(Q.formatQualityLabel(Object.assign({}, flac, { via_windows_mixer: true }), en), "FLAC 24-bit · 96 kHz · via Windows");
assert.strictEqual(Q.formatQualityLabel({ codec: "FLAC", lossless: true, bit_depth: null, sample_rate: 44100 }, en), "FLAC · 44.1 kHz");
assert.strictEqual(Q.formatQualityLabel({ codec: "OPUS", lossless: false, bitrate_kbps: 141, sample_rate: 48000 }, en), "OPUS · 141 kbps");
assert.strictEqual(Q.formatQualityLabel({ codec: "OPUS", lossless: false, bitrate_kbps: null }, en), "OPUS");
assert.strictEqual(Q.formatQualityLabel({ codec: "OPUS", lossless: false, bitrate_kbps: 141, lossless_suspended: true }, vi),
    "OPUS · 141 kbps · tạm tắt lossless khi Nghe Cùng");
assert.strictEqual(Q.formatQualityLabel({ codec: "OPUS", lossless: false, bitrate_kbps: 141, lossless_suspended: true }, en),
    "OPUS · 141 kbps · lossless paused for Listen Along");
assert.strictEqual(Q.formatQualityLabel({ codec: "" }, en), "");
assert.strictEqual(Q.formatQualityLabel(null, en), "");
assert.strictEqual(Q.dashIfEmpty(""), "—");
assert.strictEqual(Q.dashIfEmpty(undefined), "—");
assert.strictEqual(Q.dashIfEmpty("96 kHz"), "96 kHz");
console.log("quality_label: all passed");
