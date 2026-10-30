import QtQuick
import QtQuick.Window

Window {
    id: root
    default property alias contentData: root.data
    readonly property bool isDesktopBottomPanel: true
    flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus | Qt.Tool
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

    readonly property var targetMaskItem: (mask && mask.item) ? mask.item : null

    function updateMask() {
        if (typeof __NutstyBridge === "undefined") return;
        var it = targetMaskItem;
        if (!it || !it.visible || it.width <= 0 || it.height <= 0) {
            __NutstyBridge.clearWindowMask(root);
        } else {
            var pt = (typeof it.mapToItem === "function") ? it.mapToItem(null, 0, 0) : Qt.point(it.x, it.y);
            __NutstyBridge.setWindowMaskRect(root, Math.round(pt.x), Math.round(pt.y), Math.round(it.width), Math.round(it.height));
        }
    }

    onTargetMaskItemChanged: {
        updateMask();
        Qt.callLater(updateMask);
    }

    onMaskChanged: {
        updateMask();
        Qt.callLater(updateMask);
    }

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
        target: root.targetMaskItem
        ignoreUnknownSignals: true
        function onXChanged() { root.updateMask(); }
        function onYChanged() { root.updateMask(); }
        function onWidthChanged() { root.updateMask(); }
        function onHeightChanged() { root.updateMask(); }
        function onVisibleChanged() { root.updateMask(); }
    }

    Timer {
        interval: 500
        running: root.visible
        repeat: true
        onTriggered: root.updateMask()
    }

    Component.onCompleted: {
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
}
