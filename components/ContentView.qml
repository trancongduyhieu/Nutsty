import QtQuick.Controls.Basic
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    color: "transparent"

    property var tracks: []
    property int cursorIndex: 0
    property string currentTrackPath: ""
    property bool isPlaying: false

    signal trackClicked(int index, var track)
    signal cursorChanged(int index, var track)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // Table Header
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            Layout.leftMargin: 8
            Layout.rightMargin: 12
            spacing: 10

            Text {
                text: "#"
                color: Theme.subtext
                font.pixelSize: 11
                Layout.preferredWidth: 28
            }

            Text {
                text: I18n.tr("TIÊU ĐỀ", "TITLE")
                color: Theme.subtext
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 0.5
                Layout.fillWidth: true
            }

            Text {
                text: I18n.tr("NGUỒN", "SOURCE")
                color: Theme.subtext
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 0.5
                Layout.preferredWidth: 90
            }

            Text {
                text: I18n.tr("T.GIAN", "TIME")
                color: Theme.subtext
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 0.5
                Layout.preferredWidth: 44
                horizontalAlignment: Text.AlignRight
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.divider
        }

        // Tracks Scrollable List
        ListView {
            id: trackListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: root.tracks

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            delegate: Rectangle {
                id: row
                width: trackListView.width
                height: 36
                radius: Theme.radiusXs

                property bool isCurrent: modelData.path === root.currentTrackPath
                property bool isOnCursor: index === root.cursorIndex

                color: isOnCursor ? (isCurrent ? Theme.sel : Theme.selDim)
                                  : (rowHover.hovered ? Theme.glassSoft : "transparent")

                Behavior on color { ColorAnimation { duration: 100 } }

                HoverHandler { id: rowHover }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 12
                    spacing: 10

                    // Number or Play indicator
                    Item {
                        Layout.preferredWidth: 28
                        Layout.fillHeight: true

                        AppIcon {
                            anchors.centerIn: parent
                            visible: row.isCurrent
                            iconSize: 12
                            source: root.isPlaying ? "../assets/icons/media-playback-start-symbolic.svg" : "../assets/icons/media-playback-pause-symbolic.svg"
                            color: row.isOnCursor ? Theme.selText : Theme.accent
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !row.isCurrent
                            text: String(index + 1)
                            color: row.isOnCursor ? Theme.selText : (row.isCurrent ? Theme.accent : Theme.subtext)
                            font.pixelSize: 12
                            font.bold: row.isCurrent
                        }
                    }

                    // Track Title & Artist
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: modelData.name
                            color: row.isOnCursor ? Theme.selText : (row.isCurrent ? Theme.accent : Theme.text)
                            font.pixelSize: 13
                            font.bold: row.isCurrent
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.artist
                            color: row.isOnCursor ? Theme.selText : Theme.subtext
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    // Source Badge
                    Rectangle {
                        Layout.preferredWidth: 84
                        Layout.preferredHeight: 18
                        radius: 4
                        color: modelData.source === "Nutsty Music" ? Qt.rgba(168/255, 85/255, 247/255, 0.2) : Qt.rgba(56/255, 189/255, 248/255, 0.2)
                        border.color: modelData.source === "Nutsty Music" ? "#a855f7" : "#38bdf8"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: modelData.source
                            color: modelData.source === "Nutsty Music" ? "#d8b4fe" : "#7dd3fc"
                            font.pixelSize: 9
                            font.bold: true
                        }
                    }

                    // Duration
                    Text {
                        Layout.preferredWidth: 44
                        text: modelData.duration || "0:00"
                        color: row.isOnCursor ? Theme.selText : Theme.green
                        font.pixelSize: 11
                        font.family: "monospace"
                        horizontalAlignment: Text.AlignRight
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.cursorIndex = index;
                        root.cursorChanged(index, modelData);
                        root.trackClicked(index, modelData);
                    }
                }
            }

            // Empty state
            Text {
                anchors.centerIn: parent
                visible: root.tracks.length === 0
                text: I18n.tr("Không có bài hát nào trong mục này.", "There are no tracks in this section.")
                color: Theme.subtext
                font.pixelSize: 13
            }
        }
    }
}
