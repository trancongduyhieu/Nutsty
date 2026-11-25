import QtQuick
import "."

// Small pill button of the Lossless settings section. Own file, not an inline component:
// Quickshell hot reload cannot resolve an inline component added to a file it already loaded.
Rectangle {
    id: sb
    property string label: ""
    property bool danger: false
    property bool primary: false
    property color accentColor: Theme.accent
    property color roseColor: Qt.rgba(244 / 255, 63 / 255, 94 / 255, 1.0)
    signal clicked()
    readonly property color tone: danger ? roseColor : accentColor
    height: 28
    width: sbText.implicitWidth + 24
    radius: 8
    color: primary ? (sbMouse.containsMouse ? Qt.lighter(tone, 1.15) : tone)
                   : Qt.rgba(tone.r, tone.g, tone.b, sbMouse.containsMouse ? 0.22 : 0.12)
    border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.35)
    border.width: 1
    Text {
        id: sbText
        anchors.centerIn: parent
        text: sb.label
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.bold: true
        // white on a light accent (pale gold) washes out: dark text on a filled light pill
        color: sb.primary && (0.299 * sb.tone.r + 0.587 * sb.tone.g + 0.114 * sb.tone.b) > 0.6
               ? Qt.rgba(0, 0, 0, 0.85) : "#ffffff"
    }
    MouseArea { id: sbMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sb.clicked() }
}
