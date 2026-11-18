import QtQuick
import QtQuick.Effects
import "."

// Preset 5: the Mochy side panel's expressive lyrics, sized for the desktop.
// Same timetable and motion as MochySidePanel.qml (Mochy ExpressiveText.kt):
// - every line gets a fixed schedule when the lyrics load (comes in, ends, overlaps, leaves)
// - lines that don't overlap are replaced in place: the old one flies off as the new one rises
// - overlapping lines stack, then the lower one glides up as the line above flies off
// - words come in staggered (fade, rise, un-blur, zoom), one short word is shouted at 1.55x,
//   letters light and lift as they are sung, with an accent glow trailing the sweep
// All motion is a pure function of a smooth per-frame clock, so nothing pops.
Item {
    id: root

    property var activeLyrics: []
    property real currentTime: 0.0
    property bool isPlaying: false

    // Adaptive palette colours
    property color colHighlight: "#deb06c"
    property color colActiveText: "#f8fafc"
    property color colShadowDir: "#a6020305"
    property color colShadowAmb: "#66000000"
    property bool isLightArea: false

    // The Mochy panel sets lines at 18-27px in a ~330px column; the desktop box is ~2.5x wider
    property real fontScale: 1.65

    implicitWidth: 880
    implicitHeight: 250

    readonly property bool renderable: root.visible && root.width > 0

    // Timing constants (seconds), mirrored from Mochy
    readonly property real kEnterLead: 0.42
    readonly property real kEnterDur: 0.56
    readonly property real kEnterStagger: 0.065
    readonly property real kExitDur: 0.46
    readonly property real kExitStagger: 0.04
    readonly property real kGapExitDelay: 0.45
    readonly property real kMinInterludeGap: 4.0

    property var lyricSchedule: ({ count: 0, starts: [], ends: [], enter: [], exit: [], gone: [], overlaps: [], words: [], scales: [], fonts: [] })

    // Smooth clock: extrapolates between position samples every frame
    property real animClock: 0.0
    property real clockSample: 0.0
    property double clockStamp: 0
    readonly property real effectiveLyricTime: root.animClock + 0.06

    ListModel { id: visibleLinesModel }

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

    // Mochy dynamic downscaling: long lines step down so they wrap cleanly
    function computeBaseFontSize(words) {
        var base = 27;
        if (words && words.length > 0) {
            var totalChars = 0;
            for (var i = 0; i < words.length; ++i) totalChars += (words[i].text || "").length;
            var count = words.length;
            if (count >= 12 || totalChars >= 42) base = 18;
            else if (count >= 9 || totalChars >= 30) base = 21;
            else if (count >= 6 || totalChars >= 20) base = 24;
        }
        return Math.round(base * root.fontScale);
    }

    function toSec(val) {
        if (val === undefined || val === null) return 0.0;
        var n = Number(val);
        if (isNaN(n)) return 0.0;
        return n > 10000 ? n / 1000.0 : n;
    }

    function lineStartOf(entry) {
        return entry ? toSec(entry.time !== undefined ? entry.time : (entry.startTime || 0)) : 0.0;
    }

    // Word timings: the line's own when it has them, otherwise the time until the
    // next line shared out by word length, holding a little back for a breath.
    function parseWords(entry, idx) {
        if (!entry || entry.isInterlude) return [];
        var rawText = entry.text ? String(entry.text).trim() : "";
        var lineStart = lineStartOf(entry);
        var wList = [];
        if (entry.words && entry.words.length > 0) {
            for (var w = 0; w < entry.words.length; ++w) {
                var wd = entry.words[w];
                var wt = (wd && wd.text) ? String(wd.text).trim() : "";
                if (!wt) continue;
                var s = (wd.start !== undefined) ? toSec(wd.start) : (wd.startTime !== undefined ? toSec(wd.startTime) : lineStart);
                var e = (wd.end !== undefined) ? toSec(wd.end) : (wd.endTime !== undefined ? toSec(wd.endTime) : (s + 0.25));
                wList.push({ text: wt, start: s, end: e, duration: Math.max(0.05, e - s), isHeld: !!(wd.isHeld || (e - s >= 0.85)) });
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

    // Mochy wordScales: the shortest word of 3+ letters is shouted at 1.55x, long words step down
    function computeWordScales(words) {
        if (!words || words.length === 0) return [];
        var minLen = 999, shoutIdx = -1;
        for (var i = 0; i < words.length; ++i) {
            var len = String(words[i].text || "").length;
            if (len >= 3 && len < minLen) { minLen = len; shoutIdx = i; }
        }
        var scales = [];
        for (var j = 0; j < words.length; ++j) {
            var l = String(words[j].text || "").length;
            if (j === shoutIdx && words.length > 1) scales.push(1.55);
            else if (l >= 11) scales.push(0.74);
            else if (l >= 9) scales.push(0.86);
            else scales.push(1.0);
        }
        return scales;
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
            } else {
                // The last line leaves a little after it is sung, so the demo loop starts clean
                ex = sch.ends[c] + 1.2;
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
        for (var j = shown; j >= 0 && want.length < 3; --j) {
            if (t < sch.gone[j] && sch.words[j].length > 0) want.unshift(j);
            else if (!sch.overlaps[j]) break;
        }
        // Diff into the model so lines already on screen keep their delegates
        for (var r = visibleLinesModel.count - 1; r >= 0; --r) {
            if (want.indexOf(visibleLinesModel.get(r).lineIdx) < 0) visibleLinesModel.remove(r);
        }
        for (var w = 0; w < want.length; ++w) {
            var pos = 0, present = false;
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
        // Extrapolate from the last position sample, for at most half a second (a pause stops the samples)
        if (root.isPlaying && root.clockStamp > 0) {
            target = root.clockSample + Math.min(0.5, Math.max(0.0, (Date.now() - root.clockStamp) / 1000.0));
        }
        // Monotonic while playing; small corrections are absorbed, only a real seek moves it back
        if (target > root.animClock || root.animClock - target > 0.3) root.animClock = target;
        syncVisibleLines(root.effectiveLyricTime);
    }

    FrameAnimation {
        running: root.renderable && root.lyricSchedule.count > 0 && root.isPlaying
        onTriggered: root.advanceClock()
    }

    onCurrentTimeChanged: {
        var jumped = Math.abs(root.currentTime - root.animClock) > 1.0;
        root.clockSample = root.currentTime;
        root.clockStamp = Date.now();
        if (!root.renderable) return;
        if (jumped) {
            // Seek (or the demo looping): start fresh; lines that land now animate in from their birth
            root.animClock = root.currentTime;
            visibleLinesModel.clear();
        }
        advanceClock();
    }
    onActiveLyricsChanged: rebuildSchedule()
    onRenderableChanged: {
        if (!renderable) return;
        root.animClock = root.currentTime;
        visibleLinesModel.clear();
        advanceClock();
    }
    Component.onCompleted: {
        root.animClock = root.currentTime;
        rebuildSchedule();
    }

    // One soft shadow under everything so the words read on any wallpaper; no outline, no halo
    Item {
        id: stage
        anchors.fill: parent
        layer.enabled: root.renderable
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: root.colShadowDir
            shadowBlur: 0.6
            shadowVerticalOffset: 2
            shadowHorizontalOffset: 0
            blurMax: 24
            autoPaddingEnabled: true
        }

        // Instrumental break: three breathing dots
        Row {
            id: interludeDots
            readonly property bool shouldShow: root.lyricSchedule.count > 0 && visibleLinesModel.count === 0
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 4
            spacing: 14
            opacity: shouldShow ? 1.0 : 0.0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

            Repeater {
                model: 3
                Rectangle {
                    id: dotItem
                    required property int index
                    width: 14
                    height: 14
                    radius: 7
                    color: root.colActiveText

                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: interludeDots.visible && root.renderable
                        PauseAnimation { duration: dotItem.index * 180 }
                        NumberAnimation { from: 0.20; to: 0.95; duration: 420; easing.type: Easing.InOutQuad }
                        NumberAnimation { from: 0.95; to: 0.20; duration: 420; easing.type: Easing.InOutQuad }
                        PauseAnimation { duration: (2 - dotItem.index) * 180 }
                    }
                }
            }
        }

        Item {
            id: linesStack
            anchors.fill: parent
            anchors.topMargin: 8

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
                    readonly property real baseFont: validLine ? sch.fonts[lineIdx] : 40
                    readonly property real exitAt: validLine ? sch.exit[lineIdx] : -1
                    readonly property bool overlapsNext: validLine && sch.overlaps[lineIdx]

                    // A line that lands late (a seek, the widget appearing) still comes in
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

                    // Whole-line blur for the entrance and exit
                    readonly property real lineBlurPx: {
                        var mid = Math.max(0, Math.floor(lineWords.length / 2));
                        return (1.0 - enterOf(mid)) * 10.0 + exitOf(mid) * 12.0;
                    }

                    width: linesStack.width
                    height: lineFlow.height
                    y: pushY
                    z: 10 - index

                    // Kept on for the line's whole life: toggling a layer mid-flight rebuilds it and hitches a frame
                    layer.enabled: root.renderable
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
                        for (var i = 0; i < ws.length; i++) {
                            if (t < ws[i].start) return i - 1;
                            if (t < ws[i].end) return i;
                        }
                        return ws.length;
                    }

                    Flow {
                        id: lineFlow
                        width: parent.width
                        spacing: Math.round(lineItem.baseFont * 0.3)

                        FontMetrics {
                            id: baseFontMetrics
                            font.family: Theme.fontFamily
                            font.pixelSize: lineItem.baseFont
                            font.weight: Font.DemiBold
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
                                    if (isShoutWord && isSinging && shoutProgress < 0.99 && !shoutAnim.running) shoutAnim.restart();
                                }
                                onIsSingingChanged: checkAndTriggerShout()
                                onIsShoutWordChanged: checkAndTriggerShout()
                                onIsPastChanged: {
                                    if (isPast && isShoutWord && !shoutAnim.running) shoutProgress = 1.0;
                                }
                                Component.onCompleted: {
                                    if (!isShoutWord) return;
                                    if (isPast) shoutProgress = 1.0;
                                    else if (isSinging) checkAndTriggerShout();
                                }

                                readonly property real wStart: (modelData && modelData.start !== undefined) ? Number(modelData.start) : 0.0
                                readonly property real wEnd: (modelData && modelData.end !== undefined) ? Number(modelData.end) : (wStart + 0.1)
                                readonly property real wDur: Math.max(0.05, (modelData && modelData.duration !== undefined) ? Number(modelData.duration) : (wEnd - wStart))
                                readonly property bool isHeld: (modelData && modelData.isHeld !== undefined) ? !!modelData.isHeld : (wDur >= 0.85)

                                // Strict monotonic reading head: never grows before the singer gets there
                                readonly property bool isPast: (lineItem.activeWordIndex >= 0) && (index < lineItem.activeWordIndex || (index === lineItem.activeWordIndex && lineItem.t >= wEnd))
                                readonly property bool isSinging: (lineItem.activeWordIndex >= 0) && (index === lineItem.activeWordIndex) && (lineItem.t >= wStart) && (lineItem.t < wEnd)
                                readonly property real smoothProg: isPast ? 1.0 : (isSinging ? Math.max(0.0, Math.min(1.0, (lineItem.t - wStart) / wDur)) : 0.0)
                                // Bloom head trails the sweep by 120ms (comet glow)
                                readonly property real bloomProg: isSinging ? Math.max(0.0, Math.min(1.0, (lineItem.t - 0.12 - wStart) / wDur)) : 0.0
                                readonly property real bloomLagDelta: isSinging ? (smoothProg - bloomProg) : 0.0

                                function cubicBezier(p1, p2, x) {
                                    var u = 1 - x;
                                    return 3 * u * u * x * p1 + 3 * u * x * x * p2 + x * x * x;
                                }
                                function empEasing(x) {
                                    if (x < 0.5) return cubicBezier(0.3, 1.0, x * 2.0);
                                    return 1.0 - cubicBezier(0.5, 1.0, (x - 0.5) * 2.0);
                                }

                                readonly property real yCurve: isSinging ? (isHeld ? empEasing(smoothProg) : Math.sin(Math.PI * smoothProg)) : 0.0
                                readonly property real waveScale: 1.0 + (isHeld ? 0.045 : 0.010) * yCurve
                                readonly property real effectiveScale: isShoutWord ? (1.0 + (peakScale - 1.0) * shoutProgress) : peakScale

                                width: Math.round(charRow.implicitWidth * effectiveScale)
                                height: lineFlow.maxRowHeight

                                Item {
                                    x: Math.round((parent.width - charRow.implicitWidth) / 2)
                                    y: Math.round(lineFlow.baselineY - baseFontMetrics.ascent)
                                    width: charRow.implicitWidth
                                    height: charRow.implicitHeight

                                    transform: Scale {
                                        xScale: wordCell.effectiveScale
                                        yScale: wordCell.effectiveScale
                                        origin.x: charRow.implicitWidth / 2
                                        origin.y: baseFontMetrics.ascent
                                    }

                                    // Accent glow trailing the sweep, only on the word being sung
                                    Loader {
                                        anchors.fill: charRow
                                        active: root.renderable && wordCell.isSinging
                                        visible: active
                                        sourceComponent: Component {
                                            MultiEffect {
                                                source: charRow
                                                anchors.fill: parent
                                                shadowEnabled: true
                                                shadowColor: root.colHighlight
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
                                        z: 1

                                        Repeater {
                                            model: (wordCell.wordText || "").split("")

                                            delegate: Item {
                                                id: charItem
                                                required property var modelData
                                                required property int index
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
                                                    Translate { y: -charItem.hermiteLift * 2.5 * root.fontScale },
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
                                                    text: charItem.modelData
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: lineItem.baseFont
                                                    font.weight: wordCell.effectiveScale > 1.2 ? Font.Bold : Font.DemiBold
                                                    // Unsung letters wait dim; sung ones fill to the full text colour
                                                    color: Qt.rgba(root.colActiveText.r, root.colActiveText.g, root.colActiveText.b,
                                                                   0.42 + 0.58 * charItem.charProgress)
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
