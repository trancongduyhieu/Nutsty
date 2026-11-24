import QtQuick
import "."

// Close mark for the Big type look: no button, just two thin accent strokes. Hovered, they turn
// a quarter, passing through a plus and crossing again with a springy settle.
Item {
    id: root

    property color accentColor: Theme.accent
    signal clicked()

    width: 32
    height: 32
    scale: closeMa.pressed ? 0.86 : 1.0
    Behavior on scale { NumberAnimation { duration: 120 } }

    HoverHandler { id: hover }

    Item {
        anchors.centerIn: parent
        width: 24
        height: 24
        rotation: hover.hovered ? 90 : 0
        Behavior on rotation { NumberAnimation { duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }

        Repeater {
            model: [45, -45]
            delegate: Rectangle {
                required property real modelData
                anchors.centerIn: parent
                width: hover.hovered ? 26 : 22
                height: hover.hovered ? 2.6 : 2
                radius: height / 2
                antialiasing: true
                rotation: modelData
                color: root.accentColor
                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }
        }
    }

    MouseArea {
        id: closeMa
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
