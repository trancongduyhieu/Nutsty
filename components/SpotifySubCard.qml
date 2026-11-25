import QtQuick
import QtQuick.Layouts
import "."

// One option row inside a SpotifySettingCard: text on the left, a control (trailing) on the right.
// Flat like the other Settings rows; a faint accent tint shows only on hover of a clickable row (rose when danger).
// Own file, not an inline component: Quickshell hot reload cannot resolve an inline component added later.
Rectangle {
    id: sub
    property string title: ""
    property string description: ""
    property bool danger: false
    property bool clickable: false
    // the title is a working verb ("Đang đồng bộ..."): a band of light sweeps it, as ShimmerText does elsewhere
    property bool shimmer: false
    property color accentColor: Theme.accent
    default property alias trailing: trailingSlot.data
    signal clicked()

    readonly property color tone: danger ? Qt.rgba(244 / 255, 63 / 255, 94 / 255, 1.0) : accentColor

    Layout.fillWidth: true
    implicitHeight: Math.max(44, textCol.implicitHeight + 16)
    radius: 10
    color: danger ? Qt.rgba(tone.r, tone.g, tone.b, 0.12)
                  : Qt.rgba(tone.r, tone.g, tone.b, clickable && subMouse.containsMouse ? 0.10 : 0.0)
    Behavior on color { ColorAnimation { duration: 140 } }

    MouseArea {
        id: subMouse
        anchors.fill: parent
        enabled: sub.clickable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: sub.clicked()
    }

    Column {
        id: textCol
        anchors.left: parent.left
        anchors.leftMargin: danger ? 12 : 0
        anchors.right: trailingSlot.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        ShimmerText {
            visible: sub.shimmer
            running: visible
            text: sub.title
            pixelSize: 13
            fontWeight: Font.Bold
            letterSpacing: 0
        }

        Text {
            visible: !sub.shimmer
            width: parent.width
            text: sub.title
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.bold: true
            color: sub.danger ? "#fda4af" : Theme.textPrimary
            wrapMode: Text.WordWrap
        }

        Text {
            width: parent.width
            visible: sub.description !== ""
            text: sub.description
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.textSecondary
            elide: Text.ElideRight
        }
    }

    Item {
        id: trailingSlot
        anchors.right: parent.right
        anchors.rightMargin: sub.danger ? 10 : 0
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
}
