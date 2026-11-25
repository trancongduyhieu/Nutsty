import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Dialogs
import QtCore
import "."
import "lyrics_demo.js" as LyricsDemo

Rectangle {
    id: root
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.58)
    visible: false
    z: 10005

    // =========================================================================
    // Core Properties & State (100% preserved for shell.qml integration)
    // =========================================================================
    property Item backgroundSourceItem: null
    property bool isLoggedIn: false
    property string accountName: ""
    property string accountThumb: ""
    property string accountEmail: ""
    property string statusMessage: ""
    // Status text is localized, so colour and diagnostics are matched in both languages
    readonly property bool statusIsOk: /Success|Connected|thành công|Đã kết nối/.test(statusMessage)
    readonly property bool statusIsError: /Error|Failed|timed out|Lỗi|thất bại|quá thời gian|hết thời gian/.test(statusMessage)
    property bool isProcessing: false
    property bool syncHistoryToGoogle: true
    property bool animatedCoverEnabled: true
    property bool crossfadeEnabled: false
    property bool scrollEdgeFadeEnabled: true
    property bool upNextTilt: false
    // "auto" | "on" | "off"; liteModeAutoActive says whether Auto currently resolves to on (no GPU)
    property string liteMode: "auto"
    property string closeBehavior: "widget"
    property bool liteModeAutoActive: false
    property int crossfadeSeconds: 6
    property bool autoMixEnabled: false
    // Fully bit-perfect lossless holds the DAC alone: AutoMix cannot run
    property bool autoMixLocked: false
    property int cacheLimitMb: 1536
    property var cacheUsage: null
    property bool cacheBusy: false
    // Clean-up feedback: total before the click, then "Freed N MB" for a moment once the new usage arrives
    property real cacheBeforeClear: -1
    property real cacheFreedBytes: 0
    property bool cacheJustCleaned: false
    // Finish feedback only when a clean-up the user started has fully ended (limit trims never set busy)
    onCacheBusyChanged: {
        if (!root.cacheBusy && root.cacheBeforeClear >= 0 && root.cacheUsage) {
            root.cacheFreedBytes = Math.max(0, root.cacheBeforeClear - root.cacheUsage.total);
            root.cacheBeforeClear = -1;
            root.cacheJustCleaned = true;
            cacheDoneTimer.restart();
        }
    }
    Timer { id: cacheDoneTimer; interval: 2400; onTriggered: root.cacheJustCleaned = false }
    property string canvasPreference: "apple_first"
    property int currentTab: 0 // 0: Account, 1: Desktop Lyrics, 2: Playback, 3: Appearance (header order 0, 2, 3, 1)
    onCurrentTabChanged: if (typeof settingsFlickable !== "undefined") settingsFlickable.contentY = 0
    property bool desktopLyricsEnabled: true
    property bool taskbarLyricsEnabled: true
    property string taskbarLyricsPlacement: "taskbar"
    property string taskbarLyricsAlign: "center"
    property bool lyricsRomanizationEnabled: true
    property var kineticOptions: ({})
    property int lyricsPreset: 2 // id from LyricsPresets.qml (1-8)
    property int customX: -1
    property int customY: -1
    property string currentLanguage: I18n.locale
    property string streamingQuality: "high_opus"
    property string downloadQuality: "high_opus"
    property string spotifySpdc: ""
    property string lyricsSource: "auto"
    // Desktop lyrics preset previews: fed the song that is playing, else the demo song
    property var previewLyrics: []
    property real previewTime: 0.0
    property bool previewIsPlaying: false
    property var previewTrack: null
    property string previewWallpaper: ""
    // DesktopLyricsWidget, for the wallpaper palette the previews are drawn in
    property var lyricsHost: null
    readonly property bool lyricsPreviewsLive: root.visible && root.currentTab === 1
    // Preset 8's own panel, laid over the dialog; the preset cards stop while it is up
    property bool kineticPanelOpen: false
    readonly property bool lyricsPreviewUsesSong: root.previewIsPlaying && !!root.previewLyrics && root.previewLyrics.length > 0
    readonly property var demoLyrics: LyricsDemo.build()
    property real demoTime: 0.0
    property real demoLastTick: 0
    onLyricsPreviewsLiveChanged: {
        root.demoTime = 0.0;
        root.demoLastTick = Date.now();
        if (!root.lyricsPreviewsLive) root.kineticPanelOpen = false;
    }
    // A still of the wallpaper for the previews (a video wallpaper is grabbed once)
    WallpaperStill {
        id: wallStill
        source: root.previewWallpaper
    }
    // Demo clock: runs only while the lyrics tab is open and no song feeds the previews
    Timer {
        interval: 33
        repeat: true
        running: root.lyricsPreviewsLive && !root.lyricsPreviewUsesSong
        onRunningChanged: root.demoLastTick = Date.now()
        onTriggered: {
            var now = Date.now();
            var dt = Math.min(0.25, Math.max(0, (now - root.demoLastTick) / 1000.0));
            root.demoLastTick = now;
            root.demoTime = (root.demoTime + dt) % LyricsDemo.DURATION;
        }
    }
    property string spotifyStatusMessage: ""
    property bool spotifyStatusSuccess: false
    property bool spotifyMasked: true
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent
    property bool manualCookieExpanded: false
    property bool spotifyExpanded: false
    property bool spotifyAutoSyncing: false
    property bool manualSpotifyExpanded: false
    property bool spotifyValidating: false
    property string appVersion: "2.5.0"
    property string latestVersion: "2.5.0"
    property bool hasAppUpdate: false
    property bool isCheckingUpdate: false
    property bool isDownloadingUpdate: false
    property real updateProgress: 0.0
    property string updateStatusMessage: ""

    signal checkUpdateRequested()
    signal openUpdateUrlRequested()
    signal startDirectUpdateRequested()
    signal applyUpdateRequested()
    signal openWhatsNewRequested()

    onVisibleChanged: {
        if (visible) root.refreshCacheUsageRequested();
        if (!visible) {
            closeAllDropdowns();
            if (root.isProcessing) {
                root.isProcessing = false;
            }
            root.spotifyValidating = false;
            root.spotifyStatusMessage = "";
            spotifyStatusDismissTimer.stop();
        }
    }

    Timer {
        id: spotifyStatusDismissTimer
        interval: 4000
        repeat: false
        onTriggered: {
            root.spotifyStatusMessage = "";
        }
    }

    onSpotifyStatusMessageChanged: {
        if (root.spotifyStatusMessage.length > 0) {
            spotifyStatusDismissTimer.restart();
        }
    }

    Timer {
        id: spotifyLoginTimeoutTimer
        interval: 180000 // 180 seconds fail-safe timeout
        running: root.spotifyAutoSyncing
        repeat: false
        onTriggered: {
            if (root.spotifyAutoSyncing) {
                root.cancelSpotifyBrowserLoginRequested();
                root.spotifyAutoSyncing = false;
                root.spotifyStatusSuccess = false;
                root.spotifyStatusMessage = I18n.tr(
                    "Đã hết thời gian chờ trình duyệt Spotify (180s). Hãy thử lại hoặc dán cookie sp_dc thủ công.",
                    "Spotify browser login timed out (180s). Please try again or paste sp_dc cookie manually."
                );
            }
        }
    }

    Timer {
        id: loginTimeoutTimer
        interval: 180000 // 180 seconds fail-safe timeout
        running: root.isProcessing
        repeat: false
        onTriggered: {
            if (root.isProcessing) {
                root.cancelBrowserLoginRequested();
                root.isProcessing = false;
                root.statusMessage = I18n.tr(
                    "Đã hết thời gian chờ trình duyệt (180s). Hãy thử lại hoặc dùng dán cookie dự phòng ở dưới.",
                    "Browser login timed out (180s). Please try again or use backup cookie paste below."
                );
            }
        }
    }

    function startSpotifyBrowserLoginFlow() {
        root.autoSyncSpotifyFromBrowsers();
    }

    function startBrowserLoginFlow() {
        root.isProcessing = true;
        root.statusMessage = I18n.tr(
            "Đang mở trình duyệt... Vui lòng chọn tài khoản Google để đăng nhập.",
            "Opening browser window... Please select your Google account."
        );
        loginTimeoutTimer.restart();
        root.launchBrowserLoginRequested();
    }

    function pasteAndConnectFromClipboard() {
        var text = "";
        if (typeof __NutstyBridge !== "undefined" && typeof __NutstyBridge.getClipboardText === "function") {
            text = __NutstyBridge.getClipboardText();
        }
        if (!text && typeof authInput !== "undefined" && authInput) {
            authInput.selectAll();
            authInput.paste();
            text = authInput.text;
        }
        text = (text || "").trim();
        if (!text) {
            root.statusMessage = I18n.tr("Bộ nhớ tạm đang trống. Hãy sao chép mã cookie rồi thử lại.", "Clipboard is empty. Please copy cookie text first.");
            root.manualCookieExpanded = true;
            return;
        }

        var textLower = text.toLowerCase();
        var hasAuthToken = textLower.indexOf("sapisid=") !== -1 ||
                           textLower.indexOf("__secure-3papisid=") !== -1 ||
                           textLower.indexOf("login_info=") !== -1 ||
                           textLower.indexOf("cookie:") !== -1 ||
                           textLower.indexOf("sid=") !== -1;

        if (typeof authInput !== "undefined" && authInput) {
            authInput.text = text;
        }

        if (hasAuthToken) {
            root.statusMessage = I18n.tr("Đã nhận diện cookie từ bộ nhớ tạm! Đang kết nối...", "Detected cookie from Clipboard! Connecting...");
            root.connectRequested(text);
        } else {
            root.statusMessage = I18n.tr("Dữ liệu trong bộ nhớ tạm không chứa cookie YouTube Music hợp lệ. Hãy kiểm tra lại.", "Clipboard does not contain valid YouTube Music cookies. Please check.");
            root.manualCookieExpanded = true;
        }
    }

    function pasteSpotifyCookie() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "http://127.0.0.1:17890/api/clipboard");
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                var text = "";
                if (xhr.status === 200) {
                    try {
                        var res = JSON.parse(xhr.responseText);
                        text = (res.text || "").trim();
                    } catch(e) {}
                }
                if (!text && typeof __NutstyBridge !== "undefined" && typeof __NutstyBridge.getClipboardText === "function") {
                    text = __NutstyBridge.getClipboardText().trim();
                }
                if (!text && typeof spotifyInput !== "undefined" && spotifyInput) {
                    spotifyInput.selectAll();
                    spotifyInput.paste();
                    text = spotifyInput.text.trim();
                }
                applyPastedSpotifyCookie(text);
            }
        };
        xhr.onerror = function() {
            var text = "";
            if (typeof __NutstyBridge !== "undefined" && typeof __NutstyBridge.getClipboardText === "function") {
                text = __NutstyBridge.getClipboardText().trim();
            }
            if (!text && typeof spotifyInput !== "undefined" && spotifyInput) {
                spotifyInput.selectAll();
                spotifyInput.paste();
                text = spotifyInput.text.trim();
            }
            applyPastedSpotifyCookie(text);
        };
        xhr.send();
    }

    function applyPastedSpotifyCookie(text) {
        text = (text || "").trim();
        if (!text) {
            root.spotifyStatusSuccess = false;
            root.spotifyStatusMessage = I18n.tr("Bộ nhớ tạm đang trống. Hãy sao chép chuỗi sp_dc trước.", "Clipboard is empty. Please copy sp_dc string first.");
            return;
        }
        var match = text.match(/sp_dc=([A-Za-z0-9_\-]+)/);
        if (match && match[1]) {
            text = match[1];
        }
        if (typeof spotifyInput !== "undefined" && spotifyInput) {
            spotifyInput.text = text;
        }
        root.spotifyStatusSuccess = true;
        root.spotifyStatusMessage = I18n.tr("Đã dán chuỗi từ bộ nhớ tạm! Bấm Lưu để kết nối.", "Pasted from Clipboard! Click Save to connect.");
    }

    function autoSyncSpotifyFromBrowsers() {
        root.spotifyAutoSyncing = true;
        root.spotifyStatusSuccess = true;
        root.spotifyStatusMessage = I18n.tr(
            "Đang mở trình duyệt... Vui lòng đăng nhập Spotify.",
            "Opening browser window... Please sign in to Spotify."
        );
        spotifyLoginTimeoutTimer.restart();
        root.launchSpotifyBrowserLoginRequested();
    }

    function validateAndSaveSpotifyCookie(val) {
        if (!val || val.length === 0) {
            root.spotifyStatusSuccess = false;
            root.spotifyStatusMessage = I18n.tr("Vui lòng nhập cookie sp_dc trước khi lưu.", "Please enter sp_dc cookie before saving.");
            return;
        }

        root.spotifyValidating = true;
        root.spotifyStatusSuccess = true;
        root.spotifyStatusMessage = I18n.tr("Đang xác thực cookie với máy chủ Spotify...", "Verifying cookie with Spotify servers...");

        var xhr = new XMLHttpRequest();
        xhr.open("POST", "http://127.0.0.1:17890/api/spotify/validate");
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                root.spotifyValidating = false;
                if (xhr.status === 200) {
                    try {
                        var res = JSON.parse(xhr.responseText);
                        if (res && res.success) {
                            root.spotifySpdc = val;
                            root.saveSpotifySpdcRequested(val);
                            root.spotifyStatusSuccess = true;
                            root.spotifyStatusMessage = I18n.tr("Đã xác thực và liên kết Spotify thành công!", "Spotify verified and linked successfully!");
                        } else {
                            root.spotifyStatusSuccess = false;
                            root.spotifyStatusMessage = (res && res.error) ? res.error : I18n.tr("Cookie sp_dc không hợp lệ hoặc đã hết hạn từ Spotify.", "Invalid or expired sp_dc cookie from Spotify.");
                        }
                    } catch (e) {
                        root.spotifyStatusSuccess = false;
                        root.spotifyStatusMessage = I18n.tr("Lỗi xử lý phản hồi từ daemon.", "Error processing response from daemon.");
                    }
                } else {
                    root.spotifyStatusSuccess = false;
                    root.spotifyStatusMessage = I18n.tr("Không thể xác thực cookie (mã lỗi " + xhr.status + ").", "Could not verify cookie (error " + xhr.status + ").");
                }
            }
        };
        xhr.onerror = function() {
            root.spotifyValidating = false;
            root.spotifyStatusSuccess = false;
            root.spotifyStatusMessage = I18n.tr("Lỗi kết nối tới daemon để xác thực.", "Connection error while validating with daemon.");
        };
        xhr.send(JSON.stringify({ "spdc": val }));
    }

    // =========================================================================
    // Signals (100% preserved for shell.qml integration)
    // =========================================================================
    signal closeRequested()
    signal selectLanguageRequested(string lang)
    signal selectStreamingQualityRequested(string quality)
    signal selectDownloadQualityRequested(string quality)
    signal connectRequested(string rawAuth)
    signal logoutRequested()
    signal launchBrowserLoginRequested()
    signal cancelBrowserLoginRequested()
    signal launchSpotifyBrowserLoginRequested()
    signal cancelSpotifyBrowserLoginRequested()
    signal toggleSyncHistoryRequested(bool enabled)

    signal toggleAnimatedCoverRequested(bool enabled)
    signal toggleCrossfadeRequested(bool enabled)
    signal toggleScrollEdgeFadeRequested(bool enabled)
    signal toggleUpNextTiltRequested(bool enabled)
    signal selectLiteModeRequested(string mode)
    signal selectCloseBehaviorRequested(string mode)
    signal selectCrossfadeSecondsRequested(int seconds)
    signal toggleAutoMixRequested(bool enabled)
    signal refreshCacheUsageRequested()
    signal selectCacheLimitRequested(int mb)
    signal clearCacheRequested()
    signal exportPlaylistsRequested(string fileUrl)
    signal importPlaylistsRequested(string fileUrl)
    property bool playlistBackupBusy: false
    property string playlistBackupPending: ""  // "export" / "import" while that button's job runs
    onPlaylistBackupBusyChanged: if (!playlistBackupBusy) playlistBackupPending = ""

    // components/AccountSync.qml, set by shell.qml (null in previews)
    property var accountSync: null
    property var spotifySync: null
    property bool linkCodeEntry: false
    property bool detachConfirm: false
    // Friends of the account this device uses now (the warning before typing a link code)
    property int friendsCount: 0
    property double syncNowMs: Date.now()
    Timer {
        interval: 1000
        repeat: true
        running: root.visible && root.accountSync !== null && root.accountSync.linkCode !== ""
        onTriggered: root.syncNowMs = Date.now()
    }
    Connections {
        target: root.accountSync
        ignoreUnknownSignals: true
        function onLinked(tag) {
            root.linkCodeEntry = false;
            linkCodeInput.text = "";
        }
        function onDetached(tag) {
            root.detachConfirm = false;
        }
    }

    function syncStatusText() {
        var a = root.accountSync;
        if (!a) return "";
        if (!a.enabled)
            return I18n.tr("Đang tắt: máy này chỉ dùng dữ liệu của riêng nó", "Off: this device only uses its own data");
        if (a.running) return I18n.tr("Đang đồng bộ...", "Syncing...");
        if (a.lastError === "server_outdated")
            return I18n.tr("Máy chủ Nutsty chưa được cập nhật để đồng bộ", "The Nutsty server is not updated for sync yet");
        if (a.lastError === "offline")
            return I18n.tr("Chưa kết nối được, sẽ thử lại sau", "Not connected, will retry later");
        if (a.lastError !== "" && a.lastError !== "busy")
            return I18n.tr("Lần đồng bộ trước chưa xong, sẽ tự thử lại sau", "The last sync did not finish, will try again later");
        if (a.lastSync > 0) {
            var at = Qt.formatTime(new Date(a.lastSync), "HH:mm");
            var wait = a.pending > 0 ? I18n.tr(" · " + a.pending + " thay đổi chờ gửi", " · " + a.pending + " changes waiting") : "";
            return I18n.tr("Đồng bộ lần cuối lúc " + at, "Last synced at " + at) + wait;
        }
        return I18n.tr("Danh sách phát, bài đã thích, lịch sử nghe và chỗ đang nghe giống nhau trên mọi máy",
                       "Playlists, liked songs, history and where you stopped stay the same on every device");
    }

    function linkErrorText(err) {
        if (!err) return "";
        if (err === "invalid_code") return I18n.tr("Mã sai hoặc đã hết hạn", "Wrong or expired code");
        if (err === "offline") return I18n.tr("Chưa kết nối được, thử lại sau nhé", "Cannot connect right now, please try again later");
        if (err === "server_outdated")
            return I18n.tr("Máy chủ Nutsty chưa có tính năng này, cần cập nhật máy chủ trước", "The Nutsty server does not have this yet, it needs an update first");
        return I18n.tr("Không kết nối được, thử lại nhé", "Could not link, please try again");
    }

    readonly property url playlistBackupFolder: StandardPaths.writableLocation(StandardPaths.DocumentsLocation)

    FileDialog {
        id: exportPlaylistsDialog
        title: I18n.tr("Lưu bản sao lưu danh sách phát", "Save playlist backup")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "json"
        nameFilters: [I18n.tr("Bản sao lưu Nutsty (*.json)", "Nutsty backup (*.json)")]
        currentFolder: root.playlistBackupFolder
        onAccepted: {
            root.playlistBackupPending = "export";
            root.exportPlaylistsRequested(String(selectedFile));
        }
    }

    FileDialog {
        id: importPlaylistsDialog
        title: I18n.tr("Chọn bản sao lưu danh sách phát", "Choose a playlist backup")
        fileMode: FileDialog.OpenFile
        nameFilters: [I18n.tr("Bản sao lưu Nutsty (*.json)", "Nutsty backup (*.json)")]
        currentFolder: root.playlistBackupFolder
        onAccepted: {
            root.playlistBackupPending = "import";
            root.importPlaylistsRequested(String(selectedFile));
        }
    }

    // Accent-tinted pill used by the playlist backup row (icon + label, spinner while busy)
    component BackupPillButton: Rectangle {
        id: pill
        property string label: ""
        property string iconSource: ""
        property bool busy: false
        // Another job of the same row runs: dim and ignore clicks
        property bool locked: root.playlistBackupBusy && !busy
        // Muted Rose for a step that is hard to undo
        property bool danger: false
        signal activated()
        height: 32
        width: pillRow.implicitWidth + 26
        radius: 16
        color: pill.danger ? Qt.rgba(244 / 255, 63 / 255, 94 / 255, pillMouse.containsMouse ? 0.24 : 0.14)
                           : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, pillMouse.containsMouse ? 0.24 : 0.14)
        opacity: pill.locked ? 0.5 : 1.0
        scale: pillMouse.pressed ? 0.96 : 1.0
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on opacity { NumberAnimation { duration: 150 } }

        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 7

            Item {
                width: 15
                height: 15
                anchors.verticalCenter: parent.verticalCenter

                Image {
                    anchors.centerIn: parent
                    source: pill.iconSource
                    sourceSize: Qt.size(15, 15)
                    width: 15
                    height: 15
                    opacity: pill.busy ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    layer.enabled: true
                    layer.effect: MultiEffect { colorization: 1.0; colorizationColor: "#ffffff" }
                }

                CircularSpinner {
                    anchors.centerIn: parent
                    size: 14
                    strokeWidth: 2
                    color: "#ffffff"
                    running: pill.busy
                    opacity: pill.busy ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.label
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: "#ffffff"
            }
        }

        MouseArea {
            id: pillMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: !pill.locked && !pill.busy
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.activated()
        }
    }
    signal saveCanvasPreferenceRequested(string pref)
    signal toggleDesktopLyricsRequested(bool enabled)
    signal toggleTaskbarLyricsRequested(bool enabled)
    signal changeTaskbarLyricsPlacementRequested(string placement)
    signal changeTaskbarLyricsAlignRequested(string align)
    signal toggleLyricsRomanizationRequested(bool enabled)
    signal changeKineticOptionRequested(string key, var value)
    signal selectLyricsPresetRequested(int preset)
    signal resetLyricsPositionRequested()
    signal saveSpotifySpdcRequested(string spdc)
    signal saveLyricsSourceRequested(string source)
    signal spotifyImportRequested()

    function getCanvasPrefLabel(pref) {
        var p = (pref || "apple_first").toLowerCase().trim();
        if (p === "spotify_first") return "Spotify > Apple";
        if (p === "apple_only") return I18n.tr("Chỉ Apple Music", "Apple Music only");
        if (p === "spotify_only") return I18n.tr("Chỉ Spotify Canvas", "Spotify Canvas only");
        if (p === "off") return I18n.tr("Tắt (Chỉ ảnh tĩnh)", "Off (Static only)");
        return "Apple > Spotify";
    }

    function getLyricsSourceLabel(src) {
        if (src === "youlyplus") {
            return I18n.tr("YouLyPlus (Apple Music/QQ)", "YouLyPlus (Apple Music/QQ)");
        } else if (src === "simpmusic") {
            return I18n.tr("SimpMusic (YouTube Music)", "SimpMusic (YouTube Music)");
        } else if (src === "spotify") {
            return I18n.tr("Spotify (sp_dc)", "Spotify (sp_dc)");
        } else if (src === "betterlyrics") {
            return I18n.tr("Apple Music (BetterLyrics)", "Apple Music (BetterLyrics)");
        } else if (src === "lrclib") {
            return I18n.tr("LRCLIB", "LRCLIB");
        } else if (src === "kugou") {
            return I18n.tr("KuGou (酷狗音乐)", "KuGou (酷狗音乐)");
        } else if (src === "netease") {
            return I18n.tr("NetEase Cloud Music", "NetEase Cloud Music");
        } else if (src === "youtube") {
            return I18n.tr("Phụ đề YouTube", "YouTube Subtitles");
        } else {
            return I18n.tr("Tự động (Đa nguồn song song)", "Auto (Multi-Source)");
        }
    }

    function getQualityLabel(qual, isDownload) {
        if (qual === "high_opus") {
            return I18n.tr("Cao - Opus (256 kbps)", "High - Opus (256 kbps)");
        } else if (qual === "high_aac") {
            return I18n.tr("Cao - AAC (256 kbps)", "High - AAC (256 kbps)");
        } else if (qual === "medium") {
            return isDownload
                ? I18n.tr("Tiêu chuẩn (128 kbps)", "Standard (128 kbps)")
                : I18n.tr("Tiêu chuẩn (129 kbps)", "Standard (129 kbps)");
        } else if (qual === "low") {
            return isDownload
                ? I18n.tr("Tiết kiệm (64 kbps)", "Data Saver (64 kbps)")
                : I18n.tr("Tiết kiệm (66 kbps)", "Data Saver (66 kbps)");
        }
        return I18n.tr("Cao - Opus (256 kbps)", "High - Opus (256 kbps)");
    }

    function getTaskbarPlacementLabel(p) {
        if (p === "above") return I18n.tr("Nổi phía trên Taskbar", "Above Taskbar");
        return I18n.tr("Trên thanh Taskbar", "On Taskbar");
    }

    function getTaskbarAlignLabel(a) {
        if (a === "left") return I18n.tr("Bên trái", "Left");
        if (a === "right") return I18n.tr("Bên phải", "Right");
        return I18n.tr("Căn giữa", "Center");
    }

    function formatBytes(b) {
        var n = Number(b) || 0;
        if (n >= 1073741824) return (n / 1073741824).toFixed(2).replace(".", I18n.tr(",", ".")) + " GB";
        if (n >= 1048576) return Math.round(n / 1048576) + " MB";
        if (n >= 1024) return Math.round(n / 1024) + " KB";
        return n + " B";
    }

    function formatLimit(mb) {
        var gb = mb / 1024;
        var txt = (gb % 1 === 0) ? String(gb) : gb.toFixed(1).replace(".", I18n.tr(",", "."));
        return txt + " GB";
    }

    function closeAllDropdowns() {
        if (typeof langRowItem !== "undefined" && langRowItem) langRowItem.menuOpen = false;
        if (typeof streamQualityRowItem !== "undefined" && streamQualityRowItem) streamQualityRowItem.menuOpen = false;
        if (typeof downloadQualityRowItem !== "undefined" && downloadQualityRowItem) downloadQualityRowItem.menuOpen = false;
        if (typeof canvasPrefRowItem !== "undefined" && canvasPrefRowItem) canvasPrefRowItem.menuOpen = false;
        if (typeof lyricsSourceRowItem !== "undefined" && lyricsSourceRowItem) lyricsSourceRowItem.menuOpen = false;
        if (typeof placementRowItem !== "undefined" && placementRowItem) placementRowItem.menuOpen = false;
        if (typeof alignRowItem !== "undefined" && alignRowItem) alignRowItem.menuOpen = false;
    }

    function toggleStreamingQualityMenu() {
        var next = !(typeof streamQualityRowItem !== "undefined" && streamQualityRowItem.menuOpen);
        closeAllDropdowns();
        if (typeof streamQualityRowItem !== "undefined") streamQualityRowItem.menuOpen = next;
    }

    function toggleDownloadQualityMenu() {
        var next = !(typeof downloadQualityRowItem !== "undefined" && downloadQualityRowItem.menuOpen);
        closeAllDropdowns();
        if (typeof downloadQualityRowItem !== "undefined") downloadQualityRowItem.menuOpen = next;
    }

    function toggleCanvasPrefMenu() {
        var next = !(typeof canvasPrefRowItem !== "undefined" && canvasPrefRowItem.menuOpen);
        closeAllDropdowns();
        if (typeof canvasPrefRowItem !== "undefined") canvasPrefRowItem.menuOpen = next;
    }

    function toggleLyricsSourceMenu() {
        var next = !(typeof lyricsSourceRowItem !== "undefined" && lyricsSourceRowItem.menuOpen);
        closeAllDropdowns();
        if (typeof lyricsSourceRowItem !== "undefined") lyricsSourceRowItem.menuOpen = next;
    }

    function testSpotifyInput(t) {
        if (typeof spotifyInput !== "undefined" && spotifyInput) {
            spotifyInput.text = t;
        }
    }

    function scrollSettings(y) {
        settingsFlickable.contentY = y;
    }

    // =========================================================================
    // Authentic Fonts for Bento Preview Displays
    // =========================================================================
    FontLoader {
        id: instrumentSerifFont
        source: "../assets/fonts/InstrumentSerif-Regular.ttf"
    }

    FontLoader {
        id: instrumentSerifItalicFont
        source: "../assets/fonts/InstrumentSerif-Italic.ttf"
    }

    readonly property string magicFontFamily: (instrumentSerifFont.status === FontLoader.Ready && instrumentSerifFont.name !== "") ? instrumentSerifFont.name : "Instrument Serif"

    FontLoader {
        id: montserratBlackFont
        source: "../assets/fonts/Montserrat-Black.ttf"
    }

    readonly property string heavyFontFamily: (montserratBlackFont.status === FontLoader.Ready && montserratBlackFont.name !== "") ? montserratBlackFont.name : "Montserrat"

    // Click on backdrop dismisses modal
    MouseArea {
        anchors.fill: parent
        onClicked: root.closeRequested()
    }


    // =========================================================================
    // Main Dialog Container: Keo 502 Optical Resin (LiquidGlass, 20px Radius)
    // =========================================================================
    LiquidGlass {
        id: dialog
        width: Math.min(600, root.width - 32)
        height: {
            if (root.currentTab === 1) {
                return Math.min(560, root.height - 48);
            } else {
                return root.isLoggedIn ? Math.min(660, root.height - 48) : Math.min(680, root.height - 48);
            }
        }
        anchors.centerIn: parent
        radius: 20
        displacement: 22.0
        aberration: 0.03
        bevelWidth: 26.0
        tintColor: Qt.rgba(0.04, 0.05, 0.08, 0.92)
        backgroundSourceItem: root.backgroundSourceItem
        isFlowActive: (typeof win !== "undefined" && win.isPlaying && win.currentTrack !== null)
        clip: true
        z: 2

        Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

        // Shaded Tint Overlay: Ensures effortless text contrast over background music cards
        Rectangle {
            anchors.fill: parent
            radius: dialog.radius
            color: Qt.rgba(0.04, 0.05, 0.08, 0.88)
            z: 1
        }

        // 1px Hairline Border: Keo 502 Surface Tension Rim
        Rectangle {
            anchors.fill: parent
            radius: dialog.radius
            color: "transparent"
            border.color: Qt.rgba(255, 255, 255, 0.18)
            border.width: 1
            z: 20
        }

        // Intercept clicks inside dialog so modal doesn't dismiss, and close active dropdowns
        MouseArea {
            anchors.fill: parent
            z: 2
            onClicked: root.closeAllDropdowns()
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 14
            z: 5

            // -----------------------------------------------------------------
            // Header Row: Title & Close Button
            // -----------------------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32

                Text {
                    text: I18n.tr("Cài đặt", "Settings")
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                    font.bold: true
                    color: Theme.textPrimary
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: closeHover.hovered ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.05)
                    border.color: closeHover.hovered ? Qt.rgba(255, 255, 255, 0.16) : Qt.rgba(255, 255, 255, 0.08)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }

                    HoverHandler { id: closeHover }

                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/window-close-symbolic.svg"
                        iconSize: 12
                        color: closeHover.hovered ? "#ffffff" : Theme.textSecondary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }
            }

            // -----------------------------------------------------------------
            // Tab Switcher (Frameless Underline Indicator ___ - Image 1 Style)
            // -----------------------------------------------------------------
            Item {
                id: tabSwitcherRow
                Layout.fillWidth: true
                Layout.preferredHeight: 36

                Row {
                    id: tabsRow
                    spacing: 24
                    anchors.verticalCenter: parent.verticalCenter

                    // Tab 0: Tài khoản
                    Item {
                        id: tab0Btn
                        width: tab0Txt.implicitWidth
                        height: 32

                        Text {
                            id: tab0Txt
                            anchors.centerIn: parent
                            text: I18n.tr("Tài khoản", "Account")
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.bold: root.currentTab === 0
                            color: root.currentTab === 0 ? "#ffffff" : (tab0H.hovered ? "#ffffff" : Qt.rgba(255, 255, 255, 0.60))
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        HoverHandler { id: tab0H }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.closeAllDropdowns();
                                root.currentTab = 0;
                            }
                        }
                    }

                    // Tab 2: Phát nhạc (numbers 0 and 1 stay as they were: shell.qml and the tray open them)
                    Item {
                        id: tab2Btn
                        width: tab2Txt.implicitWidth
                        height: 32

                        Text {
                            id: tab2Txt
                            anchors.centerIn: parent
                            text: I18n.tr("Phát nhạc", "Playback")
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.bold: root.currentTab === 2
                            color: root.currentTab === 2 ? "#ffffff" : (tab2H.hovered ? "#ffffff" : Qt.rgba(255, 255, 255, 0.60))
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        HoverHandler { id: tab2H }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.closeAllDropdowns();
                                root.currentTab = 2;
                            }
                        }
                    }

                    // Tab 3: Giao diện
                    Item {
                        id: tab3Btn
                        width: tab3Txt.implicitWidth
                        height: 32

                        Text {
                            id: tab3Txt
                            anchors.centerIn: parent
                            text: I18n.tr("Giao diện", "Appearance")
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.bold: root.currentTab === 3
                            color: root.currentTab === 3 ? "#ffffff" : (tab3H.hovered ? "#ffffff" : Qt.rgba(255, 255, 255, 0.60))
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        HoverHandler { id: tab3H }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.closeAllDropdowns();
                                root.currentTab = 3;
                            }
                        }
                    }

                    // Tab 1: Lời bài hát Desktop
                    Item {
                        id: tab1Btn
                        width: tab1Txt.implicitWidth
                        height: 32

                        Text {
                            id: tab1Txt
                            anchors.centerIn: parent
                            text: I18n.tr("Lời bài hát Desktop", "Desktop Lyrics")
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.bold: root.currentTab === 1
                            color: root.currentTab === 1 ? "#ffffff" : (tab1H.hovered ? "#ffffff" : Qt.rgba(255, 255, 255, 0.60))
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        HoverHandler { id: tab1H }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.closeAllDropdowns();
                                root.currentTab = 1;
                            }
                        }
                    }
                }

                // Sliding Underline Indicator (___) - The only active underline indicator
                Rectangle {
                    id: tabUnderline
                    anchors.bottom: parent.bottom
                    height: 2
                    radius: 1
                    color: "#ffffff"
                    readonly property Item activeBtn: [tab0Btn, tab1Btn, tab2Btn, tab3Btn][root.currentTab] || tab0Btn
                    x: activeBtn.x
                    width: activeBtn.width

                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
            }

            // Flickable Container: Drag up/down with left mouse button, zero scrollbar column
            Flickable {
                id: settingsFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: scrollContentContainer.height
                boundsBehavior: Flickable.DragAndOvershootBounds
                flickDeceleration: 1500
                pressDelay: 60
                interactive: true

                WheelHandler {
                    onWheel: event => {
                        settingsFlickable.contentY = Math.max(0, Math.min(settingsFlickable.contentHeight - settingsFlickable.height, settingsFlickable.contentY - event.angleDelta.y));
                    }
                }

                Item {
                    id: scrollContentContainer
                    width: settingsFlickable.width
                    height: implicitHeight
                    // Room under the last row so an open dropdown can scroll into view
                    implicitHeight: (root.currentTab === 1
                                     ? tab1Content.implicitHeight + (typeof lyricsSourceRowItem !== "undefined" && lyricsSourceRowItem.menuOpen ? 400 : 0)
                                     : root.currentTab === 2
                                       ? tab2Content.implicitHeight + (streamQualityRowItem.menuOpen || downloadQualityRowItem.menuOpen ? 240 : 30)
                                       : root.currentTab === 3
                                         ? tab3Content.implicitHeight + (langRowItem.menuOpen || canvasPrefRowItem.menuOpen ? 240 : 30)
                                         : tab0Content.implicitHeight + 30) + 8

                    // =========================================================
                    // TAB 0: Google & Cloud Account Content (100% Frameless)
                    // =========================================================
                    ColumnLayout {
                        id: tab0Content
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 14
                        visible: root.currentTab === 0

                // Compact User Profile Row (When Logged In - Frameless)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    visible: root.isLoggedIn

                    Row {
                        anchors.left: parent.left
                        anchors.right: logoutBtn.left
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 14

                        // User Avatar (Zero Black Artifacts Framed Squircle: 44x44, radius: 12)
                        Item {
                            width: 44
                            height: 44

                            // Mask for the avatar image
                            Rectangle {
                                id: avatarMask
                                anchors.fill: parent
                                radius: 12
                                color: "#ffffff"
                                visible: false
                                layer.enabled: true
                            }

                            // Inner Avatar Container with MultiEffect Mask (fills 100% of parent)
                            Item {
                                anchors.fill: parent
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    maskEnabled: true
                                    maskSource: avatarMask
                                    autoPaddingEnabled: false
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: "#202024"
                                }

                                Image {
                                    sourceSize: Qt.size(128, 128)
                                    anchors.fill: parent
                                    source: root.accountThumb
                                    fillMode: Image.PreserveAspectCrop
                                    visible: root.accountThumb !== ""
                                    asynchronous: true
                                    cache: true
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: (typeof win !== "undefined" && win.accentColor) ? Qt.tint(win.accentColor, Qt.rgba(0.2, 0.1, 0.4, 0.7)) : "#6366f1"
                                    visible: root.accountThumb === ""

                                    Text {
                                        anchors.centerIn: parent
                                        text: (root.accountName && root.accountName.length > 0) ? root.accountName.substring(0, 1).toUpperCase() : "G"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 18
                                        font.bold: true
                                        color: "#ffffff"
                                    }
                                }
                            }

                            // Concentric Hairline Outer Border directly framing the avatar edge
                            Rectangle {
                                anchors.fill: parent
                                radius: 12
                                color: "transparent"
                                border.color: Qt.rgba(255, 255, 255, 0.20)
                                border.width: 1
                            }
                        }

                        // Name & Email / Channel Handle
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            width: parent.width - 60

                            Text {
                                text: root.accountName ? root.accountName : I18n.tr("Tài khoản Google", "Google Account")
                                font.family: Theme.fontFamily
                                font.pixelSize: 15
                                font.bold: true
                                color: Theme.textPrimary
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            Text {
                                text: root.accountEmail ? root.accountEmail : I18n.tr("Đã kết nối đám mây", "Connected to Cloud")
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: Theme.textSecondary
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }
                    }

                    // Logout Button (Option 1: Destructive Ghost Action Button)
                    Rectangle {
                        id: logoutBtn
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        height: 28
                        width: logoutTxt.implicitWidth + 18
                        radius: 6
                        color: logoutMouse.containsMouse ? Qt.rgba(244, 63, 94, 0.14) : "transparent"
                        border.width: 0
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            id: logoutTxt
                            anchors.centerIn: parent
                            text: I18n.tr("Đăng xuất", "Log out")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                            color: logoutMouse.containsMouse ? "#fda4af" : "#f87171"
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        MouseArea {
                            id: logoutMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.logoutRequested()
                        }
                    }
                }


                // =============================================================
                // Unified Account Login Block (When NOT Logged In)
                // =============================================================
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: !root.isLoggedIn

                    // 1-Click Native Browser Login Card
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        radius: 12
                        color: root.isProcessing ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35) : (browserLoginMouse.containsMouse ? Qt.lighter(root.accentColor, 1.12) : root.accentColor)
                        border.color: Qt.rgba(255, 255, 255, 0.16)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 12
                            spacing: 8

                            AppIcon {
                                source: root.isProcessing ? "../assets/icons/process-working-symbolic.svg" : "../assets/icons/arrow-outward-symbolic.svg"
                                iconSize: 14
                                color: "#000000"
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.isProcessing ? I18n.tr("Đang chờ đăng nhập trên trình duyệt...", "Waiting for browser login...") : I18n.tr("Đăng nhập Google qua Trình duyệt (1-Chạm)", "Sign in with Google via Browser (1-Click)")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                color: "#000000"
                                elide: Text.ElideRight
                            }

                            // Quick Cancel Button when process is waiting
                            Rectangle {
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 28
                                radius: 6
                                visible: root.isProcessing
                                color: cancelWaitMouse.containsMouse ? Qt.rgba(244, 63, 94, 0.35) : Qt.rgba(244, 63, 94, 0.20)
                                border.color: Qt.rgba(244, 63, 94, 0.40)
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: I18n.tr("Hủy", "Cancel")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    id: cancelWaitMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.cancelBrowserLoginRequested();
                                        root.isProcessing = false;
                                        root.statusMessage = I18n.tr("Đã hủy chờ đăng nhập.", "Login cancelled.");
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: browserLoginMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: root.isProcessing ? Qt.ArrowCursor : Qt.PointingHandCursor
                            enabled: !root.isProcessing
                            onClicked: {
                                root.startBrowserLoginFlow();
                            }
                        }
                    }

                    // Direct Status & Diagnostic Feedback Message
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        visible: root.statusMessage.length > 0

                        Text {
                            Layout.fillWidth: true
                            text: root.statusMessage
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                            color: root.statusIsOk ? root.accentColor : "#f87171"
                            wrapMode: Text.Wrap
                        }

                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr(
                                "Log chẩn đoán: ~/.config/noctalia/browser_login.log (Linux) hoặc %TEMP%\\nutsty\\browser_login.log (Windows)",
                                "Diagnostic log: ~/.config/noctalia/browser_login.log (Linux) or %TEMP%\\nutsty\\browser_login.log (Windows)"
                            )
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Qt.rgba(255, 255, 255, 0.40)
                            wrapMode: Text.Wrap
                            visible: root.statusIsError
                        }
                    }
                }

                // =============================================================
                // Spotify Account Integration (Compact row matching Google)
                // =============================================================
                // Compact Spotify Profile Row (When Logged In - Frameless matching Google)
                Item {
                    id: spotifyConnectedRow
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    visible: root.spotifySpdc && root.spotifySpdc.length > 10

                    Row {
                        anchors.left: parent.left
                        anchors.right: spotifyLogoutBtn.left
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 14

                        // Spotify Squircle (44x44, radius: 12)
                        Item {
                            width: 44
                            height: 44

                            Rectangle {
                                anchors.fill: parent
                                radius: 12
                                color: "#121214"
                                border.color: Qt.rgba(30, 215, 96, 0.35)
                                border.width: 1

                                AppIcon {
                                    anchors.centerIn: parent
                                    source: "../assets/icons/spotify-symbolic.svg"
                                    iconSize: 22
                                    color: "#1ed760"
                                }
                            }
                        }

                        // Account Name & Status
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            width: parent.width - 60

                            Text {
                                text: I18n.tr("Tài khoản Spotify", "Spotify Account")
                                font.family: Theme.fontFamily
                                font.pixelSize: 15
                                font.bold: true
                                color: Theme.textPrimary
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            Text {
                                text: I18n.tr("Đã liên kết cookie • Sẵn sàng tải Canvas và Lời bài hát", "Cookie linked • Ready for Canvas & Lyrics")
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: Theme.textSecondary
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }
                    }

                    // Logout Button (Matching Google Logout button 1:1)
                    Rectangle {
                        id: spotifyLogoutBtn
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        height: 28
                        width: spotifyLogoutTxt.implicitWidth + 18
                        radius: 6
                        color: spotifyLogoutMouse.containsMouse ? Qt.rgba(244, 63, 94, 0.14) : "transparent"
                        border.width: 0
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            id: spotifyLogoutTxt
                            anchors.centerIn: parent
                            text: I18n.tr("Đăng xuất", "Log out")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                            color: spotifyLogoutMouse.containsMouse ? "#fda4af" : "#f87171"
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        MouseArea {
                            id: spotifyLogoutMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.spotifySpdc = "";
                                root.saveSpotifySpdcRequested("");
                                if (typeof spotifyInput !== "undefined" && spotifyInput) {
                                    spotifyInput.text = "";
                                }
                                root.spotifyStatusSuccess = true;
                                root.spotifyStatusMessage = I18n.tr("Đã đăng xuất tài khoản Spotify.", "Logged out of Spotify account.");
                            }
                        }
                    }
                }

                // Two-way Spotify sync, only once a cookie is saved
                SpotifySyncSection {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    Layout.rightMargin: 16
                    visible: root.spotifySync !== null && root.spotifySpdc && root.spotifySpdc.length > 10
                    sync: root.spotifySync
                    accentColor: root.accentColor
                }

                // Spotify Browser Login Block (When NOT Logged In)
                ColumnLayout {
                    id: spotifyDisconnectedCol
                    Layout.fillWidth: true
                    spacing: 8
                    visible: !(root.spotifySpdc && root.spotifySpdc.length > 10)

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        radius: 12
                        color: root.spotifyAutoSyncing
                               ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                               : (spotifyBrowserMouse.containsMouse ? Qt.lighter(root.accentColor, 1.12) : root.accentColor)
                        border.color: Qt.rgba(255, 255, 255, 0.16)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 12
                            spacing: 8

                            AppIcon {
                                source: root.spotifyAutoSyncing
                                        ? "../assets/icons/process-working-symbolic.svg"
                                        : "../assets/icons/arrow-outward-symbolic.svg"
                                iconSize: 14
                                color: "#000000"
                                rotation: 0
                                RotationAnimation on rotation {
                                    loops: Animation.Infinite
                                    from: 0
                                    to: 360
                                    duration: 900
                                    running: root.spotifyAutoSyncing
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.spotifyAutoSyncing
                                      ? I18n.tr("Đang chờ đăng nhập Spotify trên trình duyệt...", "Waiting for Spotify browser login...")
                                      : I18n.tr("Đăng nhập Spotify qua Trình duyệt (1-Chạm)", "Sign in to Spotify via Browser (1-Click)")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                color: "#000000"
                                elide: Text.ElideRight
                            }

                            // Quick Cancel Button when process is waiting
                            Rectangle {
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 28
                                radius: 6
                                visible: root.spotifyAutoSyncing
                                color: cancelSpotifyWaitMouse.containsMouse ? Qt.rgba(244, 63, 94, 0.35) : Qt.rgba(244, 63, 94, 0.20)
                                border.color: Qt.rgba(244, 63, 94, 0.40)
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: I18n.tr("Hủy", "Cancel")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    id: cancelSpotifyWaitMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.cancelSpotifyBrowserLoginRequested();
                                        root.spotifyAutoSyncing = false;
                                        root.spotifyStatusMessage = I18n.tr("Đã hủy chờ đăng nhập Spotify.", "Spotify login cancelled.");
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: spotifyBrowserMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: root.spotifyAutoSyncing ? Qt.ArrowCursor : Qt.PointingHandCursor
                            enabled: !root.spotifyAutoSyncing
                            onClicked: {
                                root.autoSyncSpotifyFromBrowsers();
                            }
                        }
                    }

                    // Status Feedback Message for Spotify
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: spotifyStatusTxt.implicitHeight + 6
                        visible: root.spotifyStatusMessage.length > 0

                        Text {
                            id: spotifyStatusTxt
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 2
                            anchors.rightMargin: 2
                            text: root.spotifyStatusMessage
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                            color: root.spotifyStatusSuccess ? root.accentColor : "#f87171"
                            wrapMode: Text.Wrap
                        }
                    }
                }

                // =============================================================
                // Sync across devices: the same account on another computer (link code, sync now)
                // =============================================================
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    visible: root.accountSync !== null

                    Column {
                        anchors.left: parent.left
                        anchors.right: accountSyncButtons.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: I18n.tr("Đồng bộ giữa các máy", "Sync across devices")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.syncStatusText()
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        id: accountSyncButtons
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        BackupPillButton {
                            label: I18n.tr("Đồng bộ ngay", "Sync now")
                            iconSource: "../assets/icons/view-refresh-symbolic.svg"
                            locked: root.accountSync !== null && !root.accountSync.enabled
                            busy: root.accountSync !== null && root.accountSync.running
                            onActivated: root.accountSync.run()
                        }

                        BackupPillButton {
                            label: I18n.tr("Thêm máy", "Add device")
                            iconSource: "../assets/icons/list-add-symbolic.svg"
                            locked: root.accountSync !== null && root.accountSync.linkBusy && !busy
                            busy: root.accountSync !== null && root.accountSync.linkBusy && !root.linkCodeEntry
                            onActivated: {
                                root.linkCodeEntry = false;
                                root.accountSync.createLinkCode();
                            }
                        }

                        BackupPillButton {
                            label: I18n.tr("Nhập mã", "Enter code")
                            iconSource: "../assets/icons/accessories-text-editor-symbolic.svg"
                            locked: root.accountSync !== null && root.accountSync.linkBusy
                            onActivated: {
                                root.linkCodeEntry = !root.linkCodeEntry;
                                if (root.accountSync) root.accountSync.linkError = "";
                                if (root.linkCodeEntry) linkCodeInput.forceActiveFocus();
                            }
                        }
                    }
                }

                // Why Add device / Sync now did not work (the entry box below shows its own error)
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: -8
                    visible: root.accountSync !== null && root.accountSync.linkError !== "" && !root.linkCodeEntry
                    text: root.accountSync ? root.linkErrorText(root.accountSync.linkError) : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: "#fda4af"
                    wrapMode: Text.WordWrap
                }

                // Code made here, for the other device to type
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    visible: root.accountSync !== null && root.accountSync.linkCode !== "" && !root.linkCodeEntry
                    radius: 14
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.30)
                    border.width: 1

                    readonly property string code: root.accountSync ? root.accountSync.linkCode : ""
                    readonly property int secondsLeft: root.accountSync
                        ? Math.max(0, Math.floor((root.accountSync.linkCodeExpiresAt - root.syncNowMs) / 1000)) : 0

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.right: linkCodeText.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: I18n.tr("Trên máy kia: Cài đặt, Đồng bộ giữa các máy, Nhập mã",
                                          "On the other device: Settings, Sync across devices, Enter code")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: Theme.textPrimary
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            readonly property int secs: parent.parent.secondsLeft
                            readonly property string clock: Math.floor(secs / 60) + ":" + (secs % 60 < 10 ? "0" : "") + (secs % 60)
                            text: I18n.tr("Mã dùng được một lần, còn " + clock, "Works once, " + clock + " left")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        id: linkCodeText
                        anchors.right: parent.right
                        anchors.rightMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.code.length === 6 ? parent.code.slice(0, 3) + "-" + parent.code.slice(3) : parent.code
                        font.family: Theme.fontFamily
                        font.pixelSize: 24
                        font.weight: Font.Bold
                        font.letterSpacing: 2
                        color: root.accentColor
                    }
                }

                // Type the code shown on the other device
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: linkEntryColumn.implicitHeight + 24
                    id: linkEntryBox
                    visible: root.accountSync !== null && root.linkCodeEntry
                    radius: 14
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.30)
                    border.width: 1

                    function submit() {
                        var code = linkCodeInput.text.replace(/[^A-Za-z0-9]/g, "").toUpperCase();
                        if (code.length !== 6 || !root.accountSync || root.accountSync.linkBusy) return;
                        root.accountSync.claimLinkCode(code);
                    }

                    Column {
                        id: linkEntryColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 8

                        Item {
                            width: parent.width
                            height: 36

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: linkConfirmButton.left
                                anchors.rightMargin: 10
                                height: 36
                                radius: 10
                                color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, linkCodeInput.activeFocus ? 0.18 : 0.12)
                                border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, linkCodeInput.activeFocus ? 0.55 : 0.25)
                                border.width: 1

                                TextInput {
                                    id: linkCodeInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    verticalAlignment: TextInput.AlignVCenter
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 2
                                    font.capitalization: Font.AllUppercase
                                    color: "#ffffff"
                                    selectionColor: root.accentColor
                                    maximumLength: 7
                                    clip: true
                                    onAccepted: linkEntryBox.submit()

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: linkCodeInput.text === ""
                                        text: I18n.tr("Mã 6 chữ, ví dụ ABC-DEF", "6-letter code, e.g. ABC-DEF")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: Theme.textSecondary
                                    }
                                }
                            }

                            BackupPillButton {
                                id: linkConfirmButton
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                label: I18n.tr("Kết nối", "Link")
                                iconSource: "../assets/icons/emblem-ok-symbolic.svg"
                                locked: linkCodeInput.text.replace(/[^A-Za-z0-9]/g, "").length !== 6
                                busy: root.accountSync !== null && root.accountSync.linkBusy
                                onActivated: linkEntryBox.submit()
                            }
                        }

                        Text {
                            width: parent.width
                            readonly property string err: root.accountSync ? root.linkErrorText(root.accountSync.linkError) : ""
                            text: err !== "" ? err
                                  : I18n.tr("Máy này sẽ dùng chung tài khoản với máy kia. Danh sách phát đang có ở đây vẫn được giữ và gộp vào.",
                                            "This device will share the other device's account. Playlists already here are kept and merged in.")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: err !== "" ? "#fda4af" : Theme.textSecondary
                            wrapMode: Text.WordWrap
                        }

                        // Friends belong to an account: linking swaps them, so say so before it happens
                        Rectangle {
                            width: parent.width
                            height: friendsWarnText.implicitHeight + 16
                            visible: root.friendsCount > 0 && root.accountSync !== null && root.accountSync.homeTag === ""
                            radius: 10
                            color: Qt.rgba(244 / 255, 63 / 255, 94 / 255, 0.12)
                            border.color: Qt.rgba(244 / 255, 63 / 255, 94 / 255, 0.30)
                            border.width: 1

                            Text {
                                id: friendsWarnText
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                text: I18n.tr("Máy này đang có " + root.friendsCount + " bạn bè. Sau khi nối, máy sẽ thấy bạn bè và ghi chú của tài khoản kia thay vào. Bạn bè hiện tại không mất: chúng được cất lại và trở về khi bấm Tách ra.",
                                              "This device has " + root.friendsCount + (root.friendsCount === 1 ? " friend" : " friends") + ". Once linked it shows the other account's friends and notes instead. Your current friends are not lost: they are kept aside and come back when you press Detach.")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.textPrimary
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                // The devices sharing this account, this one first
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.accountSync !== null && root.accountSync.linkedToOthers
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Các máy đang dùng chung tài khoản", "Devices sharing this account")
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.textSecondary
                    }

                    Repeater {
                        model: root.accountSync ? root.accountSync.devices : []

                        Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            radius: 10
                            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, modelData.self ? 0.14 : 0.08)

                            Image {
                                id: deviceIcon
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                source: "../assets/icons/computer-symbolic.svg"
                                sourceSize: Qt.size(15, 15)
                                width: 15
                                height: 15
                                layer.enabled: true
                                layer.effect: MultiEffect { colorization: 1.0; colorizationColor: root.accentColor }
                            }

                            Text {
                                anchors.left: deviceIcon.right
                                anchors.leftMargin: 10
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: (modelData.name || I18n.tr("Máy không tên", "Unnamed device"))
                                      + (modelData.self ? I18n.tr("  (máy này)", "  (this device)") : "")
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: modelData.self
                                color: Theme.textPrimary
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // Sync on/off for this device (off: everything stays here, turning it back on merges)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    visible: root.accountSync !== null

                    readonly property bool on: root.accountSync !== null && root.accountSync.enabled
                    // Nothing to sync with until another device is linked (still usable to turn a stuck "off" back on)
                    readonly property bool usable: root.accountSync !== null
                                                   && (root.accountSync.linkedToOthers || !root.accountSync.enabled)

                    Column {
                        anchors.left: parent.left
                        anchors.right: toggleAccountSync.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: I18n.tr("Đồng bộ trên máy này", "Sync on this device")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: parent.parent.usable
                                ? I18n.tr("Tắt thì mọi thứ vẫn còn trên máy này nhưng không gửi đi hay nhận về. Bật lại sẽ gộp những gì đã đổi.",
                                          "Off keeps everything on this device but sends and receives nothing. Turning it back on merges what changed.")
                                : I18n.tr("Máy này chưa nối với máy nào. Bấm Thêm máy hoặc Nhập mã ở trên để bắt đầu.",
                                          "This device is not linked to any other yet. Use Add device or Enter code above to start.")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        id: toggleAccountSync
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        height: 24
                        radius: 12
                        color: parent.on ? root.accentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                        opacity: parent.usable ? 1.0 : 0.35
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        Rectangle {
                            width: 18
                            height: 18
                            radius: 9
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                            x: parent.parent.on ? parent.width - width - 3 : 3
                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            preventStealing: false
                            enabled: parent.parent.usable
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.accountSync.setEnabled(!root.accountSync.enabled)
                        }
                    }
                }

                // Detach: this device gets an account of its own (a code typed by mistake, a computer given away)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    visible: root.accountSync !== null && root.accountSync.linkedToOthers && !root.detachConfirm

                    Column {
                        anchors.left: parent.left
                        anchors.right: detachButton.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: I18n.tr("Tách máy này ra", "Detach this device")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: I18n.tr("Máy này nhận một tài khoản riêng, giữ những gì đang có và thôi đồng bộ với các máy kia",
                                          "This device gets its own account, keeps what it has and stops syncing with the others")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }

                    BackupPillButton {
                        id: detachButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        danger: true
                        label: I18n.tr("Tách ra", "Detach")
                        iconSource: "../assets/icons/window-close-symbolic.svg"
                        locked: root.accountSync !== null && (root.accountSync.running || root.accountSync.linkBusy)
                        onActivated: {
                            if (root.accountSync) root.accountSync.detachError = "";
                            root.detachConfirm = true;
                        }
                    }
                }

                // Confirm the detach: say plainly what changes
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: detachConfirmColumn.implicitHeight + 24
                    visible: root.accountSync !== null && root.accountSync.linkedToOthers && root.detachConfirm
                    radius: 14
                    color: Qt.rgba(244 / 255, 63 / 255, 94 / 255, 0.10)
                    border.color: Qt.rgba(244 / 255, 63 / 255, 94 / 255, 0.30)
                    border.width: 1

                    Column {
                        id: detachConfirmColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 10

                        Text {
                            width: parent.width
                            text: I18n.tr("Tách máy này ra khỏi tài khoản?", "Detach this device from the account?")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            width: parent.width
                            readonly property string err: root.accountSync && root.accountSync.detachError !== ""
                                ? root.linkErrorText(root.accountSync.detachError) : ""
                            readonly property string home: root.accountSync ? root.accountSync.homeTag : ""
                            text: err !== "" ? err
                                  : (home !== ""
                                     ? I18n.tr("Máy này quay về tài khoản riêng @" + home + " cùng bạn bè và ghi chú từ trước khi nối. Danh sách phát, bài đã thích và lịch sử nghe vẫn ở lại máy này. Bạn bè và ghi chú của tài khoản chung ở lại trên các máy kia.",
                                               "This device goes back to its own account @" + home + " with the friends and notes it had before linking. Playlists, liked songs and history stay here. The shared account's friends and notes stay on the other devices.")
                                     : I18n.tr("Máy này nhận một tài khoản mới, chưa có bạn bè nào. Danh sách phát, bài đã thích và lịch sử nghe vẫn ở lại máy này. Bạn bè và ghi chú của tài khoản chung ở lại trên các máy kia. Muốn nối lại thì dùng Thêm máy và Nhập mã như lúc đầu.",
                                               "This device gets a new account with no friends yet. Playlists, liked songs and history stay here. The shared account's friends and notes stay on the other devices. To link again, use Add device and Enter code as before."))
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: err !== "" ? "#fda4af" : Theme.textSecondary
                            wrapMode: Text.WordWrap
                        }

                        Row {
                            spacing: 8

                            BackupPillButton {
                                danger: true
                                label: I18n.tr("Tách máy này", "Detach this device")
                                iconSource: "../assets/icons/window-close-symbolic.svg"
                                locked: false
                                busy: root.accountSync !== null && root.accountSync.detachBusy
                                onActivated: root.accountSync.detach()
                            }

                            BackupPillButton {
                                label: I18n.tr("Thôi", "Cancel")
                                iconSource: "../assets/icons/go-previous-symbolic.svg"
                                locked: root.accountSync !== null && root.accountSync.detachBusy
                                onActivated: root.detachConfirm = false
                            }
                        }
                    }
                }

                // Sync History to Google Toggle (Frameless Row, Toggle Pinned to Right)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46

                    Column {
                        anchors.left: parent.left
                        anchors.right: toggleSyncHistory.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: I18n.tr("Đồng bộ lịch sử nghe nhạc lên đám mây (YouTube Music)", "Sync listening history to Cloud (YouTube Music)")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: I18n.tr("Cập nhật lịch sử xem và gợi ý cá nhân hóa trên tài khoản Google", "Update watch history and personalized recommendations on Google Account")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                        }
                    }

                    // Toggle Switch Pill (Pinned to Right)
                    Rectangle {
                        id: toggleSyncHistory
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        height: 24
                        radius: 12
                        color: root.syncHistoryToGoogle ? root.accentColor : Qt.rgba(255, 255, 255, 0.14)
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            width: 18
                            height: 18
                            radius: 9
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.syncHistoryToGoogle ? parent.width - width - 3 : 3
                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            preventStealing: false
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.syncHistoryToGoogle = !root.syncHistoryToGoogle;
                                root.toggleSyncHistoryRequested(root.syncHistoryToGoogle);
                            }
                        }
                    }
                }

                // =============================================================
                // Playlist backup: export / import custom + favorite playlists as JSON
                // =============================================================
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52

                    Column {
                        anchors.left: parent.left
                        anchors.right: playlistBackupButtons.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: I18n.tr("Sao lưu danh sách phát", "Playlist backup")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: I18n.tr("Lưu ra file JSON để chuyển sang máy khác hoặc khi cài lại ứng dụng",
                                          "Save to a JSON file to move to another computer or after reinstalling")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        id: playlistBackupButtons
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        BackupPillButton {
                            label: I18n.tr("Xuất file", "Export")
                            iconSource: "../assets/icons/arrow-outward-symbolic.svg"
                            busy: root.playlistBackupBusy && root.playlistBackupPending === "export"
                            onActivated: {
                                exportPlaylistsDialog.selectedFile = root.playlistBackupFolder + "/nutsty-playlists-"
                                    + Qt.formatDate(new Date(), "yyyy-MM-dd") + ".json";
                                exportPlaylistsDialog.open();
                            }
                        }

                        BackupPillButton {
                            label: I18n.tr("Nhập file", "Import")
                            iconSource: "../assets/icons/download-symbolic.svg"
                            busy: root.playlistBackupBusy && root.playlistBackupPending === "import"
                            onActivated: importPlaylistsDialog.open()
                        }
                    }
                }

                // Status Message (When Logged In)
                Text {
                    Layout.fillWidth: true
                    text: root.statusMessage
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.bold: true
                    color: root.statusIsOk ? root.accentColor : "#f87171"
                    visible: root.isLoggedIn && root.statusMessage.length > 0
                    wrapMode: Text.Wrap
                }

            } // Close tab0Content

                    // =========================================================
                    // TAB 2: Playback (quality, crossfade, cache)
                    // =========================================================
                    ColumnLayout {
                        id: tab2Content
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 14
                        visible: root.currentTab === 2

                // Streaming Audio Quality Row (100% Borderless, Expandable Clean Dropdown Pinned to Right)
                Item {
                    id: streamQualityRowItem
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    z: menuOpen ? 100 : 2

                    property bool menuOpen: false

                    Column {
                        anchors.left: parent.left
                        anchors.right: streamDropdownBtn.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: I18n.tr("Chất lượng phát trực tuyến", "Streaming Audio Quality")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: I18n.tr("Độ phân giải âm thanh khi nghe trực tuyến từ YouTube Music", "Audio stream bitrate when listening online from YouTube Music")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                        }
                    }

                    // Dropdown Trigger (Option 1: Chromatic Ghost Action Button)
                    Rectangle {
                        id: streamDropdownBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 28
                        width: streamBtnRow.implicitWidth + 16
                        radius: 6
                        color: (streamBtnMouse.containsMouse || streamQualityRowItem.menuOpen)
                               ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                               : "transparent"
                        border.width: 0

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row {
                            id: streamBtnRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: root.getQualityLabel(root.streamingQuality, false)
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                                color: (streamBtnMouse.containsMouse || streamQualityRowItem.menuOpen) ? "#ffffff" : Qt.rgba(255, 255, 255, 0.85)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            AppIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                source: "../assets/icons/go-down-symbolic.svg"
                                iconSize: 10
                                color: root.accentColor
                                rotation: streamQualityRowItem.menuOpen ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }
                        }

                        MouseArea {
                            id: streamBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var next = !streamQualityRowItem.menuOpen;
                                root.closeAllDropdowns();
                                streamQualityRowItem.menuOpen = next;
                            }
                        }
                    }

                    // Chromatic Salience Dropdown Popover Menu (Zero Dull Grey)
                    Rectangle {
                        id: streamDropdownMenu
                        visible: streamQualityRowItem.menuOpen
                        anchors.top: streamDropdownBtn.bottom
                        anchors.topMargin: 6
                        anchors.right: streamDropdownBtn.right
                        width: 250
                        height: streamCol.implicitHeight + 10
                        radius: 10
                        color: Qt.rgba(0.06 + root.accentColor.r * 0.08, 0.06 + root.accentColor.g * 0.08, 0.08 + root.accentColor.b * 0.12, 0.96)
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                        border.width: 1
                        z: 100

                        Column {
                            id: streamCol
                            anchors.top: parent.top
                            anchors.topMargin: 5
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 3

                            readonly property var qualityOptions: [
                                {
                                    key: "high_opus",
                                    name: I18n.tr("Cao - Opus (256 kbps)", "High - Opus (256 kbps)"),
                                    desc: I18n.tr("Chi tiết cao nhất, nén Opus hiện đại", "Highest detail, modern Opus compression")
                                },
                                {
                                    key: "high_aac",
                                    name: I18n.tr("Cao - AAC (256 kbps)", "High - AAC (256 kbps)"),
                                    desc: I18n.tr("Âm thanh ấm áp, tương thích tối đa", "Warm sound, maximum compatibility")
                                },
                                {
                                    key: "medium",
                                    name: I18n.tr("Tiêu chuẩn (129 kbps)", "Standard (129 kbps)"),
                                    desc: I18n.tr("Cân bằng băng thông và chất lượng", "Balanced data usage and quality")
                                },
                                {
                                    key: "low",
                                    name: I18n.tr("Tiết kiệm (66 kbps)", "Data Saver (66 kbps)"),
                                    desc: I18n.tr("Tối ưu khi mạng yếu hoặc 4G", "Optimized for slow network or 4G")
                                }
                            ]

                            Repeater {
                                model: streamCol.qualityOptions
                                delegate: Rectangle {
                                    width: streamCol.width - 10
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    height: 42
                                    radius: 7
                                    color: (root.streamingQuality === modelData.key)
                                           ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.26)
                                           : (streamItemMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14) : "transparent")
                                    border.color: (root.streamingQuality === modelData.key)
                                                  ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                                                  : (streamItemMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25) : "transparent")
                                    border.width: 1

                                    Behavior on color { ColorAnimation { duration: 100 } }
                                    Behavior on border.color { ColorAnimation { duration: 100 } }

                                    Item {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10

                                        Column {
                                            anchors.left: parent.left
                                            anchors.right: streamCheckIcon.left
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 1

                                            Text {
                                                width: parent.width
                                                text: modelData.name
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                font.bold: root.streamingQuality === modelData.key
                                                color: (root.streamingQuality === modelData.key) ? "#ffffff" : (streamItemMouse.containsMouse ? "#ffffff" : Qt.rgba(255, 255, 255, 0.85))
                                                elide: Text.ElideRight
                                            }

                                            MarqueeText {
                                                width: parent.width
                                                text: modelData.desc
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                color: (root.streamingQuality === modelData.key) ? Qt.rgba(255, 255, 255, 0.80) : Theme.textSecondary
                                                active: streamQualityRowItem.menuOpen
                                            }
                                        }

                                        AppIcon {
                                            id: streamCheckIcon
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            source: "../assets/icons/emblem-ok-symbolic.svg"
                                            iconSize: 12
                                            color: root.accentColor
                                            visible: root.streamingQuality === modelData.key
                                        }
                                    }

                                    MouseArea {
                                        id: streamItemMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.selectStreamingQualityRequested(modelData.key);
                                            streamQualityRowItem.menuOpen = false;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Lossless (Tidal): account, on/off, quality and DAC mode
                LosslessSettingsSection {
                    Layout.fillWidth: true
                    host: (typeof win !== "undefined") ? win : null
                    accentColor: root.accentColor
                    apiUrl: (typeof win !== "undefined" && win.localApiUrl) ? win.localApiUrl : "http://127.0.0.1:17890"
                }

                // Download Audio Quality Row (100% Borderless, Expandable Clean Dropdown Pinned to Right)
                Item {
                    id: downloadQualityRowItem
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    z: menuOpen ? 100 : 1

                    property bool menuOpen: false

                    Column {
                        anchors.left: parent.left
                        anchors.right: dlDropdownBtn.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: I18n.tr("Chất lượng tải nhạc về máy", "Download Audio Quality")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: I18n.tr("Định dạng và bitrate khi lưu bài hát về bộ nhớ máy", "Format and bitrate used when saving tracks to local storage")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                        }
                    }

                    // Dropdown Trigger (Option 1: Chromatic Ghost Action Button)
                    Rectangle {
                        id: dlDropdownBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 28
                        width: dlBtnRow.implicitWidth + 16
                        radius: 6
                        color: (dlBtnMouse.containsMouse || downloadQualityRowItem.menuOpen)
                               ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                               : "transparent"
                        border.width: 0

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row {
                            id: dlBtnRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: root.getQualityLabel(root.downloadQuality, true)
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                                color: (dlBtnMouse.containsMouse || downloadQualityRowItem.menuOpen) ? "#ffffff" : Qt.rgba(255, 255, 255, 0.85)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            AppIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                source: "../assets/icons/go-down-symbolic.svg"
                                iconSize: 10
                                color: root.accentColor
                                rotation: downloadQualityRowItem.menuOpen ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }
                        }

                        MouseArea {
                            id: dlBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var next = !downloadQualityRowItem.menuOpen;
                                root.closeAllDropdowns();
                                downloadQualityRowItem.menuOpen = next;
                            }
                        }
                    }

                    // Chromatic Salience Dropdown Popover Menu (Zero Dull Grey)
                    Rectangle {
                        id: dlDropdownMenu
                        visible: downloadQualityRowItem.menuOpen
                        anchors.top: dlDropdownBtn.bottom
                        anchors.topMargin: 6
                        anchors.right: dlDropdownBtn.right
                        width: 250
                        height: dlCol.implicitHeight + 10
                        radius: 10
                        color: Qt.rgba(0.06 + root.accentColor.r * 0.08, 0.06 + root.accentColor.g * 0.08, 0.08 + root.accentColor.b * 0.12, 0.96)
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                        border.width: 1
                        z: 100

                        Column {
                            id: dlCol
                            anchors.top: parent.top
                            anchors.topMargin: 5
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 3

                            readonly property var qualityOptions: [
                                {
                                    key: "high_opus",
                                    name: I18n.tr("Cao - Opus (256 kbps)", "High - Opus (256 kbps)"),
                                    desc: I18n.tr("Trích xuất Opus 256k nguyên gốc, chi tiết cao", "Direct Opus 256k extract, highest detail")
                                },
                                {
                                    key: "high_aac",
                                    name: I18n.tr("Cao - AAC (256 kbps)", "High - AAC (256 kbps)"),
                                    desc: I18n.tr("Trích xuất M4A/AAC 256k tương thích mọi nơi", "Direct M4A/AAC 256k, universal compatibility")
                                },
                                {
                                    key: "medium",
                                    name: I18n.tr("Tiêu chuẩn (128 kbps)", "Standard (128 kbps)"),
                                    desc: I18n.tr("Dung lượng vừa phải, định dạng M4A chuẩn", "Moderate file size, standard M4A")
                                },
                                {
                                    key: "low",
                                    name: I18n.tr("Tiết kiệm (64 kbps)", "Data Saver (64 kbps)"),
                                    desc: I18n.tr("Dung lượng siêu nhẹ cho bộ nhớ máy nhỏ", "Ultra light storage for small disk spaces")
                                }
                            ]

                            Repeater {
                                model: dlCol.qualityOptions
                                delegate: Rectangle {
                                    width: dlCol.width - 10
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    height: 42
                                    radius: 7
                                    color: (root.downloadQuality === modelData.key)
                                           ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.26)
                                           : (dlItemMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14) : "transparent")
                                    border.color: (root.downloadQuality === modelData.key)
                                                  ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                                                  : (dlItemMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25) : "transparent")
                                    border.width: 1

                                    Behavior on color { ColorAnimation { duration: 100 } }
                                    Behavior on border.color { ColorAnimation { duration: 100 } }

                                    Item {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10

                                        Column {
                                            anchors.left: parent.left
                                            anchors.right: dlCheckIcon.left
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 1

                                            Text {
                                                width: parent.width
                                                text: modelData.name
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                font.bold: root.downloadQuality === modelData.key
                                                color: (root.downloadQuality === modelData.key) ? "#ffffff" : (dlItemMouse.containsMouse ? "#ffffff" : Qt.rgba(255, 255, 255, 0.85))
                                                elide: Text.ElideRight
                                            }

                                            MarqueeText {
                                                width: parent.width
                                                text: modelData.desc
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                color: (root.downloadQuality === modelData.key) ? Qt.rgba(255, 255, 255, 0.80) : Theme.textSecondary
                                                active: downloadQualityRowItem.menuOpen
                                            }
                                        }

                                        AppIcon {
                                            id: dlCheckIcon
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            source: "../assets/icons/emblem-ok-symbolic.svg"
                                            iconSize: 12
                                            color: root.accentColor
                                            visible: root.downloadQuality === modelData.key
                                        }
                                    }

                                    MouseArea {
                                        id: dlItemMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.selectDownloadQualityRequested(modelData.key);
                                            downloadQualityRowItem.menuOpen = false;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // =============================================================
                // Crossfade & AutoMix (smooth track transitions)
                // =============================================================
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46

                    Column {
                        anchors.left: parent.left
                        anchors.right: toggleCrossfade.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: I18n.tr("Chuyển bài mượt mà", "Crossfade")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: I18n.tr("Bài đang phát nhỏ dần trong lúc bài kế tiếp to dần lên", "The current song fades out while the next one fades in")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        id: toggleCrossfade
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        height: 24
                        radius: 12
                        color: root.crossfadeEnabled ? root.accentColor : Qt.rgba(255, 255, 255, 0.14)
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            width: 18
                            height: 18
                            radius: 9
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.crossfadeEnabled ? parent.width - width - 3 : 3
                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            preventStealing: false
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.crossfadeEnabled = !root.crossfadeEnabled;
                                root.toggleCrossfadeRequested(root.crossfadeEnabled);
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    visible: root.crossfadeEnabled && !root.autoMixEnabled

                    Column {
                        anchors.left: parent.left
                        anchors.right: crossfadeChips.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: I18n.tr("Thời lượng chuyển bài", "Crossfade length")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: I18n.tr("Khoảng thời gian hai bài hòa vào nhau", "How long the two songs overlap")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        id: crossfadeChips
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Repeater {
                            model: [3, 6, 9, 12]
                            delegate: Rectangle {
                                required property int modelData
                                readonly property bool selected: root.crossfadeSeconds === modelData
                                width: 54
                                height: 26
                                radius: 13
                                color: selected ? root.accentColor
                                     : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, chipMouse.containsMouse ? 0.26 : 0.14)
                                Behavior on color { ColorAnimation { duration: 150 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: I18n.tr(modelData + " giây", modelData + " s")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: parent.selected
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    id: chipMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.crossfadeSeconds = modelData;
                                        root.selectCrossfadeSecondsRequested(modelData);
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    visible: root.crossfadeEnabled

                    Column {
                        anchors.left: parent.left
                        anchors.right: toggleAutoMix.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: I18n.tr("Tự động hòa trộn", "AutoMix")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.autoMixLocked
                                  ? I18n.tr("Tắt do chế độ nguyên bản", "Off in bit-perfect mode")
                                  : I18n.tr("Nghe độ lớn của từng bài để chọn lúc chuyển, bỏ qua đoạn im lặng đầu và cuối bài", "Reads each song's loudness to pick the blend point and skip silent intros and endings")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        id: toggleAutoMix
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        height: 24
                        radius: 12
                        color: root.autoMixEnabled ? root.accentColor : Qt.rgba(255, 255, 255, 0.14)
                        opacity: root.autoMixLocked ? 0.4 : 1.0
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            width: 18
                            height: 18
                            radius: 9
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.autoMixEnabled ? parent.width - width - 3 : 3
                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            preventStealing: false
                            enabled: !root.autoMixLocked
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.autoMixEnabled = !root.autoMixEnabled;
                                root.toggleAutoMixRequested(root.autoMixEnabled);
                            }
                        }
                    }
                }

                // =============================================================
                // Disk cache: usage, size limit and cleanup (cache_manager.py)
                // =============================================================
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 62

                    Column {
                        anchors.left: parent.left
                        anchors.right: clearCacheBtn.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Text {
                            width: parent.width
                            text: I18n.tr("Bộ nhớ đệm", "Cache")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            readonly property var u: root.cacheUsage
                            text: !u ? I18n.tr("Đang tính dung lượng...", "Calculating size...")
                                : I18n.tr("Đang dùng " + root.formatBytes(u.total) + " / " + root.formatLimit(root.cacheLimitMb)
                                          + "  ·  Nhạc " + root.formatBytes(u.audio) + ", ảnh " + root.formatBytes(u.images) + ", lời " + root.formatBytes(u.lyrics),
                                          "Using " + root.formatBytes(u.total) + " of " + root.formatLimit(root.cacheLimitMb)
                                          + "  ·  Music " + root.formatBytes(u.audio) + ", images " + root.formatBytes(u.images) + ", lyrics " + root.formatBytes(u.lyrics))
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)

                            Rectangle {
                                readonly property real ratio: root.cacheUsage
                                    ? Math.min(1, root.cacheUsage.total / (root.cacheLimitMb * 1048576)) : 0
                                width: parent.width * ratio
                                height: parent.height
                                radius: 2
                                color: ratio > 0.95 ? Qt.rgba(244 / 255, 63 / 255, 94 / 255, 0.9) : root.accentColor
                                Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                            }
                        }
                    }

                    // Tonal clean-up button: hover state layer, press ripple from the click point,
                    // a spinner while cleaning and a check with the freed size when done
                    Rectangle {
                        id: clearCacheBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 32
                        width: clearCacheRow.implicitWidth + 28
                        radius: 16
                        clip: true
                        readonly property color tint: Qt.rgba(244 / 255, 63 / 255, 94 / 255, 1)
                        color: Qt.rgba(tint.r, tint.g, tint.b, root.cacheJustCleaned ? 0.18 : 0.12)
                        scale: clearCacheMouse.pressed ? 0.96 : 1.0
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 200 } }

                        // State layer
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: clearCacheBtn.tint
                            opacity: root.cacheBusy ? 0 : (clearCacheMouse.pressed ? 0.16 : (clearCacheMouse.containsMouse ? 0.10 : 0))
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }

                        // Ripple
                        Rectangle {
                            id: cacheRipple
                            property real cx: 0
                            property real cy: 0
                            property real r: 0
                            x: cx - r; y: cy - r
                            width: r * 2; height: r * 2
                            radius: r
                            color: clearCacheBtn.tint
                            opacity: 0
                        }
                        ParallelAnimation {
                            id: cacheRippleAnim
                            NumberAnimation { target: cacheRipple; property: "r"; from: 0; to: clearCacheBtn.width; duration: 520; easing.type: Easing.OutCubic }
                            NumberAnimation { target: cacheRipple; property: "opacity"; from: 0.22; to: 0; duration: 520; easing.type: Easing.OutQuad }
                        }

                        Row {
                            id: clearCacheRow
                            anchors.centerIn: parent
                            spacing: 7

                            Item {
                                width: 15
                                height: 15
                                anchors.verticalCenter: parent.verticalCenter

                                Image {
                                    id: cacheIconIdle
                                    anchors.centerIn: parent
                                    source: root.cacheJustCleaned ? "../assets/icons/emblem-ok-symbolic.svg" : "../assets/icons/user-trash-symbolic.svg"
                                    sourceSize: Qt.size(15, 15)
                                    width: 15
                                    height: 15
                                    opacity: root.cacheBusy ? 0 : 1
                                    scale: root.cacheBusy ? 0.6 : 1
                                    Behavior on opacity { NumberAnimation { duration: 180 } }
                                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                                    layer.enabled: true
                                    layer.effect: MultiEffect { colorization: 1.0; colorizationColor: "#fda4af" }
                                }

                                CircularSpinner {
                                    anchors.centerIn: parent
                                    size: 14
                                    strokeWidth: 2
                                    color: "#fda4af"
                                    running: root.cacheBusy
                                    opacity: root.cacheBusy ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 180 } }
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.cacheBusy ? I18n.tr("Đang dọn", "Cleaning")
                                    : (root.cacheJustCleaned ? I18n.tr("Đã giải phóng " + root.formatBytes(root.cacheFreedBytes), "Freed " + root.formatBytes(root.cacheFreedBytes))
                                                             : I18n.tr("Dọn dẹp", "Clean up"))
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: "#fda4af"
                            }
                        }

                        MouseArea {
                            id: clearCacheMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.cacheBusy
                            cursorShape: Qt.PointingHandCursor
                            onPressed: mouse => {
                                cacheRipple.cx = mouse.x;
                                cacheRipple.cy = mouse.y;
                                cacheRippleAnim.restart();
                            }
                            onClicked: {
                                root.cacheJustCleaned = false;
                                root.cacheBeforeClear = root.cacheUsage ? root.cacheUsage.total : 0;
                                root.clearCacheRequested();
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46

                    Column {
                        anchors.left: parent.left
                        anchors.right: cacheLimitChips.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: I18n.tr("Dung lượng tối đa", "Maximum size")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: I18n.tr("Khi đầy, bài lâu chưa nghe lại sẽ được xóa trước", "When full, songs you haven't replayed in a while are removed first")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                            elide: Text.ElideRight
                        }
                    }

                    // Segmented selector: one track, a highlight that slides to the chosen size
                    Rectangle {
                        id: cacheLimitChips
                        readonly property var choices: [1024, 1536, 2048]
                        readonly property real segW: 64
                        readonly property int selIndex: Math.max(0, choices.indexOf(root.cacheLimitMb))
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: segW * choices.length + 6
                        height: 32
                        radius: 16
                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)

                        Rectangle {
                            x: 3 + cacheLimitChips.selIndex * cacheLimitChips.segW
                            y: 3
                            width: cacheLimitChips.segW
                            height: parent.height - 6
                            radius: height / 2
                            color: root.accentColor
                            Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
                        }

                        Row {
                            x: 3
                            y: 3
                            Repeater {
                                model: cacheLimitChips.choices
                                delegate: Item {
                                    required property int modelData
                                    required property int index
                                    readonly property bool selected: index === cacheLimitChips.selIndex
                                    width: cacheLimitChips.segW
                                    height: cacheLimitChips.height - 6

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: height / 2
                                        color: root.accentColor
                                        opacity: !parent.selected && segMouse.containsMouse ? 0.16 : 0
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.formatLimit(parent.modelData)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.weight: parent.selected ? Font.DemiBold : Font.Normal
                                        color: "#ffffff"
                                        opacity: parent.selected ? 1.0 : 0.72
                                        Behavior on opacity { NumberAnimation { duration: 200 } }
                                    }

                                    MouseArea {
                                        id: segMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.cacheLimitMb === parent.modelData) return;
                                            root.cacheLimitMb = parent.modelData;
                                            root.selectCacheLimitRequested(parent.modelData);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

            } // Close tab2Content

                    // =========================================================
                    // TAB 3: Appearance (language, effects, window, version)
                    // =========================================================
                    ColumnLayout {
                        id: tab3Content
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 14
                        visible: root.currentTab === 3

                // Language Selection Row (100% Borderless, Expandable Clean Dropdown Pinned to Right)
                Item {
                    id: langRowItem
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    z: menuOpen ? 100 : 3

                    property bool menuOpen: false

                    Column {
                        anchors.left: parent.left
                        anchors.right: langDropdownBtn.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: I18n.tr("Ngôn ngữ giao diện", "Interface Language")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: I18n.tr("Toàn bộ ứng dụng hiển thị theo ngôn ngữ đã chọn", "All application UI displays in selected language")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                        }
                    }

                    // Dropdown Trigger (Option 1: Chromatic Ghost Action Button)
                    Rectangle {
                        id: langDropdownBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 28
                        width: langBtnRow.implicitWidth + 16
                        radius: 6
                        color: (langBtnMouse.containsMouse || langRowItem.menuOpen)
                               ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                               : "transparent"
                        border.width: 0

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row {
                            id: langBtnRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: I18n.locale === "vi" ? "Tiếng Việt" : "English"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                                color: (langBtnMouse.containsMouse || langRowItem.menuOpen) ? "#ffffff" : Qt.rgba(255, 255, 255, 0.85)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            AppIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                source: "../assets/icons/go-down-symbolic.svg"
                                iconSize: 10
                                color: root.accentColor
                                rotation: langRowItem.menuOpen ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }
                        }

                        MouseArea {
                            id: langBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var next = !langRowItem.menuOpen;
                                root.closeAllDropdowns();
                                langRowItem.menuOpen = next;
                            }
                        }
                    }

                    // Chromatic Salience Dropdown Popover Menu (Zero Dull Grey)
                    Rectangle {
                        id: langDropdownMenu
                        visible: langRowItem.menuOpen
                        anchors.top: langDropdownBtn.bottom
                        anchors.topMargin: 6
                        anchors.right: langDropdownBtn.right
                        width: 146
                        height: langCol.implicitHeight + 10
                        radius: 10
                        color: Qt.rgba(0.06 + root.accentColor.r * 0.08, 0.06 + root.accentColor.g * 0.08, 0.08 + root.accentColor.b * 0.12, 0.96)
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                        border.width: 1
                        z: 100

                        Column {
                            id: langCol
                            anchors.top: parent.top
                            anchors.topMargin: 5
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 3

                            readonly property var languages: [
                                { code: "vi", name: "Tiếng Việt" },
                                { code: "en", name: "English" }
                            ]

                            Repeater {
                                model: langCol.languages
                                delegate: Rectangle {
                                    width: langCol.width - 10
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    height: 32
                                    radius: 7
                                    color: (I18n.locale === modelData.code)
                                           ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.26)
                                           : (langItemMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14) : "transparent")
                                    border.color: (I18n.locale === modelData.code)
                                                  ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                                                  : (langItemMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25) : "transparent")
                                    border.width: 1

                                    Behavior on color { ColorAnimation { duration: 100 } }
                                    Behavior on border.color { ColorAnimation { duration: 100 } }

                                    Item {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10

                                        Text {
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.name
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            font.bold: I18n.locale === modelData.code
                                            color: (I18n.locale === modelData.code) ? "#ffffff" : (langItemMouse.containsMouse ? "#ffffff" : Qt.rgba(255, 255, 255, 0.75))
                                        }

                                        AppIcon {
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            source: "../assets/icons/emblem-ok-symbolic.svg"
                                            iconSize: 12
                                            color: root.accentColor
                                            visible: I18n.locale === modelData.code
                                        }
                                    }

                                    MouseArea {
                                        id: langItemMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.selectLanguageRequested(modelData.code);
                                            langRowItem.menuOpen = false;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // =============================================================
                // Lite mode (Auto / On / Off): drops the effects that repaint the whole window
                // =============================================================
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46

                    Column {
                        anchors.left: parent.left
                        anchors.right: liteModeChips.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: I18n.tr("Chế độ nhẹ", "Lite mode")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.liteMode === "auto"
                                  ? (root.liteModeAutoActive
                                     ? I18n.tr("Đang bật vì máy không có card đồ họa", "On because this computer has no graphics card")
                                     : I18n.tr("Tự bật khi máy không có card đồ họa", "Turns on by itself when there is no graphics card"))
                                  : I18n.tr("Tắt nền chuyển động và hiệu ứng nặng để đỡ giật, mát máy", "Turns off the moving background and heavy effects so the app runs smoother and cooler")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                            elide: Text.ElideRight
                        }
                    }

                    // Segmented selector, same look as the cache size picker
                    Rectangle {
                        id: liteModeChips
                        readonly property var choices: ["auto", "on", "off"]
                        readonly property real segW: 64
                        readonly property int selIndex: Math.max(0, choices.indexOf(root.liteMode))
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: segW * choices.length + 6
                        height: 32
                        radius: 16
                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)

                        Rectangle {
                            x: 3 + liteModeChips.selIndex * liteModeChips.segW
                            y: 3
                            width: liteModeChips.segW
                            height: parent.height - 6
                            radius: height / 2
                            color: root.accentColor
                            Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
                        }

                        Row {
                            x: 3
                            y: 3
                            Repeater {
                                model: liteModeChips.choices
                                delegate: Item {
                                    required property string modelData
                                    required property int index
                                    readonly property bool selected: index === liteModeChips.selIndex
                                    width: liteModeChips.segW
                                    height: liteModeChips.height - 6

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: height / 2
                                        color: root.accentColor
                                        opacity: !parent.selected && liteSegMouse.containsMouse ? 0.16 : 0
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.modelData === "auto" ? I18n.tr("Tự động", "Auto")
                                              : parent.modelData === "on" ? I18n.tr("Bật", "On")
                                              : I18n.tr("Tắt", "Off")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.weight: parent.selected ? Font.DemiBold : Font.Normal
                                        color: "#ffffff"
                                        opacity: parent.selected ? 1.0 : 0.72
                                        Behavior on opacity { NumberAnimation { duration: 200 } }
                                    }

                                    MouseArea {
                                        id: liteSegMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.liteMode === parent.modelData) return;
                                            root.liteMode = parent.modelData;
                                            root.selectLiteModeRequested(parent.modelData);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // =============================================================
                // When the window closes: mini player on the desktop, or music only
                // =============================================================
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46

                    Column {
                        anchors.left: parent.left
                        anchors.right: closeBehaviorChips.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: I18n.tr("Khi đóng cửa sổ", "When you close the window")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.closeBehavior === "background"
                                  ? I18n.tr("Không hiện gì, nhạc vẫn phát. Bấm icon Nutsty để mở lại", "Nothing stays on screen and the music keeps playing. Click the Nutsty icon to open it again")
                                  : I18n.tr("Hiện trình phát nhỏ trên màn hình nền, nhạc vẫn phát", "A small player stays on the desktop and the music keeps playing")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                            elide: Text.ElideRight
                        }
                    }

                    // Segmented selector, same look as the Lite mode picker above
                    Rectangle {
                        id: closeBehaviorChips
                        readonly property var choices: ["widget", "background"]
                        readonly property real segW: 108
                        readonly property int selIndex: Math.max(0, choices.indexOf(root.closeBehavior))
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: segW * choices.length + 6
                        height: 32
                        radius: 16
                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)

                        Rectangle {
                            x: 3 + closeBehaviorChips.selIndex * closeBehaviorChips.segW
                            y: 3
                            width: closeBehaviorChips.segW
                            height: parent.height - 6
                            radius: height / 2
                            color: root.accentColor
                            Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
                        }

                        Row {
                            x: 3
                            y: 3
                            Repeater {
                                model: closeBehaviorChips.choices
                                delegate: Item {
                                    required property string modelData
                                    required property int index
                                    readonly property bool selected: index === closeBehaviorChips.selIndex
                                    width: closeBehaviorChips.segW
                                    height: closeBehaviorChips.height - 6

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: height / 2
                                        color: root.accentColor
                                        opacity: !parent.selected && closeSegMouse.containsMouse ? 0.16 : 0
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.modelData === "widget" ? I18n.tr("Trình phát nhỏ", "Mini player")
                                              : I18n.tr("Chỉ phát nhạc", "Music only")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.weight: parent.selected ? Font.DemiBold : Font.Normal
                                        color: "#ffffff"
                                        opacity: parent.selected ? 1.0 : 0.72
                                        Behavior on opacity { NumberAnimation { duration: 200 } }
                                    }

                                    MouseArea {
                                        id: closeSegMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.closeBehavior === parent.modelData) return;
                                            root.closeBehavior = parent.modelData;
                                            root.selectCloseBehaviorRequested(parent.modelData);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // =============================================================
                // Scroll edge fade (lists fade out at the edges they can scroll past)
                // =============================================================
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46

                    Column {
                        anchors.left: parent.left
                        anchors.right: toggleScrollEdgeFade.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: I18n.tr("Mờ dần ở mép khi cuộn", "Fade edges while scrolling")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: I18n.tr("Tắt đi nếu máy yếu bị giật khi cuộn", "Turn off if scrolling stutters on a slower computer")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        id: toggleScrollEdgeFade
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        height: 24
                        radius: 12
                        color: root.scrollEdgeFadeEnabled ? root.accentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            width: 18
                            height: 18
                            radius: 9
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.scrollEdgeFadeEnabled ? parent.width - width - 3 : 3
                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            preventStealing: false
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.scrollEdgeFadeEnabled = !root.scrollEdgeFadeEnabled;
                                root.toggleScrollEdgeFadeRequested(root.scrollEdgeFadeEnabled);
                            }
                        }
                    }
                }

                // =============================================================
                // Up Next lean: the Playing Next list stands straight unless this is on
                // =============================================================
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46

                    Column {
                        anchors.left: parent.left
                        anchors.right: toggleUpNextTilt.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: I18n.tr("Nghiêng danh sách Phát tiếp theo", "Lean the Playing Next list")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: I18n.tr("Các bài sắp phát xếp nghiêng lơ lửng thay vì đứng thẳng", "Upcoming songs float at a slant instead of standing straight")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        id: toggleUpNextTilt
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        height: 24
                        radius: 12
                        color: root.upNextTilt ? root.accentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            width: 18
                            height: 18
                            radius: 9
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.upNextTilt ? parent.width - width - 3 : 3
                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            preventStealing: false
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.upNextTilt = !root.upNextTilt;
                                root.toggleUpNextTiltRequested(root.upNextTilt);
                            }
                        }
                    }
                }

                // =============================================================
                // Animated Cover & Spotify Canvas Priority Dropdown (Frameless Row)
                // =============================================================
                Item {
                    id: canvasPrefRowItem
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    z: menuOpen ? 95 : 2

                    property bool menuOpen: false

                    Column {
                        anchors.left: parent.left
                        anchors.right: canvasPrefDropdownBtn.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: I18n.tr("Bìa động & Spotify Canvas", "Animated Cover & Spotify Canvas")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: I18n.tr("Ưu tiên phát video loop nghệ thuật Apple Music hoặc Spotify Canvas", "Priority for Apple Music artistic video loop or Spotify Canvas")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                            elide: Text.ElideRight
                        }
                    }

                    // Right-aligned Trigger Button (Khớp 100% kích thước và vị trí với các dropdown khác)
                    Rectangle {
                        id: canvasPrefDropdownBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 28
                        width: canvasPrefBtnRow.implicitWidth + 16
                        radius: 6
                        color: (canvasPrefBtnMouse.containsMouse || canvasPrefRowItem.menuOpen)
                               ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                               : "transparent"
                        border.width: 0

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row {
                            id: canvasPrefBtnRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: root.getCanvasPrefLabel(root.canvasPreference)
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                                color: (canvasPrefBtnMouse.containsMouse || canvasPrefRowItem.menuOpen) ? "#ffffff" : Qt.rgba(255, 255, 255, 0.85)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            AppIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                source: "../assets/icons/go-down-symbolic.svg"
                                iconSize: 10
                                color: root.accentColor
                                rotation: canvasPrefRowItem.menuOpen ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }
                        }

                        MouseArea {
                            id: canvasPrefBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var next = !canvasPrefRowItem.menuOpen;
                                root.closeAllDropdowns();
                                canvasPrefRowItem.menuOpen = next;
                            }
                        }
                    }

                    // Chromatic Salience Dropdown Popover Menu (Zero Dull Grey)
                    Rectangle {
                        id: canvasPrefDropdownMenu
                        visible: canvasPrefRowItem.menuOpen
                        anchors.top: canvasPrefDropdownBtn.bottom
                        anchors.topMargin: 6
                        anchors.right: canvasPrefDropdownBtn.right
                        width: 320
                        height: canvasPrefCol.implicitHeight + 10
                        radius: 10
                        color: Qt.rgba(0.06 + root.accentColor.r * 0.08, 0.06 + root.accentColor.g * 0.08, 0.08 + root.accentColor.b * 0.12, 0.96)
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                        border.width: 1
                        z: 100

                        Column {
                            id: canvasPrefCol
                            anchors.top: parent.top
                            anchors.topMargin: 5
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 3

                            readonly property var canvasOptions: [
                                {
                                    key: "apple_first",
                                    name: "Apple Music > Spotify Canvas",
                                    desc: I18n.tr("Ưu tiên Apple Music, nếu không có sẽ dùng Spotify Canvas (Khuyến nghị)", "Prefer Apple Music, fallback to Spotify Canvas (Recommended)")
                                },
                                {
                                    key: "spotify_first",
                                    name: "Spotify Canvas > Apple Music",
                                    desc: I18n.tr("Ưu tiên Spotify Canvas, nếu không có sẽ dùng Apple Music", "Prefer Spotify Canvas, fallback to Apple Music")
                                },
                                {
                                    key: "apple_only",
                                    name: I18n.tr("Chỉ Apple Music", "Apple Music only"),
                                    desc: I18n.tr("Chỉ dùng bìa động Apple Music, không dùng Spotify Canvas", "Only use Apple Music animated artwork, never Canvas")
                                },
                                {
                                    key: "spotify_only",
                                    name: I18n.tr("Chỉ Spotify Canvas", "Spotify Canvas only"),
                                    desc: I18n.tr("Chỉ dùng video Spotify Canvas (yêu cầu kết nối Spotify)", "Only use Spotify Canvas video (requires Spotify login)")
                                },
                                {
                                    key: "off",
                                    name: I18n.tr("Tắt (Chỉ dùng ảnh tĩnh)", "Off (Static artwork only)"),
                                    desc: I18n.tr("Không tải video bìa động để tiết kiệm mạng và CPU", "Do not load video covers to save bandwidth and CPU")
                                }
                            ]

                            Repeater {
                                model: canvasPrefCol.canvasOptions
                                delegate: Rectangle {
                                    width: canvasPrefCol.width - 10
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    height: 42
                                    radius: 7
                                    color: (root.canvasPreference === modelData.key)
                                           ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.26)
                                           : (cpItemMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14) : "transparent")
                                    border.color: (root.canvasPreference === modelData.key)
                                                  ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                                                  : (cpItemMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25) : "transparent")
                                    border.width: 1

                                    Behavior on color { ColorAnimation { duration: 100 } }
                                    Behavior on border.color { ColorAnimation { duration: 100 } }

                                    Item {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10

                                        Column {
                                            anchors.left: parent.left
                                            anchors.right: cpCheckIcon.left
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 1

                                            Text {
                                                width: parent.width
                                                text: modelData.name
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                font.bold: root.canvasPreference === modelData.key
                                                color: (root.canvasPreference === modelData.key) ? "#ffffff" : (cpItemMouse.containsMouse ? "#ffffff" : Qt.rgba(255, 255, 255, 0.85))
                                                elide: Text.ElideRight
                                            }

                                            MarqueeText {
                                                width: parent.width
                                                text: modelData.desc
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                color: (root.canvasPreference === modelData.key) ? Qt.rgba(255, 255, 255, 0.80) : Theme.textSecondary
                                                active: canvasPrefRowItem.menuOpen
                                            }
                                        }

                                        AppIcon {
                                            id: cpCheckIcon
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            source: "../assets/icons/emblem-ok-symbolic.svg"
                                            iconSize: 12
                                            color: root.accentColor
                                            visible: root.canvasPreference === modelData.key
                                        }
                                    }

                                    MouseArea {
                                        id: cpItemMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.canvasPreference = modelData.key;
                                            root.animatedCoverEnabled = (modelData.key !== "off");
                                            root.saveCanvasPreferenceRequested(modelData.key);
                                            canvasPrefRowItem.menuOpen = false;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // =============================================================
                // Application & Updates Card (Concentric Dark Glass / Frameless)
                // =============================================================
                Item {
                    id: appUpdateRowItem
                    Layout.fillWidth: true
                    Layout.preferredHeight: appUpdateText.implicitHeight + 10 + 28
                    Layout.topMargin: 4
                    Layout.bottomMargin: 16

                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 160 } }

                    // Text on top, the four buttons on their own line below: they never squeeze the text
                    Column {
                        id: appUpdateText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 4

                        Row {
                            spacing: 8

                            Text {
                                text: I18n.tr("Phiên bản ứng dụng", "Application Version")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                color: Theme.textPrimary
                            }

                            // Version Tag Badge
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                height: 18
                                width: verTagTxt.implicitWidth + 10
                                radius: 4
                                color: root.hasAppUpdate
                                       ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                                       : Qt.rgba(255, 255, 255, 0.08)
                                border.width: 1
                                border.color: root.hasAppUpdate
                                              ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.40)
                                              : Qt.rgba(255, 255, 255, 0.12)

                                Text {
                                    id: verTagTxt
                                    anchors.centerIn: parent
                                    text: "v" + (root.appVersion || "1.0.0")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: root.hasAppUpdate ? root.accentColor : Theme.textSecondary
                                }
                            }
                        }

                        Text {
                            text: root.isDownloadingUpdate
                                  ? (root.updateStatusMessage || I18n.tr("Đang tải bản cập nhật...", "Downloading update..."))
                                  : (root.updateProgress >= 1.0
                                     ? I18n.tr("Đã tải xong! Bấm Khởi động lại để áp dụng.", "Download complete! Click Restart to apply.")
                                     : (root.hasAppUpdate
                                        ? I18n.tr("Đã có bản cập nhật mới (" + root.latestVersion + "). Bấm để cập nhật trực tiếp.",
                                                  "New update available (" + root.latestVersion + "). Click to update directly.")
                                        : I18n.tr("Bạn đang sử dụng phiên bản mới nhất.", "You are using the latest version.")))
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: root.hasAppUpdate ? root.accentColor : Theme.textSecondary
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        // Direct Update Progress Bar (Concentric radius, accent salience)
                        Rectangle {
                            visible: root.isDownloadingUpdate || root.updateProgress > 0.0
                            width: Math.min(parent.width, 320)
                            height: 4
                            radius: 2
                            color: Qt.rgba(255, 255, 255, 0.12)

                            Rectangle {
                                height: parent.height
                                width: parent.width * Math.max(0.04, Math.min(1.0, root.updateProgress))
                                radius: 2
                                color: root.accentColor
                                Behavior on width { NumberAnimation { duration: 180 } }
                            }
                        }
                    }

                    // Action Buttons (Update Now / Check for Updates / View GitHub)
                    Row {
                        id: updateActionsRow
                        anchors.left: parent.left
                        anchors.top: appUpdateText.bottom
                        anchors.topMargin: 10
                        spacing: 8

                        // 1. Direct Update / Restart Button
                        Rectangle {
                            id: downloadUpdateBtn
                            visible: root.hasAppUpdate
                            height: 28
                            width: updDlBtnRow.implicitWidth + 16
                            radius: 6
                            color: updDlBtnMouse.containsMouse
                                   ? Qt.tint(root.accentColor, Qt.rgba(1, 1, 1, 0.15))
                                   : root.accentColor
                            border.width: 0
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Row {
                                id: updDlBtnRow
                                anchors.centerIn: parent
                                spacing: 6

                                AppIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: root.updateProgress >= 1.0
                                            ? "../assets/icons/emblem-ok-symbolic.svg"
                                            : (root.isDownloadingUpdate
                                               ? "../assets/icons/process-working-symbolic.svg"
                                               : "../assets/icons/download-symbolic.svg")
                                    iconSize: 12
                                    color: "#000000"
                                }

                                Text {
                                    text: root.updateProgress >= 1.0
                                          ? I18n.tr("Khởi động lại ngay", "Restart Now")
                                          : (root.isDownloadingUpdate
                                             ? I18n.tr("Đang cập nhật...", "Updating...")
                                             : I18n.tr("Cập nhật ngay", "Update Now"))
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: "#000000"
                                }
                            }

                            MouseArea {
                                id: updDlBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: root.isDownloadingUpdate ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: {
                                    if (root.updateProgress >= 1.0) {
                                        root.applyUpdateRequested();
                                    } else if (!root.isDownloadingUpdate) {
                                        root.startDirectUpdateRequested();
                                    }
                                }
                            }
                        }

                        // 2. Optional GitHub release link button
                        Rectangle {
                            id: githubReleaseBtn
                            visible: root.hasAppUpdate
                            height: 28
                            width: 28
                            radius: 6
                            color: ghBtnMouse.containsMouse
                                   ? Qt.rgba(255, 255, 255, 0.14)
                                   : Qt.rgba(255, 255, 255, 0.06)
                            border.width: 1
                            border.color: Qt.rgba(255, 255, 255, 0.12)
                            Behavior on color { ColorAnimation { duration: 120 } }

                            AppIcon {
                                anchors.centerIn: parent
                                source: "../assets/icons/arrow-outward-symbolic.svg"
                                iconSize: 12
                                color: Theme.textPrimary
                            }

                            MouseArea {
                                id: ghBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openUpdateUrlRequested()
                            }
                        }

                        // 3. View What's New Button
                        Rectangle {
                            id: whatsNewBtn
                            height: 28
                            width: whatsNewRow.implicitWidth + 16
                            radius: 6
                            color: whatsNewMouse.containsMouse
                                   ? Qt.rgba(255, 255, 255, 0.14)
                                   : Qt.rgba(255, 255, 255, 0.06)
                            border.width: 1
                            border.color: Qt.rgba(255, 255, 255, 0.12)
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Row {
                                id: whatsNewRow
                                anchors.centerIn: parent
                                spacing: 6

                                AppIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: "../assets/icons/emblem-favorite-symbolic.svg"
                                    iconSize: 12
                                    color: root.accentColor
                                }

                                Text {
                                    text: I18n.tr("Điểm mới", "What's New")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: whatsNewMouse.containsMouse ? "#ffffff" : Qt.rgba(255, 255, 255, 0.85)
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }
                            }

                            MouseArea {
                                id: whatsNewMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openWhatsNewRequested()
                            }
                        }

                        // 4. Check for Updates Button
                        Rectangle {
                            id: checkUpdateBtn
                            height: 28
                            width: checkBtnRow.implicitWidth + 16
                            radius: 6
                            color: checkBtnMouse.containsMouse
                                   ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                                   : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
                            border.width: 1
                            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Row {
                                id: checkBtnRow
                                anchors.centerIn: parent
                                spacing: 6

                                AppIcon {
                                    id: checkUpdateIcon
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: root.isCheckingUpdate
                                            ? "../assets/icons/process-working-symbolic.svg"
                                            : "../assets/icons/view-refresh-symbolic.svg"
                                    iconSize: 12
                                    color: root.accentColor

                                    NumberAnimation on rotation {
                                        duration: 900
                                        loops: Animation.Infinite
                                        running: root.isCheckingUpdate
                                        from: 0
                                        to: 360
                                    }
                                }

                                Text {
                                    text: root.isCheckingUpdate
                                          ? I18n.tr("Đang kiểm tra...", "Checking...")
                                          : I18n.tr("Kiểm tra cập nhật", "Check for updates")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: (checkBtnMouse.containsMouse || root.isCheckingUpdate) ? "#ffffff" : Qt.rgba(255, 255, 255, 0.85)
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }
                            }

                            MouseArea {
                                id: checkBtnMouse
                                anchors.fill: parent
                                hoverEnabled: !root.isCheckingUpdate
                                cursorShape: root.isCheckingUpdate ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: {
                                    if (!root.isCheckingUpdate) {
                                        root.checkUpdateRequested();
                                    }
                                }
                            }
                        }
                    }
                }

            } // Close tab3Content

            // =================================================================
            // TAB 1: Desktop Lyrics Settings Content (100% Frameless)
            // =================================================================
            ColumnLayout {
                id: tab1Content
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 12
                visible: root.currentTab === 1

                // Master Switch: Desktop Lyrics (Frameless Row, Toggle Pinned to Right)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46

                    Column {
                        anchors.left: parent.left
                        anchors.right: toggleDesktopLyrics.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: I18n.tr("Hiển thị lời bài hát trên Desktop", "Desktop Lyrics Display")
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: I18n.tr("Hiển thị lời bài hát nổi trực tiếp trên màn hình", "Display floating lyrics directly on desktop wallpaper")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                        }
                    }

                    // Toggle Switch Pill (Pinned to Right)
                    Rectangle {
                        id: toggleDesktopLyrics
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        height: 24
                        radius: 12
                        opacity: 1.0
                        color: root.desktopLyricsEnabled ? root.accentColor : Qt.rgba(255, 255, 255, 0.14)
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            width: 18
                            height: 18
                            radius: 9
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.desktopLyricsEnabled ? parent.width - width - 3 : 3
                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            preventStealing: false
                            enabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.toggleDesktopLyricsRequested(!root.desktopLyricsEnabled);
                            }
                        }
                    }
                }

                // Windows Taskbar Lyrics Switch (Spicy Taskbar)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    visible: Qt.platform.os === "windows"

                    Column {
                        anchors.left: parent.left
                        anchors.right: toggleTaskbarLyrics.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: I18n.tr("Hiển thị lời bài hát trên Taskbar", "Taskbar Lyrics Display")
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: I18n.tr("Hiển thị lời bài hát karaoke quét âm tiết trên thanh tác vụ Windows (Spicy Taskbar)", "Display syllable karaoke lyrics directly on the Windows taskbar (Spicy Taskbar style)")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                        }
                    }

                    // Toggle Switch Pill (Pinned to Right)
                    Rectangle {
                        id: toggleTaskbarLyrics
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        height: 24
                        radius: 12
                        opacity: 1.0
                        color: root.taskbarLyricsEnabled ? root.accentColor : Qt.rgba(255, 255, 255, 0.14)
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            width: 18
                            height: 18
                            radius: 9
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.taskbarLyricsEnabled ? parent.width - width - 3 : 3
                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            preventStealing: false
                            enabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.toggleTaskbarLyricsRequested(!root.taskbarLyricsEnabled);
                            }
                        }
                    }
                }

                // Windows Taskbar Placement Row
                Item {
                    id: placementRowItem
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    visible: Qt.platform.os === "windows" && root.taskbarLyricsEnabled
                    z: menuOpen ? 95 : 1
                    property bool menuOpen: false

                    Column {
                        anchors.left: parent.left
                        anchors.right: placementDropdownBtn.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: I18n.tr("Vị trí hiển thị trên màn hình", "Screen Placement")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: I18n.tr("Nằm lọt lòng thanh Taskbar hoặc nổi phía trên Taskbar", "Position inside Taskbar band or floating above it")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                        }
                    }

                    // Dropdown Trigger Button
                    Rectangle {
                        id: placementDropdownBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 28
                        width: placementBtnRow.implicitWidth + 16
                        radius: 6
                        color: (placementBtnMouse.containsMouse || placementRowItem.menuOpen)
                               ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                               : "transparent"
                        border.width: 0

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row {
                            id: placementBtnRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: root.getTaskbarPlacementLabel(root.taskbarLyricsPlacement)
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                                color: (placementBtnMouse.containsMouse || placementRowItem.menuOpen) ? "#ffffff" : Qt.rgba(255, 255, 255, 0.85)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            AppIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                source: "../assets/icons/go-down-symbolic.svg"
                                iconSize: 10
                                color: root.accentColor
                                rotation: placementRowItem.menuOpen ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }
                        }

                        MouseArea {
                            id: placementBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var next = !placementRowItem.menuOpen;
                                root.closeAllDropdowns();
                                placementRowItem.menuOpen = next;
                            }
                        }
                    }

                    // Popover Menu
                    Rectangle {
                        id: placementDropdownMenu
                        visible: placementRowItem.menuOpen
                        anchors.top: placementDropdownBtn.bottom
                        anchors.topMargin: 6
                        anchors.right: placementDropdownBtn.right
                        width: 240
                        height: placementCol.implicitHeight + 10
                        radius: 10
                        color: Qt.rgba(0.06 + root.accentColor.r * 0.08, 0.06 + root.accentColor.g * 0.08, 0.08 + root.accentColor.b * 0.12, 0.96)
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                        border.width: 1
                        z: 100

                        Column {
                            id: placementCol
                            anchors.top: parent.top
                            anchors.topMargin: 5
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 3

                            readonly property var placementOptions: [
                                {
                                    key: "taskbar",
                                    name: I18n.tr("Trên thanh Taskbar", "On Taskbar"),
                                    desc: I18n.tr("Nằm lọt lòng trong thanh Taskbar Windows", "Position inside the Windows taskbar")
                                },
                                {
                                    key: "above",
                                    name: I18n.tr("Nổi phía trên Taskbar", "Above Taskbar"),
                                    desc: I18n.tr("Nổi lơ lửng phía trên thanh Taskbar 8px", "Float 8px above the taskbar")
                                }
                            ]

                            Repeater {
                                model: placementCol.placementOptions
                                delegate: Rectangle {
                                    width: placementCol.width - 10
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    height: 38
                                    radius: 7
                                    color: (root.taskbarLyricsPlacement === modelData.key)
                                           ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.26)
                                           : (plItemMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14) : "transparent")
                                    border.color: (root.taskbarLyricsPlacement === modelData.key)
                                                  ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                                                  : (plItemMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25) : "transparent")
                                    border.width: 1

                                    Behavior on color { ColorAnimation { duration: 100 } }
                                    Behavior on border.color { ColorAnimation { duration: 100 } }

                                    Item {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10

                                        Column {
                                            anchors.left: parent.left
                                            anchors.right: plCheckIcon.left
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 1

                                            Text {
                                                text: modelData.name
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                font.bold: root.taskbarLyricsPlacement === modelData.key
                                                color: (root.taskbarLyricsPlacement === modelData.key) ? "#ffffff" : (plItemMouse.containsMouse ? "#ffffff" : Qt.rgba(255, 255, 255, 0.85))
                                            }

                                            Text {
                                                text: modelData.desc
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                color: (root.taskbarLyricsPlacement === modelData.key) ? Qt.rgba(255, 255, 255, 0.80) : Theme.textSecondary
                                            }
                                        }

                                        AppIcon {
                                            id: plCheckIcon
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            source: "../assets/icons/emblem-ok-symbolic.svg"
                                            iconSize: 12
                                            color: root.accentColor
                                            visible: root.taskbarLyricsPlacement === modelData.key
                                        }
                                    }

                                    MouseArea {
                                        id: plItemMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.changeTaskbarLyricsPlacementRequested(modelData.key);
                                            placementRowItem.menuOpen = false;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Windows Taskbar Alignment Row
                Item {
                    id: alignRowItem
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    visible: Qt.platform.os === "windows" && root.taskbarLyricsEnabled
                    z: menuOpen ? 90 : 1
                    property bool menuOpen: false

                    Column {
                        anchors.left: parent.left
                        anchors.right: alignDropdownBtn.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: I18n.tr("Căn lề lời bài hát", "Lyrics Alignment")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: I18n.tr("Căn giữa màn hình hoặc lệch trái / phải theo ý muốn", "Center horizontally or align to left / right side")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                        }
                    }

                    // Dropdown Trigger Button
                    Rectangle {
                        id: alignDropdownBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 28
                        width: alignBtnRow.implicitWidth + 16
                        radius: 6
                        color: (alignBtnMouse.containsMouse || alignRowItem.menuOpen)
                               ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                               : "transparent"
                        border.width: 0

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row {
                            id: alignBtnRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: root.getTaskbarAlignLabel(root.taskbarLyricsAlign)
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                                color: (alignBtnMouse.containsMouse || alignRowItem.menuOpen) ? "#ffffff" : Qt.rgba(255, 255, 255, 0.85)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            AppIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                source: "../assets/icons/go-down-symbolic.svg"
                                iconSize: 10
                                color: root.accentColor
                                rotation: alignRowItem.menuOpen ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }
                        }

                        MouseArea {
                            id: alignBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var next = !alignRowItem.menuOpen;
                                root.closeAllDropdowns();
                                alignRowItem.menuOpen = next;
                            }
                        }
                    }

                    // Popover Menu
                    Rectangle {
                        id: alignDropdownMenu
                        visible: alignRowItem.menuOpen
                        anchors.top: alignDropdownBtn.bottom
                        anchors.topMargin: 6
                        anchors.right: alignDropdownBtn.right
                        width: 220
                        height: alignCol.implicitHeight + 10
                        radius: 10
                        color: Qt.rgba(0.06 + root.accentColor.r * 0.08, 0.06 + root.accentColor.g * 0.08, 0.08 + root.accentColor.b * 0.12, 0.96)
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                        border.width: 1
                        z: 100

                        Column {
                            id: alignCol
                            anchors.top: parent.top
                            anchors.topMargin: 5
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 3

                            readonly property var alignOptions: [
                                {
                                    key: "center",
                                    name: I18n.tr("Căn giữa", "Center"),
                                    desc: I18n.tr("Căn giữa màn hình", "Center on screen")
                                },
                                {
                                    key: "left",
                                    name: I18n.tr("Bên trái", "Left"),
                                    desc: I18n.tr("Căn lệch phía bên trái", "Align to the left")
                                },
                                {
                                    key: "right",
                                    name: I18n.tr("Bên phải", "Right"),
                                    desc: I18n.tr("Căn lệch phía bên phải", "Align to the right")
                                }
                            ]

                            Repeater {
                                model: alignCol.alignOptions
                                delegate: Rectangle {
                                    width: alignCol.width - 10
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    height: 38
                                    radius: 7
                                    color: (root.taskbarLyricsAlign === modelData.key)
                                           ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.26)
                                           : (alItemMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14) : "transparent")
                                    border.color: (root.taskbarLyricsAlign === modelData.key)
                                                  ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                                                  : (alItemMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25) : "transparent")
                                    border.width: 1

                                    Behavior on color { ColorAnimation { duration: 100 } }
                                    Behavior on border.color { ColorAnimation { duration: 100 } }

                                    Item {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10

                                        Column {
                                            anchors.left: parent.left
                                            anchors.right: alCheckIcon.left
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 1

                                            Text {
                                                text: modelData.name
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                font.bold: root.taskbarLyricsAlign === modelData.key
                                                color: (root.taskbarLyricsAlign === modelData.key) ? "#ffffff" : (alItemMouse.containsMouse ? "#ffffff" : Qt.rgba(255, 255, 255, 0.85))
                                            }

                                            Text {
                                                text: modelData.desc
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                color: (root.taskbarLyricsAlign === modelData.key) ? Qt.rgba(255, 255, 255, 0.80) : Theme.textSecondary
                                            }
                                        }

                                        AppIcon {
                                            id: alCheckIcon
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            source: "../assets/icons/emblem-ok-symbolic.svg"
                                            iconSize: 12
                                            color: root.accentColor
                                            visible: root.taskbarLyricsAlign === modelData.key
                                        }
                                    }

                                    MouseArea {
                                        id: alItemMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.changeTaskbarLyricsAlignRequested(modelData.key);
                                            alignRowItem.menuOpen = false;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Secondary Switch: Romanization (Romaji / Romaja / Pinyin)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46

                    Column {
                        anchors.left: parent.left
                        anchors.right: toggleRomanization.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: I18n.tr("Phiên âm lời bài hát Latinh (Romanization)", "Lyrics Romanization")
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: I18n.tr("Hiển thị phát âm Romaji, Romaja, Pinyin bên dưới câu hát gốc", "Show Romaji, Romaja, and Pinyin readings under original lyrics")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                        }
                    }

                    // Toggle Switch Pill (Pinned to Right)
                    Rectangle {
                        id: toggleRomanization
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        height: 24
                        radius: 12
                        color: root.lyricsRomanizationEnabled ? root.accentColor : Qt.rgba(255, 255, 255, 0.14)
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            width: 18
                            height: 18
                            radius: 9
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.lyricsRomanizationEnabled ? parent.width - width - 3 : 3
                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            preventStealing: false
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleLyricsRomanizationRequested(!root.lyricsRomanizationEnabled)
                        }
                    }
                }

                // Lyrics Source Preference Row (100% Borderless, Expandable Clean Dropdown Pinned to Right)
                Item {
                    id: lyricsSourceRowItem
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    z: menuOpen ? 100 : 2

                    property bool menuOpen: false

                    Column {
                        anchors.left: parent.left
                        anchors.right: lyricsSourceDropdownBtn.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: I18n.tr("Nguồn ưu tiên tìm kiếm lời bài hát", "Preferred Lyrics Source")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: I18n.tr("Thứ tự ưu tiên phân giải lời bài hát (Spotify, BetterLyrics, LRCLIB...)", "Preferred source order for resolving lyrics (Spotify, BetterLyrics, LRCLIB...)")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                        }
                    }

                    // Dropdown Trigger (Chromatic Ghost Action Button)
                    Rectangle {
                        id: lyricsSourceDropdownBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 28
                        width: lyricsSourceBtnRow.implicitWidth + 16
                        radius: 6
                        color: (lyricsSourceBtnMouse.containsMouse || lyricsSourceRowItem.menuOpen)
                               ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                               : "transparent"
                        border.width: 0

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row {
                            id: lyricsSourceBtnRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: root.getLyricsSourceLabel(root.lyricsSource)
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                                color: (lyricsSourceBtnMouse.containsMouse || lyricsSourceRowItem.menuOpen) ? "#ffffff" : Qt.rgba(255, 255, 255, 0.85)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            AppIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                source: "../assets/icons/go-down-symbolic.svg"
                                iconSize: 10
                                color: root.accentColor
                                rotation: lyricsSourceRowItem.menuOpen ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }
                        }

                        MouseArea {
                            id: lyricsSourceBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var next = !lyricsSourceRowItem.menuOpen;
                                root.closeAllDropdowns();
                                lyricsSourceRowItem.menuOpen = next;
                            }
                        }
                    }

                    // Chromatic Salience Dropdown Popover Menu (Zero Dull Grey)
                    Rectangle {
                        id: lyricsSourceDropdownMenu
                        visible: lyricsSourceRowItem.menuOpen
                        anchors.top: lyricsSourceDropdownBtn.bottom
                        anchors.topMargin: 6
                        anchors.right: lyricsSourceDropdownBtn.right
                        width: 330
                        height: Math.min(380, lyricsSourceCol.implicitHeight + 12)
                        radius: 10
                        color: Qt.rgba(0.06 + root.accentColor.r * 0.08, 0.06 + root.accentColor.g * 0.08, 0.08 + root.accentColor.b * 0.12, 0.96)
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                        border.width: 1
                        clip: true
                        z: 100

                        Flickable {
                            id: lyricsSourceFlickable
                            anchors.fill: parent
                            anchors.margins: 4
                            contentHeight: lyricsSourceCol.implicitHeight + 6
                            contentWidth: width
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: lyricsSourceCol
                                width: parent.width
                                spacing: 3

                                readonly property var sourceOptions: [
                                    {
                                        key: "auto",
                                        name: I18n.tr("Tự động (Đa nguồn song song)", "Auto (Multi-Source Parallel)"),
                                        desc: I18n.tr("Gọi song song YouLyPlus, SimpMusic, LRCLIB, KuGou... với pickBest", "Parallel queries YouLyPlus, SimpMusic, LRCLIB, KuGou... with pickBest")
                                    },
                                    {
                                        key: "youlyplus",
                                        name: I18n.tr("YouLyPlus (Apple Music/QQ)", "YouLyPlus (Apple Music/QQ)"),
                                        desc: I18n.tr("Karaoke từng từ chuẩn studio kèm phân vai song ca", "Studio word-level karaoke with duet singer attribution")
                                    },
                                    {
                                        key: "simpmusic",
                                        name: I18n.tr("SimpMusic (YouTube Music)", "SimpMusic (YouTube Music)"),
                                        desc: I18n.tr("Kho lời rich-sync & karaoke từng từ chất lượng cao", "High-quality rich-sync & word-level karaoke from SimpMusic")
                                    },
                                    {
                                        key: "betterlyrics",
                                        name: I18n.tr("Apple Music (BetterLyrics)", "Apple Music (BetterLyrics)"),
                                        desc: I18n.tr("Định dạng TTML Apple Music từng từ độ chính xác cao", "High precision word-level Apple Music TTML")
                                    },
                                    {
                                        key: "spotify",
                                        name: I18n.tr("Spotify (sp_dc)", "Spotify (sp_dc)"),
                                        desc: I18n.tr("Lời đồng bộ word-level trực tiếp từ Spotify spclient", "Word-level synced lyrics directly from Spotify spclient")
                                    },
                                    {
                                        key: "lrclib",
                                        name: I18n.tr("LRCLIB", "LRCLIB"),
                                        desc: I18n.tr("Cơ sở dữ liệu LRC mã nguồn mở cộng đồng lớn nhất", "Largest open-source community LRC database")
                                    },
                                    {
                                        key: "kugou",
                                        name: I18n.tr("KuGou (酷狗音乐)", "KuGou (酷狗音乐)"),
                                        desc: I18n.tr("Kho lời bài hát KRC khổng lồ cho nhạc Á Đông & C-Pop", "Massive Asian & C-Pop KRC lyrics repository")
                                    },
                                    {
                                        key: "netease",
                                        name: I18n.tr("NetEase Cloud Music", "NetEase Cloud Music"),
                                        desc: I18n.tr("Kho lời bài hát phong phú cho nhạc Á Đông & Anime", "Rich lyrics repository for Asian & Anime tracks")
                                    },
                                    {
                                        key: "youtube",
                                        name: I18n.tr("Phụ đề YouTube", "YouTube Subtitles"),
                                        desc: I18n.tr("Phụ đề chính thức và phụ đề tự động trực tiếp từ YouTube", "Official subtitles & auto-captions from YouTube")
                                    }
                                ]

                                Repeater {
                                    model: lyricsSourceCol.sourceOptions
                                    delegate: Rectangle {
                                        width: lyricsSourceCol.width - 6
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        height: 42
                                        radius: 7
                                        color: (root.lyricsSource === modelData.key)
                                               ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.26)
                                               : (lsItemMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14) : "transparent")
                                        border.color: (root.lyricsSource === modelData.key)
                                                      ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                                                      : (lsItemMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25) : "transparent")
                                        border.width: 1

                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        Behavior on border.color { ColorAnimation { duration: 100 } }

                                        Item {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10

                                            Column {
                                                anchors.left: parent.left
                                                anchors.right: lsCheckIcon.left
                                                anchors.rightMargin: 8
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 1

                                                Text {
                                                    width: parent.width
                                                    text: modelData.name
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                    font.bold: root.lyricsSource === modelData.key
                                                    color: (root.lyricsSource === modelData.key) ? "#ffffff" : (lsItemMouse.containsMouse ? "#ffffff" : Qt.rgba(255, 255, 255, 0.85))
                                                    elide: Text.ElideRight
                                                }

                                                MarqueeText {
                                                    width: parent.width
                                                    text: modelData.desc
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    color: (root.lyricsSource === modelData.key) ? Qt.rgba(255, 255, 255, 0.80) : Theme.textSecondary
                                                    active: lyricsSourceRowItem.menuOpen
                                                }
                                            }

                                            AppIcon {
                                                id: lsCheckIcon
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                source: "../assets/icons/emblem-ok-symbolic.svg"
                                                iconSize: 12
                                                color: root.accentColor
                                                visible: root.lyricsSource === modelData.key
                                            }
                                        }

                                        MouseArea {
                                            id: lsItemMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.lyricsSource = modelData.key;
                                                root.saveLyricsSourceRequested(modelData.key);
                                                lyricsSourceRowItem.menuOpen = false;
                                            }
                                        }
                                    }
                                }
                            }
                        }
            ScrollEdgeFade {
                flickable: settingsFlickable
            }
                        ScrollEdgeFade {
                            flickable: lyricsSourceFlickable
                        }
                    }
                }

                // Section Title
                Text {
                    text: I18n.tr("CHỌN MẪU GIAO DIỆN (PRESETS)", "CHOOSE DISPLAY PRESETS")
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                    color: Theme.textMuted
                    Layout.topMargin: 2
                }

                // Live previews: the song playing now, or the built-in demo song
                Repeater {
                    model: LyricsPresets.list

                    delegate: LyricsPresetCard {
                        id: presetCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight

                        // Only cards inside the scrolled viewport load their preview
                        readonly property bool inView: {
                            settingsFlickable.contentY; settingsFlickable.height; presetCard.y; presetCard.height;
                            if (!root.lyricsPreviewsLive) return false;
                            var p = presetCard.mapToItem(settingsFlickable, 0, 0);
                            return p.y + presetCard.height > 0 && p.y < settingsFlickable.height;
                        }

                        meta: modelData
                        selected: root.lyricsPreset === modelData.id
                        running: inView && !root.kineticPanelOpen
                        isDemo: !root.lyricsPreviewUsesSong
                        customizable: modelData.id === 8
                        accentColor: root.accentColor
                        wallpaperSource: wallStill.still
                        magicFontFamily: root.magicFontFamily
                        activeLyrics: root.lyricsPreviewUsesSong ? root.previewLyrics : root.demoLyrics
                        currentTime: root.lyricsPreviewUsesSong ? root.previewTime : root.demoTime
                        isPlaying: true
                        currentTrack: root.lyricsPreviewUsesSong ? root.previewTrack : null
                        lyricsRomanizationEnabled: root.lyricsRomanizationEnabled
                        kineticOptions: root.kineticOptions
                        colHighlight: root.lyricsHost ? root.lyricsHost.colHighlight : "#deb06c"
                        colActiveText: root.lyricsHost ? root.lyricsHost.colActiveText : "#f8fafc"
                        colDeadText: root.lyricsHost ? root.lyricsHost.colDeadText : "#f1f5f9"
                        colShadowDir: root.lyricsHost ? root.lyricsHost.colShadowDir : "#a6020305"
                        colShadowAmb: root.lyricsHost ? root.lyricsHost.colShadowAmb : "#66000000"
                        isLightArea: root.lyricsHost ? root.lyricsHost.isLightArea : false
                        onPicked: root.selectLyricsPresetRequested(modelData.id)
                        onCustomize: root.kineticPanelOpen = true
                    }
                }

                // Bottom Frameless Row: Positioning & Reset (Button Pinned to Right)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38

                    Column {
                        anchors.left: parent.left
                        anchors.right: resetBtn.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: I18n.tr("Vị trí hiển thị trên màn hình", "Screen Display Position")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: (root.customX >= 0 && root.customY >= 0) ? I18n.tr("Kéo thả trực tiếp trên Desktop để dời vị trí.", "Drag directly on Desktop to reposition.") : I18n.tr("Tự động căn theo tỷ lệ màn hình • Kéo thả trực tiếp trên Desktop.", "Auto-aligned to screen ratio • Drag directly on Desktop.")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textSecondary
                        }
                    }

                    Rectangle {
                        id: resetBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 28
                        width: resetRow.implicitWidth + 16
                        radius: 6
                        color: resetMouse.containsMouse
                               ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                               : "transparent"
                        border.width: 0
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row {
                            id: resetRow
                            anchors.centerIn: parent
                            spacing: 6

                            AppIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                source: "../assets/icons/media-playlist-repeat-symbolic.svg"
                                iconSize: 12
                                color: root.accentColor
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Đặt lại mặc định", "Reset Defaults")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                color: resetMouse.containsMouse ? "#ffffff" : Qt.rgba(255, 255, 255, 0.85)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                        }

                        MouseArea {
                            id: resetMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.resetLyricsPositionRequested()
                        }
                    }
                }
            } // Close tab1Content
        } // Close inner Item
    } // Close settingsScroll
} // Close ColumnLayout

        KineticOptionsPanel {
            anchors.fill: parent
            z: 20
            open: root.kineticPanelOpen
            options: root.kineticOptions
            accentColor: root.accentColor
            lite: root.liteMode === "on" || (root.liteMode === "auto" && root.liteModeAutoActive)
            wallpaperSource: wallStill.still
            magicFontFamily: root.magicFontFamily
            isDemo: !root.lyricsPreviewUsesSong
            activeLyrics: root.lyricsPreviewUsesSong ? root.previewLyrics : root.demoLyrics
            currentTime: root.lyricsPreviewUsesSong ? root.previewTime : root.demoTime
            isPlaying: true
            currentTrack: root.lyricsPreviewUsesSong ? root.previewTrack : null
            lyricsRomanizationEnabled: root.lyricsRomanizationEnabled
            colHighlight: root.lyricsHost ? root.lyricsHost.colHighlight : "#deb06c"
            colActiveText: root.lyricsHost ? root.lyricsHost.colActiveText : "#f8fafc"
            colDeadText: root.lyricsHost ? root.lyricsHost.colDeadText : "#f1f5f9"
            colShadowDir: root.lyricsHost ? root.lyricsHost.colShadowDir : "#a6020305"
            colShadowAmb: root.lyricsHost ? root.lyricsHost.colShadowAmb : "#66000000"
            isLightArea: root.lyricsHost ? root.lyricsHost.isLightArea : false
            onChangeOption: (key, value) => root.changeKineticOptionRequested(key, value)
            onClosed: root.kineticPanelOpen = false
        }
    } // Close dialog
}
