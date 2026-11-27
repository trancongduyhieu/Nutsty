.pragma library
// Maximized-window frame (liner style): a thin band around the app with notches hanging from the
// top edge. Pure path builders, no access to `win`, so Node tests load this file as is
// (scripts/test_window_frame_logic.cjs). Paths are SVG strings for PathSvg.

var B = 6;    // band thickness
var H = 30;   // notch height below the band
var R = 8;    // concave flare where a notch meets the band
var BR = 15;  // convex bottom corners of a notch
var RC = 12;  // inner corners of the hole where no notch sits

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

// The hole's outline, clockwise from the top-left: flares sweep 1, notch bottoms sweep 0
function innerPath(W, Hh, leftW, centerW, rightW) {
    var L = B, T = B, Rr = W - B, Bt = Hh - B;
    var wl = notchOuterWidth("start", leftW);
    var wr = notchOuterWidth("end", rightW);
    var x1 = centerNotchX(W, leftW, centerW, rightW);
    var wc = notchOuterWidth("center", centerW);
    var a = function (r, sweep, x, y) { return " A " + r + " " + r + " 0 0 " + sweep + " " + x + " " + y; };
    var d = wl > 0 ? "M " + (L + wl) + " " + T : "M " + (L + RC) + " " + T;
    if (x1 >= 0) {
        d += " L " + x1 + " " + T + a(R, 1, x1 + R, T + R)
           + " V " + (T + H - BR) + a(BR, 0, x1 + R + BR, T + H)
           + " H " + (x1 + wc - R - BR) + a(BR, 0, x1 + wc - R, T + H - BR)
           + " V " + (T + R) + a(R, 1, x1 + wc, T);
    }
    if (wr > 0) {
        var x2 = Rr - wr;
        d += " L " + x2 + " " + T + a(R, 1, x2 + R, T + R)
           + " V " + (T + H - BR) + a(BR, 0, x2 + R + BR, T + H)
           + " H " + (Rr - R) + a(R, 1, Rr, T + H + R);
    } else {
        d += " L " + (Rr - RC) + " " + T + a(RC, 1, Rr, T + RC);
    }
    d += " V " + (Bt - RC) + a(RC, 1, Rr - RC, Bt)
       + " H " + (L + RC) + a(RC, 1, L, Bt - RC);
    if (wl > 0) {
        d += " V " + (T + H + R) + a(R, 1, L + R, T + H)
           + " H " + (L + wl - R - BR) + a(BR, 0, L + wl - R, T + H - BR)
           + " V " + (T + R) + a(R, 1, L + wl, T);
    } else {
        d += " V " + (T + RC) + a(RC, 1, L + RC, T);
    }
    return d + " Z";
}

// Outer rectangle plus the hole: filled with OddEvenFill this leaves only the band and notches
function framePath(W, Hh, leftW, centerW, rightW) {
    return "M 0 0 H " + W + " V " + Hh + " H 0 Z " + innerPath(W, Hh, leftW, centerW, rightW);
}
