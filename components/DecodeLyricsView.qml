import QtQuick
import QtQuick.Effects
import "."
import "decode_motion.js" as Decode

// Desktop lyrics preset 7: a HUD that decodes each line as it is sung (decode_motion.js).
// Monospace caps inside lock-on corner brackets, a line counter and clock above, a progress
// hairline below. The accent is the wallpaper palette's highlight; everything else is text colour.
Item {
    id: root

    property var activeLyrics: []
    property real currentTime: 0.0
    property bool isPlaying: false

    property color colHighlight: "#deb06c"
    property color colActiveText: "#f8fafc"
    property color colShadowDir: "#a6020305"
    property color colShadowAmb: "#66000000"
    property bool isLightArea: false

    readonly property string monoFamily: Qt.platform.os === "windows" ? "Consolas" : "monospace"

    implicitWidth: 880
    implicitHeight: 200

    readonly property bool renderable: root.visible && root.width > 0

    property var motion: ({ lines: [] })

    // Smooth clock: extrapolates between position samples every frame (at most half a second)
    property real animClock: 0.0
    property real clockSample: 0.0
    property double clockStamp: 0
    readonly property real t: root.animClock + 0.04

    ListModel { id: visibleLines }

    function rebuild() {
        root.motion = Decode.build(root.activeLyrics);
        visibleLines.clear();
        syncVisible();
    }

    function syncVisible() {
        var want = Decode.visibleAt(root.motion.lines, root.t);
        for (var r = visibleLines.count - 1; r >= 0; --r) {
            if (want.indexOf(visibleLines.get(r).lineIdx) < 0) visibleLines.remove(r);
        }
        for (var w = 0; w < want.length; ++w) {
            var pos = 0, present = false;
            for (var m = 0; m < visibleLines.count; ++m) {
                var li = visibleLines.get(m).lineIdx;
                if (li === want[w]) { present = true; break; }
                if (li < want[w]) pos = m + 1;
            }
            if (!present) visibleLines.insert(pos, { lineIdx: want[w] });
        }
    }

    function advanceClock() {
        var target = root.currentTime;
        if (root.isPlaying && root.clockStamp > 0) {
            target = root.clockSample + Math.min(0.5, Math.max(0.0, (Date.now() - root.clockStamp) / 1000.0));
        }
        if (target > root.animClock || root.animClock - target > 0.3) root.animClock = target;
        syncVisible();
    }

    function pad2(v) { return (v < 10 ? "0" : "") + v; }
    function stamp(sec) {
        sec = Math.max(0, sec);
        var m = Math.floor(sec / 60), s = sec - m * 60;
        return pad2(m) + ":" + pad2(Math.floor(s)) + "." + Math.floor((s % 1) * 10);
    }
    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
    function mix(a, b, k) { return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, 1); }

    FrameAnimation {
        running: root.renderable && root.isPlaying && root.motion.lines.length > 0
        onTriggered: root.advanceClock()
    }

    onCurrentTimeChanged: {
        root.clockSample = root.currentTime;
        root.clockStamp = Date.now();
        if (Math.abs(root.currentTime - root.animClock) > 1.0) root.animClock = root.currentTime;
        if (root.renderable) advanceClock();
    }
    onActiveLyricsChanged: rebuild()
    onRenderableChanged: if (renderable) { root.animClock = root.currentTime; advanceClock(); }
    Component.onCompleted: { root.animClock = root.currentTime; rebuild(); }

    // One soft shadow under everything so it reads on any wallpaper; no outline, no halo
    Item {
        id: stage
        anchors.fill: parent
        layer.enabled: root.renderable
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: root.colShadowDir
            shadowBlur: 0.55
            shadowVerticalOffset: 2
            blurMax: 20
            autoPaddingEnabled: true
        }

        Repeater {
            model: visibleLines

            delegate: Item {
                id: lineItem
                required property int lineIdx
                readonly property var line: root.motion.lines[lineIdx] || null
                readonly property real t: root.t
                readonly property bool leaving: line !== null && line.exitAt >= 0 && t >= line.exitAt
                readonly property var fr: Decode.frame(line, t)
                readonly property real tear: Decode.lineGlitch(line, t)

                // Size the type so the whole line fits on one row when it can
                readonly property int fontPx: {
                    if (!line) return 34;
                    var cells = line.n + Math.max(0, line.words.length - 1);
                    return Math.max(20, Math.min(40, Math.floor(root.width * 0.86 / (cells * 0.64))));
                }

                TextMetrics { id: cell; font.family: root.monoFamily; font.pixelSize: lineItem.fontPx; font.weight: Font.Bold; text: "M" }
                readonly property real cellW: Math.ceil(cell.advanceWidth)
                readonly property real cellH: Math.ceil(lineItem.fontPx * 1.22)

                width: root.width
                height: root.height
                // The leaving line lifts a little so the next one scans in clear of it
                transform: Translate {
                    y: lineItem.leaving ? -0.9 * lineItem.cellH * Math.min(1, (lineItem.t - lineItem.line.exitAt) / 0.3) : 0
                }

                Item {
                    id: block
                    x: Math.round((root.width - width) / 2 + lineItem.tear)
                    y: Math.round((root.height - height) / 2) + 6
                    width: lineFlow.width
                    height: lineFlow.height

                    Flow {
                        id: lineFlow
                        width: Math.min(root.width * 0.92, lineFlow.implicitW)
                        readonly property real implicitW: {
                            if (!lineItem.line) return 0;
                            // letters, the gaps between words, then a gap and a cell for the end cursor
                            var cells = lineItem.line.n + lineItem.line.words.length + 1;
                            return cells * lineItem.cellW + 1;
                        }
                        spacing: lineItem.cellW

                        Repeater {
                            model: lineItem.line ? lineItem.line.words : []

                            delegate: Row {
                                id: wordRow
                                required property int index
                                required property var modelData

                                Repeater {
                                    model: wordRow.modelData.chars

                                    delegate: Item {
                                        id: letter
                                        required property int index
                                        required property string modelData

                                        readonly property var st: Decode.letterState(lineItem.line, lineItem.t, wordRow.index, letter.index)
                                        readonly property string shown: st.glyph !== "" ? st.glyph : letter.modelData

                                        width: lineItem.cellW
                                        height: lineItem.cellH
                                        opacity: st.alpha
                                        visible: st.alpha > 0.003

                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.topMargin: 2
                                            anchors.bottomMargin: 1
                                            visible: letter.st.cursor
                                            color: root.colHighlight
                                        }

                                        // Chromatic ghosts: accent to the right, text colour to the left
                                        Text {
                                            visible: letter.st.ghost > 0.02 && !letter.st.cursor
                                            x: 5 * letter.st.ghost
                                            y: letter.st.dy
                                            width: parent.width
                                            horizontalAlignment: Text.AlignHCenter
                                            text: letter.shown
                                            font: glyph.font
                                            color: root.withAlpha(root.colHighlight, 0.75 * letter.st.ghost)
                                        }
                                        Text {
                                            visible: letter.st.ghost > 0.02 && !letter.st.cursor
                                            x: -4 * letter.st.ghost
                                            y: letter.st.dy
                                            width: parent.width
                                            horizontalAlignment: Text.AlignHCenter
                                            text: letter.shown
                                            font: glyph.font
                                            color: root.withAlpha(root.colActiveText, 0.35 * letter.st.ghost)
                                        }

                                        Text {
                                            id: glyph
                                            y: letter.st.dy
                                            width: parent.width
                                            horizontalAlignment: Text.AlignHCenter
                                            text: letter.shown
                                            font.family: root.monoFamily
                                            font.pixelSize: lineItem.fontPx
                                            font.weight: Font.Bold
                                            // Noise waits in a dim accent; a lock flashes accent then settles to text colour
                                            color: {
                                                var s = letter.st;
                                                if (s.cursor) return "#0b0b10";
                                                if (s.noise < 1) return root.withAlpha(root.colHighlight, 0.34 + 0.5 * s.noise);
                                                return root.mix(root.colActiveText, root.colHighlight, s.flash);
                                            }
                                        }

                                        // Exit flattens to a scanline and drifts sideways; transforms keep the Flow layout still
                                        transform: [
                                            Scale { origin.x: letter.width / 2; origin.y: letter.height * 0.6; yScale: letter.st.sy; xScale: 1 + (1 - letter.st.sy) * 0.6 },
                                            Translate { x: letter.st.dx }
                                        ]
                                    }
                                }
                            }
                        }

                        // Blinking cursor once the line is fully sung
                        Rectangle {
                            width: lineItem.cellW
                            height: lineItem.cellH
                            color: "transparent"
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: Math.round(lineItem.cellH * 0.14)
                                height: Math.max(3, Math.round(lineItem.fontPx * 0.1))
                                color: root.colHighlight
                                visible: Decode.tailCursor(lineItem.line, lineItem.t)
                            }
                        }
                    }
                }

                // Lock-on corner brackets
                Item {
                    id: brackets
                    readonly property real pad: lineItem.fr.pad + 10 * lineItem.fr.pulse
                    readonly property real arm: Math.round(lineItem.fontPx * 0.5)
                    readonly property real weight: 2
                    x: block.x - pad - 8
                    y: block.y - pad * 0.55 - 6
                    width: block.width + (pad + 8) * 2
                    height: block.height + (pad * 0.55 + 6) * 2
                    opacity: lineItem.fr.alpha * (lineItem.tear !== 0 ? 0.55 : 1)

                    Repeater {
                        model: 4
                        delegate: Item {
                            id: corner
                            required property int index
                            readonly property bool onRight: index % 2 === 1
                            readonly property bool onBottom: index >= 2
                            x: onRight ? brackets.width - brackets.arm : 0
                            y: onBottom ? brackets.height - brackets.arm : 0
                            width: brackets.arm
                            height: brackets.arm
                            Rectangle { y: corner.onBottom ? corner.height - brackets.weight : 0; width: corner.width; height: brackets.weight; color: root.colHighlight }
                            Rectangle { x: corner.onRight ? corner.width - brackets.weight : 0; width: brackets.weight; height: corner.height; color: root.colHighlight }
                        }
                    }

                    // HUD: line counter left, track clock right, progress hairline under the bottom edge
                    Text {
                        visible: !lineItem.leaving
                        anchors.left: parent.left
                        anchors.bottom: parent.top
                        anchors.bottomMargin: 6
                        text: lineItem.line ? root.pad2(lineItem.line.number) + " / " + root.pad2(lineItem.line.total) : ""
                        font.family: root.monoFamily
                        font.pixelSize: 12
                        font.letterSpacing: 2
                        color: root.withAlpha(root.colHighlight, 0.85)
                    }
                    Text {
                        visible: !lineItem.leaving
                        anchors.right: parent.right
                        anchors.bottom: parent.top
                        anchors.bottomMargin: 6
                        text: root.stamp(lineItem.t)
                        font.family: root.monoFamily
                        font.pixelSize: 12
                        font.letterSpacing: 2
                        color: root.withAlpha(root.colActiveText, 0.6)
                    }
                    Rectangle {
                        x: brackets.arm + 6
                        anchors.top: parent.bottom
                        anchors.topMargin: 6
                        width: (parent.width - 2 * (brackets.arm + 6)) * Decode.progress(lineItem.line, lineItem.t)
                        height: 1 + Math.round(2 * lineItem.fr.pulse)
                        color: root.colHighlight
                    }
                }
            }
        }
    }
}
