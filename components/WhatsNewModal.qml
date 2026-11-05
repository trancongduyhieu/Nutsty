import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "."

Item {
    id: root
    anchors.fill: parent
    enabled: isOpen || closingGuard
    visible: opacity > 0 || closingGuard
    opacity: isOpen ? 1 : 0
    z: 9998

    Behavior on opacity {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    property bool isOpen: false
    property bool closingGuard: false
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent
    property Item backgroundSourceItem: null
    property string versionString: (typeof win !== "undefined" && win.appVersion) ? win.appVersion : "1.0.7"
    property string customReleaseNotes: ""
    property var changelogItems: []

    signal closeRequested()

    FileView {
        id: changelogFileView
        path: {
            var dir = (typeof win !== "undefined" && win.appDir) ? win.appDir : (Quickshell.env("HOME") + "/Applications/FrostifyLocal");
            return dir + "/CHANGELOG.md";
        }
        watchChanges: true
        onFileChanged: {
            this.reload();
            root.refreshChangelog();
        }
        onLoadedChanged: {
            if (this.loaded) root.refreshChangelog();
        }
        Component.onCompleted: {
            if (this.loaded) root.refreshChangelog();
        }
    }

    function parseChangelogText(rawText, targetVer) {
        if (!rawText || typeof rawText !== "string") return [];
        var lines = rawText.split(/\r?\n/);
        var targetNorm = String(targetVer || "").replace(/^[vV]/, "").trim();

        var hasHeadings = lines.some(function(l) {
            return /^##\s+\[?v?[\d\.]+/.test(l.trim());
        });
        var extractedLines = [];

        if (hasHeadings) {
            var capturing = false;
            var foundAny = false;
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i].trim();
                var hMatch = line.match(/^##\s+\[?v?([0-9\.\-_a-zA-Z]+)\]?/);
                if (hMatch) {
                    var ver = hMatch[1].replace(/^[vV]/, "").trim();
                    if (targetNorm && ver.indexOf(targetNorm) === 0) {
                        capturing = true;
                        foundAny = true;
                        continue;
                    } else if (capturing) {
                        break;
                    }
                } else if (capturing) {
                    extractedLines.push(lines[i]);
                }
            }
            if (!foundAny) {
                capturing = false;
                for (var j = 0; j < lines.length; j++) {
                    var l2 = lines[j].trim();
                    if (/^##\s+\[?v?[0-9]/.test(l2)) {
                        if (!capturing) {
                            capturing = true;
                            continue;
                        } else {
                            break;
                        }
                    } else if (capturing) {
                        extractedLines.push(lines[j]);
                    }
                }
            }
        } else {
            extractedLines = lines;
        }

        var items = [];
        for (var k = 0; k < extractedLines.length; k++) {
            var rawL = extractedLines[k].trim();
            if (!rawL || rawL.startsWith("#") || rawL.startsWith("---")) continue;
            // Ignore installation instructions or step-by-step download guides
            if (/^[-*•]?\s*\**bước\s*\d+/i.test(rawL)) continue;
            if (/^[-*•]\s+/.test(rawL)) {
                var content = rawL.replace(/^[-*•]\s+/, "").trim();
                var title = "";
                var detail = "";

                var boldMatch = content.match(/^\*\*([^*]+)\*\*[:\s\-—]+(.*)$/);
                if (boldMatch) {
                    title = boldMatch[1].trim();
                    detail = boldMatch[2].trim();
                } else {
                    var colonIdx = content.indexOf(":");
                    if (colonIdx > 0 && colonIdx < 60) {
                        title = content.substring(0, colonIdx).replace(/\*\*/g, "").trim();
                        detail = content.substring(colonIdx + 1).trim();
                    } else {
                        title = content.replace(/\*\*/g, "").trim();
                        detail = "";
                    }
                }
                if (title) {
                    items.push({ "title": title, "detail": detail });
                }
            }
        }
        return items;
    }

    function refreshChangelog() {
        var items = [];
        if (root.customReleaseNotes && root.customReleaseNotes.trim() !== "") {
            items = parseChangelogText(root.customReleaseNotes, root.versionString);
        }
        if ((!items || items.length === 0) && changelogFileView.loaded && changelogFileView.text()) {
            items = parseChangelogText(changelogFileView.text(), root.versionString);
        }
        if (!items || items.length === 0) {
            // Graceful fallback
            items = [
                {
                    "title": I18n.tr("Cải tiến và tối ưu hóa hiệu năng", "Performance improvements & stability"),
                    "detail": I18n.tr("Cập nhật phiên bản mới nhất với các tính năng cải tiến và sửa lỗi hệ thống.", "Latest release with general improvements and bug fixes.")
                }
            ];
        }
        root.changelogItems = items;
    }

    onCustomReleaseNotesChanged: refreshChangelog()
    onVersionStringChanged: refreshChangelog()
    Component.onCompleted: refreshChangelog()

    function openModal(notes) {
        closeTimer.stop();
        closingGuard = false;
        if (notes && typeof notes === "string") {
            root.customReleaseNotes = notes;
        } else {
            root.customReleaseNotes = "";
        }
        root.refreshChangelog();
        root.isOpen = true;
    }

    function closeModal() {
        if (!root.isOpen && !root.closingGuard) return;
        root.isOpen = false;
        root.closingGuard = true;
        closeTimer.restart();
        root.closeRequested();
    }

    Timer {
        id: closeTimer
        interval: 200
        repeat: false
        onTriggered: root.closingGuard = false
    }

    // Dismiss Backdrop
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.58)

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeModal()
        }
    }

    // Modal Main Floating Card: LiquidGlass Resin Container (Planar Minimalist - Clean White Space)
    LiquidGlass {
        id: dialog
        width: Math.min(480, parent.width - 32)
        height: Math.min(560, parent.height - 48)
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
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

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

        // Intercept clicks inside dialog
        MouseArea {
            anchors.fill: parent
            z: 2
            onClicked: mouse => { mouse.accepted = true; }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 12
            z: 5

            // =================================================================
            // Header Row: Title + Version Badge & Close Button (SettingsModal Parity)
            // =================================================================
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32

                RowLayout {
                    spacing: 8
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        text: I18n.tr("Điểm mới", "What's New")
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    // Version Tag Badge
                    Rectangle {
                        height: 18
                        width: verTagTxt.implicitWidth + 10
                        radius: 4
                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                        border.width: 1
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.40)

                        Text {
                            id: verTagTxt
                            anchors.centerIn: parent
                            text: "v" + (root.versionString || "1.0.7")
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: true
                            color: root.accentColor
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Close Button Circle (Exact SettingsModal Parity)
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
                        onClicked: root.closeModal()
                    }
                }
            }

            // Subtitle
            Text {
                text: I18n.tr("Phiên bản v" + root.versionString + " bao gồm các tính năng và cải tiến sau:", "Version v" + root.versionString + " includes the following highlights:")
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.textSecondary
            }

            // =================================================================
            // Body: Dynamic Planar List from CHANGELOG.md (Clean whitespace, no borders)
            // =================================================================
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Flickable {
                    id: flick
                    anchors.fill: parent
                    contentHeight: contentCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    ScrollBar.vertical: LiquidScrollBar {}

                    ColumnLayout {
                        id: contentCol
                        width: flick.width
                        spacing: 14

                        Repeater {
                            model: root.changelogItems
                            delegate: ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                RowLayout {
                                    spacing: 8
                                    Layout.fillWidth: true

                                    Rectangle {
                                        width: 6
                                        height: 6
                                        radius: 3
                                        color: root.accentColor
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.title || ""
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: Theme.textPrimary
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.detail || ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.textSecondary
                                    wrapMode: Text.WordWrap
                                    Layout.leftMargin: 14
                                    visible: !!modelData.detail && modelData.detail.trim() !== ""
                                }
                            }
                        }
                    }
                }
            }

            // =================================================================
            // Footer: Clean Action Button (Exact SettingsModal Parity)
            // =================================================================
            RowLayout {
                Layout.fillWidth: true

                Item { Layout.fillWidth: true }

                Rectangle {
                    height: 28
                    width: btnText.implicitWidth + 24
                    radius: 6
                    color: btnMouse.containsMouse
                           ? Qt.tint(root.accentColor, Qt.rgba(1, 1, 1, 0.15))
                           : root.accentColor
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        id: btnText
                        anchors.centerIn: parent
                        text: I18n.tr("Đã hiểu", "Got it")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                        color: "#000000"
                    }

                    MouseArea {
                        id: btnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeModal()
                    }
                }
            }
        }
    }
}
