import QtQuick
import QtQuick.Layouts
import "."

Rectangle {
    id: root

    property string text: I18n.tr("Phát ngẫu nhiên", "Shuffle")
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent
    property int iconSize: 15
    property string iconSource: "../assets/icons/media-playlist-shuffle-symbolic.svg"
    property bool hasTracks: true

    signal clicked()

    implicitHeight: 38
    implicitWidth: btnRow.implicitWidth + 28
    radius: height / 2

    // Dynamic Chromatic Salience: Absorbs accent color instead of dead gray/black
    color: {
        if (!root.enabled || !root.hasTracks) return Qt.rgba(255, 255, 255, 0.04);
        if (mouseArea.pressed) return Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.30);
        if (mouseArea.containsMouse) return Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22);
        return Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12);
    }

    border.color: {
        if (!root.enabled || !root.hasTracks) return Qt.rgba(255, 255, 255, 0.08);
        return Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, mouseArea.containsMouse ? 0.45 : 0.22);
    }
    border.width: 1

    opacity: (root.enabled && root.hasTracks) ? 1.0 : 0.45
    scale: (root.enabled && root.hasTracks && mouseArea.containsMouse) ? 1.02 : 1.0

    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }
    Behavior on scale { NumberAnimation { duration: 100 } }
    Behavior on opacity { NumberAnimation { duration: 150 } }

    Row {
        id: btnRow
        anchors.centerIn: parent
        spacing: 8

        AppIcon {
            anchors.verticalCenter: parent.verticalCenter
            source: root.iconSource
            iconSize: root.iconSize
            color: (root.enabled && root.hasTracks) ? "#ffffff" : Theme.textMuted
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.bold: true
            color: (root.enabled && root.hasTracks) ? "#ffffff" : Theme.textMuted
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: (root.enabled && root.hasTracks) ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.enabled && root.hasTracks) {
                root.clicked();
            }
        }
    }
}
