import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "."
import "kinetic_stage.js" as Stage

// Desktop lyrics preset 7: a kinetic type stage (kinetic_stage.js). Up to three lines pile up,
// the newest big and the older ones shrunk and dimmed above it; each line gets its own type
// treatment, case and font, and its hero words are set heavy, wide or condensed in the accent
// colour; most lines sit off the level (zigzag, stairs or arc) and tilted. Some piles are a single
// big line set off-centre. Backing vocals in ( ) drop their brackets and stack in a small column
// to the left or right of the line. Most lines get a pen mark: a coil, underline, double line,
// zigzag or wave under them, or a ring, box, ticks or arrow on the hero word. A pile leaves by
// lifting away, being struck through, smudged sideways or scribbled out. With `maximal` (preset 8)
// every line gets all of it at once: double-drawn strokes, a marker swipe behind the hero, a ring
// round the line, and doodles scattered round it. Its piles take a role from the singing tempo:
// a peak line gets one big move on its hero (a bulb on its cord lighting the word, a spotlight ring,
// focus rays, an ink fill or a stamp), a rush line a mark on every word, and duos and stacks a pen
// mark that ties their lines together. Profanity goes under a glitching redaction bar, long breaks
// show waiting dots. The whole stage runs through an old-film pass (film_tv.frag): grain and
// scanlines inside the letters, a hair and scratches, a light smear and swell on big hits.
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
    // Preset 8: the maximal cut, every line covered in pen marks and doodles (kinetic_stage.js)
    property bool maximal: false

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
    // measured width of each line's body (before scaling), by line index, for the pile marks
    property var bodyW: ({})

    property var motion: ({ lines: [] })

    // Smooth clock: extrapolates between position samples every frame (at most half a second)
    property real animClock: 0.0
    property real clockSample: 0.0
    property double clockStamp: 0
    readonly property real t: root.animClock + 0.04

    ListModel { id: visibleLines }

    function rebuild() {
        root.bodyW = {};
        root.motion = Stage.build(root.activeLyrics, { max: root.maximal });
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
    onMaximalChanged: rebuild()
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
                property real u_smear: f.smear
                property real u_smearDir: f.smearDir
                property real u_bulge: f.bulge
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

            // Marks that tie a duo or a stack together (Stage.pileStrokes), drawn once per pile from
            // its first line, under that pile's camera
            Repeater {
                model: visibleLines

                delegate: Item {
                    id: pileItem
                    required property int lineIdx
                    readonly property var line: root.motion.lines[lineIdx] || null
                    readonly property bool on: line !== null && line.slot === 0 && (line.pile.role === "duo" || line.pile.role === "stack")
                    readonly property var cam: on ? Stage.camera(line, root.t, root.width, root.height) : null
                    // the measured widths of this pile's lines (its lines follow one another in motion.lines)
                    readonly property var bodyW: on && root.t > -1 ? line.pile.lines.map(function (L, k) { return root.bodyW[pileItem.lineIdx + k] || 0; }) : []
                    readonly property var ps: on ? Stage.pileState(line.pile, root.t, root.width, root.height, root.anchorY, bodyW) : null
                    width: root.width
                    height: root.height
                    visible: on && ps.alpha > 0.003
                    opacity: on ? ps.alpha * (line.pile.fx === "draft" ? 0.5 : 1) : 0
                    transform: [
                        Rotation { origin.x: pileItem.width / 2; origin.y: pileItem.height / 2; axis { x: 1; y: 0; z: 0 } angle: pileItem.cam ? pileItem.cam.rx : 0 },
                        Rotation { origin.x: pileItem.width / 2; origin.y: pileItem.height / 2; axis { x: 0; y: 1; z: 0 } angle: pileItem.cam ? pileItem.cam.ry : 0 },
                        Rotation { origin.x: pileItem.width / 2; origin.y: pileItem.height / 2; angle: pileItem.cam ? pileItem.cam.rot : 0 },
                        Scale { origin.x: pileItem.width / 2; origin.y: pileItem.height / 2; xScale: pileItem.cam ? pileItem.cam.s : 1; yScale: pileItem.cam ? pileItem.cam.s : 1 },
                        Translate { x: pileItem.cam ? pileItem.cam.x : 0; y: pileItem.cam ? pileItem.cam.y : 0 }
                    ]
                    PenMark {
                        anchors.fill: parent
                        strokes: pileItem.visible ? Stage.pileStrokes(pileItem.line.pile, root.t, root.width, root.height, root.anchorY, pileItem.bodyW) : []
                        ink: root.withAlpha(root.colHighlight, 0.85)
                        penW: Math.max(2, pileItem.line ? pileItem.line.base * 0.04 : 2)
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
                    readonly property int side: line && line.side ? line.side : 1
                    readonly property bool hasSide: line !== null && line.sideIdx.length > 0
                    // The script's width estimate sets the pile spacing; the measured body makes sure it fits
                    readonly property real fit: Math.min(ls.fit, lineBody.width > 0 ? root.width * Stage.roomOf(line) / lineBody.width : 1)

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

                    // The line and its backing-vocal column, laid out side by side, then scaled and tilted as one
                    Item {
                        id: lineBody
                        readonly property real gapX: lineItem.hasSide ? Math.round(lineItem.base * 0.42) : 0
                        width: wordsRow.width + (lineItem.hasSide ? sideBox.width + gapX : 0)
                        onWidthChanged: root.bodyW[lineItem.lineIdx] = width
                        height: lineItem.lineH
                        x: Math.round((root.width - width) / 2)
                        y: Math.round(root.anchorY + lineItem.ls.y - lineItem.lineH / 2)
                        transform: [
                            Rotation { origin.x: lineBody.width / 2; origin.y: lineItem.lineH / 2; angle: lineItem.line ? lineItem.line.tilt : 0 },
                            Scale {
                                origin.x: lineBody.width / 2
                                origin.y: lineItem.lineH / 2
                                xScale: lineItem.ls.s * lineItem.fit * lineItem.ls.sx
                                yScale: lineItem.ls.s * lineItem.fit
                            },
                            Translate { x: lineItem.ls.dx }
                        ]

                        Row {
                            id: wordsRow
                            x: lineItem.side < 0 && lineItem.hasSide ? sideBox.width + lineBody.gapX : 0
                            height: lineItem.lineH
                            spacing: Math.round(lineItem.base * 0.24)
                            Repeater {
                                model: lineItem.line ? lineItem.line.mainIdx : []
                                delegate: wordComp
                            }
                        }

                        // Pen mark under the line, drawn as the line is sung: a loose coil, an underline
                        // with a flick, a double line, a zigzag or a wave
                        PenMark {
                            id: underMark
                            readonly property string kind: lineItem.line ? Stage.markKind(lineItem.line, "line") : ""
                            readonly property bool coil: kind === "coil"
                            readonly property bool wrap: kind === "wrap"     // a big ring round the whole line
                            x: wrap ? wordsRow.x - Math.round(lineItem.base * 0.4) : wordsRow.x + Math.round(wordsRow.width * (coil ? 0.08 : 0.03))
                            y: wrap ? -Math.round(lineItem.base * 0.3) : lineItem.lineH - Math.round(lineItem.base * (coil ? 0.06 : 0.02))
                            width: wrap ? wordsRow.width + Math.round(lineItem.base * 0.8) : Math.round(wordsRow.width * (coil ? 0.62 : 0.9))
                            height: wrap ? lineItem.lineH + Math.round(lineItem.base * 0.6)
                                         : Math.round(lineItem.base * (coil ? 0.4 : (kind === "double" || kind === "wave" ? 0.3 : 0.22)))
                            rotation: wrap ? -2 : -1.5
                            strokes: kind ? Stage.penStrokes(lineItem.line, lineItem.t, "line", width, height) : []
                            ink: root.withAlpha(root.colActiveText, 0.72)
                            penW: Math.max(2, lineItem.base * 0.04)
                        }

                        // A peak's ink: a dense marker fill sweeping behind the whole line as it is sung
                        PenMark {
                            readonly property bool on: lineItem.line !== null && lineItem.line.pile.role === "peak" && lineItem.line.pile.fx === "ink"
                            visible: on && strokes.length > 0
                            x: wordsRow.x - Math.round(lineItem.base * 0.15)
                            y: Math.round(lineItem.base * 0.12)
                            width: wordsRow.width + Math.round(lineItem.base * 0.3)
                            height: Math.round(lineItem.base * 0.95)
                            z: -1
                            strokes: on ? Stage.peakStrokes(lineItem.line, lineItem.t, "ink", width, height) : []
                            ink: root.withAlpha(root.colHighlight, 0.22)
                            penW: Math.round(lineItem.base * 0.5)
                            cap: ShapePath.FlatCap
                        }

                        // Doodles scattered round the line in the maximal cut: stars, bursts, spirals, hearts...
                        Repeater {
                            model: lineItem.line && lineItem.line.doodles ? lineItem.line.doodles.length : 0
                            delegate: PenMark {
                                id: doodle
                                required property int index
                                readonly property var d: lineItem.line.doodles[index]
                                readonly property real sz: Math.round(lineItem.base * d.k)
                                // never on the side the backing vocals sit
                                readonly property string spot: lineItem.hasSide && ((d.spot === "left" && lineItem.side < 0) || (d.spot === "right" && lineItem.side > 0)) ? "above" : d.spot
                                width: sz
                                height: sz
                                x: spot === "left" ? wordsRow.x - sz * 1.15
                                 : spot === "right" ? wordsRow.x + wordsRow.width + sz * 0.15
                                 : wordsRow.x + d.u * wordsRow.width - sz / 2
                                y: spot === "above" ? -sz * 0.8
                                 : spot === "below" ? lineItem.lineH + sz * 0.05
                                 : lineItem.lineH / 2 - sz / 2 + (d.u - 0.5) * sz
                                rotation: d.rot
                                z: 2
                                strokes: Stage.doodleStrokes(lineItem.line, lineItem.t, index, width, height)
                                ink: root.withAlpha(d.accent ? root.colHighlight : root.colActiveText, 0.85)
                                penW: Math.max(2, lineItem.base * 0.035)
                            }
                        }

                        // Pen exit: struck through or scribbled out as the pile leaves
                        PenMark {
                            readonly property string kind: lineItem.line ? Stage.markKind(lineItem.line, "exit") : ""
                            x: wordsRow.x
                            y: 0
                            width: wordsRow.width
                            height: lineItem.lineH
                            z: 3
                            strokes: kind ? Stage.penStrokes(lineItem.line, lineItem.t, "exit", width, height) : []
                            ink: root.withAlpha(root.colHighlight, 0.92)
                            penW: Math.max(2.5, lineItem.base * (kind === "scrawl" ? 0.045 : 0.06))
                        }

                        // Backing vocals, brackets dropped: a small stacked column beside the line,
                        // set off by a thin accent rule on the side that faces the line
                        Item {
                            id: sideBox
                            visible: lineItem.hasSide
                            width: sideCol.width + 10
                            height: sideCol.height
                            x: lineItem.side < 0 ? 0 : wordsRow.width + lineBody.gapX
                            y: Math.round((lineItem.lineH - height) / 2 - lineItem.base * 0.08)
                            rotation: lineItem.side * -4

                            Rectangle {
                                x: lineItem.side < 0 ? parent.width - width : 0
                                width: 2
                                height: parent.height * (first ? first.alpha : 0)
                                radius: 1
                                color: root.colHighlight
                                opacity: 0.8
                                // grows down as the first backing word comes in
                                readonly property var first: lineItem.line && lineItem.hasSide ? Stage.wordFx(lineItem.line, lineItem.t, lineItem.line.sideIdx[0]) : null
                            }

                            Column {
                                id: sideCol
                                x: lineItem.side < 0 ? 0 : 10
                                spacing: Math.round(lineItem.base * 0.02)
                                Repeater {
                                    model: lineItem.hasSide ? lineItem.line.sideIdx : []
                                    delegate: wordComp
                                }
                            }
                        }
                    }

                    // One word, in the line or in the side column; modelData is its index in line.words
                    Component {
                        id: wordComp

                        Item {
                            id: wordItem
                            required property var modelData
                            readonly property int wi: modelData
                            readonly property var word: lineItem.line.words[wi]
                            readonly property bool inSide: word.paren === true && lineItem.hasSide
                            readonly property var fx: Stage.wordFx(lineItem.line, lineItem.t, wi)
                            readonly property real px: Math.round(lineItem.base * word.size)
                            readonly property real boxH: inSide ? Math.round(px * 1.12) : lineItem.lineH
                            readonly property real bl: inSide ? Math.round(px * 0.9) : lineItem.baselineY
                            readonly property color ink: (word.hero || word.look === "shout") ? root.colHighlight : root.colActiveText
                            readonly property bool slant: word.italic === true

                            width: Math.ceil(letters.width * word.sx)
                            height: boxH
                            // Opacity only, never visible: a hidden word would drop out of the Row and reflow the line
                            opacity: fx.alpha

                            // Every word sits a little off-axis (word.rot, word.jy) so the line reads hand-set
                            transform: [
                                Scale { origin.x: wordItem.width / 2; origin.y: wordItem.bl; xScale: wordItem.fx.s; yScale: wordItem.fx.s },
                                Rotation { origin.x: wordItem.width / 2; origin.y: wordItem.bl - wordItem.px * 0.35; angle: wordItem.word.rot + wordItem.fx.rot },
                                Translate { x: wordItem.fx.dx * wordItem.px; y: (wordItem.fx.dy + wordItem.word.jy) * wordItem.px }
                            ]

                            // Marker swipe behind the hero in the maximal cut, laid down as the word is sung
                            PenMark {
                                readonly property string kind: lineItem.line.hiWi === wordItem.wi ? "hilite" : ""
                                x: -Math.round(wordItem.px * 0.06)
                                y: wordItem.bl - Math.round(wordItem.px * 0.7)
                                width: wordItem.width + Math.round(wordItem.px * 0.12)
                                height: Math.round(wordItem.px * 0.62)
                                rotation: -2
                                z: -1
                                strokes: kind ? Stage.penStrokes(lineItem.line, lineItem.t, "hilite", width, height) : []
                                ink: root.withAlpha(root.colHighlight, 0.22)
                                penW: Math.round(wordItem.px * 0.42)
                                cap: ShapePath.FlatCap
                            }

                            // Hand-drawn underline under a hand-lettered hero, drawn once the word is sung
                            Rectangle {
                                visible: wordItem.fx.under > 0.01
                                x: -wordItem.px * 0.05
                                y: wordItem.bl + Math.round(wordItem.px * 0.12)
                                width: (wordItem.width + wordItem.px * 0.1) * wordItem.fx.under
                                height: Math.max(2, Math.round(wordItem.px * 0.07))
                                radius: height / 2
                                rotation: -2.5
                                transformOrigin: Item.Left
                                color: wordItem.ink
                                z: 2
                            }

                            // Pen mark on the hero word, drawn just after it lands: a ring or a rough box
                            // round it, three shout ticks off a corner, or an arrow swooping in.
                            // A rush line puts a small tick or ring on every word as it lands.
                            PenMark {
                                readonly property string kind: Stage.wordMarkKind(lineItem.line, wordItem.wi)
                                readonly property bool tick: kind === "tick"
                                readonly property bool round: kind === "ring" || kind === "box"
                                readonly property real pad: kind === "ring" ? 0.28 : (kind === "box" ? 0.16 : 0)
                                readonly property real boxH: kind === "ring" ? 1.3 : (kind === "box" ? 1.06 : (kind === "ticks" ? 1.3 : 0.95))
                                // a tick sits small off the word's top right corner, clear of the letters
                                x: tick ? wordItem.width - Math.round(wordItem.px * 0.05) : -Math.round(wordItem.px * pad)
                                y: tick ? wordItem.bl - Math.round(wordItem.px * 1.15) : wordItem.bl - Math.round(wordItem.px * (kind === "ring" ? 0.98 : (kind === "box" ? 0.86 : 0.78)))
                                width: tick ? Math.round(wordItem.px * 0.42) : wordItem.width + Math.round(wordItem.px * pad * 2)
                                height: tick ? Math.round(wordItem.px * 0.42) : Math.round(wordItem.px * boxH)
                                rotation: kind === "box" ? -1.5 : (round ? -3 : 0)
                                z: 2
                                strokes: kind ? Stage.wordStrokes(lineItem.line, lineItem.t, wordItem.wi, width, height) : []
                                ink: root.withAlpha(root.colHighlight, 0.85)
                                penW: Math.max(2, wordItem.px * 0.045)
                            }

                            // A peak's hero carries the line's one big move (pile.fx): a spotlight ring,
                            // a stamp, manga focus lines, or a bulb dropping on its cord and switching on
                            readonly property string peakFx: lineItem.line.pile.role === "peak" && lineItem.line.heroWi === wordItem.wi ? lineItem.line.pile.fx : ""
                            readonly property var peak: peakFx === "bulb" ? Stage.peakState(lineItem.line, lineItem.t) : null

                            PenMark {
                                readonly property bool on: wordItem.peakFx === "spot" || wordItem.peakFx === "stamp"
                                readonly property real k: wordItem.peakFx === "spot" ? 1.8 : 1.25
                                visible: on && strokes.length > 0
                                width: Math.round((wordItem.width + wordItem.px * 0.3) * k)
                                height: Math.round(wordItem.px * 1.15 * k)
                                x: Math.round((wordItem.width - width) / 2)
                                y: Math.round(wordItem.bl - wordItem.px * 0.36 - height / 2)
                                rotation: wordItem.peakFx === "stamp" ? -7 : -3
                                z: 2
                                strokes: on ? Stage.peakStrokes(lineItem.line, lineItem.t, wordItem.peakFx === "spot" ? "ring" : "stamp", width, height) : []
                                ink: root.withAlpha(root.colHighlight, 0.9)
                                penW: Math.max(2.5, wordItem.px * (wordItem.peakFx === "stamp" ? 0.09 : 0.05))
                            }

                            PenMark {
                                readonly property bool on: wordItem.peakFx === "rays"
                                visible: on && strokes.length > 0
                                width: Math.round(wordItem.px * 6)
                                height: Math.round(wordItem.px * 3)
                                x: Math.round((wordItem.width - width) / 2)
                                y: Math.round(wordItem.bl - wordItem.px * 0.36 - height / 2)
                                z: -1
                                strokes: on ? Stage.peakStrokes(lineItem.line, lineItem.t, "rays", width, height) : []
                                ink: root.withAlpha(root.colActiveText, 0.5)
                                penW: Math.max(1.5, wordItem.px * 0.03)
                            }

                            // The bulb's light: a soft accent cone from the glass down onto the word
                            Shape {
                                readonly property real topW: wordItem.px * 0.4
                                readonly property real botW: wordItem.width + wordItem.px * 0.5
                                visible: wordItem.peak !== null && wordItem.peak.cone > 0.01
                                opacity: wordItem.peak ? wordItem.peak.cone : 0
                                width: botW
                                height: Math.round(wordItem.px * 1.25)
                                x: Math.round((wordItem.width - width) / 2)
                                y: Math.round(wordItem.bl - wordItem.px * 1.08)
                                z: -1
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    strokeColor: "transparent"
                                    fillGradient: LinearGradient {
                                        x1: 0; y1: 0; x2: 0; y2: wordItem.px * 1.25
                                        GradientStop { position: 0; color: root.withAlpha(root.colHighlight, 0.28) }
                                        GradientStop { position: 1; color: root.withAlpha(root.colHighlight, 0) }
                                    }
                                    startX: (wordItem.width + wordItem.px * 0.5 - wordItem.px * 0.4) / 2; startY: 0
                                    PathLine { x: (wordItem.width + wordItem.px * 0.5 + wordItem.px * 0.4) / 2; y: 0 }
                                    PathLine { x: wordItem.width + wordItem.px * 0.5; y: wordItem.px * 1.25 }
                                    PathLine { x: 0; y: wordItem.px * 1.25 }
                                    PathLine { x: (wordItem.width + wordItem.px * 0.5 - wordItem.px * 0.4) / 2; y: 0 }
                                }
                            }

                            // The bulb on its cord: drops in with a springy bounce, swings round the top of
                            // its cord as it settles, then lights up with a burst of short rays
                            Item {
                                id: bulbRig
                                readonly property real cordH: wordItem.px * 3
                                readonly property real glassH: wordItem.px * 0.9
                                visible: wordItem.peak !== null
                                width: Math.round(wordItem.px * 0.8)
                                height: cordH + glassH
                                x: Math.round((wordItem.width - width) / 2)
                                y: wordItem.bl - wordItem.px * 1.9 - cordH + (wordItem.peak ? wordItem.peak.bulbY * wordItem.px : 0)
                                transformOrigin: Item.Top
                                rotation: wordItem.peak ? wordItem.peak.bulbTilt : 0
                                z: 3

                                PenMark {
                                    width: parent.width
                                    height: bulbRig.cordH
                                    strokes: wordItem.peak ? Stage.peakStrokes(lineItem.line, lineItem.t, "cord", width, height) : []
                                    ink: root.withAlpha(root.colActiveText, 0.75)
                                    penW: Math.max(1.5, wordItem.px * 0.03)
                                }
                                PenMark {
                                    width: Math.round(wordItem.px * 2.6)
                                    height: width
                                    x: Math.round((parent.width - width) / 2)
                                    y: Math.round(bulbRig.cordH + bulbRig.glassH * 0.6 - height / 2)
                                    strokes: wordItem.peak ? Stage.peakStrokes(lineItem.line, lineItem.t, "glow", width, height) : []
                                    ink: root.withAlpha(root.colHighlight, 0.85)
                                    penW: Math.max(1.5, wordItem.px * 0.035)
                                }
                                PenMark {
                                    y: bulbRig.cordH
                                    width: parent.width
                                    height: bulbRig.glassH
                                    strokes: wordItem.peak ? Stage.peakStrokes(lineItem.line, lineItem.t, "bulb", width, height) : []
                                    ink: wordItem.peak && wordItem.peak.on ? root.colHighlight : root.withAlpha(root.colActiveText, 0.85)
                                    penW: Math.max(2, wordItem.px * 0.045)
                                }
                            }

                            // Redaction bar over a profane word: three strips that glitch sideways now and then
                            Item {
                                visible: wordItem.word.censor === true && wordItem.fx.bar > 0.01
                                x: -wordItem.px * 0.08
                                y: wordItem.bl - Math.round(wordItem.px * 0.78)
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
                                        y: wordItem.bl - baselineOffset + g.dy * wordItem.px
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
                                            readonly property var st: Stage.letterState(lineItem.line, lineItem.t, wordItem.wi, index)

                                            width: Math.ceil(glyph.implicitWidth)
                                            height: wordItem.boxH
                                            opacity: st.alpha
                                            transform: Rotation {
                                                origin.x: letter.width / 2
                                                origin.y: wordItem.bl - wordItem.px * 0.35
                                                angle: letter.st.rot
                                            }

                                            // The rise treatment masks letters at the baseline as they come up
                                            // Handwriting reveals each letter from the left like a pen stroke
                                            Item {
                                                width: Math.ceil(parent.width * letter.st.reveal) + (letter.st.reveal < 1 ? 0 : 4)
                                                height: letter.st.clip ? wordItem.bl + Math.round(wordItem.px * 0.08) : wordItem.boxH
                                                clip: letter.st.clip || letter.st.reveal < 1

                                                Text {
                                                    id: glyph
                                                    readonly property color tint: {
                                                        var s = letter.st;
                                                        var c = s.flash > 0 ? root.mix(wordItem.ink, root.colHighlight, s.flash) : wordItem.ink;
                                                        return root.withAlpha(c, s.tone);
                                                    }
                                                    x: letter.st.dx * wordItem.px
                                                    y: wordItem.bl - baselineOffset + letter.st.dy * wordItem.px
                                                    text: letter.st.glyph !== "" ? letter.st.glyph : letter.modelData
                                                    font.family: root.familyFor(wordItem.word.font)
                                                    font.weight: root.weightFor(wordItem.word.font)
                                                    font.italic: wordItem.slant
                                                    font.pixelSize: wordItem.px
                                                    // Waiting letters sit dim; sung ones fill, a decode lock flashes the accent.
                                                    // Hollow backing vocals are drawn as outlines only.
                                                    color: wordItem.word.hollow === true ? "transparent" : tint
                                                    style: wordItem.word.hollow === true ? Text.Outline : Text.Normal
                                                    styleColor: tint
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
