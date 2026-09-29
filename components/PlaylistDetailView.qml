import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import "."

Rectangle {
    id: root
    color: "transparent"

    property var playlist: null
    property var currentTrack: null
    property bool isPlaying: false
    property bool isLoadingAudio: false
    property color accentColor: Theme.accent

    signal backRequested()
    signal playAllRequested(var tracks)
    signal shuffleRequested(var tracks)
    signal editRequested(var playlist)
    signal deleteRequested(string plId)
    signal trackPlayRequested(var track, int index, var trackList)
    signal removeTrackRequested(string plId, var track)
    signal trackContextMenuRequested(var track, real globalX, real globalY)
    signal addTracksRequested(var playlist)
    signal reorderTrackRequested(string plId, int fromIndex, int toIndex)

    readonly property var playlistTracks: {
        if (!playlist || !playlist.tracks) return [];
        if (playlist.tracks.length !== undefined) return playlist.tracks;
        return [];
    }

    readonly property string totalDurationFormatted: {
        var totalSecs = 0;
        for (var i = 0; i < playlistTracks.length; i++) {
            var t = playlistTracks[i];
            if (t && t.duration) {
                if (typeof t.duration === "number") {
                    totalSecs += t.duration;
                } else if (typeof t.duration === "string") {
                    var parts = t.duration.split(":");
                    if (parts.length === 2) {
                        totalSecs += parseInt(parts[0]) * 60 + parseInt(parts[1]);
                    } else if (parts.length === 3) {
                        totalSecs += parseInt(parts[0]) * 3600 + parseInt(parts[1]) * 60 + parseInt(parts[2]);
                    }
                }
            }
        }
        if (totalSecs <= 0) return "";
        var mins = Math.floor(totalSecs / 60);
        var hrs = Math.floor(mins / 60);
        var remMins = mins % 60;
        if (hrs > 0) {
            return hrs + I18n.tr(" giờ ", " hr ") + (remMins > 0 ? (remMins + I18n.tr(" phút", " min")) : "");
        }
        return mins + I18n.tr(" phút", " min");
    }

    Flickable {
        id: scrollArea
        anchors.fill: parent
        anchors.margins: 20
        contentWidth: width
        contentHeight: mainCol.implicitHeight + 60
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        ColumnLayout {
            id: mainCol
            width: scrollArea.width
            spacing: 24

            // Top Navigation: Back Button
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: 18
                    color: backArea.containsMouse ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.06)
                    border.color: Qt.rgba(255, 255, 255, 0.08)
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 150 } }

                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/go-previous-symbolic.svg"
                        iconSize: 16
                        color: backArea.containsMouse ? "#ffffff" : Qt.rgba(255, 255, 255, 0.8)
                    }

                    MouseArea {
                        id: backArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.backRequested()
                    }
                }

                Text {
                    text: I18n.tr("Quay lại Thư viện", "Back to Library")
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    color: Qt.rgba(255, 255, 255, 0.7)
                }
            }

            // Hero Header Row: Collage/Cover + Metadata + Action Buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: 24

                // Large Artwork
                PlaylistCollageThumbnail {
                    Layout.preferredWidth: 170
                    Layout.preferredHeight: 170
                    width: 170
                    height: 170
                    radius: 16
                    playlistCover: root.playlist ? (root.playlist.image || root.playlist.thumbnail || "") : ""
                    customCover: root.playlist ? (root.playlist.customCover || "") : ""
                    tracks: root.playlistTracks
                    playlistTitle: root.playlist ? (root.playlist.title || root.playlist.name || "") : ""
                    accentColor: root.accentColor
                }

                // Metadata Column
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Title
                    Text {
                        Layout.fillWidth: true
                        text: root.playlist ? (root.playlist.title || root.playlist.name || I18n.tr("Danh sách phát", "Playlist")) : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 28
                        font.weight: Font.Bold
                        color: "#ffffff"
                        elide: Text.ElideRight
                    }

                    // Personal Playlist Subtitle (No border, clean text under title - ui-layout-design-rules)
                    Text {
                        text: I18n.tr("Danh sách phát cá nhân", "Personal Playlist")
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: root.accentColor
                    }

                    // Description (if present)
                    Text {
                        Layout.fillWidth: true
                        visible: root.playlist && root.playlist.description && root.playlist.description.length > 0
                        text: root.playlist ? (root.playlist.description || "") : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.textSecondary
                        elide: Text.ElideRight
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                    }

                    // Stats: Track Count & Duration
                    RowLayout {
                        spacing: 8
                        Text {
                            text: root.playlistTracks.length + I18n.tr(" bài hát", " tracks")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            color: Theme.textSecondary
                        }
                        Text {
                            visible: root.totalDurationFormatted !== ""
                            text: "•"
                            font.pixelSize: 13
                            color: Theme.textMuted
                        }
                        Text {
                            visible: root.totalDurationFormatted !== ""
                            text: root.totalDurationFormatted
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: Theme.textSecondary
                        }
                    }

                    // Action Buttons Row
                    RowLayout {
                        Layout.topMargin: 8
                        spacing: 12

                        // Play All Button (Dynamic Chromatic Accent)
                        Rectangle {
                            id: playBtn
                            readonly property bool hasTracks: root.playlistTracks.length > 0
                            Layout.preferredHeight: 38
                            Layout.preferredWidth: playRow.implicitWidth + 24
                            radius: 19
                            color: hasTracks
                                   ? (playArea.containsMouse ? Qt.lighter(root.accentColor, 1.15) : root.accentColor)
                                   : Qt.rgba(255, 255, 255, 0.08)
                            opacity: hasTracks ? 1.0 : 0.4
                            border.color: hasTracks ? Qt.rgba(255, 255, 255, 0.25) : "transparent"
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 150 } }

                            Row {
                                id: playRow
                                anchors.centerIn: parent
                                spacing: 8

                                AppIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: "../assets/icons/media-playback-start-symbolic.svg"
                                    iconSize: 14
                                    color: playBtn.hasTracks ? "#000000" : Qt.rgba(255, 255, 255, 0.4)
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.tr("Phát tất cả", "Play All")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    color: playBtn.hasTracks ? "#000000" : Qt.rgba(255, 255, 255, 0.4)
                                }
                            }

                            MouseArea {
                                id: playArea
                                anchors.fill: parent
                                enabled: playBtn.hasTracks
                                hoverEnabled: true
                                cursorShape: playBtn.hasTracks ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.playAllRequested(root.playlistTracks)
                            }
                        }

                        // Shuffle Button (Unified SSOT)
                        ShuffleButton {
                            id: shufBtn
                            hasTracks: root.playlistTracks.length > 0
                            accentColor: root.accentColor
                            text: I18n.tr("Trộn bài", "Shuffle")
                            onClicked: root.shuffleRequested(root.playlistTracks)
                        }

                        // Add Tracks Button
                        Rectangle {
                            Layout.preferredHeight: 38
                            Layout.preferredWidth: addTrkRow.implicitWidth + 24
                            radius: 19
                            color: addTrkArea.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22) : Qt.rgba(255, 255, 255, 0.06)
                            border.color: addTrkArea.containsMouse ? root.accentColor : Qt.rgba(255, 255, 255, 0.10)
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            Row {
                                id: addTrkRow
                                anchors.centerIn: parent
                                spacing: 6

                                AppIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: "../assets/icons/list-add-symbolic.svg"
                                    iconSize: 13
                                    color: addTrkArea.containsMouse ? root.accentColor : "#ffffff"
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.tr("Thêm bài", "Add Songs")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    color: addTrkArea.containsMouse ? root.accentColor : "#ffffff"
                                }
                            }

                            MouseArea {
                                id: addTrkArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.addTracksRequested(root.playlist)
                            }
                        }

                        // Edit Button
                        Rectangle {
                            Layout.preferredHeight: 38
                            Layout.preferredWidth: editRow.implicitWidth + 20
                            radius: 19
                            color: editArea.containsMouse ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.06)
                            border.color: Qt.rgba(255, 255, 255, 0.1)
                            border.width: 1

                            Row {
                                id: editRow
                                anchors.centerIn: parent
                                spacing: 6

                                AppIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: "../assets/icons/accessories-text-editor-symbolic.svg"
                                    iconSize: 13
                                    color: Qt.rgba(255, 255, 255, 0.8)
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.tr("Sửa", "Edit")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    color: Qt.rgba(255, 255, 255, 0.8)
                                }
                            }

                            MouseArea {
                                id: editArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.editRequested(root.playlist)
                            }
                        }

                        // Delete Playlist Button (Muted Rose Style - Rule #8)
                        Rectangle {
                            Layout.preferredHeight: 38
                            Layout.preferredWidth: delRow.implicitWidth + 20
                            radius: 19
                            color: delArea.containsMouse ? Qt.rgba(244, 63, 94, 0.20) : Qt.rgba(255, 255, 255, 0.06)
                            border.color: delArea.containsMouse ? Qt.rgba(244, 63, 94, 0.45) : Qt.rgba(255, 255, 255, 0.10)
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            Row {
                                id: delRow
                                anchors.centerIn: parent
                                spacing: 6

                                AppIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: "../assets/icons/user-trash-symbolic.svg"
                                    iconSize: 13
                                    color: delArea.containsMouse ? "#f43f5e" : Qt.rgba(244, 63, 94, 0.85)
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.tr("Xóa", "Delete")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    color: delArea.containsMouse ? "#f43f5e" : Qt.rgba(244, 63, 94, 0.85)
                                }
                            }

                            MouseArea {
                                id: delArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.playlist) {
                                        root.deleteRequested(root.playlist.id || root.playlist.playlistId);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Empty State (Centered in Viewport - ui-layout-design-rules)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: emptyStateCol.implicitHeight + 80
                Layout.topMargin: Math.max(30, (scrollArea.height - 240) / 4)
                visible: root.playlistTracks.length === 0

                ColumnLayout {
                    id: emptyStateCol
                    anchors.centerIn: parent
                    width: Math.min(scrollArea.width, 480)
                    spacing: 16

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 72
                        height: 72
                        radius: 36
                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.28)
                        border.width: 1

                        AppIcon {
                            anchors.centerIn: parent
                            source: "../assets/icons/folder-music-symbolic.svg"
                            iconSize: 34
                            color: root.accentColor
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: I18n.tr("Danh sách phát chưa có bài hát nào", "This playlist has no tracks yet")
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: I18n.tr("Tìm kiếm bài hát yêu thích để thêm ngay vào danh sách phát này", "Search and add your favorite songs directly to this playlist")
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.textSecondary
                        wrapMode: Text.WordWrap
                    }

                    // Call to action button: Search & Add Songs
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 8
                        Layout.preferredHeight: 40
                        Layout.preferredWidth: addSearchRow.implicitWidth + 32
                        radius: 20
                        color: addSearchArea.containsMouse ? Qt.lighter(root.accentColor, 1.15) : root.accentColor
                        border.color: Qt.rgba(255, 255, 255, 0.25)
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 150 } }

                        Row {
                            id: addSearchRow
                            anchors.centerIn: parent
                            spacing: 8

                            AppIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                source: "../assets/icons/system-search-symbolic.svg"
                                iconSize: 15
                                color: "#000000"
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Tìm & thêm bài hát", "Search & Add Songs")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                color: "#000000"
                            }
                        }

                        MouseArea {
                            id: addSearchArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.addTracksRequested(root.playlist)
                        }
                    }
                }
            }

            // Tracklist Items
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.playlistTracks.length > 0
                spacing: 2

                Repeater {
                    model: root.playlistTracks
                    delegate: Item {
                        Layout.fillWidth: true
                        height: 52

                        readonly property var trk: modelData
                        readonly property bool isCurrent: {
                            if (!root.currentTrack || !trk) return false;
                            if (root.currentTrack.path && trk.path && root.currentTrack.path === trk.path) return true;
                            if (root.currentTrack.videoId && trk.videoId && root.currentTrack.videoId === trk.videoId) return true;
                            return false;
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: isCurrent
                                   ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                                   : (rowMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.06) : "transparent")

                            Behavior on color { ColorAnimation { duration: 100 } }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) {
                                        var pos = rowMouse.mapToItem(null, mouse.x, mouse.y);
                                        root.trackContextMenuRequested(trk, pos.x, pos.y);
                                    } else {
                                        root.trackPlayRequested(trk, index, root.playlistTracks);
                                    }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 14
                                spacing: 12
                                z: 1

                                // Index Number or Play/Pause Indicator
                                Item {
                                    Layout.preferredWidth: 24
                                    Layout.preferredHeight: 24

                                    CircularSpinner {
                                        anchors.centerIn: parent
                                        visible: isCurrent && root.isLoadingAudio
                                        size: 14
                                        strokeWidth: 2.0
                                        color: root.accentColor
                                    }

                                    AppIcon {
                                        anchors.centerIn: parent
                                        visible: isCurrent && !root.isLoadingAudio && root.isPlaying
                                        source: "../assets/icons/audio-volume-high-symbolic.svg"
                                        iconSize: 14
                                        color: root.accentColor
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: !isCurrent || (!root.isLoadingAudio && !root.isPlaying)
                                        text: String(index + 1)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                        color: isCurrent ? root.accentColor : Theme.textMuted
                                    }
                                }

                                // Track Artwork (RoundedImage)
                                RoundedImage {
                                    Layout.preferredWidth: 38
                                    Layout.preferredHeight: 38
                                    radius: 6
                                    source: trk ? (trk.image || trk.cover || trk.thumbnail || "") : ""
                                    initialsText: trk ? (trk.title || trk.name || "") : ""
                                }

                                // Title and Artist
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        Layout.fillWidth: true
                                        text: trk ? (trk.title || trk.name || "") : ""
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        color: isCurrent ? root.accentColor : "#ffffff"
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: trk ? (trk.artist || "") : ""
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Theme.textSecondary
                                        elide: Text.ElideRight
                                    }
                                }

                                // Duration (Fixed width + AlignRight to keep column strictly aligned)
                                Text {
                                    Layout.preferredWidth: 46
                                    Layout.alignment: Qt.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: {
                                        if (!trk || !trk.duration) return "";
                                        if (typeof trk.duration === "number") {
                                            var m = Math.floor(trk.duration / 60);
                                            var s = Math.floor(trk.duration % 60);
                                            return m + ":" + (s < 10 ? "0" : "") + s;
                                        }
                                        return String(trk.duration);
                                    }
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Theme.textMuted
                                }

                                // Action Buttons Container (Fixed width 88px prevents column shifting)
                                Item {
                                    Layout.preferredWidth: 88
                                    Layout.preferredHeight: 28
                                    Layout.alignment: Qt.AlignVCenter

                                    Row {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4

                                        // Move Up Button (↑)
                                        Rectangle {
                                            width: 26
                                            height: 26
                                            radius: 13
                                            visible: index > 0
                                            opacity: (rowMouse.containsMouse || upArea.containsMouse) ? 1.0 : 0.0
                                            color: upArea.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25) : "transparent"
                                            border.color: upArea.containsMouse ? root.accentColor : "transparent"
                                            border.width: 1

                                            Behavior on opacity { NumberAnimation { duration: 120 } }
                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            AppIcon {
                                                anchors.centerIn: parent
                                                source: "../assets/icons/go-up-symbolic.svg"
                                                iconSize: 13
                                                color: upArea.containsMouse ? root.accentColor : Qt.rgba(255, 255, 255, 0.6)
                                            }

                                            MouseArea {
                                                id: upArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (root.playlist && index > 0) {
                                                        root.reorderTrackRequested(root.playlist.id || root.playlist.playlistId, index, index - 1);
                                                    }
                                                }
                                            }
                                        }

                                        // Move Down Button (↓)
                                        Rectangle {
                                            width: 26
                                            height: 26
                                            radius: 13
                                            visible: index < root.playlistTracks.length - 1
                                            opacity: (rowMouse.containsMouse || downArea.containsMouse) ? 1.0 : 0.0
                                            color: downArea.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25) : "transparent"
                                            border.color: downArea.containsMouse ? root.accentColor : "transparent"
                                            border.width: 1

                                            Behavior on opacity { NumberAnimation { duration: 120 } }
                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            AppIcon {
                                                anchors.centerIn: parent
                                                source: "../assets/icons/go-down-symbolic.svg"
                                                iconSize: 13
                                                color: downArea.containsMouse ? root.accentColor : Qt.rgba(255, 255, 255, 0.6)
                                            }

                                            MouseArea {
                                                id: downArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (root.playlist && index < root.playlistTracks.length - 1) {
                                                        root.reorderTrackRequested(root.playlist.id || root.playlist.playlistId, index, index + 1);
                                                    }
                                                }
                                            }
                                        }

                                        // Remove Track Button (Muted Rose hover)
                                        Rectangle {
                                            width: 28
                                            height: 28
                                            radius: 14
                                            color: remArea.containsMouse ? Qt.rgba(244, 63, 94, 0.2) : "transparent"
                                            opacity: rowMouse.containsMouse || remArea.containsMouse ? 1.0 : 0.0

                                            Behavior on opacity { NumberAnimation { duration: 120 } }
                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            AppIcon {
                                                anchors.centerIn: parent
                                                source: "../assets/icons/user-trash-symbolic.svg"
                                                iconSize: 13
                                                color: remArea.containsMouse ? "#f43f5e" : Qt.rgba(255, 255, 255, 0.6)
                                            }

                                            MouseArea {
                                                id: remArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (root.playlist) {
                                                        root.removeTrackRequested(root.playlist.id || root.playlist.playlistId, trk);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
