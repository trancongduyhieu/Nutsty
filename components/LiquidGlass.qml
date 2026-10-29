import QtQuick
import QtQuick.Effects
import "."

Item {
    id: root

    // =========================================================================
    // Properties & Configuration (SimpMusic Liquid Glass Formula)
    // =========================================================================
    property Item backgroundSourceItem: null
    property real radius: 16
    property real displacement: 22.0
    property real aberration: 0.04
    property real bevelWidth: 20.0
    property real blurRadius: 2.0
    property real colorBleed: 0.45
    property color tintColor: Qt.rgba(0.12, 0.14, 0.18, 0.45)
    property bool interactive: false
    property real extraDependency: 0.0

    default property alias contentData: contentContainer.data

    implicitWidth: 160
    implicitHeight: 48

    property bool isFlowActive: false
    property real flowProgress: isFlowActive ? 1.0 : 0.0
    Behavior on flowProgress { NumberAnimation { duration: 950; easing.type: Easing.InOutQuad } }

    readonly property bool isEffectActive: root.visible && root.opacity > 0.01 && root.width > 0 && root.height > 0

    property real time: 0.0
    Timer {
        interval: 100 // Gentle 10 FPS ambient wave flow (prevents continuous 60 FPS shader redrawing)
        running: root.isEffectActive && root.isFlowActive
        repeat: true
        onTriggered: root.time += 0.08
    }

    // Coordinate mapping to track where this glass sits inside backgroundSourceItem
    readonly property point globalOffset: {
        if (!backgroundSourceItem || !root.isEffectActive) return Qt.point(0, 0);
        return root.mapToItem(backgroundSourceItem, 0, 0);
    }

    // Capture the background item as a GPU texture with linear filtering
    ShaderEffectSource {
        id: bgSource
        sourceItem: root.isEffectActive ? root.backgroundSourceItem : null
        recursive: false
        live: root.isEffectActive
        hideSource: false
        visible: false
        smooth: true
        mipmap: false
    }

    // Hardware-accelerated GLSL Liquid Glass Refraction Shader with 9-Tap Frosted Blur
    ShaderEffect {
        id: glassShader
        anchors.fill: parent

        property variant source: bgSource
        property real u_blur: root.blurRadius
        property vector2d u_resolution: Qt.vector2d(root.width, root.height)
        property real u_radius: root.radius
        property real u_displacement: root.displacement
        property real u_aberration: root.aberration
        property real u_bevelWidth: root.bevelWidth
        property real u_colorBleed: root.colorBleed
        property real u_time: root.time
        property real u_flowActive: root.flowProgress
        property real _pad: 0.0
        property vector2d u_sourceSize: Qt.vector2d(
            root.backgroundSourceItem ? Math.max(1, root.backgroundSourceItem.width) : 1,
            root.backgroundSourceItem ? Math.max(1, root.backgroundSourceItem.height) : 1
        )
        property vector2d u_sourceOffset: Qt.vector2d(root.globalOffset.x, root.globalOffset.y)
        property color u_tint: root.tintColor

        fragmentShader: Qt.resolvedUrl("../assets/shaders/liquid_glass.frag.qsb")
        visible: root.isEffectActive && root.backgroundSourceItem !== null
    }

    // Fallback when no backgroundSourceItem is provided
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.backgroundSourceItem === null
        color: root.tintColor
    }

    // Content container (text, icons, buttons inside the glass)
    Item {
        id: contentContainer
        anchors.fill: parent
        property alias radius: root.radius
        z: 10
    }
}
