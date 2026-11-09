import QtQuick
import QtQuick.Effects
import "."

// Apple Music Word-by-Word Flow Engine — 1-by-1 Character Sweep & Rolling Wave
// Spec source: amll-dev/applemusic-like-lyrics & maxrave-dev/SimpMusic
//   • Character sweep: Progressive illumination from left to right across glyphs
//   • Wave lift: Rises -2.0px when light touches and LEAVES IT THERE (rolling wave)
//   • MultiEffect Glow: Real volumetric Gaussian phosphor bloom on the singing word
//   • Micro Scale: 1.0 -> 1.012x (held: 1.045x) - strictly no balloon zoom

Item {
    id: root

    property var words: []
    property real currentTime: 0.0
    property bool isLineActive: false
    property int fontSize: 28
    property string fontFamily: Theme.fontFamily
    property int fontWeight: Font.Bold
    property color accentColor: "#ffffff"
    TextMetrics {
        id: spaceMetrics
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        font.weight: root.fontWeight
        text: " "
    }

    // Natural typographic space width matching static text (stops premature word wrapping)
    property int wordSpacing: Math.max(5, Math.round(spaceMetrics.width))

    // Compensate for 60ms audio buffer latency so words light up on-beat
    readonly property real effectiveTime: root.currentTime + 0.06
    readonly property var effectiveWords: root.words || []

    readonly property bool hasActiveHeldWord: {
        var ws = root.effectiveWords;
        for (var i = 0; i < ws.length; i++) {
            var w = ws[i];
            var dur = (w.duration || (w.end - w.start)) || 0;
            if ((w.isHeld || dur >= 0.85) && root.effectiveTime >= w.start && root.effectiveTime < w.end) {
                return true;
            }
        }
        return false;
    }

    property bool isAnsweringVoice: false
    property bool isEnsembleVoice: false

    TextMetrics {
        id: wordMetrics
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        font.weight: root.fontWeight
    }

    readonly property real maxLineWidth: parent ? Math.max(100, parent.width * (root.isAnsweringVoice ? 0.82 : 0.88)) : 480


    // 1:1 Mochy-Music sequential reading head: Finds the single active singing word index
    readonly property int activeWordIndex: {
        var ws = root.effectiveWords;
        if (!ws || ws.length === 0) return -1;
        var t = root.effectiveTime;
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

    // Partition words into lines that match the staticText wrap limit (parent.width * 0.82)
    // Ensures individual rows are properly right-aligned, centered, or left-aligned
    property var partitionedLines: []

    function updatePartition() {
        var ws = root.effectiveWords;
        if (!ws || ws.length === 0) {
            partitionedLines = [];
            return;
        }
        var limit = root.maxLineWidth;
        var lines = [];
        var curLine = [];
        var curWidth = 0;
        for (var i = 0; i < ws.length; i++) {
            var rawW = ws[i];
            var w = {
                text: rawW.text || "",
                start: (rawW.start !== undefined) ? Number(rawW.start) : 0.0,
                end: (rawW.end !== undefined) ? Number(rawW.end) : 0.0,
                duration: (rawW.duration !== undefined) ? Number(rawW.duration) : Math.max(0.05, (rawW.end - rawW.start)),
                hasSpace: (rawW.hasSpace !== false),
                isHeld: !!rawW.isHeld,
                globalIndex: i
            };
            wordMetrics.text = w.text || "";
            var wW = wordMetrics.width;
            var prevHadSpace = (curLine.length > 0) ? (curLine[curLine.length - 1].hasSpace !== false) : true;
            var gap = (curLine.length > 0 && prevHadSpace) ? root.wordSpacing : 0;
            var canBreak = (curLine.length > 0 && prevHadSpace);
            if (canBreak && (curWidth + gap + wW > limit)) {
                lines.push(curLine);
                curLine = [w];
                curWidth = wW;
            } else {
                curLine.push(w);
                curWidth += gap + wW;
            }
        }
        if (curLine.length > 0) lines.push(curLine);
        partitionedLines = lines;
    }

    onEffectiveWordsChanged: updatePartition()
    onMaxLineWidthChanged: updatePartition()
    onIsAnsweringVoiceChanged: updatePartition()
    onIsEnsembleVoiceChanged: updatePartition()
    onWidthChanged: updatePartition()
    Component.onCompleted: updatePartition()

    width: parent ? parent.width : implicitWidth
    implicitWidth: parent ? parent.width : 400
    implicitHeight: wordsColumn.implicitHeight + 8

    Column {
        id: wordsColumn
        y: 4
        width: root.width
        spacing: 6

        Repeater {
            model: root.partitionedLines

            delegate: Item {
                id: lineContainer
                width: wordsColumn.width
                height: lineWordsRow.implicitHeight

                Row {
                    id: lineWordsRow
                    spacing: 0
                    // 1:1 Mochy-Music Cartesian alignment: End -> (parent.width - width), Center -> (parent.width - width)/2, Start -> 0
                    // Eliminates Qt Quick positioner anchor resolution latency and anchor-deadlock
                    x: root.isAnsweringVoice ? Math.max(0, parent.width - width) : (root.isEnsembleVoice ? Math.max(0, Math.round((parent.width - width) / 2)) : 0)

                    Repeater {
                        id: lineWordsRepeater
                        model: modelData

                        delegate: Item {
                            id: wordRoot
                            readonly property var wData: modelData
                            readonly property int wordIdx: (wData && wData.globalIndex !== undefined) ? wData.globalIndex : index
                            readonly property bool isLastInLine: index === (lineWordsRepeater.count - 1)
                            readonly property real wStart: wData.start || 0.0
                            readonly property real wEnd: wData.end || 0.0
                            readonly property real wDur: Math.max(0.05, wData.duration || (wEnd - wStart))
                            readonly property bool isHeld: !!wData.isHeld || (wDur >= 0.85)

                            // Strict Mochy-Music Monotonic Reading: A word can NEVER be past or singing if the head hasn't reached it!
                            readonly property bool isPast: wordRoot.wordIdx < root.activeWordIndex || (wordRoot.wordIdx === root.activeWordIndex && root.effectiveTime >= wEnd)
                            readonly property bool isSinging: wordRoot.wordIdx === root.activeWordIndex && root.effectiveTime >= wStart && root.effectiveTime < wEnd
                            readonly property real wordProgress: wordRoot.isPast ? 1.0 : (wordRoot.isSinging ? Math.max(0.0, Math.min(1.0, (root.effectiveTime - wStart) / wDur)) : 0.0)

                            // C1 continuous smooth progress
                            property real smoothProg: 0.0
                            Behavior on smoothProg {
                                SmoothedAnimation { duration: 120; reversingMode: SmoothedAnimation.Immediate }
                            }
                            onWordProgressChanged: smoothProg = wordProgress

                            // Lagged Phosphor Bloom reader head: trails behind smoothProg to create a comet glow effect
                            property real bloomProg: 0.0
                            Behavior on bloomProg {
                                SmoothedAnimation { duration: 240; reversingMode: SmoothedAnimation.Immediate }
                            }
                            onSmoothProgChanged: bloomProg = smoothProg
                            readonly property real bloomLagDelta: wordRoot.isSinging ? (wordRoot.smoothProg - wordRoot.bloomProg) : 0.0

                            property real flareGate: isSinging ? 1.0 : 0.0
                            Behavior on flareGate {
                                NumberAnimation {
                                    duration: wordRoot.isSinging ? 400 : 1800
                                    easing.type: Easing.Linear
                                }
                            }

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

                            implicitWidth: charRow.implicitWidth + ((isLastInLine || (wData && wData.hasSpace === false)) ? 0 : root.wordSpacing)
                            implicitHeight: charRow.implicitHeight

                            Row {
                                id: charRow
                                anchors.left: parent.left
                                spacing: 0

                                Repeater {
                                    model: (wData.text || "").split("")

                                    delegate: Item {
                                        id: charItem
                                        readonly property string ch: modelData
                                        readonly property int charIndex: index
                                        readonly property int charCount: Math.max(1, (wData.text || "").length)

                                        readonly property real charFrom: charIndex / charCount
                                        readonly property real charTo: (charIndex + 1) / charCount
                                        readonly property real charCenter: (charFrom + charTo) / 2.0

                                        readonly property real charProgress: wordRoot.isPast ? 1.0 :
                                            (wordRoot.isSinging ? Math.max(0.0, Math.min(1.0, (wordRoot.smoothProg - charFrom) / Math.max(0.001, charTo - charFrom))) : 0.0)

                                        // Apple Wave Lift: Hermite curve w * w * (3.0 - 2.0 * w) for smooth -2.5px lift
                                        property real liftProgress: (charProgress > 0.0 || wordRoot.isPast) ? 1.0 : 0.0
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
                                                xScale: 1.0 + (wordRoot.waveScale - 1.0) * 0.5
                                                yScale: 1.0 + (wordRoot.isHeld ? 0.06 : 0.04) * wordRoot.yCurve
                                                origin.x: charItem.width / 2
                                                origin.y: charItem.height
                                            }
                                        ]

                                        // Typographic Sweep: 0.38 alpha (unsung) -> 1.0 pure white (sung)
                                        Text {
                                            id: charText
                                            anchors.centerIn: parent
                                            text: ch
                                            font.family: root.fontFamily
                                            font.pixelSize: root.fontSize
                                            font.weight: root.fontWeight
                                            color: {
                                                if (wordRoot.isPast || charItem.charProgress >= 1.0) return "#ffffff";
                                                if (charItem.charProgress <= 0.0) return Qt.rgba(1.0, 1.0, 1.0, 0.38);
                                                var p = charItem.charProgress;
                                                var alpha = 0.38 + (1.0 - 0.38) * p;
                                                return Qt.rgba(1.0, 1.0, 1.0, alpha);
                                            }
                                        }
                                    }
                                }
                            }

                            // Layer 2: True Hardware Gaussian MultiEffect Glow on Singing Word with Lagged Phosphor Bloom
                            // Optimization: Only instantiated on the single singing word to eliminate GPU FBO thrashing (60fps guaranteed)
                            Loader {
                                id: glowLoader
                                anchors.fill: charRow
                                active: wordRoot.isSinging
                                visible: active
                                sourceComponent: Component {
                                    MultiEffect {
                                        source: charRow
                                        anchors.fill: parent
                                        shadowEnabled: true
                                        shadowColor: "#ffffff"
                                        shadowBlur: 0.95
                                        shadowOpacity: wordRoot.isSinging ? (0.92 * wordRoot.flareGate * Math.sin(Math.PI * wordRoot.smoothProg)) : 0.0
                                        shadowHorizontalOffset: -wordRoot.bloomLagDelta * charRow.width * 0.45
                                        shadowVerticalOffset: 0
                                        shadowScale: 1.12
                                        visible: shadowOpacity > 0.01
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

