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
    readonly property bool hasSpotifySession: (root.spotifySpdc !== "" || (typeof win !== "undefined" && win.spotifySpdc !== ""))
    property bool isImporting: false
    property bool isLoadingList: false
    property var spotifyPlaylists: []
    property string errorMessage: ""
    property int currentTab: 0 // 0: User Playlists, 1: Paste Link

    // Import progress properties
    property string importPlaylistTitle: ""
    property string importPlaylistId: ""
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
        root.resolvedPlaylist = null;
        fetchPlaylists();
        checkImportStatus();
    }

    function closeModal() {
        root.opacity = 0.0;
        statusPollTimer.stop();
        root.closeRequested();
    }

    function fetchPlaylists() {
        root.isLoadingList = true;
        root.errorMessage = "";
        var xhr = new XMLHttpRequest();
        var url = "http://127.0.0.1:17890/api/spotify/playlists";
        var effectiveSpdc = root.spotifySpdc || (typeof win !== "undefined" ? win.spotifySpdc : "");
        if (effectiveSpdc) {
            url += "?spdc=" + encodeURIComponent(effectiveSpdc);
        }
        xhr.open("GET", url, true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                root.isLoadingList = false;
                if (xhr.status === 200) {
                    try {
                        var res = JSON.parse(xhr.responseText);
                        if (res.success && Array.isArray(res.playlists)) {
                            root.spotifyPlaylists = res.playlists;
                        } else {
                            if (root.currentTab !== 0) {
                                root.errorMessage = res.error || I18n.tr("Không thể tải danh sách playlist Spotify.", "Unable to load Spotify playlists.");
                            }
                        }
                    } catch(e) {
                        if (root.currentTab !== 0) {
                            root.errorMessage = I18n.tr("Lỗi xử lý dữ liệu từ Spotify.", "Data parse error from Spotify.");
                        }
                    }
                } else {
                    if (root.currentTab !== 0) {
                        root.errorMessage = I18n.tr("Lỗi kết nối máy chủ cục bộ.", "Failed to connect to local server.");
                    }
                }
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

    function startImport(playlistId, playlistTitle) {
        if (!playlistId) return;
        root.isImporting = true;
        root.importCompleted = false;
        root.errorMessage = "";
        root.importPlaylistId = playlistId;
        root.importPlaylistTitle = playlistTitle || "Spotify Playlist";
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
        xhr.send(JSON.stringify({ "playlist_id": playlistId, "playlist_title": playlistTitle }));
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

    // Modal Main Container (LiquidGlass R=20px)
    LiquidGlass {
        id: dialogCard
        width: 520
        height: root.isImporting || root.importCompleted ? 320 : 540
        anchors.centerIn: parent
        radius: 20
        displacement: 22.0
        aberration: 0.03
        bevelWidth: 26.0
        tintColor: Qt.rgba(0.04, 0.05, 0.08, 0.94)
        backgroundSourceItem: root.backgroundSourceItem
        isFlowActive: (typeof win !== "undefined" && win.isPlaying && win.currentTrack !== null)
        clip: true
        z: 2

        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        // Shaded Tint Overlay
        Rectangle {
            anchors.fill: parent
            radius: dialogCard.radius
            color: Qt.rgba(0.05, 0.06, 0.09, 0.88)
            z: 1
        }

        // 1px Hairline Border
        Rectangle {
            anchors.fill: parent
            radius: dialogCard.radius
            color: "transparent"
            border.color: Qt.rgba(255, 255, 255, 0.16)
            border.width: 1
            z: 20
        }

        MouseArea {
            anchors.fill: parent
            z: 2
            onClicked: {} // Block clicks from passing to scrim
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16
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
                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                    border.width: 1

                    AppIcon {
                        anchors.centerIn: parent
                        source: "assets/icons/media-playlist-consecutive-symbolic.svg"
                        iconSize: 18
                        color: root.accentColor
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: I18n.tr("Chuyển Giao Playlist Spotify", "Transfer Spotify Playlists")
                        color: "#ffffff"
                        font.pixelSize: 16
                        font.bold: true
                    }

                    Text {
                        text: I18n.tr("Lưu danh sách phát về Nutsty để nghe vĩnh viễn", "Save playlists to Nutsty for permanent offline/online playback")
                        color: "#9ca3af"
                        font.pixelSize: 12
                    }
                }

                // Close Button
                Rectangle {
                    width: 32
                    height: 32
                    radius: 8
                    color: closeBtnArea.containsMouse ? Qt.rgba(255, 255, 255, 0.1) : "transparent"
                    border.color: closeBtnArea.containsMouse ? Qt.rgba(255, 255, 255, 0.2) : "transparent"
                    border.width: 1
                    visible: !root.isImporting

                    AppIcon {
                        anchors.centerIn: parent
                        source: "assets/icons/window-close-symbolic.svg"
                        iconSize: 14
                        color: closeBtnArea.containsMouse ? "#ffffff" : "#9ca3af"
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
                Layout.preferredHeight: (root.errorMessage && root.currentTab !== 0) ? (errorText.implicitHeight + 16) : 0
                implicitHeight: Layout.preferredHeight
                radius: 10
                color: Qt.rgba(244, 63, 94, 0.15)
                border.color: Qt.rgba(244, 63, 94, 0.35)
                border.width: 1
                visible: (root.errorMessage !== "") && (root.currentTab !== 0)
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
                spacing: 16
                visible: root.isImporting

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 12

                    CircularSpinner {
                        size: 24
                        strokeWidth: 2.5
                        color: root.accentColor
                        running: root.isImporting
                    }

                    Text {
                        text: root.importPlaylistTitle
                        color: "#ffffff"
                        font.pixelSize: 15
                        font.bold: true
                    }
                }

                // Progress Bar Container
                Rectangle {
                    Layout.fillWidth: true
                    height: 10
                    radius: 5
                    color: Qt.rgba(255, 255, 255, 0.08)
                    border.color: Qt.rgba(255, 255, 255, 0.12)
                    border.width: 1
                    clip: true

                    Rectangle {
                        height: parent.height
                        width: parent.width * (Math.max(0, Math.min(100, root.importPercent)) / 100.0)
                        radius: 5
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
                        color: "#9ca3af"
                        font.pixelSize: 12
                    }

                    Text {
                        text: root.importTotal > 0 ? (root.importCurrent + " / " + root.importTotal + " (" + root.importPercent + "%)") : (root.importPercent + "%")
                        color: root.accentColor
                        font.pixelSize: 12
                        font.bold: true
                    }
                }

                Item { Layout.fillHeight: true }

                // Cancel Button (Muted Rose)
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 140
                    height: 36
                    radius: 10
                    color: cancelMouse.containsMouse ? Qt.rgba(244, 63, 94, 0.25) : Qt.rgba(244, 63, 94, 0.15)
                    border.color: Qt.rgba(244, 63, 94, 0.35)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: I18n.tr("Hủy Bỏ", "Cancel")
                        color: "#f87171"
                        font.pixelSize: 13
                        font.bold: true
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
                spacing: 14
                visible: root.importCompleted && !root.isImporting

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 52
                    height: 52
                    radius: 16
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.2)
                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.4)
                    border.width: 1

                    AppIcon {
                        anchors.centerIn: parent
                        source: "assets/icons/emblem-ok-symbolic.svg"
                        iconSize: 26
                        color: root.accentColor
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: I18n.tr("Chuyển Giao Hoàn Tất!", "Transfer Completed!")
                    color: "#ffffff"
                    font.pixelSize: 17
                    font.bold: true
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: I18n.tr("Playlist đã sẵn sàng trong Danh Sách Phát của Nutsty.", "Playlist is ready in your Nutsty Custom Playlists.")
                    color: "#9ca3af"
                    font.pixelSize: 13
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 150
                    height: 38
                    radius: 10
                    color: doneMouse.containsMouse ? Qt.darker(root.accentColor, 1.15) : root.accentColor

                    Text {
                        anchors.centerIn: parent
                        text: I18n.tr("Xong", "Done")
                        color: "#ffffff"
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

            // --- VIEW 3: SELECTION TABS & PLAYLIST LIST ---
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12
                visible: !root.isImporting && !root.importCompleted

                // Segmented Tab Control
                Rectangle {
                    Layout.fillWidth: true
                    height: 38
                    radius: 10
                    color: Qt.rgba(255, 255, 255, 0.05)
                    border.color: Qt.rgba(255, 255, 255, 0.1)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 3
                        spacing: 4

                        // Tab 0: Account Playlists
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 8
                            color: root.currentTab === 0 ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22) : "transparent"
                            border.color: root.currentTab === 0 ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.4) : "transparent"
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: I18n.tr("Playlist của bạn", "Your Playlists")
                                color: root.currentTab === 0 ? "#ffffff" : "#9ca3af"
                                font.pixelSize: 12
                                font.bold: root.currentTab === 0
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.currentTab = 0;
                                    root.errorMessage = "";
                                    if (root.spotifyPlaylists.length === 0) {
                                        root.fetchPlaylists();
                                    }
                                }
                            }
                        }

                        // Tab 1: Paste Link
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 8
                            color: root.currentTab === 1 ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22) : "transparent"
                            border.color: root.currentTab === 1 ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.4) : "transparent"
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: I18n.tr("Dán link Spotify", "Paste Spotify Link")
                                color: root.currentTab === 1 ? "#ffffff" : "#9ca3af"
                                font.pixelSize: 12
                                font.bold: root.currentTab === 1
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.currentTab = 1;
                                    root.errorMessage = "";
                                }
                            }
                        }
                    }
                }

                // --- TAB 0 CONTENT: LIST OF USER PLAYLISTS ---
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.currentTab === 0

                    // Loading spinner
                    CircularSpinner {
                        anchors.centerIn: parent
                        size: 28
                        color: root.accentColor
                        visible: root.isLoadingList
                        running: root.isLoadingList
                    }

                    // Empty or Not Connected Notice
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - 48
                        spacing: 12
                        visible: !root.isLoadingList && root.spotifyPlaylists.length === 0

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 50
                            height: 50
                            radius: 16
                            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                            border.width: 1

                            AppIcon {
                                anchors.centerIn: parent
                                source: "assets/icons/folder-music-symbolic.svg"
                                iconSize: 24
                                color: root.accentColor
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.hasSpotifySession ? I18n.tr("Chưa tìm thấy playlist trong tài khoản", "No Playlists Found in Account") : I18n.tr("Chưa kết nối tài khoản Spotify", "Spotify Account Not Connected")
                            color: "#ffffff"
                            font.pixelSize: 15
                            font.bold: true
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.maximumWidth: 380
                            Layout.alignment: Qt.AlignHCenter
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            text: root.hasSpotifySession
                                ? I18n.tr("Tài khoản Spotify đã kết nối! Bạn có thể dán trực tiếp link playlist Spotify bất kỳ ở tab bên cạnh để nhập và lưu về Nutsty ngay lập tức.", "Spotify connected! You can paste any Spotify playlist link in the tab above to import immediately.")
                                : I18n.tr("Đăng nhập 1-chạm hoặc đồng bộ từ trình duyệt để tải danh sách phát của bạn. Bạn cũng có thể dán link playlist bất kỳ ở tab bên cạnh.", "1-click login or sync from browser to load your playlists. You can also paste any playlist link in the tab above.")
                            color: "#9ca3af"
                            font.pixelSize: 12
                        }

                        Item { Layout.preferredHeight: 6 }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 10

                            // 1-Click Connect Button (only shown if not yet connected)
                            Rectangle {
                                Layout.preferredWidth: 155
                                Layout.preferredHeight: 34
                                radius: 8
                                visible: !root.hasSpotifySession
                                color: connectMouse.containsMouse ? Qt.darker(root.accentColor, 1.15) : root.accentColor

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    AppIcon {
                                        source: "assets/icons/process-working-symbolic.svg"
                                        iconSize: 13
                                        color: "#ffffff"
                                    }
                                    Text {
                                        text: I18n.tr("Kết nối 1-Chạm", "Connect 1-Click")
                                        color: "#ffffff"
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                }

                                MouseArea {
                                    id: connectMouse
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.closeModal();
                                        root.launchSpotifyBrowserLoginRequested();
                                    }
                                }
                            }

                            // Switch to Link Tab Button
                            Rectangle {
                                Layout.preferredWidth: 130
                                Layout.preferredHeight: 34
                                radius: 8
                                color: pasteTabMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.06)
                                border.color: Qt.rgba(255, 255, 255, 0.12)
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: I18n.tr("Dán link trực tiếp", "Paste link directly")
                                    color: "#e5e7eb"
                                    font.pixelSize: 12
                                    font.bold: true
                                }

                                MouseArea {
                                    id: pasteTabMouse
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.currentTab = 1;
                                        root.errorMessage = "";
                                    }
                                }
                            }
                        }
                    }


                    // Playlists ListView
                    ListView {
                        id: playlistView
                        anchors.fill: parent
                        clip: true
                        spacing: 8
                        model: root.spotifyPlaylists
                        visible: !root.isLoadingList && root.spotifyPlaylists.length > 0

                        delegate: Rectangle {
                            id: playlistItem
                            width: playlistView.width
                            height: 56
                            radius: 10
                            color: itemMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(255, 255, 255, 0.03)
                            border.color: itemMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.4) : Qt.rgba(255, 255, 255, 0.07)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 12

                                RoundedImage {
                                    width: 38
                                    height: 38
                                    radius: 8
                                    source: modelData.image || ""
                                    fallbackIcon: "assets/icons/folder-music-symbolic.svg"
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: modelData.title || "Untitled"
                                        color: "#ffffff"
                                        font.pixelSize: 13
                                        font.bold: true
                                    }

                                    Text {
                                        text: (modelData.trackCount || 0) + " " + I18n.tr("bài hát", "tracks")
                                        color: "#9ca3af"
                                        font.pixelSize: 11
                                    }
                                }

                                // Transfer Button
                                Rectangle {
                                    width: 90
                                    height: 30
                                    radius: 8
                                    color: transferMouse.containsMouse ? root.accentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.2)
                                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.4)
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: I18n.tr("Chuyển", "Import")
                                        color: transferMouse.containsMouse ? "#ffffff" : root.accentColor
                                        font.pixelSize: 12
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: transferMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.startImport(modelData.id, modelData.title)
                                    }
                                }
                            }

                            MouseArea {
                                id: itemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                z: -1
                            }
                        }
                    }
                }

                // --- TAB 1 CONTENT: PASTE LINK ---
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 12
                    visible: root.currentTab === 1

                    Text {
                        text: I18n.tr("Dán đường link playlist Spotify (công khai hoặc chia sẻ):", "Paste a Spotify playlist link (public or shared):")
                        color: "#9ca3af"
                        font.pixelSize: 12
                    }

                    // Input Box Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            height: 40
                            radius: 10
                            color: Qt.rgba(255, 255, 255, 0.05)
                            border.color: linkInput.activeFocus ? root.accentColor : Qt.rgba(255, 255, 255, 0.15)
                            border.width: 1

                            TextInput {
                                id: linkInput
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                verticalAlignment: TextInput.AlignVCenter
                                color: "#ffffff"
                                font.pixelSize: 13
                                clip: true
                                selectByMouse: true

                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    text: I18n.tr("Ví dụ: https://open.spotify.com/playlist/...", "E.g. https://open.spotify.com/playlist/...")
                                    color: "#6b7280"
                                    font.pixelSize: 13
                                    visible: !linkInput.text && !linkInput.activeFocus
                                }

                                onAccepted: root.resolveUrl(linkInput.text)
                            }
                        }

                        // Check/Resolve Button
                        Rectangle {
                            width: 80
                            height: 40
                            radius: 10
                            color: checkMouse.containsMouse ? root.accentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.2)
                            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.4)
                            border.width: 1

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6

                                CircularSpinner {
                                    size: 14
                                    color: "#ffffff"
                                    visible: root.isResolvingLink
                                    running: root.isResolvingLink
                                }

                                Text {
                                    text: I18n.tr("Kiểm tra", "Check")
                                    color: checkMouse.containsMouse ? "#ffffff" : root.accentColor
                                    font.pixelSize: 12
                                    font.bold: true
                                    visible: !root.isResolvingLink
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
                        Layout.fillHeight: true
                        radius: 12
                        color: Qt.rgba(255, 255, 255, 0.04)
                        border.color: Qt.rgba(255, 255, 255, 0.08)
                        border.width: 1
                        visible: root.resolvedPlaylist !== null

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 12

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                RoundedImage {
                                    width: 56
                                    height: 56
                                    radius: 10
                                    source: root.resolvedPlaylist ? (root.resolvedPlaylist.image || "") : ""
                                    fallbackIcon: "assets/icons/folder-music-symbolic.svg"
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: root.resolvedPlaylist ? (root.resolvedPlaylist.title || "") : ""
                                        color: "#ffffff"
                                        font.pixelSize: 15
                                        font.bold: true
                                    }

                                    Text {
                                        text: root.resolvedPlaylist ? (root.resolvedPlaylist.trackCount + " " + I18n.tr("bài hát", "tracks")) : ""
                                        color: "#9ca3af"
                                        font.pixelSize: 12
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 38
                                radius: 10
                                color: importLinkMouse.containsMouse ? Qt.darker(root.accentColor, 1.15) : root.accentColor

                                Text {
                                    anchors.centerIn: parent
                                    text: I18n.tr("Bắt Đầu Chuyển Giao", "Start Transfer")
                                    color: "#ffffff"
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
                                            root.startImport(root.resolvedPlaylist.id, root.resolvedPlaylist.title);
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
}
