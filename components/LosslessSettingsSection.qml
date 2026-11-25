import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "."
import "lossless_logic.js" as LosslessLogic

// Settings > Audio: "Lossless (Tidal)". The user signs in to their own Tidal account on the
// Tidal link page in the browser; Nutsty never sees the password.
// host is the main window (shell.qml): it owns the settings and the explain modal.
ColumnLayout {
    id: root
    spacing: 10

    property var host: null
    property color accentColor: Theme.accent
    property string apiUrl: "http://127.0.0.1:17890"

    readonly property var st: host ? host.tidalStatus : null
    readonly property bool loggedIn: !!(st && st.logged_in)
    readonly property bool canLossless: loggedIn && st.can_lossless !== false
    readonly property bool enabledNow: !!(host && host.losslessEnabled)
    readonly property bool coListening: !!(host && host.isCoListeningActive)
    readonly property bool isWindows: !!(host && host.isWindowsPlatform)

    // Login: "" idle, "starting", "pending" (waiting for the browser), "expired", "error"
    property string loginState: ""
    property string loginCode: ""
    property string loginUrl: ""

    readonly property color roseColor: Qt.rgba(244 / 255, 63 / 255, 94 / 255, 1.0)

    function request(method, path, onDone) {
        var xhr = new XMLHttpRequest();
        // One backend worker serves every profile, so name ours: the Tidal session is per profile.
        var profile = (Quickshell.env("NUTSTY_PROFILE") || "").toLowerCase();
        xhr.open(method, root.apiUrl + path + "?profile=" + encodeURIComponent(profile));
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            var data = null;
            try { data = JSON.parse(xhr.responseText); } catch (e) {}
            onDone(xhr.status === 200 ? data : null);
        };
        if (method === "POST") xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(method === "POST" ? "{}" : null);
    }

    function refreshStatus() {
        request("GET", "/api/tidal/status", function(data) {
            if (data && root.host) root.host.applyTidalStatus(data);
        });
    }

    function startLogin() {
        root.loginState = "starting";
        request("POST", "/api/tidal/login/start", function(data) {
            if (!data || !data.url) { root.loginState = "error"; return; }
            root.loginUrl = data.url;
            root.loginCode = data.code || "";
            root.loginState = "pending";
            if (root.host) root.host.openExternalUrl(data.url);
            pollTimer.restart();
        });
    }

    function cancelLogin() {
        pollTimer.stop();
        root.loginState = "";
    }

    function logout() {
        request("POST", "/api/tidal/logout", function() {
            if (root.host) {
                root.host.tidalStatus = { logged_in: false };
                if (root.host.losslessEnabled) root.host.disableLossless();
            }
        });
    }

    Component.onCompleted: { refreshStatus(); if (rateMatchShown) checkRateDropin(); }

    Timer {
        id: pollTimer
        interval: 2000
        repeat: true
        onTriggered: root.request("GET", "/api/tidal/login/poll", function(data) {
            if (root.loginState !== "pending") return;
            var s = data ? data.state : "error";
            if (s === "pending") return;
            pollTimer.stop();
            if (s === "ok") {
                root.loginState = "";
                root.refreshStatus();
            } else {
                root.loginState = (s === "expired") ? "expired" : "error";
            }
        })
    }

    // --- Header + on/off switch ---------------------------------------------------------
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 46

        Column {
            anchors.left: parent.left
            anchors.right: losslessToggle.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: I18n.tr("Lossless (Tidal)", "Lossless (Tidal)")
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: I18n.tr("Phát FLAC từ tài khoản Tidal của bạn. Bài không có trên Tidal vẫn phát bản YouTube.",
                              "Plays FLAC from your Tidal account. Songs missing on Tidal still play from YouTube.")
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
            }
        }

        Rectangle {
            id: losslessToggle
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 24
            radius: 12
            opacity: root.canLossless || root.enabledNow ? 1.0 : 0.45
            color: root.enabledNow ? root.accentColor : Qt.rgba(1, 1, 1, 0.14)
            Behavior on color { ColorAnimation { duration: 150 } }

            Rectangle {
                width: 18
                height: 18
                radius: 9
                color: "#ffffff"
                anchors.verticalCenter: parent.verticalCenter
                x: root.enabledNow ? parent.width - width - 3 : 3
                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.canLossless || root.enabledNow
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!root.host) return;
                    if (root.enabledNow) root.host.disableLossless();
                    else root.host.openLosslessExplain();
                }
            }
        }
    }

    // --- Account -------------------------------------------------------------------------
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: accountCol.implicitHeight + 4

        Column {
            id: accountCol
            anchors.left: parent.left
            anchors.right: accountBtn.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Text {
                width: parent.width
                text: root.loggedIn
                      ? I18n.tr("Tài khoản Tidal: " + (root.st.account || "") + (root.st.subscription ? " · " + root.st.subscription : ""),
                                "Tidal account: " + (root.st.account || "") + (root.st.subscription ? " · " + root.st.subscription : ""))
                      : (root.loginState === "pending"
                         ? I18n.tr("Mã xác nhận: " + root.loginCode, "Confirmation code: " + root.loginCode)
                         : I18n.tr("Chưa đăng nhập Tidal", "Not signed in to Tidal"))
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.bold: root.loggedIn || root.loginState === "pending"
                color: Theme.textPrimary
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: text !== ""
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: (root.loginState === "error" || root.loginState === "expired" || (root.loggedIn && (root.st.needs_relogin || !root.canLossless)))
                       ? root.roseColor : Theme.textSecondary
                text: {
                    if (root.loginState === "starting") return I18n.tr("Đang mở trang đăng nhập Tidal...", "Opening the Tidal sign-in page...");
                    if (root.loginState === "pending") return I18n.tr("Đang chờ xác nhận trên trình duyệt...", "Waiting for confirmation in the browser...");
                    if (root.loginState === "expired") return I18n.tr("Mã đã hết hạn. Bấm Đăng nhập Tidal để lấy mã mới.", "The code expired. Press Sign in to Tidal for a new one.");
                    if (root.loginState === "error") return I18n.tr("Không kết nối được Tidal. Thử lại sau.", "Could not reach Tidal. Try again later.");
                    if (root.loggedIn && root.st.needs_relogin) return I18n.tr("Phiên Tidal đã hết hạn, đang phát bản YouTube. Hãy đăng nhập lại.", "Your Tidal session expired, so songs play from YouTube. Please sign in again.");
                    if (root.loggedIn && !root.canLossless) return I18n.tr("Gói Tidal của bạn không có lossless, nên không bật được.", "Your Tidal plan has no lossless, so this cannot be turned on.");
                    if (root.enabledNow && root.coListening) return I18n.tr("Tạm tắt lossless khi Nghe Cùng", "Lossless is paused while Listening Along");
                    if (!root.loggedIn) return I18n.tr("Đăng nhập bằng tài khoản Tidal của chính bạn trên trình duyệt.", "Sign in with your own Tidal account in the browser.");
                    return "";
                }
            }
        }

        Rectangle {
            id: accountBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 28
            width: accountBtnText.implicitWidth + 24
            radius: 8
            readonly property bool danger: root.loggedIn && !root.st.needs_relogin
            readonly property color tone: danger ? root.roseColor : root.accentColor
            color: Qt.rgba(tone.r, tone.g, tone.b, accountBtnMouse.containsMouse ? 0.22 : 0.12)
            border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.35)
            border.width: 1
            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
                id: accountBtnText
                anchors.centerIn: parent
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.bold: true
                color: "#ffffff"
                text: root.loginState === "pending" ? I18n.tr("Hủy", "Cancel")
                      : (accountBtn.danger ? I18n.tr("Đăng xuất", "Sign out")
                         : (root.loggedIn ? I18n.tr("Đăng nhập lại", "Sign in again") : I18n.tr("Đăng nhập Tidal", "Sign in to Tidal")))
            }

            MouseArea {
                id: accountBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: root.loginState !== "starting"
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.loginState === "pending") root.cancelLogin();
                    else if (accountBtn.danger) root.logout();
                    else root.startLogin();
                }
            }
        }
    }

    // --- Quality and DAC mode (only once lossless is on) ---------------------------------
    component ChoiceRow: Item {
        id: choiceRow
        property string title: ""
        property string subtitle: ""
        property var options: []        // [{key, label}]
        property string current: ""
        signal picked(string key)
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(choiceText.implicitHeight, 30) + 6

        Column {
            id: choiceText
            anchors.left: parent.left
            anchors.right: choicePills.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                width: parent.width
                text: choiceRow.title
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.bold: true
                color: Theme.textPrimary
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: text !== ""
                text: choiceRow.subtitle
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
            }
        }

        Row {
            id: choicePills
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Repeater {
                model: choiceRow.options
                delegate: Rectangle {
                    readonly property bool active: choiceRow.current === modelData.key
                    height: 28
                    width: pillText.implicitWidth + 20
                    radius: 8
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b,
                                   active ? 0.30 : (pillMouse.containsMouse ? 0.16 : 0.08))
                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, active ? 0.55 : 0.20)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        id: pillText
                        anchors.centerIn: parent
                        text: modelData.label
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.bold: parent.active
                        color: "#ffffff"
                    }
                    MouseArea {
                        id: pillMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: choiceRow.picked(modelData.key)
                    }
                }
            }
        }
    }

    ChoiceRow {
        visible: root.enabledNow && root.loggedIn
        title: I18n.tr("Chất lượng lossless", "Lossless quality")
        subtitle: I18n.tr("HiRes tới 24-bit/192 kHz nếu gói Tidal có", "HiRes up to 24-bit/192 kHz when your Tidal plan has it")
        current: LosslessLogic.effectiveQuality(root.host ? root.host.losslessQuality : "lossless", root.st)
        options: {
            var o = [{ key: "lossless", label: I18n.tr("FLAC 16-bit", "FLAC 16-bit") }];
            if (root.st && root.st.can_hires) o.push({ key: "hires", label: I18n.tr("HiRes 24-bit", "HiRes 24-bit") });
            return o;
        }
        onPicked: key => { if (root.host) root.host.setLosslessQuality(key); }
    }

    // Not tied to Tidal: local FLAC goes to the DAC the same way.
    ChoiceRow {
        title: I18n.tr("Đưa âm thanh tới DAC", "DAC output")
        subtitle: root.host && root.host.dacOutputMode === "exclusive"
                  ? I18n.tr("AutoMix tắt, âm lượng trong app cố định 100%", "AutoMix off, in-app volume fixed at 100%")
                  : ""
        current: root.host ? root.host.dacOutputMode : "shared"
        options: {
            var labels = {
                shared: I18n.tr("Qua hệ thống", "Through the system"),
                rate_match: I18n.tr("Đúng tần số gốc", "Original sample rate"),
                exclusive: I18n.tr("Nguyên bản tuyệt đối", "Fully bit-perfect")
            };
            return LosslessLogic.dacModesFor(root.isWindows).map(function(k) { return { key: k, label: labels[k] }; });
        }
        onPicked: key => {
            if (!root.host) return;
            root.host.setDacOutputMode(key);
            if (key === "rate_match") root.checkRateDropin();
        }
    }

    // --- Original sample rate (Linux): PipeWire may only switch rates it is allowed to ---------
    // Nutsty writes its own drop-in file only after the user agrees, never edits another file and
    // never restarts PipeWire by itself.
    readonly property bool rateMatchShown: !root.isWindows && !!root.host && root.host.dacOutputMode === "rate_match"
    property var dropin: null           // last `rate_dropin check|write` result
    property string dropinState: ""     // "", "ask", "conflict", "written", "removed"

    onRateMatchShownChanged: if (rateMatchShown && !dropin) checkRateDropin()

    function runDropin(action) {
        if (dropinProc.running || !root.host) return;
        dropinProc.action = action;
        dropinProc.command = ["python3", "-u", root.host.appDir + "/backend/player_daemon.py", "rate_dropin", action];
        dropinProc.running = true;
    }
    function checkRateDropin() { runDropin("check"); }

    Process {
        id: dropinProc
        property string action: ""
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                var res = null;
                try { res = JSON.parse(data); } catch (e) { return; }
                if (dropinProc.action === "check") {
                    root.dropin = res;
                    root.dropinState = res.installed ? "" : (res.conflicts && res.conflicts.length ? "conflict" : "ask");
                } else if (dropinProc.action === "write") {
                    root.dropin = res;
                    root.dropinState = res.written ? "written" : "conflict";
                } else if (dropinProc.action === "remove") {
                    root.dropin = { installed: false, conflicts: [] };
                    root.dropinState = "removed";
                }
            }
        }
    }

    Rectangle {
        visible: root.rateMatchShown && root.dropin !== null
        Layout.fillWidth: true
        Layout.preferredHeight: dropinCol.implicitHeight + 24
        radius: 12
        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.08)
        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
        border.width: 1

        ColumnLayout {
            id: dropinCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 8

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.textSecondary
                text: {
                    var path = root.dropin && root.dropin.path ? root.dropin.path : "";
                    if (root.dropinState === "ask")
                        return I18n.tr("Để PipeWire đổi theo tần số của từng bài, Nutsty cần thêm một file cấu hình nhỏ: " + path + ". Nutsty không sửa file nào khác và không tự khởi động lại PipeWire.",
                                       "To let PipeWire follow each song's sample rate, Nutsty needs to add one small config file: " + path + ". Nutsty changes no other file and does not restart PipeWire by itself.");
                    if (root.dropinState === "conflict") {
                        var lines = (root.dropin.conflicts || []).map(function(c) { return c[0] + ": " + c[1]; }).join("\n");
                        return I18n.tr("Máy đã có cấu hình tần số riêng nên Nutsty không ghi thêm. Hãy thêm 44100 88200 176400 vào dòng này nếu thiếu:\n" + lines,
                                       "Your system already sets its own sample rates, so Nutsty writes nothing. Add 44100 88200 176400 to this line if they are missing:\n" + lines);
                    }
                    if (root.dropinState === "written")
                        return I18n.tr("Đã ghi cấu hình. Chạy lệnh systemctl --user restart pipewire hoặc đăng xuất rồi đăng nhập lại để áp dụng.",
                                       "Config written. Run systemctl --user restart pipewire, or log out and back in, to apply it.");
                    if (root.dropinState === "removed")
                        return I18n.tr("Đã gỡ cấu hình. Khởi động lại PipeWire hoặc đăng xuất để trở lại như cũ.",
                                       "Config removed. Restart PipeWire or log out to go back to how it was.");
                    return I18n.tr("Cấu hình tần số của Nutsty đã có: " + path, "Nutsty's sample rate config is in place: " + path);
                }
            }

            Row {
                spacing: 8
                LosslessSmallButton {
                    accentColor: root.accentColor
                    roseColor: root.roseColor
                    visible: root.dropinState === "ask"
                    primary: true
                    label: I18n.tr("Ghi cấu hình", "Write config")
                    onClicked: root.runDropin("write")
                }
                LosslessSmallButton {
                    accentColor: root.accentColor
                    roseColor: root.roseColor
                    visible: root.dropinState === "ask"
                    label: I18n.tr("Để sau", "Later")
                    onClicked: { root.dropin = null; root.dropinState = ""; }
                }
                LosslessSmallButton {
                    accentColor: root.accentColor
                    roseColor: root.roseColor
                    visible: root.dropinState === "written" || (root.dropinState === "" && !!root.dropin && root.dropin.installed)
                    danger: true
                    label: I18n.tr("Gỡ cấu hình", "Remove config")
                    onClicked: root.runDropin("remove")
                }
            }
        }
    }
}
