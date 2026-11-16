import QtQuick
import QtQuick.Controls.Basic
import "."

// SimpMusic-style action row at the bottom of the Mochy side panel: Lyrics on the left, YouTube
// comments in the middle, Up Next on the right. Listen Along controls live in the playerbar.
Item {
    id: root

    property string activeTab: "lyrics"
    property color accentColor: "#ffffff"

    signal lyricsClicked()
    signal commentsClicked()
    signal queueClicked()

    implicitHeight: 44
    implicitWidth: 3 * lyricsBtn.width + 120

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
        id: commentsBtn
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        size: 40
        icon: "../assets/icons/material/ms-forum.svg"
        toggle: true
        on: root.activeTab === "comments"
        onClicked: root.commentsClicked()
        ToolTip.visible: commentsBtnH.hovered
        ToolTip.text: I18n.tr("Bình luận", "Comments")
        ToolTip.delay: 350
        HoverHandler { id: commentsBtnH }
    }

    NowPlayingCtlButton {
        id: queueBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        size: 40
        icon: "../assets/icons/queue-music-symbolic.svg"
        toggle: true
        on: root.activeTab === "queue"
        onClicked: root.queueClicked()
        ToolTip.visible: queueBtnH.hovered
        ToolTip.text: I18n.tr("Phát tiếp theo", "Playing Next")
        ToolTip.delay: 350
        HoverHandler { id: queueBtnH }
    }
}
