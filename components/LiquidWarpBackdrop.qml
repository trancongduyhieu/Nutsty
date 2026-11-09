import QtQuick
import "."

Item {
    id: root
    clip: true

    // =========================================================================
    // Minimal Deep Module Interface (Leverage for callers)
    // =========================================================================
    property url source: ""
    property bool running: true
    property real darkScrim: 0.24
    property real zoom: 1.6

    readonly property bool isWindowActive: (typeof win === "undefined" || !win || Boolean(win.isWindowEffectivelyActive))

    // Time counter for fluid 2D warping wave
    property real animTime: 0.0

    NumberAnimation on animTime {
        running: root.visible && root.running && root.isWindowActive
        loops: Animation.Infinite
        from: 0.0
        to: 628.31853
        duration: 25000
        easing.type: Easing.Linear
    }

    // Downscale-prepass: ultra-compact 64x64 texture provides silky bilinear blur
    Item {
        id: rawContainer
        width: 64
        height: 64
        visible: false

        Image {
            id: rawImg
            anchors.fill: parent
            source: root.source
            sourceSize: Qt.size(64, 64)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            smooth: true
            onStatusChanged: {
                if (status === Image.Ready) {
                    warpSource.scheduleUpdate();
                }
            }
        }
    }

    ShaderEffectSource {
        id: warpSource
        sourceItem: rawContainer
        hideSource: true
        live: false
        smooth: true
    }

    // GPU 2D Liquid Warp ShaderEffect
    ShaderEffect {
        id: effectItem
        anchors.fill: parent
        visible: rawImg.status === Image.Ready

        property var source: warpSource
        property real u_time: root.animTime
        property real u_zoom: Math.max(1.0, root.zoom)
        property real u_scrim: Math.max(0.0, Math.min(1.0, root.darkScrim))

        fragmentShader: Qt.resolvedUrl("../assets/shaders/liquid_warp.frag.qsb")
    }

    // Fallback subtle dark atmosphere when image is loading
    Rectangle {
        anchors.fill: parent
        visible: rawImg.status !== Image.Ready
        color: "#141416"
    }
}
