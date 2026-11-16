import QtQuick
import QtQuick.Effects
import "."

// AutoMix transition for the Now Playing cover view, staged like an app switcher.
// - "pre": a few seconds before the blend the main cover springs down to card size and slides
//   left; the next track's card slides in on the right at the same size, and glowing particles
//   trade places between the two cards (mix_stream shader).
// - "mix": the engine has switched to the incoming track. In one frame the main cover (now the
//   new song) takes the right card's place and the outgoing song takes the left slot, so the
//   swap is seamless. Particles flow left -> right while the audio blends.
// - release: when the blend ends the old card slides away to the left and the main cover springs
//   back to the centre at full size.
// The main cover itself is moved through mainShift / mainScale (applied by the host view).
// Timing comes from win.mixUpcoming / win.mixActive (published by playback_engine.js).
Item {
    id: root

    property var track: null
    property var mixUpcoming: null
    property var mixActive: null
    property bool isPlaying: false
    property bool shown: true
    property real coverSize: 300
    property real coverRadius: 16
    property color mainColor: Qt.rgba(1, 1, 1, 1)
    property color accentColor: Theme.accent
    property url prevImage: ""      // the outgoing track's resolved artwork (left card fallback when no snapshot was taken)
    property url nextImage: ""      // the next track's resolved artwork (prefetched; what the main cover will show)
    property bool mainReady: true   // the main cover has its artwork decoded
    property Item mainSurface: null // the main cover item, mirrored live so the swap can freeze its last frame

    readonly property real stageMs: 8000    // how long before the blend the cards line up
    readonly property real releaseLeadMs: 350

    // Same key as playback_engine.js trackKeyOf, so the card follows exactly the tracks the engine mixes
    function keyOf(trk) {
        if (!trk) return "";
        var v = trk.videoId || trk.id || (trk.path && String(trk.path).startsWith("ytdl://") ? String(trk.path).replace("ytdl://", "") : "");
        if (v) {
            var s = String(v);
            if (s.startsWith("yt_")) s = s.replace(/^yt_/, "");
            if (s.indexOf("watch?v=") !== -1) s = s.split("watch?v=")[1].split("&")[0];
            s = s.trim();
            if (s) return s;
        }
        return trk.path || trk.title || trk.name || "";
    }
    function imageOf(trk) {
        if (!trk) return "";
        var img = trk.image || trk.cover || trk.thumbnail || trk.artUrl || "";
        if (!img && trk.videoId) img = "https://i.ytimg.com/vi/" + trk.videoId + "/hqdefault.jpg";
        var s = String(img || "").trim();
        if (!s || s.startsWith("http") || s.startsWith("file:") || s.startsWith("qrc:")) return s;
        var clean = s.replace(/\\/g, "/");
        if (clean.startsWith("/")) return "file://" + clean;
        if (/^[a-zA-Z]:\//.test(clean)) return "file:///" + clean;
        return clean;
    }
    function clamp01(x) { return Math.max(0.0, Math.min(1.0, x)); }
    function smooth(e0, e1, x) { var t = clamp01((x - e0) / (e1 - e0)); return t * t * (3 - 2 * t); }

    // ---- Clock -------------------------------------------------------------------------
    property double now: Date.now()
    property real flowTime: 0.0
    readonly property string trackKey: keyOf(track)
    readonly property bool upValid: !!mixUpcoming && mixUpcoming.fromKey === trackKey
        && now < mixUpcoming.fadeAtMs + 1500 && now > mixUpcoming.fadeAtMs - stageMs - 2000
    readonly property bool actValid: !!mixActive && mixActive.toKey === trackKey
        && now < mixActive.blendAtMs + mixActive.durMs + 600
    readonly property real approach: upValid ? clamp01(1.0 - (mixUpcoming.fadeAtMs - now) / stageMs) : 0.0
    readonly property real blendP: mixActive ? clamp01((now - mixActive.blendAtMs) / Math.max(500, mixActive.durMs)) : 1.0

    // Per frame while something is on screen or about to be; a cheap 4 Hz check otherwise
    readonly property bool live: shown && (phase !== "idle" || flowT > 0.001 || upValid || actValid)
    readonly property bool pendingMix: ((!!mixUpcoming && now < mixUpcoming.fadeAtMs + 1500)
        || (!!mixActive && now < mixActive.blendAtMs + mixActive.durMs + 600))
    FrameAnimation {
        running: root.live
        onTriggered: {
            root.flowTime += Math.min(0.05, frameTime) * (root.isPlaying ? 1.0 : 0.15);
            root.tick();
        }
    }
    Timer {
        interval: 250
        repeat: true
        running: !root.live && (root.pendingMix || root.phase !== "idle")
        onTriggered: root.tick()
    }
    onShownChanged: tick()
    // Freeze the left-card snapshot the moment the engine starts its switch: it sets mixActive
    // (and then the new track) before the phase can flip, and the main cover may already show
    // the new, prefetched artwork by the next frame
    function freezeSnap() { if (phase === "pre" && snap.live) snap.live = false; }
    onMixActiveChanged: { if (mixActive) freezeSnap(); tick(); }
    onTrackKeyChanged: freezeSnap()   // a real track change, not the same track re-enriched

    // ---- Phase machine -------------------------------------------------------------------
    // Evaluated once per tick (not as a binding) so the engine's multi-step switch
    // (mixActive set, mixUpcoming cleared, currentTrack changed) is seen as one pre -> mix step.
    property string phase: "idle"
    // True while the switch is being staged or blended (independent of the cards fitting)
    // (also while the lyrics/queue panel hides the cards: the "Mixing" label still shows)
    readonly property bool mixing: ((upValid && now >= mixUpcoming.fadeAtMs - stageMs)
            || (actValid && now < mixActive.blendAtMs + mixActive.durMs - releaseLeadMs))
    property double idleSince: 0
    function computePhase() {
        if (!shown || !fits) return "idle";
        if (actValid && mixActive && now < mixActive.blendAtMs + mixActive.durMs - releaseLeadMs) return "mix";
        if (upValid && mixUpcoming && now >= mixUpcoming.fadeAtMs - stageMs) return "pre";
        return "idle";
    }
    function tick() {
        now = Date.now();
        var p = computePhase();
        if (p === phase) { idleSince = 0; return; }
        // Dropping back to idle waits a moment: the engine may be between two of its writes
        if (p === "idle" && shown && fits) {
            if (idleSince === 0) { idleSince = now; return; }
            if (now - idleSince < 250) return;
        }
        idleSince = 0;
        var old = phase;
        phase = p;
        apply(p, old);
    }

    // Animated state. "instant" turns the springs off for the one-frame swap.
    property bool instant: false
    property real mainShift: 0
    property real mainScale: 1
    property real flowT: 0
    property bool streamFromPrev: false
    readonly property real springK: 2.6
    readonly property real dampK: 0.30
    Behavior on mainShift { enabled: !root.instant; SpringAnimation { spring: root.springK; damping: root.dampK; epsilon: 0.25 } }
    Behavior on mainScale { enabled: !root.instant; SpringAnimation { spring: root.springK; damping: root.dampK + 0.04; epsilon: 0.0008 } }
    Behavior on flowT { enabled: !root.instant; NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }

    property var nextTrack: null
    property var prevTrack: null
    // Asks the host to resolve + decode the next artwork as soon as the next track is known
    signal prefetchRequested(var trk)
    onNextTrackChanged: if (nextTrack) prefetchRequested(nextTrack)
    onMixUpcomingChanged: { if (mixUpcoming && mixUpcoming.to) prefetchRequested(mixUpcoming.to); tick(); }

    function apply(p, old) {
        var k = cardS, d = slotD, off = cardW * 0.9;
        if (p === "pre") {
            nextTrack = mixUpcoming ? mixUpcoming.to : nextTrack;
            // The left card loads the outgoing artwork now (hidden), so it is ready at the swap
            prevTrack = track;
            streamFromPrev = false;
            instant = true;
            nextCard.ox = d + off; nextCard.s = k * 0.9; nextCard.op = 0; nextCard.altOn = true;
            instant = false;
            nextCard.fadeSlow = false;
            pendingNextFade = false;
            snapOn = false;
            snapShow = true;
            snapFresh = false;
            snap.live = true;
            nextCard.ox = d; nextCard.s = k; nextCard.op = 1;
            prevCard.op = 0;
            mainShift = -d; mainScale = k;
            flowT = 1;
        } else if (p === "mix") {
            prevTrack = mixActive ? mixActive.from : prevTrack;
            streamFromPrev = true;
            if (old === "pre") {
                // Seamless swap: the main cover (new song) takes the right card's place,
                // the old song's card takes the main cover's place on the left
                // The next card stays on top of the main cover until the release, so the main
                // cover can load the new artwork underneath without a flash
                // The left card shows the main cover's last frame exactly as it was on screen
                // (resolved artwork or a canvas video frame), so nothing changes on the left either
                snap.live = false;
                // Only a snapshot drawn during this staging shows the outgoing track; otherwise
                // (view hidden while staging) the left card falls back to the track's artwork
                snapOn = snapFresh;
                snapShow = snapFresh;
                instant = true;
                mainShift = d; mainScale = k;
                prevCard.ox = -d; prevCard.s = k; prevCard.op = 1;
                instant = false;
            } else {
                // No staging was seen (opened mid-blend): the old cover peels off the main one
                nextTrack = mixActive ? mixActive.to : nextTrack;
                snap.live = false;
                snapOn = false;
                snapShow = false;
                instant = true;
                prevCard.ox = mainShift; prevCard.s = mainScale; prevCard.op = 1;
                nextCard.ox = mainShift; nextCard.s = mainScale; nextCard.op = 1;
                instant = false;
                prevCard.ox = -d; prevCard.s = k;
                nextCard.ox = d; nextCard.s = k;
                mainShift = d; mainScale = k;
            }
            flowT = 1;
        } else {
            if (old === "mix") {
                prevCard.ox = -d - off; prevCard.s = k * 0.85; prevCard.op = 0;
                // The next card rides the same spring as the main cover and dissolves into it
                nextCard.ox = 0; nextCard.s = 1; nextCard.fadeSlow = true;
                pendingNextFade = true;
                fadeNextWhenReady();
            } else {
                nextCard.ox = d + off; nextCard.s = k * 0.9; nextCard.op = 0;
                snap.live = false;
                snapShow = false;
            }
            mainShift = 0; mainScale = 1;
            flowT = 0;
        }
    }
    // The next card only dissolves once the main cover underneath has its artwork, so the
    // hand-over never reveals an empty cover
    property bool pendingNextFade: false
    function fadeNextWhenReady() {
        if (!pendingNextFade || !mainReady) return;
        pendingNextFade = false;
        nextCard.op = 0;
    }
    onMainReadyChanged: fadeNextWhenReady()
    Timer {   // never hold the card forever if the artwork fails
        interval: 2500
        running: root.pendingNextFade
        onTriggered: { root.pendingNextFade = false; nextCard.op = 0; }
    }
    // A size change (the layout often reflows when the new track arrives) only moves the cards to
    // their new slots. Re-running apply() here would restart the staging and re-arm the live
    // snapshot after the switch, so the left card would mirror the new track's cover
    function relayout() {
        var k = cardS, d = slotD;
        if (phase === "pre") {
            nextCard.ox = d; nextCard.s = k;
            mainShift = -d; mainScale = k;
        } else if (phase === "mix") {
            prevCard.ox = -d; prevCard.s = k;
            if (nextCard.op > 0) { nextCard.ox = d; nextCard.s = k; }
            mainShift = d; mainScale = k;
        }
    }
    onCoverSizeChanged: relayout()
    onWidthChanged: relayout()

    // ---- Geometry ----------------------------------------------------------------------
    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real gap: Math.max(120, coverSize * 0.42)
    readonly property real cardW: Math.round(Math.min(coverSize * 0.6, width / 2 - 12 - gap / 2))
    readonly property real cardS: cardW / Math.max(1, coverSize)
    readonly property real slotD: cardW / 2 + gap / 2
    readonly property bool fits: cardW >= 110
    readonly property real bend: Math.max(22, cardW * 0.2)

    // ---- Card ----------------------------------------------------------------------------
    component Card: Item {
        id: card
        property var trk: null
        property real ox: 0       // centre offset from the slot centre, px
        property real s: 1        // size relative to the main cover
        property real op: 0
        property string caption: ""
        property bool showCaption: true
        property url altSource: ""     // crossfaded over the card artwork once loaded (when altOn)
        property bool altOn: false
        property color sampled: root.accentColor
        readonly property real size: root.coverSize * s
        Behavior on ox { enabled: !root.instant; SpringAnimation { spring: root.springK; damping: root.dampK; epsilon: 0.25 } }
        Behavior on s { enabled: !root.instant; SpringAnimation { spring: root.springK; damping: root.dampK + 0.04; epsilon: 0.0008 } }
        property bool fadeSlow: false   // dissolve late, after the spring has mostly landed
        Behavior on op { enabled: !root.instant; NumberAnimation { duration: card.fadeSlow ? 900 : 420; easing.type: card.fadeSlow ? Easing.InQuad : Easing.OutCubic } }

        width: size
        height: size
        x: root.cx + ox - width / 2
        y: root.cy - height / 2
        // Never show the empty placeholder: the card waits (transparent) until its artwork is
        // decoded, then fades in. A track with no artwork at all shows the placeholder after a moment
        readonly property bool artReady: baseImg.status === Image.Ready
            || (card.altOn && String(card.altSource) !== "" && altImg.status === Image.Ready)
        property bool artGiveUp: false
        onTrkChanged: artGiveUp = false
        Timer { interval: 1400; running: card.op > 0.005 && !card.artReady && !card.artGiveUp; onTriggered: card.artGiveUp = true }
        property real artT: (artReady || artGiveUp) ? 1 : 0
        Behavior on artT { enabled: !root.instant; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        opacity: op * artT
        visible: op > 0.005

        RectangularShadow {
            anchors.fill: parent
            radius: root.coverRadius * card.s
            spread: 2
            blur: 40
            color: Qt.rgba(card.sampled.r, card.sampled.g, card.sampled.b, 0.5)
        }
        RoundedImage {
            id: baseImg
            anchors.fill: parent
            radius: root.coverRadius * card.s
            source: root.imageOf(card.trk)
            sourceSize: Qt.size(512, 512)
            borderColor: Qt.rgba(1, 1, 1, 0.14)
            borderWidth: 1
            fallbackIcon: "../assets/icons/material/ms-graphic_eq.svg"
            fallbackIconColor: root.accentColor
            placeholderColor: Qt.rgba(root.accentColor.r * 0.25, root.accentColor.g * 0.25, root.accentColor.b * 0.25, 1)
        }
        RoundedImage {
            id: altImg
            anchors.fill: parent
            radius: root.coverRadius * card.s
            source: card.altSource
            sourceSize: Qt.size(1200, 1200)   // same request as the main cover / preloader: a cache hit, no reload
            borderColor: Qt.rgba(1, 1, 1, 0.14)
            borderWidth: 1
            placeholderColor: "transparent"
            opacity: card.altOn && String(card.altSource) !== "" && status === Image.Ready ? 1 : 0
            visible: opacity > 0.005
            Behavior on opacity { enabled: !root.instant; NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
        }

        Column {
            anchors.top: parent.bottom
            anchors.topMargin: 14
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.cardW + 40
            spacing: 3
            opacity: card.showCaption ? root.clamp01((0.85 - card.s) / 0.2) : 0
            Behavior on opacity { NumberAnimation { duration: 260 } }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: card.caption
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 1.2
                color: Qt.rgba(card.sampled.r * 0.4 + 0.6, card.sampled.g * 0.4 + 0.6, card.sampled.b * 0.4 + 0.6, 0.85)
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: card.trk ? (card.trk.title || card.trk.name || "") : ""
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: "#ffffff"
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: card.trk ? (card.trk.artist || "") : ""
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Qt.rgba(1, 1, 1, 0.6)
                elide: Text.ElideRight
            }
        }

        // Cover colour: chroma-weighted average of a 16x16 copy, pushed to a glowing range
        Canvas {
            width: 16; height: 16
            opacity: 0
            enabled: false
            property string src: root.imageOf(card.trk)
            onSrcChanged: { if (src !== "") { if (isImageLoaded(src)) requestPaint(); else loadImage(src); } }
            onImageLoaded: requestPaint()
            onAvailableChanged: if (available && src !== "") { if (isImageLoaded(src)) requestPaint(); else loadImage(src); }
            onPaint: {
                if (src === "" || !isImageLoaded(src)) return;
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, 16, 16);
                ctx.drawImage(src, 0, 0, 16, 16);
                var d = ctx.getImageData(0, 0, 16, 16).data;
                var r = 0, g = 0, b = 0, wsum = 0;
                for (var i = 0; i < 256; ++i) {
                    var o = i * 4;
                    if (d[o + 3] < 128) continue;
                    var cr = d[o] / 255, cg = d[o + 1] / 255, cb = d[o + 2] / 255;
                    var w = 0.15 + Math.max(cr, cg, cb) - Math.min(cr, cg, cb);
                    r += cr * w; g += cg * w; b += cb * w; wsum += w;
                }
                if (wsum <= 0) return;
                var c = Qt.rgba(r / wsum, g / wsum, b / wsum, 1);
                card.sampled = Qt.hsla(c.hslHue < 0 ? 0 : c.hslHue, Math.min(1, c.hslSaturation * 1.6 + 0.12), Math.max(0.45, Math.min(0.62, c.hslLightness)), 1);
            }
        }
        Behavior on sampled { ColorAnimation { duration: 500 } }
    }

    // ---- Particle stream between the two card slots -------------------------------------
    ShaderEffect {
        id: stream
        readonly property real pad: 26
        readonly property real ax: root.cx - root.slotD + root.cardW / 2 + 10
        readonly property real bx: root.cx + root.slotD - root.cardW / 2 - 10
        readonly property real intensity: root.streamFromPrev
            ? 1.0 - root.smooth(0.72, 1.0, root.blendP)
            : 0.55 + 0.45 * root.approach
        x: ax - pad
        y: root.cy - root.bend - pad
        width: Math.max(1, bx - ax + pad * 2)
        height: (root.bend + pad) * 2
        visible: root.flowT * intensity > 0.004 && bx - ax > 16
        blending: true

        property vector2d u_size: Qt.vector2d(width, height)
        property vector2d u_a: Qt.vector2d(pad, root.bend + pad)
        property vector2d u_b: Qt.vector2d(bx - ax + pad, root.bend + pad)
        readonly property color colA: root.streamFromPrev ? prevCard.sampled : root.mainColor
        readonly property color colB: root.streamFromPrev ? root.mainColor : nextCard.sampled
        property vector4d u_colA: Qt.vector4d(colA.r, colA.g, colA.b, 1)
        property vector4d u_colB: Qt.vector4d(colB.r, colB.g, colB.b, 1)
        property real u_time: root.flowTime
        property real u_flow: root.flowT * intensity
        property real u_bias: root.streamFromPrev ? 0.55 + 0.35 * root.clamp01(root.blendP * 1.4) : 0.5
        property real u_bend: root.bend
        fragmentShader: Qt.resolvedUrl("../assets/shaders/mix_stream.frag.qsb")
    }

    Card {
        id: nextCard
        trk: root.nextTrack
        caption: I18n.tr("TIẾP THEO", "UP NEXT")
        showCaption: false   // artwork only, like the left card
        altSource: root.nextImage
    }
    Card {
        id: prevCard
        trk: root.prevTrack
        altSource: root.prevImage
        altOn: true
        caption: I18n.tr("ĐANG CHUYỂN TỪ", "MIXING FROM")
        showCaption: false   // the left card is artwork only
    }

    // Mirror of the main cover. During "pre" it sits exactly over the shrunken main cover (same
    // place, same size, same pixels), so the layer renders every frame. At the swap it freezes on
    // that last frame and stays put as the left card, so the left side never changes picture.
    property bool snapOn: false    // snapshot follows the left card
    property bool snapShow: false  // snapshot visible over the main cover (pre, and frozen until the swap)
    property bool snapFresh: false // the snapshot texture holds a frame drawn during this staging
    // A live ShaderEffectSource only updates when its window actually renders it. Count a frame
    // as captured only when one is swapped while the snapshot is live and effectively visible.
    Connections {
        target: root.Window.window
        enabled: snap.live && !root.snapFresh
        function onFrameSwapped() {
            if (snap.live && snap.visible && root.Window.window && root.Window.window.visible)
                root.snapFresh = true;
        }
    }
    ShaderEffectSource {
        id: snap
        z: 1
        readonly property real sz: root.snapOn ? prevCard.width : root.coverSize * root.mainScale
        width: sz
        height: sz
        x: root.snapOn ? prevCard.x : root.cx + root.mainShift - sz / 2
        y: root.cy - sz / 2
        sourceItem: root.mainSurface
        live: false
        hideSource: false
        smooth: true
        mipmap: true
        textureSize: root.mainSurface ? Qt.size(Math.ceil(root.mainSurface.width), Math.ceil(root.mainSurface.height)) : Qt.size(1, 1)
        opacity: root.snapOn ? prevCard.op : (root.snapShow ? 1 : 0)
        visible: opacity > 0.005 && sourceItem !== null
    }
}
