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
    property int wordSpacing: 9

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

    implicitWidth: parent ? parent.width : 300
    implicitHeight: wordsFlow.implicitHeight + 8

    Flow {
        id: wordsFlow
        y: 4
        width: root.width
        spacing: root.wordSpacing

        Repeater {
            model: root.effectiveWords

            delegate: Item {
                id: wordRoot
                readonly property var wData: modelData
                readonly property real wStart: wData.start || 0.0
                readonly property real wEnd: wData.end || 0.0
                readonly property real wDur: Math.max(0.05, wData.duration || (wEnd - wStart))
                readonly property bool isHeld: !!wData.isHeld || (wDur >= 0.85)
                readonly property bool isPast: root.effectiveTime >= wEnd
                readonly property bool isSinging: root.effectiveTime >= wStart && root.effectiveTime < wEnd
                readonly property real wordProgress: Math.max(0.0, Math.min(1.0, (root.effectiveTime - wStart) / wDur))

                // C1 continuous smooth progress
                property real smoothProg: 0.0
                Behavior on smoothProg {
                    SmoothedAnimation { duration: 120; reversingMode: SmoothedAnimation.Immediate }
                }
                onWordProgressChanged: smoothProg = wordProgress

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

                implicitWidth: charRow.implicitWidth
                implicitHeight: charRow.implicitHeight

                Row {
                    id: charRow
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

                            // Apple Wave Lift: Rises by -2.0px when light touches, and STAYS LIFTED!
                            property real liftProgress: (charProgress > 0.0 || wordRoot.isPast) ? 1.0 : 0.0
                            Behavior on liftProgress {
                                NumberAnimation {
                                    duration: 750
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.4, 0.0, 0.2, 1.0]
                                }
                            }

                            width: charText.implicitWidth
                            height: charText.implicitHeight

                            transform: [
                                Translate { y: -liftProgress * 2.0 },
                                Scale {
                                    xScale: wordRoot.waveScale
                                    yScale: wordRoot.waveScale
                                    origin.x: charItem.width / 2
                                    origin.y: charItem.height / 2
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

                // Layer 2: Fast Zero-Lag Phosphor Glow on Singing Word (replaces heavy Gaussian blur)
                Text {
                    anchors.centerIn: charRow
                    text: wData.text || ""
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize
                    font.weight: root.fontWeight
                    color: Qt.rgba(1.0, 1.0, 1.0, 0.40 * wordRoot.flareGate * Math.sin(Math.PI * wordRoot.smoothProg))
                    scale: 1.06
                    visible: wordRoot.isSinging && wordRoot.flareGate > 0.05
                    z: -1
                }
            }
        }
    }
}
