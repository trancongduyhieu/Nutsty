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
    property string resolvedSquareImage: ""
    property Item backgroundSourceItem: null
    property int panelStyle: 1 // 1: Flush Split-Rail, 2: Bento Glass Island

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

    // -------------------------------------------------------------------------
    // LYRICS SYNCHRONIZATION & WORD-LEVEL STATE MACHINE
    // -------------------------------------------------------------------------
    property int currentLyricIndex: -1
    property var currentLineWords: []
    property var currentWordScales: []
    property real activeBaseFontSize: 26
    property bool isInterlude: false
    property bool hasRealWordTiming: false
    property int lineChangeCounter: 0

    // Smooth Dual-Slot Exit Animation State
    property var exitingLineWords: []
    property var exitingWordScales: []
    property real exitingBaseFontSize: 24
    property real exitProgress: 1.0
    property real exitingLineHeight: 60.0

    // Mochy Authentic Color & Typography Tokens (StyleKit.kt & ExpressiveText.kt)
    readonly property color mochyInk: "#F1ECEC"                               // 0xFFF1ECEC (Warm Alabaster Chalk)
    readonly property color mochyInkSoft: Qt.rgba(0.945, 0.925, 0.925, 0.62) // 0xFFF1ECEC @ 62% alpha (Soft Silver-Ash)
    readonly property color mochyInkDim: Qt.rgba(0.945, 0.925, 0.925, 0.40)  // 0xFFF1ECEC @ 40% alpha (Unsung word)
    readonly property string mochyFont: "Inter, Inter Display, SF Pro Display, system-ui, sans-serif"

    // Line Shift & Shout Word Growth Animation State
    property real lineShiftProgress: 1.0
    property bool shiftTriggered: true

    // Latency compensation for audio buffer so words illuminate right on beat (from AppleMusicWordFlow)
    readonly property real effectiveLyricTime: root.currentTime + 0.06

    // Sequential monotonic reading head: finds the single active singing word index (from AppleMusicWordFlow)
    readonly property int activeWordIndex: {
        var ws = root.currentLineWords;
        if (!ws || ws.length === 0) return -1;
        var t = root.effectiveLyricTime;
        for (var i = 0; i < ws.length; i++) {
            var w = ws[i];
            var wStart = (w.start !== undefined) ? Number(w.start) : 0.0;
            var wEnd = (w.end !== undefined) ? Number(w.end) : (wStart + 0.1);
            if (t < wStart) {
                return i - 1;
            }
            if (t >= wStart && t < wEnd) {
                return i;
            }
        }
        return ws.length;
    }

    // Trigger delayed shift-up after 2-3 words have been sung at the bottom slot:
    // "câu 2 phải hát được tầm 2 3 từ mới dịch chuyển lên trên"
    onActiveWordIndexChanged: {
        if (!shiftTriggered && exitingLineWords && exitingLineWords.length > 0) {
            var threshold = (currentLineWords && currentLineWords.length <= 2) ? 1 : 2;
            if (activeWordIndex >= threshold) {
                startLineShift();
            }
        }
    }

    function startLineShift() {
        if (shiftTriggered) return;
        shiftTriggered = true;
        delayedShiftTimer.stop();
        if (exitingLineWords && exitingLineWords.length > 0) {
            lineShiftAnim.restart();
        } else {
            lineShiftProgress = 1.0;
            exitProgress = 1.0;
        }
    }

    // Safety fallback timer: ensures line never stays stuck at the bottom during long pauses
    Timer {
        id: delayedShiftTimer
        interval: 1600
        repeat: false
        running: false
        onTriggered: root.startLineShift()
    }

    // Upcoming Line State (Waits below active line, words at 1.0x rest scale)
    property int upcomingLyricIndex: -1
    property var upcomingLineWords: []
    property var upcomingWordScales: []
    property real upcomingBaseFontSize: 21

    // Exit Tilt & Horizontal Drift (Randomized per sequential transition: straight / tilt left / tilt right)
    property real exitTiltAngle: 0.0
    property real exitDriftX: 0.0

    // Mochy Dual-Slot Line Shift & Exit Animation (ExpressiveText.kt lines 889-898)
    // 1. Line 1 floats up over album cover (-170px) with 3-phase velocity curve (liftoff -> buoyant rise -> 500ms silky glide & drift) over 980ms.
    // 2. CONCURRENTLY, Line 2 glides up from bottom position to y=0 (lineShiftProgress: 0 -> 1) over 720ms.
    ParallelAnimation {
        id: lineShiftAnim
        running: false

        // Act 1: Câu 1 tan biến làm mờ bay lên ảnh bìa (3-Phase Velocity Curve: Smooth Liftoff -> Rise -> Long Deceleration Glide)
        SequentialAnimation {
            NumberAnimation {
                target: root
                property: "exitProgress"
                from: 0.0
                to: 1.0
                duration: 980
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.18, 0.10, 0.22, 1.0]
            }
            ScriptAction {
                script: {
                    root.exitingLineWords = [];
                    root.exitingWordScales = [];
                }
            }
        }

        // Act 2: Câu 2 trượt từ dưới lên trên mượt mà với quán tính Mochy trong khi đang quét chữ
        NumberAnimation {
            target: root
            property: "lineShiftProgress"
            from: 0.0
            to: 1.0
            duration: 720
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.08, 0.72, 0.15, 1.0]
        }
    }

    // Resolved cover image URL
    readonly property string coverImageUrl: {
        if (root.resolvedSquareImage !== "") {
            var r = root.resolvedSquareImage;
            return (r.startsWith("/") && !r.startsWith("file://")) ? ("file://" + r) : r;
        }
        if (!root.currentTrack) return "";
        var s = root.currentTrack.image || root.currentTrack.artUrl || root.currentTrack.cover || root.currentTrack.thumbnail || "";
        if (!s && root.currentTrack.videoId) {
            s = "https://i.ytimg.com/vi/" + root.currentTrack.videoId + "/hqdefault.jpg";
        }
        if (s.indexOf("i.ytimg.com") !== -1) s = s.split("?")[0];
        return (s.startsWith("/") && !s.startsWith("file://")) ? ("file://" + s) : s;
    }

    // Mochy Dynamic Downscaling Algorithm (ExpressiveText.kt lines 606-620):
    // Measures total characters & words in the line. If line is long (> 10 words or > 40 chars),
    // proportionally steps down base size so it wraps cleanly without overflowing.
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

    function parseWords(entry, idx) {
        if (!entry) return [];
        var rawText = (entry && entry.text) ? String(entry.text).trim() : "";
        var lineStart = toSec(entry.time || entry.startTime || 0);
        var wList = [];
        if (entry.words && entry.words.length > 0) {
            for (var w = 0; w < entry.words.length; ++w) {
                var wd = entry.words[w];
                var wt = (wd && wd.text) ? String(wd.text).trim() : "";
                if (wt) {
                    var s = (wd.start !== undefined) ? toSec(wd.start) : (wd.startTime !== undefined ? toSec(wd.startTime) : lineStart);
                    var e = (wd.end !== undefined) ? toSec(wd.end) : (wd.endTime !== undefined ? toSec(wd.endTime) : (s + 0.25));
                    wList.push({
                        text: wt,
                        start: s,
                        end: e,
                        duration: Math.max(0.05, e - s),
                        isHeld: !!(wd.isHeld || (e - s >= 0.85))
                    });
                }
            }
        } else if (rawText) {
            var parts = rawText.split(/\s+/);
            var nextTime = (idx + 1 < activeLyrics.length) ? toSec(activeLyrics[idx + 1].time || activeLyrics[idx + 1].startTime || (lineStart + 4.0)) : (lineStart + 4.0);
            var lineSpan = Math.max(1.0, (nextTime - lineStart) * 0.85);
            var step = lineSpan / Math.max(1, parts.length);
            for (var p = 0; p < parts.length; ++p) {
                if (parts[p]) {
                    wList.push({
                        text: parts[p],
                        start: lineStart + p * step,
                        end: lineStart + (p + 1) * step,
                        duration: step,
                        isHeld: false
                    });
                }
            }
        }
        return wList;
    }

    function updateLyricState() {
        if (!root.isPanelRenderable) return;
        if (!activeLyrics || activeLyrics.length === 0) {
            currentLyricIndex = -1;
            upcomingLyricIndex = -1;
            currentLineWords = [];
            upcomingLineWords = [];
            currentWordScales = [];
            upcomingWordScales = [];
            isInterlude = false;
            return;
        }

        var pos = root.currentTime;
        var idx = -1;
        for (var i = 0; i < activeLyrics.length; ++i) {
            var l = activeLyrics[i];
            if (l && l.time !== undefined && Number(l.time) <= pos) {
                idx = i;
            } else if (l && l.time !== undefined && Number(l.time) > pos) {
                break;
            }
        }

        // Interlude detection: before first lyric, or if gap between lines is an actual musical break
        if (idx === -1 && activeLyrics.length > 0) {
            var firstTime = toSec(activeLyrics[0].time || activeLyrics[0].startTime || 0);
            isInterlude = (firstTime > 2.5 && pos < (firstTime - 0.3));
        } else if (idx >= 0 && idx < activeLyrics.length - 1) {
            var entry = activeLyrics[idx];
            var curStart = toSec(entry.time || entry.startTime || 0);
            var nextStart = toSec(activeLyrics[idx + 1].time || activeLyrics[idx + 1].startTime || 0);
            var hasWords = !!(entry && entry.words && entry.words.length > 0);

            if (hasWords) {
                // Word-by-word timing: we know EXACTLY when the singer finished singing this line
                var lastW = entry.words[entry.words.length - 1];
                var curEnd = (lastW && (lastW.end !== undefined || lastW.endTime !== undefined)) ? toSec(lastW.end || lastW.endTime) : curStart;
                var gap = nextStart - curEnd;
                // Only show interlude if the gap after the singer finished is at least 3.5s,
                // and give 0.8s grace period after line finishes before collapsing to dots,
                // and collapse dots 0.35s before next line starts so line 2 can lead in!
                isInterlude = (gap >= 3.5 && pos > (curEnd + 0.8) && pos < (nextStart - 0.35));
            } else {
                // Line-by-line timing (NO word-by-word, e.g. Spotify / LRCLIB lines):
                // In standard line-by-line LRC, the line MUST stay visible and active for the natural duration of the phrase!
                // Only if the gap between lines is a massive instrumental solo (gap >= 8.5s),
                // we show interlude dots after displaying the line for at least 5.0s, and until 0.5s before next line.
                var lineGap = nextStart - curStart;
                isInterlude = (lineGap >= 8.5 && pos > (curStart + 5.0) && pos < (nextStart - 0.5));
            }
        } else {
            isInterlude = false;
        }

        if (idx !== currentLyricIndex) {
            var isSequential = (idx === currentLyricIndex + 1 && currentLyricIndex >= 0);

            if (isSequential && currentLineWords && currentLineWords.length > 0) {
                // Snapshot previous line for graceful blur-dissolve upward exit animation
                exitingLineWords = currentLineWords;
                exitingWordScales = currentWordScales;
                exitingBaseFontSize = activeBaseFontSize;
                exitingLineHeight = (typeof activeLineFlow !== "undefined" && activeLineFlow.height > 0) ? activeLineFlow.height : 60.0;

                // Randomize tilt and drift for exiting line: 1/3 straight, 1/3 tilt left, 1/3 tilt right
                var r = Math.random();
                if (r < 0.34) {
                    exitTiltAngle = 0.0;
                    exitDriftX = 0.0;
                } else if (r < 0.67) {
                    exitTiltAngle = -(2.0 + Math.random() * 2.5);
                    exitDriftX = -(8.0 + Math.random() * 12.0);
                } else {
                    exitTiltAngle = (2.0 + Math.random() * 2.5);
                    exitDriftX = (8.0 + Math.random() * 12.0);
                }

                lineShiftAnim.stop();
                delayedShiftTimer.stop();

                var entry = activeLyrics[idx];
                root.hasRealWordTiming = !!(entry && entry.words && entry.words.length > 0);
                var wList = parseWords(entry, idx);
                var wScales = computeWordScales(wList);
                var baseSize = computeBaseFontSize(wList);

                // CRITICAL SSOT ORDER: Update scales & base size BEFORE currentLineWords,
                // so delegates immediately evaluate the correct peakScale and isShoutWord upon binding!
                currentWordScales = wScales;
                activeBaseFontSize = baseSize;
                currentLineWords = wList;

                currentLyricIndex = idx;
                upcomingLyricIndex = (idx >= 0 && idx + 1 < activeLyrics.length) ? (idx + 1) : -1;

                // Populate upcoming line (starts at 1.0x rest scale, waiting below active line)
                if (upcomingLyricIndex >= 0 && upcomingLyricIndex < activeLyrics.length) {
                    var nextEntry = activeLyrics[upcomingLyricIndex];
                    var nextWords = parseWords(nextEntry, upcomingLyricIndex);
                    upcomingLineWords = nextWords;
                    upcomingWordScales = computeWordScales(nextWords);
                    upcomingBaseFontSize = computeBaseFontSize(nextWords);
                } else {
                    upcomingLineWords = [];
                    upcomingWordScales = [];
                }

                // Sits at bottom while singer sings first 2-3 words:
                // exitProgress = 0.0 (Line 1 stays visible at top)
                // lineShiftProgress = 0.0 (Line 2 positioned at bottom)
                // shiftTriggered = false (waiting for activeWordIndex >= 2 or timer)
                exitProgress = 0.0;
                lineShiftProgress = 0.0;
                shiftTriggered = false;
                delayedShiftTimer.interval = Math.min(2400, Math.max(1200, wList.length >= 3 ? 1700 : 1000));
                delayedShiftTimer.restart();

                // Increment counter ONLY AFTER all line data is completely synchronized!
                lineChangeCounter++;
            } else {
                // Non-sequential / jump / seek: Snap directly to active line without stale exit anim
                lineShiftAnim.stop();
                delayedShiftTimer.stop();

                exitingLineWords = [];
                exitingWordScales = [];
                exitProgress = 1.0;
                lineShiftProgress = 1.0;
                shiftTriggered = true;
                exitTiltAngle = 0.0;
                exitDriftX = 0.0;

                if (idx >= 0 && idx < activeLyrics.length) {
                    var entryNonSeq = activeLyrics[idx];
                    root.hasRealWordTiming = !!(entryNonSeq && entryNonSeq.words && entryNonSeq.words.length > 0);
                    var wListNonSeq = parseWords(entryNonSeq, idx);
                    var wScalesNonSeq = computeWordScales(wListNonSeq);
                    var baseSizeNonSeq = computeBaseFontSize(wListNonSeq);

                    currentWordScales = wScalesNonSeq;
                    activeBaseFontSize = baseSizeNonSeq;
                    currentLineWords = wListNonSeq;
                } else {
                    root.hasRealWordTiming = false;
                    currentWordScales = [];
                    currentLineWords = [];
                }

                currentLyricIndex = idx;
                upcomingLyricIndex = (idx >= 0 && idx + 1 < activeLyrics.length) ? (idx + 1) : -1;

                if (upcomingLyricIndex >= 0 && upcomingLyricIndex < activeLyrics.length) {
                    var nextEntryNonSeq = activeLyrics[upcomingLyricIndex];
                    var nextWordsNonSeq = parseWords(nextEntryNonSeq, upcomingLyricIndex);
                    upcomingLineWords = nextWordsNonSeq;
                    upcomingWordScales = computeWordScales(nextWordsNonSeq);
                    upcomingBaseFontSize = computeBaseFontSize(nextWordsNonSeq);
                } else {
                    upcomingLineWords = [];
                    upcomingWordScales = [];
                }

                lineChangeCounter++;
            }
        }
    }

    onCurrentTimeChanged: {
        if (root.isPanelRenderable) updateLyricState();
    }
    onActiveLyricsChanged: {
        if (root.isPanelRenderable) updateLyricState();
    }
    onIsPanelRenderableChanged: {
        if (isPanelRenderable) {
            updateLyricState();
        } else {
            lineShiftAnim.stop();
            delayedShiftTimer.stop();
        }
    }

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

    // Concentric Mask (Option 1: Flat left R=0, concentric right R=20; Option 2: All corners R=20)
    Item {
        id: panelMask
        anchors.fill: parent
        visible: false
        layer.enabled: root.isPanelRenderable
        layer.samples: 8
        layer.smooth: true
        Rectangle {
            anchors.fill: parent
            topLeftRadius: root.panelStyle === 1 ? 0 : 20
            bottomLeftRadius: root.panelStyle === 1 ? 0 : 20
            topRightRadius: 20
            bottomRightRadius: 20
            color: "#ffffff"
        }
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
        anchors.fill: parent
        anchors.margins: -4
        radius: 24
        color: Qt.rgba(0, 0, 0, 0.48)
        z: -1
        layer.enabled: root.isPanelRenderable && root.panelStyle === 2
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 0.7
            blurMax: 20
        }
    }

    // -------------------------------------------------------------------------
    // 1. MASTER PANEL CONTAINER WITH CONCENTRIC CLIP
    // -------------------------------------------------------------------------
    Item {
        id: panelContainer
        anchors.fill: parent
        layer.enabled: root.isPanelRenderable
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: panelMask
            autoPaddingEnabled: false
        }

        // =====================================================================
        // LAYER A: COVER GRADIENT BACKDROP (HEAVY PROGRESSIVE BLUR)
        // Deep liquid blurred artwork behind the entire panel.
        // "ở trên rõ ở dưới làm mờ cho expressive lyric"
        // =====================================================================
        Item {
            id: backdropWrapper
            anchors.fill: parent

            // Base deep dark tone
            Rectangle {
                anchors.fill: parent
                color: root.panelStyle === 1 ? "#121216" : "#0d0d12"
            }

            // Blurred album art background
            Image {
                id: backdropImage
                anchors.fill: parent
                source: root.coverImageUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                layer.enabled: root.isPanelRenderable
                visible: false
            }

            MultiEffect {
                anchors.fill: parent
                source: backdropImage
                visible: root.isPanelRenderable
                blurEnabled: root.isPanelRenderable
                blur: 1.0
                blurMax: 64
                saturation: 1.35
                brightness: -0.15
                contrast: 0.10
            }

            // Soft dark gradient overlay: lets cover colors breathe while ensuring high contrast
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0.06, 0.06, 0.08, 0.20) }
                    GradientStop { position: 0.40; color: Qt.rgba(0.06, 0.06, 0.08, 0.55) }
                    GradientStop { position: 0.75; color: Qt.rgba(0.06, 0.06, 0.08, 0.82) }
                    GradientStop { position: 1.0; color: Qt.rgba(0.06, 0.06, 0.08, 0.94) }
                }
            }

            // Outer Hairline Border adapted to panelStyle
            Rectangle {
                anchors.fill: parent
                topLeftRadius: root.panelStyle === 1 ? 0 : 20
                bottomLeftRadius: root.panelStyle === 1 ? 0 : 20
                topRightRadius: 20
                bottomRightRadius: 20
                color: "transparent"
                border.color: root.panelStyle === 1 ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.16)
                border.width: root.panelStyle === 1 ? 1 : 1.2
            }
        }

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
                    PathQuad {
                        x: 0
                        y: circleCover.cw * 0.8526
                        controlX: circleCover.cw * 0.50
                        controlY: circleCover.cw * 0.9150
                    }
                    PathLine { x: 0; y: 0 }
                }
            }

            // Drop Shadow underneath the elevated circle arc
            Shape {
                anchors.fill: parent
                layer.enabled: root.isPanelRenderable
                layer.samples: 8
                layer.smooth: true
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Qt.rgba(0, 0, 0, 0.35)
                    strokeWidth: 4
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    startX: circleCover.cw
                    startY: circleCover.cw * 0.4567 + 1.5

                    PathQuad {
                        x: 0
                        y: circleCover.cw * 0.8526 + 1.5
                        controlX: circleCover.cw * 0.50
                        controlY: circleCover.cw * 0.9150 + 1.5
                    }
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

                // 1. Crystal Sharp Album Artwork
                Image {
                    id: topSharpCover
                    anchors.fill: parent
                    source: root.coverImageUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                }

                // 2. Mochy Soft Vignette along the lower rim
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.60; color: "transparent" }
                        GradientStop { position: 0.85; color: Qt.rgba(0, 0, 0, 0.20) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.45) }
                    }
                }
            }

            // Mochy Hairline Edge Stroke along the Arc (Parabolic Curve)
            Shape {
                anchors.fill: parent
                layer.enabled: root.isPanelRenderable
                layer.samples: 8
                layer.smooth: true
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Qt.rgba(1, 1, 1, 0.28)
                    strokeWidth: 1.0
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    startX: circleCover.cw
                    startY: circleCover.cw * 0.4567

                    PathQuad {
                        x: 0
                        y: circleCover.cw * 0.8526
                        controlX: circleCover.cw * 0.50
                        controlY: circleCover.cw * 0.9150
                    }
                }
            }

            // Click artwork to expand full-screen Now Playing
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openDetailsRequested()
            }
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
        // LAYER D: COMPACT METADATA CREDITS (BOTTOM)
        // Authentic Mochy Poster Typography (AlternatePlayerStyles.kt & StyleKit.kt):
        // - Top: Artist Name (Inter SemiBold, 13.5px, letterSpacing -0.2px, color mochyInkSoft)
        // - Bottom: Song Title (Inter Bold, 18.5px, letterSpacing -0.45px, color mochyInk)
        // =====================================================================
        Column {
            id: creditsColumn
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            anchors.bottomMargin: 22
            spacing: 4
            z: 10

            // Artist Name (Mochy CreditLine: r.sp(0.034f, 12f, 15f), FontWeight.SemiBold, color = tones.inkSoft)
            Text {
                width: parent.width
                text: {
                    if (!root.currentTrack) return I18n.tr("Sẵn sàng phát", "Ready to play");
                    var raw = String(root.currentTrack.artist || "").trim();
                    var clean = raw.split(/\s*•\s*/)[0].replace(/\s*\d+([.,]\d+)?[KMBkmb]?\s*(views|plays|lượt xem|lượt nghe).*/i, "").trim();
                    return clean || raw || "Nutsty Desktop";
                }
                font.family: root.mochyFont
                font.pixelSize: 14
                font.weight: Font.DemiBold
                font.letterSpacing: -0.2
                color: root.mochyInkSoft
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            // Song Title (Mochy SmallTitle: smallTitle, FontWeight.Bold, color = tones.ink)
            Text {
                width: parent.width
                text: root.currentTrack ? (root.currentTrack.title || root.currentTrack.name || "Nutsty Track") : "Nutsty Music"
                font.family: root.mochyFont
                font.pixelSize: 19
                font.weight: Font.Bold
                font.letterSpacing: -0.45
                color: root.mochyInk
                elide: Text.ElideRight
                maximumLineCount: 1
            }
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
            anchors.top: parent.top
            anchors.topMargin: Math.round(circleCover.cw * 0.88 + 10)
            anchors.bottom: creditsColumn.top
            anchors.bottomMargin: 14
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
                visible: root.isInterlude || (root.activeLyrics && root.activeLyrics.length > 0 && root.currentLyricIndex < 0)

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
            // STATE 2: EXPRESSIVE LYRICS ENGINE (MOCHY DUAL-SLOT CONVEYOR)
            // - NO static blurred lines above or below!
            // - Slot 1 (Active): Words start at normal 1.0x scale, shout words smoothly expand and push outward!
            // - Slot 2 (Upcoming): Sits waiting below active line at 1.0x rest scale and soft dimmed opacity.
            // - When line finishes: Exiting line dissolves upward (0 -> -22px, opacity 1 -> 0);
            //   Upcoming line glides smoothly upward into active position;
            //   The next line arrives below, repeating this fluid conveyor motion!
            // -----------------------------------------------------------------
            Item {
                id: expressiveLyricsBox
                anchors.fill: parent
                visible: !interludeDotsBox.visible && root.activeLyrics && root.activeLyrics.length > 0 && root.currentLyricIndex >= 0

                Item {
                    id: linesStackContainer
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 16
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8

                    // ---------------------------------------------------------
                    // A. EXITING LINE (Tan biến làm mờ bay lên ảnh bìa: y: 0 -> -170px, blur: 0 -> 26px, random tilt & drift)
                    // ---------------------------------------------------------
                    Item {
                        id: exitingLineContainer
                        width: parent.width
                        height: root.exitingLineHeight
                        visible: root.isPanelRenderable && root.exitingLineWords && root.exitingLineWords.length > 0 && root.exitProgress < 0.99
                        x: root.exitProgress * root.exitDriftX
                        y: -root.exitProgress * 170.0
                        rotation: root.exitProgress * root.exitTiltAngle
                        transformOrigin: Item.Center
                        opacity: Math.max(0.0, 1.0 - Math.pow(root.exitProgress, 2.4))
                        scale: 1.0 + 0.04 * root.exitProgress
                        z: 1

                        layer.enabled: root.isPanelRenderable && visible
                        layer.effect: MultiEffect {
                            blurEnabled: root.isPanelRenderable
                            blur: root.exitProgress * 0.92
                            blurMax: 26
                            autoPaddingEnabled: true
                        }

                        Flow {
                            id: exitingLineFlow
                            width: parent.width
                            spacing: 8

                            FontMetrics {
                                id: exitFontMetrics
                                font.family: Theme.fontFamily
                                font.pixelSize: root.exitingBaseFontSize
                                font.bold: Font.DemiBold
                            }

                            readonly property real maxRowHeight: Math.round(root.exitingBaseFontSize * 1.55 * 1.42)
                            readonly property real baselineY: Math.round(root.exitingBaseFontSize * 1.55 * 1.05)

                            Repeater {
                                model: root.exitingLineWords

                                delegate: Item {
                                    id: exitCell
                                    required property int index
                                    required property var modelData

                                    readonly property string wordText: modelData ? String(modelData.text || "") : ""
                                    readonly property real wordScale: (root.exitingWordScales && index < root.exitingWordScales.length) ? root.exitingWordScales[index] : 1.0

                                    width: Math.round(exitText.paintedWidth * wordScale)
                                    height: exitingLineFlow.maxRowHeight

                                    Item {
                                        id: exitTransformWrap
                                        x: Math.round((parent.width - exitText.paintedWidth) / 2)
                                        y: Math.round(exitingLineFlow.baselineY - exitFontMetrics.ascent)
                                        width: exitText.paintedWidth
                                        height: exitText.paintedHeight
                                        transform: [
                                            Scale {
                                                xScale: exitCell.wordScale
                                                yScale: exitCell.wordScale
                                                origin.x: exitText.paintedWidth / 2
                                                origin.y: exitFontMetrics.ascent
                                            }
                                        ]

                                        Text {
                                            id: exitText
                                            anchors.centerIn: parent
                                            text: exitCell.wordText
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.exitingBaseFontSize
                                            font.bold: exitCell.wordScale > 1.2 ? true : Font.DemiBold
                                            color: "#ffffff"
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---------------------------------------------------------
                    // B. ACTIVE LINE (Xuất hiện ở vị trí bên dưới, quét chữ ngay lập tức, đồng thời trượt lên trên thế chỗ câu 1)
                    // Căn chuẩn Typographic Baseline qua FontMetrics.ascent:
                    // Các từ nhỏ và từ phóng to tuyệt đối nằm trên cùng 1 đường chân chữ phẳng!
                    // ---------------------------------------------------------
                    Item {
                        id: activeLineContainer
                        width: parent.width
                        height: activeLineFlow.height
                        y: (1.0 - root.lineShiftProgress) * (root.exitingLineWords && root.exitingLineWords.length > 0 ? Math.max(55.0, root.exitingLineHeight + 16.0) : 0.0)
                        opacity: 1.0
                        z: 3
                        visible: root.currentLineWords && root.currentLineWords.length > 0

                        Flow {
                            id: activeLineFlow
                            width: parent.width
                            spacing: 8

                            FontMetrics {
                                id: baseFontMetrics
                                font.family: Theme.fontFamily
                                font.pixelSize: root.activeBaseFontSize
                                font.bold: Font.DemiBold
                            }

                            readonly property real maxRowHeight: Math.round(root.activeBaseFontSize * 1.55 * 1.42)
                            readonly property real baselineY: Math.round(root.activeBaseFontSize * 1.55 * 1.05)

                            Repeater {
                                model: root.currentLineWords

                                delegate: Item {
                                    id: wordCell
                                    required property int index
                                    required property var modelData

                                    readonly property string wordText: modelData ? String(modelData.text || "") : ""
                                    readonly property real peakScale: (root.currentWordScales && index < root.currentWordScales.length) ? root.currentWordScales[index] : 1.0
                                    readonly property bool isShoutWord: peakScale > 1.15
                                    property real shoutProgress: 0.0

                                    // Bezier Spline Monotonic Shout Growth:
                                    // Tuyệt đối không bounce, không co rút ngược lại (shrink), tăng trưởng êm dịu C^1
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

                                    onIsSingingChanged: {
                                        checkAndTriggerShout();
                                    }

                                    onIsShoutWordChanged: {
                                        checkAndTriggerShout();
                                    }

                                    onIsPastChanged: {
                                        if (isPast && isShoutWord && !shoutAnim.running) {
                                            shoutProgress = 1.0;
                                        }
                                    }

                                    // Staggered Soft Ripple Wave Pop-in (chỉ áp dụng cho từ thường, không áp vào shout word)
                                    property real rippleScale: 1.0

                                    SequentialAnimation {
                                        id: wordRippleAnim
                                        running: false
                                        PauseAnimation { duration: Math.min(200, wordCell.index * 20) }
                                        NumberAnimation {
                                            target: wordCell
                                            property: "rippleScale"
                                            from: 0.965
                                            to: 1.014
                                            duration: 190
                                            easing.type: Easing.OutQuad
                                        }
                                        NumberAnimation {
                                            target: wordCell
                                            property: "rippleScale"
                                            from: 1.014
                                            to: 1.000
                                            duration: 150
                                            easing.type: Easing.InOutQuad
                                        }
                                    }

                                    Connections {
                                        target: root
                                        function onLineChangeCounterChanged() {
                                            wordCell.rippleScale = 0.965;
                                            wordRippleAnim.restart();
                                            if (wordCell.isShoutWord) {
                                                if (wordCell.isPast) {
                                                    shoutAnim.stop();
                                                    wordCell.shoutProgress = 1.0;
                                                } else if (wordCell.isSinging) {
                                                    wordCell.shoutProgress = 0.0;
                                                    wordCell.checkAndTriggerShout();
                                                } else {
                                                    shoutAnim.stop();
                                                    wordCell.shoutProgress = 0.0;
                                                }
                                            } else {
                                                shoutAnim.stop();
                                                wordCell.shoutProgress = 0.0;
                                            }
                                        }
                                    }

                                    Component.onCompleted: {
                                        wordCell.rippleScale = 0.965;
                                        wordRippleAnim.restart();
                                        if (wordCell.isShoutWord) {
                                            if (wordCell.isPast) {
                                                wordCell.shoutProgress = 1.0;
                                            } else if (wordCell.isSinging) {
                                                wordCell.checkAndTriggerShout();
                                            }
                                        }
                                    }

                                    readonly property real wStart: (modelData && modelData.start !== undefined) ? Number(modelData.start) : 0.0
                                    readonly property real wEnd: (modelData && modelData.end !== undefined) ? Number(modelData.end) : (wStart + 0.1)
                                    readonly property real wDur: Math.max(0.05, (modelData && modelData.duration !== undefined) ? Number(modelData.duration) : (wEnd - wStart))
                                    readonly property bool isHeld: (modelData && modelData.isHeld !== undefined) ? !!modelData.isHeld : (wDur >= 0.85)

                                    // Strict Monotonic Reading Head: Tuyệt đối không phóng to trước khi ca sĩ hát tới!
                                    readonly property bool isPast: (root.activeWordIndex >= 0) && (wordCell.index < root.activeWordIndex || (wordCell.index === root.activeWordIndex && root.effectiveLyricTime >= wEnd))
                                    readonly property bool isSinging: (root.activeWordIndex >= 0) && (wordCell.index === root.activeWordIndex) && (root.effectiveLyricTime >= wStart) && (root.effectiveLyricTime < wEnd)
                                    readonly property real wordProgress: isPast ? 1.0 : (isSinging ? Math.max(0.0, Math.min(1.0, (root.effectiveLyricTime - wStart) / wDur)) : 0.0)

                                    // C1 continuous smooth progress (exact AppleMusicWordFlow.qml)
                                    property real smoothProg: 0.0
                                    Behavior on smoothProg {
                                        SmoothedAnimation { duration: 120; reversingMode: SmoothedAnimation.Immediate }
                                    }
                                    onWordProgressChanged: smoothProg = wordProgress

                                    // Lagged Phosphor Bloom reader head: trails behind smoothProg to create comet glow effect (exact AppleMusicWordFlow.qml)
                                    property real bloomProg: 0.0
                                    Behavior on bloomProg {
                                        SmoothedAnimation { duration: 240; reversingMode: SmoothedAnimation.Immediate }
                                    }
                                    onSmoothProgChanged: bloomProg = smoothProg
                                    readonly property real bloomLagDelta: wordCell.isSinging ? (wordCell.smoothProg - wordCell.bloomProg) : 0.0

                                    // Cubic Bezier & Easing for held note swell (exact AppleMusicWordFlow.qml)
                                    function cubicBezier(p0, p1, p2, p3, t) {
                                        var u = 1 - t;
                                        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t;
                                    }

                                    function empEasing(x) {
                                        if (x < 0.5) return cubicBezier(0.0, 0.3, 0.25, 1.0, x * 2.0);
                                        return 1.0 - cubicBezier(0.0, 0.5, 0.6, 1.0, (x - 0.5) * 2.0);
                                    }

                                    readonly property real yCurve: isSinging ? (isHeld ? empEasing(smoothProg) : Math.sin(Math.PI * smoothProg)) : 0.0
                                    readonly property real waveScale: 1.0 + (isHeld ? 0.045 : 0.010) * yCurve

                                    // Shout word: phóng to mượt mà đơn điệu theo đường cong Bezier Spline [0.12, 0.88, 0.24, 1.0] không giật, không co lại!
                                    // Từ thường: giữ nguyên tỉ lệ fitting và hiệu ứng ripple nhẹ khi câu xuất hiện
                                    readonly property real effectiveScale: isShoutWord
                                        ? (1.0 + (peakScale - 1.0) * shoutProgress)
                                        : (peakScale * wordCell.rippleScale)

                                    width: Math.round(charRow.implicitWidth * effectiveScale)
                                    height: activeLineFlow.maxRowHeight

                                    Item {
                                        id: innerTransformWrap
                                        x: Math.round((parent.width - charRow.implicitWidth) / 2)
                                        y: Math.round(activeLineFlow.baselineY - baseFontMetrics.ascent)
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

                                        // 1. Phosphor Bloom Glow with Lagged Comet Tail (exact AppleMusicWordFlow MultiEffect)
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

                                        // 2. Character Row with Persistent Rolling Wave Lift (exact AppleMusicWordFlow)
                                        Row {
                                            id: charRow
                                            spacing: 0
                                            z: 1

                                            Repeater {
                                                model: (wordCell.wordText || "").split("")

                                                delegate: Item {
                                                    id: charItem
                                                    readonly property string ch: modelData
                                                    readonly property int charIndex: index
                                                    readonly property int charCount: Math.max(1, (wordCell.wordText || "").length)

                                                    readonly property real charFrom: charIndex / charCount
                                                    readonly property real charTo: (charIndex + 1) / charCount
                                                    readonly property real charProgress: wordCell.isPast ? 1.0 :
                                                        (wordCell.isSinging ? Math.max(0.0, Math.min(1.0, (wordCell.smoothProg - charFrom) / Math.max(0.001, charTo - charFrom))) : 0.0)

                                                    // Apple Wave Lift: Hermite curve w * w * (3.0 - 2.0 * w) for smooth -2.5px persistent lift (exact AppleMusicWordFlow.qml)
                                                    property real liftProgress: (charProgress > 0.0 || wordCell.isPast) ? 1.0 : 0.0
                                                    Behavior on liftProgress {
                                                        NumberAnimation {
                                                            duration: 750
                                                            easing.type: Easing.BezierSpline
                                                            easing.bezierCurve: [0.4, 0.0, 0.2, 1.0]
                                                        }
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
                                                        text: ch
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: root.activeBaseFontSize
                                                        font.bold: wordCell.effectiveScale > 1.2 ? true : Font.DemiBold
                                                        color: {
                                                            if (wordCell.isPast || charItem.charProgress >= 1.0) return "#ffffff";
                                                            if (charItem.charProgress <= 0.0) return Qt.rgba(1.0, 1.0, 1.0, 0.38);
                                                            var p = charItem.charProgress;
                                                            var alpha = 0.38 + (1.0 - 0.38) * p;
                                                            return Qt.rgba(1.0, 1.0, 1.0, alpha);
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
            // STATE 3: POSTER EXPRESSIVE TITLE FALLBACK (WHEN NO SYNCED LYRICS)
            // -----------------------------------------------------------------
            Item {
                id: expressiveTitleBox
                anchors.fill: parent
                visible: !interludeDotsBox.visible && !expressiveLyricsBox.visible

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    spacing: 12

                    Text {
                        width: parent.width
                        text: root.currentTrack ? (root.currentTrack.title || root.currentTrack.name || "Nutsty Track") : "Nutsty Music"
                        font.family: Theme.fontFamily
                        font.pixelSize: 26
                        font.bold: true
                        color: "#ffffff"
                        wrapMode: Text.WordWrap
                        lineHeight: 1.15
                    }

                    Row {
                        spacing: 8
                        AppIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            source: "../assets/icons/view-lyrics-symbolic.svg"
                            iconSize: 14
                            color: Qt.rgba(1, 1, 1, 0.35)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Chưa có lời đồng bộ", "No synchronized lyrics")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Qt.rgba(1, 1, 1, 0.45)
                        }
                    }
                }
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
    Rectangle {
        id: bentoPerimeterBorder
        visible: root.isPanelRenderable && root.panelStyle === 2
        anchors.fill: parent
        radius: 20
        color: "transparent"
        border.width: 1.2
        border.color: Qt.rgba(1.0, 1.0, 1.0, 0.18)
        z: 100
    }
}
