import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "."

Rectangle {
    id: root
    color: "transparent"
    radius: Theme.radiusCard
    Layout.fillHeight: true
    implicitWidth: 360
    implicitHeight: 600

    property var track: null
    property real currentTime: 0.0
    property bool isPlaying: false
    property var activeLyrics: []
    property int currentLyricIndex: -1

    property string compactTab: "lyrics" // "lyrics" or "art"
    property string appDir: (typeof win !== "undefined" && win && win.appDir) ? win.appDir : (Quickshell.env("NUTSTY_APP_DIR") || (Quickshell.env("HOME") + "/Applications/FrostifyLocal"))

    property color accentColor: "#deb06c"
    property var frostifyPalette: ({
        "highlightColor": "#deb06c",
        "baseTextColor": "#f8fafc",
        "shadowDirectional": "#a6020305",
        "shadowAmbient": "#66000000"
    })

    FileView {
        id: frostifyPaletteFile
        path: Quickshell.env("HOME") + "/.config/noctalia/nutsty_palette.json"
        watchChanges: true
        onFileChanged: {
            this.reload();
            delayedPaletteRead.restart();
        }
        onLoadedChanged: if (this.loaded) parseFrostifyPalette(this.text())
        Component.onCompleted: if (this.loaded) parseFrostifyPalette(this.text())
    }

    Timer {
        id: delayedPaletteRead
        interval: 80
        onTriggered: if (frostifyPaletteFile.loaded) parseFrostifyPalette(frostifyPaletteFile.text())
    }

    function parseFrostifyPalette(raw) {
        if (!raw || raw.trim() === "") return;
        try {
            var obj = JSON.parse(raw);
            var updated = Object.assign({}, root.frostifyPalette);
            for (var k in obj) {
                updated[k] = obj[k];
            }
            root.frostifyPalette = updated;
            if (obj.highlightColor) root.accentColor = obj.highlightColor;
        } catch (e) {}
    }

    readonly property bool isCompact: root.width < 720

    signal closeRequested()
    signal seekRequested(real seconds)

    function updateActiveLyric(forceScroll) {
        if (!activeLyrics || activeLyrics.length === 0) {
            currentLyricIndex = -1;
            return;
        }
        var cur = root.currentTime;
        var found = -1;
        for (var i = 0; i < activeLyrics.length; i++) {
            var t = activeLyrics[i].time;
            var nextT = (i + 1 < activeLyrics.length) ? activeLyrics[i + 1].time : 999999;
            if (cur >= t && cur < nextT) {
                found = i;
                break;
            }
        }
        if (found !== -1) {
            var changed = (currentLyricIndex !== found);
            currentLyricIndex = found;
            if (forceScroll) {
                lyricsView.currentIndex = found;
                lyricsView.positionViewAtIndex(found, ListView.Center);
            } else if (changed) {
                if (!lyricsView.moving && !lyricsView.dragging && !lyricsView.flicking && !userScrollTimer.running) {
                    lyricsView.currentIndex = found;
                }
            }
        }
    }

    Timer {
        id: userScrollTimer
        interval: 3500
        repeat: false
    }

    function fetchLyrics() {
        activeLyrics = [];
        currentLyricIndex = -1;
        var songTitle = (track && (track.title || track.name)) ? (track.title || track.name) : "";
        var songArtist = (track && track.artist) ? track.artist : "";
        var songVid = (track && track.videoId) ? track.videoId : "";
        var songPath = (track && (track.path || track.file_path || track.filePath)) ? (track.path || track.file_path || track.filePath) : "";
        if (songTitle !== "") {
            var songDur = (root.track && root.track.duration && !isNaN(Number(root.track.duration)))
                ? String(Math.round(Number(root.track.duration))) : "";
            console.log("Fetching lyrics for track:", songTitle, "by", songArtist, "dur:", songDur);
            lyricsProc.running = false;
            lyricsProc.command = [
                "python3", "-u",
                root.appDir + "/backend/lyrics_helper.py",
                songTitle, songArtist, songVid, songPath, songDur
            ];
            lyricsProc.running = true;
        }
    }

    property var songDetails: null
    property var audioSpecs: null
    readonly property bool isDetailsLoading: !songDetails || songDetailsProc.running

    signal viewAlbumRequested(var alb)
    signal startRadioRequested(var trk)
    signal downloadTrackRequested(var trk)
    signal openFolderRequested(var trk)
    signal copyLinkRequested(string text)
    signal rateSongRequested(string videoId, string rating)
    signal songDisliked(var trk)
    signal openArtistRequested(string artistName, string channelId)

    property var artistAvatarsMap: ({})
    property var dislikedSongsMap: ({})

    FileView {
        id: artistAvatarsFileView
        path: Quickshell.env("HOME") + "/.cache/nutsty/artist_avatars.json"
        watchChanges: true
        onFileChanged: {
            reload();
            try {
                var txt = text();
                if (txt && txt.length > 2) artistAvatarsMap = JSON.parse(txt);
            } catch (e) {}
        }
    }

    FileView {
        id: dislikedFileView
        path: Quickshell.env("HOME") + "/.config/noctalia/nutsty_disliked_songs.json"
        watchChanges: true
        onFileChanged: {
            reload();
            try {
                var txt = text();
                if (txt && txt.length > 2) dislikedSongsMap = JSON.parse(txt);
            } catch (e) {}
        }
    }

    function isTrackDisliked(vid) {
        if (!vid || !dislikedSongsMap) return false;
        var clean = String(vid).replace("ytdl://", "").replace("yt_", "");
        return !!dislikedSongsMap[clean];
    }

    readonly property string cachedArtistAvatar: {
        var aName = (root.track && root.track.artist) ? root.track.artist.toLowerCase().trim() : "";
        if (aName && artistAvatarsMap && artistAvatarsMap[aName]) {
            return artistAvatarsMap[aName];
        }
        return "";
    }

    property string currentLikeStatus: "INDIFFERENT"
    property int localLikesCount: (songDetails && songDetails.likes) ? songDetails.likes : 0
    property int localDislikesCount: (songDetails && songDetails.dislikes) ? songDetails.dislikes : 0

    onSongDetailsChanged: {
        if (songDetails) {
            currentLikeStatus = songDetails.likeStatus || "INDIFFERENT";
            localLikesCount = songDetails.likes || 0;
            localDislikesCount = songDetails.dislikes || 0;
        } else {
            var vid = track ? (track.videoId || (track.path && track.path.startsWith("ytdl://") ? track.path.replace("ytdl://", "") : "")) : "";
            currentLikeStatus = (vid && isTrackDisliked(vid)) ? "DISLIKE" : "INDIFFERENT";
            localLikesCount = 0;
            localDislikesCount = 0;
        }
    }

    function toggleLike() {
        if (!songDetails || !songDetails.videoId) return;
        var newStatus = (currentLikeStatus === "LIKE") ? "INDIFFERENT" : "LIKE";
        if (newStatus === "LIKE") {
            localLikesCount += 1;
            if (currentLikeStatus === "DISLIKE" && localDislikesCount > 0) {
                localDislikesCount -= 1;
            }
        } else {
            if (localLikesCount > 0) localLikesCount -= 1;
        }
        currentLikeStatus = newStatus;
        rateSongRequested(songDetails.videoId, newStatus);
    }

    function toggleDislike() {
        if (!songDetails || !songDetails.videoId) return;
        var newStatus = (currentLikeStatus === "DISLIKE") ? "INDIFFERENT" : "DISLIKE";
        if (newStatus === "DISLIKE") {
            localDislikesCount += 1;
            if (currentLikeStatus === "LIKE" && localLikesCount > 0) {
                localLikesCount -= 1;
            }
            currentLikeStatus = newStatus;
            rateSongRequested(songDetails.videoId, "DISLIKE");
            songDisliked(track);
        } else {
            if (localDislikesCount > 0) localDislikesCount -= 1;
            currentLikeStatus = newStatus;
            rateSongRequested(songDetails.videoId, "INDIFFERENT");
        }
    }

    function scrollArtDown() {
        artScrollArea.contentY = Math.min(artScrollArea.contentHeight - artScrollArea.height, artScrollArea.contentY + 340);
    }

    function fetchSongDetails() {
        songDetails = null;
        if (!track) return;
        var vid = track.videoId || "";
        if (!vid && track.path && track.path.startsWith("ytdl://")) {
            vid = track.path.replace("ytdl://", "");
        }
        if (!vid && (track.title || track.name)) {
            vid = (track.title || track.name) + " " + (track.artist || "");
        }
        if (vid) {
            songDetailsProc.running = false;
            songDetailsProc.command = [
                "python3", "-u",
                root.appDir + "/backend/ytmusic_helper.py",
                "song_details", vid
            ];
            songDetailsProc.running = true;
        }
        fetchAudioSpecs();
    }

    function fetchAudioSpecs() {
        audioSpecsProc.running = false;
        var daemonPath = root.appDir + "/backend/player_daemon.py";
        audioSpecsProc.command = [
            "python3", "-u",
            daemonPath,
            "audio_specs"
        ];
        audioSpecsProc.running = true;
    }

    onTrackChanged: {
        songDetails = null;
        var vid = track ? (track.videoId || (track.path && track.path.startsWith("ytdl://") ? track.path.replace("ytdl://", "") : "")) : "";
        currentLikeStatus = (vid && isTrackDisliked(vid)) ? "DISLIKE" : "INDIFFERENT";
        localLikesCount = 0;
        localDislikesCount = 0;

        fetchLyrics();
        fetchSongDetails();
        delayedAudioSpecsTimer.restart();
    }
    onCurrentTimeChanged: updateActiveLyric(false)
    onActiveLyricsChanged: Qt.callLater(function() { updateActiveLyric(true); })
    onVisibleChanged: {
        if (visible) {
            fetchLyrics();
            fetchSongDetails();
            delayedAudioSpecsTimer.restart();
            Qt.callLater(function() { updateActiveLyric(true); });
        }
    }
    
    onWidthChanged: console.log("AmberolDetailView width:", width, "isCompact:", isCompact)
    Component.onCompleted: {
        console.log("AmberolDetailView COMPLETED width:", width, "height:", height, "isCompact:", isCompact)
        try {
            var aTxt = artistAvatarsFileView.text();
            if (aTxt && aTxt.length > 2) artistAvatarsMap = JSON.parse(aTxt);
        } catch(e) {}
        try {
            var dTxt = dislikedFileView.text();
            if (dTxt && dTxt.length > 2) dislikedSongsMap = JSON.parse(dTxt);
        } catch(e) {}
        fetchLyrics();
        fetchSongDetails();
    }

    Process {
        id: lyricsProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                try {
                    var arr = JSON.parse(data);
                    root.activeLyrics = arr;
                    console.log("AmberolDetailView loaded lyrics count:", arr.length);
                    Qt.callLater(function() { root.updateActiveLyric(true); });
                } catch(e) {
                    console.log("Parse error:", e);
                    root.activeLyrics = [];
                }
            }
        }
    }

    Process {
        id: songDetailsProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                try {
                    var obj = JSON.parse(data);
                    if (obj && typeof obj === "object") {
                        root.songDetails = obj;
                    }
                } catch(e) {
                    console.log("songDetailsProc error:", e);
                }
            }
        }
    }

    Process {
        id: audioSpecsProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                try {
                    var obj = JSON.parse(data);
                    if (obj && typeof obj === "object") {
                        root.audioSpecs = obj;
                    }
                } catch(e) {
                    console.log("audioSpecsProc error:", e);
                }
            }
        }
    }

    Timer {
        id: delayedAudioSpecsTimer
        interval: 1200
        repeat: false
        onTriggered: fetchAudioSpecs()
    }

    // Deep Velvet Bokeh Ambient Artwork Background (SimpMusic Style)
    Item {
        id: bgArtworkContainer
        anchors.fill: parent
        clip: true

        Image {
            id: bgArtworkImg
            anchors.fill: parent
            source: root.track && root.track.image ? root.track.image : ""
            fillMode: Image.PreserveAspectCrop
            visible: false
        }

        MultiEffect {
            id: bgArtworkBlur
            anchors.fill: parent
            source: bgArtworkImg
            visible: bgArtworkImg.status === Image.Ready
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            saturation: 1.5
            brightness: 0.0
            opacity: 0.52
        }

        // Deep warm tint overlay to enhance text readability while letting warm album tones shine through
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.02, 0.02, 0.04, 0.45) }
                GradientStop { position: 0.45; color: Qt.rgba(0.01, 0.01, 0.02, 0.60) }
                GradientStop { position: 1.0; color: Qt.rgba(0.01, 0.01, 0.02, 0.78) }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        radius: Theme.radiusCard
    }

    property bool allowClose: false
    Timer {
        interval: 600
        running: true
        repeat: false
        onTriggered: root.allowClose = true
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.isCompact ? 12 : 24
        spacing: root.isCompact ? 10 : 16

        // Top Bar: Back button with Amberol symbolic icon
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 36

            Rectangle {
                width: 36
                height: 36
                radius: 18
                color: backH.hovered ? "#2e2e2e" : "#1f1f1f"
                Behavior on color { ColorAnimation { duration: 120 } }
                HoverHandler { id: backH }

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/go-previous-symbolic.svg"
                    iconSize: 16
                    color: Theme.textPrimary
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (root.allowClose) {
                            root.closeRequested();
                        }
                    }
                }
            }

            // Center track info when compact (replaces the redundant 56px sub-row)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                spacing: 1
                visible: root.isCompact

                Text {
                    Layout.fillWidth: true
                    text: root.track ? (root.track.title || root.track.name || I18n.tr("Đang phát", "Now Playing")) : I18n.tr("Đang phát", "Now Playing")
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.track ? (root.track.artist || "") : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Qt.rgba(1, 1, 1, 0.65)
                    elide: Text.ElideRight
                    visible: !!text
                }
            }

            Text {
                Layout.leftMargin: 8
                text: I18n.tr("Chi tiết bài hát & Lời đồng bộ", "Now Playing Details & Synced Lyrics")
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
                color: Theme.textSecondary
                visible: !root.isCompact
            }

            Item { Layout.fillWidth: true; visible: !root.isCompact }

            // Segmented pill switch when compact: [Lyrics | Art]
            Rectangle {
                visible: root.isCompact
                width: 144
                height: 30
                radius: 15
                color: Qt.rgba(0.08, 0.08, 0.10, 0.75)
                border.color: Qt.rgba(1, 1, 1, 0.10)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    spacing: 0

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 15
                        color: root.compactTab === "lyrics" ? Qt.rgba(1, 1, 1, 0.16) : (lyrH.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                        border.color: root.compactTab === "lyrics" ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.40) : "transparent"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        HoverHandler { id: lyrH }

                        Text {
                            anchors.centerIn: parent
                            text: I18n.tr("Lời bài hát", "Lyrics")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: root.compactTab === "lyrics"
                            color: root.compactTab === "lyrics" ? "#ffffff" : Qt.rgba(1, 1, 1, 0.55)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.compactTab = "lyrics"
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 15
                        color: root.compactTab === "art" ? Qt.rgba(1, 1, 1, 0.16) : (artH.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                        border.color: root.compactTab === "art" ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.40) : "transparent"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        HoverHandler { id: artH }

                        Text {
                            anchors.centerIn: parent
                            text: I18n.tr("Ảnh bìa", "Artwork")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: root.compactTab === "art"
                            color: root.compactTab === "art" ? "#ffffff" : Qt.rgba(1, 1, 1, 0.55)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.compactTab = "art"
                        }
                    }
                }
            }
        }

        // Main Layout: Two Columns (Wide) or Full Lyrics / Full Art (Compact)
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.isCompact ? 0 : 28

            // Left: Large Amberol Cover Card & Detailed Song Metadata Inspector (Visible when wide OR when compactTab == 'art')
            Flickable {
                id: artScrollArea
                visible: !root.isCompact || root.compactTab === "art"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 320
                Layout.maximumWidth: root.isCompact ? 360 : 320
                Layout.minimumWidth: 260
                contentWidth: width
                contentHeight: artContentCol.implicitHeight + 110
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: artContentCol
                    width: artScrollArea.width
                    spacing: 14
                    Layout.alignment: Qt.AlignHCenter

                    // 1. Large Cover Art (260x260 in compact, 280x280 wide)
                    Rectangle {
                        width: root.isCompact ? 260 : 280
                        height: width
                        Layout.preferredWidth: width
                        Layout.preferredHeight: height
                        Layout.alignment: Qt.AlignHCenter
                        radius: 16
                        color: Qt.rgba(1, 1, 1, 0.04)
                        border.color: Qt.rgba(1, 1, 1, 0.10)
                        border.width: 1
                        clip: true

                        Image {
                            id: mainCover
                            anchors.fill: parent
                            source: root.track && root.track.image ? root.track.image : ""
                            fillMode: Image.PreserveAspectCrop
                            visible: status === Image.Ready
                            asynchronous: true
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: !mainCover.visible
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#2d2d3a" }
                                GradientStop { position: 1.0; color: "#141418" }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: root.track && root.track.artist ? root.track.artist.charAt(0).toUpperCase() : "A"
                                font.family: Theme.fontFamily
                                font.pixelSize: 72
                                font.bold: true
                                color: "#444455"
                            }
                        }
                    }

                    // 2. Track Title & Artist Info
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: root.isCompact ? 260 : 280
                        Layout.maximumWidth: 320
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 4

                        Text {
                            Layout.fillWidth: true
                            text: root.track ? (root.track.title || root.track.name || I18n.tr("Chưa chọn bài hát", "No track selected")) : I18n.tr("Chưa chọn bài hát", "No track selected")
                            font.family: Theme.fontFamily
                            font.pixelSize: 19
                            font.bold: true
                            color: Theme.textPrimary
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            horizontalAlignment: root.isCompact ? Text.AlignHCenter : Text.AlignLeft
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.track ? (root.track.artist || I18n.tr("Nghệ sĩ chưa rõ", "Unknown Artist")) : I18n.tr("Nghệ sĩ chưa rõ", "Unknown Artist")
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            color: Qt.rgba(1, 1, 1, 0.72)
                            font.bold: true
                            elide: Text.ElideRight
                            horizontalAlignment: root.isCompact ? Text.AlignHCenter : Text.AlignLeft
                        }

                        // Badges Row: [CODEC & BITRATE] [SOURCE] [YEAR]
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.alignment: root.isCompact ? Qt.AlignHCenter : Qt.AlignLeft
                            spacing: 6

                            // Codec Pill
                            Rectangle {
                                height: 20
                                width: codecText.implicitWidth + 12
                                radius: 4
                                color: Qt.rgba(0.12, 0.12, 0.14, 0.9)
                                border.color: Qt.rgba(1, 1, 1, 0.15)
                                border.width: 1

                                Text {
                                    id: codecText
                                    anchors.centerIn: parent
                                    text: (root.audioSpecs ? root.audioSpecs.codec : "AAC") + " • " + (root.audioSpecs ? root.audioSpecs.bitrate_str : "192 kbps")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: root.accentColor
                                }
                            }

                            // Source Pill
                            Rectangle {
                                height: 20
                                width: srcText.implicitWidth + 12
                                radius: 4
                                color: Qt.rgba(0.12, 0.12, 0.14, 0.9)
                                border.color: Qt.rgba(1, 1, 1, 0.12)
                                border.width: 1

                                Text {
                                    id: srcText
                                    anchors.centerIn: parent
                                    text: (root.track && root.track.isLocal) ? "LOCAL" : "CLOUD"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: Theme.textSecondary
                                }
                            }

                            // Year Pill (if available)
                            Rectangle {
                                visible: !!yearText.text
                                height: 20
                                width: yearText.implicitWidth + 12
                                radius: 4
                                color: Qt.rgba(0.12, 0.12, 0.14, 0.9)
                                border.color: Qt.rgba(1, 1, 1, 0.12)
                                border.width: 1

                                Text {
                                    id: yearText
                                    anchors.centerIn: parent
                                    text: root.songDetails && root.songDetails.year ? root.songDetails.year : (root.track && root.track.year ? root.track.year : "")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: Theme.textSecondary
                                }
                            }
                        }
                    }

                    // 3. Audio Engine Specs Card (Dark Glass Grid 2x2)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: root.isCompact ? 260 : 280
                        Layout.maximumWidth: 320
                        Layout.preferredHeight: 96
                        Layout.alignment: Qt.AlignHCenter
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.04)
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1

                        GridLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            columns: 2
                            rowSpacing: 10
                            columnSpacing: 16

                            // 1. Codec
                            ColumnLayout {
                                spacing: 2
                                Text {
                                    text: "CODEC"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.bold: true
                                    color: Theme.textMuted
                                }
                                Text {
                                    text: root.audioSpecs ? root.audioSpecs.codec : "AAC"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: Theme.textPrimary
                                }
                            }

                            // 2. Bitrate
                            ColumnLayout {
                                spacing: 2
                                Text {
                                    text: "BITRATE"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.bold: true
                                    color: Theme.textMuted
                                }
                                Text {
                                    text: root.audioSpecs ? root.audioSpecs.bitrate_str : "192 kbps"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: Theme.textPrimary
                                }
                            }

                            // 3. Sample Rate
                            ColumnLayout {
                                spacing: 2
                                Text {
                                    text: "SAMPLE RATE"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.bold: true
                                    color: Theme.textMuted
                                }
                                Text {
                                    text: root.audioSpecs ? root.audioSpecs.sample_rate_str : "44.1 kHz"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: Theme.textPrimary
                                }
                            }

                            // 4. Channels
                            ColumnLayout {
                                spacing: 2
                                Text {
                                    text: "CHANNELS"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.bold: true
                                    color: Theme.textMuted
                                }
                                Text {
                                    text: root.audioSpecs ? root.audioSpecs.channels : "Stereo (2ch)"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: Theme.textPrimary
                                }
                            }
                        }
                    }

                    // 4. Nutsty Artist Card (Avatar, Label "Nghệ sĩ", Name & Subscribers)
                    Rectangle {
                        id: artistCard
                        Layout.fillWidth: true
                        Layout.preferredWidth: root.isCompact ? 260 : 280
                        Layout.maximumWidth: 320
                        Layout.preferredHeight: 164
                        Layout.alignment: Qt.AlignHCenter
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.04)
                        border.color: artistCardMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1
                        clip: true
                        visible: (root.songDetails && (root.songDetails.author || root.songDetails.authorThumbnail)) || (root.track && root.track.artist)

                        // Shimmer placeholder when avatar is not yet loaded
                        Rectangle {
                            anchors.fill: artistImg
                            color: "#202024"
                            visible: artistImg.status !== Image.Ready
                            
                            SequentialAnimation on opacity {
                                running: artistImg.status !== Image.Ready
                                loops: Animation.Infinite
                                NumberAnimation { from: 0.35; to: 0.70; duration: 900; easing.type: Easing.InOutQuad }
                                NumberAnimation { from: 0.70; to: 0.35; duration: 900; easing.type: Easing.InOutQuad }
                            }
                        }

                        // Artist Banner / Thumbnail image
                        Image {
                            id: artistImg
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: 108
                            source: (root.songDetails && root.songDetails.authorThumbnail) ? root.songDetails.authorThumbnail : root.cachedArtistAvatar
                            fillMode: Image.PreserveAspectCrop
                            clip: true
                            asynchronous: true
                        }

                        // Smooth gradient scrim on top of photo
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: 108
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.60) }
                                GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.08) }
                                GradientStop { position: 1.0; color: Qt.rgba(0.08, 0.08, 0.09, 1.0) }
                            }
                        }

                        // Top-left "Nghệ sĩ" Badge
                        Text {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 10
                            text: I18n.tr("Nghệ sĩ", "Artist")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                            color: "#ffffff"
                        }

                        // Bottom Info: Artist Name & Subscribers
                        ColumnLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 10
                            spacing: 3

                            // Shimmer placeholder state when loading
                            ColumnLayout {
                                visible: root.isDetailsLoading
                                spacing: 6

                                Rectangle {
                                    width: 130
                                    height: 14
                                    radius: 4
                                    color: "#38383e"
                                    SequentialAnimation on opacity {
                                        running: root.isDetailsLoading
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0.35; to: 0.70; duration: 800; easing.type: Easing.InOutQuad }
                                        NumberAnimation { from: 0.70; to: 0.35; duration: 800; easing.type: Easing.InOutQuad }
                                    }
                                }

                                Rectangle {
                                    width: 80
                                    height: 11
                                    radius: 3
                                    color: "#28282c"
                                    SequentialAnimation on opacity {
                                        running: root.isDetailsLoading
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0.35; to: 0.70; duration: 800; easing.type: Easing.InOutQuad }
                                        NumberAnimation { from: 0.70; to: 0.35; duration: 800; easing.type: Easing.InOutQuad }
                                    }
                                }
                            }

                            // Loaded real info
                            ColumnLayout {
                                visible: !root.isDetailsLoading
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: (root.songDetails && root.songDetails.author) ? root.songDetails.author : ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                    font.bold: true
                                    color: "#ffffff"
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: (root.songDetails && root.songDetails.subscribers) ? root.songDetails.subscribers : ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.textMuted
                                    elide: Text.ElideRight
                                    visible: text !== ""
                                }
                            }
                        }

                        MouseArea {
                            id: artistCardMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: {
                                var aName = (root.songDetails && root.songDetails.author) ? root.songDetails.author : (root.track ? (root.track.artist || "") : "");
                                var aChannel = (root.songDetails && root.songDetails.channelId) ? root.songDetails.channelId : "";
                                if (aName) {
                                    root.openArtistRequested(aName, aChannel);
                                }
                            }
                        }
                    }

                    // 5. Nutsty Info & Description Card (Release Date, Views, Interactive Likes/Dislikes, Description)
                    Rectangle {
                        id: infoDescCard
                        Layout.fillWidth: true
                        Layout.preferredWidth: root.isCompact ? 260 : 280
                        Layout.maximumWidth: 320
                        Layout.preferredHeight: (root.isDetailsLoading ? descShimmerCol.implicitHeight : descRealCol.implicitHeight) + 24
                        Layout.alignment: Qt.AlignHCenter
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.04)
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1

                        property bool isExpanded: false

                        ColumnLayout {
                            id: descCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 12
                            spacing: 8

                            // --- SHIMMER SKELETON STATE (when root.isDetailsLoading) ---
                            ColumnLayout {
                                id: descShimmerCol
                                Layout.fillWidth: true
                                visible: root.isDetailsLoading
                                spacing: 10

                                // 1. Release date shimmer
                                Rectangle {
                                    width: 110
                                    height: 12
                                    radius: 3
                                    color: "#28282c"
                                    SequentialAnimation on opacity {
                                        running: root.isDetailsLoading
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0.35; to: 0.70; duration: 800; easing.type: Easing.InOutQuad }
                                        NumberAnimation { from: 0.70; to: 0.35; duration: 800; easing.type: Easing.InOutQuad }
                                    }
                                }

                                // 2. View count shimmer
                                Rectangle {
                                    width: 150
                                    height: 20
                                    radius: 4
                                    color: "#38383e"
                                    SequentialAnimation on opacity {
                                        running: root.isDetailsLoading
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0.35; to: 0.70; duration: 800; easing.type: Easing.InOutQuad }
                                        NumberAnimation { from: 0.70; to: 0.35; duration: 800; easing.type: Easing.InOutQuad }
                                    }
                                }

                                // 3. Interactive Likes & Dislikes Row shimmer
                                RowLayout {
                                    spacing: 10

                                    Rectangle {
                                        width: 76
                                        height: 28
                                        radius: 14
                                        color: "#242428"
                                        SequentialAnimation on opacity {
                                            running: root.isDetailsLoading
                                            loops: Animation.Infinite
                                            NumberAnimation { from: 0.35; to: 0.70; duration: 800; easing.type: Easing.InOutQuad }
                                            NumberAnimation { from: 0.70; to: 0.35; duration: 800; easing.type: Easing.InOutQuad }
                                        }
                                    }

                                    Rectangle {
                                        width: 84
                                        height: 28
                                        radius: 14
                                        color: "#242428"
                                        SequentialAnimation on opacity {
                                            running: root.isDetailsLoading
                                            loops: Animation.Infinite
                                            NumberAnimation { from: 0.35; to: 0.70; duration: 800; easing.type: Easing.InOutQuad }
                                            NumberAnimation { from: 0.70; to: 0.35; duration: 800; easing.type: Easing.InOutQuad }
                                        }
                                    }
                                }

                                // 4. Like/Dislike Ratio mini bar shimmer
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 3
                                    radius: 1.5
                                    color: "#28282c"
                                    SequentialAnimation on opacity {
                                        running: root.isDetailsLoading
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0.35; to: 0.70; duration: 800; easing.type: Easing.InOutQuad }
                                        NumberAnimation { from: 0.70; to: 0.35; duration: 800; easing.type: Easing.InOutQuad }
                                    }
                                }

                                // 5. Description Header shimmer
                                Rectangle {
                                    width: 50
                                    height: 12
                                    radius: 3
                                    color: "#38383e"
                                    SequentialAnimation on opacity {
                                        running: root.isDetailsLoading
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0.35; to: 0.70; duration: 800; easing.type: Easing.InOutQuad }
                                        NumberAnimation { from: 0.70; to: 0.35; duration: 800; easing.type: Easing.InOutQuad }
                                    }
                                }

                                // 6. Description Paragraph shimmer (staggered lines)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 11
                                        radius: 3
                                        color: "#28282c"
                                        SequentialAnimation on opacity {
                                            running: root.isDetailsLoading
                                            loops: Animation.Infinite
                                            NumberAnimation { from: 0.35; to: 0.70; duration: 800; easing.type: Easing.InOutQuad }
                                            NumberAnimation { from: 0.70; to: 0.35; duration: 800; easing.type: Easing.InOutQuad }
                                        }
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: Math.max(120, (infoDescCard.width - 24) * 0.85)
                                        height: 11
                                        radius: 3
                                        color: "#28282c"
                                        SequentialAnimation on opacity {
                                            running: root.isDetailsLoading
                                            loops: Animation.Infinite
                                            NumberAnimation { from: 0.35; to: 0.70; duration: 800; easing.type: Easing.InOutQuad }
                                            NumberAnimation { from: 0.70; to: 0.35; duration: 800; easing.type: Easing.InOutQuad }
                                        }
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: Math.max(90, (infoDescCard.width - 24) * 0.58)
                                        height: 11
                                        radius: 3
                                        color: "#28282c"
                                        SequentialAnimation on opacity {
                                            running: root.isDetailsLoading
                                            loops: Animation.Infinite
                                            NumberAnimation { from: 0.35; to: 0.70; duration: 800; easing.type: Easing.InOutQuad }
                                            NumberAnimation { from: 0.70; to: 0.35; duration: 800; easing.type: Easing.InOutQuad }
                                        }
                                    }
                                }
                            }

                            // --- LOADED REAL CONTENT (when !root.isDetailsLoading) ---
                            ColumnLayout {
                                id: descRealCol
                                Layout.fillWidth: true
                                visible: !root.isDetailsLoading
                                spacing: 8

                                // 1. Release date
                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        var d = (root.songDetails && (root.songDetails.dateText || root.songDetails.publishDate)) ? (root.songDetails.dateText || root.songDetails.publishDate) : ((root.track && root.track.year) ? root.track.year : "");
                                        return d ? (I18n.tr("Phát hành lúc ", "Released on ") + d) : I18n.tr("Đã phát hành", "Released");
                                    }
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.textMuted
                                }

                                // 2. View Count
                                Text {
                                    Layout.fillWidth: true
                                    text: ((root.songDetails && root.songDetails.viewsStr && root.songDetails.viewsStr !== "--") ? root.songDetails.viewsStr : "0") + I18n.tr(" lượt xem", " views")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 16
                                    font.bold: true
                                    color: "#ffffff"
                                }

                                // 3. Interactive Likes & Dislikes Row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    // Like interactive button
                                    Rectangle {
                                        height: 28
                                        Layout.preferredWidth: likeRow.implicitWidth + 16
                                        radius: 14
                                        color: root.currentLikeStatus === "LIKE" ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22) : (likeH.hovered ? "#242428" : "#1a1a1d")
                                        border.color: root.currentLikeStatus === "LIKE" ? root.accentColor : "#2c2c30"
                                        border.width: 1

                                        RowLayout {
                                            id: likeRow
                                            anchors.centerIn: parent
                                            spacing: 5

                                            AppIcon {
                                                source: "../assets/icons/thumb-up-symbolic.svg"
                                                iconSize: 12
                                                color: root.currentLikeStatus === "LIKE" ? root.accentColor : "#ffffff"
                                            }

                                            Text {
                                                text: root.localLikesCount > 0 ? (root.songDetails && root.songDetails.likesStr ? root.songDetails.likesStr : "" + root.localLikesCount) + I18n.tr(" thích", " likes") : I18n.tr("Thích", "Like")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.bold: true
                                                color: root.currentLikeStatus === "LIKE" ? root.accentColor : "#ffffff"
                                            }
                                        }

                                        HoverHandler { id: likeH }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.toggleLike()
                                        }
                                    }

                                    // Dislike interactive button
                                    Rectangle {
                                        height: 28
                                        Layout.preferredWidth: dislikeRow.implicitWidth + 16
                                        radius: 14
                                        color: root.currentLikeStatus === "DISLIKE" ? Qt.rgba(1.0, 0.25, 0.25, 0.20) : (dislikeH.hovered ? "#242428" : "#1a1a1d")
                                        border.color: root.currentLikeStatus === "DISLIKE" ? "#ff4444" : "#2c2c30"
                                        border.width: 1

                                        RowLayout {
                                            id: dislikeRow
                                            anchors.centerIn: parent
                                            spacing: 5

                                            AppIcon {
                                                source: "../assets/icons/thumb-down-symbolic.svg"
                                                iconSize: 12
                                                color: root.currentLikeStatus === "DISLIKE" ? "#ff4444" : "#ffffff"
                                            }

                                            Text {
                                                text: root.localDislikesCount > 0 ? (root.songDetails && root.songDetails.dislikesStr ? root.songDetails.dislikesStr : "" + root.localDislikesCount) + I18n.tr(" không thích", " dislikes") : I18n.tr("Không thích", "Dislike")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.bold: true
                                                color: root.currentLikeStatus === "DISLIKE" ? "#ff4444" : Theme.textSecondary
                                            }
                                        }

                                        HoverHandler { id: dislikeH }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.toggleDislike()
                                        }
                                    }

                                    Item { Layout.fillWidth: true }
                                }

                                // Like/Dislike Ratio mini bar
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 3
                                    radius: 1.5
                                    color: "#282828"

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: parent.width * (root.songDetails ? (root.songDetails.likeRatio / 100.0) : 1.0)
                                        radius: 1.5
                                        color: root.accentColor
                                    }
                                }

                                // 4. Description Header
                                Text {
                                    text: I18n.tr("Mô tả", "Description")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: "#ffffff"
                                }

                                // 5. Description Content Text
                                Text {
                                    id: descText
                                    Layout.fillWidth: true
                                    text: (root.songDetails && root.songDetails.description) ? root.songDetails.description : I18n.tr("Không có mô tả cho bài hát này.", "No description available for this track.")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    lineHeight: 1.3
                                    color: Theme.textSecondary
                                    wrapMode: Text.Wrap
                                    maximumLineCount: infoDescCard.isExpanded ? 100 : 4
                                    elide: infoDescCard.isExpanded ? Text.ElideNone : Text.ElideRight
                                }

                                // Expand / Collapse button
                                Text {
                                    visible: descText.lineCount > 4 || (root.songDetails && root.songDetails.description && root.songDetails.description.length > 150)
                                    text: infoDescCard.isExpanded ? I18n.tr("Thu gọn ▲", "Show less ▲") : I18n.tr("Xem thêm ▼", "Show more ▼")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: root.accentColor

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: infoDescCard.isExpanded = !infoDescCard.isExpanded
                                    }
                                }
                            }
                        }
                    }

                    // 6. Album & Release Details Box (Clean, zero Nutsty text)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: root.isCompact ? 260 : 280
                        Layout.maximumWidth: 320
                        Layout.preferredHeight: albRow.implicitHeight + 16
                        Layout.alignment: Qt.AlignHCenter
                        radius: 12
                        color: albH.hovered ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1

                        RowLayout {
                            id: albRow
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10

                            AppIcon {
                                source: "../assets/icons/media-optical-audio-symbolic.svg"
                                iconSize: 18
                                color: root.accentColor
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: (root.songDetails && root.songDetails.albumBrowseId) ? "ALBUM" : "ALBUM / SINGLE"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.bold: true
                                    color: Theme.textMuted
                                }

                                Rectangle {
                                    visible: root.isDetailsLoading && (!root.track || !root.track.album)
                                    width: 120
                                    height: 12
                                    radius: 3
                                    color: "#28282c"
                                    SequentialAnimation on opacity {
                                        running: root.isDetailsLoading && (!root.track || !root.track.album)
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0.35; to: 0.70; duration: 800; easing.type: Easing.InOutQuad }
                                        NumberAnimation { from: 0.70; to: 0.35; duration: 800; easing.type: Easing.InOutQuad }
                                    }
                                }

                                Text {
                                    visible: !(root.isDetailsLoading && (!root.track || !root.track.album))
                                    Layout.fillWidth: true
                                    text: root.track && root.track.album ? root.track.album : (root.songDetails && root.songDetails.album ? root.songDetails.album : "Single")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: Theme.textPrimary
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        HoverHandler { id: albH }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: (root.songDetails && root.songDetails.albumBrowseId) ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (root.songDetails && root.songDetails.albumBrowseId) {
                                    root.viewAlbumRequested({
                                        "browseId": root.songDetails.albumBrowseId,
                                        "title": root.songDetails.album || "Album",
                                        "artist": (root.songDetails.artist || "")
                                    });
                                }
                            }
                        }
                    }

                    // 6. Quick Action Chips Row
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: root.isCompact ? 260 : 280
                        Layout.maximumWidth: 320
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8

                        // Action 1: Download or Open folder
                        Rectangle {
                            Layout.fillWidth: true
                            height: 32
                            radius: 16
                            color: actDlH.hovered ? "#282828" : "#1a1a1c"
                            border.color: "#2c2c30"
                            border.width: 1

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6

                                AppIcon {
                                    source: (root.track && root.track.isLocal) ? "../assets/icons/folder-music-symbolic.svg" : "../assets/icons/download-symbolic.svg"
                                    iconSize: 13
                                    color: "#ffffff"
                                }

                                Text {
                                    text: (root.track && root.track.isLocal) ? I18n.tr("Thư mục", "Folder") : I18n.tr("Tải bài", "Download")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: "#ffffff"
                                }
                            }

                            HoverHandler { id: actDlH }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.track && root.track.isLocal) {
                                        root.openFolderRequested(root.track);
                                    } else {
                                        root.downloadTrackRequested(root.track);
                                    }
                                }
                            }
                        }

                        // Action 2: Start Radio
                        Rectangle {
                            Layout.fillWidth: true
                            height: 32
                            radius: 16
                            color: actRadH.hovered ? "#282828" : "#1a1a1c"
                            border.color: "#2c2c30"
                            border.width: 1

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6

                                AppIcon {
                                    source: "../assets/icons/radio-symbolic.svg"
                                    iconSize: 13
                                    color: "#ffffff"
                                }

                                Text {
                                    text: I18n.tr("Phát Radio", "Radio")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: "#ffffff"
                                }
                            }

                            HoverHandler { id: actRadH }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.startRadioRequested(root.track)
                            }
                        }

                        // Action 3: Copy Link
                        Rectangle {
                            Layout.fillWidth: true
                            height: 32
                            radius: 16
                            color: actCpH.hovered ? "#282828" : "#1a1a1c"
                            border.color: "#2c2c30"
                            border.width: 1

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6

                                AppIcon {
                                    source: "../assets/icons/edit-select-all-symbolic.svg"
                                    iconSize: 12
                                    color: "#ffffff"
                                }

                                Text {
                                    text: I18n.tr("Sao chép", "Copy Link")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: "#ffffff"
                                }
                            }

                            HoverHandler { id: actCpH }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var link = (root.track && root.track.videoId)
                                        ? ("https://music.youtube.com/watch?v=" + root.track.videoId)
                                        : (root.track ? (root.track.path || "") : "");
                                    root.copyLinkRequested(link);
                                }
                            }
                        }
                    }

                    Item { Layout.preferredHeight: 12 }
                }
            }

            // Right: Amberol Synced Lyrics Flow (Seamless Full-Height SimpMusic Style)
            Item {
                id: lyricsCard
                visible: !root.isCompact || root.compactTab === "lyrics"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: root.isCompact ? 200 : 300
                clip: true

                ListView {
                    id: lyricsView
                    anchors.fill: parent
                    readonly property bool isUserScrolling: dragging || moving || flicking
                    anchors.leftMargin: root.isCompact ? 8 : 16
                    anchors.rightMargin: root.isCompact ? 8 : 16
                    clip: false
                    spacing: 20
                    topMargin: 32
                    bottomMargin: height * 0.45
                    currentIndex: root.currentLyricIndex
                    preferredHighlightBegin: height * 0.35
                    preferredHighlightEnd: height * 0.35
                    highlightRangeMode: userScrollTimer.running ? ListView.NoHighlightRange : ListView.ApplyRange
                    highlightMoveDuration: 340
                    highlightMoveVelocity: -1
                    model: root.activeLyrics

                    onMovementStarted: userScrollTimer.restart()
                    onMovementEnded: userScrollTimer.restart()
                    onFlickStarted: userScrollTimer.restart()
                    onFlickEnded: userScrollTimer.restart()

                    delegate: Item {
                        id: lyricRow
                        width: Math.max(100, lyricsView.width - 24)
                        height: Math.max(48, lyricContentItem.implicitHeight + 16)

                        readonly property int signedDist: index - root.currentLyricIndex
                        readonly property int dist: Math.abs(signedDist)
                        // Strict SSOT: Exactly ONE line is current at any time
                        readonly property bool isCurrent: dist === 0
                        readonly property real lineStartTime: (modelData && modelData.time !== undefined) ? modelData.time : 0.0
                        readonly property real lineEndTime: (modelData && modelData.endTime && modelData.endTime > lineStartTime)
                            ? modelData.endTime
                            : ((index + 1 < root.activeLyrics.length) ? root.activeLyrics[index + 1].time : (lineStartTime + 5.0))
                        readonly property real duration: Math.max(0.6, lineEndTime - lineStartTime)
                        readonly property real lineProgress: isCurrent ? Math.min(1.0, Math.max(0.0, (root.currentTime - lineStartTime) / duration)) : 0.0

                        // isHovered: chỉ TRUE khi NHẤN GIỮ chuột trái, không phải hover.
                        readonly property bool isHovered: rowMouse.pressed && !isCurrent

                        readonly property bool isPlainLine: !modelData.hasWords || modelData.isSynthetic || !modelData.words || modelData.words.length === 0
                        readonly property real targetBlur: (isCurrent || lyricsView.isUserScrolling || isHovered) ? 0.0 : (dist === 1 ? 0.20 : (dist === 2 ? 0.42 : (dist === 3 ? 0.65 : 0.85)))
                        readonly property real targetOpacity: isCurrent ? 1.0 : (lyricsView.isUserScrolling ? 0.85 : (isHovered ? 0.90 : (dist === 1 ? 0.46 : (dist === 2 ? 0.22 : (dist === 3 ? 0.10 : 0.04)))))
                        readonly property int targetFontSize: isPlainLine ? 28 : (isCurrent ? 28 : (dist === 1 ? 24 : (dist === 2 ? 20 : (dist === 3 ? 17 : 15))))

                        opacity: targetOpacity
                        transformOrigin: Item.Left
                        scale: isPlainLine ? 1.0 : (isCurrent ? 1.0 : 0.97)
                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                        layer.enabled: !lyricsView.isUserScrolling && !isHovered && targetBlur > 0.01 && dist <= 4
                        layer.effect: MultiEffect {
                            blurEnabled: true
                            blur: lyricRow.targetBlur
                            blurMax: 32
                        }

                        Item {
                            id: lyricContentItem
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            implicitHeight: Math.max(36, (appleMusicFlowLoader.visible && appleMusicFlowLoader.item)
                                ? appleMusicFlowLoader.item.implicitHeight
                                : staticLineTxt.implicitHeight)

                            // Apple Music Word Flow: Traveling wave ripple + phosphor bloom
                            // ONLY for lines with genuine syllable timestamps (hasWords=true AND NOT isSynthetic).
                            Loader {
                                id: appleMusicFlowLoader
                                active: lyricRow.dist <= 1 && modelData.hasWords && !modelData.isSynthetic && modelData.words && modelData.words.length > 0
                                visible: active && (lyricRow.isCurrent ||
                                         (lyricRow.signedDist === -1 && appleMusicFlowLoader.item !== null && appleMusicFlowLoader.item.hasActiveHeldWord))
                                anchors.left: parent.left
                                anchors.right: parent.right
                                sourceComponent: Component {
                                    AppleMusicWordFlow {
                                        words: (modelData.hasWords && !modelData.isSynthetic && modelData.words) ? modelData.words : []
                                        currentTime: root.currentTime
                                        fontSize: 28
                                    }
                                }
                            }

                            // Unified Static Typography: Used for plain LRC lines and inactive lines
                            Text {
                                id: staticLineTxt
                                visible: !appleMusicFlowLoader.visible
                                anchors.left: parent.left
                                anchors.right: parent.right
                                textFormat: Text.PlainText
                                text: modelData.text || ""
                                font.family: Theme.fontFamily
                                font.pixelSize: lyricRow.targetFontSize
                                font.weight: Font.Bold
                                color: lyricRow.isCurrent ? "#ffffff" : "#d8dce8"
                                wrapMode: Text.Wrap
                                lineHeight: 1.28

                                Behavior on color {
                                    ColorAnimation { duration: 180 }
                                }
                                Behavior on font.pixelSize {
                                    NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
                                }
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData && modelData.time !== undefined) {
                                    root.seekRequested(modelData.time);
                                    root.currentLyricIndex = index;
                                    lyricsView.positionViewAtIndex(index, ListView.Center);
                                }
                            }
                        }
                    }

                    // Empty Lyrics Fallback
                    Text {
                        anchors.centerIn: parent
                        text: I18n.tr("Đang tải hoặc không có lời bài hát (Synced Lyrics) cho bài này.", "Loading or no synced lyrics available for this track.")
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        color: Theme.textSecondary
                        visible: root.activeLyrics.length === 0
                    }
                }
            }
        }
    }
}

