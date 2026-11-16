import QtQuick
import QtQuick.Controls.Basic
import "."

// SimpMusic-style action row under the Now Playing controls:
// Lyrics | [ Listen Along · Listeners · Comment ] | Up Next
Item {
    id: root

    property string activeTab: "artwork"
    property color accentColor: "#ffffff"
    property var listeningAlongFriend: null
    property var activeCoListenersDetails: []

    readonly property bool isListener: listeningAlongFriend !== null && listeningAlongFriend !== undefined
    readonly property int listenerCount: activeCoListenersDetails ? activeCoListenersDetails.length : 0
    readonly property bool isCoListening: isListener || listenerCount > 0
    property bool chatOpen: false

    signal lyricsClicked()
    signal queueClicked()
    signal listenAlongClicked()
    signal listenersClicked(real globalX, real globalY)
    signal leaveListeningAlongClicked()
    signal sendChatMessage(string text)

    implicitHeight: 44
    // lyrics + gap + pill + gap + queue, so the side buttons never touch the pill
    implicitWidth: pill.width + 2 * (lyricsBtn.width + 16)
    onIsCoListeningChanged: if (!isCoListening) chatOpen = false

    NowPlayingCtlButton {
        id: lyricsBtn
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        size: 40
        icon: "../assets/icons/material/ms-lyrics-fill.svg"
        toggle: true
        on: root.activeTab === "lyrics"
        onClicked: root.lyricsClicked()
        ToolTip.visible: lyricsBtnH.hovered
        ToolTip.text: I18n.tr("Lời bài hát", "Lyrics")
        ToolTip.delay: 350
        HoverHandler { id: lyricsBtnH }
    }

    NowPlayingCtlButton {
        id: queueBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        size: 40
        icon: "../assets/icons/queue-music-symbolic.svg"
        toggle: true
        on: root.activeTab === "up_next"
        onClicked: root.queueClicked()
        ToolTip.visible: queueBtnH.hovered
        ToolTip.text: I18n.tr("Phát tiếp theo", "Playing Next")
        ToolTip.delay: 350
        HoverHandler { id: queueBtnH }
    }

    // Frosted pill, same family as the mode switcher at the top-right of Now Playing
    Rectangle {
        id: pill
        anchors.centerIn: parent
        width: pillRow.implicitWidth + 8
        height: 44
        radius: 22
        color: Qt.rgba(1, 1, 1, 0.10)
        border.color: Qt.rgba(1, 1, 1, 0.14)
        border.width: 1

        Row {
            id: pillRow
            anchors.centerIn: parent

            component PillButton: Item {
                id: pb
                property string icon: ""
                property string tip: ""
                property bool enabledState: true
                property bool active: false
                property color tint: "#ffffff"
                property string badge: ""
                signal clicked()
                width: 52; height: 36

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: pb.active ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.28)
                        : Qt.rgba(1, 1, 1, pb.enabledState && pbMouse.pressed ? 0.16 : (pb.enabledState && pbH.hovered ? 0.09 : 0.0))
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
                HoverHandler { id: pbH }
                AppIcon {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: pb.badge !== "" ? -6 : 0
                    source: pb.icon
                    iconSize: 22
                    color: pb.active ? root.accentColor : pb.tint
                    opacity: pb.enabledState ? 1.0 : 0.35
                }
                Text {
                    visible: pb.badge !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.horizontalCenter
                    anchors.leftMargin: 8
                    text: pb.badge
                    color: root.accentColor
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.Bold
                }
                ToolTip.visible: pbH.hovered && pb.tip !== ""
                ToolTip.text: pb.tip
                ToolTip.delay: 350
                MouseArea {
                    id: pbMouse
                    anchors.fill: parent
                    enabled: pb.enabledState
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pb.clicked()
                }
            }

            component PillDivider: Rectangle {
                width: 1; height: 18
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(1, 1, 1, 0.22)
            }

            PillButton {
                icon: "../assets/icons/material/ms-headphones.svg"
                tip: I18n.tr("Nghe cùng bạn bè", "Listen along with friends")
                onClicked: root.listenAlongClicked()
            }
            PillDivider {}
            PillButton {
                id: listenersBtn
                icon: "../assets/icons/material/ms-group.svg"
                enabledState: root.isCoListening
                badge: root.isListener ? "" : (root.listenerCount > 0 ? String(root.listenerCount) : "")
                tint: root.isListener ? "#fda4af" : "#ffffff"
                tip: root.isListener ? I18n.tr("Rời phiên nghe cùng", "Leave Listen Along")
                    : (root.listenerCount > 0 ? I18n.tr("Quản lý người nghe cùng", "Manage listeners")
                                              : I18n.tr("Chưa có ai nghe cùng", "No one is listening along"))
                onClicked: {
                    if (root.isListener) {
                        root.leaveListeningAlongClicked();
                    } else {
                        var pt = listenersBtn.mapToItem(null, listenersBtn.width / 2, 0);
                        root.listenersClicked(pt.x, pt.y);
                    }
                }
            }
            PillDivider {}
            PillButton {
                icon: "../assets/icons/material/ms-chat.svg"
                enabledState: root.isCoListening
                active: root.chatOpen
                tip: root.isCoListening ? I18n.tr("Gửi bình luận bay", "Send a floating comment")
                                        : I18n.tr("Bình luận khi nghe cùng bạn bè", "Comment while listening along")
                onClicked: {
                    root.chatOpen = !root.chatOpen;
                    if (root.chatOpen) chatField.forceActiveFocus();
                }
            }
        }
    }

    // Floating comment field above the pill
    Rectangle {
        id: chatCapsule
        visible: root.chatOpen
        anchors.bottom: pill.top
        anchors.bottomMargin: 10
        anchors.horizontalCenter: pill.horizontalCenter
        width: Math.max(pill.width, 280)
        height: 40
        radius: 20
        color: Qt.rgba(root.accentColor.r * 0.25, root.accentColor.g * 0.25, root.accentColor.b * 0.25, 0.92)
        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.6)
        border.width: 1
        z: 10

        function submit() {
            var t = chatField.text.trim();
            if (t !== "") root.sendChatMessage(t);
            chatField.text = "";
            root.chatOpen = false;
        }

        TextField {
            id: chatField
            anchors.left: parent.left
            anchors.right: sendBtn.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 14
            placeholderText: I18n.tr("Nhắn gì đó cho bạn bè...", "Say something to your friends...")
            placeholderTextColor: Qt.rgba(1, 1, 1, 0.45)
            color: "#ffffff"
            font.family: Theme.fontFamily
            font.pixelSize: 13
            background: Item {}
            onAccepted: chatCapsule.submit()
            Keys.onEscapePressed: root.chatOpen = false
        }

        NowPlayingCtlButton {
            id: sendBtn
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            size: 32
            icon: "../assets/icons/media-playback-start-symbolic.svg"
            onClicked: chatCapsule.submit()
        }
    }
}
