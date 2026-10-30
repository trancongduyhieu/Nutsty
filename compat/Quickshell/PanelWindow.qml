import QtQuick
import QtQuick.Window

Window {
    id: root
    default property alias contentData: root.data
    readonly property bool isDesktopBottomPanel: true
    flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus | Qt.Tool | Qt.WindowStaysOnBottomHint
    color: "transparent"
    visible: false

    width: (screen && screen.geometry) ? screen.geometry.width : Screen.width
    height: (screen && screen.geometry) ? screen.geometry.height : Screen.height
    x: (screen && screen.geometry) ? screen.geometry.x : 0
    y: (screen && screen.geometry) ? screen.geometry.y : 0

    property var screen: null
    property var mask: null
    property var exclusionMode: null

    property PanelAnchors anchors: PanelAnchors {}

    function updateMask() {
        if (typeof __NutstyBridge === "undefined") return;
        if (!mask || !mask.item) {
            __NutstyBridge.clearWindowMask(root);
            root.visible = false;
        } else {
            var it = mask.item;
            if (!it.visible || it.width <= 0 || it.height <= 0) {
                __NutstyBridge.setWindowMaskRect(root, -100, -100, 1, 1);
                root.visible = false;
            } else {
                root.visible = true;
                var pt = (typeof it.mapToItem === "function") ? it.mapToItem(null, 0, 0) : Qt.point(it.x, it.y);
                __NutstyBridge.setWindowMaskRect(root, Math.round(pt.x), Math.round(pt.y), Math.round(it.width), Math.round(it.height));
            }
        }
    }

    onMaskChanged: updateMask()
    onVisibleChanged: {
        if (visible) {
            root.show();
            root.lower();
            if (typeof __NutstyBridge !== "undefined") {
                __NutstyBridge.pinWindowToDesktopBottom(root);
            }
            updateMask();
            Qt.callLater(updateMask);
        } else {
            root.hide();
            if (typeof __NutstyBridge !== "undefined") {
                __NutstyBridge.clearWindowMask(root);
            }
        }
    }
    onActiveChanged: {
        if (active && visible && typeof __NutstyBridge !== "undefined") {
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

    Component.onCompleted: {
        updateMask();
        Qt.callLater(updateMask);
        if (visible) {
            root.show();
            root.lower();
            if (typeof __NutstyBridge !== "undefined") {
                __NutstyBridge.pinWindowToDesktopBottom(root);
            }
        } else {
            root.hide();
            if (typeof __NutstyBridge !== "undefined") {
                __NutstyBridge.clearWindowMask(root);
            }
        }
    }
}
