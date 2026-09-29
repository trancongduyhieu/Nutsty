import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import "."

Rectangle {
    id: root
    color: "transparent"

    property var tracks: []
    property var currentTrack: null
    property bool isPlaying: false
    property bool isLoadingAudio: false
    property string sectionTitle: "Featured & Popular"
    property bool isLoading: false
    signal trackPlayRequested(var trk)
    signal trackDetailsRequested(var trk)
    signal trackContextMenuRequested(var trk, real globalX, real globalY)
    signal playAllRequested()
    signal shufflePlayRequested()
    signal addAlbumToQueueRequested(var tracks)
    signal downloadAlbumRequested(var tracks)
    signal albumSelected(var album)
    signal batchDeleteRequested(var paths)
    signal createPlaylistRequested(var tracks)
    signal playlistSelected(var playlist)
    signal playPlaylistRequested(var playlist, bool shuffle)
    signal editPlaylistRequested(var playlist)
    signal deletePlaylistRequested(string plId)
    signal toggleFavoritePlaylistRequested(var playlist)
    signal spotifyImportRequested()

    property var albumMetadata: null
    property string downloadsSubTab: "tracks" // "tracks", "playlists", "favorites"
    onDownloadsSubTabChanged: {
        if (sortPopover.isOpen) {
            sortPopover.isOpen = false;
        }
        if (downloadsSubTab === "tracks" && typeof win !== "undefined" && win) {
            win.browsingTracks = win.allTracks;
        }
        if (typeof win !== "undefined" && win) {
            win.lastLibrarySubTab = downloadsSubTab;
        }
    }
    property var localAlbums: []
    property var customPlaylists: []
    property var favoritePlaylists: (typeof win !== "undefined" && win.favoritePlaylists) ? win.favoritePlaylists : []

    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent

    readonly property bool isDownloadsView: root.sectionTitle.includes("Download") || (typeof win !== "undefined" && win && win.currentView === "library")
    readonly property bool isPlaylistView: typeof win !== "undefined" && win && win.currentView === "playlist"
    property string sortBy: "recent" // "recent", "title", "artist"
    property bool isSelectionMode: false
    property var selectedTrackPaths: []

    function toggleSortPopover() {
        if (sortPopover.isOpen) {
            sortPopover.isOpen = false;
        } else {
            var pt = sortDropdownBtn.mapToItem(root, 0, sortDropdownBtn.height + 6);
            sortPopover.targetX = Math.max(12, Math.min(pt.x + sortDropdownBtn.width - sortPopover.popoverWidth, root.width - sortPopover.popoverWidth - 12));
            sortPopover.targetY = pt.y;
            sortPopover.isOpen = true;
        }
    }

    function toggleTrackSelection(trk) {
        if (!trk || !trk.path) return;
        var p = trk.path;
        var idx = selectedTrackPaths.indexOf(p);
        var updated = selectedTrackPaths.slice();
        if (idx !== -1) {
            updated.splice(idx, 1);
        } else {
            updated.push(p);
        }
        selectedTrackPaths = updated;
    }

    function selectAllTracks() {
        var arr = [];
        for (var i = 0; i < sortedTracks.length; i++) {
            if (sortedTracks[i] && sortedTracks[i].path) {
                arr.push(sortedTracks[i].path);
            }
        }
        selectedTrackPaths = arr;
    }

    function clearSelection() {
        selectedTrackPaths = [];
    }

    function getSelectedTracks() {
        var arr = [];
        for (var i = 0; i < sortedTracks.length; i++) {
            var t = sortedTracks[i];
            if (t && selectedTrackPaths.indexOf(t.path) !== -1) {
                arr.push(t);
            }
        }
        return arr;
    }

    function parseDurationSecs(d) {
        if (!d) return 0;
        if (typeof d === "number") return d;
        var parts = String(d).split(":");
        if (parts.length === 2) {
            return (parseInt(parts[0], 10) || 0) * 60 + (parseInt(parts[1], 10) || 0);
        } else if (parts.length === 3) {
            return (parseInt(parts[0], 10) || 0) * 3600 + (parseInt(parts[1], 10) || 0) * 60 + (parseInt(parts[2], 10) || 0);
        }
        return 0;
    }

    readonly property var sortedTracks: {
        if (!root.tracks || root.tracks.length === 0) return [];
        var list = root.tracks.slice();
        if (sortBy === "recent") {
            if (isDownloadsView) {
                list.sort((a, b) => (b.mtime || 0) - (a.mtime || 0));
            }
        } else if (sortBy === "oldest") {
            if (isDownloadsView) {
                list.sort((a, b) => (a.mtime || 0) - (b.mtime || 0));
            } else {
                list.reverse();
            }
        } else if (sortBy === "title") {
            list.sort((a, b) => (a.name || a.title || "").localeCompare(b.name || b.title || ""));
        } else if (sortBy === "artist") {
            list.sort((a, b) => (a.artist || "").localeCompare(b.artist || ""));
        } else if (sortBy === "duration") {
            list.sort((a, b) => {
                var da = a.durationMs || root.parseDurationSecs(a.duration);
                var db = b.durationMs || root.parseDurationSecs(b.duration);
                return db - da;
            });
        }
        return list;
    }

    Flickable {
        id: scrollArea
        anchors.fill: parent
        anchors.margins: 20
        contentWidth: width
        contentHeight: contentCol.implicitHeight + 110
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        ColumnLayout {
            id: contentCol
            width: scrollArea.width
            spacing: 14

            // Section 1: Header Row

                // Hero Album Banner (When viewing an Album or detailed Playlist)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 24
                    visible: root.albumMetadata !== null

                    // 1. Large Cover Art (160x160) with elegant shadow and subtle glow
                    Item {
                        Layout.preferredWidth: 160
                        Layout.preferredHeight: 160

                        Rectangle {
                            id: albumHeroMask
                            anchors.fill: parent
                            radius: 8
                            color: "#ffffff"
                            visible: false
                            layer.enabled: true
                        }

                        Item {
                            anchors.fill: parent
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: albumHeroMask
                                autoPaddingEnabled: false
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: "#242424"
                            }

                            Image {
                                id: albumHeroCover
                                anchors.fill: parent
                                source: {
                                    if (!root.albumMetadata || !root.albumMetadata.image) return "";
                                    var s = root.albumMetadata.image;
                                    return (s.startsWith("/") && !s.startsWith("file://")) ? ("file://" + s) : s;
                                }
                                fillMode: Image.PreserveAspectCrop
                                scale: (implicitWidth > 0 && implicitHeight > 0 && (implicitWidth / implicitHeight > 1.25)) ? 1.48 : 1.0
                                transformOrigin: Item.Center
                                asynchronous: true
                            }

                            Rectangle {
                                anchors.fill: parent
                                visible: !albumHeroCover.visible || albumHeroCover.status !== Image.Ready
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "#3a2255" }
                                    GradientStop { position: 1.0; color: "#1a1a1a" }
                                }
                                AppIcon {
                                    anchors.centerIn: parent
                                    source: "../assets/icons/media-optical-audio-symbolic.svg"
                                    iconSize: 54
                                    color: Qt.rgba(1, 1, 1, 0.25)
                                }
                            }
                        }

                        // 1px Hairline Border Overlay
                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: "transparent"
                            border.color: Qt.rgba(1, 1, 1, 0.12)
                            border.width: 1
                            z: 2
                        }
                    }

                    // 2. Album Details & Metadata Column
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 8

                        // Badge: ALBUM / SINGLE / EP
                        Rectangle {
                            height: 22
                            width: badgeText.implicitWidth + 14
                            radius: 4
                            color: Qt.rgba(1, 1, 1, 0.12)

                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: (root.albumMetadata && root.albumMetadata.type ? root.albumMetadata.type : "ALBUM").toUpperCase()
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.bold: true
                                color: "#ffffff"
                            }
                        }

                        // Album Title (Big & Bold)
                        Text {
                            Layout.fillWidth: true
                            text: root.albumMetadata ? (root.albumMetadata.title || root.albumMetadata.name || "") : ""
                            font.family: Theme.fontFamily
                            font.pixelSize: 26
                            font.bold: true
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                        }

                        // Subtitle: Artist • Year • Track count • Duration
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: root.albumMetadata ? (root.albumMetadata.artist || "Unknown Artist") : ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                color: "#ffffff"
                            }

                            Text {
                                visible: root.albumMetadata && !!root.albumMetadata.year
                                text: "•"
                                color: Theme.textSecondary
                                font.pixelSize: 12
                            }

                            Text {
                                visible: root.albumMetadata && !!root.albumMetadata.year
                                text: root.albumMetadata ? root.albumMetadata.year : ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                color: Theme.textSecondary
                            }

                            Text {
                                text: "•"
                                color: Theme.textSecondary
                                font.pixelSize: 12
                            }

                            Text {
                                text: (root.sortedTracks ? root.sortedTracks.length : 0) + I18n.tr(" bài hát", " songs")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                color: Theme.textSecondary
                            }

                            Text {
                                visible: root.albumMetadata && !!root.albumMetadata.duration
                                text: "•"
                                color: Theme.textSecondary
                                font.pixelSize: 12
                            }

                            Text {
                                visible: root.albumMetadata && !!root.albumMetadata.duration
                                text: root.albumMetadata ? root.albumMetadata.duration : ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                color: Theme.textSecondary
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.albumMetadata ? root.albumMetadata.description : ""
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.textSecondary
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            visible: text !== ""
                        }
                    }
                }

                // Normal View Header: Title, Count & View Options (Downloads Sub-tabs)
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.albumMetadata === null
                    spacing: 16

                    // Title & Static Count
                    RowLayout {
                        spacing: 12

                        Text {
                            text: {
                                if (!root.isDownloadsView) return root.sectionTitle;
                                if (root.downloadsSubTab === "playlists") return I18n.tr("Danh sách phát cá nhân của bạn", "Your Personal Playlists");
                                if (root.downloadsSubTab === "favorites") return I18n.tr("Danh sách phát yêu thích", "Favorite Playlists");
                                return I18n.tr("Tải xuống", "Downloads");
                            }
                            font.family: Theme.fontFamily
                            font.pixelSize: 28
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        // Plain static text (No capsule, no border)
                        Text {
                            visible: {
                                if (!root.isDownloadsView) return false;
                                if (root.downloadsSubTab === "tracks") return true;
                                if (root.downloadsSubTab === "favorites") return (root.favoritePlaylists && root.favoritePlaylists.length > 0);
                                return false; // In playlists, hide count text completely as requested!
                            }
                            text: {
                                if (root.downloadsSubTab === "tracks") {
                                    return (root.sortedTracks ? root.sortedTracks.length : 0) + I18n.tr(" bài hát", " songs");
                                }
                                if (root.downloadsSubTab === "favorites") {
                                    return (root.favoritePlaylists ? root.favoritePlaylists.length : 0) + I18n.tr(" danh sách phát", " playlists");
                                }
                                return "";
                            }
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: false
                            color: Theme.textSecondary
                            Layout.alignment: Qt.AlignBaseline
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Downloads Sub-tab Switcher: Ambient Fluid Text [ Bài hát | Danh sách phát | Yêu thích ]
                    Row {
                        visible: root.isDownloadsView
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        spacing: 6

                        // Subtab 1: Bài hát
                        Rectangle {
                            implicitWidth: trksText.implicitWidth + 24
                            implicitHeight: 30
                            width: implicitWidth
                            height: implicitHeight
                            radius: 15
                            color: root.downloadsSubTab === "tracks" 
                                   ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18) 
                                   : (trksH.hovered ? Qt.rgba(1, 1, 1, 0.07) : "transparent")
                            border.color: root.downloadsSubTab === "tracks" 
                                          ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.40) 
                                          : "transparent"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                            HoverHandler { id: trksH }

                            Text {
                                id: trksText
                                anchors.centerIn: parent
                                text: I18n.tr("Bài hát", "Songs")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: root.downloadsSubTab === "tracks"
                                color: root.downloadsSubTab === "tracks" ? root.accentColor : (trksH.hovered ? "#ffffff" : Theme.textSecondary)
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.downloadsSubTab = "tracks";
                                    if (typeof win !== "undefined" && win) {
                                        win.browsingTracks = win.allTracks;
                                    }
                                }
                            }
                        }

                        // Subtab 2: Danh sách phát
                        Rectangle {
                            implicitWidth: plsText.implicitWidth + 24
                            implicitHeight: 30
                            width: implicitWidth
                            height: implicitHeight
                            radius: 15
                            color: root.downloadsSubTab === "playlists" 
                                   ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18) 
                                   : (plsH.hovered ? Qt.rgba(1, 1, 1, 0.07) : "transparent")
                            border.color: root.downloadsSubTab === "playlists" 
                                          ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.40) 
                                          : "transparent"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                            HoverHandler { id: plsH }

                            Text {
                                id: plsText
                                anchors.centerIn: parent
                                text: I18n.tr("Danh sách phát", "Playlists")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: root.downloadsSubTab === "playlists"
                                color: root.downloadsSubTab === "playlists" ? root.accentColor : (plsH.hovered ? "#ffffff" : Theme.textSecondary)
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.downloadsSubTab = "playlists"
                            }
                        }

                        // Subtab 3: Yêu thích (Favorite Playlists)
                        Rectangle {
                            implicitWidth: favsText.implicitWidth + 24
                            implicitHeight: 30
                            width: implicitWidth
                            height: implicitHeight
                            radius: 15
                            color: root.downloadsSubTab === "favorites" 
                                   ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18) 
                                   : (favsH.hovered ? Qt.rgba(1, 1, 1, 0.07) : "transparent")
                            border.color: root.downloadsSubTab === "favorites" 
                                          ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.40) 
                                          : "transparent"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                            HoverHandler { id: favsH }

                            Text {
                                id: favsText
                                anchors.centerIn: parent
                                text: I18n.tr("Yêu thích", "Favorites")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: root.downloadsSubTab === "favorites"
                                color: root.downloadsSubTab === "favorites" ? root.accentColor : (favsH.hovered ? "#ffffff" : Theme.textSecondary)
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.downloadsSubTab = "favorites"
                            }
                        }
                    }

                    Text {
                        visible: !root.isDownloadsView && !root.isLoading
                        text: (root.sortedTracks ? root.sortedTracks.length + I18n.tr(" bài", " tracks") : "")
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.textSecondary
                    }
                }

                // Unified Toolbar: Play All, Shuffle Play, Sort Options
                RowLayout {
                    Layout.fillWidth: true
                    visible: (root.isDownloadsView && root.downloadsSubTab === "tracks" && root.albumMetadata === null) || (root.isPlaylistView && root.sortedTracks && root.sortedTracks.length > 0)
                    spacing: 12

                    // Primary Play All Button (Emerald Green Solid)
                    Rectangle {
                        id: playBtn
                        implicitHeight: 36
                        implicitWidth: playRow.implicitWidth + 28
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: implicitWidth
                        radius: 18
                        color: playH.hovered ? Qt.lighter(root.accentColor, 1.15) : root.accentColor
                        scale: playH.hovered ? 1.03 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Row {
                            id: playRow
                            anchors.centerIn: parent
                            spacing: 8

                            AppIcon {
                                source: "../assets/icons/media-playback-start-symbolic.svg"
                                iconSize: 15
                                anchors.verticalCenter: parent.verticalCenter
                                color: (root.accentColor.r * 0.299 + root.accentColor.g * 0.587 + root.accentColor.b * 0.114) > 0.6 ? "#0c0d10" : "#ffffff"
                            }

                            Text {
                                text: I18n.tr("Phát", "Play")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                                color: (root.accentColor.r * 0.299 + root.accentColor.g * 0.587 + root.accentColor.b * 0.114) > 0.6 ? "#0c0d10" : "#ffffff"
                            }
                        }

                        HoverHandler { id: playH }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.playAllRequested()
                        }
                    }

                    // Shuffle Play Button (Secondary Glass Style)
                    Rectangle {
                        id: shuffleBtn
                        implicitHeight: 36
                        implicitWidth: shuffleRow.implicitWidth + 28
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: implicitWidth
                        radius: 18
                        color: shufH.hovered ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1
                        scale: shufH.hovered ? 1.03 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100 } }

                        Row {
                            id: shuffleRow
                            anchors.centerIn: parent
                            spacing: 8

                            AppIcon {
                                source: "../assets/icons/media-playlist-shuffle-symbolic.svg"
                                iconSize: 15
                                anchors.verticalCenter: parent.verticalCenter
                                color: "#ffffff"
                            }

                            Text {
                                text: I18n.tr("Phát ngẫu nhiên", "Shuffle")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                                color: "#ffffff"
                            }
                        }

                        HoverHandler { id: shufH }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.shufflePlayRequested()
                        }
                    }

                    // Add All to Queue Button
                    Rectangle {
                        id: queueBtn
                        implicitHeight: 36
                        implicitWidth: queueRow.implicitWidth + 28
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: implicitWidth
                        radius: 18
                        visible: root.albumMetadata !== null || root.isPlaylistView
                        color: qH.hovered ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1
                        scale: qH.hovered ? 1.03 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100 } }

                        Row {
                            id: queueRow
                            anchors.centerIn: parent
                            spacing: 8

                            AppIcon {
                                source: "../assets/icons/list-add-symbolic.svg"
                                iconSize: 15
                                anchors.verticalCenter: parent.verticalCenter
                                color: "#ffffff"
                            }

                            Text {
                                text: I18n.tr("Hàng đợi", "Queue")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                                color: "#ffffff"
                            }
                        }

                        HoverHandler { id: qH }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.addAlbumToQueueRequested(root.sortedTracks)
                        }
                    }

                    // Download Entire Album Button
                    Rectangle {
                        id: dlAlbBtn
                        implicitHeight: 36
                        implicitWidth: dlAlbRow.implicitWidth + 28
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: implicitWidth
                        radius: 18
                        visible: root.albumMetadata !== null && (!root.albumMetadata.isLocal)
                        color: dlAlbH.hovered ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1
                        scale: dlAlbH.hovered ? 1.03 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100 } }

                        Row {
                            id: dlAlbRow
                            anchors.centerIn: parent
                            spacing: 8

                            AppIcon {
                                source: "../assets/icons/download-symbolic.svg"
                                iconSize: 15
                                anchors.verticalCenter: parent.verticalCenter
                                color: "#ffffff"
                            }

                            Text {
                                text: I18n.tr("Tải Album", "Download Album")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                                color: "#ffffff"
                            }
                        }

                        HoverHandler { id: dlAlbH }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.downloadAlbumRequested(root.sortedTracks)
                        }
                    }

                    // Favorite / Like Playlist Button (when viewing a playlist or album)
                    Rectangle {
                        id: favPlBtn
                        readonly property string currentPlId: (typeof win !== "undefined" && win.activePlaylistId) ? win.activePlaylistId : (root.albumMetadata ? (root.albumMetadata.id || root.albumMetadata.browseId) : "")
                        readonly property bool isFav: (typeof win !== "undefined" && win.isPlaylistFavorite) 
                                                      ? win.isPlaylistFavorite(favPlBtn.currentPlId)
                                                      : false
                        implicitHeight: 36
                        implicitWidth: favPlRow.implicitWidth + 28
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: implicitWidth
                        radius: 18
                        visible: root.isPlaylistView || root.albumMetadata !== null
                        color: isFav 
                               ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                               : (favPlH.hovered ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08))
                        border.color: isFav ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.5) : Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1
                        scale: favPlH.hovered ? 1.03 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        Row {
                            id: favPlRow
                            anchors.centerIn: parent
                            spacing: 8

                            AppIcon {
                                source: "../assets/icons/emblem-favorite-symbolic.svg"
                                iconSize: 15
                                anchors.verticalCenter: parent.verticalCenter
                                color: favPlBtn.isFav ? root.accentColor : "#ffffff"
                            }

                            Text {
                                text: favPlBtn.isFav ? I18n.tr("Đã thích", "Favorited") : I18n.tr("Yêu thích", "Favorite")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                                color: favPlBtn.isFav ? root.accentColor : "#ffffff"
                            }
                        }

                        HoverHandler { id: favPlH }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var pid = favPlBtn.currentPlId;
                                var plObj = {
                                    id: pid,
                                    playlistId: pid,
                                    browseId: pid,
                                    title: root.sectionTitle || (root.albumMetadata ? (root.albumMetadata.title || root.albumMetadata.name) : "Playlist"),
                                    name: root.sectionTitle || (root.albumMetadata ? (root.albumMetadata.title || root.albumMetadata.name) : "Playlist"),
                                    subtitle: root.albumMetadata ? (root.albumMetadata.artist || "") : "",
                                    artist: root.albumMetadata ? (root.albumMetadata.artist || "") : "",
                                    image: (root.albumMetadata && root.albumMetadata.image) ? root.albumMetadata.image : (root.sortedTracks && root.sortedTracks.length > 0 ? (root.sortedTracks[0].image || "") : ""),
                                    type: root.albumMetadata ? "album" : "playlist",
                                    trackCount: root.sortedTracks ? root.sortedTracks.length : 0,
                                    tracks: root.sortedTracks || []
                                };
                                root.toggleFavoritePlaylistRequested(plObj);
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Modern Minimalist Dropdown Pill for Sort (Liquid Glass Dynamic Accent Tint)
                    Rectangle {
                        id: sortDropdownBtn
                        implicitHeight: 34
                        implicitWidth: sortBtnRow.implicitWidth + 24
                        Layout.preferredHeight: 34
                        Layout.preferredWidth: implicitWidth
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        radius: 17
                        color: sortPopover.isOpen 
                               ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22) 
                               : (sortBtnH.hovered 
                                  ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14) 
                                  : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.08))
                        border.color: sortPopover.isOpen 
                                      ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.65) 
                                      : (sortBtnH.hovered 
                                         ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.38) 
                                         : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20))
                        border.width: 1
                        scale: sortBtnH.hovered && !sortPopover.isOpen ? 1.02 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        Row {
                            id: sortBtnRow
                            anchors.centerIn: parent
                            spacing: 7

                            AppIcon {
                                source: "../assets/icons/view-sort-symbolic.svg"
                                iconSize: 13
                                anchors.verticalCenter: parent.verticalCenter
                                color: (sortPopover.isOpen || sortBtnH.hovered) 
                                       ? root.accentColor 
                                       : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.90)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            Text {
                                text: {
                                    if (root.sortBy === "recent") return I18n.tr("Mới nhất", "Latest");
                                    if (root.sortBy === "oldest") return I18n.tr("Cũ nhất", "Oldest");
                                    if (root.sortBy === "title") return I18n.tr("Tên A-Z", "Title A-Z");
                                    if (root.sortBy === "artist") return I18n.tr("Nghệ sĩ", "Artist");
                                    if (root.sortBy === "duration") return I18n.tr("Thời lượng", "Duration");
                                    return I18n.tr("Sắp xếp", "Sort");
                                }
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                                color: (sortPopover.isOpen || sortBtnH.hovered) ? root.accentColor : "#ffffff"
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            AppIcon {
                                source: "../assets/icons/go-down-symbolic.svg"
                                iconSize: 9
                                anchors.verticalCenter: parent.verticalCenter
                                color: sortPopover.isOpen 
                                       ? root.accentColor 
                                       : (sortBtnH.hovered ? root.accentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.70))
                                rotation: sortPopover.isOpen ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                        }

                        HoverHandler { id: sortBtnH }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (sortPopover.isOpen) {
                                    sortPopover.isOpen = false;
                                } else {
                                    var pt = sortDropdownBtn.mapToItem(root, 0, sortDropdownBtn.height + 6);
                                    sortPopover.targetX = Math.max(12, Math.min(pt.x + sortDropdownBtn.width - sortPopover.popoverWidth, root.width - sortPopover.popoverWidth - 12));
                                    sortPopover.targetY = pt.y;
                                    sortPopover.isOpen = true;
                                }
                            }
                        }
                    }
                }

                // Multi-Select Action Bar (Floating Dark Glass banner matching wallpaper theme)
                Rectangle {
                    Layout.fillWidth: true
                    height: 48
                    radius: 12
                    color: Qt.rgba(0.08, 0.08, 0.10, 0.90)
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                    border.width: 1
                    visible: root.isDownloadsView && root.isSelectionMode

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12

                        // Accent-tinted Selection Count Badge
                        Rectangle {
                            height: 28
                            width: selBadgeRow.implicitWidth + 16
                            radius: 14
                            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                            border.width: 1

                            RowLayout {
                                id: selBadgeRow
                                anchors.centerIn: parent
                                spacing: 6

                                AppIcon {
                                    source: "../assets/icons/emblem-ok-symbolic.svg"
                                    iconSize: 12
                                    color: root.accentColor
                                }

                                Text {
                                    text: I18n.tr("Đã chọn: ", "Selected: ") + root.selectedTrackPaths.length + I18n.tr(" bài", " songs")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: root.accentColor
                                }
                            }
                        }

                        // Button: Select All
                        Rectangle {
                            height: 28
                            width: selAllText.implicitWidth + 20
                            radius: 14
                            color: selAllH.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                            border.color: Qt.rgba(1, 1, 1, 0.10)
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 100 } }

                            Text {
                                id: selAllText
                                anchors.centerIn: parent
                                text: I18n.tr("Chọn tất cả", "Select All")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                color: "#ffffff"
                            }
                            HoverHandler { id: selAllH }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectAllTracks()
                            }
                        }

                        // Button: Clear Selection
                        Rectangle {
                            height: 28
                            width: clearSelText.implicitWidth + 20
                            radius: 14
                            color: clearSelH.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                            border.color: Qt.rgba(1, 1, 1, 0.10)
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 100 } }

                            Text {
                                id: clearSelText
                                anchors.centerIn: parent
                                text: I18n.tr("Bỏ chọn", "Deselect")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.textSecondary
                            }
                            HoverHandler { id: clearSelH }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.clearSelection()
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Button: Create Custom Playlist from Selected (Harmonized with Wallpaper Accent)
                        Rectangle {
                            height: 32
                            width: createPlRow.implicitWidth + 22
                            radius: 16
                            color: createPlH.hovered ? Qt.lighter(root.accentColor, 1.15) : root.accentColor
                            visible: root.selectedTrackPaths.length > 0
                            Behavior on color { ColorAnimation { duration: 100 } }

                            readonly property bool isDarkAccent: (root.accentColor.r * 0.299 + root.accentColor.g * 0.587 + root.accentColor.b * 0.114) > 0.55

                            RowLayout {
                                id: createPlRow
                                anchors.centerIn: parent
                                spacing: 6

                                AppIcon {
                                    source: "../assets/icons/folder-music-symbolic.svg"
                                    iconSize: 13
                                    color: parent.parent.isDarkAccent ? "#000000" : "#ffffff"
                                }

                                Text {
                                    text: I18n.tr("+ Tạo danh sách phát", "+ New Playlist")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: parent.parent.isDarkAccent ? "#000000" : "#ffffff"
                                }
                            }

                            HoverHandler { id: createPlH }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.createPlaylistRequested(root.getSelectedTracks());
                                }
                            }
                        }

                        // Button: Delete Selected (Sophisticated Crimson Glass)
                        Rectangle {
                            height: 32
                            width: delSelRow.implicitWidth + 22
                            radius: 16
                            color: delSelH.hovered ? Qt.rgba(0.85, 0.25, 0.30, 0.32) : Qt.rgba(0.85, 0.25, 0.30, 0.20)
                            border.color: Qt.rgba(0.85, 0.25, 0.30, 0.50)
                            border.width: 1
                            visible: root.selectedTrackPaths.length > 0
                            Behavior on color { ColorAnimation { duration: 100 } }

                            RowLayout {
                                id: delSelRow
                                anchors.centerIn: parent
                                spacing: 6

                                AppIcon {
                                    source: "../assets/icons/user-trash-symbolic.svg"
                                    iconSize: 13
                                    color: "#ff8888"
                                }

                                Text {
                                    text: I18n.tr("Xóa (", "Delete (") + root.selectedTrackPaths.length + ")"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: "#ff8888"
                                }
                            }

                            HoverHandler { id: delSelH }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.batchDeleteRequested(root.selectedTrackPaths);
                                }
                            }
                        }

                        // Button: Exit selection mode
                        Rectangle {
                            width: 28
                            height: 28
                            radius: 14
                            color: exitSelH.hovered ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }

                            HoverHandler { id: exitSelH }

                            AppIcon {
                                anchors.centerIn: parent
                                source: "../assets/icons/window-close-symbolic.svg"
                                iconSize: 13
                                color: exitSelH.hovered ? "#ffffff" : Theme.textSecondary
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.isSelectionMode = false;
                                    root.clearSelection();
                                }
                            }
                        }
                    }
                }

                // Skeleton Lazy Loading Grid (Pure Visual Shimmer, Matching TrackCard 176x250 Grid)
                Flow {
                    Layout.fillWidth: true
                    spacing: 16
                    visible: root.isLoading

                    Repeater {
                        model: [
                            { tw: 120, sw: 80 },
                            { tw: 140, sw: 95 },
                            { tw: 110, sw: 75 },
                            { tw: 130, sw: 85 },
                            { tw: 125, sw: 90 },
                            { tw: 135, sw: 80 },
                            { tw: 115, sw: 70 },
                            { tw: 145, sw: 100 },
                            { tw: 120, sw: 85 },
                            { tw: 130, sw: 75 }
                        ]

                        SkeletonTrackCard {
                            titleWidth: modelData.tw
                            subtitleWidth: modelData.sw
                        }
                    }
                }

                Text {
                    visible: !root.isLoading && (!root.sortedTracks || root.sortedTracks.length === 0) && (!root.isDownloadsView || root.downloadsSubTab === "tracks")
                    text: root.isPlaylistView ? I18n.tr("Danh sách phát này đang trống. Thêm bài hát bằng menu chuột phải!", "This playlist is empty. Add songs using the context menu on any song!") : I18n.tr("Không tìm thấy bài hát nào. Nhập vào thanh tìm kiếm để khám phá!", "No tracks found. Type in search bar to explore online tracks!")
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    color: Theme.textSecondary
                }

                // Custom Playlists Grid (when in Downloads view and Playlists sub-tab is selected)
                Flow {
                    Layout.fillWidth: true
                    spacing: 16
                    visible: root.isDownloadsView && root.downloadsSubTab === "playlists" && root.albumMetadata === null

                    // 1. Create New Playlist Card
                    Rectangle {
                        width: 176
                        height: 250
                        radius: Theme.radiusCard
                        color: createCardMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.06) : Qt.rgba(1.0, 1.0, 1.0, 0.02)
                        border.color: createCardMouse.containsMouse ? root.accentColor : Qt.rgba(1.0, 1.0, 1.0, 0.12)
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 12

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: width
                                radius: 10
                                color: createCardMouse.containsMouse 
                                       ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18) 
                                       : Qt.rgba(255, 255, 255, 0.04)
                                border.color: Qt.rgba(255, 255, 255, 0.1)
                                border.width: 1

                                Behavior on color { ColorAnimation { duration: 150 } }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 8

                                    Rectangle {
                                        Layout.alignment: Qt.AlignHCenter
                                        width: 44
                                        height: 44
                                        radius: 22
                                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25)
                                        border.color: root.accentColor
                                        border.width: 1

                                        AppIcon {
                                            anchors.centerIn: parent
                                            source: "../assets/icons/list-add-symbolic.svg"
                                            iconSize: 20
                                            color: root.accentColor
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                Text {
                                    Layout.fillWidth: true
                                    text: I18n.tr("Tạo danh sách mới", "Create Playlist")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    color: createCardMouse.containsMouse ? root.accentColor : "#ffffff"
                                    elide: Text.ElideRight
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: I18n.tr("Thêm bài hát tùy thích", "Add favorite tracks")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.textSecondary
                                    elide: Text.ElideRight
                                }
                            }

                            Item { Layout.fillHeight: true }
                        }

                        MouseArea {
                            id: createCardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.createPlaylistRequested([])
                        }
                    }

                    // 1b. Action Card: Nhập từ Spotify
                    Rectangle {
                        id: spotifyImportCard
                        width: 176
                        height: 250
                        radius: Theme.radiusCard
                        color: spotifyCardMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12) : Qt.rgba(1.0, 1.0, 1.0, 0.02)
                        border.color: spotifyCardMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.4) : Qt.rgba(1.0, 1.0, 1.0, 0.06)
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: width
                                radius: 10
                                color: spotifyCardMouse.containsMouse 
                                       ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22) 
                                       : Qt.rgba(255, 255, 255, 0.04)
                                border.color: Qt.rgba(255, 255, 255, 0.1)
                                border.width: 1

                                Behavior on color { ColorAnimation { duration: 150 } }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 8

                                    Rectangle {
                                        Layout.alignment: Qt.AlignHCenter
                                        width: 44
                                        height: 44
                                        radius: 22
                                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25)
                                        border.color: root.accentColor
                                        border.width: 1

                                        AppIcon {
                                            anchors.centerIn: parent
                                            source: "../assets/icons/media-playlist-consecutive-symbolic.svg"
                                            iconSize: 20
                                            color: root.accentColor
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                Text {
                                    Layout.fillWidth: true
                                    text: I18n.tr("Nhập từ Spotify", "Import from Spotify")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    color: spotifyCardMouse.containsMouse ? root.accentColor : "#ffffff"
                                    elide: Text.ElideRight
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: I18n.tr("Chuyển giao playlist", "Transfer playlist")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.textSecondary
                                    elide: Text.ElideRight
                                }
                            }

                            Item { Layout.fillHeight: true }
                        }

                        MouseArea {
                            id: spotifyCardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.spotifyImportRequested()
                        }
                    }

                    // 2. Playlists Cards
                    Repeater {
                        model: root.customPlaylists

                        Rectangle {
                            id: plCard
                            readonly property var plData: modelData
                            width: 176
                            height: 250
                            radius: Theme.radiusCard
                            color: plCardMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.06) : Qt.rgba(1.0, 1.0, 1.0, 0.02)
                            border.color: plCardMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.18) : Qt.rgba(1.0, 1.0, 1.0, 0.06)
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            // Card Background Click Area (z: 0)
                            MouseArea {
                                id: plCardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.playlistSelected(plData)
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 10
                                z: 1

                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: width

                                    PlaylistCollageThumbnail {
                                        anchors.fill: parent
                                        radius: 10
                                        customCover: plData.customCover || ""
                                        tracks: plData.tracks || []
                                        playlistTitle: plData.title || plData.name || ""
                                        accentColor: root.accentColor
                                    }

                                    // Floating Quick Play Button on Hover (z: 20)
                                    Rectangle {
                                        id: plPlayBtn
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 8
                                        width: 36
                                        height: 36
                                        radius: 18
                                        color: plPlayMouse.containsMouse ? Qt.lighter(root.accentColor, 1.15) : root.accentColor
                                        opacity: (plCardMouse.containsMouse || plPlayMouse.containsMouse) && (plData.tracks && plData.tracks.length > 0) ? 1.0 : 0.0
                                        scale: plPlayMouse.containsMouse ? 1.08 : 1.0
                                        z: 20

                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                        Behavior on scale { NumberAnimation { duration: 150 } }
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        AppIcon {
                                            anchors.centerIn: parent
                                            source: "../assets/icons/media-playback-start-symbolic.svg"
                                            iconSize: 14
                                            color: "#000000"
                                        }

                                        MouseArea {
                                            id: plPlayMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            preventStealing: true
                                            onClicked: mouse => {
                                                mouse.accepted = true;
                                                root.playPlaylistRequested(plData, false);
                                            }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    Text {
                                        Layout.fillWidth: true
                                        text: plData.title || plData.name || I18n.tr("Danh sách phát", "Playlist")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        color: plCardMouse.containsMouse ? root.accentColor : "#ffffff"
                                        elide: Text.ElideRight
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: (plData.trackCount || (plData.tracks ? plData.tracks.length : 0)) + " " + I18n.tr("bài hát", "tracks")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Theme.textSecondary
                                        elide: Text.ElideRight
                                    }
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }
                    }
                }

                // Favorite Playlists Grid (when in Downloads view and Favorites sub-tab is selected)
                Flow {
                    Layout.fillWidth: true
                    spacing: 16
                    visible: root.isDownloadsView && root.downloadsSubTab === "favorites" && root.albumMetadata === null && root.favoritePlaylists && root.favoritePlaylists.length > 0

                    Repeater {
                        model: root.favoritePlaylists

                        Rectangle {
                            id: favPlCard
                            readonly property var plData: modelData
                            width: 176
                            height: 250
                            radius: Theme.radiusCard
                            color: favCardMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.06) : Qt.rgba(1.0, 1.0, 1.0, 0.02)
                            border.color: favCardMouse.containsMouse ? root.accentColor : Qt.rgba(1.0, 1.0, 1.0, 0.06)
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            // Base Card Click Area (z: 0)
                            MouseArea {
                                id: favCardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.playlistSelected(modelData)
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 10
                                z: 1

                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: width

                                    Rectangle {
                                        id: favImgMask
                                        anchors.fill: parent
                                        radius: 10
                                        color: "#ffffff"
                                        visible: false
                                        layer.enabled: true
                                    }

                                    Item {
                                        anchors.fill: parent
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            maskEnabled: true
                                            maskSource: favImgMask
                                            autoPaddingEnabled: false
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            color: "#202024"
                                            visible: !favImg.visible || favImg.status !== Image.Ready
                                        }

                                        Image {
                                            id: favImg
                                            anchors.fill: parent
                                            source: {
                                                if (!modelData) return "";
                                                var s = modelData.image || modelData.thumbnail || "";
                                                return (s.startsWith("/") && !s.startsWith("file://")) ? ("file://" + s) : s;
                                            }
                                            fillMode: Image.PreserveAspectCrop
                                            scale: (implicitWidth > 0 && implicitHeight > 0 && (implicitWidth / implicitHeight > 1.25)) ? 1.48 : 1.0
                                            transformOrigin: Item.Center
                                            asynchronous: true
                                            visible: status === Image.Ready
                                            sourceSize: Qt.size(360, 360)
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            visible: !favImg.visible || favImg.status !== Image.Ready
                                            gradient: Gradient {
                                                GradientStop { position: 0.0; color: "#2e1065" }
                                                GradientStop { position: 1.0; color: "#18181b" }
                                            }
                                            AppIcon {
                                                anchors.centerIn: parent
                                                source: "../assets/icons/emblem-favorite-symbolic.svg"
                                                iconSize: 42
                                                color: root.accentColor
                                            }
                                        }
                                    }

                                    // 1px Hairline Border Overlay
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 10
                                        color: "transparent"
                                        border.color: Qt.rgba(1, 1, 1, 0.12)
                                        border.width: 1
                                        z: 2
                                    }

                                    // Top-Right Remove/Toggle Heart Button (z: 20)
                                    Rectangle {
                                        id: favHBtn
                                        width: 32
                                        height: 32
                                        radius: 16
                                        color: favHBtnMouse.containsMouse 
                                               ? Qt.rgba(244/255, 63/255, 94/255, 0.28) 
                                               : Qt.rgba(0, 0, 0, 0.70)
                                        border.color: favHBtnMouse.containsMouse ? "#f43f5e" : root.accentColor
                                        border.width: 1
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 6
                                        visible: favCardMouse.containsMouse || favHBtnMouse.containsMouse
                                        scale: favHBtnMouse.containsMouse ? 1.12 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 100 } }
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Behavior on border.color { ColorAnimation { duration: 120 } }
                                        z: 20

                                        AppIcon {
                                            anchors.centerIn: parent
                                            source: "../assets/icons/emblem-favorite-symbolic.svg"
                                            iconSize: 14
                                            color: favHBtnMouse.containsMouse ? "#f43f5e" : root.accentColor
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                        }

                                        MouseArea {
                                            id: favHBtnMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            preventStealing: true
                                            onClicked: mouse => {
                                                mouse.accepted = true;
                                                root.toggleFavoritePlaylistRequested(modelData);
                                            }
                                        }
                                    }

                                    // Bottom-Right Play Button on Hover (z: 20)
                                    Rectangle {
                                        id: favPlayBtn
                                        width: 38
                                        height: 38
                                        radius: 19
                                        color: favPlayMouse.containsMouse ? Qt.lighter(root.accentColor, 1.15) : root.accentColor
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 6
                                        visible: favCardMouse.containsMouse || favPlayMouse.containsMouse
                                        scale: favPlayMouse.containsMouse ? 1.08 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 100 } }
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        z: 20

                                        AppIcon {
                                            anchors.centerIn: parent
                                            anchors.horizontalCenterOffset: 1
                                            source: "../assets/icons/media-playback-start-symbolic.svg"
                                            iconSize: 16
                                            color: (root.accentColor.r * 0.299 + root.accentColor.g * 0.587 + root.accentColor.b * 0.114) > 0.6 ? "#0c0d10" : "#ffffff"
                                        }

                                        MouseArea {
                                            id: favPlayMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            preventStealing: true
                                            onClicked: mouse => {
                                                mouse.accepted = true;
                                                root.playlistSelected(modelData);
                                            }
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.title || modelData.name || "Playlist"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.bold: true
                                    color: Theme.textPrimary
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        var sub = modelData.artist || modelData.subtitle || I18n.tr("Danh sách phát", "Playlist");
                                        var cnt = modelData.trackCount ? (" • " + modelData.trackCount + I18n.tr(" bài", " tracks")) : "";
                                        return sub + cnt;
                                    }
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Theme.textSecondary
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }
                    }
                }



                // =============================================================
                // SimpMusic Clean Horizontal List View for Downloads
                // =============================================================
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    visible: !root.isLoading && root.isDownloadsView && root.downloadsSubTab === "tracks" && root.albumMetadata === null

                    Repeater {
                        model: root.sortedTracks

                        Rectangle {
                            id: dlRow
                            Layout.fillWidth: true
                            height: 56
                            radius: 8
                            color: dlRow.isCurrentTrack
                                   ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
                                   : (dlRow.isSelected
                                      ? Qt.rgba(1.0, 1.0, 1.0, 0.08)
                                      : (dlRowMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.06) : Qt.rgba(1.0, 1.0, 1.0, 0.02)))
                            border.color: dlRow.isCurrentTrack
                                          ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                                          : (dlRowMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.18) : Qt.rgba(1.0, 1.0, 1.0, 0.06))
                            border.width: 1

                            readonly property bool isCurrentTrack: !!(root.currentTrack && modelData && (root.currentTrack.path === modelData.path || (modelData.videoId && root.currentTrack.videoId === modelData.videoId)))
                            readonly property bool isCurrentPlaying: isCurrentTrack && root.isPlaying
                            readonly property bool isCurrentLoading: isCurrentTrack && root.isLoadingAudio
                            readonly property bool isSelected: !!(modelData && modelData.path && root.selectedTrackPaths.indexOf(modelData.path) !== -1)

                            Behavior on color { ColorAnimation { duration: 100 } }
                            Behavior on border.color { ColorAnimation { duration: 100 } }

                            MouseArea {
                                id: dlRowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                pressAndHoldInterval: 450

                                property bool wasLongPress: false

                                onPressed: mouse => {
                                    wasLongPress = false;
                                }

                                onPressAndHold: mouse => {
                                    if (mouse.button === Qt.LeftButton && !root.isSelectionMode) {
                                        wasLongPress = true;
                                        root.isSelectionMode = true;
                                        root.toggleTrackSelection(modelData);
                                    }
                                }

                                onClicked: mouse => {
                                    if (wasLongPress) {
                                        wasLongPress = false;
                                        return;
                                    }
                                    if (mouse.button === Qt.RightButton) {
                                        var pt = dlRow.mapToItem(null, mouse.x, mouse.y);
                                        root.trackContextMenuRequested(modelData, pt.x, pt.y);
                                    } else {
                                        if (root.isSelectionMode) {
                                            root.toggleTrackSelection(modelData);
                                        } else {
                                            root.trackPlayRequested(modelData);
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 16
                                spacing: 14
                                z: 1

                                // Index Number / Play Icon OR Selection Checkbox
                                Item {
                                    width: 28
                                    height: 28
                                    Layout.alignment: Qt.AlignVCenter

                                    // Checkbox in selection mode
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 20
                                        height: 20
                                        radius: 4
                                        visible: root.isSelectionMode
                                        color: dlRow.isSelected ? root.accentColor : "transparent"
                                        border.color: dlRow.isSelected ? root.accentColor : Qt.rgba(1, 1, 1, 0.3)
                                        border.width: 1.5

                                        AppIcon {
                                            anchors.centerIn: parent
                                            visible: dlRow.isSelected
                                            source: "../assets/icons/emblem-ok-symbolic.svg"
                                            iconSize: 12
                                            color: "#000000"
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.toggleTrackSelection(modelData)
                                        }
                                    }

                                    // Play icon / Index number in normal mode
                                    Item {
                                        anchors.fill: parent
                                        visible: !root.isSelectionMode

                                        CircularSpinner {
                                            anchors.centerIn: parent
                                            size: 15
                                            strokeWidth: 2.0
                                            color: root.accentColor
                                            visible: dlRow.isCurrentLoading
                                            running: dlRow.isCurrentLoading
                                        }

                                        AppIcon {
                                            anchors.centerIn: parent
                                            visible: !dlRow.isCurrentLoading && (dlRowMouse.containsMouse || dlRow.isCurrentTrack)
                                            source: dlRow.isCurrentPlaying
                                                    ? "../assets/icons/media-playback-pause-symbolic.svg"
                                                    : "../assets/icons/media-playback-start-symbolic.svg"
                                            iconSize: 15
                                            color: dlRow.isCurrentTrack ? root.accentColor : "#ffffff"
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            visible: !dlRow.isCurrentLoading && !dlRowMouse.containsMouse && !dlRow.isCurrentTrack
                                            text: String(index + 1)
                                            color: Theme.textSecondary
                                            font.pixelSize: 13
                                            font.family: Theme.fontFamily
                                        }
                                    }
                                }

                                // Masked Artwork (42x42, radius 6, matching Home)
                                Item {
                                    width: 42
                                    height: 42
                                    Layout.alignment: Qt.AlignVCenter

                                    Rectangle {
                                        id: dlArtMask
                                        anchors.fill: parent
                                        radius: 6
                                        color: "#ffffff"
                                        visible: false
                                        layer.enabled: true
                                    }

                                    Item {
                                        anchors.fill: parent
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            maskEnabled: true
                                            maskSource: dlArtMask
                                            autoPaddingEnabled: false
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            color: "#202024"
                                            visible: !dlArtImg.visible || dlArtImg.status !== Image.Ready
                                        }

                                        Image {
                                            id: dlArtImg
                                            anchors.fill: parent
                                            source: {
                                                if (!modelData || !modelData.image) return "";
                                                var s = modelData.image;
                                                return (s.startsWith("/") && !s.startsWith("file://")) ? ("file://" + s) : s;
                                            }
                                            fillMode: Image.PreserveAspectCrop
                                            scale: (implicitWidth > 0 && implicitHeight > 0 && (implicitWidth / implicitHeight > 1.25)) ? 1.48 : 1.0
                                            transformOrigin: Item.Center
                                            sourceSize: Qt.size(88, 88)
                                            asynchronous: true
                                            visible: status === Image.Ready
                                        }

                                        AppIcon {
                                            anchors.centerIn: parent
                                            visible: !dlArtImg.visible || dlArtImg.status !== Image.Ready
                                            source: "../assets/icons/media-optical-audio-symbolic.svg"
                                            iconSize: 20
                                            color: Qt.rgba(1, 1, 1, 0.25)
                                        }
                                    }

                                    // 1px Hairline Border Overlay on top of image (matching Home)
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 6
                                        color: "transparent"
                                        border.color: Qt.rgba(1, 1, 1, 0.12)
                                        border.width: 1
                                        z: 2
                                    }
                                }

                                // Title & Artist • Album
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 2

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.name || modelData.title || I18n.tr("Bài hát không tên", "Unknown Track")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: dlRow.isCurrentTrack ? root.accentColor : Theme.textPrimary
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: {
                                            var art = modelData.artist || I18n.tr("Nghệ sĩ chưa rõ", "Unknown Artist");
                                            var alb = modelData.album || "";
                                            return (alb && alb !== art) ? (art + " • " + alb) : art;
                                        }
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: Theme.textSecondary
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }
                                }

                                // Duration (Fixed width + AlignRight for strict column alignment)
                                Text {
                                    Layout.preferredWidth: 46
                                    Layout.alignment: Qt.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData.duration || "--:--"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Theme.textSecondary
                                }

                                // 3-Dots Context Menu Button
                                Rectangle {
                                    width: 32
                                    height: 32
                                    radius: 16
                                    Layout.alignment: Qt.AlignVCenter
                                    color: dlDotsH.hovered ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                                    HoverHandler { id: dlDotsH }

                                    AppIcon {
                                        anchors.centerIn: parent
                                        source: "../assets/icons/view-more-symbolic.svg"
                                        iconSize: 16
                                        color: dlDotsH.hovered ? "#ffffff" : Theme.textSecondary
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var pt = dlRow.mapToItem(null, dlRow.width - 200, dlRow.height);
                                            root.trackContextMenuRequested(modelData, pt.x, pt.y);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Grid of tracks (Online searches, or playlists with no hero album)
                Flow {
                    Layout.fillWidth: true
                    spacing: 16
                    visible: !root.isLoading && (!root.isDownloadsView || root.albumMetadata !== null) && !(root.isDownloadsView && (root.downloadsSubTab === "favorites" || root.downloadsSubTab === "playlists"))

                    Repeater {
                        model: root.sortedTracks

                        TrackCard {
                            track: modelData
                            accentColor: root.accentColor
                            isPlaying: root.currentTrack && root.currentTrack.path === modelData.path && root.isPlaying
                            isSelectionMode: root.isSelectionMode
                            isSelected: root.selectedTrackPaths.indexOf(modelData.path) !== -1
                            onSelectionToggled: trk => root.toggleTrackSelection(trk)
                            onPlayRequested: trk => root.trackPlayRequested(trk)
                            onDetailsRequested: trk => root.trackDetailsRequested(trk)
                            onContextMenuRequested: (trk, gx, gy) => root.trackContextMenuRequested(trk, gx, gy)
                        }
                    }
                }
            }
        }

    // Automatically dismiss sort popover if user scrolls
    Connections {
        target: scrollArea
        function onContentYChanged() {
            if (sortPopover.isOpen) sortPopover.isOpen = false;
        }
    }

    // Empty state overlay for Favorite Playlists (Dead-Center Optical Alignment)
    Item {
        id: favEmptyOverlay
        anchors.top: parent.top
        anchors.topMargin: 84
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 100
        anchors.left: parent.left
        anchors.right: parent.right
        visible: root.isDownloadsView && root.downloadsSubTab === "favorites" && (!root.favoritePlaylists || root.favoritePlaylists.length === 0) && root.albumMetadata === null
        z: 10

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 16

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 72
                height: 72
                radius: 36
                color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
                border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25)
                border.width: 1

                AppIcon {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 1
                    source: "../assets/icons/emblem-favorite-symbolic.svg"
                    iconSize: 32
                    color: root.accentColor
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: I18n.tr("Chưa có danh sách phát yêu thích", "No favorite playlists yet")
                font.family: Theme.fontFamily
                font.pixelSize: 18
                font.bold: true
                color: Theme.textPrimary
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: I18n.tr("Khám phá các danh sách phát trực tuyến và nhấn biểu tượng Yêu thích để lưu lại.", "Explore online playlists and tap the Favorite icon to save them here.")
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Theme.textSecondary
            }
        }
    }

    // Sort Popover Overlay (LiquidGlass / Frosted Dark Glass Dropdown - SettingsModal Parity)
    Item {
        id: sortPopover
        anchors.fill: parent
        z: 9999
        visible: opacity > 0.001
        opacity: isOpen ? 1.0 : 0.0
        enabled: isOpen

        Behavior on opacity {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        property bool isOpen: false
        property real targetX: 0
        property real targetY: 0
        readonly property real popoverWidth: 154

        // Backdrop to dismiss popover when clicking anywhere outside
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: true
            onClicked: sortPopover.isOpen = false
        }

        // Popover Card
        Item {
            id: sortCardWrapper
            x: sortPopover.targetX
            y: sortPopover.targetY
            width: sortPopover.popoverWidth
            height: sortMenuCol.implicitHeight + 10

            scale: sortPopover.isOpen ? 1.0 : 0.94
            transformOrigin: Item.TopRight
            Behavior on scale {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            // Layer 1: Ambient Base Layer (Opaque foundation to completely prevent underlying track borders from shining through)
            Rectangle {
                anchors.fill: parent
                radius: 10
                color: "#0d0e15"
            }

            // Layer 2: Liquid Glass Card (Matching SettingsModal style in Image 2)
            Rectangle {
                anchors.fill: parent
                radius: 10
                color: Qt.rgba(0.06 + root.accentColor.r * 0.08, 0.06 + root.accentColor.g * 0.08, 0.08 + root.accentColor.b * 0.12, 0.96)
                border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                border.width: 1

                Column {
                    id: sortMenuCol
                    anchors.top: parent.top
                    anchors.topMargin: 5
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 3

                    readonly property var sortOptions: [
                        { key: "recent", name: I18n.tr("Mới nhất", "Latest") },
                        { key: "oldest", name: I18n.tr("Cũ nhất", "Oldest") },
                        { key: "title", name: I18n.tr("Tên A-Z", "Title A-Z") },
                        { key: "artist", name: I18n.tr("Nghệ sĩ", "Artist") },
                        { key: "duration", name: I18n.tr("Thời lượng", "Duration") }
                    ]

                    Repeater {
                        model: sortMenuCol.sortOptions
                        delegate: Rectangle {
                            width: sortMenuCol.width - 10
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: 32
                            radius: 7
                            color: (root.sortBy === modelData.key)
                                   ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.26)
                                   : (sortItemMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14) : "transparent")
                            border.color: (root.sortBy === modelData.key)
                                          ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                                          : (sortItemMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25) : "transparent")
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 100 } }
                            Behavior on border.color { ColorAnimation { duration: 100 } }

                            Item {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 10

                                Text {
                                    anchors.left: parent.left
                                    anchors.right: sortCheckIcon.left
                                    anchors.rightMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.name
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: root.sortBy === modelData.key
                                    color: (root.sortBy === modelData.key) ? "#ffffff" : (sortItemMouse.containsMouse ? "#ffffff" : Qt.rgba(255, 255, 255, 0.85))
                                    elide: Text.ElideRight
                                }

                                AppIcon {
                                    id: sortCheckIcon
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: "../assets/icons/emblem-ok-symbolic.svg"
                                    iconSize: 11
                                    color: root.accentColor
                                    visible: root.sortBy === modelData.key
                                }
                            }

                            MouseArea {
                                id: sortItemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.sortBy = modelData.key;
                                    sortPopover.isOpen = false;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

