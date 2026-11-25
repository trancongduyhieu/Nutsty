import QtQuick
import "."

// One playlist in the Spotify sync picker, after Mochy's style picker: the cover is the card, its name sits
// bottom-left over a dark fade, and the chosen one gets a 2px accent outline and a tick. Unchosen covers dim.
// Own file, not an inline component: Quickshell hot reload cannot resolve an inline component added later.
Item {
    id: pick
    property string title: ""
    property string subtitle: ""
    property url cover: ""
    // Liked Songs has no cover on Spotify: an accent square with a heart stands in
    property bool likedArt: false
    property bool checked: false
    property color accentColor: Theme.accent
    signal toggled()

    implicitHeight: width

    Item {
        id: art
        anchors.fill: parent
        scale: pickMouse.pressed ? 0.97 : 1.0
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        RoundedImage {
            anchors.fill: parent
            visible: !pick.likedArt
            radius: 12
            source: pick.cover
            sourceSize: Qt.size(320, 320)
            initialsText: pick.title
            fallbackIcon: "../assets/icons/media-playlist-consecutive-symbolic.svg"
            fallbackIconColor: pick.accentColor
            fallbackIconSize: 28
        }

        Rectangle {
            anchors.fill: parent
            visible: pick.likedArt
            radius: 12
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.lighter(pick.accentColor, 1.35) }
                GradientStop { position: 1.0; color: Qt.darker(pick.accentColor, 1.9) }
            }
            AppIcon {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -12
                source: "../assets/icons/emblem-favorite-symbolic.svg"
                iconSize: Math.round(parent.width * 0.26)
                color: "#ffffff"
            }
        }

        // Fade under the name so it reads on any cover; unchosen covers darken further
        Rectangle {
            anchors.fill: parent
            radius: 12
            gradient: Gradient {
                GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, pick.checked ? 0.0 : 0.30) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, pick.checked ? 0.72 : 0.82) }
            }
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 10
            spacing: 1

            Text {
                width: parent.width
                text: pick.title
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.Bold
                color: "#ffffff"
                opacity: pick.checked ? 1.0 : 0.75
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: pick.subtitle
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Qt.rgba(1, 1, 1, 0.65)
                elide: Text.ElideRight
            }
        }

        // 2px outline: accent when chosen, faint white on hover
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: "transparent"
            border.width: pick.checked ? 2 : 1
            border.color: pick.checked ? pick.accentColor
                                       : Qt.rgba(1, 1, 1, pickMouse.containsMouse ? 0.30 : 0.08)
            Behavior on border.color { ColorAnimation { duration: 160 } }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            width: 22
            height: 22
            radius: 11
            color: pick.accentColor
            opacity: pick.checked ? 1 : 0
            scale: pick.checked ? 1 : 0.5
            Behavior on opacity { NumberAnimation { duration: 150 } }
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

            AppIcon {
                anchors.centerIn: parent
                source: "../assets/icons/emblem-ok-symbolic.svg"
                iconSize: 12
                color: "#ffffff"
            }
        }
    }

    MouseArea {
        id: pickMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: pick.toggled()
    }
}
