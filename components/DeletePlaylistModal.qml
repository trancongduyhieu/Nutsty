import QtQuick
import QtQuick.Layouts
import "."
import "cover_art.js" as CoverArt

// Asks before a playlist is deleted, and says what else goes with it. A list linked to Spotify with
// two-way sync on is removed from the Spotify library too; with one-way sync only the Nutsty copy goes
// and the link stops. Same frosted panel as the add-to-playlist modal. Esc, the backdrop and Cancel close it.
Rectangle {
    id: root

    anchors.fill: parent
    color: "transparent"
    visible: root.shown || panel.opacity > 0
    z: 10010

    property color accentColor: Theme.accent
    property Item backgroundSourceItem: null
    property bool liteMode: false
    property bool writeBack: false        // two-way Spotify sync is on
    property var playlist: null
    property bool shown: false

    signal confirmed(var playlist)

    readonly property var link: (root.playlist && root.playlist.spotifyLink) || null
    readonly property bool linked: !!root.link
    readonly property bool alsoSpotify: root.linked && root.writeBack
    readonly property bool ownedOnSpotify: root.linked && !!root.link.owned
    readonly property string listName: root.playlist ? (root.playlist.title || root.playlist.name || "") : ""
    readonly property color rose: Qt.rgba(244 / 255, 63 / 255, 94 / 255, 1)
    readonly property real accentHue: CoverArt.hexToOklch(accentColor.toString()).h
    readonly property color mutedText: CoverArt.oklchToHex(0.82, 0.03, accentHue)

    function openFor(pl) {
        root.playlist = pl;
        root.shown = true;
        root.forceActiveFocus();
    }

    function closeModal() { root.shown = false; }

    function confirm() {
        var pl = root.playlist;
        root.closeModal();
        if (pl) root.confirmed(pl);
    }

    readonly property string message: {
        if (root.alsoSpotify && root.ownedOnSpotify)
            return I18n.tr("Nutsty đang đồng bộ hai chiều với Spotify, nên danh sách này cũng sẽ bị xóa trên Spotify. Bạn vẫn khôi phục được nó trong trang tài khoản Spotify.",
                           "Nutsty syncs both ways with Spotify, so this playlist is deleted on Spotify too. You can still recover it from your Spotify account page.");
        if (root.alsoSpotify)
            return I18n.tr("Nutsty đang đồng bộ hai chiều với Spotify, nên mục này cũng sẽ bị bỏ khỏi thư viện Spotify của bạn.",
                           "Nutsty syncs both ways with Spotify, so this is also removed from your Spotify library.");
        if (root.linked)
            return I18n.tr("Chỉ xóa trong Nutsty. Bản trên Spotify vẫn còn nguyên, và Nutsty sẽ ngừng đồng bộ danh sách này.",
                           "Only deleted in Nutsty. It stays on Spotify, and Nutsty stops syncing it.");
        return I18n.tr("Danh sách này sẽ bị xóa hẳn và không thể khôi phục.",
                       "This playlist is deleted for good. This can't be undone.");
    }

    focus: root.shown
    Keys.onEscapePressed: root.closeModal()
    Keys.onReturnPressed: root.confirm()

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.closeModal()
    }

    GlassPanel {
        id: panel
        width: Math.min(400, root.width - 48)
        height: col.implicitHeight + 40
        anchors.centerIn: parent
        glassSource: root.backgroundSourceItem
        liteMode: root.liteMode
        ground: Qt.rgba(0.04 + root.accentColor.r * 0.10, 0.04 + root.accentColor.g * 0.10, 0.06 + root.accentColor.b * 0.10, 1)
        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 20
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                RoundedImage {
                    Layout.preferredWidth: 52
                    Layout.preferredHeight: 52
                    radius: 10
                    source: root.playlist ? (root.playlist.customCover || root.playlist.image || "") : ""
                    sourceSize: Qt.size(104, 104)
                    initialsText: root.listName
                    fallbackIconColor: root.accentColor
                    borderColor: Qt.rgba(1, 1, 1, 0.10)
                    borderWidth: 1
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Xóa danh sách phát?", "Delete playlist?")
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 17
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.listName
                        color: root.mutedText
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                }
            }

            // What else goes with it. Spotify cases carry the Spotify mark, rose when Spotify loses it too.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: msgRow.implicitHeight + 24
                radius: 12
                readonly property color tone: root.alsoSpotify ? root.rose : root.accentColor
                color: Qt.rgba(tone.r, tone.g, tone.b, 0.10)
                border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.28)
                border.width: 1

                RowLayout {
                    id: msgRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    AppIcon {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 1
                        source: root.linked ? "../assets/icons/spotify-symbolic.svg" : "../assets/icons/user-trash-symbolic.svg"
                        color: root.alsoSpotify ? Qt.lighter(root.rose, 1.25) : root.accentColor
                        iconSize: 16
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.message
                        wrapMode: Text.WordWrap
                        color: Qt.rgba(1, 1, 1, 0.86)
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        lineHeight: 1.25
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Item { Layout.fillWidth: true }
                LosslessSmallButton {
                    Layout.preferredHeight: 36
                    Layout.preferredWidth: Math.max(96, children[0].implicitWidth + 32)  // children[0]: the label
                    radius: 10
                    label: I18n.tr("Hủy", "Cancel")
                    accentColor: root.accentColor
                    onClicked: root.closeModal()
                }
                LosslessSmallButton {
                    Layout.preferredHeight: 36
                    Layout.preferredWidth: Math.max(96, children[0].implicitWidth + 32)  // children[0]: the label
                    radius: 10
                    label: root.alsoSpotify ? I18n.tr("Xóa cả hai nơi", "Delete in both")
                                            : I18n.tr("Xóa", "Delete")
                    danger: true
                    primary: true
                    onClicked: root.confirm()
                }
            }
        }
    }
}
