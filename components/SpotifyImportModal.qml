import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import "."

Rectangle {
    id: root
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.65)
    visible: opacity > 0.001
    opacity: 0.0
    z: 10008

    property Item backgroundSourceItem: null
    property color accentColor: Theme.accent

    // State properties
    property string spotifySpdc: (typeof win !== "undefined" && win.spotifySpdc) ? win.spotifySpdc : ""
    property bool isImporting: false
    property string errorMessage: ""

    // Import progress properties
    property string importPlaylistTitle: ""
    property string importPlaylistId: ""
    property string importPlaylistCover: ""
    property int importCurrent: 0
    property int importTotal: 0
    property int importPercent: 0
    property string importCurrentTrack: ""
    property bool importCompleted: false
    property string importedPlaylistId: ""

    // Arc Rail Gunshot & Morphing properties
    property bool discAtCenter: false
    property bool isTransitioningToLeft: false
    property var arcQueueTracks: [
        "Nơi Này Có Anh - Sơn Tùng M-TP",
        "Chúng Ta Của Hiện Tại - Sơn Tùng M-TP",
        "Âm Thầm Bên Em - Sơn Tùng M-TP",
        "Chạy Ngay Đi - Sơn Tùng M-TP",
        "Lạc Trôi - Sơn Tùng M-TP",
        "Cơn Mưa Ngang Qua - Sơn Tùng M-TP"
    ]
    property int nextQueueTrackIndex: 6
    property var allPlaylistTracks: []
    property string lastFiredTrack: ""

    function formatTrackTitle(t) {
        if (!t) return "";
        if (typeof t === "string") return t;
        var name = t.name || "";
        var artist = t.artist || "";
        return (name && artist) ? (name + " - " + artist) : (name || artist);
    }

    NumberAnimation {
        id: slideAnim
        target: leftVinylDisc
        property: "slideT"
        from: 0.0
        to: 1.0
        duration: 1400
        easing.type: Easing.InOutCubic
        onFinished: {
            root.isTransitioningToLeft = false;
            if (root.isImporting && typeof arcGunshotStage !== "undefined" && arcGunshotStage && typeof arcGunshotStage.fireGunshot === "function") {
                var firstTrack = (root.arcQueueTracks && root.arcQueueTracks.length > 0) ? root.arcQueueTracks[0] : root.importCurrentTrack;
                root.lastFiredTrack = firstTrack;
                arcGunshotStage.fireGunshot(firstTrack);
            }
        }
    }

    function triggerCenterSlide() {
        slideAnim.stop();
        if (typeof leftVinylDisc !== "undefined" && leftVinylDisc) {
            leftVinylDisc.slideT = 0.0;
        }
        if (typeof gunshotProjectile !== "undefined" && gunshotProjectile) {
            gunshotProjectile.projOpacity = 0.0;
        }
        if (typeof projectileAnim !== "undefined" && projectileAnim) {
            projectileAnim.stop();
        }
        root.discAtCenter = true;
        root.isTransitioningToLeft = true;
        discSlideTimer.interval = 800;
        discSlideTimer.restart();
    }

    function shiftQueue() {
        var list = root.arcQueueTracks ? root.arcQueueTracks.slice(0) : [];
        if (list.length > 0) {
            list.shift();
        }
        if (root.allPlaylistTracks && root.nextQueueTrackIndex < root.allPlaylistTracks.length) {
            var nextItem = root.allPlaylistTracks[root.nextQueueTrackIndex];
            root.nextQueueTrackIndex++;
            var nextTitle = root.formatTrackTitle(nextItem);
            if (nextTitle) {
                list.push(nextTitle);
            }
        }
        root.arcQueueTracks = list;
    }

    function testGunshot(track) {
        if (typeof arcGunshotStage !== "undefined" && arcGunshotStage && typeof arcGunshotStage.fireGunshot === "function") {
            arcGunshotStage.fireGunshot(track);
        }
    }

    Timer {
        id: discSlideTimer
        interval: 800
        repeat: false
        onTriggered: {
            root.discAtCenter = false;
            slideAnim.restart();
        }
    }

    property real spiralPhase: 0.0
    property var recentTracks: []

    NumberAnimation on spiralPhase {
        from: 0.0
        to: 2 * Math.PI
        duration: 8000
        loops: Animation.Infinite
        running: root.isImporting
    }

    onImportCurrentTrackChanged: {
        if (root.importCurrentTrack && root.importCurrentTrack.length > 0) {
            var list = root.recentTracks ? root.recentTracks.slice(0) : [];
            if (list.length === 0 || list[0] !== root.importCurrentTrack) {
                list.unshift(root.importCurrentTrack);
                if (list.length > 6) list.pop();
                root.recentTracks = list;
                if (!root.discAtCenter && !root.isTransitioningToLeft) {
                    if (root.lastFiredTrack !== root.importCurrentTrack) {
                        root.lastFiredTrack = root.importCurrentTrack;
                        if (typeof arcGunshotStage !== "undefined" && arcGunshotStage && typeof arcGunshotStage.fireGunshot === "function") {
                            arcGunshotStage.fireGunshot(root.importCurrentTrack);
                        }
                    }
                }
            }
        }
    }

    // Resolved link preview
    property var resolvedPlaylist: null
    property bool isResolvingLink: false

    signal closeRequested()
    signal playlistImported(string playlistId)
    signal openSettingsRequested()
    signal launchSpotifyBrowserLoginRequested()

    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    function openModal() {
        root.opacity = 1.0;
        root.errorMessage = "";
        root.isImporting = false;
        root.discAtCenter = false;
        root.isTransitioningToLeft = false;
        slideAnim.stop();
        if (typeof leftVinylDisc !== "undefined" && leftVinylDisc) {
            leftVinylDisc.slideT = 1.0;
        }
        if (typeof gunshotProjectile !== "undefined" && gunshotProjectile) {
            gunshotProjectile.projOpacity = 0.0;
        }
        if (typeof projectileAnim !== "undefined" && projectileAnim) {
            projectileAnim.stop();
        }
        root.importCompleted = false;
        root.importPlaylistCover = "";
        root.recentTracks = [];
        root.resolvedPlaylist = null;
        if (linkInput) {
            linkInput.text = "";
        }
        checkClipboardLink();
        checkImportStatus();
    }

    function closeModal() {
        root.opacity = 0.0;
        statusPollTimer.stop();
        root.closeRequested();
    }

    function checkClipboardLink() {
        if (typeof __NutstyBridge !== "undefined" && __NutstyBridge && __NutstyBridge.getClipboardText) {
            try {
                var bridgeText = (__NutstyBridge.getClipboardText() || "").trim();
                if (bridgeText && (bridgeText.includes("spotify.com/playlist") || bridgeText.includes("spotify:playlist"))) {
                    if (linkInput && !linkInput.text) {
                        linkInput.text = bridgeText;
                        root.resolveUrl(bridgeText);
                        return;
                    }
                }
            } catch(e) {}
        }
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "http://127.0.0.1:17890/api/clipboard", true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var res = JSON.parse(xhr.responseText);
                    var text = (res.text || "").trim();
                    if (text && (text.includes("spotify.com/playlist") || text.includes("spotify:playlist"))) {
                        if (linkInput && !linkInput.text) {
                            linkInput.text = text;
                            root.resolveUrl(text);
                        }
                    }
                } catch(e) {}
            }
        };
        xhr.send();
    }

    function resolveUrl(urlStr) {
        var clean = (urlStr || "").trim();
        if (!clean) return;
        root.isResolvingLink = true;
        root.errorMessage = "";
        root.resolvedPlaylist = null;

        var xhr = new XMLHttpRequest();
        xhr.open("POST", "http://127.0.0.1:17890/api/spotify/resolve_url", true);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                root.isResolvingLink = false;
                if (xhr.status === 200) {
                    try {
                        var res = JSON.parse(xhr.responseText);
                        if (res.success) {
                            root.resolvedPlaylist = res;
                        } else {
                            root.errorMessage = res.error || I18n.tr("Không thể phân giải link Spotify.", "Unable to resolve Spotify URL.");
                        }
                    } catch(e) {
                        root.errorMessage = I18n.tr("Lỗi đọc dữ liệu phân giải.", "Error parsing resolution data.");
                    }
                } else {
                    root.errorMessage = I18n.tr("Đường dẫn Spotify không hợp lệ hoặc bị khóa.", "Invalid or private Spotify link.");
                }
            }
        };
        var effectiveSpdc = root.spotifySpdc || (typeof win !== "undefined" ? win.spotifySpdc : "");
        xhr.send(JSON.stringify({ "url": clean, "spdc": effectiveSpdc }));
    }

    function startImport(playlistId, playlistTitle, coverUrl) {
        if (!playlistId) return;
        root.triggerCenterSlide();
        root.isImporting = true;
        root.importCompleted = false;
        root.errorMessage = "";
        root.importPlaylistId = playlistId;
        root.importPlaylistTitle = playlistTitle || "Spotify Playlist";
        root.importPlaylistCover = coverUrl || (root.resolvedPlaylist ? root.resolvedPlaylist.image : "");
        root.importCurrent = 0;
        root.importTotal = (root.resolvedPlaylist && root.resolvedPlaylist.trackCount) ? root.resolvedPlaylist.trackCount : 0;
        root.importPercent = 0;
        root.allPlaylistTracks = (root.resolvedPlaylist && root.resolvedPlaylist.tracks) ? root.resolvedPlaylist.tracks : [];
        root.nextQueueTrackIndex = 0;
        root.lastFiredTrack = "";
        if (root.allPlaylistTracks.length > 0) {
            var realList = [];
            var initialCount = Math.min(6, root.allPlaylistTracks.length);
            for (var i = 0; i < initialCount; i++) {
                realList.push(root.formatTrackTitle(root.allPlaylistTracks[i]));
            }
            root.arcQueueTracks = realList;
            root.nextQueueTrackIndex = initialCount;
        } else {
            root.arcQueueTracks = [
                I18n.tr("Đang kết nối...", "Connecting..."),
                I18n.tr("Đang nạp dữ liệu...", "Loading tracks..."),
                I18n.tr("Đang chuẩn bị danh sách...", "Preparing queue..."),
                I18n.tr("Đang phân giải audio...", "Resolving audio..."),
                I18n.tr("Sắp hoàn tất kết nối...", "Almost ready...")
            ];
        }

        var xhr = new XMLHttpRequest();
        xhr.open("POST", "http://127.0.0.1:17890/api/spotify/import_playlist", true);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    statusPollTimer.restart();
                } else {
                    root.isImporting = false;
                    try {
                        var res = JSON.parse(xhr.responseText);
                        root.errorMessage = res.error || I18n.tr("Không thể khởi động chuyển giao.", "Unable to start transfer.");
                    } catch(e) {
                        root.errorMessage = I18n.tr("Lỗi máy chủ.", "Server error.");
                    }
                }
            }
        };
        var effectiveSpdc = root.spotifySpdc || (typeof win !== "undefined" ? win.spotifySpdc : "");
        xhr.send(JSON.stringify({
            "playlist_id": playlistId,
            "playlist_title": playlistTitle,
            "image": root.importPlaylistCover,
            "spdc": effectiveSpdc
        }));
    }

    function cancelImport() {
        var xhr = new XMLHttpRequest();
        xhr.open("POST", "http://127.0.0.1:17890/api/spotify/cancel_import", true);
        xhr.send();
        root.isImporting = false;
        statusPollTimer.stop();
    }

    function checkImportStatus() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "http://127.0.0.1:17890/api/spotify/import_status", true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var st = JSON.parse(xhr.responseText);
                    if (st.active) {
                        root.isImporting = true;
                        root.importPlaylistId = st.playlistId || "";
                        root.importPlaylistTitle = st.playlistTitle || "";
                        if (st.image) {
                            root.importPlaylistCover = st.image;
                        }
                        root.importCurrent = st.current || 0;
                        root.importTotal = st.total || 0;
                        root.importPercent = st.percent || 0;
                        root.importCurrentTrack = st.currentTrack || "";
                        if (st.upcomingTracks && Array.isArray(st.upcomingTracks) && st.upcomingTracks.length > 0) {
                            if (!root.arcQueueTracks || root.arcQueueTracks.length === 0 || 
                                (root.arcQueueTracks.length > 0 && root.arcQueueTracks[0].indexOf("...") !== -1)) {
                                root.arcQueueTracks = st.upcomingTracks.slice(0, 6);
                                if (!root.allPlaylistTracks || root.allPlaylistTracks.length === 0) {
                                    root.allPlaylistTracks = st.upcomingTracks.slice(0);
                                    root.nextQueueTrackIndex = Math.min(6, st.upcomingTracks.length);
                                }
                            }
                        }
                        statusPollTimer.start();
                    } else if (st.completed && root.isImporting && (!root.importPlaylistId || !st.playlistId || st.playlistId === root.importPlaylistId)) {
                        root.isImporting = false;
                        root.importCompleted = true;
                        root.importPercent = 100;
                        root.importedPlaylistId = st.importedPlaylistId || "";
                        if (st.image) {
                            root.importPlaylistCover = st.image;
                        }
                        statusPollTimer.stop();
                        root.playlistImported(root.importedPlaylistId);
                    } else if (st.error && root.isImporting) {
                        root.isImporting = false;
                        root.errorMessage = st.error;
                        statusPollTimer.stop();
                    }
                } catch(e) {}
            }
        };
        xhr.send();
    }

    Timer {
        id: statusPollTimer
        interval: 800
        repeat: true
        onTriggered: root.checkImportStatus()
    }

    // Dismiss on background click
    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (!root.isImporting) {
                root.closeModal();
            }
        }
    }

    // Outer Drop Shadow
    Rectangle {
        id: shadowSourceRect
        anchors.fill: dialogCard
        radius: dialogCard.radius
        color: "#000000"
        visible: false
    }

    MultiEffect {
        anchors.fill: shadowSourceRect
        source: shadowSourceRect
        shadowEnabled: true
        shadowColor: "#99000000"
        shadowVerticalOffset: 8
        shadowBlur: 0.7
        z: 1
    }

    // Modal Main Container: Keo 502 Optical Resin (LiquidGlass, 20px Radius matching PostNoteModal)
    LiquidGlass {
        id: dialogCard
        width: root.importCompleted ? 380 : 440
        height: root.importCompleted ? 240 : (root.isImporting ? 420 : (root.resolvedPlaylist ? 360 : 230))
        anchors.centerIn: parent
        radius: 20
        displacement: 22.0
        aberration: 0.03
        bevelWidth: 26.0
        tintColor: Qt.rgba(0.04, 0.05, 0.08, 0.88)
        backgroundSourceItem: root.backgroundSourceItem
        isFlowActive: (typeof win !== "undefined" && win.isPlaying && win.currentTrack !== null)
        clip: true
        z: 2

        Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

        // Shaded Tint Overlay: Ensures effortless text contrast (matching PostNoteModal)
        Rectangle {
            anchors.fill: parent
            radius: dialogCard.radius
            color: Qt.rgba(0.04, 0.05, 0.08, 0.75)
            z: 1
        }

        // 1px Hairline Border: Keo 502 Surface Tension Rim
        Rectangle {
            anchors.fill: parent
            radius: dialogCard.radius
            color: "transparent"
            border.color: Qt.rgba(255, 255, 255, 0.18)
            border.width: 1
            z: 20
        }

        MouseArea {
            anchors.fill: parent
            z: 2
            onClicked: (mouse) => { mouse.accepted = true; } // Block clicks from passing to scrim
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14
            z: 5

            // --- HEADER ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    width: 36
                    height: 36
                    radius: 10
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.40)
                    border.width: 1

                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/media-playlist-consecutive-symbolic.svg"
                        iconSize: 18
                        color: root.accentColor
                    }
                }

                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true

                    Text {
                        text: I18n.tr("Chuyển Giao Playlist Spotify", "Transfer Spotify Playlists")
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        text: I18n.tr("Lưu danh sách phát về Nutsty để nghe vĩnh viễn", "Save playlists to Nutsty for playback")
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                // Close Button (aligned to far right)
                Rectangle {
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    width: 28
                    height: 28
                    radius: 8
                    color: closeBtnArea.containsMouse ? Qt.rgba(244, 63, 94, 0.14) : "transparent"
                    visible: !root.importCompleted && !root.isImporting
                    Behavior on color { ColorAnimation { duration: 120 } }

                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/window-close-symbolic.svg"
                        iconSize: 13
                        color: closeBtnArea.containsMouse ? "#f43f5e" : Qt.rgba(255, 255, 255, 0.70)
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    MouseArea {
                        id: closeBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeModal()
                    }
                }
            }

            // --- ERROR BANNER ---
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: (root.errorMessage !== "") ? (errorText.implicitHeight + 16) : 0
                implicitHeight: Layout.preferredHeight
                radius: 10
                color: Qt.rgba(244, 63, 94, 0.15)
                border.color: Qt.rgba(244, 63, 94, 0.35)
                border.width: 1
                visible: root.errorMessage !== ""
                clip: true

                Behavior on Layout.preferredHeight { NumberAnimation { duration: 150 } }

                Text {
                    id: errorText
                    anchors.centerIn: parent
                    width: parent.width - 24
                    wrapMode: Text.Wrap
                    text: root.errorMessage
                    color: "#fca5a5"
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            // --- VIEW 1: IMPORTING PROGRESS VIEW ---
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10
                visible: root.isImporting

                // 1. Header: Playlist Title & Subtitle
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        Layout.fillWidth: true
                        text: root.importPlaylistTitle || I18n.tr("Playlist Spotify", "Spotify Playlist")
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Đang hút và khớp nguồn âm thanh chất lượng cao...", "Siphoning and matching high-quality audio streams...")
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }

                // 2. Arc Rail Gunshot Projectile Stage (Vinyl Disc + Shockwave + Curved Arc + Gunshot Projectile)
                Item {
                    id: arcGunshotStage
                    Layout.fillWidth: true
                    Layout.preferredHeight: 180
                    clip: true

                    property real arcShiftProgress: 0.0

                    NumberAnimation {
                        id: shiftAnim
                        target: arcGunshotStage
                        property: "arcShiftProgress"
                        from: 0.0
                        to: 1.0
                        duration: 320
                        easing.type: Easing.OutCubic
                        onFinished: {
                            root.shiftQueue();
                            arcGunshotStage.arcShiftProgress = 0.0;
                        }
                    }

                    // Shockwave Ripple Ring (Impact feedback)
                    Rectangle {
                        id: shockwaveRipple
                        property real rippleSize: 88
                        property real rippleOpacity: 0.0

                        x: leftVinylDisc.x + (leftVinylDisc.width - rippleSize) / 2
                        y: leftVinylDisc.y + (leftVinylDisc.height - rippleSize) / 2
                        width: rippleSize
                        height: rippleSize
                        radius: rippleSize / 2
                        color: "transparent"
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, rippleOpacity)
                        border.width: 2
                        z: 3
                        visible: shockwaveAnim.running
                    }

                    ParallelAnimation {
                        id: shockwaveAnim
                        NumberAnimation {
                            target: shockwaveRipple
                            property: "rippleSize"
                            from: 88
                            to: 175
                            duration: 380
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: shockwaveRipple
                            property: "rippleOpacity"
                            from: 0.85
                            to: 0.0
                            duration: 380
                            easing.type: Easing.OutCubic
                        }
                    }


                    // Left Rotating Vinyl Disc (Recoil Pulse on impact & Morphing Center to Left)
                    Rectangle {
                        id: leftVinylDisc
                        property real discRecoilScale: 1.0
                        property real slideT: 1.0

                        readonly property real centerDiscX: (arcGunshotStage.width > 100 ? (arcGunshotStage.width - width) / 2 : 156)
                        x: (1.0 - slideT) * centerDiscX + slideT * 28
                        anchors.verticalCenter: parent.verticalCenter
                        width: 88
                        height: 88
                        radius: 44
                        color: "#111116"
                        border.color: Qt.rgba(255, 255, 255, 0.16)
                        border.width: 1
                        scale: discRecoilScale
                        z: 5

                        // Outer Vinyl Groove
                        Rectangle {
                            anchors.centerIn: parent
                            width: 74
                            height: 74
                            radius: 37
                            color: "transparent"
                            border.color: Qt.rgba(255, 255, 255, 0.08)
                            border.width: 1
                        }

                        // Inner Vinyl Groove
                        Rectangle {
                            anchors.centerIn: parent
                            width: 60
                            height: 60
                            radius: 30
                            color: "transparent"
                            border.color: Qt.rgba(255, 255, 255, 0.06)
                            border.width: 1
                        }

                        // Center Playlist Cover via RoundedImage
                        Item {
                            anchors.centerIn: parent
                            width: 44
                            height: 44

                            RoundedImage {
                                anchors.fill: parent
                                radius: 22
                                source: root.importPlaylistCover || (root.resolvedPlaylist ? root.resolvedPlaylist.image : "")
                                fallbackIcon: "../assets/icons/media-playlist-consecutive-symbolic.svg"
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: 22
                                color: "transparent"
                                border.color: Qt.rgba(255, 255, 255, 0.25)
                                border.width: 1
                            }
                        }

                        // Spindle Hole
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
                            color: "#09090c"
                            border.color: Qt.rgba(255, 255, 255, 0.40)
                            border.width: 1
                            z: 6
                        }

                        RotationAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 10000
                            loops: Animation.Infinite
                            running: root.isImporting
                        }
                    }

                    SequentialAnimation {
                        id: discRecoilAnim
                        NumberAnimation {
                            target: leftVinylDisc
                            property: "discRecoilScale"
                            to: 1.08
                            duration: 80
                            easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: leftVinylDisc
                            property: "discRecoilScale"
                            to: 1.0
                            duration: 180
                            easing.type: Easing.InOutQuad
                        }
                    }

                    // Right Curved Arc Rail Queue (5 Upcoming Tracks)
                    Item {
                        id: rightArcRail
                        anchors.fill: parent
                        opacity: leftVinylDisc.slideT
                        transform: Translate {
                            x: (1.0 - leftVinylDisc.slideT) * 60
                        }

                        Repeater {
                            model: root.arcQueueTracks ? Math.min(6, root.arcQueueTracks.length) : 0
                            delegate: Item {
                                id: arcTrackItem
                                readonly property int k: index
                                readonly property real slot: k - arcGunshotStage.arcShiftProgress
                                readonly property real clampedSlot: Math.max(0.0, Math.min(4.0, slot))
                                readonly property real arcOffset: Math.sin(clampedSlot / 4.0 * Math.PI) * 20.0

                                x: arcGunshotStage.width - 230 + arcOffset
                                y: 12 + slot * 31
                                width: 175
                                height: 26
                                z: 10 - Math.min(6, Math.max(0, Math.floor(slot)))
                                visible: slot >= -0.8 && slot <= 5.2
                                opacity: {
                                    if (slot < 0.0) return Math.max(0.0, 1.0 + slot);
                                    if (slot > 4.0) return Math.max(0.0, 1.0 - (slot - 4.0));
                                    return 1.0;
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 13
                                    readonly property real highlight: Math.max(0.0, Math.min(1.0, 1.0 - arcTrackItem.slot))
                                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 
                                                   0.08 + highlight * 0.20)
                                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 
                                                         0.20 + highlight * 0.55)
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 6

                                        AppIcon {
                                            source: arcTrackItem.slot <= 0.5 ? "../assets/icons/audio-volume-high-symbolic.svg" : "../assets/icons/folder-music-symbolic.svg"
                                            iconSize: 11
                                            color: arcTrackItem.slot <= 0.5 ? root.accentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.70)
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.arcQueueTracks && root.arcQueueTracks[index] ? root.arcQueueTracks[index] : ""
                                            color: arcTrackItem.slot <= 0.5 ? "#ffffff" : Qt.rgba(255, 255, 255, 0.75)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.bold: arcTrackItem.slot <= 0.5
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Gunshot Projectile (Shoots directly into leftVinylDisc on track intake)
                    Item {
                        id: gunshotProjectile
                        property string trackTitle: ""
                        property real projX: 0
                        property real projY: 0
                        property real projScale: 1.0
                        property real projOpacity: 0.0

                        x: projX
                        y: projY
                        scale: projScale
                        opacity: projOpacity
                        width: 175
                        height: 24
                        z: 10
                        visible: projOpacity > 0.01

                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.85)
                            border.color: "#ffffff"
                            border.width: 1.5

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 4

                                AppIcon {
                                    source: "../assets/icons/media-playback-start-symbolic.svg"
                                    iconSize: 10
                                    color: "#ffffff"
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: gunshotProjectile.trackTitle || root.importCurrentTrack || I18n.tr("Nạp thành công", "Loaded")
                                    color: "#ffffff"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    ParallelAnimation {
                        id: projectileAnim
                        NumberAnimation {
                            target: gunshotProjectile
                            property: "projX"
                            to: leftVinylDisc.x + (leftVinylDisc.width - gunshotProjectile.width) / 2
                            duration: 320
                            easing.type: Easing.InQuad
                        }
                        NumberAnimation {
                            target: gunshotProjectile
                            property: "projY"
                            to: leftVinylDisc.y + (leftVinylDisc.height - gunshotProjectile.height) / 2
                            duration: 320
                            easing.type: Easing.InQuad
                        }
                        NumberAnimation {
                            target: gunshotProjectile
                            property: "projScale"
                            from: 1.0
                            to: 0.3
                            duration: 320
                            easing.type: Easing.InQuad
                        }
                        NumberAnimation {
                            target: gunshotProjectile
                            property: "projOpacity"
                            from: 1.0
                            to: 0.2
                            duration: 320
                            easing.type: Easing.InQuad
                        }
                        onFinished: {
                            gunshotProjectile.projOpacity = 0.0;
                            shockwaveAnim.restart();
                            discRecoilAnim.restart();
                        }
                    }

                    function fireGunshot(loadedTitle) {
                        if (root.discAtCenter || root.isTransitioningToLeft) return;
                        if (shiftAnim.running) {
                            shiftAnim.stop();
                            root.shiftQueue();
                            arcGunshotStage.arcShiftProgress = 0.0;
                        }
                        var trackName = loadedTitle || (root.arcQueueTracks && root.arcQueueTracks.length > 0 ? root.arcQueueTracks[0] : root.importCurrentTrack);
                        gunshotProjectile.trackTitle = trackName;
                        gunshotProjectile.projX = arcGunshotStage.width - 230;
                        gunshotProjectile.projY = 12;
                        gunshotProjectile.projScale = 1.0;
                        gunshotProjectile.projOpacity = 1.0;
                        projectileAnim.restart();
                        shiftAnim.restart();
                    }
                }

                // 3. Progress Bar Container
                Rectangle {
                    Layout.fillWidth: true
                    height: 6
                    radius: 3
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.15)
                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25)
                    border.width: 1
                    clip: true

                    Rectangle {
                        height: parent.height
                        width: parent.width * (Math.max(0, Math.min(100, root.importPercent)) / 100.0)
                        radius: 3
                        color: root.accentColor

                        Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    }
                }

                // 4. Stats & Current Track Text
                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.importCurrentTrack ? (I18n.tr("Đang xử lý: ", "Processing: ") + root.importCurrentTrack) : ""
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }

                    Text {
                        text: (root.importTotal > 0 ? (root.importCurrent + "/" + root.importTotal) : (root.importPercent + "%"))
                        color: "#ffffff"
                        font.pixelSize: 11
                        font.bold: true
                    }
                }

                // Cancel Button (Flat Ghost Text Button, Muted Rose)
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: cancelRow.implicitWidth + 24
                    implicitHeight: 30

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: cancelMouse.containsMouse ? Qt.rgba(244, 63, 94, 0.10) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    RowLayout {
                        id: cancelRow
                        anchors.centerIn: parent
                        spacing: 6

                        AppIcon {
                            source: "../assets/icons/window-close-symbolic.svg"
                            iconSize: 12
                            color: cancelMouse.containsMouse ? "#fda4af" : "#f87171"
                            opacity: cancelMouse.containsMouse ? 1.0 : 0.75
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }

                        Text {
                            text: I18n.tr("Hủy Quá Trình Chuyển Giao", "Cancel Transfer")
                            color: cancelMouse.containsMouse ? "#fda4af" : "#f87171"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: false
                            opacity: cancelMouse.containsMouse ? 1.0 : 0.80
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }
                    }

                    MouseArea {
                        id: cancelMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancelImport()
                    }
                }
            }

            // --- VIEW 2: COMPLETED VIEW ---
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10
                visible: root.importCompleted && !root.isImporting

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    Rectangle {
                        width: 28
                        height: 28
                        radius: 14
                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                        border.width: 1

                        AppIcon {
                            anchors.centerIn: parent
                            source: "../assets/icons/emblem-ok-symbolic.svg"
                            iconSize: 15
                            color: root.accentColor
                        }
                    }

                    Text {
                        text: I18n.tr("Chuyển Giao Hoàn Tất!", "Transfer Completed!")
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                    }
                }

                // Compact Playlist Summary Card
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    radius: 12
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.28)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 10

                        RoundedImage {
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            radius: 10
                            source: root.importPlaylistCover || (root.resolvedPlaylist ? root.resolvedPlaylist.image : "")
                            fallbackIcon: "../assets/icons/media-playlist-consecutive-symbolic.svg"
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: root.resolvedPlaylist ? (root.resolvedPlaylist.title || root.resolvedPlaylist.name || I18n.tr("Playlist của bạn", "Your Playlist")) : I18n.tr("Playlist Spotify", "Spotify Playlist")
                                color: "#ffffff"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: I18n.tr("Đã nạp thành công %1 bài hát", "Successfully imported %1 tracks").arg(root.importTotal > 0 ? root.importTotal : root.importCurrent)
                                color: root.accentColor
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 130
                    Layout.preferredHeight: 34
                    radius: 10
                    color: doneMouse.containsMouse ? Qt.lighter(root.accentColor, 1.12) : root.accentColor
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: I18n.tr("Xong", "Done")
                        color: (root.accentColor.r * 0.299 + root.accentColor.g * 0.587 + root.accentColor.b * 0.114) > 0.6 ? "#000000" : "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                    }

                    MouseArea {
                        id: doneMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeModal()
                    }
                }
            }

            // --- VIEW 3: LINK INPUT & PREVIEW VIEW ---
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12
                visible: !root.isImporting && !root.importCompleted

                Text {
                    text: I18n.tr("Dán đường link playlist Spotify (công khai hoặc chia sẻ):", "Paste a Spotify playlist link (public or shared):")
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }

                // Input Box Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        height: 42
                        radius: 12
                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
                        border.color: linkInput.activeFocus ? root.accentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.30)
                        border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        TextInput {
                            id: linkInput
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            color: "#ffffff"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            clip: true
                            selectByMouse: true

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: I18n.tr("Ví dụ: https://open.spotify.com/playlist/...", "E.g. https://open.spotify.com/playlist/...")
                                color: Qt.rgba(255, 255, 255, 0.35)
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                visible: !linkInput.text && !linkInput.activeFocus
                            }

                            onAccepted: root.resolveUrl(linkInput.text)
                        }
                    }

                    // Check/Resolve Button
                    Rectangle {
                        width: 88
                        height: 42
                        radius: 12
                        color: checkMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.28) : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            CircularSpinner {
                                size: 14
                                color: root.accentColor
                                visible: root.isResolvingLink
                                running: root.isResolvingLink
                            }

                            Text {
                                text: I18n.tr("Kiểm tra", "Check")
                                color: checkMouse.containsMouse ? "#ffffff" : root.accentColor
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                                visible: !root.isResolvingLink
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                        }

                        MouseArea {
                            id: checkMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.resolveUrl(linkInput.text)
                        }
                    }
                }

                // Preview Card for resolved playlist
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 114
                    radius: 12
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.30)
                    border.width: 1
                    visible: root.resolvedPlaylist !== null

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            RoundedImage {
                                width: 48
                                height: 48
                                radius: 10
                                source: root.resolvedPlaylist ? (root.resolvedPlaylist.image || "") : ""
                                fallbackIcon: "../assets/icons/folder-music-symbolic.svg"
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: root.resolvedPlaylist ? (root.resolvedPlaylist.title || "") : ""
                                    color: "#ffffff"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                    font.bold: true
                                }

                                Text {
                                    text: root.resolvedPlaylist ? (root.resolvedPlaylist.trackCount + " " + I18n.tr("bài hát", "tracks")) : ""
                                    color: Theme.textSecondary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 36
                            radius: 10
                            color: importLinkMouse.containsMouse ? Qt.lighter(root.accentColor, 1.12) : root.accentColor
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text {
                                anchors.centerIn: parent
                                text: I18n.tr("Bắt Đầu Chuyển Giao", "Start Transfer")
                                color: (root.accentColor.r * 0.299 + root.accentColor.g * 0.587 + root.accentColor.b * 0.114) > 0.6 ? "#000000" : "#ffffff"
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                            }

                            MouseArea {
                                id: importLinkMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: root.isImporting ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: {
                                    if (root.isImporting) return;
                                    if (root.resolvedPlaylist && root.resolvedPlaylist.id) {
                                        root.startImport(root.resolvedPlaylist.id, root.resolvedPlaylist.title, root.resolvedPlaylist.image);
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                    visible: root.resolvedPlaylist === null
                }
            }
        }
    }
}
