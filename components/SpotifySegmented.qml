import QtQuick
import "."

// Segmented picker of the Spotify sync section, same look as the Lite mode picker in Settings:
// accent 12% capsule track, a filled pill that slides to the choice. `labels` are already translated.
// Own file, not an inline component: Quickshell hot reload cannot resolve an inline component added later.
Rectangle {
    id: seg
    property var labels: []
    property int currentIndex: 0
    property color accentColor: Theme.accent
    signal picked(int index)

    // white on a light accent (pale gold) washes out: dark text on the filled pill then
    readonly property color pillText: (0.299 * accentColor.r + 0.587 * accentColor.g + 0.114 * accentColor.b) > 0.6
                                      ? Qt.rgba(0, 0, 0, 0.85) : "#ffffff"
    readonly property real segW: {
        var w = 56;
        for (var i = 0; i < seg.labels.length; i++) w = Math.max(w, metrics.advanceWidth(seg.labels[i]) + 28);
        return w;
    }

    FontMetrics { id: metrics; font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold }

    width: segW * labels.length + 6
    height: 32
    radius: 16
    color: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.12)

    Rectangle {
        x: 3 + seg.currentIndex * seg.segW
        y: 3
        width: seg.segW
        height: parent.height - 6
        radius: height / 2
        color: seg.accentColor
        Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
    }

    Row {
        x: 3
        y: 3
        Repeater {
            model: seg.labels
            delegate: Item {
                id: cell
                required property string modelData
                required property int index
                readonly property bool selected: index === seg.currentIndex
                width: seg.segW
                height: seg.height - 6

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: seg.accentColor
                    opacity: !cell.selected && cellMouse.containsMouse ? 0.16 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }

                Text {
                    anchors.centerIn: parent
                    text: cell.modelData
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: cell.selected ? Font.DemiBold : Font.Normal
                    color: cell.selected ? seg.pillText : "#ffffff"
                    opacity: cell.selected ? 1.0 : 0.72
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }

                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (!cell.selected) seg.picked(cell.index)
                }
            }
        }
    }
}
