import QtQuick
import QtQuick.Layouts
import "."

Rectangle {
    id: root
    width: 176
    height: 250
    radius: Theme.radiusCard
    color: Theme.bgCard

    property real titleWidth: 120
    property real subtitleWidth: 80

    // Smooth pulsing shimmer animation
    SequentialAnimation on opacity {
        running: root.visible && root.opacity > 0.01
        loops: Animation.Infinite
        NumberAnimation { from: 0.25; to: 0.70; duration: 750; easing.type: Easing.InOutQuad }
        NumberAnimation { from: 0.70; to: 0.25; duration: 750; easing.type: Easing.InOutQuad }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        // 1. Square Artwork Placeholder (148x148)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: width
            radius: 6
            color: "#282828"
        }

        // 2. Title Placeholder Bar
        Rectangle {
            Layout.preferredWidth: Math.min(root.titleWidth, parent.width)
            Layout.preferredHeight: 14
            radius: 4
            color: "#383838"
        }

        // 3. Subtitle / Artist Placeholder Bar
        Rectangle {
            Layout.preferredWidth: Math.min(root.subtitleWidth, parent.width * 0.7)
            Layout.preferredHeight: 12
            radius: 4
            color: "#282828"
        }

        Item { Layout.fillHeight: true }
    }
}
