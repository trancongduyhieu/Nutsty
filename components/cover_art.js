// Nutsty generated playlist covers: deterministic shapes from a name + a colour list.
// The first six layouts (marble, bauhaus, sunset, ring, pixel, beam) port the generators of
// boring-avatars (MIT License, Copyright (c) boringdesigners) from React/SVG to plain
// data that GeneratedCover.qml draws with Qt Quick Shapes. The other six (waves, stripes,
// tiles, dots, aurora, folds) are Nutsty's own and return a list of filled SVG paths.
.pragma library

var VARIANTS = ["marble", "bauhaus", "sunset", "ring", "pixel", "beam",
                "waves", "stripes", "tiles", "dots", "aurora", "folds"];

// Fixed palettes offered next to the live ones (wallpaper, now playing).
var PRESETS = [
    { id: "classic", colors: ["#92A1C6", "#146A7C", "#F0AB3D", "#C271B4", "#C20D90"] },
    { id: "sunset",  colors: ["#ff7e5f", "#feb47b", "#6a3093", "#a044ff", "#2c1e4a"] },
    { id: "sea",     colors: ["#0f2027", "#203a43", "#2c5364", "#5ec8d8", "#e0f7fa"] },
    { id: "matcha",  colors: ["#2d3a2e", "#7a9e7e", "#c7d6b5", "#f2efe4", "#d9a05b"] },
    { id: "neon",     colors: ["#ff006e", "#8338ec", "#3a86ff", "#ffbe0b", "#0b0014"] },
    { id: "peach",    colors: ["#6d6875", "#b5838d", "#e5989b", "#ffb4a2", "#ffcdb2"] },
    { id: "berry",    colors: ["#2b0f2e", "#5c1a4b", "#a4286a", "#e05780", "#ffb3c6"] },
    { id: "forest",   colors: ["#1b2b1f", "#2f4f3a", "#5b8c5a", "#cfd186", "#e3655b"] },
    { id: "desert",   colors: ["#3d2c2e", "#a0522d", "#d9a066", "#f4d6a0", "#7fb7be"] },
    { id: "retro",    colors: ["#264653", "#2a9d8f", "#e9c46a", "#f4a261", "#e76f51"] },
    { id: "lavender", colors: ["#1e1b3a", "#4a4e8f", "#8e8ce0", "#c8b6ff", "#ffd6e0"] },
    { id: "citrus",   colors: ["#1d3557", "#8ecae6", "#ffb703", "#fb8500", "#f1faee"] },
    { id: "midnight", colors: ["#0b132b", "#1c2541", "#3a506b", "#5bc0be", "#f2c14e"] },
    { id: "candy",    colors: ["#ff99c8", "#fcf6bd", "#d0f4de", "#a9def9", "#e4c1f9"] },
    { id: "mono",     colors: ["#111111", "#3a3a3a", "#7a7a7a", "#c4c4c4", "#f5f5f5"] }
];

function hashCode(name) {
    var hash = 0;
    for (var i = 0; i < name.length; i++) {
        hash = ((hash << 5) - hash) + name.charCodeAt(i);
        hash = hash & hash;
    }
    return Math.abs(hash);
}

function digit(n, ntn) { return Math.floor((n / Math.pow(10, ntn)) % 10); }
function bool(n, ntn) { return !(digit(n, ntn) % 2); }
function unit(n, range, index) {
    var v = n % range;
    return (index && digit(n, index) % 2 === 0) ? -v : v;
}
function pick(n, colors) { return colors[n % colors.length]; }

// ---------- colour maths (OKLCH, same matrices as backend/palette_extractor.py) ----------

function _toLin(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }
function _toSrgb(c) {
    c = Math.max(0, Math.min(1, c));
    return c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055;
}
function _rgb(hex) {
    var h = String(hex).replace("#", "");
    if (h.length === 8) h = h.substr(2);   // Qt "#aarrggbb"
    return [0, 2, 4].map(function (i) { return parseInt(h.substr(i, 2), 16) / 255; });
}
function _hex(rgb) {
    return "#" + rgb.map(function (v) {
        var s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16);
        return s.length < 2 ? "0" + s : s;
    }).join("");
}

function hexToOklch(hex) {
    var c = _rgb(hex).map(_toLin);
    var l = Math.cbrt(0.4122214708 * c[0] + 0.5363325363 * c[1] + 0.0514459929 * c[2]);
    var m = Math.cbrt(0.2119034982 * c[0] + 0.6806995451 * c[1] + 0.1073969566 * c[2]);
    var s = Math.cbrt(0.0883024619 * c[0] + 0.2817188376 * c[1] + 0.6299787005 * c[2]);
    var L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
    var A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
    var B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
    return { l: L, c: Math.sqrt(A * A + B * B), h: (Math.atan2(B, A) * 180 / Math.PI + 360) % 360 };
}

function oklchToHex(L, C, H) {
    var a = C * Math.cos(H * Math.PI / 180), b = C * Math.sin(H * Math.PI / 180);
    var l = Math.pow(L + 0.3963377774 * a + 0.2158037573 * b, 3);
    var m = Math.pow(L - 0.1055613458 * a - 0.0638541728 * b, 3);
    var s = Math.pow(L - 0.0894841775 * a - 1.2914855480 * b, 3);
    return _hex([
        4.0767434721 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    ].map(_toSrgb));
}

// Five swatches built from one colour: a lightness ladder plus its complement.
function harmony(hex) {
    var q = hexToOklch(hex), c = Math.max(q.c, 0.08);
    return [
        oklchToHex(0.30, c * 0.8, q.h),
        oklchToHex(0.48, c, q.h - 25),
        oklchToHex(0.66, c, q.h),
        oklchToHex(0.86, c * 0.5, q.h + 20),
        oklchToHex(0.72, c * 0.9, q.h + 180)
    ];
}

function contrast(hex) {
    var c = _rgb(hex);
    return (c[0] * 299 + c[1] * 587 + c[2] * 114) / 1000 >= 128 / 255 ? "#000000" : "#ffffff";
}

// ---------- layouts (all coordinates in each layout's own viewBox) ----------

function marble(name, colors) {
    var n = hashCode(name), S = 80, p = [];
    for (var i = 0; i < 3; i++) {
        p.push({
            color: pick(n + i, colors),
            tx: unit(n * (i + 1), S / 10, 1),
            ty: unit(n * (i + 1), S / 10, 2),
            scale: 1.2 + unit(n * (i + 1), S / 20) / 10,
            rotate: unit(n * (i + 1), 360, 1)
        });
    }
    p[1].scale = p[2].scale;   // upstream scales both shapes by the third element's scale
    return { size: S, bg: p[0].color, a: p[1], b: p[2] };
}

function bauhaus(name, colors) {
    var n = hashCode(name), S = 80, p = [];
    for (var i = 0; i < 4; i++) {
        p.push({
            color: pick(n + i, colors),
            tx: unit(n * (i + 1), S / 2 - (i + 17), 1),
            ty: unit(n * (i + 1), S / 2 - (i + 17), 2),
            rotate: unit(n * (i + 1), 360)
        });
    }
    return { size: S, bg: p[0].color, rect: p[1], rectSquare: bool(n, 2), circle: p[2], line: p[3] };
}

function sunset(name, colors) {
    var n = hashCode(name), c = [];
    for (var i = 0; i < 4; i++) c.push(pick(n + i, colors));
    return { size: 80, colors: c };
}

function ring(name, colors) {
    var n = hashCode(name), s = [];
    for (var i = 0; i < 5; i++) s.push(pick(n + i, colors));
    return { size: 90, colors: [s[0], s[1], s[1], s[2], s[2], s[3], s[3], s[0], s[4]] };
}

function pixel(name, colors) {
    var n = hashCode(name), cells = [], xs = [0, 20, 40, 60, 10, 30, 50, 70], k = 0, i, y;
    for (i = 0; i < xs.length; i++) cells.push({ x: xs[i], y: 0 });
    for (i = 0; i < xs.length; i++) for (y = 10; y < 80; y += 10) cells.push({ x: xs[i], y: y });
    for (k = 0; k < cells.length; k++) cells[k].color = pick(n % (k + 1), colors);
    return { size: 80, cells: cells };
}

function beam(name, colors) {
    var n = hashCode(name), S = 36;
    var wrapper = pick(n, colors);
    var px = unit(n, 10, 1), tx = px < 5 ? px + S / 9 : px;
    var py = unit(n, 10, 2), ty = py < 5 ? py + S / 9 : py;
    return {
        size: S,
        bg: pick(n + 13, colors),
        wrapper: wrapper,
        face: contrast(wrapper),
        tx: tx, ty: ty,
        rotate: unit(n, 360),
        scale: 1 + unit(n, S / 12) / 10,
        mouthOpen: bool(n, 2),
        round: bool(n, 1),
        eyeSpread: unit(n, 5),
        mouthSpread: unit(n, 3),
        faceRotate: unit(n, 10, 3),
        faceTx: tx > S / 6 ? tx / 2 : unit(n, 8, 1),
        faceTy: ty > S / 6 ? ty / 2 : unit(n, 7, 2)
    };
}


// ---------- Nutsty layouts: { size, bg, blur, layers: [{ color, path }] } ----------

// Seeded PRNG (mulberry32): the same name always draws the same picture
function rng(seed) {
    var a = seed >>> 0;
    return function () {
        a = (a + 0x6D2B79F5) >>> 0;
        var t = a;
        t = Math.imul(t ^ (t >>> 15), t | 1);
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

// Palette in a seeded order, so the background is not always the first colour
function shuffled(colors, r) {
    var c = colors.slice();
    for (var i = c.length - 1; i > 0; i--) {
        var j = Math.floor(r() * (i + 1)), t = c[i];
        c[i] = c[j]; c[j] = t;
    }
    return c;
}

function f(v) { return Math.round(v * 100) / 100; }
function circlePath(cx, cy, rad) {
    return "M" + f(cx - rad) + " " + f(cy) + "a" + f(rad) + " " + f(rad) + " 0 1 0 " + f(2 * rad) + " 0"
         + "a" + f(rad) + " " + f(rad) + " 0 1 0 " + f(-2 * rad) + " 0Z";
}
function polyPath(pts) {
    var out = "M" + f(pts[0][0]) + " " + f(pts[0][1]);
    for (var i = 1; i < pts.length; i++) out += "L" + f(pts[i][0]) + " " + f(pts[i][1]);
    return out + "Z";
}
function sectorPts(cx, cy, rad, a0, a1) {
    var pts = [[cx, cy]], n = 24;
    for (var i = 0; i <= n; i++) {
        var a = (a0 + (a1 - a0) * i / n) * Math.PI / 180;
        pts.push([cx + rad * Math.cos(a), cy + rad * Math.sin(a)]);
    }
    return pts;
}
// Paths that never overlap can share one Shape per colour
function merged(parts) {
    var by = {}, order = [];
    for (var i = 0; i < parts.length; i++) {
        if (!(parts[i].color in by)) { by[parts[i].color] = ""; order.push(parts[i].color); }
        by[parts[i].color] += parts[i].path;
    }
    return order.map(function (c) { return { color: c, path: by[c] }; });
}

function waves(name, colors) {
    var r = rng(hashCode(name)), c = shuffled(colors, r), layers = [];
    var bands = 4, freq = 1 + Math.floor(r() * 2) * 0.5;
    for (var i = 0; i < bands; i++) {
        var base = 18 + i * 17 + (r() - 0.5) * 6, amp = 2.5 + r() * 6, phase = r() * Math.PI * 2, pts = [];
        for (var x = 0; x <= 80; x += 2)
            pts.push([x, base + amp * Math.sin(phase + x / 80 * Math.PI * 2 * freq)]);
        pts.push([80, 80]); pts.push([0, 80]);
        layers.push({ color: c[(i + 1) % c.length], path: polyPath(pts) });
    }
    return { size: 80, bg: c[0], layers: layers };
}

function stripes(name, colors) {
    var r = rng(hashCode(name)), c = shuffled(colors, r), parts = [];
    var angles = [-60, -45, -30, 0, 30, 45, 60, 90], ang = angles[Math.floor(r() * angles.length)] * Math.PI / 180;
    var ca = Math.cos(ang), sa = Math.sin(ang);
    function pt(u, v) { return [40 + u * ca - v * sa, 40 + u * sa + v * ca]; }
    var u = -60, k = 0;
    while (u < 60) {
        var w = 5 + Math.floor(r() * 4) * 4;
        parts.push({ color: c[k % c.length], path: polyPath([pt(u, -60), pt(u + w, -60), pt(u + w, 60), pt(u, 60)]) });
        u += w; k++;
    }
    return { size: 80, bg: c[0], seal: true, layers: merged(parts) };
}

function tiles(name, colors) {
    var r = rng(hashCode(name)), c = shuffled(colors, r), g = r() < 0.5 ? 2 : 3, s = 80 / g, back = [], front = [];
    for (var ty = 0; ty < g; ty++) for (var tx = 0; tx < g; tx++) {
        var x = tx * s, y = ty * s, a = Math.floor(r() * c.length), b = (a + 1 + Math.floor(r() * (c.length - 1))) % c.length;
        back.push({ color: c[a], path: polyPath([[x, y], [x + s, y], [x + s, y + s], [x, y + s]]) });
        var kind = Math.floor(r() * 4), turn = Math.floor(r() * 4), pts;
        var corners = [[x, y, 0], [x + s, y, 90], [x + s, y + s, 180], [x, y + s, 270]];
        if (kind === 0) {           // quarter circle from a corner
            var cn = corners[turn];
            pts = sectorPts(cn[0], cn[1], s, cn[2], cn[2] + 90);
        } else if (kind === 1) {    // half circle on a side
            var mids = [[x + s / 2, y, 0], [x + s, y + s / 2, 90], [x + s / 2, y + s, 180], [x, y + s / 2, 270]], m = mids[turn];
            pts = sectorPts(m[0], m[1], s / 2, m[2], m[2] + 180);
        } else if (kind === 2) {    // triangle: half the tile
            var t0 = corners[turn], t1 = corners[(turn + 1) % 4], t2 = corners[(turn + 2) % 4];
            pts = [[t0[0], t0[1]], [t1[0], t1[1]], [t2[0], t2[1]]];
        } else {                    // centred circle
            front.push({ color: c[b], path: circlePath(x + s / 2, y + s / 2, s * 0.32) });
            continue;
        }
        front.push({ color: c[b], path: polyPath(pts) });
    }
    return { size: 80, bg: c[0], seal: true, layers: merged(back).concat(merged(front)) };
}

function dots(name, colors) {
    var r = rng(hashCode(name)), c = shuffled(colors, r), parts = [], n = 6 + Math.floor(r() * 3), sp = 80 / n;
    var ang = r() * Math.PI * 2, dx = Math.cos(ang), dy = Math.sin(ang);
    for (var j = 0; j < n; j++) for (var i = 0; i < n; i++) {
        var cx = (i + 0.5) * sp, cy = (j + 0.5) * sp;
        var t = Math.max(0, Math.min(1, 0.5 + ((cx - 40) * dx + (cy - 40) * dy) / 80));
        var rad = sp * 0.5 * (0.12 + 0.82 * t);
        parts.push({ color: t < 0.5 ? c[1] : c[2], path: circlePath(cx, cy, rad) });
    }
    return { size: 80, bg: c[0], layers: merged(parts) };
}

function aurora(name, colors) {
    var r = rng(hashCode(name)), c = shuffled(colors, r), layers = [];
    for (var i = 0; i < 4; i++)
        layers.push({ color: c[(i + 1) % c.length], path: circlePath(8 + r() * 64, 8 + r() * 64, 18 + r() * 16) });
    return { size: 80, bg: c[0], blur: true, layers: layers };
}

function folds(name, colors) {
    var r = rng(hashCode(name)), c = shuffled(colors, r), px = 18 + r() * 44, py = 18 + r() * 44;
    var sq = [[0, 0], [80, 0], [80, 80], [0, 80]], layers = [];
    for (var i = 0; i < 4; i++)
        layers.push({ color: c[i % c.length], path: polyPath([[px, py], sq[i], sq[(i + 1) % 4]]) });
    if (r() < 0.5) layers.push({ color: c[4 % c.length], path: circlePath(px, py, 5 + r() * 6) });
    return { size: 80, bg: c[0], seal: true, layers: layers };
}

function layout(variant, name, colors) {
    var cols = (colors && colors.length) ? colors : PRESETS[0].colors;
    var key = name || "Nutsty";
    switch (variant) {
    case "bauhaus": return bauhaus(key, cols);
    case "sunset": return sunset(key, cols);
    case "ring": return ring(key, cols);
    case "pixel": return pixel(key, cols);
    case "beam": return beam(key, cols);
    case "waves": return waves(key, cols);
    case "stripes": return stripes(key, cols);
    case "tiles": return tiles(key, cols);
    case "dots": return dots(key, cols);
    case "aurora": return aurora(key, cols);
    case "folds": return folds(key, cols);
    default: return marble(key, cols);
    }
}

// Local path from the backend (may be a Windows path) -> file URL for Image sources.
function fileUrl(path) {
    var p = String(path).replace(/\\/g, "/");
    return /^[A-Za-z]:\//.test(p) ? "file:///" + p : "file://" + p;
}
