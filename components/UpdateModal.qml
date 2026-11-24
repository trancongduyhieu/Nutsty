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
    // 0 in Lite mode: every motion below multiplies its duration by this, so Lite shows the end state at once
    readonly property int motion: liteMode ? 0 : 1
    readonly property bool primaryOn: phase === "available" || phase === "ready" || phase === "error"

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
        planSettled = false;
        knownPlan = null;
        // Reopened while already downloading or ready: the plan in the state is current, no new compare is coming
        planFresh = busy || stateName === "ready" || !hasAppUpdate;
        minSpin = hasAppUpdate && !busy && stateName !== "ready";
        minSpinTimer.restart();
        planWait.restart();
        ringFwd.stop(); ringBack.stop();
        ringMotion.p = ringMoved ? 1 : 0;
        badge.replay();
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

    readonly property bool ringMoved: busy || phase === "ready"
    onRingMovedChanged: {
        if (ringMoved) { ringBack.stop(); ringFwd.restart(); }
        else { ringFwd.stop(); ringBack.restart(); }
    }
    // Out and back both overshoot a little and settle, like a cartoon landing
    NumberAnimation {
        id: ringFwd
        target: ringMotion; property: "p"; to: 1
        duration: 1100 * root.motion
        easing.type: Easing.OutBack; easing.overshoot: 1.7
    }
    NumberAnimation {
        id: ringBack
        target: ringMotion; property: "p"; to: 0
        duration: 900 * root.motion
        easing.type: Easing.OutBack; easing.overshoot: 1.2
    }

    Timer { id: closeTimer; interval: 200; onTriggered: root.closingGuard = false }

    onReleaseNotesChanged: refreshNotes()
    
    // The release body is the CHANGELOG section: "- **Title**: detail" lines, sub-bullets indented
    function refreshNotes() {
        var out = [];
        var lines = String(root.releaseNotes || "").split(/\r?\n/);
        for (var i = 0; i < lines.length; i++) {
            var raw = lines[i];
            var hm = raw.match(/^##\s+(v?[\d.]+)\s*$/);
            if (hm) { out.push({ "title": hm[1], "detail": "", "header": true }); continue; }
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

    // The last real answer about how much has to be downloaded. Kept across cancel/re-plan so the size never blinks away
    property var knownPlan: null
    // False right after open until the backend reports it is comparing, so a stale plan never shows
    property bool planFresh: false
    // Keeps the reels spinning for a moment even when the answer is instant, so the effect is always seen
    property bool minSpin: false
    Timer { id: minSpinTimer; interval: 900; onTriggered: root.minSpin = false }
    // True once the backend finished comparing (or we gave up waiting), so a plain package size may be shown
    property bool planSettled: false
    onUpdateStateChanged: {
        if (stateName === "planning") planFresh = true;
        if (plan && planFresh && updateState.mode === "delta" && plan.download_bytes >= 0) knownPlan = plan;
        if (planFresh && (stateName === "planned" || stateName === "error")) planSettled = true;
    }
    onLatestVersionChanged: { knownPlan = null; planSettled = false; }
    Timer { id: planWait; interval: 6000; onTriggered: { root.planFresh = true; root.planSettled = true; } }

    readonly property var shownPlan: (plan && planFresh) ? plan : knownPlan
    readonly property bool isDelta: !!shownPlan && shownPlan.download_bytes >= 0 && (knownPlan !== null || updateState.mode === "delta")
    // The whole package size only once comparing is over: while it runs the real (smaller) size is still coming
    readonly property bool fullSizeShown: planSettled && phase !== "planning" && packageBytes > 0
    readonly property bool sizeKnown: !minSpin && (isDelta || fullSizeShown)
    // Waiting for the size: show a quiet dot only, no text that would change under the reader
    readonly property bool sizePending: (phase === "available" || phase === "planning") && !sizeKnown
    readonly property real savedPercent: (isDelta && shownPlan.full_bytes > 0)
        ? Math.max(0, Math.min(99, Math.round(100 * (1 - shownPlan.download_bytes / shownPlan.full_bytes)))) : 0
    readonly property bool nothingToDownload: isDelta && shownPlan.changed === 0
    readonly property string sizeText: nothingToDownload ? I18n.tr("Không cần tải gì, chỉ cần khởi động lại", "Nothing to download, just restart") : ""
    // The figure that rolls on its reels: the delta size if we have it, else the whole package, else a placeholder that spins
    readonly property string sizeFigure: isDelta ? formatBytes(shownPlan.download_bytes)
                                      : (fullSizeShown ? formatBytes(packageBytes) : "00.0 MB")
    readonly property string sizeNumber: sizeFigure.split(" ")[0]
    readonly property string sizeUnit: sizeFigure.split(" ")[1] || ""
    readonly property bool showSizeRow: (phase === "available" || phase === "planning") && !nothingToDownload

    // Two fixed lines under the version: what matters now, then the detail. Both are always one line,
    // so the layout below never moves when the phase changes.
    readonly property string statusMain: {
        switch (phase) {
        case "checking": return I18n.tr("Đang kiểm tra", "Checking");
        case "upToDate": return I18n.tr("Bạn đang dùng bản mới nhất", "You are up to date");
        case "ready": return I18n.tr("Đã tải xong", "Download complete");
        case "downloading":
            return stateName === "extracting" ? I18n.tr("Đang chuẩn bị", "Getting ready")
                                              : I18n.tr("Đang tải " + (updateState.percent || 0) + "%", "Downloading " + (updateState.percent || 0) + "%");
        case "error": return I18n.tr("Cập nhật chưa xong", "The update did not finish");
        default: return sizeText;
        }
    }
    readonly property string statusSub: {
        switch (phase) {
        case "downloading":
            return formatBytes(updateState.bytes_done) + " / " + formatBytes(updateState.bytes_total)
                   + (updateState.speed > 1 ? "  ·  " + formatBytes(updateState.speed) + "/s" : "")
                   + (formatEta(updateState.eta) !== "" ? "  ·  " + formatEta(updateState.eta) : "");
        case "ready": return I18n.tr("Bấm Khởi động lại để dùng bản " + cleanLatest, "Restart to use version " + cleanLatest);
        case "error": return String(updateState.error || "");
        default: return "";
        }
    }

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

        scale: root.isOpen ? 1.0 : 0.97
        Behavior on scale { NumberAnimation { duration: 240 * root.motion; easing.type: Easing.OutCubic } }

        Rectangle { anchors.fill: parent; radius: dialog.radius; color: Qt.rgba(0.04, 0.05, 0.08, 0.88); z: 1 }
        Rectangle {
            anchors.fill: parent; radius: dialog.radius; color: "transparent"
            border.color: Qt.rgba(255, 255, 255, 0.18); border.width: 1; z: 20
        }
        MouseArea { anchors.fill: parent; z: 2; onClicked: mouse => { mouse.accepted = true; } }

        // Version ring. At rest it sits in the top-right corner, cropped by the dialog edge. When the update starts
        // that ring swells and leaves up and to the left, fading out, while a second one arrives from beyond the
        // bottom-left corner, overshoots a little and settles back, like a cartoon landing.
        QtObject { id: ringMotion; property real p: 0 }

        Repeater {
            model: 2
            delegate: Item {
                id: band
                required property int index
                readonly property bool isEnter: index === 1
                readonly property real p: ringMotion.p
                // Both rings travel the same distance upward, like a strip that wraps: whatever leaves through the
                // top edge of the dialog re-enters from the bottom edge, so the two crops always add up to one ring.
                readonly property real travel: 190
                width: 210; height: 210
                x: (isEnter ? 24 + 0.3 * travel * (1 - p) : dialog.width - 24 - 0.3 * travel * p) - width / 2
                y: (isEnter ? (dialog.height - 16 + travel * (1 - p)) : (16 - travel * p)) - height / 2
                scale: 1 + (isEnter ? 0.82 : 0.5) * p
                visible: isEnter ? p > 0.001 : p < 0.999
                z: 3
                readonly property real mid: 88
                readonly property string unit: "NUTSTY  " + (root.cleanLatest || root.cleanCurrent) + "  "
                // Whole repeats of the unit, so the text meets itself at the seam
                readonly property int cells: unit.length * Math.max(1, Math.round(48 / unit.length))

                Rectangle {
                    anchors.centerIn: parent
                    width: 2 * (band.mid + 14); height: width; radius: width / 2
                    color: "transparent"
                    border.width: 28
                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, root.phase === "ready" ? 0.24 : 0.10)
                    Behavior on border.color { ColorAnimation { duration: 400 * root.motion } }
                }
                Item {
                    id: spinner
                    anchors.fill: parent
                    NumberAnimation on rotation {
                        from: 0; to: 360; duration: 40000
                        loops: Animation.Infinite
                        running: root.isOpen && !root.liteMode && band.visible
                    }
                    Repeater {
                        model: band.cells
                        delegate: Item {
                            required property int index
                            width: 0; height: 0
                            x: spinner.width / 2; y: spinner.height / 2
                            rotation: index * 360 / band.cells
                            Text {
                                x: -width / 2
                                y: -band.mid - height / 2
                                text: band.unit.charAt(index % band.unit.length)
                                font.family: Theme.fontFamily
                                font.pixelSize: 12; font.bold: true
                                color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.62)
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            width: 32; height: 32; radius: 16
            anchors.top: parent.top; anchors.right: parent.right
            anchors.topMargin: 24; anchors.rightMargin: 24
            z: 10
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

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 14
            z: 5

            // The Nutsty mark in white (the outline SVG, tinted by AppIcon)
            AppIcon {
                Layout.alignment: Qt.AlignLeft
                Layout.preferredWidth: 64; Layout.preferredHeight: 64
                source: "../assets/icons/nutsty-outline-symbolic.svg"
                iconSize: 64
                color: "#ffffff"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: -2
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 80
                    spacing: 12
                    Text {
                        Layout.alignment: Qt.AlignBottom
                        text: root.phase === "upToDate" ? root.cleanCurrent : (root.cleanLatest || root.cleanCurrent)
                        font.family: Theme.fontFamily; font.pixelSize: 44; font.bold: true
                        font.letterSpacing: -2
                        color: Theme.textPrimary
                    }
                    // Accent text beside the version, no capsule. Its first word ("Ê") is set 50% larger than the version
                    Item {
                        id: badge
                        readonly property string label: {
                            switch (root.phase) {
                            case "available":
                            case "planning": return I18n.tr("Ê cập nhật đi bản mới nè!", "Hey, grab the new version!");
                            case "ready": return I18n.tr("Sẵn sàng", "Ready");
                            case "upToDate": return I18n.tr("Mới nhất", "Latest");
                            default: return "";
                            }
                        }
                        readonly property bool exclaim: root.phase === "available" || root.phase === "planning"
                        readonly property int cut: label.indexOf(" ")
                        readonly property string head: (shownExclaim && shown.indexOf(" ") > 0) ? shown.substring(0, shown.indexOf(" ")) : ""
                        readonly property string rest: head !== "" ? shown.substring(shown.indexOf(" ")) : shown
                        property string shown: ""
                        property bool shownExclaim: false
                        visible: opacity > 0.001
                        opacity: 0
                        transform: Translate { id: badgeShift; y: 0 }
                        Component.onCompleted: { shown = label; shownExclaim = exclaim; opacity = label !== "" ? 1 : 0; }
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: 2
                        Layout.preferredWidth: headText.width + restText.implicitWidth
                        Behavior on Layout.preferredWidth { NumberAnimation { duration: 260 * root.motion; easing.type: Easing.OutExpo } }
                        Layout.preferredHeight: headText.implicitHeight
                        onLabelChanged: replay()
                        function replay() { fadeAnim.restart(); }
                        // Out (drift up, fade), swap the words, then in (rise from below, fade), the way Mochy swaps content
                        SequentialAnimation {
                            id: fadeAnim
                            ParallelAnimation {
                                NumberAnimation { target: badge; property: "opacity"; to: 0; duration: 140 * root.motion; easing.type: Easing.OutCubic }
                                NumberAnimation { target: badgeShift; property: "y"; to: -6; duration: 140 * root.motion; easing.type: Easing.OutCubic }
                            }
                            ScriptAction { script: { badge.shown = badge.label; badge.shownExclaim = badge.exclaim; badgeShift.y = 10; } }
                            ParallelAnimation {
                                NumberAnimation { target: badge; property: "opacity"; to: badge.label !== "" ? 1 : 0; duration: 320 * root.motion; easing.type: Easing.OutExpo }
                                NumberAnimation { target: badgeShift; property: "y"; to: 0; duration: 320 * root.motion; easing.type: Easing.OutExpo }
                            }
                        }
                        Text {
                            id: headText
                            visible: badge.head !== ""
                            width: visible ? implicitWidth : 0
                            text: badge.head
                            font.family: Theme.fontFamily; font.pixelSize: 66; font.bold: true
                            font.letterSpacing: -2
                            color: root.accentColor
                        }
                        Text {
                            id: restText
                            anchors.left: headText.right
                            anchors.baseline: headText.baseline
                            text: badge.rest
                            font.family: Theme.fontFamily; font.pixelSize: 14; font.bold: true
                            color: root.accentColor
                        }
                    }
                }
            }

            // Status: the one line to read, then its detail. Fixed height, so nothing below shifts
            ColumnLayout {
                id: statusBlock
                Layout.fillWidth: true
                spacing: 3
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Rectangle {
                        id: waitDot
                        readonly property bool on: root.phase === "checking"
                        Layout.preferredWidth: on ? 8 : 0; Layout.preferredHeight: 8
                        Layout.rightMargin: on ? 8 : 0
                        scale: on ? 1 : 0.3
                        Behavior on Layout.preferredWidth { NumberAnimation { duration: 260 * root.motion; easing.type: Easing.OutExpo } }
                        Behavior on Layout.rightMargin { NumberAnimation { duration: 260 * root.motion; easing.type: Easing.OutExpo } }
                        Behavior on scale { NumberAnimation { duration: 260 * root.motion; easing.type: Easing.OutExpo } }
                        radius: 4
                        color: root.accentColor
                        SequentialAnimation on opacity {
                            running: waitDot.on && root.isOpen && !root.liteMode
                            loops: Animation.Infinite
                            NumberAnimation { from: 1.0; to: 0.25; duration: 650; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 0.25; to: 1.0; duration: 650; easing.type: Easing.InOutSine }
                        }
                    }
                  Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22
                    FadeText {
                        width: parent.width
                        height: 22
                        opacity: root.showSizeRow ? 0 : 1
                        key: root.phase
                        value: root.statusMain
                        motion: root.motion
                        font.family: Theme.fontFamily; font.pixelSize: 16; font.bold: true
                        color: root.phase === "error" ? Qt.rgba(244 / 255, 63 / 255, 94 / 255, 1) : Theme.textPrimary
                        elide: Text.ElideRight
                    }
                    // "Cần tải 40.0 MB, nhẹ hơn 89%": the figure is a slot-machine reel until the real size is known
                    Row {
                        width: parent.width
                        height: 22
                        opacity: root.showSizeRow ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 240 * root.motion; easing.type: Easing.OutExpo } }
                        Text {
                            text: I18n.tr("Cần tải ", "Download ")
                            font.family: Theme.fontFamily; font.pixelSize: 16; font.bold: true
                            color: Theme.textPrimary
                        }
                        // Lite mode has no spinning reels: say it is still counting instead of a frozen 00.0
                        Text {
                            visible: root.liteMode && !root.sizeKnown
                            text: I18n.tr("đang tính...", "calculating...")
                            font.family: Theme.fontFamily; font.pixelSize: 16; font.bold: true
                            color: Theme.textSecondary
                        }
                        Odometer {
                            visible: !(root.liteMode && !root.sizeKnown)
                            text: root.sizeNumber
                            pixelSize: 16
                            color: Theme.textPrimary
                            spinning: !root.sizeKnown
                            down: true
                            liteMode: root.liteMode
                        }
                        Text {
                            visible: !(root.liteMode && !root.sizeKnown)
                            text: " " + root.sizeUnit
                            font.family: Theme.fontFamily; font.pixelSize: 16; font.bold: true
                            color: Theme.textPrimary
                        }
                    }
                  }
                }
                FadeText {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 16
                    motion: root.motion
                    key: root.phase
                    value: root.statusSub
                    font.family: Theme.fontFamily; font.pixelSize: 12
                    color: Theme.textSecondary
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.fillWidth: true
                property real t: root.phase === "downloading" ? 1 : 0
                Behavior on t { NumberAnimation { duration: 320 * root.motion; easing.type: Easing.OutExpo } }
                Layout.preferredHeight: 6 * t
                Layout.topMargin: -14 * (1 - t)
                opacity: t
                radius: 3
                color: Qt.rgba(255, 255, 255, 0.10)
                Rectangle {
                    height: parent.height; radius: 3
                    width: parent.width * Math.max(0.02, Math.min(1.0, root.updateState.progress || 0))
                    color: root.accentColor
                    Behavior on width { NumberAnimation { duration: 160 * root.motion; easing.type: Easing.OutCubic } }
                }
            }

            // Release notes: a quiet heading, then rows separated by space only
            Text {
                Layout.topMargin: 6
                opacity: notes.shown && root.changelogItems.length > 0 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 260 * root.motion; easing.type: Easing.OutExpo } }
                text: I18n.tr("Có gì mới", "What's new")
                font.family: Theme.fontFamily; font.pixelSize: 12; font.bold: true
                color: Theme.textSecondary
            }
            Flickable {
                id: notes
                Layout.fillWidth: true
                Layout.fillHeight: true
                readonly property bool shown: root.phase === "available" || root.phase === "planning" || root.phase === "downloading"
                opacity: shown ? 1 : 0
                visible: opacity > 0.001
                Behavior on opacity { NumberAnimation { duration: 260 * root.motion; easing.type: Easing.OutExpo } }
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
                            id: rowItem
                            required property int index
                            required property var modelData
                            width: notesCol.width
                            // Rows glide in one after another when the list shows
                            property real shown: root.motion === 0 ? 1 : 0
                            readonly property bool go: root.isOpen && notes.visible
                            onGoChanged: if (go && root.motion !== 0) rowAnim.restart()
                            Component.onCompleted: if (go && root.motion !== 0) rowAnim.restart()
                            opacity: shown
                            transform: Translate { y: (1 - rowItem.shown) * 12 }
                            SequentialAnimation {
                                id: rowAnim
                                PropertyAction { target: rowItem; property: "shown"; value: 0 }
                                PauseAnimation { duration: 120 + Math.min(rowItem.index, 8) * 45 }
                                NumberAnimation { target: rowItem; property: "shown"; to: 1; duration: 420; easing.type: Easing.OutExpo }
                            }

                            Text {
                                width: parent.width
                                text: modelData.title
                                font.family: Theme.fontFamily; font.pixelSize: modelData.header ? 12 : 13; font.bold: true
                                color: modelData.header ? root.accentColor : Theme.textPrimary
                                wrapMode: Text.WordWrap
                            }
                            Item { width: 1; height: 2 }
                            Text {
                                width: parent.width
                                visible: modelData.detail !== ""
                                text: modelData.detail
                                font.family: Theme.fontFamily; font.pixelSize: 12
                                color: Theme.textSecondary
                                wrapMode: Text.WordWrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                            }
                            Item { width: 1; height: 16 }
                        }
                    }
                }
            }
            Item { Layout.fillHeight: true; visible: !notes.visible }

            // Actions
            RowLayout {
                id: actionsRow
                Layout.fillWidth: true
                spacing: 0

                // Secondary
                Rectangle {
                    Layout.preferredHeight: 42
                    Layout.preferredWidth: !root.primaryOn ? actionsRow.width : (root.phase === "error" ? 160 : 120)
                    radius: 12
                    color: secHover.hovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                                            : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
                    border.width: 1
                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.32)
                    opacity: root.phase !== "checking" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 240 * root.motion; easing.type: Easing.OutExpo } }
                    Behavior on Layout.preferredWidth { NumberAnimation { duration: 300 * root.motion; easing.type: Easing.OutExpo } }
                    Behavior on color { ColorAnimation { duration: 120 } }
                    HoverHandler { id: secHover }
                    FadeText {
                        anchors.centerIn: parent
                        motion: root.motion
                        value: root.phase === "downloading" ? I18n.tr("Hủy", "Cancel")
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
                    Layout.leftMargin: root.primaryOn ? 10 : 0
                    Layout.preferredWidth: 0
                    Layout.minimumWidth: 0
                    Behavior on Layout.leftMargin { NumberAnimation { duration: 300 * root.motion; easing.type: Easing.OutExpo } }
                    clip: true
                    color: priHover.hovered ? Qt.tint(root.accentColor, Qt.rgba(1, 1, 1, 0.15)) : root.accentColor
                    // Hidden until the size is known, so its label never changes under the cursor
                    opacity: (root.primaryOn && !root.sizePending) ? 1 : 0
                    enabled: root.primaryOn && !root.sizePending
                    Behavior on opacity { NumberAnimation { duration: 200 * root.motion; easing.type: Easing.OutExpo } }
                    Behavior on color { ColorAnimation { duration: 120 } }
                    HoverHandler { id: priHover }
                    FadeText {
                        anchors.centerIn: parent
                        motion: root.motion
                        value: root.phase === "ready" ? I18n.tr("Khởi động lại ngay", "Restart now")
                              : (root.phase === "error" ? I18n.tr("Thử lại", "Try again")
                                 : (root.isDelta && root.shownPlan.download_bytes > 0
                                    ? I18n.tr("Cập nhật · " + root.formatBytes(root.shownPlan.download_bytes), "Update · " + root.formatBytes(root.shownPlan.download_bytes))
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
