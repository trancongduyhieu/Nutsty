import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import "."

// App update dialog. One surface walks the whole update: compare, download only what changed,
// restart. The shell owns the real state and feeds it in; this file only draws it and emits intents.
Item {
    id: root
    anchors.fill: parent
    enabled: isOpen || closingGuard
    visible: opacity > 0 || closingGuard
    opacity: isOpen ? 1 : 0
    z: 9998
    focus: isOpen
    Keys.onEscapePressed: root.closeModal()

    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    property bool isOpen: false
    property bool closingGuard: false
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent
    property Item backgroundSourceItem: null
    property bool liteMode: (typeof win !== "undefined") ? !!win.liteMode : false

    // Fed by the shell
    property string appVersion: ""
    property string latestVersion: ""
    property bool hasAppUpdate: false
    property bool isChecking: false
    property string releaseNotes: ""
    property real packageBytes: 0
    // Mirrors /api/update/status: status, percent, progress, bytes_done, bytes_total, speed, eta, mode, plan, error
    property var updateState: ({})

    signal planRequested()
    signal startRequested()
    signal cancelRequested()
    signal applyRequested()
    signal checkRequested()
    signal releasePageRequested()
    signal closeRequested()

    readonly property string stateName: (updateState && updateState.status) ? updateState.status : "idle"
    readonly property var plan: (updateState && updateState.plan) ? updateState.plan : null
    readonly property bool busy: stateName === "downloading" || stateName === "extracting"
    // checking | upToDate | available | planning | downloading | ready | error
    readonly property string phase: {
        if (stateName === "ready") return "ready";
        if (busy) return "downloading";
        if (stateName === "error") return "error";
        if (stateName === "planning") return "planning";
        if (isChecking) return "checking";
        return hasAppUpdate ? "available" : "upToDate";
    }
    readonly property string cleanLatest: String(latestVersion || "").replace(/^[vV]/, "")
    readonly property string cleanCurrent: String(appVersion || "").replace(/^[vV]/, "")
    property var changelogItems: []

    function openModal() {
        closeTimer.stop();
        closingGuard = false;
        refreshNotes();
        isOpen = true;
        forceActiveFocus();
        if (hasAppUpdate && !busy && stateName !== "ready") root.planRequested();
    }

    function closeModal() {
        if (!isOpen && !closingGuard) return;
        isOpen = false;
        closingGuard = true;
        closeTimer.restart();
        root.closeRequested();
    }

    Timer { id: closeTimer; interval: 200; onTriggered: root.closingGuard = false }

    onReleaseNotesChanged: refreshNotes()

    // The release body is the CHANGELOG section: "- **Title**: detail" lines, sub-bullets indented
    function refreshNotes() {
        var out = [];
        var lines = String(root.releaseNotes || "").split(/\r?\n/);
        for (var i = 0; i < lines.length; i++) {
            var raw = lines[i];
            if (/^\s+[-*]/.test(raw) || !/^[-*]\s+/.test(raw)) continue;
            var body = raw.replace(/^[-*]\s+/, "").trim();
            if (/^\**bước\s*\d+/i.test(body)) continue;
            var m = body.match(/^\*\*([^*]+)\*\*[:\s\-—]+(.*)$/);
            var title = m ? m[1].trim() : body.replace(/\*\*/g, "");
            var detail = m ? m[2].replace(/\*\*/g, "").trim() : "";
            if (title) out.push({ "title": title, "detail": detail });
        }
        root.changelogItems = out;
    }

    function formatBytes(n) {
        var v = Number(n) || 0;
        if (v >= 1073741824) return (v / 1073741824).toFixed(1) + " GB";
        if (v >= 1048576) return (v / 1048576).toFixed(v >= 104857600 ? 0 : 1) + " MB";
        if (v >= 1024) return Math.round(v / 1024) + " KB";
        return Math.round(v) + " B";
    }

    function formatEta(sec) {
        var s = Number(sec);
        if (!(s >= 0)) return "";
        if (s < 60) return I18n.tr("còn khoảng " + Math.max(1, Math.round(s)) + " giây", "about " + Math.max(1, Math.round(s)) + " s left");
        return I18n.tr("còn khoảng " + Math.ceil(s / 60) + " phút", "about " + Math.ceil(s / 60) + " min left");
    }

    // Plain-language headline for the current phase
    readonly property string headline: {
        switch (phase) {
        case "checking": return I18n.tr("Đang kiểm tra", "Checking");
        case "upToDate": return I18n.tr("Bạn đang dùng bản mới nhất", "You are up to date");
        case "available": return I18n.tr("Có bản mới", "A new version is here");
        case "planning": return I18n.tr("Đang so sánh với bản của bạn", "Comparing with your version");
        case "downloading": return stateName === "extracting" ? I18n.tr("Đang chuẩn bị", "Getting ready") : I18n.tr("Đang tải", "Downloading");
        case "ready": return I18n.tr("Đã sẵn sàng", "Ready to install");
        default: return I18n.tr("Cập nhật chưa xong", "The update did not finish");
        }
    }

    // What the download costs, in one sentence
    readonly property string sizeLine: {
        if (phase === "planning" || phase === "checking") return "";
        if (plan && plan.download_bytes >= 0 && updateState.mode === "delta") {
            if (plan.changed === 0) return I18n.tr("Không có gì cần tải, chỉ cần khởi động lại", "Nothing to download, just a restart");
            return I18n.tr("Chỉ tải phần thay đổi: " + formatBytes(plan.download_bytes) + " thay vì " + formatBytes(plan.full_bytes),
                           "Only what changed: " + formatBytes(plan.download_bytes) + " instead of " + formatBytes(plan.full_bytes));
        }
        if (packageBytes > 0) return I18n.tr("Dung lượng tải: " + formatBytes(packageBytes), "Download size: " + formatBytes(packageBytes));
        return "";
    }
    readonly property real savedPercent: (plan && updateState.mode === "delta" && plan.full_bytes > 0)
        ? Math.max(0, Math.min(99, Math.round(100 * (1 - plan.download_bytes / plan.full_bytes)))) : 0

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.58)
        MouseArea { anchors.fill: parent; onClicked: if (!root.busy) root.closeModal() }
    }

    LiquidGlass {
        id: dialog
        width: Math.min(460, parent.width - 32)
        height: Math.min(640, parent.height - 48)
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

        scale: root.isOpen ? 1.0 : 0.94
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Rectangle { anchors.fill: parent; radius: dialog.radius; color: Qt.rgba(0.04, 0.05, 0.08, 0.88); z: 1 }
        Rectangle {
            anchors.fill: parent; radius: dialog.radius; color: "transparent"
            border.color: Qt.rgba(255, 255, 255, 0.18); border.width: 1; z: 20
        }
        MouseArea { anchors.fill: parent; z: 2; onClicked: mouse => { mouse.accepted = true; } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 14
            z: 5

            // Close
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                Text {
                    text: I18n.tr("Cập nhật", "Update")
                    font.family: Theme.fontFamily; font.pixelSize: 20; font.bold: true
                    color: Theme.textPrimary
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 32; height: 32; radius: 16
                    opacity: root.busy ? 0.4 : 1
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
                        enabled: !root.busy
                        onClicked: root.closeModal()
                    }
                }
            }

            // Hero: the version ring turns slowly; its middle shows the version, then the live percent
            Item {
                id: hero
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 200
                Layout.preferredHeight: 200

                Item {
                    id: ring
                    anchors.fill: parent
                    readonly property string unit: "NUTSTY  " + (root.cleanLatest || root.cleanCurrent) + "  "
                    // Whole repeats of the unit, so the text meets itself at the seam
                    readonly property int cells: unit.length * Math.max(1, Math.round(34 / unit.length))

                    Rectangle {
                        anchors.centerIn: parent
                        width: 2 * 88 + 2; height: width; radius: width / 2
                        color: "transparent"
                        border.width: 28
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, root.phase === "ready" ? 0.22 : 0.10)
                        Behavior on border.color { ColorAnimation { duration: 400 } }
                    }

                    Item {
                        id: spinner
                        anchors.fill: parent
                        NumberAnimation on rotation {
                            from: 0; to: 360; duration: 32000
                            loops: Animation.Infinite
                            running: root.isOpen && !root.liteMode
                        }
                        Repeater {
                            model: ring.cells
                            delegate: Item {
                                required property int index
                                width: 0; height: 0
                                x: spinner.width / 2; y: spinner.height / 2
                                rotation: index * 360 / ring.cells
                                Text {
                                    x: -width / 2
                                    y: -74 - height / 2
                                    text: ring.unit.charAt(index % ring.unit.length)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13; font.bold: true
                                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.55)
                                }
                            }
                        }
                    }

                    // The middle of the ring
                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: root.phase !== "downloading" && root.phase !== "ready"
                            text: root.phase === "upToDate" ? root.cleanCurrent : (root.cleanLatest || root.cleanCurrent)
                            font.family: Theme.fontFamily; font.pixelSize: 36; font.bold: true
                            font.letterSpacing: -1
                            color: Theme.textPrimary
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: root.phase === "available" || root.phase === "planning"
                            text: I18n.tr("từ " + root.cleanCurrent, "from " + root.cleanCurrent)
                            font.family: Theme.fontFamily; font.pixelSize: 12
                            color: Theme.textSecondary
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: root.phase === "downloading"
                            text: (root.updateState.percent || 0) + "%"
                            font.family: Theme.fontFamily; font.pixelSize: 40; font.bold: true
                            font.letterSpacing: -1
                            color: Theme.textPrimary
                        }
                        AppIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: root.phase === "ready"
                            source: "../assets/icons/emblem-ok-symbolic.svg"
                            iconSize: 44
                            color: root.accentColor
                        }
                    }

                    CircularSpinner {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: parent.height / 2 + 28
                        size: 22
                        visible: root.phase === "planning" || root.phase === "checking"
                        color: root.accentColor
                    }
                }
            }

            // Headline and the size sentence
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.headline
                    font.family: Theme.fontFamily; font.pixelSize: 17; font.bold: true
                    color: Theme.textPrimary
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    visible: text !== ""
                    text: root.phase === "error" ? String(root.updateState.error || "")
                          : (root.phase === "downloading"
                             ? (root.formatBytes(root.updateState.bytes_done) + " / " + root.formatBytes(root.updateState.bytes_total)
                                + (root.updateState.speed > 1 ? "  ·  " + root.formatBytes(root.updateState.speed) + "/s" : "")
                                + (root.formatEta(root.updateState.eta) !== "" ? "  ·  " + root.formatEta(root.updateState.eta) : ""))
                             : (root.phase === "ready" ? I18n.tr("Bấm Khởi động lại để dùng bản " + root.cleanLatest, "Restart to use version " + root.cleanLatest) : root.sizeLine))
                    font.family: Theme.fontFamily; font.pixelSize: 12
                    color: root.phase === "error" ? Qt.rgba(244 / 255, 63 / 255, 94 / 255, 1) : Theme.textSecondary
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.savedPercent >= 10 && (root.phase === "available")
                    text: I18n.tr("Nhẹ hơn " + root.savedPercent + "% so với tải cả bản", root.savedPercent + "% lighter than a full download")
                    font.family: Theme.fontFamily; font.pixelSize: 11; font.bold: true
                    color: root.accentColor
                }
            }

            // Progress bar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                radius: 3
                visible: root.phase === "downloading"
                color: Qt.rgba(255, 255, 255, 0.10)
                Rectangle {
                    height: parent.height; radius: 3
                    width: parent.width * Math.max(0.02, Math.min(1.0, root.updateState.progress || 0))
                    color: root.accentColor
                    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                }
            }

            // Release notes
            Flickable {
                id: notes
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.phase === "available" || root.phase === "planning" || root.phase === "downloading"
                clip: true
                contentWidth: width
                contentHeight: notesCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { width: 4; policy: ScrollBar.AsNeeded }

                Column {
                    id: notesCol
                    width: notes.width - 10
                    spacing: 12
                    Text {
                        text: I18n.tr("Có gì mới", "What is new")
                        font.family: Theme.fontFamily; font.pixelSize: 13; font.bold: true
                        color: Theme.textPrimary
                        visible: root.changelogItems.length > 0
                    }
                    Repeater {
                        model: root.changelogItems
                        delegate: Column {
                            required property var modelData
                            width: notesCol.width
                            spacing: 2
                            Text {
                                width: parent.width
                                text: modelData.title
                                font.family: Theme.fontFamily; font.pixelSize: 12; font.bold: true
                                color: Theme.textPrimary
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                width: parent.width
                                visible: modelData.detail !== ""
                                text: modelData.detail
                                font.family: Theme.fontFamily; font.pixelSize: 11
                                color: Theme.textSecondary
                                wrapMode: Text.WordWrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
            Item { Layout.fillHeight: true; visible: !notes.visible }

            // Actions
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // Secondary
                Rectangle {
                    Layout.preferredHeight: 40
                    Layout.preferredWidth: root.phase === "error" ? 160 : 120
                    Layout.fillWidth: root.phase === "upToDate" || root.phase === "downloading"
                    radius: 20
                    color: secHover.hovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                                            : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
                    border.width: 1
                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.32)
                    visible: root.phase !== "checking" && root.phase !== "planning"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    HoverHandler { id: secHover }
                    Text {
                        anchors.centerIn: parent
                        text: root.phase === "downloading" ? I18n.tr("Hủy", "Cancel")
                              : (root.phase === "upToDate" ? I18n.tr("Kiểm tra lại", "Check again")
                                 : (root.phase === "error" ? I18n.tr("Xem trên GitHub", "Open on GitHub") : I18n.tr("Để sau", "Later")))
                        font.family: Theme.fontFamily; font.pixelSize: 13; font.bold: true
                        color: root.accentColor
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.phase === "downloading") root.cancelRequested();
                            else if (root.phase === "upToDate") root.checkRequested();
                            else if (root.phase === "error") root.releasePageRequested();
                            else root.closeModal();
                        }
                    }
                }

                // Primary
                Rectangle {
                    id: primaryBtn
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 20
                    visible: root.phase === "available" || root.phase === "ready" || root.phase === "error"
                    color: priHover.hovered ? Theme.accentGreenHover : root.accentColor
                    opacity: root.phase === "planning" ? 0.5 : 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    HoverHandler { id: priHover }
                    Text {
                        anchors.centerIn: parent
                        text: root.phase === "ready" ? I18n.tr("Khởi động lại ngay", "Restart now")
                              : (root.phase === "error" ? I18n.tr("Thử lại", "Try again")
                                 : (root.plan && root.updateState.mode === "delta" && root.plan.download_bytes > 0
                                    ? I18n.tr("Cập nhật · " + root.formatBytes(root.plan.download_bytes), "Update · " + root.formatBytes(root.plan.download_bytes))
                                    : I18n.tr("Cập nhật ngay", "Update now")))
                        font.family: Theme.fontFamily; font.pixelSize: 13; font.bold: true
                        color: "#14100a"
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.phase === "ready") root.applyRequested();
                            else root.startRequested();
                        }
                    }
                }
            }
        }
    }
}
