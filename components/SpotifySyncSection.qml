import QtQuick
import QtQuick.Layouts
import "."

// Settings > Account, under the Spotify account row: two-way sync with the user's own Spotify library.
// `sync` is the SpotifySync object of shell.qml. Shown only while a Spotify cookie is saved.
// Laid out after Mochy's Sync and account-import screens: grouped cards of rows, round icon or cover,
// title over one line of description, a control at the end; longer notes go under the card.
ColumnLayout {
    id: root
    spacing: 16

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
    readonly property int syncedCount: synced.length + (sync && sync.likedChoice ? 1 : 0)

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

    // --- On/off ---------------------------------------------------------------------------------
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8

        SpotifySyncGroup {
            Layout.fillWidth: true
            title: I18n.tr("Đồng bộ Spotify", "Spotify sync")
            accentColor: root.accentColor

            SpotifySyncRow {
                accentColor: root.accentColor
                iconSource: "../assets/icons/spotify-link.svg"
                title: I18n.tr("Tự cập nhật từ Spotify", "Auto-update from Spotify")
                description: I18n.tr("Playlist và bài đã thích về Nutsty", "Your playlists and likes, in Nutsty")
                onClicked: root.toggleSync()

                Rectangle {
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
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            text: I18n.tr("Chỉ nên bật trên một máy. Các máy khác nhận qua đồng bộ tài khoản.",
                          "Turn this on for one device only. Your other devices get the changes through account sync.")
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.textMuted
            wrapMode: Text.WordWrap
        }
    }

    // --- Status while on: sync now, what is synced, lists held back ---------------------------------
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.on && !root.pickerOpen
        spacing: 8

        SpotifySyncGroup {
            Layout.fillWidth: true
            title: I18n.tr("Bây giờ", "Now")
            accentColor: root.accentColor

            SpotifySyncRow {
                accentColor: root.accentColor
                iconSource: "../assets/icons/view-refresh-symbolic.svg"
                active: !(root.sync && root.sync.running)
                title: root.sync && root.sync.running ? I18n.tr("Đang đồng bộ...", "Syncing...") : I18n.tr("Đồng bộ ngay", "Sync now")
                description: !root.sync ? "" : (root.sync.lastSync > 0
                      ? I18n.tr("Lần cuối lúc %1", "Last synced at %1").arg(Qt.formatDateTime(new Date(root.sync.lastSync * 1000), "HH:mm dd/MM"))
                      : I18n.tr("Chưa đồng bộ lần nào", "Not synced yet"))
                onClicked: root.sync.run()

                CircularSpinner {
                    visible: !!(root.sync && root.sync.running)
                    size: 18
                    strokeWidth: 2
                    color: root.accentColor
                    running: visible
                }
            }

            SpotifySyncRow {
                accentColor: root.accentColor
                iconSource: "../assets/icons/media-playlist-consecutive-symbolic.svg"
                title: I18n.tr("Chọn playlist", "Choose playlists")
                description: I18n.tr("Đang giữ %1 mục khớp với Spotify", "Keeping %1 in step with Spotify").arg(root.syncedCount)
                onClicked: root.openPicker()

                // What is being kept in step, as a small stack of round covers
                Row {
                    spacing: -8

                    Rectangle {
                        visible: !!(root.sync && root.sync.likedChoice)
                        width: 26
                        height: 26
                        radius: 13
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.18)
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.lighter(root.accentColor, 1.35) }
                            GradientStop { position: 1.0; color: Qt.darker(root.accentColor, 1.9) }
                        }
                        AppIcon {
                            anchors.centerIn: parent
                            source: "../assets/icons/emblem-favorite-symbolic.svg"
                            iconSize: 11
                            color: "#ffffff"
                        }
                    }

                    Repeater {
                        model: root.synced.slice(0, 4)
                        delegate: RoundedImage {
                            required property var modelData
                            width: 26
                            height: 26
                            radius: 13
                            source: modelData.image || ""
                            sourceSize: Qt.size(52, 52)
                            initialsText: modelData.title || ""
                            fallbackIcon: "../assets/icons/media-playlist-consecutive-symbolic.svg"
                            fallbackIconColor: root.accentColor
                            fallbackIconSize: 11
                            borderColor: Qt.rgba(1, 1, 1, 0.18)
                            borderWidth: 1
                        }
                    }

                    Text {
                        visible: root.synced.length > 4
                        anchors.verticalCenter: parent.verticalCenter
                        leftPadding: 14
                        text: "+" + (root.synced.length - 4)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Theme.textSecondary
                    }
                }
            }

            // Lists held back by the mass-delete guard
            Repeater {
                model: root.sync ? root.sync.blocked : []
                delegate: SpotifySyncRow {
                    required property var modelData
                    accentColor: root.accentColor
                    danger: true
                    clickable: false
                    iconSource: "../assets/icons/spotify-link.svg"
                    title: I18n.tr("%1 định xóa nhiều bài, đã tạm dừng", "%1 would remove many songs, paused").arg(root.blockedName(modelData))
                    description: I18n.tr("Kiểm tra trên Spotify trước khi áp dụng", "Check it on Spotify before applying")

                    LosslessSmallButton {
                        label: I18n.tr("Vẫn áp dụng", "Apply anyway")
                        danger: true
                        onClicked: if (root.sync) root.sync.forceApply(modelData)
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            visible: !!(root.sync && root.sync.unmatched > 0)
            text: root.sync ? I18n.tr("%1 bài chưa tìm được bản trên YouTube", "%1 songs not found on YouTube yet").arg(root.sync.unmatched) : ""
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.textMuted
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            visible: text !== ""
            text: root.sync ? root.errorText(root.sync.lastError) : ""
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: "#fda4af"
            wrapMode: Text.WordWrap
        }
    }

    // --- Picker: actions on top, then every list with its cover and a checkbox -----------------------
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.pickerOpen
        spacing: 16

        SpotifySyncGroup {
            Layout.fillWidth: true
            title: I18n.tr("Chọn playlist để đồng bộ", "Choose playlists to sync")
            accentColor: root.accentColor

            SpotifySyncRow {
                accentColor: root.accentColor
                iconSource: "../assets/icons/list-add-symbolic.svg"
                active: !root.choicesLoading && root.choicesErr === "" && root.pickedCount > 0
                title: root.pickedCount === 0 ? I18n.tr("Chọn thứ cần đồng bộ", "Choose what to sync")
                                              : I18n.tr("Đồng bộ %1 mục đã chọn", "Sync %1 selected").arg(root.pickedCount)
                description: root.pickedCount === 0 ? I18n.tr("Đánh dấu playlist bên dưới", "Tick playlists below")
                                                    : I18n.tr("Lần đầu sẽ mất vài phút", "The first sync takes a few minutes")
                onClicked: {
                    var ids = [];
                    for (var k in root.picked) if (root.picked[k]) ids.push(k);
                    root.sync.confirmSelection(ids, root.likedPicked);
                    root.pickerOpen = false;
                }
            }

            SpotifySyncRow {
                readonly property bool all: root.pickedCount === root.totalCount
                accentColor: root.accentColor
                iconSource: "../assets/icons/edit-select-all-symbolic.svg"
                active: !root.choicesLoading && root.choicesErr === ""
                title: all ? I18n.tr("Bỏ chọn hết", "Clear all") : I18n.tr("Chọn hết", "Select all")
                onClicked: {
                    var on = !all;
                    var m = {};
                    var list = root.sync ? (root.sync.choices || []) : [];
                    for (var i = 0; i < list.length; i++) m[list[i].id] = on;
                    root.picked = m;
                    root.likedPicked = on;
                }
            }

            SpotifySyncRow {
                accentColor: root.accentColor
                iconSource: "../assets/icons/window-close-symbolic.svg"
                title: I18n.tr("Hủy", "Cancel")
                onClicked: root.pickerOpen = false
            }
        }

        // Loading or error, in place of the list
        SpotifySyncGroup {
            Layout.fillWidth: true
            visible: root.choicesLoading || root.choicesErr !== ""
            accentColor: root.accentColor

            SpotifySyncRow {
                accentColor: root.accentColor
                clickable: false
                danger: root.choicesErr !== ""
                iconSource: "../assets/icons/spotify-link.svg"
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
        }

        SpotifySyncGroup {
            Layout.fillWidth: true
            visible: !root.choicesLoading && root.choicesErr === ""
            title: I18n.tr("%1 mục trong thư viện", "%1 in your library").arg(root.totalCount)
            accentColor: root.accentColor

            SpotifySyncRow {
                accentColor: root.accentColor
                likedArt: true
                title: I18n.tr("Bài hát đã thích", "Liked Songs")
                description: I18n.tr("Thư viện của bạn", "Your library")
                onClicked: root.likedPicked = !root.likedPicked

                SpotifySyncCheck { checked: root.likedPicked; accentColor: root.accentColor }
            }

            Repeater {
                model: root.pickerOpen && root.sync ? root.sync.choices : []
                delegate: SpotifySyncRow {
                    required property var modelData
                    accentColor: root.accentColor
                    coverMode: true
                    cover: modelData.image || ""
                    title: modelData.title || ""
                    description: root.ownerText(modelData)
                    onClicked: {
                        var m = Object.assign({}, root.picked);
                        m[modelData.id] = !m[modelData.id];
                        root.picked = m;
                    }

                    SpotifySyncCheck { checked: !!root.picked[modelData.id]; accentColor: root.accentColor }
                }
            }
        }
    }
}
