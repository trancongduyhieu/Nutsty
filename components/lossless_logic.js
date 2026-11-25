.pragma library
// Tidal lossless: pure helpers for settings and Listen Along suspension. No access to `win`,
// so Node tests load this file as is (scripts/test_lossless_logic.cjs).

var QUALITIES = ["lossless", "hires"];

// Co-listening changed. The suspension flag follows Listen Along whatever lossless is, so
// toggling lossless mid-session never leaves it stale or missing; notify only when lossless is on.
function suspendTransition(wasActive, isActive, losslessEnabled) {
    if (!!wasActive === !!isActive) return { command: "", notify: false };
    return { command: isActive ? "suspend" : "resume", notify: !!losslessEnabled };
}

// Windows has no PipeWire, so it cannot follow each song's sample rate.
function dacModesFor(isWindows) {
    return isWindows ? ["shared", "exclusive"] : ["shared", "rate_match", "exclusive"];
}

// Values read from nutsty_settings.json; anything unknown falls back to the default.
// losslessQualityChosen: the user picked a quality once, so login must not override it.
function normalizeLosslessSettings(obj, isWindows) {
    var o = (obj && typeof obj === "object") ? obj : {};
    var quality = QUALITIES.indexOf(o.losslessQuality) >= 0 ? o.losslessQuality : "lossless";
    var mode = dacModesFor(isWindows).indexOf(o.dacOutputMode) >= 0 ? o.dacOutputMode : "shared";
    return {
        losslessEnabled: o.losslessEnabled === true,
        losslessQuality: quality,
        dacOutputMode: mode,
        losslessQualityChosen: o.losslessQualityChosen === true || o.losslessQuality === "hires"
    };
}

// Quality to use after the first successful Tidal login.
function defaultQualityAfterLogin(status, qualityChosen, current) {
    if (qualityChosen) return current;
    return (status && status.can_hires) ? "hires" : "lossless";
}

// A plan without HiRes plays 16-bit FLAC even when "hires" was saved earlier.
function effectiveQuality(quality, status) {
    if (quality === "hires" && !(status && status.can_hires)) return "lossless";
    return QUALITIES.indexOf(quality) >= 0 ? quality : "lossless";
}

// Lossless or DAC mode changed. Only bit-perfect (exclusive) needs a new mpv and locks AutoMix;
// leaving lossless or bit-perfect puts AutoMix back as it was.
function dacTransition(prev, next) {
    var p = prev || {}, n = next || {};
    var wasExclusive = !!p.enabled && p.mode === "exclusive";
    var isExclusive = !!n.enabled && n.mode === "exclusive";
    return {
        restartMpv: wasExclusive !== isExclusive,
        autoMixLocked: isExclusive,
        restoreAutoMix: (wasExclusive && !isExclusive) || (!!p.enabled && !n.enabled)
    };
}
