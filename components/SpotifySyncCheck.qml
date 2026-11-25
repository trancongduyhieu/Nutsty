import QtQuick
import "."

// Checkbox at the end of a SpotifySyncRow in the playlist picker: accent fill and a white tick when checked.
// It only shows state; the row it sits in takes the click.
Rectangle {
    id: box
    property bool checked: false
    property color accentColor: Theme.accent

    width: 20
    height: 20
    radius: 6
    color: checked ? accentColor : "transparent"
    border.width: checked ? 0 : 1.5
    border.color: Qt.rgba(1, 1, 1, 0.35)
    Behavior on color { ColorAnimation { duration: 150 } }

    AppIcon {
        anchors.centerIn: parent
        source: "../assets/icons/emblem-ok-symbolic.svg"
        iconSize: 12
        color: "#ffffff"
        opacity: box.checked ? 1 : 0
        scale: box.checked ? 1 : 0.5
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
    }
}
