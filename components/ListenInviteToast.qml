import QtQuick
import QtQuick.Layouts
import "."

// Incoming listen-along invite: who invites, the track they play, and Join / Later.
Item {
    id: root
    width: 390
    height: 118
    visible: opacity > 0
    opacity: isShown ? 1 : 0
    z: 9999

    Behavior on opacity {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }

    property bool isShown: false
    property var invite: null
    // The receiver already listens along or hosts: joining ends that session
    property bool leavesCurrentSession: false
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent

    readonly property var track: invite && invite.now_playing ? invite.now_playing : null
    readonly property string senderName: invite && invite.user_name ? invite.user_name : I18n.tr("Bạn bè", "Friend")

    signal acceptRequested(var invite)

    Timer {
        id: autoDismissTimer
        interval: 25000
        repeat: false
        running: root.isShown && !cardHover.hovered
        onTriggered: root.dismiss()
    }

    function showInvite(inv, busy) {
        root.invite = inv;
        root.leavesCurrentSession = Boolean(busy);
        root.isShown = true;
        autoDismissTimer.restart();
    }

    function dismiss() {
        root.isShown = false;
        autoDismissTimer.stop();
    }

    function accept() {
        var inv = root.invite;
        root.dismiss();
        if (inv) root.acceptRequested(inv);
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Qt.tint(Qt.rgba(0.07, 0.07, 0.09, 0.94), Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16))
        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.40)
        border.width: 1

        HoverHandler { id: cardHover }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            // Cover with the inviter's avatar pinned on its corner
            Item {
                Layout.preferredWidth: 64
                Layout.preferredHeight: 64

                RoundedImage {
                    anchors.fill: parent
                    radius: 10
                    source: root.track ? (root.track.cover || root.track.image || "") : ""
                    fallbackIcon: "../assets/icons/media-optical-audio-symbolic.svg"
                    fallbackIconColor: root.accentColor
                    placeholderColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                }

                RoundedImage {
                    width: 26; height: 26; radius: 13
                    x: parent.width - 18
                    y: parent.height - 18
                    source: root.invite ? (root.invite.avatar_url || "") : ""
                    borderColor: root.accentColor
                    borderWidth: 1.5
                    fallbackIcon: "../assets/icons/system-users-symbolic.svg"
                    placeholderColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr(root.senderName + " mời bạn nghe cùng", root.senderName + " invited you to listen along")
                        color: root.accentColor
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        radius: 10
                        color: closeHover.hovered ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                        HoverHandler { id: closeHover }
                        AppIcon {
                            anchors.centerIn: parent
                            source: "../assets/icons/window-close-symbolic.svg"
                            iconSize: 9
                            color: closeHover.hovered ? "#ffffff" : "#a1a1aa"
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.dismiss()
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.track && root.track.title ? root.track.title : I18n.tr("Bài hát", "Track")
                    color: "#ffffff"
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.leavesCurrentSession
                          ? I18n.tr("Bạn sẽ rời phiên nghe cùng hiện tại", "You will leave your current session")
                          : (root.track && root.track.artist ? root.track.artist : I18n.tr("Nghệ sĩ chưa rõ", "Unknown Artist"))
                    color: root.leavesCurrentSession ? "#fda4af" : "#a1a1aa"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 6

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 28
                        radius: 8
                        color: joinHover.hovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.38) : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        HoverHandler { id: joinHover }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5
                            AppIcon {
                                source: "../assets/icons/media-playback-start-symbolic.svg"
                                iconSize: 11
                                color: "#ffffff"
                            }
                            Text {
                                text: I18n.tr("Nghe cùng", "Listen along")
                                color: "#ffffff"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.accept()
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 28
                        radius: 8
                        color: laterHover.hovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        HoverHandler { id: laterHover }

                        Text {
                            anchors.centerIn: parent
                            text: I18n.tr("Để sau", "Later")
                            color: Qt.rgba(1, 1, 1, 0.85)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.dismiss()
                        }
                    }
                }
            }
        }
    }
}
