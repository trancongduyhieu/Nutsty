import QtQuick
import "."

Item {
    id: root
    clip: true
    default property alias contentData: contentContainer.data

    implicitWidth: contentContainer.childrenRect.width
    implicitHeight: contentContainer.childrenRect.height

    property bool isWindowEffectivelyActive: (typeof win === "undefined" || !win || Boolean(win.isWindowEffectivelyActive))
    property real wavePhase: 0.0
    property int waveDuration: 1800

    // Single unified wave animation driving the horizontal sheen across all child bones
    NumberAnimation on wavePhase {
        running: root.visible && root.isWindowEffectivelyActive
        loops: Animation.Infinite
        from: 0.0
        to: 1.0
        duration: root.waveDuration
        easing.type: Easing.Linear
    }

    Item {
        id: contentContainer
        anchors.fill: parent
    }

    // Soft horizontal sheen band overlay (zero FBO allocation, zero layout re-render)
    Rectangle {
        id: sheenBand
        width: Math.max(160, Math.min(360, root.width * 0.35))
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        x: -width + root.wavePhase * (root.width + width * 2)
        visible: root.visible && root.isWindowEffectivelyActive
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.rgba(1.0, 1.0, 1.0, 0.10) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
}
