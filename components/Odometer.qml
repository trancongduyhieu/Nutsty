import QtQuick
import "."

// Rolling-digit counter. Each digit is a reel: it rolls through 0..9 to land on its value, the higher
// places a touch later. While `spinning` the reels run freely (a slot machine waiting for a result) and
// settle onto `text` as soon as spinning stops. Non-digits (".", ",", "%") are drawn as plain text.
Row {
    id: odo
    property string text: "0"
    property int pixelSize: 52
    property int gen: 0
    property color color: Theme.textPrimary
    property bool liteMode: (typeof win !== "undefined") ? !!win.liteMode : false
    property bool spinning: false
    // Reels travel downward when true, upward when false
    property bool down: false
    property real roll: 1
    property real spin: 0
    // Set when the reels stop spinning: they glide on from where they were instead of starting another full lap
    property bool fromSpin: false
    property real spinAtStop: 0

    function restartRoll() { roll = 0; rollAnim.restart(); }
    onGenChanged: restartRoll()
    onTextChanged: if (!spinning) { fromSpin = false; restartRoll(); }
    onSpinningChanged: {
        if (spinning) { fromSpin = false; return; }
        fromSpin = true;
        spinAtStop = spin;
        restartRoll();
    }
    Component.onCompleted: if (!spinning) restartRoll()

    NumberAnimation {
        id: rollAnim
        target: odo; property: "roll"; from: 0; to: 1
        duration: odo.liteMode ? 1 : (odo.fromSpin ? 900 : 1400)
        easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
    }
    // A whole number of laps per loop, so the wrap is invisible
    NumberAnimation on spin {
        from: 0; to: 10; duration: 700
        loops: Animation.Infinite
        running: odo.spinning && !odo.liteMode && odo.visible
    }

    Repeater {
        model: odo.text.split("")
        delegate: Item {
            id: digit
            required property string modelData
            required property int index
            readonly property bool isDigit: /[0-9]/.test(modelData)
            readonly property real lag: (odo.text.length - 1 - index) * 0.08
            readonly property real t: Math.max(0, Math.min(1, (odo.roll - lag) / (1 - lag)))
            readonly property real spinPos: (odo.spin * (1 + index % 3)) % 10
            readonly property real digitValue: isDigit ? parseInt(modelData) : 0
            // Where this reel was when spinning stopped, and the shortest way down to its digit (never more than one lap)
            readonly property real idxStop: 10 - (odo.spinAtStop * (1 + index % 3)) % 10
            readonly property real idxFrom: idxStop < digitValue ? idxStop + 10 : idxStop
            width: probe.implicitWidth
            height: probe.implicitHeight
            clip: true
            Text {
                id: probe
                visible: !digit.isDigit
                text: digit.isDigit ? "0" : digit.modelData
                color: odo.color
                font.family: Theme.fontFamily
                font.pixelSize: odo.pixelSize
                font.weight: Font.Bold
                font.letterSpacing: -odo.pixelSize * 0.045
                font.features: { "tnum": 1 }
            }
            Column {
                visible: digit.isDigit
                opacity: odo.spinning ? 0.7 : 1
                // a full lap plus the digit, so even a 0 rolls
                y: odo.spinning
                   ? (odo.down ? -(10 - digit.spinPos) : -digit.spinPos) * digit.height
                   : (odo.fromSpin ? -(digit.idxFrom + (digit.digitValue - digit.idxFrom) * digit.t)
                                   : (odo.down ? -(digit.digitValue + 10 * (1 - digit.t)) : -(10 + digit.digitValue) * digit.t)) * digit.height
                Repeater {
                    model: 20
                    Text {
                        required property int index
                        height: digit.height
                        text: index % 10
                        color: odo.color
                        font: probe.font
                    }
                }
            }
        }
    }
}
