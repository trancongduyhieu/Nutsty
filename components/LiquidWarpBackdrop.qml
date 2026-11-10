import QtQuick
import QtQuick.Effects
import "."

Item {
    id: root
    clip: true

    // =========================================================================
    // Minimal Deep Module Interface (Leverage for callers)
    // =========================================================================
    property url source: ""
    property bool running: true
    property real darkScrim: 0.0
    property real zoom: 1.6

    readonly property bool isWindowActive: (typeof win === "undefined" || !win || Boolean(win.isWindowEffectivelyActive))

    // Time counter for ultra-serene fluid 2D warping wave (3x slower: 300s period)
    property real animTime: 0.0

    NumberAnimation on animTime {
        running: root.visible && root.running && root.isWindowActive
        loops: Animation.Infinite
        from: 0.0
        to: 300.0
        duration: 300000
        easing.type: Easing.Linear
    }

    // 1. Source Artwork downscaled to 36x36 (1:1 Mochy-Music technique: dissolves all text & edges into pure color fields)
    Image {
        id: rawImg
        anchors.fill: parent
        source: root.source
        sourceSize: Qt.size(36, 36)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        visible: false
    }

    // 2. GPU 2D Liquid Warp ShaderEffect: Warps the 128x128 texture with slow, gentle 2D fluid waves
    ShaderEffect {
        id: warpEffect
        anchors.fill: parent
        visible: false

        property var source: rawImg
        property real u_time: root.animTime
        property real u_zoom: Math.max(1.0, root.zoom)
        property real u_scrim: 0.0

        fragmentShader: Qt.resolvedUrl("../assets/shaders/liquid_warp.frag.qsb")
    }

    // 3. MultiEffect: True hardware 2-pass Gaussian blur (blurMax: 64)
    // Completely dissolves any edges, typography (BAD 25), or facial features into an ethereal, creamy liquid haze
    MultiEffect {
        id: finalAtmosphere
        anchors.fill: parent
        source: warpEffect
        visible: rawImg.status === Image.Ready
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        saturation: 1.35
        brightness: -0.04
    }

    // Fallback subtle dark atmosphere when image is loading
    Rectangle {
        anchors.fill: parent
        visible: rawImg.status !== Image.Ready
        color: "#141416"
    }
}
