import QtQuick
import "."

// One row of a SpotifySyncGroup, after Mochy's SettingsItemRow: 32px round icon or cover on the left,
// title over a one-line description, and whatever control is put inside it (switch, checkbox, button) on the right.
// Own file, not an inline component: Quickshell hot reload cannot resolve an inline component added later.
Item {
    id: row
    width: parent ? parent.width : 0
    implicitHeight: Math.max(60, textCol.implicitHeight + 28)
    height: visible ? implicitHeight : 0

    property string title: ""
    property string description: ""
    // A symbolic icon in an accent-tinted circle, or a cover cropped round, or the Liked Songs heart
    property url iconSource: ""
    property url cover: ""
    property bool coverMode: false
    property bool likedArt: false
    property bool danger: false
    // Rows with an action respond to the pointer; plain rows do not
    property bool clickable: true
    property bool active: true
    property color accentColor: Theme.accent
    default property alias trailing: trailingSlot.data
    signal clicked()

    readonly property color tone: danger ? Qt.rgba(244 / 255, 63 / 255, 94 / 255, 1.0) : accentColor

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        radius: 18
        color: Qt.rgba(row.tone.r, row.tone.g, row.tone.b, rowMouse.pressed ? 0.14 : 0.08)
        opacity: row.clickable && row.active && rowMouse.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        enabled: row.clickable && row.active
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.clicked()
    }

    Item {
        id: art
        x: 20
        anchors.verticalCenter: parent.verticalCenter
        width: 32
        height: 32
        opacity: row.active ? 1 : 0.45

        Rectangle {
            anchors.fill: parent
            visible: !row.coverMode && !row.likedArt
            radius: 16
            color: Qt.rgba(row.tone.r, row.tone.g, row.tone.b, 0.18)

            AppIcon {
                anchors.centerIn: parent
                source: row.iconSource
                iconSize: 16
                color: Qt.lighter(row.tone, 1.3)
            }
        }

        RoundedImage {
            anchors.fill: parent
            visible: row.coverMode && !row.likedArt
            radius: 16
            source: row.cover
            sourceSize: Qt.size(64, 64)
            initialsText: row.title
            fallbackIcon: "../assets/icons/media-playlist-consecutive-symbolic.svg"
            fallbackIconColor: row.accentColor
            fallbackIconSize: 14
            borderColor: Qt.rgba(1, 1, 1, 0.12)
            borderWidth: 1
        }

        Rectangle {
            anchors.fill: parent
            visible: row.likedArt
            radius: 16
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.lighter(row.accentColor, 1.35) }
                GradientStop { position: 1.0; color: Qt.darker(row.accentColor, 1.9) }
            }

            AppIcon {
                anchors.centerIn: parent
                source: "../assets/icons/emblem-favorite-symbolic.svg"
                iconSize: 14
                color: "#ffffff"
            }
        }
    }

    Column {
        id: textCol
        anchors.left: art.right
        anchors.leftMargin: 14
        anchors.right: trailingSlot.left
        anchors.rightMargin: trailingSlot.width > 0 ? 14 : 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        opacity: row.active ? 1 : 0.45

        Text {
            width: parent.width
            text: row.title
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: row.danger ? "#fda4af" : Theme.textPrimary
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            visible: row.description !== ""
            text: row.description
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.textSecondary
            elide: Text.ElideRight
        }
    }

    Item {
        id: trailingSlot
        anchors.right: parent.right
        anchors.rightMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
}
