import QtQuick
import "."

// One selectable playlist tile of the Spotify sync picker (SpotifySyncSection.qml): cover, title, owner line.
// Selected = accent tint + accent hairline + check on the right. Own file, not an inline component:
// Quickshell hot reload cannot resolve an inline component added later.
Rectangle {
    id: row
    property string title: ""
    property string subtitle: ""
    property url cover: ""
    // Liked Songs has no cover on Spotify: draw an accent square with a heart instead
    property bool likedTile: false
    property bool checked: false
    property color accentColor: Theme.accent
    signal toggled()

    readonly property color a: accentColor
    implicitHeight: 60
    radius: 12
    color: row.checked ? Qt.rgba(a.r, a.g, a.b, rowMouse.containsMouse ? 0.22 : 0.12)
                       : (rowMouse.containsMouse ? Qt.rgba(a.r, a.g, a.b, 0.08) : "transparent")
    border.width: 1
    border.color: row.checked ? Qt.rgba(a.r, a.g, a.b, 0.45)
                              : (rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.07))
    scale: rowMouse.pressed ? 0.98 : 1.0
    Behavior on color { ColorAnimation { duration: 140 } }
    Behavior on border.color { ColorAnimation { duration: 140 } }
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    // Cover 44px inset 8px in a 12px tile: concentric radius 12 - 8 = 4
    Item {
        id: coverBox
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 44
        height: 44

        RoundedImage {
            anchors.fill: parent
            visible: !row.likedTile
            radius: 4
            source: row.cover
            sourceSize: Qt.size(88, 88)
            initialsText: row.title
            fallbackIcon: "../assets/icons/media-playlist-consecutive-symbolic.svg"
            fallbackIconColor: row.accentColor
            borderColor: Qt.rgba(1, 1, 1, 0.07)
            borderWidth: 1
        }

        Rectangle {
            anchors.fill: parent
            visible: row.likedTile
            radius: 4
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.lighter(row.accentColor, 1.25) }
                GradientStop { position: 1.0; color: Qt.darker(row.accentColor, 1.6) }
            }
            border.color: Qt.rgba(1, 1, 1, 0.10)
            border.width: 1

            AppIcon {
                anchors.centerIn: parent
                source: "../assets/icons/emblem-favorite-symbolic.svg"
                iconSize: 20
                color: "#ffffff"
            }
        }
    }

    Column {
        anchors.left: coverBox.right
        anchors.leftMargin: 12
        anchors.right: check.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        Text {
            width: parent.width
            text: row.title
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: Theme.textPrimary
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            visible: row.subtitle !== ""
            text: row.subtitle
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.textSecondary
            elide: Text.ElideRight
        }
    }

    // Selection mark: hollow ring idle, filled accent with a tick when chosen
    Rectangle {
        id: check
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: 20
        height: 20
        radius: 10
        color: row.checked ? row.accentColor : "transparent"
        border.width: row.checked ? 0 : 1.5
        border.color: Qt.rgba(1, 1, 1, rowMouse.containsMouse ? 0.45 : 0.28)
        Behavior on color { ColorAnimation { duration: 140 } }

        AppIcon {
            anchors.centerIn: parent
            source: "../assets/icons/emblem-ok-symbolic.svg"
            iconSize: 12
            color: "#ffffff"
            opacity: row.checked ? 1 : 0
            scale: row.checked ? 1 : 0.6
            Behavior on opacity { NumberAnimation { duration: 140 } }
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
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
