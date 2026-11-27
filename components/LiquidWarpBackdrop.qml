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
    // Lite mode (on by default without a GPU): each animated frame re-runs the full-window warp + 64px
    // blur, so the artwork stays a static blurred frame instead
    readonly property bool liteMode: (typeof win !== "undefined" && win && Boolean(win.liteMode))

    // Time counter for serene fluid 2D warping wave (50s period)
    property real animTime: 0.0

    // ---- Bass pulse -------------------------------------------------------------------------
    // Two channels of 0..255 per 25 ms of the playing song (backend/bass_envelope.py): pulseSlots, how
    // hard the bass hits (a kick, the start of a note; a drop harder than a verse), and bodySlots, how
    // much bass stays (a held 808, a thick bass line). The caller hands over the last known position
    // (playhead, seconds) and when it was read (playheadStampMs, Date.now()); each frame looks both up
    // at the position now. A hit swells the backdrop and runs the warp faster for a moment; a held bass
    // keeps it slightly fuller and quicker for as long as it lasts, easing in and out
    property var pulseSlots: null
    property var bodySlots: null
    property bool pulseOn: false
    property real playhead: 0
    property real playheadStampMs: 0
    property real pulse: 0
    property real body: 0
    // Strength, tuned for a desktop window (SimpMusic's phone numbers, 8% / 4x / instant / 140 ms, read
    // as too strong here): a hit eases in over ~40 ms, swells up to 3.5%, warps up to 2.5x and fades over
    // ~220 ms; the level is shaped by ^1.5 so moderate hits swell little and only the hardest swell fully
    readonly property real pulseZoom: 0.035
    readonly property real pulseWarp: 1.5
    readonly property real pulseAttackS: 0.04
    readonly property real pulseDecayS: 0.22
    readonly property real bodyZoom: 0.012
    readonly property real bodyWarp: 0.6
    readonly property real bodyEaseS: 0.35
    property int lastSlot: -1
    property real bodyTarget: 0

    // The strongest slot passed since the last frame, so a slow frame (or 30 fps) never skips a hit.
    // The position counts on from the last status read for at most 0.5 s: past that the reads have
    // stopped (loading, a stall) and guessing on would run ahead of the sound
    function pulseTarget() {
        if (!pulseOn || !pulseSlots || pulseSlots.length === 0) { lastSlot = -1; bodyTarget = 0; return 0; }
        var t = playhead + Math.min(0.5, Math.max(0, Date.now() - playheadStampMs) / 1000);
        var i = Math.floor(t * 40);
        var from = (lastSlot >= 0 && i > lastSlot && i - lastSlot <= 8) ? lastSlot + 1 : i;
        lastSlot = i;
        var b = (pulseOn && bodySlots && i >= 0 && i < bodySlots.length) ? bodySlots[i] / 255 : 0;
        bodyTarget = b;
        var best = 0;
        for (var k = Math.max(0, from); k <= i && k < pulseSlots.length; k++)
            if (pulseSlots[k] > best) best = pulseSlots[k];
        return Math.pow(best / 255, 1.5);
    }

    FrameAnimation {
        running: root.visible && root.running && root.isWindowActive && !root.liteMode
        onTriggered: {
            var dt = Math.min(0.1, Math.max(0, frameTime));
            var target = root.pulseTarget();
            var p = target > root.pulse
                    ? root.pulse + (target - root.pulse) * (1 - Math.exp(-dt / root.pulseAttackS))
                    : Math.max(target, root.pulse * Math.exp(-dt / root.pulseDecayS));
            root.pulse = p < 0.002 ? 0 : p;
            var b = root.body + (root.bodyTarget - root.body) * (1 - Math.exp(-dt / root.bodyEaseS));
            root.body = b < 0.002 ? 0 : b;
            root.animTime = (root.animTime + dt * (62.831853 / 50)
                             * (1 + root.pulseWarp * root.pulse + root.bodyWarp * root.body)) % 62.831853;
        }
        onRunningChanged: if (!running) { root.pulse = 0; root.body = 0; }
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

    // MultiEffect: true hardware 2-pass Gaussian blur (blurMax: 64) dissolves edges and text into haze.
    // Sized with width/height, not anchors.fill: an anchored blur keeps its old texture size after
    // the window is maximized and restored, leaving part of the backdrop black
    MultiEffect {
        id: finalAtmosphere
        width: root.width
        height: root.height
        source: warpEffect
        scale: 1 + root.pulseZoom * root.pulse + root.bodyZoom * root.body
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
