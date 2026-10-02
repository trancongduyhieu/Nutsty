import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import "."

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
    property bool isProcessing: false
    property bool syncHistoryToGoogle: true
    property bool animatedCoverEnabled: true
    property string canvasPreference: "apple_first"
    property int currentTab: 0 // 0: Google Account, 1: Desktop Lyrics
    property bool desktopLyricsEnabled: true
    property int lyricsPreset: 2 // 1: Gacha, 2: Apple Music 5-Line, 3: Minimalist Blur, 4: Anime MV Kinetic
    property int customX: -1
    property int customY: -1
    property string currentLanguage: I18n.locale
    property string streamingQuality: "high_opus"
    property string downloadQuality: "high_opus"
    property string spotifySpdc: ""
    property string lyricsSource: "auto"
    property string spotifyStatusMessage: ""
    property bool spotifyStatusSuccess: false
    property bool spotifyMasked: true
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent
    property bool manualCookieExpanded: false
    property bool spotifyExpanded: false
    property bool spotifyAutoSyncing: false
    property bool manualSpotifyExpanded: false
    property bool spotifyValidating: false
    property string appVersion: "1.0.2"
    property string latestVersion: "1.0.2"
    property bool hasAppUpdate: false
    property bool isCheckingUpdate: false
    property bool isDownloadingUpdate: false
    property real updateProgress: 0.0
    property string updateStatusMessage: ""

    signal checkUpdateRequested()
    signal openUpdateUrlRequested()
    signal startDirectUpdateRequested()
    signal applyUpdateRequested()

    onVisibleChanged: {
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
            root.statusMessage = I18n.tr("Clipboard đang rỗng. Hãy copy mã cookie rồi thử lại.", "Clipboard is empty. Please copy cookie text first.");
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
            root.statusMessage = I18n.tr("Đã nhận diện cookie từ Clipboard! Đang kết nối...", "Detected cookie from Clipboard! Connecting...");
            root.connectRequested(text);
        } else {
            root.statusMessage = I18n.tr("Dữ liệu Clipboard không chứa cookie YouTube Music hợp lệ. Hãy kiểm tra lại.", "Clipboard does not contain valid YouTube Music cookies. Please check.");
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
            root.spotifyStatusMessage = I18n.tr("Clipboard đang rỗng. Hãy sao chép chuỗi sp_dc trước.", "Clipboard is empty. Please copy sp_dc string first.");
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
        root.spotifyStatusMessage = I18n.tr("Đã dán chuỗi từ Clipboard! Bấm Lưu để kết nối.", "Pasted from Clipboard! Click Save to connect.");
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
    signal saveCanvasPreferenceRequested(string pref)
    signal toggleDesktopLyricsRequested(bool enabled)
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
        if (src === "spotify") {
            return I18n.tr("Spotify (sp_dc)", "Spotify (sp_dc)");
        } else if (src === "betterlyrics") {
            return I18n.tr("Apple Music (BetterLyrics)", "Apple Music (BetterLyrics)");
        } else if (src === "lrclib") {
            return I18n.tr("LRCLIB", "LRCLIB");
        } else if (src === "netease") {
            return I18n.tr("NetEase Cloud Music", "NetEase Cloud Music");
        } else {
            return I18n.tr("Tự động (Khuyến nghị)", "Auto (Recommended)");
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

    function closeAllDropdowns() {
        if (typeof langRowItem !== "undefined" && langRowItem) langRowItem.menuOpen = false;
        if (typeof streamQualityRowItem !== "undefined" && streamQualityRowItem) streamQualityRowItem.menuOpen = false;
        if (typeof downloadQualityRowItem !== "undefined" && downloadQualityRowItem) downloadQualityRowItem.menuOpen = false;
        if (typeof canvasPrefRowItem !== "undefined" && canvasPrefRowItem) canvasPrefRowItem.menuOpen = false;
        if (typeof lyricsSourceRowItem !== "undefined" && lyricsSourceRowItem) lyricsSourceRowItem.menuOpen = false;
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
    // Elevation: MultiEffect Drop Shadow behind Dialog
    // =========================================================================
    Rectangle {
        id: shadowShape
        anchors.fill: dialog
        radius: dialog.radius
        color: "#000000"
        visible: false
    }

    MultiEffect {
        anchors.fill: shadowShape
        source: shadowShape
        shadowEnabled: true
        shadowColor: "#80000000"
        shadowVerticalOffset: 6
        shadowBlur: 0.65
        z: 1
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
                    x: root.currentTab === 0 ? tab0Btn.x : tab1Btn.x
                    width: root.currentTab === 0 ? tab0Btn.width : tab1Btn.width

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
                    implicitHeight: (root.currentTab === 0
                                     ? tab0Content.implicitHeight + (langRowItem.menuOpen || streamQualityRowItem.menuOpen || downloadQualityRowItem.menuOpen || (typeof canvasPrefRowItem !== "undefined" && canvasPrefRowItem.menuOpen) ? 240 : 30)
                                     : tab1Content.implicitHeight + (typeof lyricsSourceRowItem !== "undefined" && lyricsSourceRowItem.menuOpen ? 240 : 0)) + 8

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
                                text: root.accountEmail ? root.accountEmail : I18n.tr("Đã kết nối Cloud", "Connected to Cloud")
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
                            color: (root.statusMessage.indexOf("Success") !== -1 || root.statusMessage.indexOf("Connected") !== -1) ? root.accentColor : "#f87171"
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
                            visible: root.statusMessage.indexOf("Error") !== -1 || root.statusMessage.indexOf("Failed") !== -1 || root.statusMessage.indexOf("timed out") !== -1
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
                            text: I18n.tr("Đồng bộ lịch sử nghe nhạc lên Cloud (YouTube Music)", "Sync listening history to Cloud (YouTube Music)")
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
                    Layout.preferredHeight: (root.isDownloadingUpdate || root.updateProgress > 0.0) ? 76 : 56
                    Layout.topMargin: 4
                    Layout.bottomMargin: 16

                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 160 } }

                    Column {
                        anchors.left: parent.left
                        anchors.right: updateActionsRow.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: (root.isDownloadingUpdate || root.updateProgress > 0.0) ? undefined : parent.verticalCenter
                        anchors.top: (root.isDownloadingUpdate || root.updateProgress > 0.0) ? parent.top : undefined
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
                        anchors.right: parent.right
                        anchors.verticalCenter: (root.isDownloadingUpdate || root.updateProgress > 0.0) ? undefined : parent.verticalCenter
                        anchors.top: (root.isDownloadingUpdate || root.updateProgress > 0.0) ? parent.top : undefined
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

                        // 3. Check for Updates Button
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

                // Status Message (When Logged In)
                Text {
                    Layout.fillWidth: true
                    text: root.statusMessage
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.bold: true
                    color: (root.statusMessage.indexOf("Success") !== -1 || root.statusMessage.indexOf("Connected") !== -1) ? root.accentColor : "#f87171"
                    visible: root.isLoggedIn && root.statusMessage.length > 0
                    wrapMode: Text.Wrap
                }

            } // Close tab0Content

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
                            text: I18n.tr("Hiển thị lời bài hát nổi trực tiếp trên hình nền Wayland", "Display floating lyrics directly on Wayland desktop wallpaper")
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
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleDesktopLyricsRequested(!root.desktopLyricsEnabled)
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
                        width: 290
                        height: lyricsSourceCol.implicitHeight + 10
                        radius: 10
                        color: Qt.rgba(0.06 + root.accentColor.r * 0.08, 0.06 + root.accentColor.g * 0.08, 0.08 + root.accentColor.b * 0.12, 0.96)
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                        border.width: 1
                        z: 100

                        Column {
                            id: lyricsSourceCol
                            anchors.top: parent.top
                            anchors.topMargin: 5
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 3

                            readonly property var sourceOptions: [
                                {
                                    key: "auto",
                                    name: I18n.tr("Tự động (Khuyến nghị)", "Auto (Recommended)"),
                                    desc: I18n.tr("Spotify (nếu có sp_dc) → BetterLyrics → LRCLIB → NetEase", "Spotify (if sp_dc) → BetterLyrics → LRCLIB → NetEase")
                                },
                                {
                                    key: "spotify",
                                    name: I18n.tr("Spotify (sp_dc)", "Spotify (sp_dc)"),
                                    desc: I18n.tr("Lời đồng bộ word-level trực tiếp từ Spotify spclient", "Word-level synced lyrics directly from Spotify spclient")
                                },
                                {
                                    key: "betterlyrics",
                                    name: I18n.tr("Apple Music (BetterLyrics)", "Apple Music (BetterLyrics)"),
                                    desc: I18n.tr("Định dạng TTML Apple Music từng từ độ chính xác cao", "High precision word-level Apple Music TTML")
                                },
                                {
                                    key: "lrclib",
                                    name: I18n.tr("LRCLIB", "LRCLIB"),
                                    desc: I18n.tr("Cơ sở dữ liệu LRC mã nguồn mở cộng đồng", "Open-source community LRC database")
                                },
                                {
                                    key: "netease",
                                    name: I18n.tr("NetEase Cloud Music", "NetEase Cloud Music"),
                                    desc: I18n.tr("Kho lời bài hát phong phú cho nhạc Á Đông & Anime", "Rich lyrics repository for Asian & Anime tracks")
                                }
                            ]

                            Repeater {
                                model: lyricsSourceCol.sourceOptions
                                delegate: Rectangle {
                                    width: lyricsSourceCol.width - 10
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

                // -------------------------------------------------------------
                // PRESET 1: Gacha / Anime Pop (100% Frameless Row)
                // -------------------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    radius: 8
                    color: p1Hover.hovered ? Qt.rgba(255, 255, 255, 0.05) : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }

                    HoverHandler { id: p1Hover }

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8

                        // Left: Title & Subtitle
                        Column {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            width: 195

                            Text {
                                text: I18n.tr("Mẫu 1: Điện ảnh Serif", "Preset 1: Cinematic Serif")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                color: root.lyricsPreset === 1 ? "#ffffff" : (p1Hover.hovered ? "#ffffff" : Theme.textPrimary)
                            }

                            Text {
                                text: I18n.tr("1 dòng • Instrument Serif", "1 line • Instrument Serif")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.textSecondary
                            }
                        }

                        // Center: Live Lyric Typography Preview (Floating naturally on glass)
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 205
                            anchors.right: check1.left
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: "君の笑顔が 眩しくて..."
                            font.family: root.magicFontFamily
                            font.italic: true
                            font.pixelSize: 15
                            color: "#ffffff"
                            elide: Text.ElideRight
                        }

                        // Right: Circular Radio Checkmark Badge (Pinned to Right)
                        Rectangle {
                            id: check1
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20
                            height: 20
                            radius: 10
                            color: root.lyricsPreset === 1 ? "#ffffff" : "transparent"
                            border.color: root.lyricsPreset === 1 ? "#ffffff" : (p1Hover.hovered ? Qt.rgba(255, 255, 255, 0.40) : Qt.rgba(255, 255, 255, 0.20))
                            border.width: root.lyricsPreset === 1 ? 0 : 1.5
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            AppIcon {
                                anchors.centerIn: parent
                                source: "../assets/icons/emblem-ok-symbolic.svg"
                                iconSize: 12
                                color: "#000000"
                                visible: root.lyricsPreset === 1
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        preventStealing: false
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectLyricsPresetRequested(1)
                    }
                }

                // -------------------------------------------------------------
                // PRESET 2: Apple Music 5-Line Fluid Sync (100% Frameless Row)
                // -------------------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    radius: 8
                    color: p2Hover.hovered ? Qt.rgba(255, 255, 255, 0.05) : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }

                    HoverHandler { id: p2Hover }

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8

                        // Left: Title & Subtitle
                        Column {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            width: 195

                            Text {
                                text: I18n.tr("Mẫu 2: Apple Music", "Preset 2: Apple Music")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                color: root.lyricsPreset === 2 ? "#ffffff" : (p2Hover.hovered ? "#ffffff" : Theme.textPrimary)
                            }

                            Text {
                                text: I18n.tr("5 dòng • DoF quang học", "5 lines • Optical DoF")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.textSecondary
                            }
                        }

                        // Center: Live Lyric Typography Preview (Floating naturally on glass)
                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 205
                            anchors.right: check2.left
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                text: "Soft memories remain..."
                                font.family: Theme.fontFamily
                                font.pixelSize: 8
                                color: "#ffffff"
                                opacity: 0.35
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            Text {
                                text: "And every melody feels alive"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                color: "#ffffff"
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            Text {
                                text: "Until the morning light..."
                                font.family: Theme.fontFamily
                                font.pixelSize: 8
                                color: "#ffffff"
                                opacity: 0.35
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        // Right: Circular Radio Checkmark Badge (Pinned to Right)
                        Rectangle {
                            id: check2
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20
                            height: 20
                            radius: 10
                            color: root.lyricsPreset === 2 ? "#ffffff" : "transparent"
                            border.color: root.lyricsPreset === 2 ? "#ffffff" : (p2Hover.hovered ? Qt.rgba(255, 255, 255, 0.40) : Qt.rgba(255, 255, 255, 0.20))
                            border.width: root.lyricsPreset === 2 ? 0 : 1.5
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            AppIcon {
                                anchors.centerIn: parent
                                source: "../assets/icons/emblem-ok-symbolic.svg"
                                iconSize: 12
                                color: "#000000"
                                visible: root.lyricsPreset === 2
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        preventStealing: false
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectLyricsPresetRequested(2)
                    }
                }

                // -------------------------------------------------------------
                // PRESET 3: Tối giản lướt (100% Frameless Row)
                // -------------------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    radius: 8
                    color: p3Hover.hovered ? Qt.rgba(255, 255, 255, 0.05) : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }

                    HoverHandler { id: p3Hover }

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8

                        // Left: Title & Subtitle
                        Column {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            width: 195

                            Text {
                                text: I18n.tr("Mẫu 3: Tối giản lướt", "Preset 3: Minimal Glide")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                color: root.lyricsPreset === 3 ? "#ffffff" : (p3Hover.hovered ? "#ffffff" : Theme.textPrimary)
                            }

                            Text {
                                text: I18n.tr("2 dòng • Motion Blur", "2 lines • Motion Blur")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.textSecondary
                            }
                        }

                        // Center: Live Lyric Typography Preview (Floating naturally on glass)
                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 205
                            anchors.right: check3.left
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                text: "Yesterday is fading away"
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                color: Theme.textSecondary
                                opacity: 0.50
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            Text {
                                text: "Now tomorrow is singing"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                color: Theme.textPrimary
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        // Right: Circular Radio Checkmark Badge (Pinned to Right)
                        Rectangle {
                            id: check3
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20
                            height: 20
                            radius: 10
                            color: root.lyricsPreset === 3 ? "#ffffff" : "transparent"
                            border.color: root.lyricsPreset === 3 ? "#ffffff" : (p3Hover.hovered ? Qt.rgba(255, 255, 255, 0.40) : Qt.rgba(255, 255, 255, 0.20))
                            border.width: root.lyricsPreset === 3 ? 0 : 1.5
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            AppIcon {
                                anchors.centerIn: parent
                                source: "../assets/icons/emblem-ok-symbolic.svg"
                                iconSize: 12
                                color: "#000000"
                                visible: root.lyricsPreset === 3
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        preventStealing: false
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectLyricsPresetRequested(3)
                    }
                }

                // -------------------------------------------------------------
                // PRESET 4: Anime MV Kinetic Typography (100% Frameless Row)
                // -------------------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    radius: 8
                    color: p4Hover.hovered ? Qt.rgba(255, 255, 255, 0.05) : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }

                    HoverHandler { id: p4Hover }

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8

                        // Left: Title & Subtitle
                        Column {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            width: 195

                            Text {
                                text: I18n.tr("Mẫu 4: Đồ họa Chuyển động", "Preset 4: Motion Typography")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                color: root.lyricsPreset === 4 ? "#ffffff" : (p4Hover.hovered ? "#ffffff" : Theme.textPrimary)
                            }

                            Text {
                                text: I18n.tr("Chữ khối • Bento Frame", "Block text • Bento Frame")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.textSecondary
                            }
                        }

                        // Center: Live Lyric Typography Preview (Floating naturally on glass)
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 205
                            anchors.right: check4.left
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: "[ MOTION GRAPHICS ]"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 2.0
                            color: "#ffffff"
                            elide: Text.ElideRight
                        }

                        // Right: Circular Radio Checkmark Badge (Pinned to Right)
                        Rectangle {
                            id: check4
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20
                            height: 20
                            radius: 10
                            color: root.lyricsPreset === 4 ? "#ffffff" : "transparent"
                            border.color: root.lyricsPreset === 4 ? "#ffffff" : (p4Hover.hovered ? Qt.rgba(255, 255, 255, 0.40) : Qt.rgba(255, 255, 255, 0.20))
                            border.width: root.lyricsPreset === 4 ? 0 : 1.5
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            AppIcon {
                                anchors.centerIn: parent
                                source: "../assets/icons/emblem-ok-symbolic.svg"
                                iconSize: 12
                                color: "#000000"
                                visible: root.lyricsPreset === 4
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        preventStealing: false
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectLyricsPresetRequested(4)
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
    } // Close dialog
}
