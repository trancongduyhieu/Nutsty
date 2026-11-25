import QtQuick
import "."

// The switch of a Spotify setting card: accent track when on, accent-tinted when off (never grey).
// Own file, not an inline component: Quickshell hot reload cannot resolve an inline component added later.
Rectangle {
    id: sw
    property bool checked: false
    property color accentColor: Theme.accent
    signal toggled()

    width: 44
    height: 24
    radius: 12
    color: checked ? accentColor : Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.18)
    border.color: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.35)
    border.width: 1
    Behavior on color { ColorAnimation { duration: 150 } }

    Rectangle {
        width: 18
        height: 18
        radius: 9
        color: "#ffffff"
        anchors.verticalCenter: parent.verticalCenter
        x: sw.checked ? parent.width - width - 3 : 3
        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggled()
    }
}
