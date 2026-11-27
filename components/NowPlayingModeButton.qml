import QtQuick
import QtQuick.Controls.Basic
import "."

// Icon segment of the Now Playing mode switcher (artwork / lyrics / up next).
// Swiftify-like: the active segment is a solid white pill with a dark glyph.
Rectangle {
    id: mb
    property string icon: ""
    property string tip: ""
    property bool active: false
    property color accent: "#ffffff"
    // Small dot in the top-right corner (e.g. a running sleep timer)
    property bool badge: false
    // compact: the notch size (26px row, like liner's notch buttons)
    property bool compact: false
    signal clicked()
    width: compact ? 34 : 52; height: compact ? 26 : 36; radius: height / 2
    color: active ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(1, 1, 1, mbH.hovered ? 0.10 : 0.0)
    Behavior on color { ColorAnimation { duration: 160 } }
    HoverHandler { id: mbH }
    ToolTip.visible: mbH.hovered
    ToolTip.text: mb.tip
    ToolTip.delay: 400
    AppIcon {
        anchors.centerIn: parent
        source: mb.icon
        iconSize: mb.compact ? 16 : 20
        color: mb.active ? "#121214" : "#ffffff"
        opacity: (mb.active || mbH.hovered) ? 1.0 : 0.75
        scale: mbMouse.pressed ? 0.88 : 1.0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 110 } }
    }
    Rectangle {
        visible: mb.badge
        width: 6; height: 6; radius: 3
        color: mb.active ? "#121214" : "#ffffff"
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: mb.compact ? 4 : 7
        anchors.rightMargin: mb.compact ? 8 : 13
    }
    MouseArea { id: mbMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mb.clicked() }
}
