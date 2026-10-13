import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "."

Rectangle {
    id: root
    width: 176
    height: 250
    radius: Theme.radiusCard
    color: cardMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.06) : Qt.rgba(1.0, 1.0, 1.0, 0.02)
    border.color: (root.track && root.isPlaying)
                  ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                  : (cardMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.18) : Qt.rgba(1.0, 1.0, 1.0, 0.06))
    border.width: 1

    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }

    property var track: null
    property bool isPlaying: false
    property bool isSelectionMode: false
    property bool isSelected: false
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent
    signal playRequested(var trk)
    signal detailsRequested(var trk)
    signal selectionToggled(var trk)
    signal contextMenuRequested(var trk, real globalX, real globalY)

    readonly property string trackVideoId: {
        if (!track) return "";
        if (track.videoId) return track.videoId;
        if (track.path && track.path.startsWith("ytdl://")) return track.path.replace("ytdl://", "");
        return "";
    }
    readonly property bool isDownloading: (typeof downloadManager !== "undefined" && downloadManager && trackVideoId) ? Boolean(downloadManager.isDownloading(trackVideoId)) : false
    readonly property real downloadProgress: (typeof downloadManager !== "undefined" && downloadManager) ? downloadManager.getProgress(trackVideoId) : -1
    readonly property bool isDownloaded: {
        if (typeof downloadManager !== "undefined" && downloadManager && downloadManager.isDownloaded(trackVideoId)) return true;
        if (track && (track.videoId || (track.path && track.path.startsWith("ytdl://"))) && typeof win !== "undefined" && win.allTracks) {
            var vId = trackVideoId;
            var tName = (track.name || track.title || "").toLowerCase().trim();
            return win.allTracks.some(t => (vId && t.videoId === vId) || (tName && (t.title || t.name || "").toLowerCase().trim() === tName));
        }
        return false;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        // Album Art Image Container
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: width

            Rectangle {
                anchors.fill: parent
                radius: 7
                color: "#202024"
                clip: true

                Rectangle {
                    anchors.fill: parent
                    color: "#202024"
                    visible: !coverImg.visible || coverImg.status !== Image.Ready
                }

            Image {
                id: coverImg
                anchors.fill: parent
                source: {
                    if (!root.track || !root.track.image) return "";
                    var s = root.track.image;
                    if (s.startsWith("/") && !s.startsWith("file://")) return "file://" + s;
                    if (s.indexOf("googleusercontent.com") !== -1 || s.indexOf("ggpht.com") !== -1) {
                        return s.replace(/=w\d+-h\d+[^=]*$/, "=w360-h360-l90-rj");
                    }
                    if (s.indexOf("mzstatic.com") !== -1) {
                        return s.replace(/\d+x\d+bb/, "360x360bb");
                    }
                    if (s.indexOf("i.ytimg.com") !== -1) {
                        return s.split("?")[0];
                    }
                    return s;
                }
                fillMode: Image.PreserveAspectCrop
                scale: {
                    if (implicitWidth > 0 && implicitHeight > 0) {
                        var r = implicitWidth / implicitHeight;
                        if (r > 1.25 && r < 1.45) return 1.34;
                    }
                    return 1.0;
                }
                transformOrigin: Item.Center
                asynchronous: true
                visible: status === Image.Ready
                sourceSize: Qt.size(240, 240)
                smooth: true
                    onStatusChanged: {
                        if (status === Image.Error) {
                            var srcStr = String(source);
                            if (srcStr.indexOf("maxresdefault.jpg") !== -1) {
                                source = srcStr.replace("maxresdefault.jpg", "hqdefault.jpg");
                            }
                        }
                    }
                }

                // Fallback gradient cover if image fails or missing
                Rectangle {
                    anchors.fill: parent
                    visible: !coverImg.visible
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#333333" }
                        GradientStop { position: 1.0; color: "#181818" }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: root.track && root.track.artist ? root.track.artist.charAt(0).toUpperCase() : "A"
                        font.family: Theme.fontFamily
                        font.pixelSize: 42
                        font.bold: true
                        color: "#555555"
                    }
                }
            }

            // 1px Hairline Border Overlay on top of image
            Rectangle {
                anchors.fill: parent
                radius: 8
                color: "transparent"
                border.color: cardMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.40) : Qt.rgba(1.0, 1.0, 1.0, 0.16)
                border.width: 1
                z: 1
                Behavior on border.color { ColorAnimation { duration: 120 } }
            }

            // Nutsty Floating Accent Play Button on Hover
            Rectangle {
                id: greenPlayBtn
                width: 44
                height: 44
                radius: 22
                color: root.accentColor
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 8
                z: 10

                // Fade & Slide up on hover
                opacity: cardMouse.containsMouse || root.isPlaying ? 1.0 : 0.0
                y: cardMouse.containsMouse || root.isPlaying ? parent.height - height - 8 : parent.height - height
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                AppIcon {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: root.isPlaying ? 0 : 1
                    source: root.isPlaying ? "../assets/icons/media-playback-pause-symbolic.svg" : "../assets/icons/media-playback-start-symbolic.svg"
                    iconSize: 18
                    color: "#000000"
                }
            }

            // Nutsty Download State Badge (Spinner or Checkmark)
            Rectangle {
                id: downloadBadge
                width: 26
                height: 26
                radius: 13
                color: Qt.rgba(0.08, 0.08, 0.1, 0.85)
                border.color: root.isDownloading ? root.accentColor : Qt.rgba(0, 160, 203, 0.5)
                border.width: 1
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 6
                z: 15
                visible: root.isDownloading || root.isDownloaded

                DownloadingSpinner {
                    anchors.centerIn: parent
                    visible: root.isDownloading
                    running: root.isDownloading
                    iconSize: 15
                    progress: root.downloadProgress
                    color: root.accentColor
                }

                AppIcon {
                    anchors.centerIn: parent
                    visible: root.isDownloaded && !root.isDownloading
                    source: "../assets/icons/emblem-ok-symbolic.svg"
                    iconSize: 13
                    color: "#00a0cb"
                }
            }

            // Selection Checkbox
            Rectangle {
                id: selectBox
                width: 26
                height: 26
                radius: 13
                color: root.isSelected ? root.accentColor : Qt.rgba(0.08, 0.08, 0.1, 0.85)
                border.color: root.isSelected ? root.accentColor : Qt.rgba(1, 1, 1, 0.6)
                border.width: 1.5
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 6
                z: 16
                visible: root.isSelectionMode

                AppIcon {
                    anchors.centerIn: parent
                    visible: root.isSelected
                    source: "../assets/icons/emblem-ok-symbolic.svg"
                    iconSize: 13
                    color: "#000000"
                }
            }
        }

        // Title
        Text {
            Layout.fillWidth: true
            text: root.track ? root.track.name : ""
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.bold: true
            color: Theme.textPrimary
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        // Artist / Subtitle
        Text {
            Layout.fillWidth: true
            text: root.track ? root.track.artist : ""
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.textSecondary
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
        }

        Item { Layout.fillHeight: true }
    }

    MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        z: 20
        onClicked: mouse => {
            if (win && win.isContextMenuActive) {
                mouse.accepted = true;
                return;
            }
            if (root.isSelectionMode) {
                root.selectionToggled(root.track);
                return;
            }
            if (mouse.button === Qt.RightButton) {
                var pt = root.mapToItem(null, mouse.x, mouse.y);
                root.contextMenuRequested(root.track, pt.x, pt.y);
            } else {
                root.playRequested(root.track);
            }
        }
    }
}
