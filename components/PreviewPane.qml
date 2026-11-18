import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    color: "transparent"

    property var item: null
    property bool isPlaying: false

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14

        // Large Album Art / Visual Cover Card
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: width
            radius: Theme.radiusSm
            color: Theme.bgDark
            border.color: Theme.border
            border.width: 1
            clip: true

            // Album art from URL if exists
            Image {
                id: albumImg
                sourceSize: Qt.size(512, 512)
                anchors.fill: parent
                source: root.item && root.item.image ? root.item.image : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }

            // Fallback: Vinyl / Music note graphic
            Item {
                anchors.fill: parent
                visible: !albumImg.visible

                // Animated vinyl circle
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.75
                    height: width
                    radius: width / 2
                    color: "#16161e"
                    border.color: root.isPlaying ? Theme.accent : Theme.border
                    border.width: 3

                    // Grooves
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.7
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.color: Theme.divider
                        border.width: 1
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.4
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.color: Theme.divider
                        border.width: 1
                    }

                    // Center label
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.25
                        height: width
                        radius: width / 2
                        color: Theme.accentSoft
                        border.color: Theme.accent
                        border.width: 1

                        AppIcon {
                            anchors.centerIn: parent
                            source: "../assets/icons/audio-only-symbolic.svg"
                            iconSize: 16
                            color: Theme.accent
                        }
                    }

                    NumberAnimation on rotation {
                        from: 0
                        to: 360
                        duration: 8000
                        loops: Animation.Infinite
                        running: root.isPlaying
                    }
                }
            }
        }

        // Song Title
        Text {
            Layout.fillWidth: true
            text: root.item ? root.item.name : I18n.tr("Chưa chọn bài hát", "No track selected")
            color: Theme.text
            font.pixelSize: 16
            font.bold: true
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        // Artist Name
        Text {
            Layout.fillWidth: true
            text: root.item ? root.item.artist : I18n.tr("Nutsty ngoại tuyến", "Nutsty Offline")
            color: Theme.teal
            font.pixelSize: 13
            font.bold: true
            elide: Text.ElideRight
        }

        // Album & Source details
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.divider
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Text { text: I18n.tr("Nguồn:", "Source:"); color: Theme.subtext; font.pixelSize: 11 }
                Item { Layout.fillWidth: true }
                Text { text: root.item ? root.item.source : I18n.tr("Không có", "None"); color: Theme.text; font.pixelSize: 11; font.bold: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Text { text: I18n.tr("Thời lượng:", "Duration:"); color: Theme.subtext; font.pixelSize: 11 }
                Item { Layout.fillWidth: true }
                Text { text: root.item ? root.item.duration : "0:00"; color: Theme.green; font.pixelSize: 11; font.family: "monospace" }
            }

            RowLayout {
                Layout.fillWidth: true
                Text { text: I18n.tr("Định dạng:", "Format:"); color: Theme.subtext; font.pixelSize: 11 }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.item && root.item.path ? root.item.path.split('.').pop().toUpperCase() : I18n.tr("ÂM THANH", "AUDIO")
                    color: Theme.teal
                    font.pixelSize: 11
                    font.bold: true
                }
            }
        }

        Item { Layout.fillHeight: true }

        // Audio Engine Status
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            radius: Theme.radiusSm
            color: Theme.glassSoft
            border.color: Theme.border
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                AppIcon { source: "../assets/icons/process-working-symbolic.svg"; color: Theme.accent; iconSize: 14 }
                Text {
                    text: I18n.tr("Bộ phát không suy hao (MPV)", "Lossless engine (MPV)")
                    color: Theme.text
                    font.pixelSize: 11
                }
            }
        }
    }
}
