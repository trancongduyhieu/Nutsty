import QtQuick
import QtQuick.Layouts
import "."

// Settings > Account, under the Spotify account row: two-way sync with the user's own Spotify library.
// `sync` is the SpotifySync object of shell.qml. Shown only while a Spotify cookie is saved.
ColumnLayout {
    id: root
    spacing: 10

    property var sync: null
    property color accentColor: Theme.accent
    readonly property color roseColor: Qt.rgba(244 / 255, 63 / 255, 94 / 255, 1.0)

    readonly property bool on: !!(sync && sync.enabled && sync.selectionConfirmed)
    property bool pickerOpen: false
    // Spotify id -> checked, edited in the picker before it is confirmed
    property var picked: ({})
    property bool likedPicked: true

    function openPicker() {
        if (!root.sync) return;
        root.pickerOpen = true;
        root.sync.loadChoices();
    }

    function errorText(code) {
        if (code === "auth_expired") return I18n.tr("Phiên Spotify đã hết hạn. Hãy đăng nhập Spotify lại.", "Your Spotify session expired. Sign in to Spotify again.");
        if (code === "rate_limited") return I18n.tr("Spotify đang giới hạn, sẽ thử lại sau.", "Spotify is rate limiting, will retry later.");
        if (code === "query_changed") return I18n.tr("Spotify vừa thay đổi, cần cập nhật Nutsty.", "Spotify changed something, Nutsty needs an update.");
        if (code === "") return "";
        return I18n.tr("Không kết nối được Spotify.", "Could not reach Spotify.");
    }

    function blockedName(pid) {
        if (pid === "liked") return I18n.tr("Bài hát đã thích", "Liked Songs");
        var n = root.sync && root.sync.blockedNames ? root.sync.blockedNames[pid] : "";
        return n || I18n.tr("Một playlist", "A playlist");
    }

    // Seed the checkboxes from what the backend proposes each time the list arrives
    Connections {
        target: root.sync
        function onChoicesChanged() {
            var m = {};
            var list = root.sync.choices || [];
            for (var i = 0; i < list.length; i++) m[list[i].id] = !!list[i].selected;
            root.picked = m;
            root.likedPicked = root.sync.likedChoice;
        }
    }

    // --- Header + on/off switch ---------------------------------------------------------
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(46, headerCol.implicitHeight + 8)

        Column {
            id: headerCol
            anchors.left: parent.left
            anchors.right: syncToggle.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: I18n.tr("Tự cập nhật từ Spotify", "Auto-update from Spotify")
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: I18n.tr("Chỉ nên bật trên một máy. Các máy khác nhận qua đồng bộ tài khoản.",
                              "Turn this on for one device only. Your other devices get the changes through account sync.")
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
            }
        }

        Rectangle {
            id: syncToggle
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 24
            radius: 12
            readonly property bool lit: root.on || root.pickerOpen
            color: lit ? root.accentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
            border.width: 1
            Behavior on color { ColorAnimation { duration: 150 } }

            Rectangle {
                width: 18
                height: 18
                radius: 9
                color: "#ffffff"
                anchors.verticalCenter: parent.verticalCenter
                x: syncToggle.lit ? parent.width - width - 3 : 3
                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!root.sync) return;
                    if (root.pickerOpen) { root.pickerOpen = false; return; }
                    if (root.on) root.sync.setEnabled(false);
                    else if (root.sync.selectionConfirmed) root.sync.setEnabled(true);
                    else root.openPicker();
                }
            }
        }
    }

    // --- Playlist picker -------------------------------------------------------------------
    Rectangle {
        Layout.fillWidth: true
        visible: root.pickerOpen
        implicitHeight: pickerCol.implicitHeight + 24
        radius: 12
        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.08)
        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25)
        border.width: 1

        ColumnLayout {
            id: pickerCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: I18n.tr("Chọn playlist để đồng bộ", "Choose playlists to sync")
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
            }

            Text {
                Layout.fillWidth: true
                visible: root.sync && (root.sync.choicesLoading || root.sync.choicesError !== "")
                text: !root.sync ? "" : (root.sync.choicesLoading
                      ? I18n.tr("Đang tải danh sách playlist...", "Loading playlists...")
                      : root.errorText(root.sync.choicesError))
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: root.sync && root.sync.choicesError !== "" ? "#fda4af" : Theme.textSecondary
                wrapMode: Text.WordWrap
            }

            SpotifyChoiceRow {
                Layout.fillWidth: true
                visible: root.sync && !root.sync.choicesLoading
                accentColor: root.accentColor
                title: I18n.tr("Bài hát đã thích", "Liked Songs")
                checked: root.likedPicked
                onToggled: root.likedPicked = !root.likedPicked
            }

            Repeater {
                model: root.sync && !root.sync.choicesLoading ? root.sync.choices : []
                delegate: SpotifyChoiceRow {
                    required property var modelData
                    Layout.fillWidth: true
                    accentColor: root.accentColor
                    title: modelData.title || ""
                    hint: modelData.spotifyMade ? I18n.tr("Spotify tự tạo, thay mới mỗi lần", "Made by Spotify, replaced each time") : ""
                    checked: !!root.picked[modelData.id]
                    onToggled: {
                        var m = Object.assign({}, root.picked);
                        m[modelData.id] = !m[modelData.id];
                        root.picked = m;
                    }
                }
            }

            Row {
                Layout.alignment: Qt.AlignRight
                Layout.topMargin: 4
                spacing: 8

                LosslessSmallButton {
                    label: I18n.tr("Hủy", "Cancel")
                    accentColor: root.accentColor
                    onClicked: root.pickerOpen = false
                }

                LosslessSmallButton {
                    label: I18n.tr("Bắt đầu đồng bộ", "Start syncing")
                    primary: true
                    accentColor: root.accentColor
                    opacity: root.sync && !root.sync.choicesLoading && root.sync.choicesError === "" ? 1.0 : 0.45
                    onClicked: {
                        if (!root.sync || root.sync.choicesLoading || root.sync.choicesError !== "") return;
                        var ids = [];
                        for (var k in root.picked) if (root.picked[k]) ids.push(k);
                        root.sync.confirmSelection(ids, root.likedPicked);
                        root.pickerOpen = false;
                    }
                }
            }
        }
    }

    // --- Status + sync now --------------------------------------------------------------------
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(32, statusCol.implicitHeight)
        visible: root.on && !root.pickerOpen

        Column {
            id: statusCol
            anchors.left: parent.left
            anchors.right: statusButtons.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Text {
                width: parent.width
                text: !root.sync ? "" : (root.sync.lastSync > 0
                      ? I18n.tr("Đồng bộ lần cuối lúc %1", "Last synced at %1").arg(Qt.formatDateTime(new Date(root.sync.lastSync * 1000), "HH:mm dd/MM"))
                      : I18n.tr("Chưa đồng bộ lần nào", "Not synced yet"))
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.textPrimary
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: root.sync && root.sync.unmatched > 0
                text: root.sync ? I18n.tr("%1 bài chưa tìm được bản trên YouTube", "%1 songs not found on YouTube yet").arg(root.sync.unmatched) : ""
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: root.sync ? root.errorText(root.sync.lastError) : ""
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: "#fda4af"
                wrapMode: Text.WordWrap
            }
        }

        Row {
            id: statusButtons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            LosslessSmallButton {
                label: I18n.tr("Chọn playlist", "Choose playlists")
                accentColor: root.accentColor
                onClicked: root.openPicker()
            }

            LosslessSmallButton {
                label: root.sync && root.sync.running ? I18n.tr("Đang đồng bộ...", "Syncing...") : I18n.tr("Đồng bộ ngay", "Sync now")
                primary: true
                accentColor: root.accentColor
                opacity: root.sync && root.sync.running ? 0.6 : 1.0
                onClicked: if (root.sync) root.sync.run()
            }
        }
    }

    // --- Lists held back by the mass-delete guard -------------------------------------------
    Repeater {
        model: root.on && !root.pickerOpen && root.sync ? root.sync.blocked : []
        delegate: Item {
            required property var modelData
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(32, blockedText.implicitHeight)

            Text {
                id: blockedText
                anchors.left: parent.left
                anchors.right: applyBtn.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("%1 định xóa nhiều bài, đã tạm dừng", "%1 would remove many songs, paused").arg(root.blockedName(modelData))
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: "#fda4af"
                wrapMode: Text.WordWrap
            }

            LosslessSmallButton {
                id: applyBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: I18n.tr("Vẫn áp dụng", "Apply anyway")
                danger: true
                onClicked: if (root.sync) root.sync.forceApply(modelData)
            }
        }
    }
}
