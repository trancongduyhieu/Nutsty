import QtQuick
import QtQuick.Layouts
import "."
import "lossless_logic.js" as LosslessLogic

// Shown when the user turns lossless on: what changes, and how audio reaches the DAC.
Item {
    id: root
    anchors.fill: parent
    z: 10008
    visible: opacity > 0.001
    opacity: isOpen ? 1.0 : 0.0
    enabled: isOpen
    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    property bool isOpen: false
    property bool isWindows: Qt.platform.os === "windows"
    property string selectedMode: "shared"
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent
    property Item backgroundSourceItem: null

    signal accepted(string dacMode)
    signal dismissed()

    function openModal(mode) {
        var modes = LosslessLogic.dacModesFor(root.isWindows);
        root.selectedMode = modes.indexOf(mode) >= 0 ? mode : "shared";
        root.isOpen = true;
    }

    function close(accept) {
        root.isOpen = false;
        if (accept) root.accepted(root.selectedMode);
        else root.dismissed();
    }

    readonly property var points: [
        I18n.tr("Bài tìm được trên Tidal sẽ phát FLAC. Bài không có trên Tidal vẫn phát bản YouTube như cũ.",
                "Songs found on Tidal play in FLAC. Songs missing on Tidal still play from YouTube."),
        I18n.tr("Thanh phát hiện chất lượng thật của bài đang nghe.",
                "The player bar shows the real quality of the song."),
        I18n.tr("Dùng nhiều dữ liệu mạng hơn: khoảng 30-50 MB mỗi bài thay vì 3-5 MB.",
                "Uses more data: about 30-50 MB per song instead of 3-5 MB."),
        I18n.tr("Khi Nghe Cùng, Nutsty tạm phát bản YouTube để hai bên nghe khớp nhau, rồi bật lại lossless khi dừng.",
                "While Listening Along, Nutsty plays the YouTube version so you both stay in sync, then lossless comes back when you stop."),
        I18n.tr("Bài đã tải về máy vẫn phát bản đã tải.",
                "Downloaded songs keep playing the downloaded file.")
    ]

    readonly property var modeInfo: ({
        shared: { name: I18n.tr("Qua hệ thống", "Through the system"),
                  desc: I18n.tr("Giữ mọi tính năng. Vẫn là FLAC nhưng hệ thống có thể chuyển tần số trước khi tới DAC.",
                                "Keeps every feature. Still FLAC, but the system may change the sample rate before the DAC.") },
        rate_match: { name: I18n.tr("Đúng tần số gốc", "Original sample rate"),
                      desc: I18n.tr("Giữ AutoMix. Trong vài giây chuyển bài, tần số có thể bị chuyển đổi tạm thời.",
                                    "Keeps AutoMix. For a few seconds between songs the sample rate may be converted.") },
        exclusive: { name: I18n.tr("Nguyên bản tuyệt đối", "Fully bit-perfect"),
                     desc: I18n.tr("Tắt AutoMix, âm lượng trong app cố định 100%, app khác không phát được tiếng qua DAC.",
                                   "Turns AutoMix off, fixes in-app volume at 100%, and other apps cannot play through the DAC.") }
    })

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.58)
        MouseArea { anchors.fill: parent; onClicked: root.close(false) }
    }

    LiquidGlass {
        id: card
        width: Math.min(480, root.width - 48)
        height: Math.min(content.implicitHeight + 44, root.height - 48)
        anchors.centerIn: parent
        radius: 20
        displacement: 22.0
        aberration: 0.03
        bevelWidth: 26.0
        tintColor: Qt.rgba(0.04, 0.05, 0.08, 0.92)
        backgroundSourceItem: root.backgroundSourceItem
        isFlowActive: false
        clip: true
        scale: root.isOpen ? 1.0 : 0.94
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Rectangle { anchors.fill: parent; radius: card.radius; color: Qt.rgba(0.04, 0.05, 0.08, 0.82); z: 1 }
        Rectangle { anchors.fill: parent; radius: card.radius; color: "transparent"; border.color: Qt.rgba(1, 1, 1, 0.18); border.width: 1; z: 20 }
        MouseArea { anchors.fill: parent; z: 2; onClicked: mouse => { mouse.accepted = true; } }

        Flickable {
            anchors.fill: parent
            anchors.margins: 22
            contentHeight: content.implicitHeight
            clip: true
            z: 5

            ColumnLayout {
                id: content
                width: parent.width
                spacing: 12

                RowLayout {
                    spacing: 10
                    AppIcon {
                        source: "../assets/icons/audio-only-symbolic.svg"
                        iconSize: 18
                        color: root.accentColor
                    }
                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Bật lossless", "Turn on lossless")
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.bold: true
                        color: Theme.textPrimary
                    }
                }

                Repeater {
                    model: root.points
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 6
                            width: 5; height: 5; radius: 2.5
                            color: root.accentColor
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData
                            wrapMode: Text.WordWrap
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.textSecondary
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    text: I18n.tr("Cách đưa âm thanh tới DAC", "How audio reaches your DAC")
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                    color: Theme.textPrimary
                }

                Repeater {
                    model: LosslessLogic.dacModesFor(root.isWindows)
                    delegate: Rectangle {
                        readonly property bool active: root.selectedMode === modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: modeCol.implicitHeight + 20
                        radius: 12
                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b,
                                       active ? 0.22 : (modeMouse.containsMouse ? 0.12 : 0.06))
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, active ? 0.55 : 0.18)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Column {
                            id: modeCol
                            anchors.left: parent.left
                            anchors.right: modeCheck.left
                            anchors.margins: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Text {
                                width: parent.width
                                text: root.modeInfo[modelData].name
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                                color: "#ffffff"
                            }
                            Text {
                                width: parent.width
                                text: root.modeInfo[modelData].desc
                                wrapMode: Text.WordWrap
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.textSecondary
                            }
                        }
                        AppIcon {
                            id: modeCheck
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            source: "../assets/icons/emblem-ok-symbolic.svg"
                            iconSize: 12
                            color: root.accentColor
                            opacity: parent.active ? 1 : 0
                        }
                        MouseArea {
                            id: modeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedMode = modelData
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.isWindows
                    text: I18n.tr("Windows không đổi được tần số theo từng bài khi dùng chung thiết bị, nên muốn đúng tần số gốc phải chọn Nguyên bản tuyệt đối và chấp nhận tắt AutoMix.",
                                  "Windows cannot follow each song's sample rate on a shared device, so the original rate needs Fully bit-perfect, which turns AutoMix off.")
                    wrapMode: Text.WordWrap
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.textSecondary
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 10
                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredHeight: 34
                        Layout.preferredWidth: laterText.implicitWidth + 28
                        radius: 10
                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, laterMouse.containsMouse ? 0.16 : 0.08)
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25)
                        border.width: 1
                        Text {
                            id: laterText
                            anchors.centerIn: parent
                            text: I18n.tr("Để sau", "Later")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: "#ffffff"
                        }
                        MouseArea { id: laterMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.close(false) }
                    }

                    Rectangle {
                        Layout.preferredHeight: 34
                        Layout.preferredWidth: okText.implicitWidth + 28
                        radius: 10
                        color: okMouse.containsMouse ? Qt.lighter(root.accentColor, 1.15) : root.accentColor
                        Text {
                            id: okText
                            anchors.centerIn: parent
                            text: I18n.tr("Bật lossless", "Turn on lossless")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                            color: "#ffffff"
                        }
                        MouseArea { id: okMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.close(true) }
                    }
                }
            }
        }
    }
}
