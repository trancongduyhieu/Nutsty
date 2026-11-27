.pragma library
// Maximized-window frame (liner style): a thin band around the app with notches hanging from the
// top edge. Pure path builders, no access to `win`, so Node tests load this file as is
// (scripts/test_window_frame_logic.cjs). Paths are SVG strings for PathSvg.

var B = 6;    // band thickness
var H = 30;   // notch height below the band
var R = 8;    // concave flare where a notch meets the band
var BR = 15;  // convex bottom corners of a notch
var RC = 12;  // inner corners of the hole where no notch sits (maximized; windowed passes 24 - B)

function even(w) { return Math.ceil(Math.max(0, w) / 2) * 2; }

// Full width of a notch: the center one flares on both sides, the side ones on their inner side only
function notchOuterWidth(kind, contentW) {
    if (!(contentW > 0)) return 0;
    return even(contentW) + (kind === "center" ? 2 * R : R);
}

// Left x of the center notch: centered, pushed clear of the side notches, -1 when it cannot fit
function centerNotchX(W, leftW, centerW, rightW) {
    var wc = notchOuterWidth("center", centerW);
    if (wc <= 0) return -1;
    var lo = B + notchOuterWidth("start", leftW);
    var hi = W - B - notchOuterWidth("end", rightW) - wc;
    if (hi < lo) return -1;
    return Math.max(lo, Math.min(hi, Math.round(W / 2 - wc / 2)));
}

// The hole's outline, clockwise from the top-left: flares sweep 1, notch bottoms sweep 0.
// rc: the hole's own corner radius, concentric with the window's (defaults to RC).
// centerExtra: how much deeper the center notch reaches while it is open (mood chips)
// cbr: the center notch's bottom corner radius (defaults to BR; it grows while the notch is open)
function innerPath(W, Hh, leftW, centerW, rightW, rc, centerExtra, cbr) {
    var hc = H + (centerExtra > 0 ? centerExtra : 0);
    var CB = cbr > 0 ? cbr : BR;
    var C = rc > 0 ? rc : RC;
    var L = B, T = B, Rr = W - B, Bt = Hh - B;
    var wl = notchOuterWidth("start", leftW);
    var wr = notchOuterWidth("end", rightW);
    var x1 = centerNotchX(W, leftW, centerW, rightW);
    var wc = notchOuterWidth("center", centerW);
    var a = function (r, sweep, x, y) { return " A " + r + " " + r + " 0 0 " + sweep + " " + x + " " + y; };
    var d = wl > 0 ? "M " + (L + wl) + " " + T : "M " + (L + C) + " " + T;
    if (x1 >= 0) {
        d += " L " + x1 + " " + T + a(R, 1, x1 + R, T + R)
           + " V " + (T + hc - CB) + a(CB, 0, x1 + R + CB, T + hc)
           + " H " + (x1 + wc - R - CB) + a(CB, 0, x1 + wc - R, T + hc - CB)
           + " V " + (T + R) + a(R, 1, x1 + wc, T);
    }
    if (wr > 0) {
        var x2 = Rr - wr;
        d += " L " + x2 + " " + T + a(R, 1, x2 + R, T + R)
           + " V " + (T + H - BR) + a(BR, 0, x2 + R + BR, T + H)
           + " H " + (Rr - R) + a(R, 1, Rr, T + H + R);
    } else {
        d += " L " + (Rr - C) + " " + T + a(C, 1, Rr, T + C);
    }
    d += " V " + (Bt - C) + a(C, 1, Rr - C, Bt)
       + " H " + (L + C) + a(C, 1, L, Bt - C);
    if (wl > 0) {
        d += " V " + (T + H + R) + a(R, 1, L + R, T + H)
           + " H " + (L + wl - R - BR) + a(BR, 0, L + wl - R, T + H - BR)
           + " V " + (T + R) + a(R, 1, L + wl, T);
    } else {
        d += " V " + (T + C) + a(C, 1, L + C, T);
    }
    return d + " Z";
}

// Outer rectangle plus the hole: filled with OddEvenFill this leaves only the band and notches
function framePath(W, Hh, leftW, centerW, rightW, rc, centerExtra, cbr) {
    return "M 0 0 H " + W + " V " + Hh + " H 0 Z " + innerPath(W, Hh, leftW, centerW, rightW, rc, centerExtra, cbr);
}

// The center notch on its own, with the band strip above it, outlined clockwise: drawn over the
// frame with a deeper tint while the notch is open, so it reads as one solid island ("" if dropped)
function centerNotchPath(W, leftW, centerW, rightW, centerExtra, cbr) {
    var x1 = centerNotchX(W, leftW, centerW, rightW);
    if (x1 < 0) return "";
    var wc = notchOuterWidth("center", centerW), T = B, CB = cbr > 0 ? cbr : BR;
    var hc = H + (centerExtra > 0 ? centerExtra : 0);
    var a = function (r, sweep, x, y) { return " A " + r + " " + r + " 0 0 " + sweep + " " + x + " " + y; };
    return "M " + x1 + " 0 H " + (x1 + wc) + " V " + T + a(R, 0, x1 + wc - R, T + R)
        + " V " + (T + hc - CB) + a(CB, 1, x1 + wc - R - CB, T + hc)
        + " H " + (x1 + R + CB) + a(CB, 1, x1 + R, T + hc - CB)
        + " V " + (T + R) + a(R, 0, x1, T) + " Z";
}

// One frame of a damped spring toward `target` (mass 1), parameterised like SwiftUI's
// .spring(response:dampingFraction:) that boring.notch uses: open (0.42, 0.8) settles with a
// ~1.5% overshoot, close (0.45, 1.0) with none. Semi-implicit Euler in <= 4 ms substeps keeps it
// stable on long frames; velocity carries over, so reversing mid-flight stays smooth. Returns [x, v].
function springStep(x, v, target, response, damping, dt) {
    var k = Math.pow(2 * Math.PI / response, 2), c = 4 * Math.PI * damping / response;
    var t = Math.min(Math.max(dt, 0), 0.1), n = Math.max(1, Math.ceil(t / 0.004)), h = t / n;
    for (var i = 0; i < n; ++i) {
        v += (-k * (x - target) - c * v) * h;
        x += v * h;
    }
    return [x, v];
}
