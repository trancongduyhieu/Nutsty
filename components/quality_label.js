.pragma library
// One formatter for every quality label. specs comes from the player status (audio_specs);
// tr is I18n.tr. Unknown values are left out, never guessed. Tested by scripts/test_quality_label.cjs.

function _khz(rate) {
    return (Math.round(rate / 100) / 10) + " kHz";
}

function formatQualityLabel(specs, tr) {
    if (!specs || !specs.codec) return "";
    var parts = [];
    if (specs.lossless) {
        parts.push(specs.bit_depth ? specs.codec + " " + specs.bit_depth + "-bit" : specs.codec);
        if (specs.sample_rate) {
            var rate = _khz(specs.sample_rate);
            if (specs.output_rate) rate += " → " + _khz(specs.output_rate);
            parts.push(rate);
        }
        if (specs.via_windows_mixer) parts.push(tr("qua Windows", "via Windows"));
    } else {
        parts.push(specs.codec);
        if (specs.bitrate_kbps) parts.push(specs.bitrate_kbps + " kbps");
    }
    if (specs.lossless_suspended) parts.push(tr("tạm tắt lossless khi Nghe Cùng", "lossless paused for Listen Along"));
    return parts.join(" · ");
}

function dashIfEmpty(value) {
    return (value === undefined || value === null || value === "") ? "—" : String(value);
}
