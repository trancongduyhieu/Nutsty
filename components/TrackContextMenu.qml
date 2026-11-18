import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Quickshell.Io

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

    // ---- Lyrics source probe (Mochy-like): every source is asked as soon as the menu opens and each
    // row says what it found. Only sources that actually have lyrics for this song can be picked.
    // probeStates[key] = { status: "checking" | "ok" | "none", sync: "word" | "line" | "plain", duet }
    property var probeStates: ({})
    property string probeTrackKey: ""
    property bool probeRunning: false
    function startLyricsProbe() {
        var trk = root.track;
        if (!trk) return;
        var title = trk.title || trk.name || "";
        var artist = trk.artist || "";
        if (title === "") return;
        var key = title + "|" + artist;
        if (key === root.probeTrackKey && (root.probeRunning || Object.keys(root.probeStates).length > 0)) return;
        root.probeTrackKey = key;
        var st = {};
        for (var i = 1; i < root.lyricsSourceOptions.length; ++i) st[root.lyricsSourceOptions[i].key] = { status: "checking" };
        root.probeStates = st;
        var dur = (typeof win !== "undefined" && win && win.totalDuration > 1) ? String(Math.round(win.totalDuration)) : "";
        var appDir = (typeof win !== "undefined" && win && win.appDir) ? win.appDir : "";
        probeProc.running = false;
        probeProc.command = ["python3", "-u", appDir + "/backend/lyrics_helper.py", "--probe", title, artist, root.trackVid, dur];
        root.probeRunning = true;
        probeProc.running = true;
    }
    function probeDescription(key) {
        if (key === "auto") return I18n.tr("Tự chọn bản lời tốt nhất", "Picks the best lyrics for you");
        var st = root.probeStates[key];
        if (!st || st.status === "checking") return I18n.tr("Đang kiểm tra...", "Checking...");
        if (st.status !== "ok") return I18n.tr("Không có lời cho bài này", "No lyrics for this song");
        var d = st.sync === "word" ? I18n.tr("Đồng bộ theo từng chữ", "Word synced")
              : (st.sync === "line" ? I18n.tr("Đồng bộ theo từng câu", "Line synced") : I18n.tr("Không đồng bộ thời gian", "Not time-synced"));
        if (st.duet) d += I18n.tr(" · Song ca", " · Duet");
        return d;
    }
    Process {
        id: probeProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (!data || data.trim() === "") return;
                var obj;
                try { obj = JSON.parse(data); } catch (e) { return; }
                var st = Object.assign({}, root.probeStates);
                if (obj.done) {
                    for (var k in st) if (st[k].status === "checking") st[k] = { status: "none" };
                    root.probeStates = st;
                    root.probeRunning = false;
                    return;
                }
                if (!obj.key) return;
                st[obj.key] = obj.status === "ok" ? { status: "ok", sync: obj.sync, duet: !!obj.duet } : { status: "none" };
                root.probeStates = st;
            }
        }
        onExited: {
            if (!root.probeRunning) return;
            var st = Object.assign({}, root.probeStates);
            for (var k in st) if (st[k].status === "checking") st[k] = { status: "none" };
            root.probeStates = st;
            root.probeRunning = false;
        }
    }

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
        menuFlick.contentY = 0;
        if (root.showLyricsSource) root.startLyricsProbe();
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
        // Never taller than the window: with the lyrics sources expanded the list scrolls instead
        height: Math.min(menuCol.implicitHeight + 16, root.height - 24)
        radius: 10
        clip: true
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

        Flickable {
            id: menuFlick
            anchors.fill: parent
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            contentWidth: width
            contentHeight: menuCol.implicitHeight
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            clip: true

        Column {
            id: menuCol
            width: menuFlick.width
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
                            sourceSize: Qt.size(64, 64)
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
                    delegate: Rectangle {
                        id: srcRow
                        required property var modelData
                        readonly property string key: modelData.key
                        readonly property bool active: key === root.currentLyricsSource
                        readonly property var st: root.probeStates[key]
                        readonly property bool checking: key !== "auto" && (!st || st.status === "checking")
                        readonly property bool available: key === "auto" || (!!st && st.status === "ok")
                        width: parent.width - 8
                        height: 42
                        anchors.horizontalCenter: parent.horizontalCenter
                        radius: 8
                        color: (srcHover.hovered && available && !active) ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14) : "transparent"
                        opacity: (available || checking) ? 1.0 : 0.42
                        Behavior on opacity { NumberAnimation { duration: 180 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 24
                            anchors.rightMargin: 10
                            spacing: 10
                            // Fixed slot: tick for the active source, a small morphing loader while checking
                            Item {
                                Layout.preferredWidth: 15
                                Layout.preferredHeight: 15
                                AppIcon {
                                    anchors.centerIn: parent
                                    visible: srcRow.active
                                    source: "../assets/icons/material/ms-check.svg"
                                    color: root.accentColor
                                    iconSize: 15
                                }
                                ShapeLoader {
                                    anchors.centerIn: parent
                                    visible: !srcRow.active && srcRow.checking
                                    running: visible && root.isOpen
                                    size: 14
                                    color: root.accentColor
                                }
                            }
                            Column {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    width: parent.width
                                    text: srcRow.modelData.name
                                    color: srcRow.active ? root.accentColor : Theme.textPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.weight: srcRow.active ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: root.probeDescription(srcRow.key)
                                    color: (srcRow.st && srcRow.st.status === "ok" && srcRow.st.sync === "word") ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.9) : Theme.textSecondary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }
                        }
                        HoverHandler {
                            id: srcHover
                            cursorShape: (srcRow.available && !srcRow.active) ? Qt.PointingHandCursor : Qt.ArrowCursor
                        }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            preventStealing: true
                            enabled: srcRow.available && !srcRow.active
                            onPressed: mouse => mouse.accepted = true
                            onReleased: mouse => mouse.accepted = true
                            onClicked: mouse => {
                                mouse.accepted = true;
                                var key = srcRow.key;
                                root.closeMenu();
                                root.lyricsSourceSelected(key);
                            }
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
                text: I18n.tr("Phát đài", "Start radio")
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
        ScrollEdgeFade {
            flickable: menuFlick
            fadeLength: 16
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
