import QtQuick
import "."

// Frosted liquid glass panel shared by the playlist picker, New playlist and Make a cover: the page behind is
// blurred out of reading, the rim bends it, and a thin wash, a hairline and a top highlight sit over it.
// `glassSource` is the item to sample (masterAppSurface); lite mode or no source draws `ground` as a plain fill.
// Own file, not an inline component: Quickshell hot reload cannot resolve an inline component added later.
LiquidGlass {
    id: panel

    property Item glassSource: null
    property bool liteMode: false
    property color ground: Qt.rgba(0.07, 0.07, 0.09, 1)
    readonly property bool glassOn: !panel.liteMode && !!panel.glassSource

    radius: 24
    displacement: 30.0
    aberration: 0.06
    bevelWidth: 30.0
    blurRadius: 1.1
    frost: 40
    opaque: true
    isFlowActive: false
    backgroundSourceItem: panel.glassOn ? panel.glassSource : null
    tintColor: Qt.rgba(panel.ground.r, panel.ground.g, panel.ground.b, panel.glassOn ? 0.40 : 0.96)

    // Readability wash under the content, kept light so the glass reads bright
    Rectangle {
        anchors.fill: parent
        radius: panel.radius
        visible: panel.glassOn
        color: Qt.rgba(0.02, 0.02, 0.04, 0.22)
        z: -1
    }
    // Hairline, a touch brighter along the top edge where light hits the glass
    Rectangle {
        anchors.fill: parent
        radius: panel.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.18)
        z: 20
    }
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 2 * panel.radius
        height: 1
        z: 21
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.40) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
        }
    }
}
