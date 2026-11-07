import QtQuick
import "."

// Backing Vocal Line Engine — 1:1 Mochy-Music & Apple Music
// Spec source: Mochy-Music/LyricsGlowLine.kt (rememberBackingExpand, smoothstep, BackingVocalLine)
//   • Expand: Hermite smoothstep 3x^2 - 2x^3
//   • BackingLeadInSec = 0.35s (opens 350ms before first word)
//   • BackingTailSec = 0.6s (folds away 600ms after last word)
//   • Sliding reveal: content slides down (height - fullHeight) while expanding
//   • Typography: BackingVocalFontSize = 21px, bold, italic
//   • Progressive sweep: AppleMusicWordFlow when words have timestamps

Item {
    id: root

    property string text: ""
    property var words: []
    property real currentTime: 0.0
    property bool lineIsActive: false
    property bool slide: true
    property bool isAnsweringVoice: false
    property bool isEnsembleVoice: false
    property color accentColor: "#ffffff"

    readonly property var validWords: root.words || []
    readonly property bool hasWords: validWords.length > 0
    readonly property real firstStart: hasWords ? (validWords[0].start || 0.0) : 0.0
    readonly property real lastEnd: hasWords ? (validWords[validWords.length - 1].end || 0.0) : 0.0

    // 1:1 Mochy-Music smoothstep(t): Hermite cubic curve C1 continuous
    function smoothstep(t) {
        var x = Math.min(1.0, Math.max(0.0, t));
        return x * x * (3.0 - 2.0 * x);
    }

    // 1:1 Mochy-Music rememberBackingExpand:
    // Blooms open 350ms before singing using Hermite smoothstep 3x^2 - 2x^3.
    // Folds away 600ms after last word ends.
    readonly property real expand: {
        if (!hasWords) {
            return root.lineIsActive ? 1.0 : 0.0;
        }
        var sec = root.currentTime;
        if (sec < root.firstStart - 0.35) {
            return 0.0;
        } else if (sec < root.firstStart) {
            return root.smoothstep((sec - (root.firstStart - 0.35)) / 0.35);
        } else if (sec <= root.lastEnd) {
            return 1.0;
        } else {
            return Math.max(0.0, 1.0 - root.smoothstep((sec - root.lastEnd) / 0.6));
        }
    }

    // 60 FPS continuous smooth animation interpolator: converts discrete audio timer ticks into buttery glide
    property real smoothExpand: expand
    Behavior on smoothExpand {
        NumberAnimation {
            duration: 220
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.42, 0.0, 0.16, 1.0]
        }
    }

    implicitWidth: parent ? parent.width : 400
    implicitHeight: Math.round(contentBox.implicitHeight * root.smoothExpand)
    height: implicitHeight
    clip: root.smoothExpand < 0.999
    opacity: Math.min(1.0, Math.max(0.0, root.smoothExpand))
    visible: root.smoothExpand > 0.001

    Item {
        id: contentBox
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: Math.max(26, (flowLoader.visible && flowLoader.item)
            ? flowLoader.item.implicitHeight
            : staticBackingTxt.implicitHeight)
        // 1:1 Mochy-Music sliding reveal: placeable.place(0, if (slide) height - placeable.height else 0)
        y: root.slide ? (root.height - contentBox.implicitHeight) : 0

        // 1. Timed backing vocal with progressive character sweep
        Loader {
            id: flowLoader
            active: root.hasWords
            visible: active

            anchors.left: parent.left
            anchors.right: parent.right
            sourceComponent: Component {
                AppleMusicWordFlow {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    words: root.validWords
                    currentTime: root.currentTime
                    fontSize: 21
                    accentColor: "#ffffff"
                    isAnsweringVoice: root.isAnsweringVoice
                    isEnsembleVoice: root.isEnsembleVoice
                }
            }
        }

        // 2. Untimed fallback plain backing vocal (strictly when no word timestamps exist)
        Text {
            id: staticBackingTxt
            visible: !root.hasWords
            anchors.left: (!root.isAnsweringVoice && !root.isEnsembleVoice) ? parent.left : undefined
            anchors.right: root.isAnsweringVoice ? parent.right : undefined
            anchors.horizontalCenter: root.isEnsembleVoice ? parent.horizontalCenter : undefined
            width: Math.min(parent.width * 0.82, implicitWidth)
            horizontalAlignment: root.isAnsweringVoice ? Text.AlignRight : (root.isEnsembleVoice ? Text.AlignHCenter : Text.AlignLeft)
            textFormat: Text.PlainText
            text: root.text
            font.family: Theme.fontFamily
            font.pixelSize: 21
            font.weight: Font.Bold
            font.italic: true
            color: root.lineIsActive ? "#ffffff" : Qt.rgba(255, 255, 255, 0.58)
            wrapMode: Text.Wrap
            lineHeight: 1.24
        }
    }
}
