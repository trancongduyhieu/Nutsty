import QtQuick
import QtQuick.Layouts
import "."

// Settings > Account, under the Spotify account row: two-way sync with the user's own Spotify library.
// `sync` is the SpotifySync object of shell.qml. Shown only while a Spotify cookie is saved.
// Mochy's setting-card anatomy (DESIGN.md "Setting Card"): one card per setting, switch top-right,
// the value in large type bottom-left, a preview of the effect on the right, options as sub-cards.
ColumnLayout {
    id: root
    spacing: 12

    property var sync: null
    property color accentColor: Theme.accent

    readonly property bool on: !!(sync && sync.enabled && sync.selectionConfirmed)
    property bool pickerOpen: false
    // Spotify id -> checked, edited in the picker before it is confirmed
    property var picked: ({})
    property bool likedPicked: true

    readonly property bool choicesLoading: !!(sync && sync.choicesLoading)
    readonly property string choicesErr: sync ? sync.choicesError : ""
    readonly property int pickedCount: {
        var n = root.likedPicked ? 1 : 0;
        for (var k in root.picked) if (root.picked[k]) n++;
        return n;
    }
    readonly property int totalCount: 1 + (sync && sync.choices ? sync.choices.length : 0)
    readonly property var synced: {
        var list = sync ? (sync.choices || []) : [];
        var out = [];
        for (var i = 0; i < list.length; i++) if (list[i].selected) out.push(list[i]);
        return out;
    }
    readonly property bool likedSynced: !!(sync && sync.likedChoice)
    readonly property int syncedCount: synced.length + (likedSynced ? 1 : 0)

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

    function ownerText(item) {
        if (item.spotifyMade) return I18n.tr("Spotify tự tạo, thay mới mỗi lần", "Made by Spotify, replaced each time");
        if (item.owned) return I18n.tr("Của bạn", "Yours");
        return I18n.tr("Của %1", "By %1").arg(item.ownerName || "Spotify");
    }

    function toggleSync() {
        if (!root.sync) return;
        if (root.pickerOpen) { root.pickerOpen = false; return; }
        if (root.on) root.sync.setEnabled(false);
        else if (root.sync.selectionConfirmed) root.sync.setEnabled(true);
        else root.openPicker();
    }

    function setAll(on) {
        var m = {};
        var list = root.sync ? (root.sync.choices || []) : [];
        for (var i = 0; i < list.length; i++) m[list[i].id] = on;
        root.picked = m;
        root.likedPicked = on;
    }

    function confirm() {
        if (!root.sync || root.pickedCount === 0) return;
        var ids = [];
        for (var k in root.picked) if (root.picked[k]) ids.push(k);
        root.sync.confirmSelection(ids, root.likedPicked);
        root.pickerOpen = false;
    }

    // The cover fan needs the playlist list once per session while sync is on
    function loadStackOnce() {
        if (root.on && root.sync && (root.sync.choices || []).length === 0 && !root.sync.choicesLoading) root.sync.loadChoices();
    }
    onOnChanged: loadStackOnce()
    Component.onCompleted: loadStackOnce()

    // Seed the picks from what the backend proposes each time the list arrives
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

    // --- Card 1: the setting itself ------------------------------------------------------------------
    SpotifySettingCard {
        Layout.fillWidth: true
        accentColor: root.accentColor
        showBody: root.on && !root.pickerOpen
        title: I18n.tr("Tự cập nhật từ Spotify", "Auto-update from Spotify")
        description: I18n.tr("Playlist và bài đã thích của bạn tự về Nutsty. Chỉ nên bật trên một máy, các máy khác nhận qua đồng bộ tài khoản.",
                             "Your playlists and likes arrive in Nutsty by themselves. Turn this on for one device only, your other devices get them through account sync.")

        headerRight: Rectangle {
            id: syncSwitch
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
                x: syncSwitch.lit ? parent.width - width - 3 : 3
                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleSync()
            }
        }

        // Value bottom-left, what is kept in step fanned out on the right
        RowLayout {
            Layout.fillWidth: true
            visible: root.on && !root.pickerOpen
            spacing: 16

            // Mochy's figure layout: the count rolls (and spins like a slot machine while a sync runs),
            // a monospace caption broken by hand sits beside it, never under it
            Row {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignBottom
                spacing: 14

                // clipped: spinning reels would otherwise show the digits above and below
                Item {
                    id: countBox
                    width: countOdo.implicitWidth
                    height: countOdo.implicitHeight
                    clip: true
                    Odometer {
                        id: countOdo
                        text: String(root.syncedCount)
                        pixelSize: 44
                        spinning: !!(root.sync && root.sync.running)
                    }
                }

                Text {
                    anchors.verticalCenter: countBox.verticalCenter
                    text: I18n.tr("mục\nđang khớp\nvới Spotify", "kept\nin step\nwith Spotify")
                    font.family: "monospace"
                    font.pixelSize: 11
                    lineHeight: 0.95
                    color: Theme.textSecondary
                }
            }

            // Cover fan: Liked Songs first, then up to three synced covers, tilted like a hand of cards
            Item {
                id: fan
                Layout.preferredWidth: 190
                Layout.preferredHeight: 92
                readonly property var covers: {
                    var out = [];
                    if (root.likedSynced) out.push({ liked: true, image: "", title: "" });
                    for (var i = 0; i < root.synced.length && out.length < 4; i++) out.push(root.synced[i]);
                    return out;
                }
                // The preview performs the setting: while a sync runs the covers lift one after another,
                // left to right, as if passing through. Idle, hidden or in Lite mode it rests.
                readonly property bool lite: (typeof win !== "undefined") ? !!win.liteMode : false
                readonly property bool waving: !!(root.sync && root.sync.running) && fan.visible && !fan.lite
                property real phase: 0
                NumberAnimation on phase {
                    from: 0; to: 1; duration: 1400; loops: Animation.Infinite
                    running: fan.waving
                }
                onWavingChanged: if (!waving) phase = 0

                Repeater {
                    model: fan.covers
                    delegate: Item {
                        id: fanCard
                        required property var modelData
                        required property int index
                        readonly property real mid: (fan.covers.length - 1) / 2
                        width: 72
                        height: 72
                        z: index
                        x: fan.width - 72 - 10 - (fan.covers.length - 1 - index) * 34
                        // 0..1 bump that travels across the hand once per phase
                        readonly property real lift: {
                            if (!fan.waving) return 0;
                            var t = fan.phase - fanCard.index / Math.max(1, fan.covers.length) * 0.6;
                            t = t - Math.floor(t);
                            return t < 0.4 ? Math.sin(t / 0.4 * Math.PI) : 0;
                        }
                        y: 10 + Math.abs(index - mid) * 4 - lift * 14
                        rotation: (index - mid) * 7
                        transformOrigin: Item.Bottom

                        RoundedImage {
                            anchors.fill: parent
                            visible: !fanCard.modelData.liked
                            radius: 12
                            source: fanCard.modelData.image || ""
                            sourceSize: Qt.size(152, 152)
                            initialsText: fanCard.modelData.title || ""
                            fallbackIcon: "../assets/icons/media-playlist-consecutive-symbolic.svg"
                            fallbackIconColor: root.accentColor
                            fallbackIconSize: 22
                            borderColor: Qt.rgba(1, 1, 1, 0.14)
                            borderWidth: 1
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: !!fanCard.modelData.liked
                            radius: 12
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.14)
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.lighter(root.accentColor, 1.35) }
                                GradientStop { position: 1.0; color: Qt.darker(root.accentColor, 1.9) }
                            }
                            AppIcon {
                                anchors.centerIn: parent
                                source: "../assets/icons/emblem-favorite-symbolic.svg"
                                iconSize: 24
                                color: "#ffffff"
                            }
                        }
                    }
                }
            }
        }

        SpotifySubCard {
            visible: root.on && !root.pickerOpen
            accentColor: root.accentColor
            clickable: !(root.sync && root.sync.running)
            shimmer: !!(root.sync && root.sync.running)
            title: root.sync && root.sync.running ? I18n.tr("Đang đồng bộ...", "Syncing...") : I18n.tr("Đồng bộ ngay", "Sync now")
            description: !root.sync ? "" : (root.sync.lastSync > 0
                  ? I18n.tr("Lần cuối lúc %1", "Last synced at %1").arg(Qt.formatDateTime(new Date(root.sync.lastSync * 1000), "HH:mm dd/MM"))
                  : I18n.tr("Chưa đồng bộ lần nào", "Not synced yet"))
            onClicked: root.sync.run()

            Item {
                width: 20
                height: 20
                CircularSpinner {
                    anchors.centerIn: parent
                    visible: !!(root.sync && root.sync.running)
                    size: 18
                    strokeWidth: 2
                    color: root.accentColor
                    running: visible
                }
                AppIcon {
                    anchors.centerIn: parent
                    visible: !(root.sync && root.sync.running)
                    source: "../assets/icons/view-refresh-symbolic.svg"
                    iconSize: 16
                    color: root.accentColor
                }
            }
        }

        SpotifySubCard {
            visible: root.on && !root.pickerOpen
            accentColor: root.accentColor
            clickable: true
            title: I18n.tr("Chọn playlist", "Choose playlists")
            description: I18n.tr("%1 trên %2 mục trong thư viện", "%1 of %2 in your library").arg(root.syncedCount).arg(root.totalCount)
            onClicked: root.openPicker()

            AppIcon {
                source: "../assets/icons/media-playlist-consecutive-symbolic.svg"
                iconSize: 16
                color: root.accentColor
            }
        }

        // Lists held back by the mass-delete guard
        Repeater {
            model: root.on && !root.pickerOpen && root.sync ? root.sync.blocked : []
            delegate: SpotifySubCard {
                required property var modelData
                accentColor: root.accentColor
                danger: true
                title: I18n.tr("%1 định xóa nhiều bài, đã tạm dừng", "%1 would remove many songs, paused").arg(root.blockedName(modelData))
                description: I18n.tr("Kiểm tra trên Spotify trước khi áp dụng", "Check it on Spotify before applying")

                LosslessSmallButton {
                    label: I18n.tr("Vẫn áp dụng", "Apply anyway")
                    danger: true
                    onClicked: if (root.sync) root.sync.forceApply(modelData)
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 2
            visible: root.on && !root.pickerOpen && !!(root.sync && root.sync.unmatched > 0)
            text: root.sync ? I18n.tr("%1 bài chưa tìm được bản trên YouTube", "%1 songs not found on YouTube yet").arg(root.sync.unmatched) : ""
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.textMuted
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 2
            visible: root.on && !root.pickerOpen && text !== ""
            text: root.sync ? root.errorText(root.sync.lastError) : ""
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: "#fda4af"
            wrapMode: Text.WordWrap
        }
    }

    // --- Card 2: the picker, covers as the choices ---------------------------------------------------
    SpotifySettingCard {
        Layout.fillWidth: true
        visible: root.pickerOpen
        accentColor: root.accentColor
        title: I18n.tr("Chọn playlist để đồng bộ", "Choose playlists to sync")
        description: I18n.tr("Chạm vào ảnh bìa để chọn hoặc bỏ. Lần đầu sẽ mất vài phút.",
                             "Tap a cover to pick or drop it. The first sync takes a few minutes.")

        headerRight: Text {
            visible: !root.choicesLoading && root.choicesErr === ""
            text: root.pickedCount + "/" + root.totalCount
            font.family: Theme.fontFamily
            font.pixelSize: 28
            font.weight: Font.Black
            color: Theme.textPrimary
        }

        SpotifySubCard {
            visible: root.choicesLoading || root.choicesErr !== ""
            accentColor: root.accentColor
            danger: root.choicesErr !== ""
            title: root.choicesLoading ? I18n.tr("Đang lấy playlist từ Spotify...", "Getting your playlists from Spotify...")
                                       : root.errorText(root.choicesErr)

            CircularSpinner {
                visible: root.choicesLoading
                size: 18
                strokeWidth: 2
                color: root.accentColor
                running: visible
            }
        }

        Grid {
            id: coverGrid
            Layout.fillWidth: true
            Layout.topMargin: 2
            visible: !root.choicesLoading && root.choicesErr === ""
            spacing: 10
            columns: Math.max(3, Math.floor((width + spacing) / (130 + spacing)))
            readonly property real cell: (width - (columns - 1) * spacing) / columns

            SpotifyCoverPick {
                width: coverGrid.cell
                height: coverGrid.cell
                accentColor: root.accentColor
                likedArt: true
                checked: root.likedPicked
                title: I18n.tr("Bài hát đã thích", "Liked Songs")
                subtitle: I18n.tr("Thư viện của bạn", "Your library")
                onToggled: root.likedPicked = !root.likedPicked
            }

            Repeater {
                model: root.pickerOpen && root.sync ? root.sync.choices : []
                delegate: SpotifyCoverPick {
                    required property var modelData
                    width: coverGrid.cell
                    height: coverGrid.cell
                    accentColor: root.accentColor
                    cover: modelData.image || ""
                    checked: !!root.picked[modelData.id]
                    title: modelData.title || ""
                    subtitle: root.ownerText(modelData)
                    onToggled: {
                        var m = Object.assign({}, root.picked);
                        m[modelData.id] = !m[modelData.id];
                        root.picked = m;
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 8

            LosslessSmallButton {
                readonly property bool all: root.pickedCount === root.totalCount
                visible: !root.choicesLoading && root.choicesErr === ""
                accentColor: root.accentColor
                label: all ? I18n.tr("Bỏ chọn hết", "Clear all") : I18n.tr("Chọn hết", "Select all")
                onClicked: root.setAll(!all)
            }

            Item { Layout.fillWidth: true }

            LosslessSmallButton {
                accentColor: root.accentColor
                label: I18n.tr("Hủy", "Cancel")
                onClicked: root.pickerOpen = false
            }

            LosslessSmallButton {
                readonly property bool ready: !root.choicesLoading && root.choicesErr === "" && root.pickedCount > 0
                accentColor: root.accentColor
                primary: true
                enabled: ready
                opacity: ready ? 1.0 : 0.4
                label: I18n.tr("Bắt đầu đồng bộ", "Start syncing")
                onClicked: root.confirm()
            }
        }
    }
}
