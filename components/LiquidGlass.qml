import QtQuick
import QtQuick.Effects
import "."

Item {
    id: root

    // =========================================================================
    // Properties & Configuration (PlayerBar Liquid Glass Optical Pipeline)
    // =========================================================================
    property Item backgroundSourceItem: null
    property real radius: 16
    property color tintColor: Qt.rgba(0.08, 0.09, 0.12, 0.48)
    property color borderColor: Qt.rgba(1, 1, 1, 0.18)
    property bool interactive: false
    property bool isPressed: false

    // Backward compatibility properties (preserved to avoid breaking callers)
    property real displacement: 30.0
    property real aberration: 0.065
    property real bevelWidth: 21.0
    property real blurRadius: 0.5
    property real colorBleed: 0.94
    property real extraDependency: 0.0
    property bool isFlowActive: false
    property real flowProgress: isFlowActive ? 1.0 : 0.0
    property real time: 0.0

    default property alias contentData: contentContainer.data

    implicitWidth: 160
    implicitHeight: 48

    // Strictly active ONLY when visible with positive opacity and dimension
    // ZERO idle GPU cost when popover or modal is hidden!
    readonly property bool isEffectActive: root.visible && root.opacity > 0.01 && root.width > 0 && root.height > 0 && root.backgroundSourceItem !== null

    // Subtle elastic scale feedback when interactive
    scale: (root.interactive && root.isPressed) ? 1.02 : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: root.isPressed ? 140 : 260
            easing.type: root.isPressed ? Easing.OutQuad : Easing.OutBack
            easing.overshoot: 1.10
        }
    }

    PointHandler {
        id: interactivePointer
        enabled: root.interactive
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchScreen
        onActiveChanged: root.isPressed = active
    }

    // Concentric Mask (Concentric bo góc đồng tâm)
    Item {
        id: capsuleMask
        anchors.fill: parent
        visible: false
        layer.enabled: root.isEffectActive
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: "#ffffff"
        }
    }

    // =========================================================================
    // 1. LIQUID GLASS BACKDROP BLUR (PlayerBar Hardware MultiEffect Blur)
    // Tightly crops the exact area behind component and runs 48px GPU Gaussian Blur!
    // =========================================================================
    Item {
        id: cropAnchorHelper
        property point cropPos: {
            if (!root.backgroundSourceItem || !root.isEffectActive) return Qt.point(root.x, root.y);
            var _dep = root.x + root.y + root.width + root.height + (root.parent ? (root.parent.width + root.parent.height) : 0);
            return root.mapToItem(root.backgroundSourceItem, 0, 0);
        }
    }

    function refreshBackdrop() {
        if (backdropCropSource && root.isEffectActive) backdropCropSource.scheduleUpdate();
    }

    onVisibleChanged: if (visible) Qt.callLater(refreshBackdrop)
    onOpacityChanged: if (opacity > 0.01) Qt.callLater(refreshBackdrop)
    onWidthChanged: if (visible) Qt.callLater(refreshBackdrop)
    onHeightChanged: if (visible) Qt.callLater(refreshBackdrop)
    Component.onCompleted: Qt.callLater(refreshBackdrop)

    ShaderEffectSource {
        id: backdropCropSource
        sourceItem: root.isEffectActive ? root.backgroundSourceItem : null
        sourceRect: Qt.rect(cropAnchorHelper.cropPos.x, cropAnchorHelper.cropPos.y, root.width, root.height)
        visible: false
        live: (root.interactive && root.isPressed)
        smooth: true
        recursive: false
        hideSource: false
    }

    MultiEffect {
        anchors.fill: parent
        source: backdropCropSource
        blurEnabled: true
        blur: 1.0
        blurMax: 48
        saturation: 1.55
        brightness: -0.05
        maskEnabled: true
        maskSource: capsuleMask
        autoPaddingEnabled: false
        visible: root.isEffectActive
        z: 1
    }

    // =========================================================================
    // 2. ADAPTIVE DARK SCRIM & 1PX CONCENTRIC HAIRLINE BORDER
    // 48% dark overlay keeps high contrast without turning into an opaque block
    // =========================================================================
    Rectangle {
        id: scrimRect
        anchors.fill: parent
        radius: root.radius
        color: root.tintColor
        border.color: root.borderColor
        border.width: 1
        Behavior on border.color { ColorAnimation { duration: 200 } }
        z: 2
    }

    // Content container (text, icons, buttons inside the glass)
    Item {
        id: contentContainer
        anchors.fill: parent
        property alias radius: root.radius
        z: 10
    }
}
