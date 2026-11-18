import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    height: 58
    color: Theme.bgDark
    border.color: Theme.border
    border.width: 1
    radius: Theme.radiusSm

    property var currentTrack: null
    property bool isPlaying: false
    property real currentTime: 0.0
    property real totalDuration: 1.0
    property real volume: 100.0

    signal playPauseClicked()
    signal nextClicked()
    signal prevClicked()
    signal seekRequested(real seconds)
    signal reqVolumeChange(real newVol)

    function fmtTime(sec) {
        if (!sec || sec < 0) return "0:00";
        var m = Math.floor(sec / 60);
        var s = Math.floor(sec % 60);
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 16

        // Left: Badge + Mini Info
        RowLayout {
            Layout.preferredWidth: 260
            spacing: 10

            // Status Badge
            Rectangle {
                Layout.preferredHeight: 22
                Layout.preferredWidth: 80
                radius: Theme.radiusXs
                color: root.isPlaying ? Theme.accent : Theme.selDim

                Text {
                    anchors.centerIn: parent
                    text: root.isPlaying ? I18n.tr("ĐANG PHÁT", "PLAYING") : (!root.currentTrack ? I18n.tr("ĐÃ DỪNG", "STOPPED") : I18n.tr("TẠM DỪNG", "PAUSED"))
                    color: root.isPlaying ? Theme.selText : Theme.accent
                    font.pixelSize: 10
                    font.bold: true
                }
            }

            // Transport Buttons
            Rectangle {
                width: 28; height: 28; radius: 14
                color: prevHover.hovered ? Theme.glassSoft : "transparent"
                HoverHandler { id: prevHover }
                AppIcon { anchors.centerIn: parent; source: "../assets/icons/media-skip-backward-symbolic.svg"; color: Theme.subtext; iconSize: 14 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.prevClicked() }
            }

            Rectangle {
                width: 32; height: 32; radius: 16
                color: playHover.hovered ? Theme.accent : Theme.accentSoft
                border.color: Theme.accent; border.width: 1
                Behavior on color { ColorAnimation { duration: 120 } }
                HoverHandler { id: playHover }
                AppIcon {
                    anchors.centerIn: parent
                    source: root.isPlaying ? "../assets/icons/media-playback-pause-symbolic.svg" : "../assets/icons/media-playback-start-symbolic.svg"
                    color: playHover.hovered ? Theme.selText : Theme.text
                    iconSize: 14
                    anchors.horizontalCenterOffset: root.isPlaying ? 0 : 1
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.playPauseClicked() }
            }

            Rectangle {
                width: 28; height: 28; radius: 14
                color: nextHover.hovered ? Theme.glassSoft : "transparent"
                HoverHandler { id: nextHover }
                AppIcon { anchors.centerIn: parent; source: "../assets/icons/media-skip-forward-symbolic.svg"; color: Theme.subtext; iconSize: 14 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.nextClicked() }
            }

            // Now playing track name
            Text {
                Layout.fillWidth: true
                text: root.currentTrack ? (root.currentTrack.name + " · " + root.currentTrack.artist) : I18n.tr("Chưa chọn bài hát", "No track selected")
                color: root.currentTrack ? Theme.text : Theme.subtext
                font.pixelSize: 12
                elide: Text.ElideRight
            }
        }

        // Center: Scrubber / Seek Bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: root.fmtTime(root.currentTime)
                color: Theme.subtext
                font.pixelSize: 11
                font.family: "monospace"
                Layout.preferredWidth: 32
                horizontalAlignment: Text.AlignRight
            }

            Rectangle {
                id: seekTrack
                Layout.fillWidth: true
                height: 4
                radius: 2
                color: Theme.divider

                Rectangle {
                    height: parent.height
                    radius: 2
                    color: Theme.accent
                    width: parent.width * Math.min(1.0, Math.max(0.0, root.totalDuration > 0 ? (root.currentTime / root.totalDuration) : 0))
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (root.totalDuration > 0) {
                            var ratio = Math.max(0.0, Math.min(1.0, mouse.x / seekTrack.width));
                            root.seekRequested(ratio * root.totalDuration);
                        }
                    }
                }
            }

            Text {
                text: root.fmtTime(root.totalDuration)
                color: Theme.subtext
                font.pixelSize: 11
                font.family: "monospace"
                Layout.preferredWidth: 32
            }
        }

        // Right: Volume Bar
        RowLayout {
            Layout.preferredWidth: 130
            spacing: 8

            AppIcon { source: "../assets/icons/audio-volume-high-symbolic.svg"; color: Theme.subtext; iconSize: 14 }

            Rectangle {
                id: volTrack
                Layout.preferredWidth: 70
                height: 4
                radius: 2
                color: Theme.divider

                Rectangle {
                    height: parent.height
                    radius: 2
                    color: Theme.teal
                    width: parent.width * (root.volume / 100.0)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        var newVol = Math.max(0, Math.min(100, (mouse.x / volTrack.width) * 100));
                        root.volume = newVol;
                        root.reqVolumeChange(newVol);
                    }
                }
            }

            Text {
                text: Math.round(root.volume) + "%"
                color: Theme.subtext
                font.pixelSize: 11
                font.family: "monospace"
            }
        }
    }
}
