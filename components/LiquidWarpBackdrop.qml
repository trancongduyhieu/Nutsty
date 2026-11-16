import QtQuick
import QtQuick.Effects

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
    // No GPU (WARP / Basic Render Driver): each animated frame re-runs the full-window warp + 64px blur
    // on the CPU, so the artwork stays a static blurred frame instead
    readonly property bool softwareRendering: (typeof win !== "undefined" && win && Boolean(win.softwareRendering))

    // Time counter for serene fluid 2D warping wave (50s period)
    property real animTime: 0.0

    NumberAnimation on animTime {
        running: root.visible && root.running && root.isWindowActive && !root.softwareRendering
        loops: Animation.Infinite
        from: 0.0
        to: 62.831853
        duration: 50000
        easing.type: Easing.Linear
    }

    // ---- Artwork hand-over ------------------------------------------------------------------
    // Two 48x48 slots: "front" is on screen, "back" loads the next artwork. Once the back slot is
    // ready the shader floods it in (u_mix 0 -> 1), then the slots trade roles in one frame.
    // driveProgress >= 0 lets the caller steer the hand-over (AutoMix ties it to the audio blend).
    property int fadeMs: 1100
    property real driveProgress: -1
    property bool frontIsA: true
    property real mixT: 0
    readonly property Image frontImg: frontIsA ? slotA : slotB
    readonly property Image backImg: frontIsA ? slotB : slotA
    readonly property bool backReady: backImg.status === Image.Ready && String(backImg.source) !== ""
    property bool settling: false

    function easeDrive(x) { var t = Math.max(0, Math.min(1, (x - 0.06) / 0.86)); return t * t * (3 - 2 * t); }
    function finishSwap() {
        mixAnim.stop();
        settling = false;
        frontIsA = !frontIsA;   // the back slot (fully shown) becomes the front
        mixT = 0;
        backImg.source = "";
    }
    function sync() {
        var want = String(root.source);
        if (want === String(frontImg.source)) {
            // Back to the artwork already on screen (cancelled skip): drop the pending one
            if (mixT > 0 || String(backImg.source) !== "") { mixAnim.stop(); settling = false; mixT = 0; backImg.source = ""; }
            return;
        }
        if (String(frontImg.source) === "" || frontImg.status === Image.Error) {
            frontImg.source = want;   // first artwork: nothing to blend from
            return;
        }
        if (String(backImg.source) !== want) { mixAnim.stop(); settling = false; mixT = 0; backImg.source = want; }
        advance();
    }
    function advance() {
        if (!backReady) return;
        if (driveProgress >= 0) {
            mixAnim.stop();
            mixT = easeDrive(driveProgress);
            if (driveProgress >= 1) finishSwap();
        } else if (!settling) {
            settling = true;
            mixAnim.from = mixT;
            mixAnim.duration = Math.max(200, root.fadeMs * (1 - mixT));
            mixAnim.start();
        }
    }
    onSourceChanged: sync()
    onBackReadyChanged: advance()
    onDriveProgressChanged: advance()
    Component.onCompleted: sync()

    NumberAnimation {
        id: mixAnim
        target: root
        property: "mixT"
        to: 1
        easing.type: Easing.InOutSine
        onFinished: root.finishSwap()
    }

    Image {
        id: slotA
        anchors.fill: parent
        sourceSize: Qt.size(48, 48)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        mipmap: true
        visible: false
    }
    Image {
        id: slotB
        anchors.fill: parent
        sourceSize: Qt.size(48, 48)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        mipmap: true
        visible: false
    }

    // GPU 2D Liquid Warp ShaderEffect: warps the 48x48 textures with slow, gentle 2D fluid waves
    ShaderEffect {
        id: warpEffect
        anchors.fill: parent
        visible: false

        property var source: root.frontImg
        property var source2: root.backReady ? root.backImg : root.frontImg
        property real u_time: root.animTime
        property real u_zoom: Math.max(1.0, root.zoom)
        property real u_scrim: Math.max(0.0, Math.min(1.0, root.darkScrim))
        property real u_mix: root.backReady ? root.mixT : 0.0

        fragmentShader: Qt.resolvedUrl("../assets/shaders/liquid_warp.frag.qsb")
    }

    // MultiEffect: true hardware 2-pass Gaussian blur (blurMax: 64) dissolves edges and text into haze
    MultiEffect {
        id: finalAtmosphere
        anchors.fill: parent
        source: warpEffect
        visible: root.frontImg.status === Image.Ready
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        saturation: 1.45
        brightness: -0.04
    }

    // Fallback subtle dark atmosphere while the very first artwork loads
    Rectangle {
        anchors.fill: parent
        visible: root.frontImg.status !== Image.Ready
        color: "#141416"
    }
}
