import QtQuick
import QtQuick.Controls.Basic
import "."

// SimpMusic-style tab bar at the bottom of the Mochy side panel: Lyrics, YouTube comments, Up Next.
// One capsule holds the three buttons and a highlight slides to the active one. The capsule is a
// tinted fill, not more glass, because it already sits on the panel's material.
Item {
    id: root

    property string activeTab: "lyrics"
    property color accentColor: "#ffffff"
    // Concentric with the panel: panel radius minus the inset the host places this row at
    property real radius: 16

    signal lyricsClicked()
    signal commentsClicked()
    signal queueClicked()

    readonly property var tabs: ["lyrics", "comments", "queue"]
    readonly property int activeIndex: Math.max(0, tabs.indexOf(activeTab))
    readonly property real segment: width / 3
    readonly property real highlightInset: 5

    function activate(i) {
        if (i === 0) root.lyricsClicked();
        else if (i === 1) root.commentsClicked();
        else root.queueClicked();
    }

    implicitHeight: 50
    implicitWidth: 240

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
        border.width: 1
        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
    }

    Rectangle {
        id: highlight
        y: root.highlightInset
        height: parent.height - 2 * root.highlightInset
        width: root.segment - 2 * root.highlightInset
        x: root.activeIndex * root.segment + root.highlightInset
        radius: root.radius - root.highlightInset
        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.26)
        Behavior on x { SpringAnimation { spring: 4.5; damping: 0.38; epsilon: 0.25 } }
    }

    Row {
        anchors.fill: parent

        Repeater {
            model: [
                { icon: "../assets/icons/material/ms-lyrics-fill.svg", tip: I18n.tr("Lời bài hát", "Lyrics") },
                { icon: "../assets/icons/material/ms-forum.svg", tip: I18n.tr("Bình luận", "Comments") },
                { icon: "../assets/icons/queue-music-symbolic.svg", tip: I18n.tr("Phát tiếp theo", "Playing Next") }
            ]

            delegate: Item {
                id: slot
                required property var modelData
                required property int index
                width: root.segment
                height: root.height

                // The whole segment is the hit target, not just the icon
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activate(slot.index)
                }

                NowPlayingCtlButton {
                    anchors.centerIn: parent
                    size: 40
                    plain: true
                    toggle: true
                    icon: slot.modelData.icon
                    on: root.activeIndex === slot.index
                    onClicked: root.activate(slot.index)
                    ToolTip.visible: slotH.hovered
                    ToolTip.text: slot.modelData.tip
                    ToolTip.delay: 350
                    HoverHandler { id: slotH }
                }
            }
        }
    }
}
