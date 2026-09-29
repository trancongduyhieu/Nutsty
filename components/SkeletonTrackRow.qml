import QtQuick
import QtQuick.Layouts
import "."

Item {
    id: root
    Layout.fillWidth: true
    Layout.preferredHeight: isCompact ? 44 : 52
    implicitHeight: isCompact ? 44 : 52
    implicitWidth: 200
    height: isCompact ? 44 : 52

    property bool isCompact: false
    property int titleWidth: isCompact ? 110 : 200
    property int subtitleWidth: isCompact ? 75 : 120

    opacity: 0.40

    SequentialAnimation on opacity {
        loops: Animation.Infinite
        running: true
        NumberAnimation {
            from: 0.25
            to: 0.70
            duration: 800
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            from: 0.70
            to: 0.25
            duration: 800
            easing.type: Easing.InOutQuad
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: root.isCompact ? 6 : 12
        anchors.rightMargin: root.isCompact ? 6 : 16
        spacing: root.isCompact ? 10 : 14

        // 1. Cover Thumbnail Placeholder
        Rectangle {
            Layout.preferredWidth: root.isCompact ? 32 : 40
            Layout.preferredHeight: root.isCompact ? 32 : 40
            radius: 4
            color: Qt.rgba(1, 1, 1, 0.12)
        }

        // 2. Title & Subtitle Bars
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            // Title Bar
            Rectangle {
                Layout.preferredWidth: root.titleWidth
                Layout.maximumWidth: root.titleWidth
                Layout.preferredHeight: root.isCompact ? 11 : 13
                radius: 3
                color: Qt.rgba(1, 1, 1, 0.14)
            }

            // Subtitle Bar
            Rectangle {
                Layout.preferredWidth: root.subtitleWidth
                Layout.maximumWidth: root.subtitleWidth
                Layout.preferredHeight: root.isCompact ? 8 : 10
                radius: 2
                color: Qt.rgba(1, 1, 1, 0.08)
            }
        }

        Item { Layout.fillWidth: true }

        // 3. Duration Bar (Only in wide mode)
        Rectangle {
            visible: !root.isCompact
            Layout.preferredWidth: 36
            Layout.preferredHeight: 10
            radius: 2
            color: Qt.rgba(1, 1, 1, 0.08)
        }
    }
}
