import QtQuick
import QtQuick.Effects
import "."
import "motion_recipes.js" as Motion

// Per-letter lyric motion built on motion_recipes.js (JIZURA-style enter / hold / exit).
// Every letter's state is a pure function of the clock, so seeking and looping never pop.
// family: "" lets each song pick its own mood; or one of Motion.FAMILY_ORDER to pin it,
// which is how a fixed-style preset can reuse this view.
Item {
    id: root

    property var activeLyrics: []
    property real currentTime: 0.0
    property bool isPlaying: false
    property string family: ""

    property color colHighlight: "#deb06c"
    property color colActiveText: "#f8fafc"
    property color colShadowDir: "#a6020305"
    property color colShadowAmb: "#66000000"
    property bool isLightArea: false

    implicitWidth: 880
    implicitHeight: 220

    readonly property bool renderable: root.visible && root.width > 0

    property var motion: ({ lines: [], seed: 0 })

    // Smooth clock: extrapolates between position samples every frame (at most half a second)
    property real animClock: 0.0
    property real clockSample: 0.0
    property double clockStamp: 0
    readonly property real t: root.animClock + 0.04

    ListModel { id: visibleLines }

    function rebuild() {
        root.motion = Motion.build(root.activeLyrics, root.family);
        visibleLines.clear();
        syncVisible();
    }

    function syncVisible() {
        var want = Motion.visibleAt(root.motion.lines, root.t);
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
    onFamilyChanged: rebuild()
    onRenderableChanged: if (renderable) { root.animClock = root.currentTime; advanceClock(); }
    Component.onCompleted: { root.animClock = root.currentTime; rebuild(); }

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
            blurMax: 24
            autoPaddingEnabled: true
        }

        Repeater {
            model: visibleLines

            delegate: Item {
                id: lineItem
                required property int lineIdx
                readonly property var line: root.motion.lines[lineIdx] || null
                readonly property real t: root.t

                x: 0
                y: Math.round((root.height - lineFlow.height) / 2)
                width: root.width
                height: lineFlow.height

                // One blur layer per line, kept on for the line's life so it never rebuilds mid-flight
                layer.enabled: root.renderable
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: Motion.lineBlur(lineItem.line, lineItem.t)
                    blurMax: 20
                    autoPaddingEnabled: true
                }

                Flow {
                    id: lineFlow
                    width: parent.width
                    spacing: lineItem.line ? Math.round(lineItem.line.font * 0.28) : 10

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

                                    readonly property var st: Motion.letterState(lineItem.line, lineItem.t, wordRow.index, letter.index)

                                    width: glyph.implicitWidth
                                    height: glyph.implicitHeight
                                    opacity: st.alpha
                                    visible: st.alpha > 0.003
                                    clip: st.clip

                                    Text {
                                        id: glyph
                                        y: letter.st.clipDy * letter.height
                                        text: letter.st.glyph !== "" ? letter.st.glyph : letter.modelData
                                        font.family: Theme.fontFamily
                                        font.pixelSize: lineItem.line ? lineItem.line.font : 40
                                        font.weight: Font.Bold
                                        // Waiting letters dim; sung ones fill in, the word being sung in the accent
                                        color: {
                                            var c = letter.st.lit ? root.colHighlight : root.colActiveText;
                                            return Qt.rgba(c.r, c.g, c.b, 0.46 + 0.54 * letter.st.sung);
                                        }
                                    }

                                    transform: [
                                        Scale {
                                            origin.x: letter.width / 2
                                            origin.y: letter.height * 0.62
                                            xScale: letter.st.s * letter.st.sx
                                            yScale: letter.st.s * letter.st.sy
                                        },
                                        Rotation {
                                            origin.x: letter.width / 2
                                            origin.y: letter.height * 0.62
                                            angle: letter.st.rot
                                        },
                                        Translate { x: letter.st.dx; y: letter.st.dy }
                                    ]
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
