import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import "."
import "cover_art.js" as CoverArt
import "notification_kinds.js" as Kinds

// Popover under the bell: things waiting on you (friend requests, an update) on top,
// then the history kept by NotificationStore. Opening it marks everything read.
Item {
    id: root
    anchors.fill: parent
    z: 9998
    visible: opacity > 0.01
    enabled: isOpen
    opacity: isOpen ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

    property NotificationStore store: null
    property color accentColor: Theme.accent
    property int friendRequestCount: 0
    property bool hasUpdate: false
    property string latestVersion: ""

    property bool isOpen: false
    property real targetX: 0
    property real targetY: 64
    property real now: Date.now()

    signal friendRequestsRequested(real xPos, real yPos)
    signal updateRequested()

    readonly property real accentHue: CoverArt.hexToOklch(accentColor.toString()).h
    readonly property color ground: CoverArt.oklchToHex(0.19, 0.025, accentHue)
    readonly property color rowHover: CoverArt.oklchToHex(0.24, 0.035, accentHue)
    readonly property color mutedText: CoverArt.oklchToHex(0.80, 0.03, accentHue)
    readonly property color faintText: CoverArt.oklchToHex(0.62, 0.03, accentHue)
    readonly property color hairline: Qt.rgba(1, 1, 1, 0.09)
    readonly property color rose: Qt.rgba(244 / 255, 63 / 255, 94 / 255, 1)
    readonly property var history: store ? store.items : []
    readonly property bool hasPinned: friendRequestCount > 0 || hasUpdate

    function toggleAt(xPos, yPos) {
        if (root.isOpen) { root.close(); return; }
        root.targetX = xPos > 0 ? xPos : root.width - 40;
        root.targetY = yPos > 0 ? yPos : 64;
        root.now = Date.now();
        root.isOpen = true;
    }

    function close() {
        if (!root.isOpen) return;
        root.isOpen = false;
        if (root.store) root.store.markAllRead();
    }

    // Relative times stay fresh while it is open
    Timer { interval: 30000; repeat: true; running: root.isOpen; onTriggered: root.now = Date.now() }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => { mouse.accepted = true; root.close(); }
    }

    component RowIcon: Rectangle {
        property string kind: "info"
        width: 32
        height: 32
        radius: 16
        color: Kinds.isError(kind)
               ? Qt.rgba(root.rose.r, root.rose.g, root.rose.b, 0.16)
               : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
        AppIcon {
            anchors.centerIn: parent
            source: Kinds.icon(parent.kind)
            iconSize: 16
            color: Kinds.isError(parent.kind) ? Qt.lighter(root.rose, 1.3) : Qt.lighter(root.accentColor, 1.3)
        }
    }

    component TextButton: Text {
        id: tb
        signal clicked()
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: tbArea.containsMouse ? "#ffffff" : Qt.lighter(root.accentColor, 1.3)
        Accessible.role: Accessible.Button
        Accessible.name: text
        MouseArea {
            id: tbArea
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tb.clicked()
        }
    }

    // A pinned row: something to act on now
    component PinnedRow: Rectangle {
        id: pin
        property string kind: "info"
        property string label: ""
        property string action: ""
        signal triggered()
        Layout.fillWidth: true
        Layout.preferredHeight: 52
        radius: 12
        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, pinArea.containsMouse ? 0.16 : 0.10)
        Behavior on color { ColorAnimation { duration: 120 } }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 14
            spacing: 12
            RowIcon { kind: pin.kind }
            Text {
                Layout.fillWidth: true
                text: pin.label
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: "#ffffff"
                elide: Text.ElideRight
            }
            Text {
                text: pin.action
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.Bold
                color: Qt.lighter(root.accentColor, 1.3)
            }
        }
        MouseArea {
            id: pinArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pin.triggered()
        }
    }

    Item {
        id: cardWrap
        width: Math.min(372, root.width - 32)
        height: Math.min(col.implicitHeight, root.height - y - 16)
        x: Math.max(16, Math.min(root.targetX - width + 40, root.width - width - 16))
        y: Math.max(16, root.targetY + 10)
        scale: root.isOpen ? 1 : 0.96
        transformOrigin: Item.TopRight
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        RectangularShadow {
            anchors.fill: card
            offset.y: 10
            blur: 32
            radius: card.radius
            color: Qt.rgba(0, 0, 0, 0.45)
        }

        Rectangle {
            id: card
            anchors.fill: parent
            radius: 18
            color: root.ground
            border.color: root.hairline
            border.width: 1
            clip: true

            MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

            ColumnLayout {
                id: col
                width: parent.width
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 18
                    Layout.topMargin: 16
                    Layout.bottomMargin: 10
                    spacing: 14
                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Thông báo", "Notifications")
                        font.family: Theme.fontFamily
                        font.pixelSize: 17
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }
                    TextButton {
                        visible: root.store && root.store.unread > 0
                        text: I18n.tr("Đánh dấu đã đọc", "Mark all read")
                        onClicked: root.store.markAllRead()
                    }
                    TextButton {
                        visible: root.history.length > 0
                        text: I18n.tr("Xóa hết", "Clear")
                        onClicked: root.store.clear()
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    Layout.bottomMargin: 6
                    visible: root.hasPinned
                    spacing: 6
                    PinnedRow {
                        visible: root.friendRequestCount > 0
                        kind: "friend"
                        label: I18n.tr(root.friendRequestCount + " lời mời kết bạn", root.friendRequestCount + (root.friendRequestCount === 1 ? " friend request" : " friend requests"))
                        action: I18n.tr("Xem", "View")
                        onTriggered: { var p = cardWrap.mapToItem(root, cardWrap.width - 40, 0); root.close(); root.friendRequestsRequested(p.x, p.y - 10); }
                    }
                    PinnedRow {
                        visible: root.hasUpdate
                        kind: "update"
                        label: I18n.tr("Có bản mới " + root.latestVersion, "Version " + root.latestVersion + " is out")
                        action: I18n.tr("Cập nhật", "Update")
                        onTriggered: { root.close(); root.updateRequested(); }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.topMargin: 4
                    visible: root.hasPinned && root.history.length > 0
                    color: root.hairline
                }

                // Empty state: fixed-width column centred in the card, texts centred inside it
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: emptyCol.implicitHeight + 46
                    visible: root.history.length === 0 && !root.hasPinned
                    Column {
                        id: emptyCol
                        y: 14
                        width: Math.min(280, parent.width - 48)
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10
                        AppIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            source: "../assets/icons/notifications-symbolic.svg"
                            iconSize: 28
                            color: root.faintText
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: I18n.tr("Chưa có gì mới", "Nothing new yet")
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            color: "#ffffff"
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: I18n.tr("Bạn bè nghe cùng, bản cập nhật và kết quả xuất nhập sẽ hiện ở đây.",
                                          "Friends listening along, updates and import or export results show up here.")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: root.mutedText
                        }
                    }
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    Layout.preferredHeight: Math.min(contentHeight, 380)
                    Layout.topMargin: 6
                    Layout.bottomMargin: 8
                    visible: root.history.length > 0
                    clip: true
                    model: root.history
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        width: ListView.view.width
                        height: Math.max(56, msg.implicitHeight + 24)
                        radius: 12
                        color: rowArea.hovered ? root.rowHover : "transparent"

                        HoverHandler { id: rowArea }

                        RowIcon {
                            id: ic
                            kind: row.modelData.kind
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.top: parent.top
                            anchors.topMargin: 12
                        }
                        Text {
                            id: msg
                            anchors.left: ic.right
                            anchors.leftMargin: 12
                            anchors.right: when.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.text
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: row.modelData.read ? Font.Normal : Font.Medium
                            color: row.modelData.read ? root.mutedText : "#ffffff"
                            lineHeight: 1.15
                        }
                        Text {
                            id: when
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.top: parent.top
                            anchors.topMargin: 14
                            text: Kinds.ago(row.modelData.ts, root.now, I18n.locale === "vi")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: root.faintText
                            visible: !rowArea.hovered
                        }
                        Rectangle {
                            visible: !row.modelData.read && !rowArea.hovered
                            width: 7; height: 7; radius: 3.5
                            color: root.accentColor
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.top: when.bottom
                            anchors.topMargin: 6
                        }
                        // Remove this one (shows on hover, where the time was)
                        Rectangle {
                            visible: rowArea.hovered
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28; height: 28; radius: 14
                            color: delArea.containsMouse ? Qt.rgba(root.rose.r, root.rose.g, root.rose.b, 0.2) : "transparent"
                            Accessible.role: Accessible.Button
                            Accessible.name: I18n.tr("Xóa thông báo", "Remove notification")
                            AppIcon {
                                anchors.centerIn: parent
                                source: "../assets/icons/window-close-symbolic.svg"
                                iconSize: 11
                                color: delArea.containsMouse ? Qt.lighter(root.rose, 1.3) : root.mutedText
                            }
                            MouseArea {
                                id: delArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.store.remove(row.modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
