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
        color: Qt.rgba(0, 0, 0, 0.58)

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeModal()
        }
    }

    // Modal Main Floating Card: LiquidGlass Resin Container (Planar Minimalist - Clean White Space)
    LiquidGlass {
        id: dialog
        width: Math.min(460, parent.width - 32)
        height: Math.min(550, parent.height - 48)
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
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        // Shaded Tint Overlay: Ensures effortless text contrast over background music cards
        Rectangle {
            anchors.fill: parent
            radius: dialog.radius
            color: Qt.rgba(0.04, 0.05, 0.08, 0.88)
            z: 1
        }

        // 1px Hairline Border: Keo 502 Surface Tension Rim
        Rectangle {
            anchors.fill: parent
            radius: dialog.radius
            color: "transparent"
            border.color: Qt.rgba(255, 255, 255, 0.18)
            border.width: 1
            z: 20
        }

        // Intercept clicks inside dialog
        MouseArea {
            anchors.fill: parent
            z: 2
            onClicked: mouse => { mouse.accepted = true; }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 12
            z: 5

            // =================================================================
            // Header Row: Title + Version Badge & Close Button (SettingsModal Parity)
            // =================================================================
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32

                RowLayout {
                    spacing: 8
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        text: I18n.tr("Điểm mới", "What's New")
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    // Version Tag Badge
                    Rectangle {
                        height: 18
                        width: verTagTxt.implicitWidth + 10
                        radius: 4
                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                        border.width: 1
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.40)

                        Text {
                            id: verTagTxt
                            anchors.centerIn: parent
                            text: "v" + (root.versionString || "1.0.4.2")
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: true
                            color: root.accentColor
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Close Button Circle (Exact SettingsModal Parity)
                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: closeHover.hovered ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.05)
                    border.color: closeHover.hovered ? Qt.rgba(255, 255, 255, 0.16) : Qt.rgba(255, 255, 255, 0.08)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }

                    HoverHandler { id: closeHover }

                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/window-close-symbolic.svg"
                        iconSize: 12
                        color: closeHover.hovered ? "#ffffff" : Theme.textSecondary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeModal()
                    }
                }
            }

            // Subtitle
            Text {
                text: I18n.tr("Phiên bản v" + root.versionString + " bao gồm các tính năng và cải tiến sau:", "Version v" + root.versionString + " includes the following highlights:")
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.textSecondary
            }

            // =================================================================
            // Body: Planar List of Highlights (Clean whitespace, no dividers, no scrollbar)
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

                    ColumnLayout {
                        id: contentCol
                        width: flick.width
                        spacing: 12

                        // Item 1: Romanization
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            RowLayout {
                                spacing: 8

                                Rectangle {
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: root.accentColor
                                }

                                Text {
                                    text: I18n.tr("Phiên âm lời bài hát Latinh (Romanization)", "Lyrics Romanization (Romaji, Romaja, Pinyin)")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.bold: true
                                    color: Theme.textPrimary
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: I18n.tr("Tự động nhận diện và phiên âm Romaji (Nhật), Romaja (Hàn), Pinyin (Trung) cho toàn bộ bài hát; hiển thị dòng phát âm phụ thanh lịch dưới câu gốc trong Now Playing View và Desktop Lyrics.", "Automatic Latin-script pronunciation for Japanese, Korean, and Chinese lyrics without altering timings; renders an elegant secondary row in Now Playing and Desktop Lyrics.")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.textSecondary
                                wrapMode: Text.WordWrap
                                Layout.leftMargin: 14
                            }
                        }

                        // Item 2: Deep Obsidian PlayerBar
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            RowLayout {
                                spacing: 8

                                Rectangle {
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: root.accentColor
                                }

                                Text {
                                    text: I18n.tr("Kính lỏng PlayerBar Deep Obsidian", "Deep Obsidian Frosted PlayerBar")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.bold: true
                                    color: Theme.textPrimary
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: I18n.tr("Bổ sung lớp đế sẫm màu chống lem chữ bên dưới khi cuộn danh sách bài hát; hiệu ứng khúc xạ quang học và phản xạ viền tinh tế, chuẩn xác theo ngôn ngữ thiết kế Dark Glass.", "Introduces a deep obsidian foundation eliminating background text bleed-through while scrolling; preserves pristine crystal edge refractions and chromatic rim salience.")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.textSecondary
                                wrapMode: Text.WordWrap
                                Layout.leftMargin: 14
                            }
                        }

                        // Item 3: MediaCoverSurface Unified Module
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            RowLayout {
                                spacing: 8

                                Rectangle {
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: root.accentColor
                                }

                                Text {
                                    text: I18n.tr("Hợp nhất Bề mặt Bìa & Sửa lỗi Ảnh Retina", "Unified MediaCoverSurface & HD Retina Art")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.bold: true
                                    color: Theme.textPrimary
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: I18n.tr("Đóng gói bề mặt bìa MediaCoverSurface chuẩn Deep Module; tự động bo tròn 16px video canvas Apple Music / Spotify không lem 4 góc, và khắc phục triệt để lỗi không load ảnh bìa Retina.", "Encapsulated MediaCoverSurface deep module; perfectly clips Apple Music & Spotify video canvas within 16px rounded corners with zero VRAM leaks, and resolves HD Retina artwork loading.")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.textSecondary
                                wrapMode: Text.WordWrap
                                Layout.leftMargin: 14
                            }
                        }

                        // Item 4: Sleep Timer Controller
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            RowLayout {
                                spacing: 8

                                Rectangle {
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: root.accentColor
                                }

                                Text {
                                    text: I18n.tr("Bộ đếm Hẹn giờ ngủ Cosine Fade", "Smart Sleep Timer with Cosine Fade")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.bold: true
                                    color: Theme.textPrimary
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: I18n.tr("Tách rời bộ điều khiển hẹn giờ ngủ SleepTimerController; hẹn giờ tắt nhạc linh hoạt từ 15 đến 60 phút hoặc khi hết bài, hạ âm lượng êm dịu 5s trước khi dừng.", "Encapsulated SleepTimerController deep module; flexible countdown options with smooth 5-second cosine volume fade before pausing.")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.textSecondary
                                wrapMode: Text.WordWrap
                                Layout.leftMargin: 14
                            }
                        }
                    }
                }
            }

            // =================================================================
            // Footer: Clean Action Button (Exact SettingsModal Parity)
            // =================================================================
            RowLayout {
                Layout.fillWidth: true

                Item { Layout.fillWidth: true }

                Rectangle {
                    height: 28
                    width: btnText.implicitWidth + 24
                    radius: 6
                    color: btnMouse.containsMouse
                           ? Qt.tint(root.accentColor, Qt.rgba(1, 1, 1, 0.15))
                           : root.accentColor
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        id: btnText
                        anchors.centerIn: parent
                        text: I18n.tr("Đã hiểu", "Got it")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                        color: "#000000"
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
