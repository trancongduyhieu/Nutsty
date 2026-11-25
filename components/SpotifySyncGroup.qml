import QtQuick
import QtQuick.Layouts
import "."

// Grouped settings card of the Spotify sync section, after Mochy's SettingsGroup (Grouped style):
// an accent label above, one rounded glass card holding SpotifySyncRow items, no dividers between them.
// Own file, not an inline component: Quickshell hot reload cannot resolve an inline component added later.
ColumnLayout {
    id: group
    spacing: 8

    property string title: ""
    property color accentColor: Theme.accent
    default property alias rows: rowsCol.data

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        visible: group.title !== ""
        text: group.title
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: Qt.lighter(group.accentColor, 1.15)
        elide: Text.ElideRight
    }

    // Panel radius 24; rows inside sit 6px in, so their hover fill uses 24 - 6 = 18
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: rowsCol.implicitHeight + 12
        radius: 24
        color: Qt.rgba(1, 1, 1, 0.04)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.07)

        Column {
            id: rowsCol
            x: 0
            y: 6
            width: parent.width
        }
    }
}
