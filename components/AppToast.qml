import QtQuick
import QtQuick.Effects
import "."
import "notification_kinds.js" as Kinds

// Top-centre toast: an icon for the kind of event, then the message (up to two lines).
// Errors take the muted rose; everything else follows the accent.
Item {
    id: root

    property string message: ""
    property string kind: "info"
    property bool shown: false
    property color accentColor: Theme.accent

    signal holdChanged(bool hold)   // hovering keeps it on screen
    signal dismissed()

    readonly property color tone: Kinds.isError(kind) ? Qt.rgba(244 / 255, 63 / 255, 94 / 255, 1) : accentColor

    y: shown ? 20 : -height - 12
    opacity: shown ? 1.0 : 0.0
    visible: opacity > 0.01
    width: Math.min(520, (parent ? parent.width : 560) - 48, label.implicitWidth + 76)
    height: Math.max(48, label.height + 24)

    Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 180 } }

    Accessible.role: Accessible.AlertMessage
    Accessible.name: message

    RectangularShadow {
        anchors.fill: card
        offset.y: 8
        blur: 24
        radius: card.radius
        color: Qt.rgba(0, 0, 0, 0.45)
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Math.min(24, height / 2)
        color: Qt.rgba(0.07, 0.07, 0.09, 0.96)
        border.width: 1
        border.color: Qt.rgba(root.tone.r, root.tone.g, root.tone.b, 0.35)

        Rectangle {
            id: badge
            width: 30
            height: 30
            radius: 15
            anchors.left: parent.left
            anchors.leftMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.rgba(root.tone.r, root.tone.g, root.tone.b, 0.20)
            AppIcon {
                anchors.centerIn: parent
                source: Kinds.icon(root.kind)
                iconSize: 15
                color: Qt.lighter(root.tone, 1.3)
            }
        }

        Text {
            id: label
            anchors.left: badge.right
            anchors.leftMargin: 11
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            text: root.message
            color: "#ffffff"
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.Medium
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onContainsMouseChanged: root.holdChanged(containsMouse)
        onClicked: root.dismissed()
    }
}
