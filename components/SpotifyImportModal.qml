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
        root.importCompleted = false;
        root.importPlaylistCover = "";
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
        root.isImporting = true;
        root.importCompleted = false;
        root.errorMessage = "";
        root.importPlaylistId = playlistId;
        root.importPlaylistTitle = playlistTitle || "Spotify Playlist";
        root.importPlaylistCover = coverUrl || (root.resolvedPlaylist ? root.resolvedPlaylist.image : "");
        root.importCurrent = 0;
        root.importTotal = 0;
        root.importPercent = 0;
        root.importCurrentTrack = I18n.tr("Đang kết nối...", "Connecting...");

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
                        statusPollTimer.start();
                    } else if (st.completed && root.isImporting) {
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
        width: 440
        height: root.importCompleted ? 260 : (root.isImporting ? 300 : (root.resolvedPlaylist ? 360 : 230))
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

        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

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
                    border.width: 0
                    visible: !root.isImporting
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
                spacing: 14
                visible: root.isImporting

                Item { Layout.fillHeight: true }

                // Playlist Info Card with Cover Art & Live Spinner
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 68
                    radius: 12
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.28)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 12

                        // Cover Art Thumbnail with Rounded Mask
                        Rectangle {
                            width: 48
                            height: 48
                            radius: 8
                            color: Qt.rgba(255, 255, 255, 0.06)
                            border.color: Qt.rgba(255, 255, 255, 0.12)
                            border.width: 1
                            clip: true

                            Image {
                                id: importCoverImg
                                anchors.fill: parent
                                source: root.importPlaylistCover || (root.resolvedPlaylist ? root.resolvedPlaylist.image : "")
                                fillMode: Image.PreserveAspectCrop
                                visible: status === Image.Ready
                            }

                            AppIcon {
                                anchors.centerIn: parent
                                source: "../assets/icons/media-playlist-consecutive-symbolic.svg"
                                iconSize: 22
                                color: root.accentColor
                                visible: !importCoverImg.visible
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                Layout.fillWidth: true
                                text: root.importPlaylistTitle || I18n.tr("Playlist Spotify", "Spotify Playlist")
                                color: "#ffffff"
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            RowLayout {
                                spacing: 6
                                CircularSpinner {
                                    size: 13
                                    strokeWidth: 2
                                    color: root.accentColor
                                    running: root.isImporting
                                }
                                Text {
                                    text: I18n.tr("Đang khớp nguồn âm thanh chất lượng cao...", "Matching high-quality audio streams...")
                                    color: Theme.textSecondary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                // Progress Bar Container
                Rectangle {
                    Layout.fillWidth: true
                    height: 8
                    radius: 4
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.15)
                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25)
                    border.width: 1
                    clip: true

                    Rectangle {
                        height: parent.height
                        width: parent.width * (Math.max(0, Math.min(100, root.importPercent)) / 100.0)
                        radius: 4
                        color: root.accentColor

                        Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    }
                }

                // Stats text
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

                Item { Layout.fillHeight: true }

                // Cancel Button (Squircle Design System: radius 12, muted rose)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 12
                    color: cancelMouse.containsMouse ? Qt.rgba(244, 63, 94, 0.22) : Qt.rgba(244, 63, 94, 0.12)
                    border.color: cancelMouse.containsMouse ? Qt.rgba(244, 63, 94, 0.50) : Qt.rgba(244, 63, 94, 0.30)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        AppIcon {
                            source: "../assets/icons/window-close-symbolic.svg"
                            iconSize: 13
                            color: cancelMouse.containsMouse ? "#fda4af" : "#f87171"
                        }

                        Text {
                            text: I18n.tr("Hủy Quá Trình Chuyển Giao", "Cancel Transfer")
                            color: cancelMouse.containsMouse ? "#fda4af" : "#f87171"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
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
                spacing: 12
                visible: root.importCompleted && !root.isImporting

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 56
                    height: 56
                    radius: 18
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                    border.width: 1.5

                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/emblem-ok-symbolic.svg"
                        iconSize: 26
                        color: root.accentColor
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: I18n.tr("Chuyển Giao Hoàn Tất!", "Transfer Completed!")
                    color: "#ffffff"
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.bold: true
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: I18n.tr("Playlist đã sẵn sàng trong Danh Sách Phát của Nutsty.", "Playlist is ready in your Nutsty Custom Playlists.")
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 140
                    Layout.preferredHeight: 38
                    radius: 12
                    color: doneMouse.containsMouse ? Qt.lighter(root.accentColor, 1.12) : root.accentColor
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: I18n.tr("Xong", "Done")
                        color: (root.accentColor.r * 0.299 + root.accentColor.g * 0.587 + root.accentColor.b * 0.114) > 0.6 ? "#000000" : "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
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
                                radius: 8
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
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
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
