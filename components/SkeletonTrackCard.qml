import QtQuick
import QtQuick.Layouts
import "."

Rectangle {
    id: root
    width: 176
    height: 250
    radius: Theme.radiusCard
    clip: true
    color: Theme.bgCard

    property real titleWidth: 120
    property real subtitleWidth: 80

    opacity: 0.65
    border.width: 1
    border.color: Qt.rgba(255, 255, 255, 0.05)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        // 1. Square Artwork Placeholder (148x148)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: width
            radius: 6
            color: Qt.rgba(255, 255, 255, 0.08)
        }

        // 2. Title Placeholder Bar
        Rectangle {
            Layout.preferredWidth: Math.min(root.titleWidth, parent.width)
            Layout.preferredHeight: 14
            radius: 4
            color: Qt.rgba(255, 255, 255, 0.12)
        }

        // 3. Subtitle / Artist Placeholder Bar
        Rectangle {
            Layout.preferredWidth: Math.min(root.subtitleWidth, parent.width * 0.7)
            Layout.preferredHeight: 12
            radius: 4
            color: Qt.rgba(255, 255, 255, 0.06)
        }

        Item { Layout.fillHeight: true }
    }
}
