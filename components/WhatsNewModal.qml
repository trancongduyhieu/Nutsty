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
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    property bool isOpen: false
    property bool closingGuard: false
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent
    property Item backgroundSourceItem: null
    property string versionString: (typeof win !== "undefined" && win.appVersion) ? win.appVersion : "1.0.4.2"
    property string customReleaseNotes: ""

    signal closeRequested()
    signal checkUpdateRequested()

    function openModal(notes) {
        closeTimer.stop();
        closingGuard = false;
        if (notes && typeof notes === "string") {
            root.customReleaseNotes = notes;
        } else {
            root.customReleaseNotes = "";
        }
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
        color: Qt.rgba(0, 0, 0, 0.62)

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeModal()
        }
    }

    // Modal Main Floating Card: LiquidGlass Resin Container (20px Radius)
    LiquidGlass {
        id: dialogCard
        width: Math.min(480, parent.width - 32)
        height: Math.min(540, parent.height - 48)
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
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

        // Deep Obsidian Frosted Foundation: Blocks text bleed-through
        Rectangle {
            anchors.fill: parent
            radius: dialogCard.radius
            color: Qt.rgba(0.05, 0.06, 0.09, 0.92)
            z: 1
        }

        // 1px Concentric Hairline Accent Border
        Rectangle {
            anchors.fill: parent
            radius: dialogCard.radius
            color: "transparent"
            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.32)
            border.width: 1
            z: 20
            Behavior on border.color { ColorAnimation { duration: 250 } }
        }

        // Prevent click-through
        MouseArea {
            anchors.fill: parent
            z: 2
            onClicked: mouse => { mouse.accepted = true; }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 16
            z: 5

            // =================================================================
            // HEADER: Icon + Title + Version Pill + Close Button
            // =================================================================
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    width: 36
                    height: 36
                    radius: 18
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                    border.width: 1

                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/emblem-favorite-symbolic.svg"
                        iconSize: 18
                        color: root.accentColor
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        spacing: 8

                        Text {
                            text: I18n.tr("Có gì mới trong Nutsty?", "What's new in Nutsty?")
                            font.family: Theme.fontFamily
                            font.pixelSize: 16
                            font.bold: true
                            color: "#ffffff"
                        }

                        // Version Pill Badge
                        Rectangle {
                            height: 20
                            width: verTxt.implicitWidth + 12
                            radius: 10
                            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                            border.width: 1

                            Text {
                                id: verTxt
                                anchors.centerIn: parent
                                text: "v" + root.versionString
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                color: root.accentColor
                            }
                        }
                    }

                    Text {
                        text: I18n.tr("Khám phá các tính năng và cải tiến vừa được phát hành", "Discover the latest features and architectural updates")
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.textSecondary
                    }
                }

                // Close Button ✕
                Rectangle {
                    width: 28
                    height: 28
                    radius: 14
                    color: closeMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.15) : Qt.rgba(255, 255, 255, 0.06)
                    border.color: Qt.rgba(255, 255, 255, 0.12)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeModal()
                    }
                }
            }

            // Hairline Divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(255, 255, 255, 0.08)
            }

            // =================================================================
            // BODY: Scrollable Feature Highlights List
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
                    ScrollBar.vertical: LiquidScrollBar {}

                    ColumnLayout {
                        id: contentCol
                        width: flick.width
                        spacing: 10

                        // Feature 1: Lyrics Romanization
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: f1Row.implicitHeight + 20
                            radius: 12
                            color: Qt.rgba(255, 255, 255, 0.04)
                            border.color: Qt.rgba(255, 255, 255, 0.08)
                            border.width: 1

                            RowLayout {
                                id: f1Row
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 12

                                Rectangle {
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36
                                    radius: 18
                                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.32)
                                    border.width: 1

                                    AppIcon {
                                        anchors.centerIn: parent
                                        source: "../assets/icons/view-lyrics-symbolic.svg"
                                        iconSize: 18
                                        color: root.accentColor
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    Text {
                                        text: I18n.tr("Phiên âm lời bài hát Latinh (Romanization)", "Lyrics Romanization (Romaji, Romaja, Pinyin)")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: "#ffffff"
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: I18n.tr("Tự động nhận diện và phiên âm Romaji (Nhật), Romaja (Hàn), Pinyin (Trung) cho toàn bộ bài hát; hiển thị dòng phát âm phụ thanh lịch dưới câu gốc trong Now Playing View và Desktop Lyrics.", "Automatic Latin-script pronunciation for Japanese, Korean, and Chinese lyrics without altering timings; renders an elegant secondary row in Now Playing and Desktop Lyrics.")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: "#a0a5b5"
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }

                        // Feature 2: Deep Obsidian LiquidGlass PlayerBar
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: f2Row.implicitHeight + 20
                            radius: 12
                            color: Qt.rgba(255, 255, 255, 0.04)
                            border.color: Qt.rgba(255, 255, 255, 0.08)
                            border.width: 1

                            RowLayout {
                                id: f2Row
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 12

                                Rectangle {
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36
                                    radius: 18
                                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.32)
                                    border.width: 1

                                    AppIcon {
                                        anchors.centerIn: parent
                                        source: "../assets/icons/preferences-system-symbolic.svg"
                                        iconSize: 18
                                        color: root.accentColor
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    Text {
                                        text: I18n.tr("Kính lỏng PlayerBar Deep Obsidian", "Deep Obsidian Frosted PlayerBar")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: "#ffffff"
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: I18n.tr("Bổ sung lớp đế sẫm màu chống lem chữ bên dưới khi cuộn danh sách bài hát; hiệu ứng khúc xạ quang học và phản xạ viền tinh tế, chuẩn xác theo ngôn ngữ thiết kế Dark Glass.", "Introduces a deep obsidian foundation eliminating background text bleed-through while scrolling; preserves pristine crystal edge refractions and chromatic rim salience.")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: "#a0a5b5"
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }

                        // Feature 3: MediaCoverSurface Unified Module
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: f3Row.implicitHeight + 20
                            radius: 12
                            color: Qt.rgba(255, 255, 255, 0.04)
                            border.color: Qt.rgba(255, 255, 255, 0.08)
                            border.width: 1

                            RowLayout {
                                id: f3Row
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 12

                                Rectangle {
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36
                                    radius: 18
                                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.32)
                                    border.width: 1

                                    AppIcon {
                                        anchors.centerIn: parent
                                        source: "../assets/icons/media-optical-audio-symbolic.svg"
                                        iconSize: 18
                                        color: root.accentColor
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    Text {
                                        text: I18n.tr("Hợp nhất Bề mặt Bìa & Sửa lỗi Ảnh Retina", "Unified MediaCoverSurface & HD Retina Art")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: "#ffffff"
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: I18n.tr("Đóng gói bề mặt bìa MediaCoverSurface chuẩn Deep Module; tự động bo tròn 16px video canvas Apple Music / Spotify không lem 4 góc, và khắc phục triệt để lỗi không load ảnh bìa Retina.", "Encapsulated MediaCoverSurface deep module; perfectly clips Apple Music & Spotify video canvas within 16px rounded corners with zero VRAM leaks, and resolves HD Retina artwork loading.")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: "#a0a5b5"
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }

                        // Feature 4: Sleep Timer Controller
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: f4Row.implicitHeight + 20
                            radius: 12
                            color: Qt.rgba(255, 255, 255, 0.04)
                            border.color: Qt.rgba(255, 255, 255, 0.08)
                            border.width: 1

                            RowLayout {
                                id: f4Row
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 12

                                Rectangle {
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36
                                    radius: 18
                                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.32)
                                    border.width: 1

                                    AppIcon {
                                        anchors.centerIn: parent
                                        source: "../assets/icons/sleep-timer-symbolic.svg"
                                        iconSize: 18
                                        color: root.accentColor
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    Text {
                                        text: I18n.tr("Bộ đếm Hẹn giờ ngủ Cosine Fade", "Smart Sleep Timer with Cosine Fade")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: "#ffffff"
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: I18n.tr("Tách rời bộ điều khiển hẹn giờ ngủ SleepTimerController; hẹn giờ tắt nhạc linh hoạt từ 15 đến 60 phút hoặc khi hết bài, hạ âm lượng êm dịu 5s trước khi dừng.", "Encapsulated SleepTimerController deep module; flexible countdown options with smooth 5-second cosine volume fade before pausing.")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: "#a0a5b5"
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Hairline Divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(255, 255, 255, 0.08)
            }

            // =================================================================
            // FOOTER: Primary Dismiss / Enjoy Button
            // =================================================================
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 10
                    color: btnMouse.containsMouse ? Qt.tint(root.accentColor, Qt.rgba(1, 1, 1, 0.15)) : root.accentColor
                    Behavior on color { ColorAnimation { duration: 120 } }

                    scale: btnMouse.pressed ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100 } }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        AppIcon {
                            source: "../assets/icons/emblem-ok-symbolic.svg"
                            iconSize: 14
                            color: "#000000"
                        }

                        Text {
                            text: I18n.tr("Đã hiểu, trải nghiệm ngay", "Got it, start listening")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: "#000000"
                        }
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
