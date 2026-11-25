import QtQuick
import QtQuick.Effects
import "."

// One playlist of the Spotify sync picker (SpotifySyncSection.qml): the cover is the control.
// Not chosen = cover drained of colour and dimmed; chosen = full colour, accent hairline, check in the corner.
// Own file, not an inline component: Quickshell hot reload cannot resolve an inline component added later.
Item {
    id: tile
    property string title: ""
    property string subtitle: ""
    property url cover: ""
    // Liked Songs has no cover on Spotify: an accent square with a heart stands in
    property bool likedTile: false
    property bool checked: false
    property color accentColor: Theme.accent
    signal toggled()

    readonly property color a: accentColor
    implicitHeight: width + 8 + titleText.implicitHeight + 2 + subText.implicitHeight

    Item {
        id: art
        width: tile.width
        height: tile.width
        scale: tileMouse.pressed ? 0.97 : (tileMouse.containsMouse ? 1.025 : 1.0)
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Item {
            id: artContent
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                saturation: tile.checked ? 0.0 : -1.0
                brightness: tile.checked ? 0.0 : (tileMouse.containsMouse ? -0.18 : -0.32)
                Behavior on saturation { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on brightness { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            }

            RoundedImage {
                anchors.fill: parent
                visible: !tile.likedTile
                radius: 12
                source: tile.cover
                sourceSize: Qt.size(320, 320)
                initialsText: tile.title
                fallbackIcon: "../assets/icons/media-playlist-consecutive-symbolic.svg"
                fallbackIconColor: tile.accentColor
                fallbackIconSize: 32
            }

            Rectangle {
                anchors.fill: parent
                visible: tile.likedTile
                radius: 12
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.lighter(tile.accentColor, 1.35) }
                    GradientStop { position: 1.0; color: Qt.darker(tile.accentColor, 1.9) }
                }

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/emblem-favorite-symbolic.svg"
                    iconSize: Math.round(parent.width * 0.32)
                    color: "#ffffff"
                }
            }
        }

        // Hairline on the cover edge: white 7% idle, 18% hover, accent 45% chosen
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: "transparent"
            border.width: 1
            border.color: tile.checked ? Qt.rgba(tile.a.r, tile.a.g, tile.a.b, 0.45)
                                       : Qt.rgba(1, 1, 1, tileMouse.containsMouse ? 0.18 : 0.07)
            Behavior on border.color { ColorAnimation { duration: 180 } }
        }

        // Check in the corner, inset 8px: concentric with the 12px cover (12 - 8 = 4 <= its own radius)
        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            width: 24
            height: 24
            radius: 12
            color: tile.checked ? tile.accentColor : Qt.rgba(0, 0, 0, 0.35)
            border.width: tile.checked ? 0 : 1.5
            border.color: Qt.rgba(1, 1, 1, tileMouse.containsMouse ? 0.75 : 0.5)
            Behavior on color { ColorAnimation { duration: 180 } }

            AppIcon {
                anchors.centerIn: parent
                source: "../assets/icons/emblem-ok-symbolic.svg"
                iconSize: 13
                color: "#ffffff"
                opacity: tile.checked ? 1 : 0
                scale: tile.checked ? 1 : 0.5
                Behavior on opacity { NumberAnimation { duration: 160 } }
                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
            }
        }
    }

    Text {
        id: titleText
        anchors.top: art.bottom
        anchors.topMargin: 8
        width: tile.width
        text: tile.title
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.weight: Font.DemiBold
        color: tile.checked ? Theme.textPrimary : Theme.textSecondary
        elide: Text.ElideRight
        Behavior on color { ColorAnimation { duration: 180 } }
    }

    Text {
        id: subText
        anchors.top: titleText.bottom
        anchors.topMargin: 2
        width: tile.width
        text: tile.subtitle
        font.family: Theme.fontFamily
        font.pixelSize: 11
        color: Theme.textMuted
        elide: Text.ElideRight
    }

    MouseArea {
        id: tileMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.toggled()
    }
}
