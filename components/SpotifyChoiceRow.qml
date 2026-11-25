import QtQuick
import "."

// One checkable row of the Spotify sync playlist picker (SpotifySyncSection.qml).
// Own file, not an inline component: Quickshell hot reload cannot resolve an inline component added later.
Rectangle {
    id: row
    property string title: ""
    property string hint: ""
    property bool checked: false
    property color accentColor: Theme.accent
    signal toggled()

    implicitHeight: Math.max(34, textCol.implicitHeight + 12)
    radius: 8
    color: rowMouse.containsMouse ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.14) : "transparent"
    border.color: rowMouse.containsMouse ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.25) : "transparent"
    border.width: 1
    Behavior on color { ColorAnimation { duration: 120 } }

    Rectangle {
        id: box
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        height: 18
        radius: 5
        color: row.checked ? row.accentColor : Qt.rgba(row.accentColor.r, row.accentColor.g, row.accentColor.b, 0.12)
        border.color: Qt.rgba(row.accentColor.r, row.accentColor.g, row.accentColor.b, row.checked ? 0.6 : 0.35)
        border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }

        AppIcon {
            anchors.centerIn: parent
            source: "../assets/icons/emblem-ok-symbolic.svg"
            iconSize: 12
            color: "#ffffff"
            opacity: row.checked ? 1 : 0
        }
    }

    Column {
        id: textCol
        anchors.left: box.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            width: parent.width
            text: row.title
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.textPrimary
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            visible: row.hint !== ""
            text: row.hint
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: Theme.textSecondary
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.toggled()
    }
}
