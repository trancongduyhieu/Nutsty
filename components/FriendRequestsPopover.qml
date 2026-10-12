import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import "."

Item {
    id: root
    anchors.fill: parent
    enabled: isOpen || closingGuard
    visible: opacity > 0 || closingGuard
    opacity: isOpen ? 1 : 0
    z: 9998

    Behavior on opacity {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    property bool isOpen: false
    property bool closingGuard: false
    property var requests: [] // Array of { id, from_email, from_name, from_avatar, created_ts }
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent
    property Item backgroundSourceItem: null
    property real targetX: 0
    property real targetY: 0

    signal acceptRequested(string requestId, string fromEmail, string fromName)
    signal rejectRequested(string requestId, string fromEmail)

    Timer {
        id: closeTimer
        interval: 200
        repeat: false
        onTriggered: root.closingGuard = false
    }

    function toggleAt(requestsList, xPos, yPos) {
        if (root.isOpen) {
            root.closePopover();
        } else {
            root.openAt(requestsList, xPos, yPos);
        }
    }

    function openAt(requestsList, xPos, yPos) {
        closeTimer.stop();
        root.closingGuard = false;
        root.requests = requestsList || [];
        if (xPos !== undefined && xPos > 0) root.targetX = xPos;
        else root.targetX = root.width - 320;
        if (yPos !== undefined && yPos > 0) root.targetY = yPos;
        else root.targetY = 64;
        root.isOpen = true;
    }

    function closePopover() {
        if (!root.isOpen && !root.closingGuard) return;
        root.isOpen = false;
        root.closingGuard = true;
        closeTimer.restart();
    }

    // Dismiss backdrop (click outside to close)
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true
        onPressed: mouse => {
            mouse.accepted = true;
            root.closePopover();
        }
        onReleased: mouse => mouse.accepted = true
        onClicked: mouse => mouse.accepted = true
    }

    // Popover Card with Keo 502 Optical LiquidGlass (Nền phẳng, chữ phẳng, không hộp trong hộp)
    Item {
        id: cardWrapper
        width: 330
        height: Math.min(380, Math.max(130, col.implicitHeight + 24))

        // Position dropdown anchored below bell icon
        x: Math.max(16, Math.min(root.targetX - 24, root.width - width - 16))
        y: Math.max(16, Math.min(root.targetY + 8, root.height - height - 16))

        scale: root.isOpen ? 1 : 0.94
        Behavior on scale {
            NumberAnimation { duration: 160; easing.type: Easing.OutBack }
        }

        // Deep Obsidian Frosted Foundation: Blocks text bleed-through
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: Qt.rgba(0.05, 0.06, 0.09, 0.90)
            z: 1
        }

        // Keo 502 Optical LiquidGlass Resin Container
        LiquidGlass {
            id: card
            anchors.fill: parent
            radius: 16
            displacement: 18.0
            aberration: 0.03
            bevelWidth: 24.0
            tintColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
            backgroundSourceItem: root.backgroundSourceItem
            isFlowActive: (typeof win !== "undefined" && win.isPlaying && win.currentTrack !== null)
            clip: true
            z: 2

            // 1px Concentric Hairline Accent Border
            Rectangle {
                anchors.fill: parent
                radius: card.radius
                color: "transparent"
                border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25)
                border.width: 1
                z: 1
                Behavior on border.color { ColorAnimation { duration: 250 } }
            }

            // Prevent click-through from card background to dismiss backdrop
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                z: 1
                onPressed: mouse => mouse.accepted = true
                onReleased: mouse => mouse.accepted = true
                onClicked: mouse => mouse.accepted = true
            }

            ColumnLayout {
                id: col
                anchors.top: parent.top
                anchors.topMargin: 12
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.rightMargin: 14
                spacing: 10
                z: 10

                // Header Row: Tiêu đề phẳng + Số lượng + Nút đóng ✕
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    AppIcon {
                        source: "../assets/icons/notifications-symbolic.svg"
                        iconSize: 15
                        color: root.accentColor
                    }

                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Lời mời kết bạn", "Friend Requests") + (root.requests && root.requests.length > 0 ? " (" + root.requests.length + ")" : "")
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                    }

                    // Nút Đóng mini phẳng
                    Item {
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22

                        Rectangle {
                            anchors.fill: parent
                            radius: 11
                            color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            AppIcon {
                                anchors.centerIn: parent
                                source: "../assets/icons/window-close-symbolic.svg"
                                iconSize: 11
                                color: "#ffffff"
                                opacity: closeMouse.containsMouse ? 1.0 : 0.65
                            }
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.closePopover()
                        }
                    }
                }

                // Đường phân cách mỏng phẳng
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                // Empty State phẳng khi không có lời mời nào
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 70
                    visible: !root.requests || root.requests.length === 0

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        AppIcon {
                            Layout.alignment: Qt.AlignHCenter
                            source: "../assets/icons/notifications-symbolic.svg"
                            iconSize: 22
                            color: root.accentColor
                            opacity: 0.35
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: I18n.tr("Không có lời mời nào", "No friend requests")
                            color: Qt.rgba(1, 1, 1, 0.50)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }
                }

                // Danh sách lời mời - NỀN PHẲNG, CHỮ PHẲNG (Hoàn toàn không hộp lồng hộp)
                ListView {
                    id: reqsList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(260, count * 56)
                    visible: root.requests && root.requests.length > 0
                    model: root.requests || []
                    clip: true
                    spacing: 8
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Item {
                        width: reqsList.width
                        height: 48

                        RowLayout {
                            anchors.fill: parent
                            spacing: 10

                            // Avatar tròn phẳng không răng cưa
                            RoundedImage {
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                radius: 18
                                source: modelData.from_avatar || ""
                                initialsText: modelData.from_name || modelData.from_email || ""
                                useInitialsFallback: true
                                fallbackIcon: "../assets/icons/system-users-symbolic.svg"
                                borderWidth: 1
                                borderColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.40)
                            }

                            // Thông tin người gửi phẳng
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.from_name || modelData.from_email || "User"
                                    color: "#ffffff"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.from_email || ""
                                    color: Qt.rgba(1, 1, 1, 0.55)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                }
                            }

                            // Cặp nút hành động phẳng (Flat Actions)
                            RowLayout {
                                spacing: 6

                                // Nút Chấp nhận phẳng (Accent Color)
                                Rectangle {
                                    Layout.preferredWidth: 64
                                    Layout.preferredHeight: 26
                                    radius: 13
                                    color: acceptMouse.containsMouse
                                        ? root.accentColor
                                        : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, acceptMouse.containsMouse ? 0.90 : 0.45)
                                    border.width: 1
                                    scale: acceptMouse.containsMouse ? 1.05 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 120 } }
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: I18n.tr("Đồng ý", "Accept")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: acceptMouse.containsMouse ? "#ffffff" : root.accentColor
                                    }

                                    MouseArea {
                                        id: acceptMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.acceptRequested(modelData.id, modelData.from_email, modelData.from_name);
                                        }
                                    }
                                }

                                // Nút Từ chối phẳng (Muted Rose)
                                Rectangle {
                                    Layout.preferredWidth: 54
                                    Layout.preferredHeight: 26
                                    radius: 13
                                    color: rejectMouse.containsMouse
                                        ? Qt.rgba(244, 63, 94, 0.28)
                                        : Qt.rgba(244, 63, 94, 0.12)
                                    border.color: Qt.rgba(244, 63, 94, rejectMouse.containsMouse ? 0.60 : 0.30)
                                    border.width: 1
                                    scale: rejectMouse.containsMouse ? 1.05 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 120 } }
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: I18n.tr("Từ chối", "Decline")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: Qt.rgba(251, 113, 133, 0.95)
                                    }

                                    MouseArea {
                                        id: rejectMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.rejectRequested(modelData.id, modelData.from_email);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
