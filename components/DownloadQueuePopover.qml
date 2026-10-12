import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import Quickshell
import "."

Item {
    id: root
    anchors.fill: parent
    z: 9999
    visible: opacity > 0
    opacity: isOpen ? 1 : 0
    enabled: isOpen

    Behavior on opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    property bool isOpen: false
    property var dlMgr: (typeof downloadManager !== "undefined" ? downloadManager : null)
    property Item backgroundSourceItem: null
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent

    readonly property var allTasksList: dlMgr ? (dlMgr.tasksList || []) : []
    readonly property var activeTasks: allTasksList.filter(t => t.state === 1 || t.state === 2)
    readonly property var completedTasks: allTasksList.filter(t => t.state === 3)

    function open() {
        isOpen = true;
    }

    function close() {
        isOpen = false;
    }

    // Dismiss backdrop
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true
        onClicked: root.close()
    }

    // Popover Card - Liquid Glass Acrylic Container
    Item {
        id: popoverCard
        width: 390
        height: Math.min(Math.max(tasksCol.implicitHeight + 84, 160), 480)

        // Positioned centered below header
        anchors.horizontalCenter: parent.horizontalCenter
        y: 64

        scale: root.isOpen ? 1.0 : 0.95
        Behavior on scale {
            NumberAnimation { duration: 150; easing.type: Easing.OutBack }
        }

        // Prevent click through
        MouseArea {
            anchors.fill: parent
            preventStealing: true
            onClicked: mouse => mouse.accepted = true
        }

        // Deep Obsidian Frosted Foundation: Blocks text bleed-through
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: Qt.rgba(0.05, 0.06, 0.09, 0.90)
            z: 1
        }

        // Liquid Glass Container (matching PlayerBarBottom)
        LiquidGlass {
            id: popoverGlass
            anchors.fill: parent
            radius: 16
            displacement: 16.0
            aberration: 0.03
            bevelWidth: 20.0
            tintColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
            backgroundSourceItem: root.backgroundSourceItem
            z: 2

            // 1px Hairline Accent Border for Liquid Glass Popover
            Rectangle {
                anchors.fill: parent
                radius: 16
                color: "transparent"
                border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.30)
                border.width: 1
                z: 20
                Behavior on border.color { ColorAnimation { duration: 250 } }
            }

            ColumnLayout {
                id: cardContent
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

            // Header Bar
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                AppIcon {
                    source: "../assets/icons/download-symbolic.svg"
                    iconSize: 15
                    color: root.activeTasks.length > 0 ? root.accentColor : Theme.textSecondary
                }

                Text {
                    text: I18n.tr("Tải xuống & Hàng đợi", "Downloads & Queue")
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                    color: "#ffffff"
                }

                Rectangle {
                    visible: root.activeTasks.length > 0
                    radius: 4
                    height: 18
                    width: actCountText.implicitWidth + 10
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.15)
                    border.color: root.accentColor
                    border.width: 1

                    Text {
                        id: actCountText
                        anchors.centerIn: parent
                        text: root.activeTasks.length + I18n.tr(" đang tải", " active")
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                        color: root.accentColor
                    }
                }

                Item { Layout.fillWidth: true }

                // Open Folder Button
                Rectangle {
                    width: 26
                    height: 26
                    radius: 13
                    color: folderH.hovered ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                    HoverHandler { id: folderH }
                    ToolTip.visible: folderH.hovered
                    ToolTip.text: I18n.tr("Mở thư mục tải xuống", "Open downloads folder")
                    ToolTip.delay: 300

                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/folder-music-symbolic.svg"
                        iconSize: 14
                        color: folderH.hovered ? "#ffffff" : Theme.textSecondary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached([
                                "xdg-open",
                                Quickshell.env("HOME") + "/Music/Downloads_Phone"
                            ]);
                        }
                    }
                }

                // Clear completed button
                Rectangle {
                    width: 26
                    height: 26
                    radius: 13
                    visible: root.completedTasks.length > 0
                    color: clearH.hovered ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                    HoverHandler { id: clearH }
                    ToolTip.visible: clearH.hovered
                    ToolTip.text: I18n.tr("Xóa danh sách đã tải xong", "Clear completed")
                    ToolTip.delay: 300

                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/edit-clear-all-symbolic.svg"
                        iconSize: 14
                        color: clearH.hovered ? "#ffffff" : Theme.textSecondary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.dlMgr) root.dlMgr.clearCompleted();
                        }
                    }
                }

                // Close Button
                Rectangle {
                    width: 26
                    height: 26
                    radius: 13
                    color: closeH.hovered ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                    HoverHandler { id: closeH }
                    ToolTip.visible: closeH.hovered
                    ToolTip.text: I18n.tr("Đóng", "Close")
                    ToolTip.delay: 300

                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/window-close-symbolic.svg"
                        iconSize: 12
                        color: closeH.hovered ? "#ffffff" : Theme.textSecondary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(1, 1, 1, 0.06)
            }

            // Scrollable Task List
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: tasksCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: tasksCol
                    width: parent.width
                    spacing: 10

                    // Empty State
                    Column {
                        Layout.fillWidth: true
                        width: tasksCol.width
                        spacing: 8
                        visible: root.activeTasks.length === 0 && root.completedTasks.length === 0
                        topPadding: 24
                        bottomPadding: 24

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: I18n.tr("Không có tác vụ tải xuống nào", "No active downloads")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textSecondary
                        }

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: I18n.tr("Bài hát tải về được lưu tại ~/Music/Downloads_Phone", "Downloaded tracks are saved to ~/Music/Downloads_Phone")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Qt.rgba(1, 1, 1, 0.35)
                        }
                    }

                    // Section: Active Downloads
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: root.activeTasks.length > 0

                        Text {
                            text: I18n.tr("ĐANG TẢI XUỐNG (", "DOWNLOADING (") + root.activeTasks.length + ")"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: true
                            color: root.accentColor
                        }

                        Repeater {
                            model: root.activeTasks

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                height: 56
                                radius: 6
                                color: Qt.rgba(1, 1, 1, 0.03)
                                border.color: Qt.rgba(1, 1, 1, 0.06)
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 10

                                    // 38x38 Thumbnail with Circular Spinner
                                    Rectangle {
                                        width: 38
                                        height: 38
                                        radius: 4
                                        color: "#1e1e1e"
                                        clip: true

                                        Image {
                                            anchors.fill: parent
                                            source: modelData.thumbnail || ""
                                            fillMode: Image.PreserveAspectCrop
                                            visible: status === Image.Ready
                                        }

                                        CircularSpinner {
                                            anchors.centerIn: parent
                                            size: 16
                                            strokeWidth: 2
                                            color: root.accentColor
                                            running: true
                                        }
                                    }

                                    // Title, info, progress bar
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.title || I18n.tr("Bài hát", "Track")
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            font.bold: true
                                            color: "#ffffff"
                                            elide: Text.ElideRight
                                        }

                                        // Progress Bar (Slim 3px)
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 3
                                            radius: 1.5
                                            color: Qt.rgba(1, 1, 1, 0.08)

                                            Rectangle {
                                                height: parent.height
                                                radius: 1.5
                                                color: root.accentColor
                                                width: parent.width * Math.min(1.0, Math.max(0.0, (modelData.progress || 0) / 100.0))
                                                Behavior on width { NumberAnimation { duration: 150 } }
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Text {
                                                text: Math.round(modelData.progress || 0) + "%"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                font.bold: true
                                                color: root.accentColor
                                            }

                                            Text {
                                                text: "•"
                                                font.pixelSize: 10
                                                color: Theme.textMuted
                                            }

                                            Text {
                                                text: (modelData.speed || "--")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                color: Theme.textSecondary
                                            }

                                            Item { Layout.fillWidth: true }

                                            Text {
                                                text: "ETA: " + (modelData.eta || "--")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                color: Theme.textMuted
                                            }
                                        }
                                    }

                                    // Cancel Button
                                    Rectangle {
                                        width: 24
                                        height: 24
                                        radius: 12
                                        color: cancelH.hovered ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                                        HoverHandler { id: cancelH }

                                        AppIcon {
                                            anchors.centerIn: parent
                                            source: "../assets/icons/window-close-symbolic.svg"
                                            iconSize: 11
                                            color: cancelH.hovered ? "#ff5252" : Theme.textMuted
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.dlMgr) root.dlMgr.cancel(modelData.videoId);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Section: Completed Downloads
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: root.completedTasks.length > 0

                        Text {
                            text: I18n.tr("ĐÃ HOÀN THÀNH GẦN ĐÂY (", "RECENTLY COMPLETED (") + root.completedTasks.length + ")"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: true
                            color: Theme.textMuted
                        }

                        Repeater {
                            model: root.completedTasks

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                height: 42
                                radius: 6
                                color: Qt.rgba(1, 1, 1, 0.02)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 8

                                    AppIcon {
                                        source: "../assets/icons/emblem-ok-symbolic.svg"
                                        iconSize: 14
                                        color: root.accentColor
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.title || I18n.tr("Bài hát", "Track")
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.bold: true
                                            color: "#ffffff"
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.artist || I18n.tr("Đã tải xong", "Downloaded")
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            color: Theme.textSecondary
                                            elide: Text.ElideRight
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
}
