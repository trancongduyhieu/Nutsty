import QtQuick.Controls.Basic
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    color: "transparent"

    property var playlists: []
    property int selectedIndex: 0

    signal playlistSelected(int index, var playlist)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        // App Branding / Header
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            Layout.leftMargin: 6
            spacing: 8

            AppIcon {
                source: "../assets/icons/nutsty-outline-symbolic.svg"
                iconSize: 18
                color: Theme.accent
            }

            Text {
                text: "Nutsty"
                color: Theme.text
                font.pixelSize: 15
                font.bold: true
                font.letterSpacing: 0.5
            }

            Rectangle {
                Layout.preferredWidth: 42
                Layout.preferredHeight: 18
                radius: 4
                color: Theme.accentSoft
                border.color: Theme.accent
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: I18n.tr("NGOẠI TUYẾN", "OFFLINE")
                    color: Theme.accent
                    font.pixelSize: 8
                    font.bold: true
                }
            }
        }

        // Section Label
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.topMargin: 6
            text: I18n.tr("DANH SÁCH PHÁT", "PLAYLISTS")
            color: Theme.subtext
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 1.2
        }

        // Playlists List
        ListView {
            id: plView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 3
            model: root.playlists

            delegate: Rectangle {
                id: plRow
                width: plView.width
                height: 34
                radius: Theme.radiusSm
                property bool isSelected: index === root.selectedIndex

                color: isSelected ? Theme.sel
                                  : (plHover.hovered ? Theme.glassSoft : "transparent")

                Behavior on color { ColorAnimation { duration: 120 } }

                HoverHandler { id: plHover }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    AppIcon {
                        source: modelData.pinned ? "../assets/icons/emblem-favorite-symbolic.svg"
                            : (modelData.id === "all" ? "../assets/icons/audio-only-symbolic.svg"
                            : (modelData.id === "simp" ? "../assets/icons/media-optical-audio-symbolic.svg"
                            : (modelData.id === "downloads" ? "../assets/icons/download-symbolic.svg" : "../assets/icons/favorite-border-symbolic.svg")))
                        color: plRow.isSelected ? Theme.selText : Theme.teal
                        iconSize: 14
                    }

                    Text {
                        Layout.fillWidth: true
                        text: modelData.name
                        color: plRow.isSelected ? Theme.selText : Theme.text
                        font.pixelSize: 13
                        font.bold: plRow.isSelected
                        elide: Text.ElideRight
                    }

                    Text {
                        text: String(modelData.count || 0)
                        color: plRow.isSelected ? Theme.selText : Theme.subtext
                        font.pixelSize: 11
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.selectedIndex = index;
                        root.playlistSelected(index, modelData);
                    }
                }
            }
        }

        // Bottom shortcut card
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            radius: Theme.radiusSm
            color: Theme.glassSoft
            border.color: Theme.border
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 2

                Text {
                    text: I18n.tr("Phím tắt", "Shortcuts")
                    color: Theme.teal
                    font.pixelSize: 11
                    font.bold: true
                }
                Text {
                    text: I18n.tr("Space: Phát/Dừng • Lên/Xuống: Chọn bài", "Space: Play/Pause • Up/Down: Pick a track")
                    color: Theme.subtext
                    font.pixelSize: 10
                }
            }
        }
    }
}
