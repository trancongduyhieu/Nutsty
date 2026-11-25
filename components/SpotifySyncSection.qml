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

    // The cover stack needs the playlist list once per session while sync is on
    function loadStackOnce() {
        if (root.on && root.sync && (root.sync.choices || []).length === 0 && !root.sync.choicesLoading) root.sync.loadChoices();
    }
    onOnChanged: loadStackOnce()
    Component.onCompleted: loadStackOnce()

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

    // --- Playlist picker: covers in a two-column grid, no box around it ---------------------
    ColumnLayout {
        id: picker
        Layout.fillWidth: true
        Layout.topMargin: 4
        visible: root.pickerOpen
        spacing: 12

        readonly property bool loading: !!(root.sync && root.sync.choicesLoading)
        readonly property string err: root.sync ? root.sync.choicesError : ""
        readonly property int pickedCount: {
            var n = root.likedPicked ? 1 : 0;
            for (var k in root.picked) if (root.picked[k]) n++;
            return n;
        }
        readonly property int totalCount: 1 + (root.sync && root.sync.choices ? root.sync.choices.length : 0)

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                Layout.fillWidth: true
                text: I18n.tr("Chọn playlist để đồng bộ", "Choose playlists to sync")
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
                color: Theme.textPrimary
                elide: Text.ElideRight
            }

            Text {
                visible: !picker.loading && picker.err === ""
                text: I18n.tr("Đã chọn %1/%2", "%1 of %2 selected").arg(picker.pickedCount).arg(picker.totalCount)
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.textSecondary
            }

            Text {
                id: toggleAllText
                visible: !picker.loading && picker.err === ""
                readonly property bool all: picker.pickedCount === picker.totalCount
                text: all ? I18n.tr("Bỏ chọn hết", "Clear all") : I18n.tr("Chọn hết", "Select all")
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: toggleAllMouse.containsMouse ? Qt.lighter(root.accentColor, 1.25) : root.accentColor
                MouseArea {
                    id: toggleAllMouse
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var on = !toggleAllText.all;
                        var m = {};
                        var list = root.sync ? (root.sync.choices || []) : [];
                        for (var i = 0; i < list.length; i++) m[list[i].id] = on;
                        root.picked = m;
                        root.likedPicked = on;
                    }
                }
            }
        }

        // Loading or error line
        RowLayout {
            Layout.fillWidth: true
            visible: picker.loading || picker.err !== ""
            spacing: 10

            CircularSpinner {
                visible: picker.loading
                size: 16
                strokeWidth: 2
                color: root.accentColor
                running: picker.loading
            }

            Text {
                Layout.fillWidth: true
                text: picker.loading ? I18n.tr("Đang lấy playlist từ Spotify...", "Getting your playlists from Spotify...")
                                     : root.errorText(picker.err)
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: picker.err !== "" ? "#fda4af" : Theme.textSecondary
                wrapMode: Text.WordWrap
            }
        }

        GridLayout {
            id: grid
            Layout.fillWidth: true
            visible: !picker.loading && picker.err === ""
            // As many 120px-plus covers as fit, never fewer than three
            columns: Math.max(3, Math.floor((width + columnSpacing) / (120 + columnSpacing)))
            columnSpacing: 16
            rowSpacing: 20

            SpotifyChoiceTile {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                accentColor: root.accentColor
                likedTile: true
                title: I18n.tr("Bài hát đã thích", "Liked Songs")
                subtitle: I18n.tr("Thư viện của bạn", "Your library")
                checked: root.likedPicked
                onToggled: root.likedPicked = !root.likedPicked
            }

            Repeater {
                model: grid.visible && root.sync ? root.sync.choices : []
                delegate: SpotifyChoiceTile {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    accentColor: root.accentColor
                    title: modelData.title || ""
                    cover: modelData.image || ""
                    subtitle: modelData.spotifyMade
                              ? I18n.tr("Spotify tự tạo, thay mới mỗi lần", "Made by Spotify, replaced each time")
                              : (modelData.owned ? I18n.tr("Của bạn", "Yours")
                                                 : I18n.tr("Của %1", "By %1").arg(modelData.ownerName || "Spotify"))
                    checked: !!root.picked[modelData.id]
                    onToggled: {
                        var m = Object.assign({}, root.picked);
                        m[modelData.id] = !m[modelData.id];
                        root.picked = m;
                    }
                }
            }
        }

        Row {
            Layout.alignment: Qt.AlignRight
            spacing: 8

            LosslessSmallButton {
                label: I18n.tr("Hủy", "Cancel")
                accentColor: root.accentColor
                onClicked: root.pickerOpen = false
            }

            LosslessSmallButton {
                readonly property bool ready: !picker.loading && picker.err === "" && picker.pickedCount > 0
                label: I18n.tr("Bắt đầu đồng bộ", "Start syncing")
                primary: true
                accentColor: root.accentColor
                opacity: ready ? 1.0 : 0.45
                onClicked: {
                    if (!ready) return;
                    var ids = [];
                    for (var k in root.picked) if (root.picked[k]) ids.push(k);
                    root.sync.confirmSelection(ids, root.likedPicked);
                    root.pickerOpen = false;
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

            // What is being kept in step, as a stack of small covers
            Row {
                id: coverStack
                visible: syncedRepeater.count > 0 || (root.sync && root.sync.likedChoice)
                bottomPadding: 8
                spacing: -8
                readonly property var synced: {
                    var list = root.sync ? (root.sync.choices || []) : [];
                    var out = [];
                    for (var i = 0; i < list.length; i++) if (list[i].selected) out.push(list[i]);
                    return out;
                }

                Rectangle {
                    visible: !!(root.sync && root.sync.likedChoice)
                    width: 30
                    height: 30
                    radius: 6
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.18)
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.lighter(root.accentColor, 1.35) }
                        GradientStop { position: 1.0; color: Qt.darker(root.accentColor, 1.9) }
                    }
                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/emblem-favorite-symbolic.svg"
                        iconSize: 13
                        color: "#ffffff"
                    }
                }

                Repeater {
                    id: syncedRepeater
                    model: coverStack.synced.slice(0, 6)
                    delegate: RoundedImage {
                        required property var modelData
                        width: 30
                        height: 30
                        radius: 6
                        source: modelData.image || ""
                        sourceSize: Qt.size(60, 60)
                        initialsText: modelData.title || ""
                        fallbackIcon: "../assets/icons/media-playlist-consecutive-symbolic.svg"
                        fallbackIconColor: root.accentColor
                        borderColor: Qt.rgba(1, 1, 1, 0.18)
                        borderWidth: 1
                    }
                }

                Text {
                    visible: coverStack.synced.length > 6
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: 16
                    text: "+" + (coverStack.synced.length - 6)
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: Theme.textSecondary
                }
            }

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
