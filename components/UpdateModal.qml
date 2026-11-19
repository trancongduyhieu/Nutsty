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

            // Close sits alone at the top right; the ring below carries the title
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
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

            // The ring turns slowly. Its middle is the Nutsty icon with the version (or the live percent) under it
            Item {
                id: hero
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: -22
                Layout.preferredWidth: 236
                Layout.preferredHeight: 236

                Item {
                    id: ring
                    anchors.fill: parent
                    readonly property real mid: 102
                    readonly property string unit: "NUTSTY  " + (root.cleanLatest || root.cleanCurrent) + "  "
                    // Whole repeats of the unit, so the text meets itself at the seam
                    readonly property int cells: unit.length * Math.max(1, Math.round(48 / unit.length))

                    Rectangle {
                        anchors.centerIn: parent
                        width: 2 * (ring.mid + 15); height: width; radius: width / 2
                        color: "transparent"
                        border.width: 30
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, root.phase === "ready" ? 0.24 : 0.10)
                        Behavior on border.color { ColorAnimation { duration: 400 } }
                    }

                    Item {
                        id: spinner
                        anchors.fill: parent
                        NumberAnimation on rotation {
                            from: 0; to: 360; duration: 40000
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
                                    y: -ring.mid - height / 2
                                    text: ring.unit.charAt(index % ring.unit.length)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13; font.bold: true
                                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.62)
                                }
                            }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 6

                        RoundedImage {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 72; height: 72
                            radius: 18
                            source: "../assets/nutsty-app-icon.svg"
                            sourceSize: Qt.size(144, 144)
                            fillMode: Image.PreserveAspectCrop
                            autoCropBlackBars: false
                            useInitialsFallback: false
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.phase === "downloading" ? ((root.updateState.percent || 0) + "%")
                                  : (root.phase === "upToDate" ? root.cleanCurrent : (root.cleanLatest || root.cleanCurrent))
                            font.family: Theme.fontFamily; font.pixelSize: 22; font.bold: true
                            font.letterSpacing: -0.4
                            color: Theme.textPrimary
                        }
                    }
                }
            }

            // Headline, then one plain sentence about the cost
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    Layout.fillWidth: true
                    text: root.phase === "available" || root.phase === "planning"
                          ? I18n.tr("Nutsty " + root.cleanLatest + " đã có", "Nutsty " + root.cleanLatest + " is out")
                          : root.headline
                    font.family: Theme.fontFamily; font.pixelSize: 22; font.bold: true
                    font.letterSpacing: -0.4
                    color: Theme.textPrimary
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.phase === "error" ? String(root.updateState.error || "")
                          : (root.phase === "downloading"
                             ? (root.formatBytes(root.updateState.bytes_done) + " / " + root.formatBytes(root.updateState.bytes_total)
                                + (root.updateState.speed > 1 ? "  ·  " + root.formatBytes(root.updateState.speed) + "/s" : "")
                                + (root.formatEta(root.updateState.eta) !== "" ? "  ·  " + root.formatEta(root.updateState.eta) : ""))
                             : (root.phase === "ready" ? I18n.tr("Bấm Khởi động lại để dùng bản " + root.cleanLatest, "Restart to use version " + root.cleanLatest)
                                : (root.phase === "available" && root.savedPercent >= 10
                                   ? root.sizeLine + I18n.tr(", nhẹ hơn " + root.savedPercent + "%", ", " + root.savedPercent + "% lighter")
                                   : root.sizeLine)))
                    font.family: Theme.fontFamily; font.pixelSize: 13
                    color: root.phase === "error" ? Qt.rgba(244 / 255, 63 / 255, 94 / 255, 1) : Theme.textSecondary
                    wrapMode: Text.WordWrap
                }
            }

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

            // Release notes: plain rows split by hairlines
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
                    spacing: 0
                    Repeater {
                        model: root.changelogItems
                        delegate: Column {
                            required property int index
                            required property var modelData
                            width: notesCol.width
                            Rectangle {
                                width: parent.width; height: 1
                                color: Qt.rgba(255, 255, 255, 0.08)
                                visible: index > 0
                            }
                            Item { width: 1; height: 10 }
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
                            Item { width: 1; height: 10 }
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
                    Layout.preferredHeight: 42
                    Layout.preferredWidth: root.phase === "error" ? 160 : 120
                    Layout.fillWidth: root.phase === "upToDate" || root.phase === "downloading"
                    radius: 12
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
                    Layout.preferredHeight: 42
                    radius: 12
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
