import QtQuick
import QtQuick.Effects
import "."
import "kinetic_stage.js" as Stage

// Desktop lyrics preset 7: a kinetic type stage (kinetic_stage.js). Up to three lines pile up,
// the newest big and the older ones shrunk and dimmed above it; each line gets its own type
// treatment and its hero words are set heavy, wide or condensed in the accent colour. A held
// hero word throws echo copies that slide away from it. One gentle camera move per pile.
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

    FontLoader { id: heavyFont; source: "../assets/fonts/Montserrat-Black.ttf" }
    FontLoader { id: softFont; source: "../assets/fonts/InstrumentSerif-Italic.ttf" }
    readonly property string heavyFamily: (heavyFont.status === FontLoader.Ready && heavyFont.name !== "") ? heavyFont.name : "Montserrat"
    readonly property string softFamily: (softFont.status === FontLoader.Ready && softFont.name !== "") ? softFont.name : "Instrument Serif"
    readonly property string monoFamily: Qt.platform.os === "windows" ? "Consolas" : "monospace"

    function familyFor(key) { return key === "heavy" ? root.heavyFamily : (key === "soft" ? root.softFamily : root.monoFamily); }
    function weightFor(key) { return key === "heavy" ? Font.Black : (key === "soft" ? Font.Normal : Font.Bold); }
    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
    function mix(a, b, k) { return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, 1); }

    implicitWidth: 880
    implicitHeight: 300

    readonly property bool renderable: root.visible && root.width > 0
    // Centre of the newest line; older lines stack upward from here
    readonly property real anchorY: root.height * 0.64

    property var motion: ({ lines: [] })

    // Smooth clock: extrapolates between position samples every frame (at most half a second)
    property real animClock: 0.0
    property real clockSample: 0.0
    property double clockStamp: 0
    readonly property real t: root.animClock + 0.04

    ListModel { id: visibleLines }

    function rebuild() {
        root.motion = Stage.build(root.activeLyrics);
        visibleLines.clear();
        syncVisible();
    }

    function syncVisible() {
        var want = Stage.visibleAt(root.motion.lines, root.t);
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
            shadowBlur: 0.6
            shadowVerticalOffset: 3
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
                readonly property var ls: Stage.lineState(line, t, root.width)
                readonly property var cam: Stage.camera(line, t, root.width, root.height)
                readonly property real base: line ? line.base : 48
                readonly property real lineH: Math.round(base * 1.3)
                readonly property real baselineY: Math.round(base * 1.0)
                // The script's width estimate sets the pile spacing; the measured row makes sure it fits
                readonly property real fit: Math.min(ls.fit, wordsRow.width > 0 ? root.width * 0.84 / wordsRow.width : 1)

                width: root.width
                height: root.height
                opacity: ls.alpha
                visible: ls.alpha > 0.003

                // The pile's camera: one move around the middle of the box
                readonly property real cx: width / 2
                readonly property real cy: height / 2
                transform: [
                    Rotation { origin.x: lineItem.cx; origin.y: lineItem.cy; axis { x: 1; y: 0; z: 0 } angle: lineItem.cam.rx },
                    Rotation { origin.x: lineItem.cx; origin.y: lineItem.cy; axis { x: 0; y: 1; z: 0 } angle: lineItem.cam.ry },
                    Rotation { origin.x: lineItem.cx; origin.y: lineItem.cy; angle: lineItem.cam.rot },
                    Scale { origin.x: lineItem.cx; origin.y: lineItem.cy; xScale: lineItem.cam.s; yScale: lineItem.cam.s },
                    Translate { x: lineItem.cam.x; y: lineItem.cam.y }
                ]

                // Kept on for the line's life so the blur never rebuilds mid-shot
                layer.enabled: root.renderable
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: Math.min(1, lineItem.ls.blur / 24)
                    blurMax: 24
                    autoPaddingEnabled: true
                }

                Row {
                    id: wordsRow
                    x: Math.round((root.width - width) / 2)
                    y: Math.round(root.anchorY + lineItem.ls.y - lineItem.lineH / 2)
                    height: lineItem.lineH
                    spacing: Math.round(lineItem.base * 0.24)
                    transform: Scale {
                        origin.x: wordsRow.width / 2
                        origin.y: lineItem.lineH / 2
                        xScale: lineItem.ls.s * lineItem.fit
                        yScale: lineItem.ls.s * lineItem.fit
                    }

                    Repeater {
                        model: lineItem.line ? lineItem.line.words : []

                        delegate: Item {
                            id: wordItem
                            required property int index
                            required property var modelData
                            readonly property var word: modelData
                            readonly property var fx: Stage.wordFx(lineItem.line, lineItem.t, index)
                            readonly property real px: Math.round(lineItem.base * word.size)
                            readonly property color ink: word.hero ? root.colHighlight : root.colActiveText

                            width: Math.ceil(letters.width * word.sx)
                            height: lineItem.lineH
                            // Opacity only, never visible: a hidden word would drop out of the Row and reflow the line
                            opacity: fx.alpha

                            transform: [
                                Scale { origin.x: wordItem.width / 2; origin.y: lineItem.baselineY; xScale: wordItem.fx.s; yScale: wordItem.fx.s },
                                Translate { x: wordItem.fx.dx * wordItem.px; y: wordItem.fx.dy * wordItem.px }
                            ]

                            // Letters and their echo copies share the wide / condensed stretch
                            Item {
                                id: body
                                width: letters.width
                                height: parent.height
                                transform: Scale { xScale: wordItem.word.sx }

                                Repeater {
                                    model: 4
                                    delegate: Text {
                                        id: ghost
                                        required property int index
                                        readonly property var g: wordItem.fx.ghosts[index]
                                        visible: g.a > 0.004
                                        x: g.dx * wordItem.px
                                        y: lineItem.baselineY - baselineOffset + g.dy * wordItem.px
                                        opacity: g.a
                                        text: wordItem.word.chars.join("")
                                        font.family: root.familyFor(wordItem.word.font)
                                        font.weight: root.weightFor(wordItem.word.font)
                                        font.pixelSize: wordItem.px
                                        color: wordItem.ink
                                    }
                                }

                                Row {
                                    id: letters

                                    Repeater {
                                        model: wordItem.word.chars

                                        delegate: Item {
                                            id: letter
                                            required property int index
                                            required property string modelData
                                            readonly property var st: Stage.letterState(lineItem.line, lineItem.t, wordItem.index, index)

                                            width: Math.ceil(glyph.implicitWidth)
                                            height: lineItem.lineH
                                            opacity: st.alpha

                                            // The rise treatment masks letters at the baseline as they come up
                                            Item {
                                                width: parent.width
                                                height: lineItem.baselineY + Math.round(wordItem.px * 0.08)
                                                clip: letter.st.clip

                                                Text {
                                                    id: glyph
                                                    x: letter.st.dx * wordItem.px
                                                    y: lineItem.baselineY - baselineOffset + letter.st.dy * wordItem.px
                                                    text: letter.st.glyph !== "" ? letter.st.glyph : letter.modelData
                                                    font.family: root.familyFor(wordItem.word.font)
                                                    font.weight: root.weightFor(wordItem.word.font)
                                                    font.pixelSize: wordItem.px
                                                    // Waiting letters sit dim; sung ones fill, a decode lock flashes the accent
                                                    color: {
                                                        var s = letter.st;
                                                        var c = s.flash > 0 ? root.mix(wordItem.ink, root.colHighlight, s.flash) : wordItem.ink;
                                                        return root.withAlpha(c, s.tone);
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
}
