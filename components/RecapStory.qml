import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import QtMultimedia

// The monthly recap, opened by scratching the barcode on the back of the listener card.
// Ported from Mochy Music's recap story (RecapStory.kt, RecapStoryPages.kt, RecapVisuals.kt,
// GPL-3.0): the same backdrop of giant sliding words over a dot grid, a slow mesh gradient taken
// from the cover art once the colour arrives, the avatar and logo travelling between pages, lines
// that rise in one after another, odometer numbers, the artist slot machine, the tilted cover grid,
// the torn receipt and the card at the end.
//
// Pages: 0 hello, 1 journey, 2 month, 3 weekday, 4 top artist, 5 top song, 6 bill, 7 ending.
// Right arrow, Space or a click moves on; left arrow or a click on the left third goes back; Esc
// closes. Data: GET /api/listening/recap.
Item {
    id: root

    property var recap: null
    property string userName: ""
    property string avatarUrl: ""
    property string cardNumber: ""
    property double joinedAt: 0
    property color accentColor: Theme.accent
    property bool liteMode: false
    property string apiUrl: "http://127.0.0.1:17890"
    property real cornerRadius: Theme.radiusApp
    // true from open() until close(): the host pauses the player and hides its bar meanwhile
    property bool active: false
    signal closeRequested()
    // the last page's tap: the host collapses its header, then calls flyHome(itsCard)
    signal finishRequested()

    readonly property int pageCount: 8
    property int page: 0
    property int lastPage: -1
    property real shown: 0

    // the blink's lids and the cards in flight show while the story itself is faded out
    property real lid: 0
    property real intro: 0          // the card floating in after the blink
    property real introFly: 0       // 0..1: its swoop off to the right
    property rect introFrom: Qt.rect(0, 0, 0, 0)
    property bool homing: false     // the ending card is flying back to the header
    property real homeT: 0
    property rect homeFrom: Qt.rect(0, 0, 0, 0)
    property rect homeTo: Qt.rect(0, 0, 0, 0)
    visible: shown > 0.001 || lid > 0.001 || intro > 0.001 || homing
    enabled: shown > 0.5
    focus: visible

    // --- Geometry: Mochy's 852dp-tall phone mock, mapped onto this window ------------------------
    readonly property real u: Math.max(0.75, Math.min(1.7, height / 852))
    function fy(v) { return v / 852 * root.height; }
    readonly property real inset: Math.max(36 * u, width * 0.05)
    readonly property real topPad: 10 * u
    readonly property real column: Math.min(width - 2 * inset, 560 * u)
    // a landscape window puts the picture and its words side by side, as one centred group
    readonly property real stageW: Math.min(width - 2 * inset, 1040 * u)
    readonly property real heroSize: Math.min(300 * u, height * 0.4)
    readonly property bool wide: width - 2 * inset >= heroSize + 64 * u + 360 * u
    readonly property real textW: Math.min(460 * u, stageW - heroSize - 64 * u)
    readonly property real groupW: heroSize + 64 * u + textW
    readonly property real groupX: (width - groupW) / 2
    readonly property real heroCx: groupX + heroSize / 2
    readonly property real heroCy: height / 2 + 10 * u
    readonly property real textX: groupX + heroSize + 64 * u
    readonly property real chipD: Math.max(80 * u, heroSize * 0.34)
    readonly property real aGap: chipD + 76 * u
    readonly property real aTextW: Math.min(460 * u, stageW - heroSize - aGap)
    readonly property real aGroupX: (width - heroSize - aGap - aTextW) / 2
    readonly property real aHeroCx: aGroupX + heroSize / 2
    readonly property real aTextX: aGroupX + heroSize + aGap

    // --- Motion helpers (RecapVisuals.kt) ------------------------------------------------------
    function clamp01(t) { return Math.max(0, Math.min(1, t)); }
    function eoc(t) { t = clamp01(t); return 1 - (1 - t) * (1 - t) * (1 - t); }
    function eic(t) { t = clamp01(t); return t * t * t; }
    function eioc(t) { t = clamp01(t); return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; }
    function eob(t, o) { t = clamp01(t); var c3 = o + 1; return 1 + c3 * Math.pow(t - 1, 3) + o * Math.pow(t - 1, 2); }
    function lerp(a, b, t) { return a + (b - a) * t; }
    function stagger(p, i, n, len) {
        if (len === undefined) len = 0.55;
        if (n <= 1) return clamp01(p);
        var start = i * (1 - len) / (n - 1);
        return clamp01((p - start) / len);
    }
    function mix(a, b, t) { return Qt.rgba(lerp(a.r, b.r, t), lerp(a.g, b.g, t), lerp(a.b, b.b, t), lerp(a.a, b.a, t)); }
    // Line i of n: rises in (or slides in from enterFrom) and slides out to exitTo, in mock dp
    function lmA(a, i, n) { return root.eoc(root.stagger(a.enter, i, n)) * (1 - root.eic(root.stagger(a.exit, i, n, 0.7))); }
    function lmX(a, i, n, from, to) {
        if (to === undefined) to = -110;
        return (1 - root.eoc(root.stagger(a.enter, i, n))) * (from || 0) * root.u + root.eic(root.stagger(a.exit, i, n, 0.7)) * to * root.u;
    }
    function lmY(a, i, n, rise) { return (1 - root.eoc(root.stagger(a.enter, i, n))) * (rise === undefined ? 26 : rise) * root.u; }

    readonly property var curveStd: [0.4, 0, 0.2, 1, 1, 1]          // FastOutSlowIn
    readonly property var curveEmph: [0.2, 0, 0, 1, 1, 1]           // Emphasized
    readonly property var curveEmphAcc: [0.3, 0, 0.8, 0.15, 1, 1]   // EmphasizedAccelerate
    // starts at full speed (no crawl while the column slides in), then a long settle onto the hero
    readonly property var curveSpin: [0.22, 0.55, 0.12, 1, 1, 1]
    readonly property real speed: liteMode ? 0 : 1

    // A tween on any property, like Mochy's Animatable.go(): one per target and property
    property var tweens: []
    Component {
        id: tweenComp
        SequentialAnimation {
            id: tw
            property var tgt: null
            property string prop: ""
            property real to: 0
            property int ms: 300
            property int wait: 0
            property var curve: null
            PauseAnimation { duration: tw.wait }
            NumberAnimation {
                target: tw.tgt; property: tw.prop; to: tw.to; duration: tw.ms
                easing.type: tw.curve ? Easing.BezierSpline : Easing.Linear
                easing.bezierCurve: tw.curve ? tw.curve : []
            }
            onStopped: {
                var i = root.tweens.indexOf(tw);
                if (i >= 0) root.tweens.splice(i, 1);
                tw.destroy();
            }
        }
    }
    function go(tgt, prop, to, ms, wait, curve) {
        for (var i = root.tweens.length - 1; i >= 0; i--)
            if (root.tweens[i].tgt === tgt && root.tweens[i].prop === prop) root.tweens[i].stop();
        if (root.speed === 0 || (ms || 0) <= 0) { tgt[prop] = to; return; }
        var a = tweenComp.createObject(root, { tgt: tgt, prop: prop, to: to, ms: ms, wait: wait || 0,
                                               curve: curve === undefined ? root.curveStd : curve });
        root.tweens.push(a);
        a.start();
    }
    function stopTweens() {
        var list = root.tweens.slice();
        for (var i = 0; i < list.length; i++) list[i].stop();
    }

    // Clock for the drifting words, the mesh and the sheens
    property real time: 0
    FrameAnimation {
        running: root.visible && !root.liteMode
        onTriggered: root.time += frameTime
    }

    // --- Data --------------------------------------------------------------------------------
    readonly property var stats: root.recap && root.recap.stats ? root.recap.stats : null
    readonly property var songs: root.stats ? root.stats.top_songs || [] : []
    readonly property var artists: root.stats ? root.stats.top_artists || [] : []
    readonly property var heroSong: root.songs.length > 0 ? root.songs[0] : null
    // the cover wall on the song page: the top song in the middle, then every other cover played this month
    readonly property var gridSongs: {
        if (!root.heroSong) return [];
        var out = [root.heroSong], seen = {};
        seen[root.heroSong.cover_url || ""] = true;
        var pool = (root.stats && root.stats.grid_songs ? root.stats.grid_songs : []).concat(root.songs);
        for (var i = 0; i < pool.length; i++) {
            var c = pool[i].cover_url || "";
            if (c === "" || seen[c]) continue;
            seen[c] = true;
            out.push(pool[i]);
        }
        return out;
    }
    readonly property var heroArtist: root.artists.length > 0 ? root.artists[0] : null
    readonly property bool hasArtist: root.heroArtist !== null
    readonly property bool hasSong: root.heroSong !== null
    readonly property var numberLocale: Qt.locale(I18n.locale === "vi" ? "vi_VN" : "en_US")

    readonly property string monthName: {
        if (!root.stats) return "";
        return I18n.locale === "vi" ? "Tháng " + root.stats.month
                                    : Qt.locale("en_US").standaloneMonthName(root.stats.month - 1);
    }
    function hoursMinutes(min) {
        min = Math.max(0, Math.round(min || 0));
        return Math.floor(min / 60) + "h " + (min % 60) + "m";
    }
    function hoursDecimal(min) {
        return Number((min || 0) / 60).toLocaleString(root.numberLocale, "f", 1) + "h";
    }
    readonly property var weekdayNames: I18n.locale === "vi"
        ? ["Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy", "Chủ Nhật"]
        : ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    readonly property var weekdays: root.stats ? root.stats.weekday_minutes || [0, 0, 0, 0, 0, 0, 0] : [0, 0, 0, 0, 0, 0, 0]
    readonly property int favouriteDay: {
        var best = 0;
        for (var i = 1; i < 7; i++) if (root.weekdays[i] > root.weekdays[best]) best = i;
        return best;
    }
    readonly property int runnerUpMinutes: {
        var second = 0;
        for (var i = 0; i < 7; i++) if (i !== root.favouriteDay) second = Math.max(second, root.weekdays[i]);
        return second;
    }
    readonly property string dayWord: root.weekdayNames[root.favouriteDay].toUpperCase()
    // the song behind the artist page: the hero artist's most played song, unless that is the #1
    // song, which the next page reveals - then their next song in the top ten, or none (no chip,
    // no music) so the reveal is not given away
    readonly property var heroArtistSong: {
        if (!root.heroArtist || !root.heroArtist.top_song) return null;
        for (var i = 0; i < root.songs.length; i++) {
            var s = root.songs[i];
            if (s !== root.heroSong && s.artist === root.heroArtist.artist) return s;
        }
        var tid = root.heroArtist.top_song_track_id || "";
        if (root.artistOwnsHeroSong) return root.artistPick;
        return { title: root.heroArtist.top_song, cover_url: root.heroArtist.top_song_cover || "",
                 track_id: tid, plays: 0 };
    }
    // the hero artist's only song in the top ten is the #1 song itself
    readonly property bool artistOwnsHeroSong: {
        if (!root.heroArtist || !root.heroSong) return false;
        for (var i = 1; i < root.songs.length; i++)
            if (root.songs[i].artist === root.heroArtist.artist) return false;
        return root.heroSong.artist === root.heroArtist.artist
            || (root.heroArtist.top_song_track_id || "") === root.heroSong.track_id;
    }
    // then a popular song of theirs the listener has not played this month stands in, from the catalog
    property var artistPick: null
    property bool artistPickBusy: false
    function fetchArtistPick() {
        root.artistPick = null;
        if (!root.artistOwnsHeroSong || root.artistPickBusy) return;
        root.artistPickBusy = true;
        var artist = root.heroArtist.artist, xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            root.artistPickBusy = false;
            if (xhr.status !== 200) return;
            try {
                var r = JSON.parse(xhr.responseText);
                if (!r.success || !r.track_id || !root.heroArtist || root.heroArtist.artist !== artist) return;
                root.artistPick = { title: r.title, cover_url: r.cover_url || "", track_id: r.track_id,
                                    plays: r.plays || 0, fresh: r.fresh !== false };
                root.resolveSnippet(r.track_id);
            } catch (e) {}
        };
        xhr.open("GET", root.apiUrl + "/api/listening/artist_song?artist=" + encodeURIComponent(artist)
                 + "&exclude=" + encodeURIComponent(root.heroSong.title || "")
                 + "&exclude_id=" + encodeURIComponent(root.heroSong.track_id || "")
                 + "&year=" + (root.stats.year || 0) + "&month=" + (root.stats.month || 0));
        xhr.send();
    }
    // the artist's own photo; the cover of their top song only when no photo was found
    function photoOf(a) { return a ? (a.photo_url || a.cover_url || "") : ""; }
    readonly property string heroSongArtistCover: {
        if (!root.heroSong) return "";
        for (var i = 0; i < root.artists.length; i++)
            if (root.artists[i].artist === root.heroSong.artist) return root.photoOf(root.artists[i]) || root.heroSong.cover_url || "";
        return root.heroSong.cover_url || "";
    }

    // --- Shared animated state (StoryState) ------------------------------------------------
    property real textRotation: 90
    property real textScale: 1
    property real textCenterX: 0.86
    // where the page header's giant NUTSTY stands (x of its cap centre, in this item) and its cap height;
    // the column opens and closes there so the warp starts from the word you were looking at
    property real columnX: -1
    property real columnCap: 0
    readonly property real homeCenterX: columnX > 0 && width > 0 ? columnX / width : 0.86
    readonly property real homeScale: columnCap > 0 ? columnCap / (0.727 * 178 * root.u) : 1
    property real textOffsetY: 0
    property real textAlpha: 1
    property real dots: 1
    property real mesh: 0
    property real logoSide: 0
    property real avX: width / 2
    property real avY: height * 0.43
    property real avD: 127 * u
    property real avAlpha: 0
    property real avPop: 0
    property real avRing: 0
    property real avRingAlpha: 1
    // the artist slot machine and the cover grid
    property real spin: 0
    property real spinGlow: 0
    property real heroMove: 0
    property real gridDrift: 0
    property real gridPick: 0
    property real heroCover: 0
    property real heroCoverUp: 0

    component PageAnim: QtObject {
        property real enter: 0
        property real exit: 0
    }
    PageAnim { id: pHey }
    PageAnim { id: pJourney }
    PageAnim { id: pMonth }
    PageAnim { id: pWeek }
    PageAnim { id: pSpin }
    PageAnim { id: pArtist }
    PageAnim { id: pGrid }
    PageAnim { id: pMelody }
    PageAnim { id: pSong }
    PageAnim { id: pBill }
    PageAnim { id: pEnd }
    function pageAnims(k) {
        return [[pHey], [pJourney], [pMonth], [pWeek], [pSpin, pArtist], [pGrid, pMelody, pSong], [pBill], [pEnd]][k] || [];
    }
    function shows(a) { return a.enter > 0 && a.exit < 1; }

    // --- Palettes taken from the cover art (RecapPalettes) ------------------------------------
    readonly property var fallbackPalette: [Qt.color("#732C2A"), Qt.color("#7A3B26"), Qt.color("#4E1D1C"), Qt.color("#6B3324")]
    property var artistPalette: fallbackPalette
    property var songPalette: fallbackPalette
    property var palFrom: fallbackPalette
    property var palTo: fallbackPalette
    property real palMix: 1
    readonly property color m0: mix(palFrom[0], palTo[0], palMix)
    readonly property color m1: mix(palFrom[1], palTo[1], palMix)
    readonly property color m2: mix(palFrom[2], palTo[2], palMix)
    readonly property color m3: mix(palFrom[3], palTo[3], palMix)
    function crossfadePalette(to, ms) {
        if (root.spreading) { spreadAnim.stop(); root.commitSpread(); }
        root.palFrom = [root.m0, root.m1, root.m2, root.m3];
        root.palTo = to;
        root.palMix = 0;
        root.go(root, "palMix", 1, ms);
    }
    // the pick's colour change: the new palette bleeds from (x, y) over the frame, then becomes
    // the mesh's own. Lite mode, or a frame with no mesh yet, gets the plain crossfade.
    property var spreadPal: fallbackPalette
    property real spreadX: 0
    property real spreadY: 0
    property real spreadR: 0
    property bool spreading: false
    property real spreadSeed: 0
    function spreadPalette(to, x, y) {
        spreadAnim.stop();
        if (root.liteMode || root.mesh < 0.05 || root.speed === 0) { root.crossfadePalette(to, 1400); return; }
        if (root.spreading) root.commitSpread();
        // x and y are functions, so the spread keeps its centre on the photo while it moves
        root.spreadPal = to; root.spreadX = Qt.binding(x); root.spreadY = Qt.binding(y); root.spreadR = 0;
        root.spreadSeed = Math.random() * 100;
        root.spreading = true;
        spreadAnim.start();
    }
    function commitSpread() {
        root.palFrom = root.spreadPal; root.palTo = root.spreadPal; root.palMix = 1;
        root.spreading = false; root.spreadR = 0; root.spreadX = 0; root.spreadY = 0;
    }
    SequentialAnimation {
        id: spreadAnim
        // the shader eases each drop out on its own (fast when wet, slow as it dries); this curve
        // only lets the first touch of the brush linger a beat before the ink runs
        NumberAnimation { target: root; property: "spreadR"; from: 0; to: 1; duration: 2200 * Math.max(0.3, root.speed); easing.type: Easing.BezierSpline; easing.bezierCurve: [0.3, 0, 0.6, 1, 1, 1] }
        ScriptAction { script: root.commitSpread() }
    }
    // brightened copies for text: the mesh tones are too dark to read on the mesh
    function textTone(c) {
        return Qt.hsla(c.hslHue < 0 ? 0 : c.hslHue, Math.min(0.95, c.hslSaturation + 0.2), 0.78, 1);
    }
    // --- OKLAB palette (same recipe as backend/palette_extractor.py: chroma filter, k-means, salience) ---
    function lin(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }
    function gam(c) { c = Math.max(0, Math.min(1, c)); return c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055; }
    function oklab(r, g, b) {
        var lr = lin(r), lg = lin(g), lb = lin(b);
        var l = Math.cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb);
        var m = Math.cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb);
        var q = Math.cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb);
        return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * q,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * q,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * q];
    }
    function oklch(L, C, h) {
        var a = C * Math.cos(h), b = C * Math.sin(h);
        var l = Math.pow(L + 0.3963377774 * a + 0.2158037573 * b, 3);
        var m = Math.pow(L - 0.1055613458 * a - 0.0638541728 * b, 3);
        var q = Math.pow(L - 0.0894841775 * a - 1.2914855480 * b, 3);
        return Qt.rgba(gam(4.0767434721 * l - 3.3077115913 * m + 0.2309699292 * q),
                       gam(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * q),
                       gam(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * q), 1);
    }
    function kmeans(pts, k) {
        var cs = [pts[0]];
        while (cs.length < k) {
            var bp = pts[0], bd = -1;
            for (var i = 0; i < pts.length; i += 3) {
                var d = 1e9;
                for (var c = 0; c < cs.length; c++)
                    d = Math.min(d, Math.pow(pts[i][0] - cs[c][0], 2) + Math.pow(pts[i][1] - cs[c][1], 2) + Math.pow(pts[i][2] - cs[c][2], 2));
                if (d > bd) { bd = d; bp = pts[i]; }
            }
            cs.push(bp);
        }
        var sums = [];
        for (var it = 0; it < 8; it++) {
            sums = [];
            for (var z = 0; z < k; z++) sums.push([0, 0, 0, 0]);
            for (var j = 0; j < pts.length; j++) {
                var best = 0, dist = 1e9;
                for (var n = 0; n < k; n++) {
                    var e = Math.pow(pts[j][0] - cs[n][0], 2) + Math.pow(pts[j][1] - cs[n][1], 2) + Math.pow(pts[j][2] - cs[n][2], 2);
                    if (e < dist) { dist = e; best = n; }
                }
                sums[best][0] += pts[j][0]; sums[best][1] += pts[j][1]; sums[best][2] += pts[j][2]; sums[best][3]++;
            }
            for (var w = 0; w < k; w++) if (sums[w][3] > 0) cs[w] = [sums[w][0] / sums[w][3], sums[w][1] / sums[w][3], sums[w][2] / sums[w][3]];
        }
        var out = [];
        for (var v = 0; v < k; v++) if (sums[v][3] > 0) out.push({ L: cs[v][0], C: Math.hypot(cs[v][1], cs[v][2]), h: Math.atan2(cs[v][2], cs[v][1]), n: sums[v][3] });
        return out;
    }
    // four mesh tones from the cover: the most salient hue (count^0.35 * chroma) carries the base and
    // the bright blob, the next clusters keep their own hues for the other blobs. Lightness is fixed
    // low so white type always reads; a colourless cover keeps a faint warm cast instead of grey.
    // A portrait (the artist photo) is read by its backdrop instead: the side and top ring of the
    // upper part is almost always wall, sky or studio light, while the middle is skin and clothes
    // that would turn every artist brown. A backdrop with any hue at all leads the mesh.
    function paletteOf(data, side, portrait) {
        var all = [], chromatic = [];
        var bL = 0, bA = 0, bB = 0, bN = 0;
        for (var i = 0; i < data.length; i += 4) {
            if (data[i + 3] < 128) continue;
            var p = root.oklab(data[i] / 255, data[i + 1] / 255, data[i + 2] / 255);
            all.push(p);
            if (Math.hypot(p[1], p[2]) >= 0.028) chromatic.push(p);
            var x = (i / 4) % side, y = Math.floor(i / 4 / side);
            if (portrait && y < side * 0.62 && Math.min(x, y, side - 1 - x) < side / 6) {
                bL += p[0]; bA += p[1]; bB += p[2]; bN++;
            }
        }
        if (portrait && bN > 0 && Math.hypot(bA / bN, bB / bN) >= 0.008) {
            var bC = Math.hypot(bA / bN, bB / bN), bh = Math.atan2(bB / bN, bA / bN);
            function k(x, lo, hi, f) { return Math.max(lo, Math.min(hi, x * f)); }
            return [root.oklch(0.30, k(bC, 0.05, 0.10, 1.6), bh),
                    root.oklch(0.42, k(bC, 0.09, 0.15, 2.2), bh),
                    root.oklch(0.21, k(bC, 0.04, 0.09, 1.4), bh - 0.35),
                    root.oklch(0.35, k(bC, 0.05, 0.10, 1.8), bh + 0.35)];
        }
        if (all.length === 0) return root.fallbackPalette;
        if (chromatic.length < all.length * 0.05 || chromatic.length < 8) {
            var warm = 1.2;
            return [root.oklch(0.27, 0.025, warm), root.oklch(0.36, 0.035, warm), root.oklch(0.19, 0.02, warm), root.oklch(0.31, 0.03, warm + 0.5)];
        }
        var cl = root.kmeans(chromatic, Math.min(4, chromatic.length));
        cl.sort((a, b) => Math.pow(b.n, 0.35) * b.C - Math.pow(a.n, 0.35) * a.C);
        var top = cl[0], second = cl[1] || top, third = cl[2] || second;
        function c(x, lo, hi, f) { return Math.max(lo, Math.min(hi, x * f)); }
        return [root.oklch(0.30, c(top.C, 0.05, 0.10, 0.8), top.h),
                root.oklch(0.42, c(top.C, 0.09, 0.15, 1.3), top.h),
                root.oklch(0.21, c(second.C, 0.04, 0.09, 1.0), second.h),
                root.oklch(0.35, c(third.C, 0.04, 0.09, 1.0), third.h)];
    }
    // the opening pages' night: the top song's colours, sunk most of the way to black
    readonly property var nightPalette: [mix(songPalette[0], Qt.rgba(0.047, 0.047, 0.05, 1), 0.3), mix(songPalette[1], Qt.rgba(0.047, 0.047, 0.05, 1), 0.25),
                                         mix(songPalette[2], Qt.rgba(0.047, 0.047, 0.05, 1), 0.3), mix(songPalette[3], Qt.rgba(0.047, 0.047, 0.05, 1), 0.3)]
    component PaletteProbe: Canvas {
        property string url: ""
        property bool portrait: false
        signal read(var palette)
        width: 24; height: 24
        opacity: 0.01
        onUrlChanged: if (url !== "") loadImage(url)
        onImageLoaded: requestPaint()
        onPaint: {
            if (url === "" || !isImageLoaded(url)) return;
            var ctx = getContext("2d");
            ctx.reset();
            ctx.drawImage(url, 0, 0, width, height);
            read(root.paletteOf(ctx.getImageData(0, 0, width, height).data, width, portrait));
        }
    }
    PaletteProbe {
        url: root.photoOf(root.heroArtist)
        portrait: true
        onRead: (p) => root.artistPalette = p
    }
    PaletteProbe {
        url: root.heroSong ? root.heroSong.cover_url || "" : ""
        onRead: (p) => root.songPalette = p
    }

    // --- Every picture loads while the card is scratched, at the sizes the pages ask for --------
    // The pixmap cache keys on url, sourceSize and fill mode, so these match RoundedImage exactly;
    // by the time a page draws, its pictures are already decoded.
    component Preload: Image {
        width: 1; height: 1
        opacity: 0
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
    }
    Repeater {
        model: root.artists
        Item {
            Preload { source: root.photoOf(modelData); sourceSize: Qt.size(400, 400) }
            Preload { source: root.photoOf(modelData); sourceSize: Qt.size(48, 48) }
        }
    }
    Repeater {
        model: root.gridSongs
        Preload { source: modelData.cover_url || ""; sourceSize: Qt.size(320, 320) }
    }
    Repeater {
        model: root.songs
        Item {
            Preload { source: modelData.cover_url || ""; sourceSize: Qt.size(320, 320) }
            Preload { source: modelData.cover_url || ""; sourceSize: Qt.size(48, 48) }
            Preload { source: index === 0 ? modelData.cover_url || "" : ""; sourceSize: Qt.size(460, 460) }
        }
    }
    Preload { source: root.heroArtistSong ? root.heroArtistSong.cover_url || "" : ""; sourceSize: Qt.size(320, 320) }

    // --- A few seconds of the song behind each reveal --------------------------------------------
    property var snippetUrls: ({})
    function resolveSnippet(track) {
        if (!track || root.snippetUrls[track] !== undefined) return;
        var pending = Object.assign({}, root.snippetUrls);
        pending[track] = "";
        root.snippetUrls = pending;
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            var url = "";
            try {
                var r = xhr.status === 200 ? JSON.parse(xhr.responseText) : null;
                if (r && r.success) url = r.url || "";
            } catch (e) {}
            // a failed lookup is forgotten, so opening the story again retries it
            var urls = Object.assign({}, root.snippetUrls);
            if (url) urls[track] = url; else delete urls[track];
            root.snippetUrls = urls;
        };
        xhr.open("GET", root.apiUrl + "/api/listening/snippet?track=" + encodeURIComponent(track));
        xhr.send();
    }
    function prefetchSnippets() {
        if (root.heroArtistSong) root.resolveSnippet(root.heroArtistSong.track_id);
        if (root.heroSong) root.resolveSnippet(root.heroSong.track_id);
    }
    onRecapChanged: { root.snippetUrls = ({}); root.prefetchSnippets(); root.fetchArtistPick(); }
    Component.onCompleted: { root.prefetchSnippets(); root.fetchArtistPick(); }
    // asked again on each open: a song of theirs played since, or another of their popular songs
    // (a lookup that failed while the backend was still waking up gets another go too)
    onActiveChanged: {
        if (!root.active) return;
        if (root.artistOwnsHeroSong) root.fetchArtistPick();
        root.prefetchSnippets();
    }
    property real snippetVolume: 0
    property bool snippetSeekPending: false
    AudioOutput { id: snippetOut; volume: root.snippetVolume }
    MediaPlayer {
        id: snippet
        audioOutput: snippetOut
        onMediaStatusChanged: {
            if (mediaStatus !== MediaPlayer.LoadedMedia && mediaStatus !== MediaPlayer.BufferedMedia) return;
            if (!root.snippetSeekPending) return;
            root.snippetSeekPending = false;
            // into the song, past its intro, where it is recognisable
            if (duration > 70000) position = Math.min(duration * 0.3, 60000);
        }
    }
    function playSnippet(track) {
        var url = track ? root.snippetUrls[track] || "" : "";
        if (url === "" || !root.active) return;
        snippetStop.stop();
        if (String(snippet.source) !== url) {
            root.snippetSeekPending = true;
            snippet.source = url;
        }
        root.snippetVolume = 0;
        snippet.play();
        root.go(root, "snippetVolume", 0.8, 1500, 0, null);
    }
    function stopSnippet() {
        if (snippet.playbackState === MediaPlayer.StoppedState) return;
        root.go(root, "snippetVolume", 0, 600, 0, null);
        snippetStop.restart();
    }
    Timer { id: snippetStop; interval: 650; onTriggered: snippet.stop() }

    // --- The director (StoryDirector) -----------------------------------------------------------
    function avatarSlot(k) {
        switch (k) {
        case 0: return [root.width / 2, root.height * 0.43, 127 * root.u];
        case 1: return [root.inset + 45.5 * root.u, root.topPad + 95 * root.u + 45.5 * root.u, 91 * root.u];
        case 2: return [root.inset + 71.5 * root.u, root.topPad + 106 * root.u + 71.5 * root.u, 143 * root.u];
        case 3: return [root.inset + 42.5 * root.u, root.topPad + 91 * root.u + 42.5 * root.u, 85 * root.u];
        default: return [root.inset + 18 * root.u, root.topPad + 31 * root.u + 18 * root.u, 36 * root.u];
        }
    }
    function avatarTo(k, ms, wait) {
        var s = root.avatarSlot(k);
        root.go(root, "avX", s[0], ms, wait);
        root.go(root, "avY", s[1], ms, wait);
        root.go(root, "avD", s[2], ms, wait);
    }
    // Every giant row to word(i), or out when word(i) is "", one after another
    function rowsTo(order, wordOf, ms, step, wait) {
        for (var n = 0; n < order.length; n++) {
            var row = rowRepeater.itemAt(order[n] + 4);
            if (!row) continue;
            var w = wordOf(order[n]);
            if (w === "") row.slideOut(ms, (wait || 0) + n * step);
            else row.slideIn(w, ms, (wait || 0) + n * step);
        }
    }
    readonly property var allRows: [-4, -3, -2, -1, 0, 1, 2, 3, 4]

    // One roll per open picks every line's variant, so a replay can read differently
    property int lineSeed: 0
    // a small integer hash of (seed, line) so every line rolls on its own, not in lockstep
    function pick(list, salt) {
        var h = Math.imul(root.lineSeed ^ Math.imul(salt + 1, 0x9E3779B1), 0x85EBCA6B);
        h = Math.imul(h ^ (h >>> 13), 0xC2B2AE35);
        return list[((h ^ (h >>> 16)) >>> 0) % list.length];
    }

    function open() {
        root.active = true;
        root.lineSeed = Math.floor(Math.random() * 0x7FFFFFFF);
        root.prefetchSnippets();
        root.stopTweens();
        artistSeq.stop();
        songSeq.stop();
        var anims = [pHey, pJourney, pMonth, pWeek, pSpin, pArtist, pGrid, pMelody, pSong, pBill, pEnd];
        for (var i = 0; i < anims.length; i++) { anims[i].enter = 0; anims[i].exit = 0; }
        // the page header's single column, standing on its side at the right
        root.textRotation = 90; root.textScale = root.homeScale; root.textCenterX = root.homeCenterX; root.textOffsetY = 0;
        root.textAlpha = 1; root.dots = 1; root.mesh = 0; root.logoSide = 0;
        for (var r = -4; r <= 4; r++) {
            var row = rowRepeater.itemAt(r + 4);
            if (row) row.reset("NUTSTY", r === 0 ? 1 : 0);
        }
        var s = root.avatarSlot(0);
        root.avX = s[0]; root.avY = s[1]; root.avD = s[2];
        root.avAlpha = 0; root.avPop = 0; root.avRing = 0; root.avRingAlpha = 1;
        root.palFrom = root.artistPalette; root.palTo = root.artistPalette; root.palMix = 1;
        root.lastPage = -1;
        root.homing = false;
        root.forceActiveFocus();
        if (root.liteMode || !introCardFrom) {
            root.shown = root.liteMode ? 1 : root.shown;
            root.startPages();
            root.go(root, "shown", 1, 420, 0, root.curveStd);
            return;
        }
        // the blink: the lids close over the scanned card, open on the night with the card afloat
        var r = introCardFrom.mapToItem(root, 0, 0, introCardFrom.width, introCardFrom.height);
        root.introFrom = Qt.rect(r.x, r.y, r.width, r.height);
        root.introFly = 0;
        blinkSeq.restart();
    }
    property Item introCardFrom: null
    // The ending: the card on the last page flies back into the header's card, the story fading under it
    function flyHome(target) {
        autoNext.stop(); artistSeq.stop(); songSeq.stop();
        root.stopSnippet();
        if (!target || root.liteMode) { root.close(); return; }
        var a = endCard.mapToItem(root, 0, 0, endCard.width, endCard.height);
        var b = target.mapToItem(root, 0, 0, target.width, target.height);
        root.homeFrom = Qt.rect(a.x, a.y, a.width, a.height);
        root.homeTo = Qt.rect(b.x, b.y, b.width, b.height);
        root.homeT = 0;
        root.homing = true;
        // the opening, played backwards: the words leave, the rows gather into one column and stand up
        root.go(pEnd, "exit", 1, 520, 0, root.curveStd);
        root.rowsTo([-4, -3, -2, -1, 1, 2, 3, 4], () => "", 620, 50, 0);
        root.go(root, "textAlpha", 1, 600);
        root.go(root, "textOffsetY", 0, 900);
        root.go(root, "textRotation", 90, 1100, 180);
        root.go(root, "textScale", root.homeScale, 1100, 180);
        root.go(root, "textCenterX", root.homeCenterX, 1100, 180);
        // then the card heads home while the night fades off the header
        root.go(root, "shown", 0, 600, 1250, root.curveStd);
        homeSeq.restart();
    }
    SequentialAnimation {
        id: homeSeq
        PauseAnimation { duration: 900 }
        NumberAnimation { target: root; property: "homeT"; from: 0; to: 1; duration: 1050; easing.type: Easing.InOutCubic }
        ScriptAction { script: { root.homing = false; root.active = false; } }
    }
    function startPages() {
        if (root.page === 0) root.enterPage(0, -1);
        else root.page = 0;
    }
    SequentialAnimation {
        id: blinkSeq
        NumberAnimation { target: root; property: "lid"; from: 0; to: 1; duration: 260; easing.type: Easing.InCubic }
        ScriptAction { script: { root.shown = 1; root.intro = 1; } }
        PauseAnimation { duration: 140 }
        NumberAnimation { target: root; property: "lid"; to: 0; duration: 420; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 650 }
        ScriptAction { script: root.startPages() }
        NumberAnimation { target: root; property: "introFly"; to: 1; duration: 1050; easing.type: Easing.InOutCubic }
        ScriptAction { script: root.intro = 0 }
    }
    function close() {
        blinkSeq.stop(); homeSeq.stop();
        if (root.spreading) { spreadAnim.stop(); root.commitSpread(); }
        root.lid = 0; root.intro = 0; root.homing = false;
        root.active = false;
        autoNext.stop();
        artistSeq.stop();
        songSeq.stop();
        root.stopSnippet();
        root.go(root, "shown", 0, 380, 0, root.curveStd);
    }
    function nextIndex(k, dir) {
        k += dir;
        while ((k === 4 && !root.hasArtist) || (k === 5 && !root.hasSong)) k += dir;
        return k;
    }
    function next() {
        if (blinkSeq.running || root.homing) return;
        var k = root.nextIndex(root.page, 1);
        if (k < root.pageCount) root.page = k;
        else root.finishRequested();
    }
    function prev() {
        if (blinkSeq.running || root.homing) return;
        var k = root.nextIndex(root.page, -1);
        if (k >= 0) root.page = k;
    }
    onPageChanged: root.enterPage(root.page, root.lastPage)

    function enterPage(k, from) {
        autoNext.stop();
        if (root.spreading) { spreadAnim.stop(); root.commitSpread(); }
        if (from >= 0 && from !== k) {
            if (from === 4) artistSeq.stop();
            if (from === 5) songSeq.stop();
            if (from === 4 || from === 5) root.stopSnippet();
            var out = root.pageAnims(from);
            var outMs = [420, 700, 650, 600, 650, 650, 700, 520][from];
            for (var i = 0; i < out.length; i++)
                root.go(out[i], "exit", 1, outMs, 0, from === 6 ? root.curveEmphAcc : root.curveStd);
        }
        var mine = root.pageAnims(k);
        for (var j = 0; j < mine.length; j++) { mine[j].enter = 0; mine[j].exit = 0; }
        root.lastPage = k;
        var u = root.u;

        // the backdrop for this page
        if (k <= 3) {
            root.go(root, "textAlpha", 1, 900);
            root.go(root, "dots", 1, 900);
            if (root.mesh < 0.05) { root.palFrom = root.nightPalette; root.palTo = root.nightPalette; root.palMix = 1; }
            else if (root.palTo !== root.nightPalette) root.crossfadePalette(root.nightPalette, 1400);
            root.go(root, "mesh", 1, 950);
            root.go(root, "logoSide", 0, 900);
            root.go(root, "avAlpha", 1, 300, k === 0 && from < 0 ? 520 : 0);
            root.go(root, "avRingAlpha", 1, 700);
            root.go(root, "avRing", k === 0 ? 0 : 1, 950);
            root.go(root, "textOffsetY", k === 1 || k === 2 ? -46 * u : 0, 1100, k === 3 ? 300 : 0);
        } else if (k <= 6) {
            root.go(root, "textAlpha", 0, 900);
            root.go(root, "dots", 0, 900);
            // the reel and the grid keep the page before's colours while they search; the new
            // colours arrive with the pick (artistSeq / songSeq), so the choice reads as the change
            var pal = k === 6 ? root.songPalette : k === 5 && root.hasArtist ? root.artistPalette : root.nightPalette;
            if (root.mesh < 0.05) { root.palFrom = pal; root.palTo = pal; root.palMix = 1; }
            else if (root.palTo !== pal) root.crossfadePalette(pal, 1400);
            root.go(root, "mesh", 1, 1400);
            root.go(root, "logoSide", 1, 1000);
            root.go(root, "avAlpha", 1, 300);
            root.go(root, "avRingAlpha", 0, 700);
        } else {
            if (root.mesh < 0.05) { root.palFrom = root.songPalette; root.palTo = root.songPalette; root.palMix = 1; }
            else if (root.palTo !== root.songPalette) root.crossfadePalette(root.songPalette, 1400);
            root.go(root, "mesh", 1, 1400);
            root.go(root, "logoSide", 0, 900);
            root.go(root, "avAlpha", 0, 500);
            root.go(root, "textOffsetY", 0, 900);
            root.go(root, "textAlpha", 0.9, 1200, 300);
            root.go(root, "dots", 0, 900);
        }
        root.avatarTo(k, 950, k === 2 ? 120 : k === 3 ? 100 : 0);

        switch (k) {
        case 0:
            if (from < 0) {
                // columns warp into rows, the avatar pops
                root.go(root, "textRotation", 0, 1200);
                root.go(root, "textScale", 0.74, 1200);
                root.go(root, "textCenterX", 0.5, 1200);
                root.rowsTo([-1, 1], () => "NUTSTY", 900, 60, 0);
                root.rowsTo([-2, 2, -3, 3, -4, 4], () => "NUTSTY", 1000, 70, 120);
                root.go(root, "avPop", 1, 700, 520, [0.34, 1.56, 0.64, 1, 1, 1]);
                root.go(pHey, "enter", 1, 800, 760);
                autoNext.interval = 760 + 800 + 1300;
            } else {
                root.rowsTo(root.allRows, () => "NUTSTY", 1000, 60, 0);
                root.go(pHey, "enter", 1, 800, 300);
                autoNext.interval = 300 + 800 + 1600;
            }
            autoNext.start();
            break;
        case 1:
            root.rowsTo([-1, 0, 1, 2, 3, 4], () => "", 620, 60, 0);
            root.rowsTo([-4, -3, -2], () => "NUTSTY", 900, 60, 0);
            root.go(pJourney, "enter", 1, 2200, 380, null);
            break;
        case 2:
            root.rowsTo([-1, 0, 1, 2, 3], () => root.monthName.toUpperCase(), 1000, 80, 260);
            root.rowsTo([4], () => "", 620, 0, 0);
            root.go(pMonth, "enter", 1, 2000, 420, null);
            // the percentage reads on its own: a second after it has settled, the story moves on
            autoNext.interval = 420 + 2000 + 1000;
            autoNext.start();
            break;
        case 3:
            root.rowsTo(root.allRows, () => root.dayWord, 950, 60, 0);
            root.go(pWeek, "enter", 1, 2000, 560, null);
            break;
        case 4:
            root.spin = 0; root.spinGlow = 0; root.heroMove = 0;
            artistSeq.restart();
            break;
        case 5:
            root.gridDrift = 0; root.gridPick = 0; root.heroCover = 0; root.heroCoverUp = 0;
            songSeq.restart();
            break;
        case 6:
            root.go(pBill, "enter", 1, 1300, 250);
            break;
        case 7:
            root.rowsTo(root.allRows, () => "NUTSTY", 1000, 60, 300);
            root.go(pEnd, "enter", 1, 1600, 250, null);
            break;
        }
    }

    Timer { id: autoNext; onTriggered: if (root.shown > 0.5) root.next() }

    // three laps, decelerating onto the hero (lap * n is always artist #1); then the rings, then the reveal
    SequentialAnimation {
        id: artistSeq
        ParallelAnimation {
            SequentialAnimation {
                PauseAnimation { duration: 250 * root.speed }
                NumberAnimation { target: pSpin; property: "enter"; to: 1; duration: 1000 * root.speed; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveStd }
            }
            SequentialAnimation {
                PauseAnimation { duration: 250 * root.speed }
                NumberAnimation {
                    target: root; property: "spin"; to: 3 * Math.max(1, root.artists.length); duration: 3600 * root.speed
                    easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveSpin
                }
            }
        }
        // the photo lands: its most played song starts under the rings
        ScriptAction {
            script: {
                root.playSnippet(root.heroArtistSong ? root.heroArtistSong.track_id : "");
                root.spreadPalette(root.artistPalette, () => artistSeqView.heroCx, () => artistSeqView.heroCy);
            }
        }
        NumberAnimation { target: root; property: "spinGlow"; to: 1; duration: 1100 * root.speed }
        ParallelAnimation {
            NumberAnimation { target: root; property: "heroMove"; to: 1; duration: 1000 * root.speed; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveStd }
            NumberAnimation { target: pSpin; property: "exit"; to: 1; duration: 650 * root.speed; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveStd }
            SequentialAnimation {
                PauseAnimation { duration: 300 * root.speed }
                NumberAnimation { target: pArtist; property: "enter"; to: 1; duration: 2400 * root.speed }
            }
        }
    }

    // the grid drifts in, picks the top song, which becomes "Hear the melody..", then its own page
    SequentialAnimation {
        id: songSeq
        ParallelAnimation {
            SequentialAnimation {
                PauseAnimation { duration: 150 * root.speed }
                NumberAnimation { target: pGrid; property: "enter"; to: 1; duration: 1400 * root.speed; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveStd }
            }
            NumberAnimation { target: root; property: "gridDrift"; to: 1; duration: 3800 * root.speed }
        }
        NumberAnimation { target: root; property: "gridPick"; to: 1; duration: 800 * root.speed; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveStd }
        // "Hear the melody..": and it plays
        ScriptAction {
            script: {
                root.playSnippet(root.heroSong ? root.heroSong.track_id : "");
                root.spreadPalette(root.songPalette, () => heroCoverImg.x + heroCoverImg.width / 2, () => heroCoverImg.y + heroCoverImg.height / 2);
            }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "heroCover"; to: 1; duration: 1000 * root.speed; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveStd }
            NumberAnimation { target: pGrid; property: "exit"; to: 1; duration: 600 * root.speed; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveStd }
            SequentialAnimation {
                PauseAnimation { duration: 300 * root.speed }
                NumberAnimation { target: pMelody; property: "enter"; to: 1; duration: 1000 * root.speed; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveStd }
            }
        }
        PauseAnimation { duration: 3200 * root.speed }
        ParallelAnimation {
            NumberAnimation { target: root; property: "heroCoverUp"; to: 1; duration: 1000 * root.speed; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveStd }
            NumberAnimation { target: pMelody; property: "exit"; to: 1; duration: 500 * root.speed; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveStd }
            SequentialAnimation {
                PauseAnimation { duration: 250 * root.speed }
                NumberAnimation { target: pSong; property: "enter"; to: 1; duration: 2000 * root.speed }
            }
        }
    }

    Keys.onRightPressed: root.next()
    Keys.onLeftPressed: root.prev()
    Keys.onSpacePressed: root.next()
    Keys.onEscapePressed: root.closeRequested()

    // --- Shared pieces ------------------------------------------------------------------------
    component Bold: Text {
        property real sz: 22
        property real lh: sz * 1.1
        property real tracking: -0.035 * sz
        color: "#FFFFFF"
        font.family: Theme.fontFamily
        font.weight: Font.Bold
        font.pixelSize: sz * root.u
        font.letterSpacing: tracking * root.u
        lineHeightMode: Text.FixedHeight
        lineHeight: lh * root.u
        wrapMode: Text.WordWrap
    }
    component Mono: Text {
        color: "#FFFFFF"
        font.family: "monospace"
        font.pixelSize: 20 * root.u
    }
    // Digits roll into place like an odometer as progress goes 0..1, left to right; letters rise in
    component Odo: Item {
        id: odo
        property string text: ""
        property real sz: 44
        property real progress: 1
        property int weight: Font.Bold
        property real tracking: -0.035 * sz
        property color color: "#FFFFFF"
        implicitWidth: odoRow.implicitWidth
        implicitHeight: odoFm.height
        FontMetrics { id: odoFm; font.family: Theme.fontFamily; font.pixelSize: odo.sz * root.u; font.weight: odo.weight }
        Row {
            id: odoRow
            Repeater {
                model: odo.text.split("")
                Item {
                    readonly property string ch: modelData
                    readonly property bool digit: ch >= "0" && ch <= "9"
                    readonly property real local: root.stagger(odo.progress, index, odo.text.length, 0.62)
                    readonly property real value: digit ? ((1 + index % 3) * 10 + Number(ch)) * root.eoc(local) : 0
                    readonly property int base: Math.floor(value)
                    readonly property real frac: value - base
                    readonly property real fade: Math.min(1, local * 5)
                    width: (digit ? Math.max(odoFm.advanceWidth(ch), odoFm.advanceWidth("0")) : odoFm.advanceWidth(ch)) + odo.tracking * root.u
                    height: odoFm.height
                    clip: digit
                    Text {
                        width: parent.width
                        horizontalAlignment: parent.digit ? Text.AlignHCenter : Text.AlignLeft
                        y: parent.digit ? -parent.frac * parent.height : (1 - root.eoc(parent.local)) * parent.height * 0.35
                        text: parent.digit ? String(parent.base % 10) : parent.ch
                        opacity: parent.digit ? (1 - parent.frac) * parent.fade : root.eoc(parent.local)
                        color: odo.color
                        font: odoFm.font
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: parent.digit && parent.frac > 0.001
                        y: (1 - parent.frac) * parent.height
                        text: String((parent.base + 1) % 10)
                        opacity: parent.frac * parent.fade
                        color: odo.color
                        font: odoFm.font
                    }
                }
            }
        }
    }

    // Everything sits in one frame cut to the window's rounded corners
    Item {
        id: frame
        anchors.fill: parent
        opacity: Math.min(1, root.shown * 1.6)
        visible: root.shown > 0.001
        layer.enabled: root.visible
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: frameMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        // ===== Backdrop =====
        Rectangle { anchors.fill: parent; color: "#0C0C0C" }

        // The mesh: the palette's base tone with three slow soft blobs over it
        // one soft blob of a Mesh; it lives out here because inline components cannot nest
        component MeshBlob: ShapePath {
            id: blob
            property var host
            property int n: 0
            property color tint: "black"
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: blob.host.centers[blob.n * 2] * blob.host.width
                centerY: blob.host.centers[blob.n * 2 + 1] * blob.host.width
                centerRadius: blob.host.r
                focalX: centerX; focalY: centerY; focalRadius: 0
                GradientStop { position: 0; color: blob.tint }
                GradientStop { position: 1; color: Qt.rgba(blob.tint.r, blob.tint.g, blob.tint.b, 0) }
            }
            startX: 0; startY: 0
            PathLine { x: blob.host.width; y: 0 }
            PathLine { x: blob.host.width; y: blob.host.height }
            PathLine { x: 0; y: blob.host.height }
            PathLine { x: 0; y: 0 }
        }
        component Mesh: Shape {
            id: meshShape
            property color c0: "black"
            property color c1: "black"
            property color c2: "black"
            property color c3: "black"
            readonly property real t: root.time * 0.22
            readonly property real r: width * 0.95
            readonly property var centers: [
                0.85 + 0.22 * Math.cos(t * 0.8 + 1.3), (height / Math.max(1, width)) * (0.38 + 0.20 * Math.sin(t * 0.6 + 2.1)),
                0.25 + 0.28 * Math.cos(t * 0.55 + 3.2), (height / Math.max(1, width)) * (0.72 + 0.16 * Math.sin(t * 0.85 + 0.7)),
                0.80 + 0.20 * Math.sin(t * 0.75 + 4.1), (height / Math.max(1, width)) * (0.94 + 0.10 * Math.cos(t * 0.95))
            ]
            ShapePath {
                strokeWidth: -1
                fillColor: meshShape.c0
                startX: 0; startY: 0
                PathLine { x: meshShape.width; y: 0 }
                PathLine { x: meshShape.width; y: meshShape.height }
                PathLine { x: 0; y: meshShape.height }
                PathLine { x: 0; y: 0 }
            }
            MeshBlob { host: meshShape; n: 0; tint: meshShape.c1 }
            MeshBlob { host: meshShape; n: 1; tint: meshShape.c2 }
            MeshBlob { host: meshShape; n: 2; tint: meshShape.c3 }
        }
        Mesh {
            anchors.fill: parent
            visible: root.mesh > 0.003
            opacity: root.mesh
            c0: root.m0; c1: root.m1; c2: root.m2; c3: root.m3
        }
        // A pick's colours bleed out from the picked photo like a wet brush on paper: the new mesh
        // drawn over the old one through a watercolour stain (assets/shaders/ink_bleed.frag) with a
        // main drop on the photo and three seeded satellite drops, uneven edges and a darker rim
        Mesh {
            id: spreadMesh
            anchors.fill: parent
            visible: root.spreading && root.mesh > 0.003
            opacity: root.mesh
            c0: root.spreadPal[0]; c1: root.spreadPal[1]; c2: root.spreadPal[2]; c3: root.spreadPal[3]
            layer.enabled: visible
            layer.effect: ShaderEffect {
                property variant source
                readonly property real h: Math.max(1, spreadMesh.height)
                property real u_progress: root.spreadR
                property real u_aspect: spreadMesh.width / h
                property real u_seed: root.spreadSeed
                property real u_time: root.time
                property real u_reach: Math.max(Math.hypot(root.spreadX, root.spreadY), Math.hypot(spreadMesh.width - root.spreadX, root.spreadY),
                                                Math.hypot(root.spreadX, spreadMesh.height - root.spreadY),
                                                Math.hypot(spreadMesh.width - root.spreadX, spreadMesh.height - root.spreadY)) / h
                property point u_origin: Qt.point(root.spreadX / Math.max(1, spreadMesh.width), root.spreadY / h)
                fragmentShader: Qt.resolvedUrl("../assets/shaders/ink_bleed.frag.qsb")
            }
        }

        // Rows of one huge word, endlessly sliding. Stood on its side the plane reads as the page
        // header's column; turning it back is the story's warp from columns into rows.
        readonly property real giantPx: 178 * root.u
        readonly property real giantPitch: 0.727 * giantPx * 1.16
        readonly property color giantColor: root.mix(Qt.rgba(0.086, 0.086, 0.086, 1), Qt.rgba(1, 1, 1, 0.06), root.mesh)
        FontMetrics { id: giantFm; font.family: Theme.fontFamily; font.pixelSize: frame.giantPx; font.weight: Font.Bold }
        // The giant words fade out at the top and bottom of the frame too, like the pages over them
        Item {
            id: giantLayer
            anchors.fill: parent
            visible: root.textAlpha > 0.003
            layer.enabled: !root.liteMode && root.visible && visible
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: pageFadeMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
                autoPaddingEnabled: false
            }
            Item {
                id: plane
                x: root.textCenterX * frame.width
                y: frame.height / 2 + root.textOffsetY
                width: 0; height: 0
                transformOrigin: Item.TopLeft
                rotation: root.textRotation
                scale: root.textScale
                visible: root.textAlpha > 0.003
                opacity: root.textAlpha
                readonly property real span: Math.hypot(frame.width, frame.height) * 1.1 / Math.max(0.2, root.textScale)
                readonly property real capCenter: giantFm.ascent - 0.727 * frame.giantPx / 2

                Repeater {
                    id: rowRepeater
                    model: 9
                    Item {
                        id: gr
                        readonly property int idx: index - 4
                        property string word: "NUTSTY"
                        property string nextWord: "NUTSTY"
                        property real fill: idx === 0 ? 1 : 0
                        property real side: 1
                        function reset(w, f) { seq.stop(); gr.word = w; gr.nextWord = w; gr.fill = f; gr.side = 1; }
                        function slideIn(w, ms, wait) {
                            if (gr.fill > 0.999 && w === gr.word && !seq.running) return;
                            seq.stop();
                            var needOut = gr.fill > 0.001 && w !== gr.word;
                            pause.duration = wait * root.speed;
                            outA.to = needOut ? 0 : gr.fill;
                            outA.duration = needOut ? 520 * root.speed : 0;
                            gr.nextWord = w;
                            inA.to = 1;
                            inA.duration = ms * root.speed;
                            seq.start();
                        }
                        function slideOut(ms, wait) {
                            if (gr.fill <= 0.001 && !seq.running) return;
                            seq.stop();
                            pause.duration = wait * root.speed;
                            outA.to = 0;
                            outA.duration = ms * root.speed;
                            gr.nextWord = gr.word;
                            inA.to = 0;
                            inA.duration = 0;
                            seq.start();
                        }
                        SequentialAnimation {
                            id: seq
                            PauseAnimation { id: pause }
                            ScriptAction { script: gr.side = -1 }
                            NumberAnimation { id: outA; target: gr; property: "fill"; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveStd }
                            ScriptAction { script: { gr.word = gr.nextWord; gr.side = 1; } }
                            NumberAnimation { id: inA; target: gr; property: "fill"; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveStd }
                        }

                        readonly property real tileW: giantFm.advanceWidth(gr.word) + frame.giantPx * 0.22
                        readonly property real dir: idx % 2 === 0 ? -1 : 1
                        readonly property real pace: 22 * root.u * (1 + 0.18 * ((idx + 8) % 3))
                        readonly property real base: ((root.time * pace) % tileW) * dir + (1 - root.eoc(fill)) * plane.span * side
                        x: base - Math.ceil((base + plane.span / 2) / tileW) * tileW
                        y: idx * frame.giantPitch - plane.capCenter
                        visible: fill > 0.002
                        opacity: fill
                        Row {
                            Repeater {
                                model: Math.ceil(plane.span / Math.max(1, gr.tileW)) + 2
                                Text {
                                    width: gr.tileW
                                    text: gr.word
                                    color: frame.giantColor
                                    font: giantFm.font
                                }
                            }
                        }
                    }
                }
            }
        }

        DotGrid {
            anchors.fill: parent
            step: 17 * root.u
            dotRadius: 1.3 * root.u
            dotAlpha: 0.07
            visible: root.dots > 0.004
            opacity: root.dots
        }

        // A click moves the story: the left third goes back, the rest goes on
        TapHandler {
            onTapped: (point) => {
                if (point.position.x < root.width * 0.3) root.prev();
                else root.next();
            }
        }

        // Every page's content fades out at the top and bottom of the frame instead of being cut
        // there (the artist reel, the cover wall, the receipt); the backdrop and chrome stay whole
        Item {
            id: pageLayer
            anchors.fill: parent
            layer.enabled: !root.liteMode && root.visible
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: pageFadeMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
                autoPaddingEnabled: false
            }

            // ===== 0. Hello =====
            Bold {
                visible: root.shows(pHey)
                x: root.inset; width: root.width - 2 * root.inset
                y: root.avatarSlot(0)[1] + root.avatarSlot(0)[2] / 2 + 34 * root.u
                horizontalAlignment: Text.AlignHCenter
                maximumLineCount: 2
                sz: 26
                text: root.pick([I18n.tr("Chao xìn, %1!", "Hey, %1!"), I18n.tr("Oi oi oi, %1!", "Oi oi oi, %1!"), I18n.tr("Ủa alo, %1!", "Yo, %1!"), I18n.tr("%1 tới, bá khí ngút trời!", "%1 walked in, aura maxed!"), I18n.tr("Gét gô, %1!", "Lock in, %1!")], 1).arg(root.userName)
                opacity: root.eoc(pHey.enter) * (1 - root.eic(pHey.exit))
                transform: Translate { y: (1 - root.eoc(pHey.enter)) * 22 * root.u - root.eic(pHey.exit) * 36 * root.u }
            }

            // ===== 1. The journey so far =====
            Item {
                anchors.fill: parent
                visible: root.shows(pJourney)
                Column {
                    x: root.inset
                    y: root.avatarSlot(1)[1] + root.avatarSlot(1)[2] / 2 + 44 * root.u
                    width: root.column
                    Bold {
                        width: parent.width; sz: 22
                        text: root.pick([I18n.tr("%1 đã bắt đầu hành trình cùng Nutsty vào ngày", "%1, you started your journey in Nutsty on"), I18n.tr("ngày định mệnh %1 gặp Nutsty là", "the fateful day %1 met Nutsty was"), I18n.tr("cột mốc trùng sinh của %1 là ngày", "the canon event of %1 happened on"), I18n.tr("%1 chính thức nhập hội Nutsty từ", "the lore of %1 begins on")], 2).arg(root.userName)
                        opacity: root.lmA(pJourney, 0, 5)
                        transform: Translate { x: root.lmX(pJourney, 0, 5); y: root.lmY(pJourney, 0, 5) }
                    }
                    Item { width: 1; height: 4 * root.u }
                    Odo {
                        sz: 44
                        text: {
                            var d = root.joinedAt > 0 ? new Date(root.joinedAt) : new Date();
                            return I18n.locale === "vi" ? d.getDate() + " Tháng " + (d.getMonth() + 1) + ", " + d.getFullYear()
                                                        : d.toLocaleDateString(Qt.locale("en_US"), "MMM d, yyyy");
                        }
                        progress: root.stagger(pJourney.enter, 1, 5)
                        opacity: root.lmA(pJourney, 1, 5)
                        transform: Translate { x: root.lmX(pJourney, 1, 5); y: root.lmY(pJourney, 1, 5) }
                    }
                    Item { width: 1; height: 20 * root.u }
                    Bold {
                        width: parent.width; sz: 22
                        text: root.pick([I18n.tr("và bạn đã nghe nhạc với tổng thời gian là", "and you have been listening to music in total time of"), I18n.tr("từ đó tới giờ tai bạn đã gánh", "since then your ears have endured"), I18n.tr("và bạn đã cày nhạc tổng cộng", "and you have been grinding music for"), I18n.tr("tổng thời gian bạn tu luyện bá khí là", "your total aura farming time is")], 3)
                        opacity: root.lmA(pJourney, 2, 5)
                        transform: Translate { x: root.lmX(pJourney, 2, 5); y: root.lmY(pJourney, 2, 5) }
                    }
                    Item { width: 1; height: 4 * root.u }
                    Odo {
                        sz: 44
                        text: root.hoursMinutes(root.recap ? root.recap.all_time_minutes : 0)
                        progress: root.stagger(pJourney.enter, 3, 5)
                        opacity: root.lmA(pJourney, 3, 5)
                        transform: Translate { x: root.lmX(pJourney, 3, 5); y: root.lmY(pJourney, 3, 5) }
                    }
                    Item { width: 1; height: 22 * root.u }
                    Bold {
                        width: parent.width; sz: 22
                        text: root.pick([I18n.tr("hẹn gặp lại nhé!", "so long, partners!"), I18n.tr("chưa hết đâu nha!", "but wait, there's more!"), I18n.tr("đi tiếp thôi, gét gô!", "onwards we go!"), I18n.tr("căng đét luôn á!", "that's tuff, ngl!"), I18n.tr("khum dừng được đâu!", "no cap, keep going!")], 4)
                        opacity: root.lmA(pJourney, 4, 5)
                        transform: Translate { x: root.lmX(pJourney, 4, 5); y: root.lmY(pJourney, 4, 5) }
                    }
                }
                Mono {
                    x: 52 * root.u
                    y: root.height - 157 * root.u
                    text: I18n.tr("BẤM !", "CLICK!")
                    opacity: root.clamp01((pJourney.enter - 0.6) / 0.4) * (1 - pJourney.exit)
                }
            }

            // ===== 2. How far the month is =====
            Column {
                visible: root.shows(pMonth)
                x: root.inset
                width: Math.min(root.width - 2 * root.inset, 900 * root.u)
                y: root.fy(702) - height
                Bold {
                    width: parent.width; rightPadding: 6 * root.u
                    sz: 44
                    horizontalAlignment: Text.AlignRight
                    text: root.pick([I18n.tr("%1 đã đi được", "%1 is"), I18n.tr("%1 đã trôi mất", "%1 is already"), I18n.tr("%1 đã tiêu hết", "%1 has used up"), I18n.tr("%1 đã bay màu", "%1 is already cooked")], 5).arg(root.monthName)
                    opacity: root.lmA(pMonth, 0, 4)
                    transform: Translate { x: root.lmX(pMonth, 0, 4, 70); y: root.lmY(pMonth, 0, 4) }
                }
                Item {
                    width: parent.width
                    height: pctOdo.implicitHeight
                    Odo {
                        id: pctOdo
                        anchors.right: parent.right
                        sz: 104; weight: Font.ExtraBold; tracking: -4
                        text: Math.round(root.recap ? root.recap.month_progress : 0) + "%"
                        progress: root.stagger(pMonth.enter, 1, 4)
                        opacity: root.lmA(pMonth, 1, 4)
                        transform: Translate { x: root.lmX(pMonth, 1, 4, 70); y: root.lmY(pMonth, 1, 4) }
                    }
                }
                Bold {
                    leftPadding: 6 * root.u
                    sz: 15
                    text: I18n.tr("trên 100%", "out of 100%")
                    opacity: root.lmA(pMonth, 2, 4)
                    transform: Translate { x: root.lmX(pMonth, 2, 4); y: root.lmY(pMonth, 2, 4) }
                }
                Item { width: 1; height: 12 * root.u }
                // The month bar: a white track and a green fill that grows in, with a sheen that never stops
                Item {
                    id: monthBar
                    width: parent.width
                    height: 46 * root.u
                    opacity: root.lmA(pMonth, 3, 4)
                    transform: Translate { x: root.lmX(pMonth, 3, 4); y: root.lmY(pMonth, 3, 4) }
                    readonly property real grow: root.eioc((pMonth.enter - 0.4) / 0.6)
                    readonly property real f: (root.recap ? root.recap.month_progress : 0) / 100 * grow
                    readonly property real w: Math.max(height, width * f)
                    Rectangle { anchors.fill: parent; radius: height / 2; color: "#FFFFFF" }
                    Rectangle {
                        id: barFill
                        visible: monthBar.f > 0.001
                        width: monthBar.w; height: parent.height
                        radius: height / 2
                        clip: true
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "#46E68F" }
                            GradientStop { position: 0.5; color: "#88FF76" }
                            GradientStop { position: 1; color: "#D4FF73" }
                        }
                        Rectangle {
                            readonly property real sweep: ((root.time * 0.55) % 1.5 - 0.25) * barFill.width
                            width: Math.min(barFill.width, barFill.height * 2)
                            height: barFill.height
                            radius: height / 2
                            x: Math.max(0, Math.min(barFill.width - width, sweep - width * 0.8))
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0) }
                                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.55) }
                                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.35) }
                                GradientStop { position: 0.6; color: Qt.rgba(1, 1, 1, 0) }
                            }
                        }
                        // a soft glow at the leading edge while it is still growing
                        Rectangle {
                            width: barFill.height * 0.64; height: width; radius: width / 2
                            x: barFill.width - barFill.height / 2 - width / 2
                            y: (barFill.height - height) / 2
                            color: "#FFFFFF"
                            opacity: 0.5 * (1 - monthBar.grow)
                        }
                    }
                }
            }

            // ===== 3. The favourite weekday =====
            Item {
                anchors.fill: parent
                visible: root.shows(pWeek)
                readonly property int favMin: root.weekdays[root.favouriteDay]
                readonly property int more: root.runnerUpMinutes > 0 ? Math.round((favMin - root.runnerUpMinutes) * 100 / root.runnerUpMinutes) : -1
                Column {
                    x: root.inset
                    y: root.avatarSlot(3)[1] + root.avatarSlot(3)[2] / 2 + 22 * root.u
                    width: root.column
                    Bold {
                        width: parent.width; sz: 34
                        text: root.pick([I18n.tr("và vào lúc này,", "and at this time,"), I18n.tr("tin nóng hổi đây,", "breaking news,"), I18n.tr("nói nhỏ nghe nè,", "psst, guess what,"), I18n.tr("không phải dạng vừa đâu,", "not to glaze, but,")], 6)
                        opacity: root.lmA(pWeek, 0, 5)
                        transform: Translate { x: root.lmX(pWeek, 0, 5); y: root.lmY(pWeek, 0, 5) }
                    }
                    Bold {
                        width: parent.width
                        sz: 62; lh: 66; tracking: -2.4
                        font.weight: Font.ExtraBold
                        wrapMode: Text.NoWrap
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 30 * root.u
                        text: root.dayWord
                        opacity: root.lmA(pWeek, 1, 5)
                        transform: Translate { x: root.lmX(pWeek, 1, 5); y: root.lmY(pWeek, 1, 5) }
                    }
                    Bold {
                        width: parent.width; sz: 22
                        text: root.pick([I18n.tr("là ngày bạn thích nghe nhạc nhất", "is your favourite day to listen to music"), I18n.tr("là ngày tai bạn tăng ca nhiều nhất", "is when your ears work overtime"), I18n.tr("là ngày bạn quẩy nhạc hết cỡ", "is your official jam day"), I18n.tr("là ngày bá khí của bạn lên đỉnh", "is your peak aura day"), I18n.tr("là ngày bạn nghe nhạc không biết mệt", "is the day you just can't stop listening")], 7)
                        opacity: root.lmA(pWeek, 2, 5)
                        transform: Translate { x: root.lmX(pWeek, 2, 5); y: root.lmY(pWeek, 2, 5) }
                    }
                }
                Column {
                    id: weekNumbers
                    x: root.inset
                    y: root.fy(546)
                    width: root.column
                    readonly property bool hours: parent.favMin >= 60
                    readonly property string amount: hours ? String(Math.floor(parent.favMin / 60)) : String(Math.max(1, parent.favMin))
                    readonly property string unit: hours ? I18n.tr(" giờ", Math.floor(parent.favMin / 60) === 1 ? " hour" : " hours") : I18n.tr(" phút", " minutes")
                    Row {
                        opacity: root.lmA(pWeek, 3, 5)
                        transform: Translate { x: root.lmX(pWeek, 3, 5); y: root.lmY(pWeek, 3, 5) }
                        Odo { sz: 36; text: weekNumbers.amount; progress: root.stagger(pWeek.enter, 3, 5) }
                        Bold { sz: 36; wrapMode: Text.NoWrap; text: weekNumbers.unit + (weekNumbers.parent.more >= 0 ? "," : "") }
                        Item { width: 10 * root.u; height: 1; visible: weekNumbers.parent.more >= 0 }
                        Odo {
                            visible: weekNumbers.parent.more >= 0
                            sz: 36
                            text: weekNumbers.parent.more + "%"
                            progress: root.stagger(pWeek.enter, 4, 5)
                        }
                    }
                    Bold {
                        width: parent.width; sz: 36
                        text: weekNumbers.parent.more >= 0 ? root.pick([I18n.tr("nhiều hơn ngày xếp thứ hai của bạn!", "more than your 2nd!"), I18n.tr("bỏ xa ngày về nhì!", "ahead of the runner-up!"), I18n.tr("ngày về nhì chỉ biết hít khói!", "the runner-up is cooked!"), I18n.tr("hơn ngày về nhì, hết nước chấm!", "more than your 2nd, huge W!")], 8)
                                                           : root.pick([I18n.tr("không ngày nào sánh bằng!", "nothing else comes close!"), I18n.tr("các ngày khác chỉ là phụ!", "the other days are just extras!"), I18n.tr("không ai có cửa!", "no contest at all!"), I18n.tr("các ngày khác xỉu ngang!", "every other day is an NPC!")], 8)
                        opacity: root.lmA(pWeek, 4, 5)
                        transform: Translate { x: root.lmX(pWeek, 4, 5); y: root.lmY(pWeek, 4, 5) }
                    }
                }
            }

            // ===== 4. The top artist: the slot machine, then the reveal =====
            Item {
                id: artistSeqView
                anchors.fill: parent
                visible: root.hasArtist && (root.shows(pSpin) || root.shows(pArtist) || (pSpin.enter > 0 && pArtist.exit < 1))
                // the artist page leaves sliding left, every piece of it
                readonly property real away: pArtist.exit
                opacity: 1 - root.eic(root.clamp01((away - 0.1) / 0.9))
                transform: Translate { x: -root.eic(artistSeqView.away) * artistSeqView.width * 0.6 }

                readonly property int n: Math.max(1, root.artists.length)
                readonly property int heroIndex: 3 * n
                readonly property real d: 229 * root.u
                readonly property real pitch: 254 * root.u
                readonly property real colCx: root.wide ? root.groupX + root.groupW * 0.72
                                                        : Math.min(width - root.inset - d / 2, Math.max(width / 2 + d / 2, width * 0.62 + d / 2))
                // where the photo settles: the left of the group on a wide window, under the words on a tall one
                readonly property real heroEndD: root.wide ? root.heroSize : 132 * root.u
                readonly property real heroEndCx: root.wide ? root.aHeroCx : root.inset + 4 * root.u + heroEndD / 2
                readonly property real heroEndCy: root.wide ? root.heroCy : revealCol.y + revealCol.height + 24 * root.u + heroEndD / 2
                readonly property real heroCx: root.lerp(colCx, heroEndCx, root.heroMove)
                readonly property real heroCy: root.lerp(height / 2 + (heroIndex - root.spin) * pitch, heroEndCy, root.heroMove)
                readonly property real heroD: root.lerp(d, heroEndD, root.heroMove)

                Bold {
                    x: root.wide ? root.groupX : root.inset; y: root.topPad + 118 * root.u
                    sz: 48; lh: 46
                    text: root.pick([I18n.tr("Lặp đi\nlặp lại\nmãi", "Again\nand\nagain"), I18n.tr("Nghe hoài\nnghe mãi\nkhông chán", "On\nrepeat\nforever"), I18n.tr("Một lần\nchưa đủ\nđâu", "Once\nis never\nenough"), I18n.tr("Mê mẩn\nkhông\nlối thoát", "Glazing\nnonstop\nfor")], 9)
                    opacity: root.lmA(pSpin, 0, 2)
                    transform: Translate { x: root.lmX(pSpin, 0, 2, 0, -140); y: root.lmY(pSpin, 0, 2) }
                }
                Bold {
                    x: root.wide ? root.groupX : root.inset; y: root.fy(578)
                    sz: 62; lh: 58
                    text: I18n.tr("nghệ sĩ\nnày..", "this\nartist..")
                    opacity: root.lmA(pSpin, 1, 2)
                    transform: Translate { x: root.lmX(pSpin, 1, 2, 0, -140); y: root.lmY(pSpin, 1, 2) }
                }
                // the column, endlessly climbing; the hero slot is drawn on its own below
                Repeater {
                    model: 7
                    RoundedImage {
                        // each slot keeps its own row and only takes a new photo when it wraps off the edge,
                        // so a step of the reel never swaps all seven pictures at once
                        readonly property int base: Math.floor(root.spin) - 3
                        readonly property int j: base + (((index - base) % 7) + 7) % 7
                        readonly property var artist: root.artists.length ? root.artists[((j % artistSeqView.n) + artistSeqView.n) % artistSeqView.n] : null
                        visible: j !== artistSeqView.heroIndex && root.shows(pSpin)
                        width: artistSeqView.d; height: width; radius: width / 2
                        sourceSize: Qt.size(400, 400)
                        source: root.photoOf(artist)
                        initialsText: artist ? artist.artist : ""
                        placeholderColor: Qt.rgba(1, 1, 1, 0.2)
                        x: artistSeqView.colCx - width / 2 + (1 - root.eoc(pSpin.enter)) * 120 * root.u + root.eic(pSpin.exit) * artistSeqView.width * 0.6
                        y: artistSeqView.height / 2 + (j - root.spin) * artistSeqView.pitch - width / 2
                        opacity: root.eoc(pSpin.enter) * (1 - root.eic(pSpin.exit))
                    }
                }
                // the highlight: rings breaking out of the chosen circle
                Repeater {
                    model: 3
                    Rectangle {
                        readonly property real t: root.clamp01((root.spinGlow - index * 0.16) / 0.68)
                        visible: t > 0 && t < 1 && root.heroMove < 0.6
                        width: artistSeqView.heroD * (1 + 0.9 * root.eoc(t)); height: width; radius: width / 2
                        x: artistSeqView.heroCx - width / 2
                        y: artistSeqView.heroCy - height / 2
                        color: "transparent"
                        border.color: "#FFFFFF"
                        border.width: 5 * root.u * (1 - t) + 1
                        opacity: 0.7 * (1 - t)
                    }
                }

                // the reveal: the words beside the photo
                Column {
                    id: revealCol
                    visible: pArtist.enter > 0
                    x: root.wide ? root.aTextX : root.inset
                    y: root.wide ? root.heroCy - height / 2 : root.topPad + 92 * root.u
                    width: root.wide ? root.aTextW : root.column
                    Bold {
                        id: revealTitle
                        width: parent.width
                        sz: 34; lh: 37
                        text: (function (t) { return root.wide ? t.replace("\n", " ") : t; })(root.pick([I18n.tr("Nhận ra\nnghệ sĩ này?", "Recognize\nthis artist?"), I18n.tr("Thấy quen\nquen không?", "Ring\na bell?"), I18n.tr("Đoán xem\nai đây?", "Guess\nwho?"), I18n.tr("Bá khí\nnày của ai?", "Whose aura\nis this?")], 10))
                        opacity: root.lmA(pArtist, 0, 5)
                        transform: Translate { x: root.lmX(pArtist, 0, 5, 90); y: root.lmY(pArtist, 0, 5) }
                    }
                    Bold {
                        width: parent.width; topPadding: 4 * root.u
                        sz: 24; lh: 28
                        color: Qt.rgba(1, 1, 1, 0.72)
                        text: root.pick([I18n.tr("là nghệ sĩ bạn yêu thích nhất tháng này!", "that's your favorite this month!"), I18n.tr("là chân ái của bạn tháng này!", "your top crush this month!"), I18n.tr("đã chiếm trọn tai bạn tháng này!", "owned your ears this month!"), I18n.tr("bá khí áp đảo cả tháng này!", "+1000 aura this month!")], 11)
                        opacity: root.lmA(pArtist, 1, 5)
                        transform: Translate { x: root.lmX(pArtist, 1, 5, 90); y: root.lmY(pArtist, 1, 5) }
                    }
                    Item { width: 1; height: (root.wide ? 28 : 8) * root.u }
                    Bold {
                        width: parent.width
                        sz: 64; lh: 66; tracking: -2.6
                        maximumLineCount: 2
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 30 * root.u
                        elide: Text.ElideRight
                        text: root.heroArtist ? root.heroArtist.artist : ""
                        // tinted with the cover's colours, easing to white
                        readonly property real whiteness: root.clamp01((pArtist.enter - 0.62) / 0.38)
                        readonly property real cyc: (root.time * 0.35) % 1
                        color: root.mix(root.mix(root.textTone(root.artistPalette[1]), root.textTone(root.artistPalette[3]), 0.5 + 0.5 * Math.sin(cyc * Math.PI * 2)), Qt.rgba(1, 1, 1, 1), whiteness)
                        opacity: root.lmA(pArtist, 3, 5)
                        transform: Translate { x: root.lmX(pArtist, 3, 5, 90); y: root.lmY(pArtist, 3, 5) }
                    }
                    Row {
                        opacity: root.lmA(pArtist, 4, 5)
                        transform: Translate { x: root.lmX(pArtist, 4, 5, 90); y: root.lmY(pArtist, 4, 5) }
                        Odo { sz: 26; text: String(root.heroArtist ? root.heroArtist.plays : 0); progress: root.stagger(pArtist.enter, 4, 5) }
                        Bold { sz: 26; wrapMode: Text.NoWrap; text: I18n.tr("x lượt phát", "x Plays") }
                    }
                }

                // the most played song slides out from behind the photo, tilted, its title and count
                // printed along the same slant. Wide: in the gap between the photo and the words, level
                // with the question; tall: off the photo's upper right.
                Item {
                    id: songChip
                    visible: root.heroArtistSong !== null && pArtist.enter > 0
                    readonly property real coverD: root.wide ? root.chipD : Math.max(80 * root.u, artistSeqView.heroEndD * 0.34)
                    readonly property real tilt: root.wide ? -14 : -30
                    readonly property real endCx: root.wide ? root.aGroupX + root.heroSize + root.aGap / 2 - 8 * root.u
                                                            : artistSeqView.heroEndCx + artistSeqView.heroEndD * 0.48 + coverD * 0.25
                    readonly property real endCy: root.wide ? revealCol.y + revealTitle.height - 8 * root.u
                                                            : artistSeqView.heroEndCy - artistSeqView.heroEndD * 0.42
                    readonly property real t: root.stagger(pArtist.enter, 2, 5)
                    readonly property real e: root.eoc(t)
                    // once out, it hangs in the air: a slow bob and a little sway, the label riding along
                    transform: [
                        Rotation { origin.x: songChip.endCx; origin.y: songChip.endCy; angle: Math.sin(root.time * 1.15) * 2.2 * songChip.e },
                        Translate { y: Math.sin(root.time * 1.6) * 7 * root.u * songChip.e }
                    ]
                    RoundedImage {
                        width: songChip.coverD; height: width; radius: 16 * root.u
                        sourceSize: Qt.size(320, 320)
                        source: root.heroArtistSong ? root.heroArtistSong.cover_url || "" : ""
                        initialsText: root.heroArtistSong ? root.heroArtistSong.title : ""
                        x: root.lerp(artistSeqView.heroEndCx, songChip.endCx, songChip.e) - width / 2
                        y: root.lerp(artistSeqView.heroEndCy, songChip.endCy, songChip.e) - height / 2
                        rotation: songChip.tilt * songChip.e
                        scale: 0.85 + 0.15 * songChip.e
                        opacity: Math.min(1, songChip.t * 2.5)
                    }
                    // wide: under the cover along its bottom edge; tall: off its top right
                    Column {
                        readonly property real turn: songChip.tilt * Math.PI / 180
                        readonly property real ax: root.wide ? -songChip.coverD / 2 : songChip.coverD / 2 + 10 * root.u
                        readonly property real ay: root.wide ? songChip.coverD / 2 + 8 * root.u : -songChip.coverD / 2 + 2 * root.u
                        readonly property real e: root.eoc(root.stagger(pArtist.enter, 3, 5))
                        readonly property real back: (1 - e) * 24 * root.u
                        x: songChip.endCx + ax * Math.cos(turn) - ay * Math.sin(turn) - back * Math.cos(turn)
                        y: songChip.endCy + ax * Math.sin(turn) + ay * Math.cos(turn) - back * Math.sin(turn)
                        transformOrigin: Item.TopLeft
                        rotation: songChip.tilt
                        opacity: e
                        readonly property real labelW: root.wide ? songChip.coverD + 18 * root.u : 150 * root.u
                        Bold {
                            width: parent.labelW; sz: root.wide ? 15 : 13; wrapMode: Text.NoWrap; elide: Text.ElideRight
                            text: root.heroArtistSong ? root.heroArtistSong.title : ""
                        }
                        Bold {
                            width: parent.labelW; sz: root.wide ? 13 : 13; wrapMode: Text.NoWrap; elide: Text.ElideRight
                            color: Qt.rgba(1, 1, 1, 0.72)
                            visible: root.heroArtistSong !== null && (root.heroArtistSong.fresh || root.heroArtistSong.plays > 0)
                            text: root.heroArtistSong && root.heroArtistSong.fresh
                                  ? I18n.tr("Thử nghe xem", "Give it a listen")
                                  : I18n.tr("%1 lượt phát", "%1 plays").arg(root.heroArtistSong ? root.heroArtistSong.plays : 0)
                        }
                    }
                }

                // the hero itself, over its song once the song is out
                RoundedImage {
                    readonly property real pulse: 1 + 0.07 * Math.sin(Math.PI * Math.min(0.5, root.spinGlow) * 2)
                    width: artistSeqView.d; height: width; radius: width / 2
                    sourceSize: Qt.size(400, 400)
                    source: root.photoOf(root.heroArtist)
                    initialsText: root.heroArtist ? root.heroArtist.artist : ""
                    placeholderColor: Qt.rgba(1, 1, 1, 0.2)
                    x: artistSeqView.heroCx - width / 2 + (1 - root.eoc(pSpin.enter)) * 120 * root.u
                    y: artistSeqView.heroCy - height / 2
                    scale: artistSeqView.heroD / artistSeqView.d * pulse
                    opacity: root.eoc(pSpin.enter)
                }
            }

            // ===== 5. The top song: the tilted grid, "Hear the melody..", then the song =====
            Item {
                id: songView
                anchors.fill: parent
                visible: root.hasSong && pGrid.enter > 0 && pSong.exit < 1
                // zooms out and fades as it leaves
                readonly property real away: root.eioc(pSong.exit)
                scale: 1 - 0.2 * away
                opacity: 1 - away

                readonly property int cols: Math.max(2, Math.ceil(width / (184 * root.u) / 2) + 1)
                readonly property int rows: 4
                readonly property int n: Math.max(1, root.gridSongs.length)
                readonly property real cover: 163 * root.u
                readonly property real colPitch: 184 * root.u
                readonly property real rowPitch: 184 * root.u
                readonly property real driftPx: 150 * root.u
                readonly property real cx: width / 2
                readonly property real cy: height / 2
                readonly property real cosT: Math.cos(-30 * Math.PI / 180)
                readonly property real sinT: Math.sin(-30 * Math.PI / 180)
                function columnEnter(c) { return root.eoc(root.stagger(pGrid.enter, c + cols, 2 * cols + 1, 0.7)); }
                function column(c) {
                    var dir = c % 2 === 0 ? -1 : 1;
                    return dir * driftPx * (root.gridDrift - 1) + (1 - columnEnter(c)) * dir * height * 1.3;
                }
                function enterX(c) { return (1 - columnEnter(c)) * width * 0.9; }
                // the picked cover: beside the words on a wide window (it stays put there), at the right on a tall one
                readonly property real melodySize: root.wide ? root.heroSize : 212 * root.u
                readonly property real melodyCx: root.wide ? root.heroCx : width - 42 * root.u - melodySize / 2
                readonly property real melodyCy: root.wide ? root.heroCy : root.fy(229) + melodySize / 2
                readonly property real songCy: root.wide ? root.heroCy : root.fy(151) + melodySize / 2
                // the song page: the artist, pressed as an old CD, slides out from behind the cover's left
                readonly property real cdD: melodySize * 0.86
                readonly property real cdOut: melodySize * 0.34
                readonly property real songIn: root.eoc(root.stagger(pSong.enter, 0, 4, 0.6))
                // wide: the cover and its words step right so the disc has room on the left
                readonly property real songShift: root.wide ? Math.max(0, cdOut + cdD / 2 - melodySize / 2 + 24 * root.u - root.groupX) : 0
                readonly property string songLine: root.heroSong ? I18n.tr("%1 của %2", "%1 by %2").arg(root.heroSong.title).arg(root.heroSong.artist) : ""

                Repeater {
                    // built when the story opens, not when the page starts: making ~100 covers in one frame
                    // was the stall before the grid began to drift
                    model: root.active ? (2 * songView.cols + 1) * (2 * songView.rows + 1) : 0
                    RoundedImage {
                        readonly property int c: Math.floor(index / (2 * songView.rows + 1)) - songView.cols
                        readonly property int r: index % (2 * songView.rows + 1) - songView.rows
                        // neighbours step by 1 down a column and by 4 across, so a cover never sits beside itself
                        readonly property var song: root.gridSongs.length ? root.gridSongs[(((c * 4 + r) % songView.n) + songView.n) % songView.n] : null
                        readonly property real gx: c * songView.colPitch
                        readonly property real gy: (r + (c % 2 !== 0 ? 0.5 : 0)) * songView.rowPitch + songView.column(c)
                        readonly property real dist: Math.hypot(c, r) / 5
                        readonly property real p: root.clamp01((root.gridPick - (1 - dist) * 0.35) / 0.65)
                        visible: !(c === 0 && r === 0)
                        width: songView.cover; height: width; radius: 26 * root.u
                        sourceSize: Qt.size(320, 320)
                        source: song ? song.cover_url || "" : ""
                        initialsText: song ? song.title : ""
                        placeholderColor: Qt.rgba(1, 1, 1, 0.2)
                        x: songView.cx + gx * songView.cosT - gy * songView.sinT - width / 2 + songView.enterX(c)
                        y: songView.cy + gx * songView.sinT + gy * songView.cosT - height / 2
                        rotation: -30
                        scale: 1 - 0.35 * root.eic(p)
                        opacity: 1 - p
                    }
                }
                // the question sits on a soft shade so it reads over the covers
                Rectangle {
                    visible: root.shows(pGrid)
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: parent.height * 0.45
                    opacity: root.lmA(pGrid, 0, 2)
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0) }
                        GradientStop { position: 1; color: Qt.rgba(root.m2.r * 0.6, root.m2.g * 0.6, root.m2.b * 0.6, 0.85) }
                    }
                }
                Column {
                    visible: root.shows(pGrid)
                    x: root.wide ? root.groupX : root.inset
                    y: root.fy(628)
                    width: root.column
                    Bold {
                        width: parent.width
                        sz: 40; lh: 42
                        text: root.pick([I18n.tr("Có thể bạn\nnhận ra bài này!", "You might\nrecognize this!"), I18n.tr("Bài này\nquen lắm nè!", "This one\nsounds familiar!"), I18n.tr("Tai bạn\nnhớ bài này!", "Your ears\nremember this!"), I18n.tr("Bài này\nkhét lẹt!", "This one\nis tuff!")], 12)
                        opacity: root.lmA(pGrid, 0, 2)
                        transform: Translate { x: root.lmX(pGrid, 0, 2, 120); y: root.lmY(pGrid, 0, 2) }
                    }
                    Item { width: 1; height: 14 * root.u }
                    Bold {
                        width: parent.width; sz: 24
                        text: root.pick([I18n.tr("hmm, là bài nào nhỉ...", "hmm, which one..."), I18n.tr("ủa, bài gì ta...", "wait, what is this..."), I18n.tr("khoan, để nhớ coi...", "hold on, let me think..."), I18n.tr("đoán sai là quê xệ á...", "guess wrong, lose aura...")], 13)
                        opacity: root.lmA(pGrid, 1, 2)
                        transform: Translate { x: root.lmX(pGrid, 1, 2, 120); y: root.lmY(pGrid, 1, 2) }
                    }
                }

                // "Hear the melody..": the words beside the cover
                Column {
                    visible: root.shows(pMelody)
                    x: root.wide ? root.textX : root.inset
                    y: root.wide ? songView.melodyCy - height / 2 : root.topPad + 80 * root.u
                    width: root.wide ? root.textW : root.width - root.inset - 42 * root.u
                    spacing: 18 * root.u
                    Bold {
                        width: parent.width
                        horizontalAlignment: root.wide ? Text.AlignLeft : Text.AlignRight
                        sz: root.wide ? 48 : 34; lh: root.wide ? 50 : 37
                        text: root.pick([I18n.tr("Nghe giai\nđiệu..", "Hear the\nmelody.."), I18n.tr("Lắng tai\nnghe nè..", "Listen\nclosely.."), I18n.tr("Vặn to\nlên nào..", "Turn it\nup.."), I18n.tr("Khét\nlẹt luôn..", "Lock\nin..")], 14)
                        opacity: root.lmA(pMelody, 0, 2)
                        transform: Translate { x: root.lmX(pMelody, 0, 2, 90, 60); y: root.lmY(pMelody, 0, 2) }
                    }
                    Bold {
                        visible: root.wide
                        width: parent.width
                        sz: 26; lh: 30
                        color: Qt.rgba(1, 1, 1, 0.78)
                        maximumLineCount: 3; elide: Text.ElideRight
                        text: songView.songLine
                        opacity: root.lmA(pMelody, 1, 2)
                        transform: Translate { x: root.lmX(pMelody, 1, 2, 90, 60); y: root.lmY(pMelody, 1, 2) }
                    }
                }
                Bold {
                    visible: !root.wide && root.shows(pMelody)
                    x: 60 * root.u; width: root.width - 102 * root.u
                    y: songView.melodyCy + songView.melodySize / 2 + 18 * root.u
                    horizontalAlignment: Text.AlignRight
                    sz: 30; lh: 34
                    maximumLineCount: 4; elide: Text.ElideRight
                    text: songView.songLine
                    opacity: root.lmA(pMelody, 1, 2)
                    transform: Translate { x: root.lmX(pMelody, 1, 2, 90, 60); y: root.lmY(pMelody, 1, 2) }
                }

                // the song's page: the artist's disc behind the cover, the count beside it
                Item {
                    anchors.fill: parent
                    visible: pSong.enter > 0
                    Item {
                        id: cd
                        width: songView.cdD; height: width
                        x: songView.melodyCx + (songView.songShift - songView.cdOut) * songView.songIn - width / 2
                        y: songView.songCy - height / 2
                        scale: 0.8 + 0.2 * songView.songIn
                        opacity: Math.min(1, songView.songIn * 3)
                        // the pressed side turns; the light on it stays put
                        Item {
                            anchors.fill: parent
                            rotation: root.time * 22
                            RoundedImage {
                                anchors.fill: parent
                                radius: width / 2
                                sourceSize: Qt.size(400, 400)
                                source: root.heroSongArtistCover
                                initialsText: root.heroSong ? root.heroSong.artist : ""
                                placeholderColor: Qt.rgba(1, 1, 1, 0.2)
                            }
                        }
                        // the rainbow sheen of an old disc under a lamp
                        Shape {
                            anchors.fill: parent
                            opacity: 0.3
                            layer.enabled: true
                            layer.samples: 4
                            ShapePath {
                                strokeWidth: -1
                                fillGradient: ConicalGradient {
                                    centerX: cd.width / 2; centerY: cd.height / 2; angle: 35
                                    GradientStop { position: 0.00; color: Qt.rgba(1, 1, 1, 0) }
                                    GradientStop { position: 0.08; color: Qt.rgba(1, 0.55, 0.8, 0.9) }
                                    GradientStop { position: 0.14; color: Qt.rgba(0.5, 0.9, 1, 0.9) }
                                    GradientStop { position: 0.22; color: Qt.rgba(1, 1, 1, 0) }
                                    GradientStop { position: 0.50; color: Qt.rgba(1, 1, 1, 0) }
                                    GradientStop { position: 0.58; color: Qt.rgba(1, 0.9, 0.5, 0.9) }
                                    GradientStop { position: 0.64; color: Qt.rgba(0.6, 0.8, 1, 0.9) }
                                    GradientStop { position: 0.72; color: Qt.rgba(1, 1, 1, 0) }
                                    GradientStop { position: 1.00; color: Qt.rgba(1, 1, 1, 0) }
                                }
                                startX: cd.width; startY: cd.height / 2
                                PathAngleArc {
                                    centerX: cd.width / 2; centerY: cd.height / 2
                                    radiusX: cd.width / 2; radiusY: cd.height / 2
                                    startAngle: 0; sweepAngle: 360
                                }
                            }
                        }
                    }
                    Column {
                        x: root.wide ? root.textX + songView.songShift : root.inset - 3 * root.u
                        y: root.wide ? songView.songCy - height / 2 : root.fy(456)
                        width: root.wide ? root.textW - songView.songShift : root.column
                        Bold {
                            width: parent.width
                            sz: 22; lh: 26
                            color: Qt.rgba(1, 1, 1, 0.72)
                            maximumLineCount: 2; elide: Text.ElideRight
                            visible: root.wide
                            text: songView.songLine
                            opacity: root.lmA(pSong, 1, 4)
                            transform: Translate { x: root.lmX(pSong, 1, 4, 60); y: root.lmY(pSong, 1, 4) }
                        }
                        Item { width: 1; height: 10 * root.u; visible: root.wide }
                        Row {
                            opacity: root.lmA(pSong, 2, 4)
                            transform: Translate { x: root.lmX(pSong, 2, 4, root.wide ? 60 : 0); y: root.lmY(pSong, 2, 4) }
                            Odo { sz: root.wide ? 60 : 46; text: String(root.heroSong ? root.heroSong.plays : 0); progress: root.stagger(pSong.enter, 2, 4) }
                            Bold { sz: root.wide ? 60 : 46; wrapMode: Text.NoWrap; text: I18n.tr(" lượt phát!", " Plays!") }
                        }
                        Bold {
                            width: parent.width; topPadding: 4 * root.u
                            sz: 26; lh: 30
                            color: Qt.rgba(1, 1, 1, 0.72)
                            text: root.pick([I18n.tr("Bài hát yêu thích\ncủa bạn tháng này!!!", "Your favourite song\nthis month!!!"), I18n.tr("Bài ruột\ncủa bạn tháng này!!!", "Your ride-or-die song\nthis month!!!"), I18n.tr("Bài bạn nghe\nđến mòn tai!!!", "The song you\nwore out!!!"), I18n.tr("Bài hát\nđỉnh nóc kịch trần!!!", "Your main character\nsong this month!!!")], 15)
                            opacity: root.lmA(pSong, 3, 4)
                            transform: Translate { x: root.lmX(pSong, 3, 4, root.wide ? 60 : 0); y: root.lmY(pSong, 3, 4) }
                        }
                    }
                    Bold {
                        visible: !root.wide
                        x: 80 * root.u; width: root.width - 122 * root.u
                        y: songView.songCy + songView.melodySize / 2 + 14 * root.u
                        horizontalAlignment: Text.AlignRight
                        sz: 22; lh: 26
                        maximumLineCount: 3; elide: Text.ElideRight
                        text: songView.songLine
                        opacity: root.lmA(pSong, 1, 4)
                        transform: Translate { x: root.lmX(pSong, 1, 4, -60); y: root.lmY(pSong, 1, 4) }
                    }
                }

                // the hero cover: picked from the grid, then the melody cover, then the song page's
                RoundedImage {
                    id: heroCoverImg
                    readonly property real m: root.heroCover
                    readonly property real gy: songView.column(0)
                    readonly property real pulse: 1 + 0.1 * Math.sin(Math.PI * root.gridPick)
                    readonly property real sz: root.lerp(songView.cover * pulse, songView.melodySize, m)
                    width: songView.melodySize; height: width
                    radius: 30 * root.u * songView.melodySize / (212 * root.u)
                    sourceSize: Qt.size(460, 460)
                    source: root.heroSong ? root.heroSong.cover_url || "" : ""
                    initialsText: root.heroSong ? root.heroSong.title : ""
                    x: root.lerp(songView.cx - gy * songView.sinT, songView.melodyCx, m) - width / 2 + songView.enterX(0) * (1 - m)
                       + songView.songShift * songView.songIn
                    y: root.lerp(root.lerp(songView.cy + gy * songView.cosT, songView.melodyCy, m), songView.songCy, root.heroCoverUp) - height / 2
                    scale: sz / songView.melodySize
                    rotation: -30 * (1 - m)
                    opacity: root.eoc(root.stagger(pGrid.enter, songView.cols, 2 * songView.cols + 1, 0.7))
                }
            }

            // ===== 6. The bill =====
            Item {
                id: billView
                anchors.fill: parent
                visible: root.shows(pBill)
                // wide: the totals on the left, the receipt beside them; tall: the title over the receipt
                readonly property real leftW: Math.min(420 * root.u, root.stageW * 0.42)
                readonly property real paperW: root.wide ? Math.min(480 * root.u, root.stageW - leftW - 64 * root.u) : Math.min(root.width - 2 * root.inset + 18 * root.u, 560 * root.u)
                readonly property real groupX: (root.width - leftW - 64 * root.u - paperW) / 2
                Column {
                    x: root.wide ? billView.groupX : root.inset
                    y: root.wide ? (root.height - height) / 2 : root.topPad + 82 * root.u
                    width: root.wide ? billView.leftW : root.column
                    Bold {
                        width: parent.width
                        sz: root.wide ? 44 : 30; lh: root.wide ? 46 : 33
                        text: root.pick([I18n.tr("Xem hóa đơn\ncủa bạn nào", "Let's see\nyour bill"), I18n.tr("Tới giờ\ntính tiền rồi", "Time to\npay up"), I18n.tr("Bình tĩnh,\nhóa đơn nè", "Don't panic,\nit's the bill"), I18n.tr("Ét ô ét,\nhóa đơn tới", "Bill time,\nwe're cooked")], 16)
                        opacity: root.lmA(pBill, 0, 4)
                        transform: Translate { x: root.lmX(pBill, 0, 4, 0, 0); y: root.lmY(pBill, 0, 4, 20) }
                    }
                    Item { width: 1; height: 36 * root.u; visible: root.wide }
                    Odo {
                        visible: root.wide
                        sz: 64; weight: Font.ExtraBold; tracking: -2.4
                        text: root.hoursMinutes(root.stats ? root.stats.total_minutes : 0)
                        progress: root.stagger(pBill.enter, 1, 4)
                        opacity: root.lmA(pBill, 1, 4)
                        transform: Translate { x: root.lmX(pBill, 1, 4, 0, 0); y: root.lmY(pBill, 1, 4) }
                    }
                    Bold {
                        visible: root.wide
                        width: parent.width; sz: 22
                        color: Qt.rgba(1, 1, 1, 0.72)
                        text: I18n.tr("nghe nhạc trong %1", "of music in %1").arg(root.monthName)
                        opacity: root.lmA(pBill, 2, 4)
                        transform: Translate { x: root.lmX(pBill, 2, 4, 0, 0); y: root.lmY(pBill, 2, 4) }
                    }
                    Item { width: 1; height: 22 * root.u; visible: root.wide }
                    Bold {
                        visible: root.wide && root.stats !== null
                        width: parent.width; sz: 22; lh: 30
                        text: root.stats ? I18n.tr("%1 lượt phát\n%2 bài hát\n%3 nghệ sĩ", "%1 plays\n%2 songs\n%3 artists")
                                              .arg(root.stats.plays).arg(root.stats.song_count).arg(root.stats.artist_count) : ""
                        opacity: root.lmA(pBill, 3, 4)
                        transform: Translate { x: root.lmX(pBill, 3, 4, 0, 0); y: root.lmY(pBill, 3, 4) }
                    }
                }
                Item {
                    id: billBox
                    x: root.wide ? billView.groupX + billView.leftW + 64 * root.u : root.inset - 9 * root.u
                    y: root.wide ? root.topPad + 70 * root.u : root.fy(240)
                    width: billView.paperW
                    height: root.height - y
                    transform: Translate {
                        y: (1 - root.eob(pBill.enter, 0.9)) * billBox.height + root.eic(pBill.exit) * billBox.height * 1.1
                    }
                    Flickable {
                        id: billFlick
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: receipt.height + 120 * root.u
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Component.onCompleted: if ("acceptedButtons" in billFlick) billFlick.acceptedButtons = Qt.NoButton
                        // the paper fades into the night at both edges, from the first look on
                        ScrollEdgeFade {
                            flickable: billFlick
                            fadeLength: 72 * root.u
                            alwaysFade: true
                            when: !root.liteMode && pBill.enter > 0.99
                        }
                        Item {
                            id: receipt
                            width: parent.width
                            y: 6 * root.u
                            height: receiptBody.implicitHeight + 80 * root.u
                            // paper torn in a zigzag at the top and the bottom
                            Canvas {
                                anchors.fill: parent
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.reset();
                                    var tooth = 44 * root.u, depth = 18 * root.u, w = width, h = height;
                                    var teeth = Math.max(3, Math.round(w / tooth)), step = w / teeth;
                                    ctx.fillStyle = "#EEECE6";
                                    ctx.beginPath();
                                    ctx.moveTo(0, depth);
                                    for (var i = 0; i < teeth; i++) { ctx.lineTo(i * step + step / 2, 0); ctx.lineTo((i + 1) * step, depth); }
                                    ctx.lineTo(w, h - depth);
                                    for (var j = teeth; j > 0; j--) { ctx.lineTo(j * step - step / 2, h); ctx.lineTo((j - 1) * step, h - depth); }
                                    ctx.closePath();
                                    ctx.fill();
                                }
                            }
                            Column {
                                id: receiptBody
                                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 26 * root.u; rightMargin: 26 * root.u; topMargin: 40 * root.u }
                                readonly property color ink: "#1B1B1B"
                                component Line: Text {
                                    width: receiptBody.width
                                    horizontalAlignment: Text.AlignHCenter
                                    color: receiptBody.ink
                                    font.family: "monospace"
                                    font.pixelSize: 13 * root.u
                                    lineHeightMode: Text.FixedHeight
                                    lineHeight: 17 * root.u
                                    elide: Text.ElideRight
                                }
                                component Dashes: Line { text: "-".repeat(90); elide: Text.ElideNone; clip: true }
                                component Heading: Text {
                                    bottomPadding: 10 * root.u
                                    color: receiptBody.ink
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 18 * root.u
                                    font.weight: Font.Bold
                                    font.letterSpacing: -0.6 * root.u
                                }
                                component ItemRow: RowLayout {
                                    property string image: ""
                                    property bool round: false
                                    property string label: ""
                                    property string value: ""
                                    width: receiptBody.width
                                    height: 28 * root.u
                                    spacing: 8 * root.u
                                    RoundedImage {
                                        Layout.preferredWidth: 18 * root.u; Layout.preferredHeight: 18 * root.u
                                        radius: parent.round ? 9 * root.u : 5 * root.u
                                        sourceSize: Qt.size(48, 48)
                                        source: parent.image
                                        initialsText: parent.label
                                        placeholderColor: "#E53935"
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: parent.label
                                        elide: Text.ElideRight
                                        color: "#3A3A3A"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13.5 * root.u
                                        font.weight: Font.Bold
                                        font.letterSpacing: -0.2 * root.u
                                    }
                                    Text {
                                        text: "- " + parent.value
                                        color: "#3A3A3A"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13.5 * root.u
                                        font.weight: Font.Bold
                                        font.letterSpacing: -0.2 * root.u
                                    }
                                }

                                Dashes {}
                                Line { text: "NUTSTY" }
                                Line { text: I18n.tr("Tổng kết %1", "%1 recap").arg(root.monthName) }
                                Line {
                                    text: I18n.tr("in lúc %1", "printed at %1").arg(Qt.formatDateTime(new Date(), "dd/MM/yyyy/HH:mm"))
                                }
                                Dashes {}
                                Item { width: 1; height: 18 * root.u }
                                Heading { text: I18n.tr("Nghệ sĩ hàng đầu", "Top Artist") }
                                Repeater {
                                    model: root.artists
                                    ItemRow {
                                        image: root.photoOf(modelData)
                                        round: true
                                        label: (index + 1) + "x " + modelData.artist
                                        value: root.hoursDecimal(modelData.minutes)
                                    }
                                }
                                Item { width: 1; height: 18 * root.u }
                                Heading { text: I18n.tr("Bài hát hàng đầu", "Top Music") }
                                Repeater {
                                    model: root.songs
                                    ItemRow {
                                        image: modelData.cover_url || ""
                                        label: (index + 1) + "x " + modelData.title
                                        value: root.hoursDecimal(modelData.minutes)
                                    }
                                }
                                Item { width: 1; height: 36 * root.u }
                                Line {
                                    horizontalAlignment: Text.AlignLeft
                                    text: I18n.tr("Tổng : %1 nghe nhạc", "Total : %1 playtime").arg(root.hoursMinutes(root.stats ? root.stats.total_minutes : 0))
                                }
                                Line {
                                    horizontalAlignment: Text.AlignLeft
                                    color: Qt.rgba(0.106, 0.106, 0.106, 0.6)
                                    text: root.stats
                                          ? I18n.tr("%1 lượt · %2 bài · %3 nghệ sĩ", "%1 plays · %2 songs · %3 artists")
                                                .arg(root.stats.plays).arg(root.stats.song_count).arg(root.stats.artist_count)
                                          : ""
                                }
                                Item { width: 1; height: 10 * root.u }
                                Dashes {}
                                Line { text: I18n.tr("HẾT HÓA ĐƠN", "END OF LINE") }
                                Dashes {}
                            }
                        }
                    }
                }
            }

            // ===== 7. The ending: the card and the words, one group in the middle =====
            Item {
                id: endView
                anchors.fill: parent
                visible: root.shows(pEnd)
                readonly property real cardW: root.wide ? Math.min(460 * root.u, root.stageW * 0.44) : Math.min(root.width - 2 * root.inset, 420 * root.u)
                readonly property real textW: root.wide ? Math.min(460 * root.u, root.stageW - cardW - 64 * root.u) : root.column
                readonly property real groupX: root.wide ? (root.width - cardW - 64 * root.u - textW) / 2 : root.inset
                ListenerCard {
                    id: endCard
                    x: endView.groupX
                    y: root.wide ? (root.height - height) / 2 : root.topPad + 175 * root.u
                    width: endView.cardW
                    height: width / 1.89
                    interactive: false
                    userName: root.userName
                    avatarUrl: root.avatarUrl
                    cardNumber: root.cardNumber
                    joinedAt: root.joinedAt
                    liteMode: root.liteMode
                    swayAmount: 1
                    readonly property real e: root.eoc(root.stagger(pEnd.enter, 0, 4, 0.7))
                    opacity: root.homing ? 0 : e
                    transform: [
                        Translate { y: (1 - endCard.e) * 60 * root.u },
                        Rotation { origin.x: endCard.width / 2; origin.y: endCard.height / 2; angle: -8 * (1 - endCard.e) }
                    ]
                }
                Column {
                    x: root.wide ? endView.groupX + endView.cardW + 64 * root.u : root.inset
                    y: root.wide ? (root.height - height) / 2 : root.topPad + 112 * root.u
                    width: endView.textW
                    Bold {
                        width: parent.width
                        sz: root.wide ? 30 : 34
                        color: Qt.rgba(1, 1, 1, 0.72)
                        text: root.pick([I18n.tr("Đây rồi", "There you go"), I18n.tr("Xong rồi nè", "Ta-da"), I18n.tr("Tèn tén ten", "Behold"), I18n.tr("Hết nước chấm", "Ate, no crumbs")], 17)
                        opacity: root.lmA(pEnd, 0, 4)
                        transform: Translate { x: root.lmX(pEnd, 0, 4, 0, 0); y: root.lmY(pEnd, 0, 4) }
                    }
                    // on a tall window the card sits between the two lines
                    Item { width: 1; height: root.wide ? 10 * root.u : endCard.height + 63 * root.u }
                    Bold {
                        width: parent.width
                        sz: 44; lh: 46
                        text: root.pick([I18n.tr("Đây là tổng kết\n%1 của bạn!", "That's your\n%1 recap!"), I18n.tr("Gói gọn\n%1 của bạn!", "Your %1\nin a nutshell!"), I18n.tr("%1 của bạn\nlà vậy đó!", "So that was\nyour %1!"), I18n.tr("%1 của bạn\nbá khí thật sự!", "Your %1\nhad real aura!")], 18).arg(root.monthName)
                        opacity: root.lmA(pEnd, 1, 4)
                        transform: Translate { x: root.lmX(pEnd, 1, 4, 0, 0); y: root.lmY(pEnd, 1, 4) }
                    }
                    Item { width: 1; height: 28 * root.u }
                    Mono {
                        font.pixelSize: 16 * root.u
                        color: Qt.rgba(1, 1, 1, 0.8)
                        text: I18n.tr("BẤM ĐỂ KẾT THÚC", "CLICK TO FINISH")
                        opacity: root.lmA(pEnd, 3, 4)
                        transform: Translate { y: root.lmY(pEnd, 3, 4) }
                    }
                }
            }
        }

        // ===== Chrome: the avatar and the logo travel between pages =====
        Item {
            id: avatar
            width: root.avD; height: width
            x: root.avX - width / 2
            y: root.avY - height / 2
            scale: root.avPop
            opacity: root.avAlpha
            visible: opacity > 0.003
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: root.mix(Qt.rgba(1, 1, 1, 1), Qt.color("#626262"), root.avRing)
                opacity: root.avRingAlpha
            }
            RoundedImage {
                anchors.fill: parent
                anchors.margins: parent.width * 0.075
                radius: width / 2
                sourceSize: Qt.size(320, 320)
                source: root.avatarUrl
                initialsText: root.userName
                placeholderColor: "#E8E8E8"
            }
        }
        AppIcon {
            source: Qt.resolvedUrl("../assets/icons/nutsty-outline-symbolic.svg")
            iconSize: 32 * root.u
            color: "#FFFFFF"
            x: root.lerp(root.inset, root.width - root.inset - iconSize - 56 * root.u, root.logoSide)
            y: root.topPad + 32 * root.u
            opacity: root.page >= 4 && root.page <= 6 || root.logoSide > 0.01 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }

        // the way out, always in the same corner
        Rectangle {
            id: closeButton
            width: 40 * root.u; height: width; radius: width / 2
            x: root.width - root.inset - width + 4 * root.u
            y: root.topPad + 28 * root.u
            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, closeHover.hovered ? 0.4 : 0.22)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.14)
            Behavior on color { ColorAnimation { duration: 160 } }
            scale: closeHover.hovered ? 1.06 : 1
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            AppIcon {
                anchors.centerIn: parent
                source: Qt.resolvedUrl("../assets/icons/window-close-symbolic.svg")
                iconSize: 18 * root.u
                color: "#FFFFFF"
            }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: root.closeRequested() }
        }

        Text {
            anchors { bottom: parent.bottom; bottomMargin: 16 * root.u; horizontalCenter: parent.horizontalCenter }
            visible: root.page !== root.pageCount - 1
            text: I18n.tr("BẤM ĐỂ TIẾP · ESC ĐỂ ĐÓNG", "CLICK TO GO ON · ESC TO CLOSE")
            color: Qt.rgba(1, 1, 1, 0.3)
            font.family: "monospace"
            font.pixelSize: 11
            font.letterSpacing: 1
        }
    }

    // After the blink: the scanned card hangs in the night, bobbing and tilting, then swoops off right
    ListenerCard {
        id: introCard
        readonly property real f: root.introFly
        readonly property real bob: Math.sin(root.time * 1.7) * 7 * root.u
        readonly property real cx0: root.introFrom.x + root.introFrom.width / 2
        readonly property real cy0: root.introFrom.y + root.introFrom.height / 2
        visible: root.intro > 0.001 && root.introFrom.width > 0
        width: root.introFrom.width
        height: width / 1.89
        x: cx0 - width / 2 + root.eic(f) * (root.width - cx0 + width * 0.9) + Math.sin(Math.PI * f) * 30 * root.u
        y: cy0 - height / 2 + bob - Math.sin(Math.PI * f) * 110 * root.u + f * f * 60 * root.u
        rotation: Math.sin(root.time * 1.2) * 3 + Math.sin(Math.PI * Math.min(1, f * 1.4)) * 14 + f * 8
        scale: 1 - 0.18 * root.eoc(f)
        opacity: root.intro * (1 - root.clamp01((f - 0.75) / 0.25))
        interactive: false
        swayAmount: 1
        userName: root.userName
        avatarUrl: root.avatarUrl
        cardNumber: root.cardNumber
        joinedAt: root.joinedAt
        liteMode: root.liteMode
    }

    // The ending's card on its way home to the header
    ListenerCard {
        id: homeCard
        readonly property real t: root.homeT
        visible: root.homing
        width: root.lerp(root.homeFrom.width, root.homeTo.width, t)
        height: width / 1.89
        x: root.lerp(root.homeFrom.x + root.homeFrom.width / 2, root.homeTo.x + root.homeTo.width / 2, t) - width / 2
        y: root.lerp(root.homeFrom.y + root.homeFrom.height / 2, root.homeTo.y + root.homeTo.height / 2, t) - height / 2
           - Math.sin(Math.PI * t) * 80 * root.u
        rotation: -Math.sin(Math.PI * t) * 10
        interactive: false
        swayAmount: 1 - t
        userName: root.userName
        avatarUrl: root.avatarUrl
        cardNumber: root.cardNumber
        joinedAt: root.joinedAt
        liteMode: root.liteMode
    }

    // The blink: two lids of night close from above and below, the edges curved like an eye
    Shape {
        id: lids
        anchors.fill: parent
        visible: root.lid > 0.001
        layer.enabled: visible
        layer.samples: 4
        readonly property real edge: root.lid * (height / 2 + 2)
        readonly property real bulge: 70 * root.u * Math.min(1, root.lid * 1.3)
        ShapePath {
            strokeWidth: -1
            fillColor: "#070708"
            startX: 0; startY: 0
            PathLine { x: lids.width; y: 0 }
            PathLine { x: lids.width; y: lids.edge }
            PathQuad { x: 0; y: lids.edge; controlX: lids.width / 2; controlY: lids.edge + lids.bulge }
            PathLine { x: 0; y: 0 }
        }
        ShapePath {
            strokeWidth: -1
            fillColor: "#070708"
            startX: 0; startY: lids.height
            PathLine { x: lids.width; y: lids.height }
            PathLine { x: lids.width; y: lids.height - lids.edge }
            PathQuad { x: 0; y: lids.height - lids.edge; controlX: lids.width / 2; controlY: lids.height - lids.edge - lids.bulge }
            PathLine { x: 0; y: lids.height }
        }
    }

    // the page fade's mask: opaque, ramping to clear over the last stretch at the top and bottom
    Item {
        id: pageFadeMask
        width: root.width
        height: root.height
        visible: false
        layer.enabled: true
        readonly property real frac: height > 0 ? Math.min(0.2, 72 * root.u / height) : 0
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: pageFadeMask.frac; color: "#ffffff" }
                GradientStop { position: 1.0 - pageFadeMask.frac; color: "#ffffff" }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }
    Item {
        id: frameMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: root.cornerRadius; color: "black" }
    }
}
