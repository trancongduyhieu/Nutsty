import QtQuick
import QtQuick.Window

Window {
    id: root
    default property alias contentData: root.data
    readonly property bool isDesktopBottomPanel: true
    flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus | Qt.Tool | Qt.WindowStaysOnBottomHint
    color: "transparent"
    visible: false

    // Quickshell windows size themselves through implicitWidth/implicitHeight;
    // QtQuick.Window has no such properties, so declare them for parity.
    property real implicitWidth: 0
    property real implicitHeight: 0

    width: (screen && screen.geometry) ? screen.geometry.width : Screen.width
    height: (screen && screen.geometry) ? screen.geometry.height : Screen.height
    x: (screen && screen.geometry) ? screen.geometry.x : 0
    y: (screen && screen.geometry) ? screen.geometry.y : 0

    property var screen: null
    property var mask: null
    property var exclusionMode: null

    property PanelAnchors anchors: PanelAnchors {}

    // A Win32 window region set before the first frame makes the D3D swapchain drop
    // its alpha: the whole panel paints as a solid black/white box. Clip only once a
    // frame has been presented (the bridge flips regionReady from frameSwapped), and
    // drop the region (not an empty one) while hidden.
    property bool regionReady: false
    onRegionReadyChanged: if (regionReady) updateMask()

    function showPanel() {
        root.show();
        root.lower();
        if (typeof __NutstyBridge === "undefined") return;
        if (typeof __NutstyBridge.pinWindowToDesktopBottom === "function")
            __NutstyBridge.pinWindowToDesktopBottom(root);
        if (typeof __NutstyBridge.armWindowRegion === "function")
            __NutstyBridge.armWindowRegion(root);
        // Sets `occluded` on panels that declare it while other apps cover them.
        if (typeof __NutstyBridge.watchOcclusion === "function")
            __NutstyBridge.watchOcclusion(root);
    }

    function updateMask() {
        if (typeof __NutstyBridge === "undefined" || !root.regionReady) return;
        if (!mask || !mask.item) {
            __NutstyBridge.clearWindowMask(root);
        } else {
            var it = mask.item;
            if (!it.visible || it.width <= 0 || it.height <= 0) {
                __NutstyBridge.setWindowMaskRect(root, -100, -100, 1, 1);
            } else {
                var pt = (typeof it.mapToItem === "function") ? it.mapToItem(null, 0, 0) : Qt.point(it.x, it.y);
                __NutstyBridge.setWindowMaskRect(root, Math.round(pt.x), Math.round(pt.y), Math.round(it.width), Math.round(it.height));
            }
        }
    }

    onMaskChanged: updateMask()
    onVisibleChanged: {
        if (visible) {
            root.showPanel();
        } else {
            root.regionReady = false;
            if (typeof __NutstyBridge !== "undefined" && typeof __NutstyBridge.removeWindowRegion === "function") {
                __NutstyBridge.removeWindowRegion(root);
            }
            if (typeof __NutstyBridge !== "undefined" && typeof __NutstyBridge.unwatchOcclusion === "function") {
                __NutstyBridge.unwatchOcclusion(root);
            }
        }
    }
    onActiveChanged: {
        if (active && visible && typeof __NutstyBridge !== "undefined" && typeof __NutstyBridge.pinWindowToDesktopBottom === "function") {
            __NutstyBridge.pinWindowToDesktopBottom(root);
        }
    }

    Connections {
        target: (mask && mask.item) ? mask.item : null
        function onXChanged() { if (mask && mask.item) root.updateMask(); }
        function onYChanged() { if (mask && mask.item) root.updateMask(); }
        function onWidthChanged() { if (mask && mask.item) root.updateMask(); }
        function onHeightChanged() { if (mask && mask.item) root.updateMask(); }
        function onVisibleChanged() { if (mask && mask.item) root.updateMask(); }
    }

    Component.onCompleted: if (visible) root.showPanel()
}
