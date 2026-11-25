import QtQuick
import QtQuick.Layouts
import "."

// Sub-card inside a SpotifySettingCard (Mochy's "Làm mờ lũy tiến" row): one option on a 12px tinted card,
// 20 - 8 = 12 concentric with its parent. Text on the left, a control (trailing) on the right.
// Own file, not an inline component: Quickshell hot reload cannot resolve an inline component added later.
Rectangle {
    id: sub
    property string title: ""
    property string description: ""
    property bool danger: false
    property bool clickable: false
    property color accentColor: Theme.accent
    default property alias trailing: trailingSlot.data
    signal clicked()

    readonly property color tone: danger ? Qt.rgba(244 / 255, 63 / 255, 94 / 255, 1.0) : accentColor

    Layout.fillWidth: true
    implicitHeight: Math.max(48, textCol.implicitHeight + 20)
    radius: 12
    color: Qt.rgba(tone.r, tone.g, tone.b, subMouse.containsMouse ? 0.20 : 0.12)
    border.width: 1
    border.color: Qt.rgba(tone.r, tone.g, tone.b, danger ? 0.30 : 0.14)
    Behavior on color { ColorAnimation { duration: 140 } }

    MouseArea {
        id: subMouse
        anchors.fill: parent
        enabled: sub.clickable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: sub.clicked()
    }

    Column {
        id: textCol
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.right: trailingSlot.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            width: parent.width
            text: sub.title
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: sub.danger ? "#fda4af" : Theme.textPrimary
            wrapMode: Text.WordWrap
        }

        Text {
            width: parent.width
            visible: sub.description !== ""
            text: sub.description
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.textSecondary
            elide: Text.ElideRight
        }
    }

    Item {
        id: trailingSlot
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
}
