import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import "."

Item {
    id: root

    property var currentTrack: null
    property real currentTime: 0.0
    property real totalDuration: 0.0
    property bool isPlaying: false
    property bool isLiked: false
    property color accentColor: Theme.accent
    property var activeLyrics: []
    property bool isLoadingLyrics: false
    property string resolvedSquareImage: ""
    // Last real playback position from mpv and when it was read (ms); drives the per-frame lyric clock
    property real syncTime: 0.0
    property double syncStamp: 0
    property Item backgroundSourceItem: null
    property int panelStyle: 1 // 1: Flush Split-Rail, 2: Bento Glass Island
    property string activeTab: "lyrics" // "lyrics" | "queue" | "comments"
    property bool isLoggedIn: false
    // Corner radius declared once; everything nested derives from it (R_inner = R_outer - inset)
    readonly property real panelRadius: 24
    readonly property real dockInset: 8
    property var currentTracks: []
    property real layoutDependency: 0.0 // Driven by host slide progress so LiquidGlass re-samples its backdrop offset
    readonly property real targetPanelWidth: Math.max(380, Math.min(460, Math.round((parent ? parent.width : 1200) * 0.34)))

    // Performance Gating (Zero-overhead: disables all shaders, FBOs, and lyric updates when hidden, closed, or in another app)
    property bool isEffectivelyActive: true
    readonly property bool isPanelRenderable: root.visible && root.opacity > 0.01 && root.isEffectivelyActive

    signal closeRequested()
    signal openDetailsRequested()
    signal seekRequested(real seconds)
    signal playPauseRequested()
    signal nextRequested()
    signal previousRequested()
    signal toggleLikeRequested()
    signal trackPlayRequested(var track, int index)
    signal trackContextMenuRequested(var track, real gx, real gy)
    signal tabRequested(string tab)

    readonly property var upNextTracks: {
        if (!root.currentTracks || root.currentTracks.length === 0) return [];
        var curIdx = -1;
        if (root.currentTrack) {
            for (var i = 0; i < root.currentTracks.length; ++i) {
                if (root.isSameTrack(root.currentTracks[i], root.currentTrack)) {
                    curIdx = i;
                    break;
                }
            }
        }
        if (curIdx >= 0) {
            return root.currentTracks.slice(curIdx + 1);
        }
        return root.currentTracks;
    }

    function isSameTrack(a, b) {
        if (!a || !b) return false;
        if (typeof win !== "undefined" && win && typeof win.isSameTrack === "function") {
            return win.isSameTrack(a, b);
        }
        if (a.id && b.id && a.id === b.id) return true;
        if (a.videoId && b.videoId && a.videoId === b.videoId) return true;
        if (a.path && b.path && a.path === b.path) return true;
        return (a.title && b.title && a.title === b.title && a.artist && b.artist && a.artist === b.artist);
    }

    function formatDuration(sec) {
        if (!sec || isNaN(sec) || sec <= 0) return "--:--";
        var m = Math.floor(sec / 60);
        var s = Math.floor(sec % 60);
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
    }

    function getTrackDuration(trk) {
        if (!trk) return "";
        if (typeof trk.duration === "number") return formatDuration(trk.duration);
        if (typeof trk.duration === "string" && trk.duration.length > 0) return trk.duration;
        if (trk.length) return formatDuration(trk.length);
        return "";
    }

    // -------------------------------------------------------------------------
    // EXPRESSIVE LYRICS SCHEDULE (Mochy ExpressiveText.kt timing model)
    // Every line gets a fixed timetable when the lyrics load: when it comes in,
    // when its singing ends, whether it overlaps the next line and when it leaves.
    // - Lines that don't overlap are replaced in place: the old one flies off
    //   while the new one rises into the same spot.
    // - Lines that overlap stack: the next one waits underneath, then glides up
    //   into the top spot as the line above flies off.
    // All motion is a pure function of a smooth per-frame clock, so nothing pops.
    // -------------------------------------------------------------------------
    property int currentLyricIndex: -1
    property bool isInterlude: false

    // -------------------------------------------------------------------------
    // POSTER TITLE (Mochy PosterText + ExpressiveTitle)
    // A new song opens on its title set big, words rising in one after another.
    // When its lyrics are found, the big title slides down and shrinks into the
    // small title under the artist while the lyrics take the space it leaves,
    // and slides back up if they go away. titleFound: 0 big title, 1 lyrics.
    // -------------------------------------------------------------------------
    readonly property bool hasSyncedLyrics: !!(root.activeLyrics && root.activeLyrics.length > 0)
    readonly property string trackTitle: root.currentTrack ? String(root.currentTrack.title || root.currentTrack.name || "") : ""
    readonly property string trackArtist: root.currentTrack ? String(root.currentTrack.artist || root.currentTrack.author || "") : ""
    readonly property string trackKey: root.currentTrack ? String(root.currentTrack.videoId || root.currentTrack.path || root.trackTitle) : ""
    property real titleFound: hasSyncedLyrics ? 1.0 : 0.0
    // Seconds since the title began coming in; it runs the same entrance clock as a lyric line
    property real titleClock: 99.0
    // What the poster shows: held on the old song until it has faded out, so text never swaps in view
    property string shownTitle: trackTitle
    property string shownArtist: trackArtist
    // 1: poster and credits shown, 0: faded out between two songs
    property real swapFade: 1.0
    // Desktop addition: the title holds this long on a new song before it gives way to the lyrics,
    // so it is seen even when the lyrics come from cache in the same instant
    readonly property int kTitleHoldMs: 1600

    NumberAnimation {
        id: titleFoundAnim
        target: root; property: "titleFound"; duration: 820
        easing.type: Easing.BezierSpline; easing.bezierCurve: [0.3, 0.0, 0.1, 1.0, 1.0, 1.0]
    }
    // A song change never cuts: the old poster and credits fade out, the new title is put in
    // place unseen, then its words rise in one after another as the credits fade back
    SequentialAnimation {
        id: trackSwapAnim
        NumberAnimation { target: root; property: "swapFade"; to: 0.0; duration: 260; easing.type: Easing.InOutQuad }
        ScriptAction { script: root.commitNewTrack() }
        ScriptAction { script: titleClockAnim.restart() }
        NumberAnimation { target: root; property: "swapFade"; to: 1.0; duration: 520; easing.type: Easing.OutCubic }
    }
    NumberAnimation { id: titleClockAnim; target: root; property: "titleClock"; from: 0.0; to: 6.0; duration: 6000 }
    Timer {
        id: titleHold
        interval: root.kTitleHoldMs
        onTriggered: root.settleTitle()
    }
    function settleTitle() {
        if (titleHold.running || trackSwapAnim.running) return;
        var target = root.hasSyncedLyrics ? 1.0 : 0.0;
        if (Math.abs(root.titleFound - target) < 0.001) return;
        titleFoundAnim.stop();
        titleFoundAnim.to = target;
        titleFoundAnim.start();
    }
    function commitNewTrack() {
        titleFoundAnim.stop();
        root.titleFound = 0.0;
        titleClockAnim.stop();
        root.titleClock = 0.0;
        root.shownTitle = root.trackTitle;
        root.shownArtist = root.trackArtist;
        root.shownKey = root.trackKey;
        titleHold.restart();
    }
    onTrackKeyChanged: {
        trackSwapAnim.stop();
        // the old lyrics clear a moment before the key turns: don't let the old title rise while it fades
        titleFoundAnim.stop();
        if (root.trackTitle === "") { root.shownTitle = ""; root.shownArtist = ""; root.shownKey = root.trackKey; root.swapFade = 1.0; return; }
        trackSwapAnim.start();
    }
    // same song, details filled in later (artist arriving after the title): follow quietly
    // (title and key change together on a new song, in no set order: only follow when the key held)
    property string shownKey: trackKey
    onTrackTitleChanged: if (!trackSwapAnim.running && root.trackKey === root.shownKey) root.shownTitle = root.trackTitle
    onTrackArtistChanged: if (!trackSwapAnim.running && root.trackKey === root.shownKey) root.shownArtist = root.trackArtist
    onHasSyncedLyricsChanged: settleTitle()

    readonly property color mochyInk: "#F1ECEC"
    readonly property color mochyInkSoft: Qt.rgba(0.945, 0.925, 0.925, 0.62)
    readonly property color mochyInkDim: Qt.rgba(0.945, 0.925, 0.925, 0.40)
    readonly property string mochyFont: "Inter, Inter Display, SF Pro Display, system-ui, sans-serif"

    // Timing constants (seconds), mirrored from Mochy
    readonly property real kEnterLead: 0.42
    readonly property real kEnterDur: 0.56
    readonly property real kEnterStagger: 0.065
    readonly property real kExitDur: 0.46
    readonly property real kExitStagger: 0.04
    readonly property real kGapExitDelay: 0.45
    readonly property real kMinInterludeGap: 4.0

    // Per-line timetable, rebuilt whenever the lyrics change
    property var lyricSchedule: ({ count: 0, starts: [], ends: [], enter: [], exit: [], gone: [], overlaps: [], words: [], scales: [], fonts: [] })

    // Smooth clock: extrapolates between position samples every frame
    property real animClock: 0.0
    property real clockSample: 0.0
    property double clockStamp: 0
    // Latency compensation so words light up right on the beat
    readonly property real effectiveLyricTime: root.animClock + 0.06

    ListModel { id: visibleLinesModel }

    // Resolved cover image URL
    // Animated covers follow the app's setting (Settings > animated cover / canvas source)
    property bool animatedCoverEnabled: (typeof win !== "undefined" && win) ? win.animatedCoverEnabled : true
    property string canvasPreference: (typeof win !== "undefined" && win) ? win.canvasPreference : "apple_first"
    readonly property string coverImageUrl: {
        if (root.resolvedSquareImage !== "") {
            var r = root.resolvedSquareImage;
            return (r.startsWith("/") && !r.startsWith("file://")) ? ("file://" + r) : r;
        }
        if (!root.currentTrack) return "";
        var s = String(root.currentTrack.image || root.currentTrack.artUrl || root.currentTrack.cover || root.currentTrack.thumbnail || "");
        if (!s && root.currentTrack.videoId) {
            s = "https://i.ytimg.com/vi/" + root.currentTrack.videoId + "/hqdefault.jpg";
        }
        if (s.indexOf("i.ytimg.com") !== -1) s = s.split("?")[0];
        return (s.startsWith("/") && !s.startsWith("file://")) ? ("file://" + s) : s;
    }

    function easeOutCubic(x) {
        var c = Math.max(0.0, Math.min(1.0, x));
        var u = 1.0 - c;
        return 1.0 - u * u * u;
    }
    function smoothstep(x) {
        var c = Math.max(0.0, Math.min(1.0, x));
        return c * c * (3.0 - 2.0 * c);
    }
    function smootherstep(x) {
        var c = Math.max(0.0, Math.min(1.0, x));
        return c * c * c * (c * (c * 6.0 - 15.0) + 10.0);
    }

    // Mochy Dynamic Downscaling: long lines step down so they wrap cleanly
    function computeBaseFontSize(words) {
        if (!words || words.length === 0) return 26;
        var count = words.length;
        var totalChars = 0;
        for (var i = 0; i < words.length; ++i) {
            totalChars += (words[i].text || "").length;
        }
        if (count >= 12 || totalChars >= 42) return 18;
        if (count >= 9 || totalChars >= 30) return 21;
        if (count >= 6 || totalChars >= 20) return 24;
        return 27;
    }

    function toSec(val) {
        if (val === undefined || val === null) return 0.0;
        var n = Number(val);
        if (isNaN(n)) return 0.0;
        if (n > 10000) return n / 1000.0;
        return n;
    }

    function lineStartOf(entry) {
        return entry ? toSec(entry.time !== undefined ? entry.time : (entry.startTime || 0)) : 0.0;
    }

    // Word timings: the line's own when it has them, otherwise the time until the
    // next line shared out by word length, holding a little back for a breath.
    function parseWords(entry, idx) {
        if (!entry) return [];
        var rawText = (entry && entry.text) ? String(entry.text).trim() : "";
        var lineStart = lineStartOf(entry);
        var wList = [];
        if (entry.words && entry.words.length > 0) {
            for (var w = 0; w < entry.words.length; ++w) {
                var wd = entry.words[w];
                var wt = (wd && wd.text) ? String(wd.text).trim() : "";
                if (wt) {
                    var s = (wd.start !== undefined) ? toSec(wd.start) : (wd.startTime !== undefined ? toSec(wd.startTime) : lineStart);
                    var e = (wd.end !== undefined) ? toSec(wd.end) : (wd.endTime !== undefined ? toSec(wd.endTime) : (s + 0.25));
                    wList.push({ text: wt, start: s, end: e, duration: Math.max(0.05, e - s), isHeld: !!(wd.isHeld || (e - s >= 0.85)) });
                }
            }
        } else if (rawText) {
            var parts = rawText.split(/\s+/).filter(function(p) { return p.length > 0; });
            if (parts.length === 0) return [];
            var nextStart = (idx + 1 < activeLyrics.length) ? lineStartOf(activeLyrics[idx + 1]) : (lineStart + 4.0);
            var lineEnd = Math.max(nextStart, lineStart + 0.6);
            var singing = Math.min((lineEnd - lineStart) * 0.86, parts.length * 0.9);
            var total = 0;
            for (var k = 0; k < parts.length; ++k) total += parts[k].length + 1.5;
            var cursor = lineStart;
            for (var p = 0; p < parts.length; ++p) {
                var len = singing * (parts[p].length + 1.5) / total;
                wList.push({ text: parts[p], start: cursor, end: cursor + len, duration: Math.max(0.05, len), isHeld: false });
                cursor += len;
            }
        }
        return wList;
    }

    function rebuildSchedule() {
        var lines = activeLyrics || [];
        var n = lines.length;
        var sch = { count: n, starts: [], ends: [], enter: [], exit: [], gone: [], overlaps: [], words: [], scales: [], fonts: [] };
        for (var i = 0; i < n; ++i) {
            var ws = parseWords(lines[i], i);
            sch.words.push(ws);
            sch.scales.push(computeWordScales(ws));
            var st = lineStartOf(lines[i]);
            sch.starts.push(st);
            sch.ends.push(ws.length > 0 ? ws[ws.length - 1].end : st);
        }
        for (var a = 0; a < n; ++a) {
            if (a === 0) sch.enter.push(sch.starts[0] < kMinInterludeGap ? 0.0 : sch.starts[0] - kEnterLead);
            else sch.enter.push(Math.max(sch.starts[a] - kEnterLead, sch.starts[a - 1]));
        }
        for (var b = 0; b < n; ++b) {
            sch.overlaps.push(b < n - 1 && sch.ends[b] - 0.1 > sch.enter[b + 1]);
        }
        for (var c = 0; c < n; ++c) {
            var ex = -1;
            if (c < n - 1) {
                var nx = c + 1;
                var interlude = (sch.starts[nx] - sch.ends[c] >= kMinInterludeGap) && (sch.enter[nx] - (sch.ends[c] + kGapExitDelay + 0.25) > 1.5);
                if (interlude) ex = Math.min(sch.ends[c] + kGapExitDelay, sch.enter[nx]);
                else if (sch.overlaps[c]) ex = sch.ends[c] + 0.15;
                else ex = Math.max(sch.enter[nx], Math.min(sch.ends[c] - 0.1, Math.max(sch.enter[nx], sch.starts[nx])));
            }
            sch.exit.push(ex);
            sch.gone.push(ex < 0 ? Number.POSITIVE_INFINITY : ex + kExitDur + 12 * kExitStagger + 0.12);
            // Stacked lines share the canvas, so they come in a touch smaller
            var stacked = sch.overlaps[c] || (c > 0 && sch.overlaps[c - 1]);
            var base = computeBaseFontSize(sch.words[c]);
            sch.fonts.push(stacked ? Math.round(base * 0.86) : base);
        }
        lyricSchedule = sch;
        visibleLinesModel.clear();
        syncVisibleLines(root.effectiveLyricTime);
    }

    // Which lines are on screen at t: back from the newest line that has come in,
    // through every line not gone yet (an overlapping line keeps the scan going).
    function syncVisibleLines(t) {
        var sch = lyricSchedule;
        if (!sch || sch.count === 0) {
            if (visibleLinesModel.count > 0) visibleLinesModel.clear();
            return;
        }
        var lo = 0, hi = sch.count - 1, shown = -1;
        while (lo <= hi) {
            var mid = (lo + hi) >> 1;
            if (sch.enter[mid] <= t) { shown = mid; lo = mid + 1; } else hi = mid - 1;
        }
        var want = [];
        for (var j = shown; j >= 0 && want.length < 4; --j) {
            if (t < sch.gone[j]) want.unshift(j);
            else if (!sch.overlaps[j]) break;
        }
        // Diff into the model so lines already on screen keep their delegates
        for (var r = visibleLinesModel.count - 1; r >= 0; --r) {
            if (want.indexOf(visibleLinesModel.get(r).lineIdx) < 0) visibleLinesModel.remove(r);
        }
        for (var w = 0; w < want.length; ++w) {
            var pos = 0;
            var present = false;
            for (var m = 0; m < visibleLinesModel.count; ++m) {
                var li = visibleLinesModel.get(m).lineIdx;
                if (li === want[w]) { present = true; break; }
                if (li < want[w]) pos = m + 1;
            }
            if (!present) visibleLinesModel.insert(pos, { lineIdx: want[w] });
        }
    }

    function advanceClock() {
        var target = root.currentTime;
        // Extrapolate from mpv's last reported position every frame, not the 25 fps UI clock
        if (root.isPlaying && root.syncStamp > 0) {
            target = root.syncTime + Math.max(0.0, (Date.now() - root.syncStamp) / 1000.0);
        }
        // Monotonic while playing; small corrections are absorbed, only a real seek moves it back
        if (target > root.animClock || root.animClock - target > 0.3) root.animClock = target;
        syncVisibleLines(root.effectiveLyricTime);
    }

    FrameAnimation {
        running: root.isPanelRenderable && root.lyricSchedule.count > 0 && root.isPlaying
        onTriggered: root.advanceClock()
    }

    function updateLyricState() {
        if (!root.isPanelRenderable) return;
        if (!activeLyrics || activeLyrics.length === 0) {
            currentLyricIndex = -1;
            isInterlude = false;
            return;
        }
        var pos = root.currentTime;
        var idx = -1;
        for (var i = 0; i < activeLyrics.length; ++i) {
            if (lineStartOf(activeLyrics[i]) <= pos) idx = i;
            else break;
        }
        currentLyricIndex = idx;
        isInterlude = visibleLinesModel.count === 0;
    }

    onCurrentTimeChanged: {
        var jumped = Math.abs(root.currentTime - root.animClock) > 1.0;
        root.clockSample = root.currentTime;
        root.clockStamp = Date.now();
        if (!root.isPanelRenderable) return;
        if (jumped) {
            // Seek: start the clock fresh; lines that land now animate in from their birth
            root.animClock = root.currentTime;
            visibleLinesModel.clear();
        }
        advanceClock();
        updateLyricState();
    }
    onActiveLyricsChanged: {
        rebuildSchedule();
        if (root.isPanelRenderable) updateLyricState();
    }
    onIsPanelRenderableChanged: {
        if (isPanelRenderable) {
            root.animClock = root.currentTime;
            visibleLinesModel.clear();
            advanceClock();
            updateLyricState();
        }
    }
    Component.onCompleted: rebuildSchedule()

    // Mochy wordScales Algorithm (AlternatePlayerStyles.kt lines 89-102):
    // Shortest word >= 3 chars gets 1.55x (shout word).
    // Words >= 11 chars scale to 0.74x, >= 9 chars scale to 0.86x, else 1.0x.
    function computeWordScales(words) {
        if (!words || words.length === 0) return [];
        var minLen = 999;
        var shoutIdx = -1;
        for (var i = 0; i < words.length; ++i) {
            var str = words[i].text ? String(words[i].text) : "";
            var len = str.length;
            if (len >= 3 && len < minLen) {
                minLen = len;
                shoutIdx = i;
            }
        }

        var scales = [];
        for (var j = 0; j < words.length; ++j) {
            var s = words[j].text ? String(words[j].text) : "";
            var l = s.length;
            if (j === shoutIdx && words.length > 1) {
                scales.push(1.55);
            } else if (l >= 11) {
                scales.push(0.74);
            } else if (l >= 9) {
                scales.push(0.86);
            } else {
                scales.push(1.0);
            }
        }
        return scales;
    }

    // -------------------------------------------------------------------------
    // OPTION 1: FLUSH SPLIT-RAIL ELEVATION SHADOW (Behind panel, casting leftward)
    // -------------------------------------------------------------------------
    Rectangle {
        id: splitElevationShadow
        visible: root.isPanelRenderable && root.panelStyle === 1
        anchors.right: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 32
        z: -1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
        }
    }

    // -------------------------------------------------------------------------
    // OPTION 2: BENTO GLASS ISLAND DIFFUSE SHADOW (Behind card, diffuse ambient)
    // -------------------------------------------------------------------------
    Rectangle {
        id: bentoShadowLayer
        visible: root.isPanelRenderable && root.panelStyle === 2
        // Soft, low, offset downward: sits the island on the window instead of outlining it
        anchors.fill: parent
        anchors.topMargin: 10
        anchors.bottomMargin: -6
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        radius: root.panelRadius
        color: Qt.rgba(0, 0, 0, 0.22)
        z: -1
        layer.enabled: root.isPanelRenderable && root.panelStyle === 2
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 32
        }
    }

    // -------------------------------------------------------------------------
    // 1. MASTER PANEL CONTAINER WITH CONCENTRIC CLIP
    // -------------------------------------------------------------------------
    Item {
        id: panelContainer
        anchors.fill: parent
        layer.enabled: root.isPanelRenderable
        // SDF corner clip (rounded_clip.frag): anti-aliased edge with no dark fringe,
        // which the old MultiEffect mask left at all four corners
        layer.effect: ShaderEffect {
            readonly property real leftR: root.panelStyle === 1 ? 0 : root.panelRadius
            property vector2d u_resolution: Qt.vector2d(Math.max(1, width), Math.max(1, height))
            property vector4d u_radii: Qt.vector4d(leftR, root.panelRadius, root.panelRadius, leftR)
            fragmentShader: Qt.resolvedUrl("../assets/shaders/rounded_clip.frag.qsb")
        }

        // =====================================================================
        // LAYER A: LIQUID GLASS BACKDROP
        // One see-through glass material behind every tab (lyrics, comments, up next),
        // tinted dark enough for long text.
        // =====================================================================
        Item {
            id: backdropWrapper
            anchors.fill: parent

            // Base deep dark tone, shown while the glass is not rendering
            Rectangle {
                anchors.fill: parent
                color: root.panelStyle === 1 ? "#0e0f14" : "#0a0b10"
            }

            LiquidGlass {
                id: panelLiquidBackdrop
                anchors.fill: parent
                visible: root.isPanelRenderable
                extraDependency: root.layoutDependency
                backgroundSourceItem: root.backgroundSourceItem
                radius: root.panelStyle === 1 ? 0 : root.panelRadius
                displacement: 12.0
                bevelWidth: 16.0
                blurRadius: 0.85
                tintColor: Qt.rgba(0.06, 0.07, 0.10, 0.74)
                isFlowActive: false
            }
        }

        // =====================================================================
        // VIEW 1: LYRICS MODE (Mochy CircleCover + Expressive Kinetic Canvas)
        // =====================================================================
        Item {
            id: lyricsView
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: root.activeTab === "lyrics" ? 1.0 : 0.0
            scale: root.activeTab === "lyrics" ? 1.0 : 0.94
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            // =====================================================================
            // LAYER B: CIRCLECOVER (MOCHY EXACT GEOMETRIC CIRCLE ARC - ELEVATED)
            // Center: (0.13 * W, -0.28 * W), Radius: 1.14 * W, Height: 0.88 * W
            // Sweeps through right edge at 0.457 W, left edge at 0.853 W
            // Elevated to give +130px generous breathing room for multi-line lyrics!
            // "ở trên rõ, ở dưới làm mờ"
            // =====================================================================
            Item {
                id: circleCover
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.round(width * 0.88)
            z: 2

            readonly property real cw: width

            // Mathematical Exact Parabolic Curve from (x=1.0W, y=0.4567W) to (x=0.0W, y=0.8526W)
            // Quadratic Bezier: P0 = (1.0W, 0.4567W), P1 = (0.50W, 0.9150W), P2 = (0.0W, 0.8526W)
            // 8x MSAA GPU analytical rendering (preferredRendererType: Shape.CurveRenderer + layer.samples: 8)
            Shape {
                id: circleArcMask
                anchors.fill: parent
                visible: false
                layer.enabled: root.isPanelRenderable
                layer.samples: 8
                layer.smooth: true
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: "#ffffff"
                    strokeColor: "transparent"
                    strokeWidth: 0
                    startX: 0
                    startY: 0

                    PathLine { x: circleCover.cw; y: 0 }
                    PathLine { x: circleCover.cw; y: circleCover.cw * 0.4567 }
                    // A true circle (Mochy's CircleCover): centre (0.13 W, -0.28 W), radius 1.14 W.
                    // It meets the right edge at 0.4567 W and the left at 0.8526 W, and the seek
                    // ring below runs on exactly this circle.
                    PathArc {
                        x: 0
                        y: circleCover.cw * 0.8526
                        radiusX: circleCover.cw * 1.14
                        radiusY: circleCover.cw * 1.14
                        direction: PathArc.Clockwise
                    }
                    PathLine { x: 0; y: 0 }
                }
            }

            // Cover glow: instead of a dark drop shadow under the arc, the artwork spills its own light
            // downward. A heavily blurred, saturated copy sits behind the sharp cover and extends past
            // the curve, fading out so the lyrics underneath stay readable.
            Item {
                id: coverGlow
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: parent.height + glowSpill
                readonly property real glowSpill: Math.round(circleCover.cw * 0.60)
                visible: root.isPanelRenderable

                Image {
                    id: coverGlowSrc
                    sourceSize: Qt.size(128, 128)
                    anchors.fill: parent
                    source: root.coverImageUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    visible: false
                    layer.enabled: coverGlow.visible
                }
                Item {
                    id: coverGlowMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: coverGlow.visible
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#ffffffff" }
                            GradientStop { position: 0.52; color: "#ffffffff" }
                            GradientStop { position: 0.72; color: "#b3ffffff" }
                            GradientStop { position: 1.0; color: "#00ffffff" }
                        }
                    }
                }
                MultiEffect {
                    anchors.fill: parent
                    source: coverGlowSrc
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 64
                    saturation: 0.9
                    brightness: 0.12
                    maskEnabled: true
                    maskSource: coverGlowMask
                    // MultiEffect maps mask alpha through smoothstep(t*(1+s)-s, t*(1+s)). Only t=0.5, s=1
                    // gives smoothstep(0, 1): a real fade. t=0 makes any alpha > 0 fully opaque, so the
                    // glow ended in a hard edge at the bottom of this item.
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                    autoPaddingEnabled: false
                    opacity: 0.85
                }
            }

            // Cover Image: 100% Crystal Sharp, bounded strictly within the antialiased parabolic curve
            Item {
                id: sharpImageContainer
                anchors.fill: parent
                layer.enabled: root.isPanelRenderable
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: circleArcMask
                    autoPaddingEnabled: false
                }

                // 1. Album artwork: the shared cover surface, so a song with an Apple Music animated
                // cover or a Spotify Canvas plays it here (looped, muted, paused with the music);
                // without one it is the still cover. The arc mask above cuts it like the still did.
                MediaCoverSurface {
                    id: topSharpCover
                    anchors.fill: parent
                    track: root.currentTrack
                    radius: 0
                    showShadow: false
                    borderWidth: 0
                    overrideImage: root.coverImageUrl
                    isPlaying: root.isPlaying
                    animatedCoverEnabled: root.animatedCoverEnabled
                    canvasPreference: root.canvasPreference
                }

                // 2. Mochy Soft Vignette along the lower rim
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.60; color: "transparent" }
                        GradientStop { position: 0.85; color: Qt.rgba(0, 0, 0, 0.06) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.14) }
                    }
                }
            }

            // No lit stroke or bloom on the arc: the curve is drawn by the artwork edge alone,
            // with the cover glow below carrying the light (a glowing line read as a sticker cut-out)

            // Click artwork to expand full-screen Now Playing
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openDetailsRequested()
            }
        }

        // Seek bar on the cover's rim (Mochy CoverRing): thin on the edge, springs out on hover,
        // press or song start; drag along the curve to scrub
        CoverSeekRing {
            id: seekRing
            anchors.fill: parent
            z: 6
            cx: circleCover.cw * 0.13
            cy: -circleCover.cw * 0.28
            r: circleCover.cw * 1.14
            live: root.isPanelRenderable && root.activeTab === "lyrics"
            visible: root.isPanelRenderable
            position: root.currentTime
            duration: root.totalDuration
            syncTime: root.syncTime
            syncStamp: root.syncStamp
            isPlaying: root.isPlaying
            trackKey: root.currentTrack ? String(root.currentTrack.videoId || root.currentTrack.path || root.currentTrack.title || "") : ""
            onSeekRequested: seconds => root.seekRequested(seconds)
        }

        // Top-Right Close Button (Glass Capsule Circle)
        Item {
            id: closeBtn
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 16
            width: 32
            height: 32
            z: 20

            HoverHandler { id: closeH }
            scale: closeH.hovered ? 1.08 : 1.0
            Behavior on scale { NumberAnimation { duration: 120 } }

            Rectangle {
                anchors.fill: parent
                radius: 16
                color: closeH.hovered ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.48)
                border.color: Qt.rgba(1, 1, 1, 0.20)
                border.width: 1
                Behavior on color { ColorAnimation { duration: 120 } }

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/window-close-symbolic.svg"
                    iconSize: 12
                    color: "#ffffff"
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.closeRequested()
            }
        }

        // =====================================================================
        // LAYER D: BOTTOM DOCK, reserves the action row's space (Lyrics | Up Next) for the lyric canvas
        // =====================================================================
        Item {
            id: bottomDock
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.leftMargin: root.dockInset
            anchors.rightMargin: root.dockInset
            anchors.bottomMargin: root.dockInset
            height: actionDock.height
            z: 10

        }

        // =====================================================================
        // POSTER CREDITS (Mochy PosterText): the artist, then the title set small.
        // The small title shows only once the big one has slid down into it.
        // =====================================================================
        Column {
            id: posterCredits
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: bottomDock.top
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            anchors.bottomMargin: 16
            spacing: 3
            z: 5
            visible: root.currentTrack !== null
            opacity: root.swapFade

            MarqueeText {
                width: parent.width
                height: 18
                visible: root.shownArtist !== ""
                text: root.shownArtist
                color: root.mochyInkSoft
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
                active: root.isPanelRenderable
            }
            MarqueeText {
                id: posterSmallTitleBox
                width: parent.width
                height: 24
                text: root.shownTitle
                color: root.mochyInkSoft
                font.family: Theme.fontFamily
                font.pixelSize: 19
                font.weight: Font.Bold
                font.letterSpacing: -0.035 * 19
                active: root.isPanelRenderable && opacity > 0.99
                opacity: Math.max(0, Math.min(1, (root.titleFound - 0.6) / 0.4))
            }
        }
        // Landing point for the big title: where the small title's first glyph line starts
        Item {
            id: posterSmallTitle
            parent: posterSmallTitleBox
            readonly property real pixelSize: 19
            x: 0; y: Math.round((posterSmallTitleBox.height - pixelSize * 1.2) / 2)
            width: 1; height: 1
        }

        // =====================================================================
        // LAYER E: EXPANDED EXPRESSIVE POSTER CANVAS (CENTRAL REGION)
        // Sits directly below the elevated arc cut (top = 0.88 * W + 8px).
        // Uses FULL width (redundant right controls pill removed as requested).
        // Massive ~320px vertical breathing room!
        // Hosts:
        // 1. Interlude countdown 3-dots
        // 2. Kinetic Expressive Lyrics with auto-fitting font scale & dual-phase exit
        // 3. Expressive Title poster fallback
        // =====================================================================
        Item {
            id: expressiveCanvas
            // The bar coming out past the rim moves the words down with it (Mochy RingPush 34)
            transform: Translate { y: seekRing.expand * 34 }
            anchors.top: parent.top
            anchors.topMargin: Math.round(circleCover.cw * 0.88 + 10)
            anchors.bottom: posterCredits.top
            anchors.bottomMargin: 12
            anchors.left: parent.left
            anchors.leftMargin: 24
            anchors.right: parent.right
            anchors.rightMargin: 24
            z: 5
            clip: false

            // -----------------------------------------------------------------
            // STATE 1: THREE-DOT INTERLUDE PAGER
            // Shows when counting down instrumental breaks or before singing
            // -----------------------------------------------------------------
            Item {
                id: interludeDotsBox
                anchors.fill: parent
                readonly property bool shouldShow: root.activeLyrics && root.activeLyrics.length > 0 && visibleLinesModel.count === 0 && root.titleFound > 0.999
                opacity: shouldShow ? 1.0 : 0.0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    spacing: 10

                    Repeater {
                        model: 3
                        Rectangle {
                            id: dotItem
                            required property int index
                            width: 10
                            height: 10
                            radius: 5
                            color: "#ffffff"

                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                running: interludeDotsBox.visible && root.isPanelRenderable
                                PauseAnimation { duration: dotItem.index * 180 }
                                NumberAnimation { from: 0.20; to: 0.95; duration: 420; easing.type: Easing.InOutQuad }
                                NumberAnimation { from: 0.95; to: 0.20; duration: 420; easing.type: Easing.InOutQuad }
                                PauseAnimation { duration: (2 - dotItem.index) * 180 }
                            }
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // STATE 2: EXPRESSIVE LYRICS ENGINE (MOCHY TIMETABLE)
            // One delegate per line on screen. Each word comes in staggered
            // (fade, rise, un-blur, zoom 0.94 -> 1) and leaves the same way
            // (fade, rise, zoom up, blur). A line below an overlapping line is
            // pushed down by it, then glides up as that line flies off.
            // -----------------------------------------------------------------
            Item {
                id: expressiveLyricsBox
                anchors.fill: parent
                visible: root.hasSyncedLyrics && opacity > 0.001
                // PosterText: the lyrics come up as the big title leaves
                opacity: root.swapFade * Math.max(0.0, Math.min(1.0, (root.titleFound - 0.25) / 0.75))

                Item {
                    id: linesStackContainer
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 16
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8

                    Repeater {
                        id: lineRepeater
                        model: visibleLinesModel

                        delegate: Item {
                            id: lineItem
                            required property int index
                            required property int lineIdx

                            readonly property var sch: root.lyricSchedule
                            readonly property bool validLine: lineIdx >= 0 && lineIdx < sch.count
                            readonly property var lineWords: validLine ? sch.words[lineIdx] : []
                            readonly property var lineScales: validLine ? sch.scales[lineIdx] : []
                            readonly property real baseFont: validLine ? sch.fonts[lineIdx] : 26
                            readonly property real exitAt: validLine ? sch.exit[lineIdx] : -1
                            readonly property bool overlapsNext: validLine && sch.overlaps[lineIdx]

                            // A line that lands late (a seek, the panel opening) still comes in
                            property real bornAt: 0.0
                            readonly property real enterAt: {
                                var planned = validLine ? sch.enter[lineIdx] : 0.0;
                                return (bornAt - planned > 0.25) ? bornAt : planned;
                            }
                            Component.onCompleted: bornAt = root.animClock

                            readonly property real t: root.effectiveLyricTime
                            readonly property real liftPx: baseFont

                            function enterOf(order) {
                                return root.easeOutCubic((t - enterAt - order * root.kEnterStagger) / root.kEnterDur);
                            }
                            function exitOf(order) {
                                if (exitAt < 0) return 0.0;
                                return root.smoothstep((t - exitAt - order * root.kExitStagger) / root.kExitDur);
                            }

                            // Overlapping lines above hold this one down, then let it glide up
                            readonly property real pushY: {
                                var y = 0.0;
                                var n = lineRepeater.count;
                                for (var k = 0; k < index && k < n; ++k) {
                                    var above = lineRepeater.itemAt(k);
                                    if (!above || !above.overlapsNext || above.exitAt < 0) continue;
                                    var hold = 1.0 - root.smootherstep((t - above.exitAt) / root.kExitDur);
                                    y += (above.height + above.baseFont * 0.28) * hold;
                                }
                                return y;
                            }

                            // Whole-line blur for the entrance and exit (one layer, only while moving)
                            readonly property real lineBlurPx: {
                                var mid = Math.max(0, Math.floor(lineWords.length / 2));
                                return (1.0 - enterOf(mid)) * 10.0 + exitOf(mid) * 12.0;
                            }

                            width: linesStackContainer.width
                            height: lineFlow.height
                            y: pushY
                            z: 10 - index

                            // Kept on for the line's whole life: toggling a layer mid-flight rebuilds it and hitches a frame
                            layer.enabled: root.isPanelRenderable
                            layer.effect: MultiEffect {
                                blurEnabled: true
                                blur: Math.min(1.0, lineItem.lineBlurPx / 16.0)
                                blurMax: 16
                                autoPaddingEnabled: true
                            }

                            // Sequential reading head for this line's words
                            readonly property int activeWordIndex: {
                                var ws = lineWords;
                                if (!ws || ws.length === 0) return -1;
                                var tt = t;
                                for (var i = 0; i < ws.length; i++) {
                                    var w = ws[i];
                                    if (tt < w.start) return i - 1;
                                    if (tt < w.end) return i;
                                }
                                return ws.length;
                            }

                            Flow {
                                id: lineFlow
                                width: parent.width
                                spacing: 8

                                FontMetrics {
                                    id: baseFontMetrics
                                    font.family: Theme.fontFamily
                                    font.pixelSize: lineItem.baseFont
                                    font.bold: Font.DemiBold
                                }

                                readonly property real maxRowHeight: Math.round(lineItem.baseFont * 1.55 * 1.42)
                                readonly property real baselineY: Math.round(lineItem.baseFont * 1.55 * 1.05)

                                Repeater {
                                    model: lineItem.lineWords

                                    delegate: Item {
                                        id: wordCell
                                        required property int index
                                        required property var modelData

                                        readonly property string wordText: modelData ? String(modelData.text || "") : ""
                                        readonly property real peakScale: (lineItem.lineScales && index < lineItem.lineScales.length) ? lineItem.lineScales[index] : 1.0
                                        readonly property bool isShoutWord: peakScale > 1.15
                                        property real shoutProgress: 0.0

                                        // Entrance / exit motion (Mochy GraphicsLayerScope.motion)
                                        readonly property real enterE: lineItem.enterOf(index)
                                        readonly property real exitO: lineItem.exitOf(index)
                                        readonly property real motionY: (1.0 - enterE) * lineItem.liftPx * 0.55 - exitO * exitO * lineItem.liftPx * 0.9
                                        readonly property real motionZoom: (0.94 + 0.06 * enterE) * (1.0 + 0.08 * exitO)
                                        opacity: Math.max(0.0, Math.min(1.0, enterE * (1.0 - exitO)))

                                        // The whole line zooms about its left edge and middle, so words keep their places
                                        transform: [
                                            Scale {
                                                xScale: wordCell.motionZoom
                                                yScale: wordCell.motionZoom
                                                origin.x: -wordCell.x
                                                origin.y: lineFlow.height / 2 - wordCell.y
                                            },
                                            Translate { y: wordCell.motionY }
                                        ]

                                        // Monotonic shout growth: no bounce, never shrinks back
                                        NumberAnimation {
                                            id: shoutAnim
                                            target: wordCell
                                            property: "shoutProgress"
                                            to: 1.0
                                            duration: Math.max(450, Math.min(750, Math.round(wordCell.wDur * 1000 * 1.15)))
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: [0.12, 0.88, 0.24, 1.0]
                                        }

                                        function checkAndTriggerShout() {
                                            if (isShoutWord && isSinging && shoutProgress < 0.99 && !shoutAnim.running) {
                                                shoutAnim.restart();
                                            }
                                        }
                                        onIsSingingChanged: checkAndTriggerShout()
                                        onIsShoutWordChanged: checkAndTriggerShout()
                                        onIsPastChanged: {
                                            if (isPast && isShoutWord && !shoutAnim.running) shoutProgress = 1.0;
                                        }
                                        Component.onCompleted: {
                                            if (isShoutWord) {
                                                if (isPast) shoutProgress = 1.0;
                                                else if (isSinging) checkAndTriggerShout();
                                            }
                                        }

                                        readonly property real wStart: (modelData && modelData.start !== undefined) ? Number(modelData.start) : 0.0
                                        readonly property real wEnd: (modelData && modelData.end !== undefined) ? Number(modelData.end) : (wStart + 0.1)
                                        readonly property real wDur: Math.max(0.05, (modelData && modelData.duration !== undefined) ? Number(modelData.duration) : (wEnd - wStart))
                                        readonly property bool isHeld: (modelData && modelData.isHeld !== undefined) ? !!modelData.isHeld : (wDur >= 0.85)

                                        // Strict monotonic reading head: never grows before the singer gets there
                                        readonly property bool isPast: (lineItem.activeWordIndex >= 0) && (index < lineItem.activeWordIndex || (index === lineItem.activeWordIndex && lineItem.t >= wEnd))
                                        readonly property bool isSinging: (lineItem.activeWordIndex >= 0) && (index === lineItem.activeWordIndex) && (lineItem.t >= wStart) && (lineItem.t < wEnd)
                                        readonly property real wordProgress: isPast ? 1.0 : (isSinging ? Math.max(0.0, Math.min(1.0, (lineItem.t - wStart) / wDur)) : 0.0)

                                        // The clock is already per-frame smooth, so the sweep reads it directly
                                        readonly property real smoothProg: wordProgress
                                        // Bloom head trails the sweep by 120ms (comet glow)
                                        readonly property real bloomProg: isSinging ? Math.max(0.0, Math.min(1.0, (lineItem.t - 0.12 - wStart) / wDur)) : 0.0
                                        readonly property real bloomLagDelta: wordCell.isSinging ? (wordCell.smoothProg - wordCell.bloomProg) : 0.0

                                        function cubicBezier(p0, p1, p2, p3, x) {
                                            var u = 1 - x;
                                            return 3 * u * u * x * p1 + 3 * u * x * x * p2 + x * x * x;
                                        }
                                        function empEasing(x) {
                                            if (x < 0.5) return cubicBezier(0.0, 0.3, 0.25, 1.0, x * 2.0);
                                            return 1.0 - cubicBezier(0.0, 0.5, 0.6, 1.0, (x - 0.5) * 2.0);
                                        }

                                        readonly property real yCurve: isSinging ? (isHeld ? empEasing(smoothProg) : Math.sin(Math.PI * smoothProg)) : 0.0
                                        readonly property real waveScale: 1.0 + (isHeld ? 0.045 : 0.010) * yCurve
                                        readonly property real effectiveScale: isShoutWord ? (1.0 + (peakScale - 1.0) * shoutProgress) : peakScale

                                        width: Math.round(charRow.implicitWidth * effectiveScale)
                                        height: lineFlow.maxRowHeight

                                        Item {
                                            id: innerTransformWrap
                                            x: Math.round((parent.width - charRow.implicitWidth) / 2)
                                            y: Math.round(lineFlow.baselineY - baseFontMetrics.ascent)
                                            width: charRow.implicitWidth
                                            height: charRow.implicitHeight

                                            transform: [
                                                Scale {
                                                    xScale: wordCell.effectiveScale
                                                    yScale: wordCell.effectiveScale
                                                    origin.x: charRow.implicitWidth / 2
                                                    origin.y: baseFontMetrics.ascent
                                                }
                                            ]

                                            Loader {
                                                id: glowLoader
                                                anchors.fill: charRow
                                                active: root.isPanelRenderable && wordCell.isSinging
                                                visible: active
                                                z: 0
                                                sourceComponent: Component {
                                                    MultiEffect {
                                                        source: charRow
                                                        anchors.fill: parent
                                                        shadowEnabled: true
                                                        shadowColor: (root.accentColor && root.accentColor !== "") ? root.accentColor : "#ffffff"
                                                        shadowBlur: 0.95
                                                        shadowOpacity: wordCell.isSinging ? (0.92 * Math.sin(Math.PI * wordCell.smoothProg)) : 0.0
                                                        shadowHorizontalOffset: -wordCell.bloomLagDelta * charRow.width * 0.45
                                                        shadowVerticalOffset: 0
                                                        shadowScale: 1.12
                                                        visible: shadowOpacity > 0.01
                                                    }
                                                }
                                            }

                                            Row {
                                                id: charRow
                                                spacing: 0
                                                z: 1

                                                Repeater {
                                                    model: (wordCell.wordText || "").split("")

                                                    delegate: Item {
                                                        id: charItem
                                                        required property var modelData
                                                        required property int index
                                                        readonly property string ch: modelData
                                                        readonly property int charCount: Math.max(1, (wordCell.wordText || "").length)
                                                        readonly property real charFrom: index / charCount
                                                        readonly property real charTo: (index + 1) / charCount
                                                        readonly property real charProgress: wordCell.isPast ? 1.0 :
                                                            (wordCell.isSinging ? Math.max(0.0, Math.min(1.0, (wordCell.smoothProg - charFrom) / Math.max(0.001, charTo - charFrom))) : 0.0)

                                                        // Persistent rolling lift once a letter is sung
                                                        property real liftProgress: (charProgress > 0.0 || wordCell.isPast) ? 1.0 : 0.0
                                                        Behavior on liftProgress {
                                                            NumberAnimation { duration: 750; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0.0, 0.2, 1.0] }
                                                        }
                                                        readonly property real hermiteLift: {
                                                            var w = Math.max(0.0, Math.min(1.0, liftProgress));
                                                            return w * w * (3.0 - 2.0 * w);
                                                        }

                                                        width: charText.implicitWidth
                                                        height: charText.implicitHeight

                                                        transform: [
                                                            Translate { y: -charItem.hermiteLift * 2.5 },
                                                            Scale {
                                                                xScale: wordCell.isShoutWord ? 1.0 : (1.0 + (wordCell.waveScale - 1.0) * 0.5)
                                                                yScale: wordCell.isShoutWord ? 1.0 : (1.0 + (wordCell.isHeld ? 0.06 : 0.04) * wordCell.yCurve)
                                                                origin.x: charItem.width / 2
                                                                origin.y: charItem.height
                                                            }
                                                        ]

                                                        Text {
                                                            id: charText
                                                            anchors.centerIn: parent
                                                            text: charItem.ch
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: lineItem.baseFont
                                                            font.bold: wordCell.effectiveScale > 1.2 ? true : Font.DemiBold
                                                            color: {
                                                                if (wordCell.isPast || charItem.charProgress >= 1.0) return "#ffffff";
                                                                if (charItem.charProgress <= 0.0) return Qt.rgba(1.0, 1.0, 1.0, 0.38);
                                                                return Qt.rgba(1.0, 1.0, 1.0, 0.38 + 0.62 * charItem.charProgress);
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // STATE 3: POSTER TITLE (Mochy ExpressiveTitle)
            // The song's title as a poster: one short word shouted at 1.55x, long words
            // stepped down, tight lines, words rising in one after another. It is the
            // big words while there are no lyrics; once they are found it slides into
            // the small title in the credits below.
            // -----------------------------------------------------------------
            Item {
                id: expressiveTitleBox
                anchors.fill: parent
                visible: root.titleFound < 0.999 && root.shownTitle !== ""
                opacity: root.swapFade

                readonly property var words: root.shownTitle.split(" ").filter(w => w.length > 0)
                readonly property var scales: {
                    var ws = words, emph = -1, minLen = 999;
                    for (var i = 0; i < ws.length; ++i)
                        if (ws[i].length >= 3 && ws[i].length < minLen) { minLen = ws[i].length; emph = i; }
                    var out = [];
                    for (var j = 0; j < ws.length; ++j) {
                        var n = ws[j].length;
                        out.push(j === emph && ws.length > 1 ? 1.55 : (n >= 11 ? 0.74 : (n >= 9 ? 0.86 : 1.0)));
                    }
                    return out;
                }
                readonly property real baseSize: 40
                readonly property real spacingRatio: 0.24
                // Space it may fill: above the "finding lyrics" note
                readonly property real fitHeight: Math.max(60, height - (statusRow.visible ? statusRow.height + 14 : 0))

                // Measured once at 100 px and scaled: a side-effect-free width for any size
                FontMetrics { id: boldMetrics; font.family: Theme.fontFamily; font.pixelSize: 100; font.weight: Font.Bold }
                FontMetrics { id: blackMetrics; font.family: Theme.fontFamily; font.pixelSize: 100; font.weight: Font.Black }
                function wordWidth(word, px, scale) {
                    var m = scale > 1 ? blackMetrics : boldMetrics;
                    var size = px * scale;
                    // letterSpacing -0.035em per glyph, as drawn
                    return (m.advanceWidth(word) / 100 - 0.035 * word.length) * size;
                }
                // fitTitle: long titles start smaller, then step down until no word runs past the
                // width and the wrapped rows fit the height
                function fits(px) {
                    var gap = px * spacingRatio, rowW = 0, rowH = 0, total = 0;
                    for (var i = 0; i < words.length; ++i) {
                        var w = wordWidth(words[i], px, scales[i]);
                        if (w > width) return false;
                        if (rowW > 0 && rowW + gap + w > width) { total += rowH; rowW = 0; rowH = 0; }
                        rowW += (rowW > 0 ? gap : 0) + w;
                        rowH = Math.max(rowH, px * scales[i] * 0.96);
                    }
                    return total + rowH <= fitHeight;
                }
                readonly property real fitted: {
                    if (width <= 0 || words.length === 0) return baseSize;
                    var len = Math.max(1, root.shownTitle.length);
                    var px = baseSize * Math.sqrt(Math.max(0.52, Math.min(1.0, 14 / len)));
                    for (var k = 0; k < 8 && !fits(px); ++k) px *= 0.9;
                    return px;
                }

                Item {
                    id: bigTitle
                    width: parent.width
                    height: titleFlow.implicitHeight
                    // Slide from here to the small title's place, shrinking from the top-left corner
                    readonly property point dest: {
                        root.titleFound; posterSmallTitle.y; expressiveCanvas.height;
                        return posterSmallTitle.mapToItem(expressiveTitleBox, 0, 0);
                    }
                    readonly property real f: root.titleFound
                    transform: [
                        Scale { xScale: 1 + (posterSmallTitle.pixelSize / expressiveTitleBox.fitted - 1) * bigTitle.f; yScale: xScale }
                    ]
                    x: bigTitle.dest.x * f
                    y: bigTitle.dest.y * f
                    // it becomes the small title in the last part of the slide
                    opacity: 1 - Math.max(0, Math.min(1, (f - 0.6) / 0.35))

                    // The whole title softens in and out of focus as a lyric line does (one layer)
                    readonly property real blurPx: {
                        var mid = Math.floor(Math.max(0, expressiveTitleBox.words.length - 1) / 2);
                        return (1.0 - root.easeOutCubic((root.titleClock - mid * root.kEnterStagger) / root.kEnterDur)) * 10.0;
                    }
                    layer.enabled: root.isPanelRenderable
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: Math.min(1.0, bigTitle.blurPx / 16.0)
                        blurMax: 16
                        autoPaddingEnabled: true
                    }

                    Flow {
                        id: titleFlow
                        width: parent.width
                        spacing: expressiveTitleBox.fitted * expressiveTitleBox.spacingRatio

                        Repeater {
                            model: expressiveTitleBox.words
                            // Each word comes in exactly like a lyric word: rises, fades and zooms
                            // from 0.94 with the same stagger and curve. The shout word arrives at
                            // normal size and only swells to its full size once the title has landed.
                            delegate: Item {
                                id: titleWord
                                required property string modelData
                                required property int index
                                readonly property real peak: expressiveTitleBox.scales[index] || 1.0
                                readonly property bool isShout: peak > 1.15
                                property real shoutProgress: 0.0
                                // set at peak size, drawn scaled down: crisp at every step of the swell
                                readonly property real drawScale: isShout ? (1.0 + (peak - 1.0) * shoutProgress) / peak : 1.0

                                readonly property real enterE: root.easeOutCubic((root.titleClock - index * root.kEnterStagger) / root.kEnterDur)
                                readonly property real motionZoom: 0.94 + 0.06 * enterE

                                // rows align on the bottom like FlowRow(itemVerticalAlignment = Bottom)
                                width: Math.round(wordText.implicitWidth * drawScale)
                                height: expressiveTitleBox.fitted * 1.55 * 0.96
                                opacity: Math.max(0.0, Math.min(1.0, enterE))
                                transform: [
                                    Scale {
                                        xScale: titleWord.motionZoom
                                        yScale: titleWord.motionZoom
                                        origin.x: -titleWord.x
                                        origin.y: titleFlow.height / 2 - titleWord.y
                                    },
                                    Translate { y: (1.0 - titleWord.enterE) * expressiveTitleBox.fitted * 0.55 }
                                ]

                                // the swell starts when the last word has come in, on the lyric shout curve
                                readonly property bool shoutDue: isShout
                                    && root.titleClock >= (expressiveTitleBox.words.length - 1) * root.kEnterStagger + root.kEnterDur * 0.85
                                onShoutDueChanged: {
                                    if (shoutDue) {
                                        if (shoutProgress < 0.99) shoutAnim.restart();
                                    } else {
                                        shoutAnim.stop();
                                        shoutProgress = 0.0;
                                    }
                                }
                                Component.onCompleted: if (shoutDue) shoutProgress = 1.0
                                NumberAnimation {
                                    id: shoutAnim
                                    target: titleWord; property: "shoutProgress"; to: 1.0; duration: 650
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.12, 0.88, 0.24, 1.0, 1.0, 1.0]
                                }

                                Text {
                                    id: wordText
                                    anchors.left: parent.left
                                    anchors.bottom: parent.bottom
                                    text: titleWord.modelData
                                    color: root.mochyInk
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Math.round(expressiveTitleBox.fitted * titleWord.peak)
                                    font.weight: titleWord.isShout ? Font.Black : Font.Bold
                                    font.letterSpacing: -0.035 * Math.round(expressiveTitleBox.fitted * titleWord.peak)
                                    transform: Scale {
                                        xScale: titleWord.drawScale
                                        yScale: titleWord.drawScale
                                        origin.x: 0
                                        origin.y: wordText.height
                                    }
                                }
                            }
                        }
                    }
                }

                // While lyrics are being fetched: spinning, morphing shape instead of "no lyrics"
                Row {
                    id: statusRow
                    anchors.left: parent.left
                    // right under the title as first set, so the seek ring's push never lands it on the credits
                    y: titleFlow.implicitHeight + 16
                    spacing: 10
                    opacity: Math.max(0, 1 - root.titleFound * 3)
                    visible: opacity > 0.01

                    ShapeLoader {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.isLoadingLyrics
                        size: 22
                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.9)
                    }
                    AppIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !root.isLoadingLyrics
                        source: "../assets/icons/view-lyrics-symbolic.svg"
                        iconSize: 14
                        color: root.mochyInkDim
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.isLoadingLyrics ? I18n.tr("Đang tìm lời bài hát...", "Finding lyrics...")
                                                   : I18n.tr("Chưa có lời đồng bộ", "No synchronized lyrics")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: root.mochyInkSoft
                    }
                }
            }
        }
    }

        // =====================================================================
        // VIEW 2: QUEUE MODE ("Playing Next" List + Current Track Header)
        // =====================================================================
        Item {
            id: queueView
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: root.activeTab === "queue" ? 1.0 : 0.0
            scale: root.activeTab === "queue" ? 1.0 : 0.94
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            // Header (Title, Track count, Close button)
            Item {
                id: queueHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 16
                height: 48
                z: 20

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Phát tiếp theo", "Playing Next")
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.bold: true
                    color: "#ffffff"
                }

                // Close Button (Glass Capsule Circle)
                Item {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    height: 30

                    HoverHandler { id: qCloseH }
                    scale: qCloseH.hovered ? 1.08 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120 } }

                    Rectangle {
                        anchors.fill: parent
                        radius: 15
                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, qCloseH.hovered ? 0.28 : 0.14)
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.30)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        AppIcon {
                            anchors.centerIn: parent
                            source: "../assets/icons/window-close-symbolic.svg"
                            iconSize: 12
                            color: "#ffffff"
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }
            }

            // Up Next List
            ListView {
                id: queueListView
                anchors.top: queueHeader.bottom
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 8
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.bottomMargin: actionDock.height + actionDock.anchors.bottomMargin + root.dockInset
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                model: root.upNextTracks

                header: Column {
                    width: queueListView.width
                    spacing: 8
                    bottomPadding: 6

                    // Now Playing Header Label
                    Text {
                        visible: root.currentTrack !== null
                        text: I18n.tr("ĐANG PHÁT", "NOW PLAYING")
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 0.8
                        color: root.accentColor
                        leftPadding: 4
                    }

                    // Current Playing Track Card
                    Item {
                        id: currentPlayingCard
                        visible: root.currentTrack !== null
                        width: parent.width
                        height: 56

                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: Qt.rgba(1, 1, 1, 0.04)
                            border.color: curCardHover.hovered 
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45) 
                                : Qt.rgba(1, 1, 1, 0.10)
                            border.width: 1
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 12

                            // Artwork with live playing equalizer bars
                            Item {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40

                                RoundedImage {
                                    anchors.fill: parent
                                    radius: 6
                                    source: root.coverImageUrl
                                    fillMode: Image.PreserveAspectCrop
                                    fallbackIcon: "../assets/icons/folder-music-symbolic.svg"
                                    fallbackIconSize: 18
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 8
                                    color: Qt.rgba(0, 0, 0, 0.50)
                                    visible: root.isPlaying

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 2.5
                                        Repeater {
                                            model: 3
                                            Rectangle {
                                                width: 3
                                                height: 8 + (index % 2) * 6
                                                radius: 1.5
                                                color: root.accentColor
                                                SequentialAnimation on height {
                                                    running: root.isPlaying && root.visible && root.activeTab === "queue"
                                                    loops: Animation.Infinite
                                                    NumberAnimation { from: 5; to: 16; duration: 280 + index * 110; easing.type: Easing.InOutQuad }
                                                    NumberAnimation { from: 16; to: 5; duration: 280 + index * 110; easing.type: Easing.InOutQuad }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Info (Title, Artist)
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: root.currentTrack ? (root.currentTrack.title || root.currentTrack.name || I18n.tr("Bài hát Nutsty", "Nutsty Track")) : ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.bold: true
                                    color: "#ffffff"
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.currentTrack ? (root.currentTrack.artist || root.currentTrack.artists || I18n.tr("Nghệ sĩ chưa rõ", "Unknown Artist")) : ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Qt.rgba(1, 1, 1, 0.75)
                                    elide: Text.ElideRight
                                }
                            }

                            // 3-Dots Action Button (Isolated from row-click)
                            Item {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                Layout.alignment: Qt.AlignVCenter
                                z: 10

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 16
                                    color: curMoreH.hovered ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                AppIcon {
                                    anchors.centerIn: parent
                                    source: "../assets/icons/view-more-symbolic.svg"
                                    iconSize: 18
                                    color: curMoreH.hovered ? "#ffffff" : Qt.rgba(1, 1, 1, 0.75)
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                HoverHandler { id: curMoreH }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: mouse => {
                                        mouse.accepted = true;
                                        var pt = mapToItem(null, mouse.x, mouse.y);
                                        root.trackContextMenuRequested(root.currentTrack, pt.x, pt.y);
                                    }
                                }
                            }
                        }

                        HoverHandler { id: curCardHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            z: 1
                            onClicked: root.openDetailsRequested()
                        }
                    }

                    // Up Next Section Label
                    Item {
                        width: parent.width
                        height: 28
                        visible: root.upNextTracks.length > 0

                        Text {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            leftPadding: 4
                            text: I18n.tr("DANH SÁCH TIẾP THEO", "UP NEXT")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 0.8
                            color: Qt.rgba(1, 1, 1, 0.72)
                        }
                    }
                }

                delegate: Item {
                    id: queueItem
                    required property int index
                    required property var modelData

                    width: queueListView.width
                    height: 52

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: rowHover.hovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    RowLayout {
                        // Above the row-wide play MouseArea (z: 1): otherwise it swallowed the three-dot
                        // button's click and played the track instead of opening the menu.
                        z: 2
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 10
                        spacing: 10

                        Item {
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40

                            RoundedImage {
                                anchors.fill: parent
                                radius: 6
                                source: {
                                    var trk = queueItem.modelData;
                                    if (!trk) return "";
                                    var s = trk.image || trk.artUrl || trk.cover || trk.thumbnail || "";
                                    if (!s && trk.videoId) {
                                        s = "https://i.ytimg.com/vi/" + trk.videoId + "/hqdefault.jpg";
                                    }
                                    if (s.indexOf("i.ytimg.com") !== -1) s = s.split("?")[0];
                                    return (s.startsWith("/") && !s.startsWith("file://")) ? ("file://" + s) : s;
                                }
                                fillMode: Image.PreserveAspectCrop
                                fallbackIcon: "../assets/icons/media-optical-audio-symbolic.svg"
                                fallbackIconSize: 18
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: queueItem.modelData ? (queueItem.modelData.title || queueItem.modelData.name || I18n.tr("Bài hát", "Track")) : ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                color: rowHover.hovered ? "#ffffff" : Qt.rgba(1, 1, 1, 0.90)
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: queueItem.modelData ? (queueItem.modelData.artist || queueItem.modelData.artists || I18n.tr("Nghệ sĩ chưa rõ", "Unknown Artist")) : ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Qt.rgba(1, 1, 1, 0.72)
                                elide: Text.ElideRight
                            }
                        }

                        // 3-Dots Action Button (Dedicated click target with high z-index)
                        Item {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            Layout.alignment: Qt.AlignVCenter
                            z: 10

                            Rectangle {
                                anchors.fill: parent
                                radius: 16
                                color: moreHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            AppIcon {
                                anchors.centerIn: parent
                                source: "../assets/icons/view-more-symbolic.svg"
                                iconSize: 18
                                color: moreHover.hovered ? "#ffffff" : Qt.rgba(1, 1, 1, 0.75)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            HoverHandler { id: moreHover }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: mouse => {
                                    mouse.accepted = true;
                                    var pt = mapToItem(null, mouse.x, mouse.y);
                                    root.trackContextMenuRequested(queueItem.modelData, pt.x, pt.y);
                                }
                            }
                        }
                    }

                    HoverHandler { id: rowHover }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        z: 1
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                var pt = mapToItem(null, mouse.x, mouse.y);
                                root.trackContextMenuRequested(queueItem.modelData, pt.x, pt.y);
                            } else {
                                root.trackPlayRequested(queueItem.modelData, queueItem.index);
                            }
                        }
                    }
                }
            }

            ScrollEdgeFade {
                flickable: queueListView
                when: root.isPanelRenderable && root.activeTab === "queue"
            }

            // Empty State
            Item {
                anchors.centerIn: parent
                width: parent.width - 40
                visible: root.upNextTracks.length === 0 && (root.currentTrack === null)

                EmptyState {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 32, 340)
                    icon: "../assets/icons/material/ms-queue_music.svg"
                    shape: "clover"
                    accentColor: root.accentColor
                    title: I18n.pick("queue.empty", ["Hàng đợi trống", "Chưa ai xếp hàng cả", "Vắng như chợ chiều", "Hàng đợi đang ngồi chơi", "Thêm bài đi, kẻo nhạc hết giữa chừng", "Trống trơn, xếp vài bài vào nhé", "Hàng đợi khum có ai"], ["Queue is empty", "Nobody's in line", "Empty as a market at closing time", "The queue is taking a break", "Add songs before the music runs out", "All empty, line up a few songs", "Not a soul in the queue"])
                    description: I18n.tr("Chọn bài hát để bắt đầu danh sách phát", "Play a track to start the queue")
                }
            }
        }

        // =====================================================================
        // VIEW 3: YOUTUBE COMMENTS
        // =====================================================================
        MochyCommentsView {
            id: commentsView
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: root.activeTab === "comments" ? 1.0 : 0.0
            scale: root.activeTab === "comments" ? 1.0 : 0.94
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            videoId: root.currentTrack && root.currentTrack.videoId ? root.currentTrack.videoId : ""
            accentColor: root.accentColor
            isLoggedIn: root.isLoggedIn
            active: root.activeTab === "comments" && root.isPanelRenderable
            bottomInset: actionDock.height + actionDock.anchors.bottomMargin + root.dockInset
            sideInset: root.dockInset
            cornerRadius: root.panelRadius - root.dockInset
            onCloseRequested: root.closeRequested()
        }

        // Action row lives at panelContainer level so it stays visible on both tabs;
        // bottomDock inside lyricsView only reserves its space for the lyric canvas.
        Item {
            id: actionDock
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: root.dockInset
            anchors.rightMargin: root.dockInset
            anchors.bottomMargin: root.dockInset
            height: actionRow.implicitHeight
            z: 30

            NowPlayingActionRow {
                id: actionRow
                anchors.fill: parent
                activeTab: root.activeTab
                accentColor: root.accentColor
                radius: root.panelRadius - root.dockInset
                onLyricsClicked: root.tabRequested("lyrics")
                onCommentsClicked: root.tabRequested(root.activeTab === "comments" ? "lyrics" : "comments")
                onQueueClicked: root.tabRequested(root.activeTab === "queue" ? "lyrics" : "queue")
            }
        }
    }

    // -------------------------------------------------------------------------
    // OPTION 1: FLUSH SPLIT-RAIL SHARP HAIRLINE SEAM
    // -------------------------------------------------------------------------
    Rectangle {
        id: splitHairlineDivider
        visible: root.isPanelRenderable && root.panelStyle === 1
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        z: 100
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Qt.rgba(1.0, 1.0, 1.0, 0.28) }
            GradientStop { position: 0.35; color: Qt.rgba(1.0, 1.0, 1.0, 0.16) }
            GradientStop { position: 1.0; color: Qt.rgba(1.0, 1.0, 1.0, 0.05) }
        }
    }

    // -------------------------------------------------------------------------
    // OPTION 2: BENTO GLASS ISLAND LUMINOUS PERIMETER BORDER
    // -------------------------------------------------------------------------
    // Single shared rim for BOTH tabs (lyrics + queue). Lives OUTSIDE the masked panelContainer layer so its
    // own antialiased edge covers the mask edge (inside the mask the two AA edges clashed into black jaggies).
    // A quiet 1px hairline (white 8%), like every other card in the window; the accent sheen rim
    // made the island read as a sticker pasted on top
    Rectangle {
        id: panelRim
        visible: root.isPanelRenderable
        anchors.fill: parent
        z: 100
        color: "transparent"
        antialiasing: true
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)
        topLeftRadius: root.panelStyle === 1 ? 0 : root.panelRadius
        bottomLeftRadius: root.panelStyle === 1 ? 0 : root.panelRadius
        topRightRadius: root.panelRadius
        bottomRightRadius: root.panelRadius
    }
}
