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
    property real displacement: 30.0
    property real aberration: 0.065
    property real bevelWidth: 21.0
    property real blurRadius: 0.5
    property real colorBleed: 0.94
    property color tintColor: Qt.rgba(0.12, 0.14, 0.18, 0.45)
    // Opt-in, off by default so existing glass looks the same: a frosted interior (blur radius px,
    // Gaussian blur of the backdrop patch) and full coverage of what is behind, for panels over busy text
    property real frost: 0.0
    property bool opaque: false
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
        var _dep = root.x + root.y + root.width + root.height + (root.parent ? (root.parent.x + root.parent.y) : 0) + root.extraDependency;
        return root.mapToItem(backgroundSourceItem, 0, 0);
    }

    // Frosted glass only needs the patch of backdrop under it (plus room for the rim to bend and the blur
    // to reach) instead of the whole page every frame. Full resolution: a half-size capture showed as blocky
    // grain once blurred. Plain glass keeps the whole backdrop as before. An empty rect means "the whole item".
    readonly property rect captureRect: {
        var src = root.backgroundSourceItem;
        if (root.frost <= 0 || !src) return Qt.rect(0, 0, 0, 0);
        var pad = root.displacement + root.frost + 4;
        var x0 = Math.max(0, Math.floor(root.globalOffset.x - pad));
        var y0 = Math.max(0, Math.floor(root.globalOffset.y - pad));
        var x1 = Math.min(src.width, Math.ceil(root.globalOffset.x + root.width + pad));
        var y1 = Math.min(src.height, Math.ceil(root.globalOffset.y + root.height + pad));
        return Qt.rect(x0, y0, Math.max(1, x1 - x0), Math.max(1, y1 - y0));
    }
    readonly property bool cropped: root.captureRect.width > 0

    // Capture the background item as a GPU texture with linear filtering
    ShaderEffectSource {
        id: bgSource
        sourceItem: root.isEffectActive ? root.backgroundSourceItem : null
        sourceRect: root.captureRect
        recursive: false
        live: root.isEffectActive
        hideSource: false
        visible: false
        smooth: true
    }

    // Frost: a real Gaussian blur of the captured patch (Qt's MultiEffect blurs on a downscaled mip chain,
    // smooth and light on the GPU), layered offscreen and handed to the glass shader as its source
    MultiEffect {
        id: frostBlur
        visible: root.frost > 0 && root.isEffectActive && root.backgroundSourceItem !== null
        width: root.captureRect.width
        height: root.captureRect.height
        source: visible ? bgSource : null
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1.0
        blurMax: Math.round(Math.max(1, root.frost) * 1.6)
        blurMultiplier: 0.4
    }
    ShaderEffectSource {
        id: frostSource
        sourceItem: frostBlur.visible ? frostBlur : null
        hideSource: true
        live: true
        visible: false
        smooth: true
    }

    // Hardware-accelerated GLSL Liquid Glass Refraction Shader with 9-Tap Frosted Blur
    ShaderEffect {
        id: glassShader
        anchors.fill: parent

        property variant source: root.frost > 0 ? frostSource : bgSource
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
        property vector2d u_sourceSize: root.cropped ? Qt.vector2d(root.captureRect.width, root.captureRect.height)
                                                     : Qt.vector2d(
            root.backgroundSourceItem ? Math.max(1, root.backgroundSourceItem.width) : 1,
            root.backgroundSourceItem ? Math.max(1, root.backgroundSourceItem.height) : 1
        )
        property vector2d u_sourceOffset: Qt.vector2d(root.globalOffset.x - root.captureRect.x,
                                                      root.globalOffset.y - root.captureRect.y)
        property color u_tint: root.tintColor
        property real u_frost: root.frost
        property real u_opaque: root.opaque ? 1.0 : 0.0

        fragmentShader: Qt.resolvedUrl("../assets/shaders/liquid_glass_frost.frag.qsb")
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
