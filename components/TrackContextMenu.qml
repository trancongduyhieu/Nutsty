import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

Item {
    id: root
    anchors.fill: parent
    enabled: isOpen || closingGuard
    visible: opacity > 0 || closingGuard
    opacity: isOpen ? 1 : 0
    z: 9999

    Behavior on opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    property bool isOpen: false
    property bool closingGuard: false
    property var track: null
    property bool isQueueItem: false
    property real targetX: 0
    property real targetY: 0
    property var dlMgr: null
    property var customPlaylists: []
    property bool isPlaylistSubmenuOpen: false
    // Lyrics source picker: only offered when opened from the Now Playing "more" button
    property bool showLyricsSource: false
    property bool isLyricsSourceSubmenuOpen: false
    readonly property string currentLyricsSource: (typeof win !== "undefined" && win && win.lyricsSource) ? win.lyricsSource : "auto"
    readonly property var lyricsSourceOptions: [
        { key: "auto", name: I18n.tr("Tự động", "Automatic") },
        { key: "youlyplus", name: "YouLyPlus" },
        { key: "simpmusic", name: "SimpMusic" },
        { key: "betterlyrics", name: "Apple Music" },
        { key: "spotify", name: "Spotify" },
        { key: "lrclib", name: "LRCLIB" },
        { key: "kugou", name: "KuGou" },
        { key: "netease", name: "NetEase" },
        { key: "youtube", name: I18n.tr("Phụ đề YouTube", "YouTube Subtitles") }
    ]
    function lyricsSourceName(key) {
        for (var i = 0; i < lyricsSourceOptions.length; ++i)
            if (lyricsSourceOptions[i].key === key) return lyricsSourceOptions[i].name;
        return lyricsSourceOptions[0].name;
    }
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent

    Timer {
        id: closeTimer
        interval: 220
        repeat: false
        onTriggered: {
            root.closingGuard = false;
        }
    }

    signal playNextRequested(var track)
    signal addToQueueRequested(var track)
    signal startRadioRequested(var track)
    signal openFolderRequested(var track)
    signal downloadTrackRequested(var track)
    signal removeFromQueueRequested(var track)
    signal removeFromPlaylistRequested(var track, string playlistId)
    signal deleteTrackRequested(var track)
    signal addToPlaylistRequested(var track, string playlistId)
    signal createPlaylistWithTrackRequested(var track)
    signal viewArtistRequested(var track)
    signal toggleFavoriteRequested(var track)
    signal likeRequested(var track)
    signal dislikeRequested(var track)
    signal lyricsSourceSelected(string source)

    readonly property string trackVid: {
        if (!track) return "";
        if (track.videoId) return String(track.videoId);
        if (track.path && String(track.path).startsWith("ytdl://")) return String(track.path).replace("ytdl://", "");
        return "";
    }
    readonly property bool isFavorite: {
        var rev = (typeof win !== "undefined" && win) ? win.likedSongsRevision : 0;
        return rev >= 0 && !!track && typeof win !== "undefined" && win && typeof win.isTrackLiked === "function" && win.isTrackLiked(track);
    }

    function openAt(posTrack, xPos, yPos, queueItem, withLyricsSource) {
        closeTimer.stop();
        root.closingGuard = false;
        root.isPlaylistSubmenuOpen = false;
        root.isLyricsSourceSubmenuOpen = false;
        root.showLyricsSource = !!withLyricsSource;
        root.track = posTrack;
        root.isQueueItem = !!queueItem;
        root.targetX = xPos;
        root.targetY = yPos;
        root.isOpen = true;
    }

    function closeMenu() {
        if (!root.isOpen && !root.closingGuard) return;
        root.isOpen = false;
        root.closingGuard = true;
        closeTimer.restart();
    }

    // Dismiss backdrop - completely absorbs press, release, and click
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true
        onPressed: mouse => {
            mouse.accepted = true;
            root.closeMenu();
        }
        onReleased: mouse => mouse.accepted = true
        onClicked: mouse => mouse.accepted = true
    }

    // Context Menu Card
    Rectangle {
        id: menuCard
        width: 230
        height: menuCol.implicitHeight + 16
        radius: 10
        color: Qt.rgba(0.11, 0.11, 0.13, 0.96)
        border.color: Qt.rgba(1, 1, 1, 0.12)
        border.width: 1

        // Clamping to avoid window borders
        x: Math.max(12, Math.min(root.targetX, root.width - width - 12))
        y: Math.max(12, Math.min(root.targetY, root.height - height - 12))

        scale: root.isOpen ? 1 : 0.95
        Behavior on scale {
            NumberAnimation { duration: 150; easing.type: Easing.OutBack }
        }

        // Prevent click propagation through menu card
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: true
            onPressed: mouse => mouse.accepted = true
            onReleased: mouse => mouse.accepted = true
            onClicked: mouse => mouse.accepted = true
        }

        Column {
            id: menuCol
            anchors.top: parent.top
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 2

            // Track header
            Item {
                width: parent.width
                height: 40
                visible: root.track !== null

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: 4
                        color: "#222"
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: (root.track && root.track.image) ? root.track.image : ""
                            fillMode: Image.PreserveAspectCrop
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: (root.track && (root.track.title || root.track.name)) ? (root.track.title || root.track.name) : I18n.tr("Bài hát", "Track")
                            color: Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: (root.track && root.track.artist) ? root.track.artist : I18n.tr("Nghệ sĩ chưa rõ", "Unknown Artist")
                            color: Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width - 16
                height: 1
                color: Qt.rgba(1, 1, 1, 0.08)
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.track !== null
            }

            // Rating: heart (favourites), like / dislike (YouTube Music rating)
            MenuItemButton {
                text: root.isFavorite ? I18n.tr("Bỏ khỏi Yêu thích", "Remove from Favorites") : I18n.tr("Thêm vào Yêu thích", "Add to Favorites")
                iconSource: root.isFavorite ? "../assets/icons/material/ms-favorite-fill.svg" : "../assets/icons/material/ms-favorite.svg"
                iconColor: root.isFavorite ? Qt.rgba(0.957, 0.247, 0.369, 1.0) : Theme.textSecondary
                onClicked: {
                    var t = root.track;
                    root.closeMenu();
                    if (t) root.toggleFavoriteRequested(t);
                }
            }

            MenuItemButton {
                visible: root.trackVid !== ""
                text: I18n.tr("Thích", "Like")
                iconSource: "../assets/icons/material/ms-thumb_up.svg"
                onClicked: {
                    var t = root.track;
                    root.closeMenu();
                    if (t) root.likeRequested(t);
                }
            }

            MenuItemButton {
                visible: root.trackVid !== ""
                text: I18n.tr("Không thích", "Dislike")
                iconSource: "../assets/icons/material/ms-thumb_down.svg"
                onClicked: {
                    var t = root.track;
                    root.closeMenu();
                    if (t) root.dislikeRequested(t);
                }
            }

            Rectangle {
                width: parent.width - 16
                height: 1
                color: Qt.rgba(1, 1, 1, 0.08)
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Lyrics source (Now Playing only): expandable list, the active source is ticked
            MenuItemButton {
                visible: root.showLyricsSource
                text: I18n.tr("Nguồn lời: ", "Lyrics source: ") + root.lyricsSourceName(root.currentLyricsSource)
                iconSource: "../assets/icons/material/ms-lyrics.svg"
                trailingIcon: "../assets/icons/material/ms-expand_more.svg"
                trailingRotation: root.isLyricsSourceSubmenuOpen ? 180 : 0
                onClicked: root.isLyricsSourceSubmenuOpen = !root.isLyricsSourceSubmenuOpen
            }

            Column {
                visible: root.showLyricsSource && root.isLyricsSourceSubmenuOpen
                width: parent.width
                spacing: 2

                Repeater {
                    model: root.lyricsSourceOptions
                    delegate: MenuItemButton {
                        readonly property bool active: modelData.key === root.currentLyricsSource
                        text: modelData.name
                        iconSource: active ? "../assets/icons/material/ms-check.svg" : ""
                        textColor: active ? root.accentColor : Theme.textPrimary
                        iconColor: root.accentColor
                        indent: 14
                        onClicked: {
                            var key = modelData.key;
                            root.closeMenu();
                            if (!active) root.lyricsSourceSelected(key);
                        }
                    }
                }
            }

            Rectangle {
                visible: root.showLyricsSource
                width: parent.width - 16
                height: 1
                color: Qt.rgba(1, 1, 1, 0.08)
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Action 1: Play next
            MenuItemButton {
                text: I18n.tr("Phát tiếp theo", "Play next")
                iconSource: "../assets/icons/media-playlist-consecutive-symbolic.svg"
                onClicked: {
                    var t = root.track;
                    root.closeMenu();
                    if (t) root.playNextRequested(t);
                }
            }

            // Action 2: Add to queue
            MenuItemButton {
                text: I18n.tr("Thêm vào hàng đợi", "Add to queue")
                iconSource: "../assets/icons/view-queue-symbolic.svg"
                onClicked: {
                    var t = root.track;
                    root.closeMenu();
                    if (t) root.addToQueueRequested(t);
                }
            }

            // Action 3: Start radio
            MenuItemButton {
                text: I18n.tr("Phát Radio", "Start radio")
                iconSource: "../assets/icons/radio-symbolic.svg"
                onClicked: {
                    var t = root.track;
                    root.closeMenu();
                    if (t) root.startRadioRequested(t);
                }
            }

            // Action: Suggest Track to Host (Chỉ hiển thị khi đang nghe cùng Host)
            MenuItemButton {
                visible: typeof win !== "undefined" && win && win.listeningAlongFriend !== null && win.listeningAlongFriend !== undefined
                text: I18n.tr("Đề xuất cho Host", "Suggest to Host")
                iconSource: "../assets/icons/media-playlist-consecutive-symbolic.svg"
                textColor: root.accentColor
                iconColor: root.accentColor
                onClicked: {
                    var t = root.track;
                    root.closeMenu();
                    if (t && typeof win !== "undefined" && win && win.suggestTrackToHost) {
                        win.suggestTrackToHost(t);
                    }
                }
            }

            // Action: Add to playlist
            MenuItemButton {
                text: I18n.tr("Thêm vào danh sách phát", "Add to playlist")
                iconSource: "../assets/icons/folder-music-symbolic.svg"
                onClicked: {
                    root.isPlaylistSubmenuOpen = !root.isPlaylistSubmenuOpen;
                }
            }

            // Expandable Playlist choices
            Column {
                visible: root.isPlaylistSubmenuOpen
                width: parent.width
                spacing: 2

                MenuItemButton {
                    text: I18n.tr("+ Danh sách phát mới", "+ New Playlist")
                    iconSource: "../assets/icons/media-playlist-consecutive-symbolic.svg"
                    textColor: root.accentColor
                    iconColor: root.accentColor
                    onClicked: {
                        var t = root.track;
                        root.closeMenu();
                        if (t) root.createPlaylistWithTrackRequested(t);
                    }
                }

                Repeater {
                    model: root.customPlaylists || []
                    delegate: MenuItemButton {
                        text: modelData.title || modelData.name || I18n.tr("Danh sách phát", "Playlist")
                        iconSource: "../assets/icons/folder-music-symbolic.svg"
                        onClicked: {
                            var t = root.track;
                            var pid = modelData.id;
                            root.closeMenu();
                            if (t && pid) root.addToPlaylistRequested(t, pid);
                        }
                    }
                }
            }

            // Action: Go to artist
            MenuItemButton {
                visible: !!(root.track && (root.track.artist || root.track.author))
                text: I18n.tr("Đến trang nghệ sĩ", "Go to artist")
                iconSource: "../assets/icons/folder-music-symbolic.svg"
                onClicked: {
                    var t = root.track;
                    root.closeMenu();
                    if (t) root.viewArtistRequested(t);
                }
            }

            Rectangle {
                width: parent.width - 16
                height: 1
                color: Qt.rgba(1, 1, 1, 0.08)
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Action 4: Open folder (local) or Download (online)
            MenuItemButton {
                id: openOrDownloadBtn
                property string vid: {
                    if (!root.track) return "";
                    if (root.track.videoId) return String(root.track.videoId);
                    if (root.track.path && root.track.path.startsWith("ytdl://")) return root.track.path.replace("ytdl://", "");
                    return "";
                }
                property int dlRev: root.dlMgr ? root.dlMgr.revision : 0
                property bool isDownloaded: (dlRev >= 0 && root.dlMgr) ? !!root.dlMgr.isDownloaded(vid, root.track) : false
                property bool isLocal: isDownloaded || (root.track && root.track.path && !root.track.path.startsWith("ytdl://") && !root.track.path.startsWith("http://") && !root.track.path.startsWith("https://"))
                property bool isDownloading: (dlRev >= 0 && root.dlMgr && vid) ? !!root.dlMgr.isDownloading(vid) : false
                property real progress: (dlRev >= 0 && root.dlMgr && vid) ? root.dlMgr.getProgress(vid) : -1

                text: isLocal ? I18n.tr("Mở thư mục chứa file", "Open containing folder") : (isDownloading ? (I18n.tr("Đang tải (", "Downloading (") + Math.max(0, Math.round(progress)) + "%)...") : I18n.tr("Tải bài hát", "Download track"))
                iconSource: isLocal ? "../assets/icons/folder-music-symbolic.svg" : (isDownloading ? "../assets/icons/process-working-symbolic.svg" : "../assets/icons/download-symbolic.svg")
                textColor: isDownloading ? root.accentColor : Theme.textPrimary
                iconColor: isDownloading ? root.accentColor : Theme.textSecondary
                onClicked: {
                    if (isDownloading) return;
                    var t = root.track;
                    var local = isLocal;
                    root.closeMenu();
                    if (!t) return;
                    if (local) {
                        root.openFolderRequested(t);
                    } else {
                        root.downloadTrackRequested(t);
                    }
                }
            }

            Rectangle {
                width: parent.width - 16
                height: 1
                color: Qt.rgba(1, 1, 1, 0.08)
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.isQueueItem || openOrDownloadBtn.isLocal
            }

            // Action 5: Remove from Custom Playlist
            MenuItemButton {
                visible: typeof win !== "undefined" && win && win.currentView === "playlist" && win.activePlaylistId && win.activePlaylistId.startsWith("custom_")
                text: I18n.tr("Xóa khỏi danh sách phát", "Remove from playlist")
                textColor: "#ff5252"
                iconColor: "#ff5252"
                iconSource: "../assets/icons/user-trash-symbolic.svg"
                onClicked: {
                    var t = root.track;
                    var pid = (typeof win !== "undefined" && win) ? win.activePlaylistId : "";
                    root.closeMenu();
                    if (t && pid) root.removeFromPlaylistRequested(t, pid);
                }
            }

            // Action 6: Remove from Queue or Delete
            MenuItemButton {
                visible: root.isQueueItem || openOrDownloadBtn.isLocal
                text: root.isQueueItem ? I18n.tr("Xóa khỏi hàng đợi", "Remove from queue") : I18n.tr("Xóa khỏi thư viện", "Delete from library")
                textColor: "#ff5252"
                iconColor: "#ff5252"
                iconSource: "../assets/icons/user-trash-symbolic.svg"
                onClicked: {
                    var t = root.track;
                    var isQ = root.isQueueItem;
                    root.closeMenu();
                    if (!t) return;
                    if (isQ) {
                        root.removeFromQueueRequested(t);
                    } else {
                        root.deleteTrackRequested(t);
                    }
                }
            }
        }
    }

    component MenuItemButton: Rectangle {
        id: itemBtn
        width: parent ? parent.width - 8 : 214
        height: 32
        anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
        radius: 6
        color: btnHover.hovered ? Qt.rgba(1, 1, 1, 0.09) : "transparent"

        property string text: ""
        property string iconSource: ""
        property color textColor: Theme.textPrimary
        property color iconColor: Theme.textSecondary
        property string trailingIcon: ""
        property real trailingRotation: 0
        property real indent: 0
        signal clicked()

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10 + itemBtn.indent
            anchors.rightMargin: 10
            spacing: 10

            // Fixed 15px slot so rows without an icon (unticked sources) stay aligned
            Item {
                Layout.preferredWidth: 15
                Layout.preferredHeight: 15
                AppIcon {
                    anchors.centerIn: parent
                    visible: itemBtn.iconSource !== ""
                    source: itemBtn.iconSource
                    color: btnHover.hovered ? itemBtn.textColor : itemBtn.iconColor
                    iconSize: 15
                }
            }

            Text {
                Layout.fillWidth: true
                text: itemBtn.text
                color: itemBtn.textColor
                font.family: Theme.fontFamily
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            AppIcon {
                visible: itemBtn.trailingIcon !== ""
                source: itemBtn.trailingIcon
                color: Theme.textSecondary
                iconSize: 15
                rotation: itemBtn.trailingRotation
                Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }
        }

        HoverHandler {
            id: btnHover
            cursorShape: Qt.PointingHandCursor
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            preventStealing: true
            onPressed: mouse => mouse.accepted = true
            onReleased: mouse => mouse.accepted = true
            onClicked: mouse => {
                mouse.accepted = true;
                itemBtn.clicked();
            }
        }
    }
}
