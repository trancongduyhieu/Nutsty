import QtQuick
import QtQuick.Effects
import "."
import "kinetic_stage.js" as Stage

// Desktop lyrics preset 7: a kinetic type stage (kinetic_stage.js). Up to three lines pile up,
// the newest big and the older ones shrunk and dimmed above it; each line gets its own type
// treatment, case and font, and its hero words are set heavy, wide or condensed in the accent
// colour. Backing vocals in ( ) get their own look, profanity goes under a glitching redaction
// bar, long breaks show waiting dots. The whole stage runs through an old-film pass
// (film_tv.frag): grain and scanlines inside the letters, a hair and scratches now and then.
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
    // Bangers (graffiti caps) and Patrick Hand (handwriting): Google Fonts, OFL, both cover Vietnamese
    FontLoader { id: markerFont; source: "../assets/fonts/Bangers-Regular.ttf" }
    FontLoader { id: handFont; source: "../assets/fonts/PatrickHand-Regular.ttf" }
    function loaded(f, fallback) { return (f.status === FontLoader.Ready && f.name !== "") ? f.name : fallback; }
    readonly property string heavyFamily: loaded(heavyFont, "Montserrat")
    readonly property string softFamily: loaded(softFont, "Instrument Serif")
    readonly property string markerFamily: loaded(markerFont, "Bangers")
    readonly property string handFamily: loaded(handFont, "Patrick Hand")
    readonly property string monoFamily: Qt.platform.os === "windows" ? "Consolas" : "monospace"

    function familyFor(key) {
        switch (key) {
        case "heavy": return root.heavyFamily;
        case "soft": return root.softFamily;
        case "marker": return root.markerFamily;
        case "hand": return root.handFamily;
        }
        return root.monoFamily;
    }
    function weightFor(key) { return key === "heavy" ? Font.Black : (key === "mono" ? Font.Bold : Font.Normal); }
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

    readonly property var filmFx: Stage.film(root.motion, root.t)
    readonly property var gap: Stage.gapAt(root.motion, root.t)

    // One soft shadow under everything so it reads on any wallpaper; no outline, no halo
    Item {
        id: shadowed
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

        Item {
            id: stage
            anchors.fill: parent
            layer.enabled: root.renderable
            layer.effect: ShaderEffect {
                readonly property var f: root.filmFx
                property size u_size: Qt.size(stage.width, stage.height)
                property real u_frame: f.frame % 997
                property real u_grain: f.grain
                property real u_scan: f.scan
                property real u_flicker: f.flicker
                property real u_chroma: f.chroma
                property real u_tear: f.tear
                property real u_hair: f.hair
                property real u_hairX: f.hairX
                property real u_hairAmp: f.hairAmp
                property real u_hairPhase: f.hairPhase
                property real u_scratchX: f.scratchX
                property real u_scratchA: f.scratchA
                property color u_ink: root.colActiveText
                property color u_accent: root.colHighlight
                fragmentShader: Qt.resolvedUrl("../assets/shaders/film_tv.frag.qsb")
            }

            // Waiting for the singer: three hand-drawn dots in brackets fill up towards the next line
            Item {
                id: waiting
                visible: root.gap.alpha > 0.003
                opacity: root.gap.alpha
                width: waitRow.width
                height: waitRow.height
                x: Math.round((root.width - width) / 2)
                y: Math.round(root.anchorY - height / 2)
                rotation: -3

                Row {
                    id: waitRow
                    spacing: 14
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "("
                        font.family: root.handFamily
                        font.pixelSize: 54
                        color: root.withAlpha(root.colActiveText, 0.7)
                    }
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            id: dot
                            required property int index
                            readonly property real lit: Math.max(0, Math.min(1, root.gap.prog * 3.2 - index))
                            // breathing, each dot a little behind the one before
                            readonly property real breath: 0.5 + 0.5 * Math.sin((root.t - root.gap.t0) * 3.2 - index * 0.9)
                            anchors.verticalCenter: parent.verticalCenter
                            width: 13 + 3 * dot.breath
                            height: width
                            radius: width / 2
                            color: root.mix(root.withAlpha(root.colActiveText, 1), root.colHighlight, dot.lit)
                            opacity: 0.35 + 0.65 * dot.lit
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ")"
                        font.family: root.handFamily
                        font.pixelSize: 54
                        color: root.withAlpha(root.colActiveText, 0.7)
                    }
                }
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
                                readonly property color ink: (word.hero || word.look === "shout") ? root.colHighlight : root.colActiveText
                                readonly property bool slant: word.italic === true

                                width: Math.ceil(letters.width * word.sx)
                                height: lineItem.lineH
                                // Opacity only, never visible: a hidden word would drop out of the Row and reflow the line
                                opacity: fx.alpha

                                // Every word sits a little off-axis (word.rot, word.jy) so the line reads hand-set
                                transform: [
                                    Scale { origin.x: wordItem.width / 2; origin.y: lineItem.baselineY; xScale: wordItem.fx.s; yScale: wordItem.fx.s },
                                    Rotation { origin.x: wordItem.width / 2; origin.y: lineItem.baselineY - wordItem.px * 0.35; angle: wordItem.word.rot + wordItem.fx.rot },
                                    Translate { x: wordItem.fx.dx * wordItem.px; y: (wordItem.fx.dy + wordItem.word.jy) * wordItem.px }
                                ]

                                // Hand-drawn underline under a hand-lettered hero, drawn once the word is sung
                                Rectangle {
                                    visible: wordItem.fx.under > 0.01
                                    x: -wordItem.px * 0.05
                                    y: lineItem.baselineY + Math.round(wordItem.px * 0.12)
                                    width: (wordItem.width + wordItem.px * 0.1) * wordItem.fx.under
                                    height: Math.max(2, Math.round(wordItem.px * 0.07))
                                    radius: height / 2
                                    rotation: -2.5
                                    transformOrigin: Item.Left
                                    color: wordItem.ink
                                    z: 2
                                }

                                // Redaction bar over a profane word: three strips that glitch sideways now and then
                                Item {
                                    visible: wordItem.word.censor === true && wordItem.fx.bar > 0.01
                                    x: -wordItem.px * 0.08
                                    y: lineItem.baselineY - Math.round(wordItem.px * 0.78)
                                    width: (wordItem.width + wordItem.px * 0.16) * wordItem.fx.bar
                                    height: Math.round(wordItem.px * 0.9)
                                    rotation: -1.5
                                    z: 3
                                    Repeater {
                                        model: 3
                                        delegate: Rectangle {
                                            required property int index
                                            x: wordItem.fx.barDx[index] * wordItem.px
                                            y: Math.round(index * parent.height / 3)
                                            width: parent.width
                                            height: Math.ceil(parent.height / 3) + 1
                                            color: Qt.rgba(0.03, 0.03, 0.045, 0.94)
                                            // hairline edge so the bar still reads on a dark wallpaper
                                            border.width: 1
                                            border.color: Qt.rgba(root.colHighlight.r, root.colHighlight.g, root.colHighlight.b, 0.28)
                                        }
                                    }
                                }

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
                                            font.italic: wordItem.slant
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
                                                transform: Rotation {
                                                    origin.x: letter.width / 2
                                                    origin.y: lineItem.baselineY - wordItem.px * 0.35
                                                    angle: letter.st.rot
                                                }

                                                // The rise treatment masks letters at the baseline as they come up
                                                // Handwriting reveals each letter from the left like a pen stroke
                                                Item {
                                                    width: Math.ceil(parent.width * letter.st.reveal) + (letter.st.reveal < 1 ? 0 : 4)
                                                    height: letter.st.clip ? lineItem.baselineY + Math.round(wordItem.px * 0.08) : lineItem.lineH
                                                    clip: letter.st.clip || letter.st.reveal < 1

                                                    Text {
                                                        id: glyph
                                                        x: letter.st.dx * wordItem.px
                                                        y: lineItem.baselineY - baselineOffset + letter.st.dy * wordItem.px
                                                        text: letter.st.glyph !== "" ? letter.st.glyph : letter.modelData
                                                        font.family: root.familyFor(wordItem.word.font)
                                                        font.weight: root.weightFor(wordItem.word.font)
                                                        font.italic: wordItem.slant
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
}
