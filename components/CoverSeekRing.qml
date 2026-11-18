import QtQuick
import QtQuick.Shapes
import "."

// Seek bar riding the rim of the Mochy side panel's round-cut cover (rebuilt from Mochy's CoverRing.kt).
// At rest it is a faint thin line just inside the cover's edge. Hovered, pressed or when a song starts,
// it springs out past the rim, thickens, and shows the elapsed time and the length at its two ends.
// Press on it to jump, drag along it to scrub; the seek is sent on release.
// Coordinates are the host's: the cover circle is (cx, cy, r) in this item's own pixels.
Item {
    id: ring

    property real cx: 0
    property real cy: 0
    property real r: 100
    property real position: 0        // seconds, as last reported
    property real duration: 0        // seconds
    property real syncTime: 0        // mpv position at syncStamp, for per-frame extrapolation
    property double syncStamp: 0
    property bool isPlaying: false
    property string trackKey: ""
    property bool live: true         // false while the panel is hidden: no peeking, no frame clock

    // 0: thin hint on the cover, 1: full bar out past the rim (hosts push the lyrics by this)
    property real expand: 0
    property real scrubSec: -1
    property bool held: false
    readonly property bool scrubbing: scrubSec >= 0

    signal seekRequested(real seconds)

    // ---- geometry (degrees: 0 at 3 o'clock, clockwise, as PathAngleArc and Compose's drawArc) ----
    function lerp(a, b, t) { return a + (b - a) * t; }
    function deg(rad) { return rad * 180 / Math.PI; }
    function barRadius(e) { return ring.r + lerp(-15, 22, e); }
    // where a circle of radius rr crosses x, on its lower side
    function angleAtX(x, rr) {
        var dx = Math.max(-rr * 0.999, Math.min(rr * 0.999, x - ring.cx));
        return deg(Math.atan2(Math.sqrt(rr * rr - dx * dx), dx));
    }
    // the song's start (left) and end (right), kept clear of the panel's sides
    function startAngle(e) { return angleAtX(lerp(26, 64, e), barRadius(e)); }
    function endAngle(e) { return angleAtX(ring.width - lerp(26, 52, e), barRadius(e)); }
    function angleOf(px, py) { return deg(Math.atan2(py - ring.cy, px - ring.cx)); }
    function onBand(px, py) {
        var d = Math.hypot(px - ring.cx, py - ring.cy);
        if (d < ring.r - 30 || d > ring.r + 44) return false;
        var a = angleOf(px, py), s = startAngle(0), e = endAngle(0);
        return a >= Math.min(s, e) - 4 && a <= Math.max(s, e) + 4;
    }
    function fractionAt(px, py) {
        var s = startAngle(1), e = endAngle(1);
        return Math.max(0, Math.min(1, (angleOf(px, py) - s) / (e - s)));
    }
    function fmt(sec) {
        var t = Math.max(0, Math.floor(sec));
        var m = Math.floor(t / 60), s = t % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    readonly property real barR: barRadius(expand)
    readonly property real a0: startAngle(expand)
    readonly property real sweep: endAngle(expand) - a0
    readonly property real ink: lerp(0.3, 1.0, Math.max(0, Math.min(1, expand)))
    readonly property real labelsShown: Math.max(0, Math.min(1, (expand - 0.3) / 0.7))

    // ---- smooth position: extrapolated every frame while the bar is out ----
    property real livePos: position
    onPositionChanged: if (!clock.running) livePos = position
    FrameAnimation {
        id: clock
        running: ring.live && ring.visible && ring.isPlaying && ring.expand > 0.01
        onTriggered: {
            var p = ring.syncStamp > 0 ? ring.syncTime + Math.max(0, (Date.now() - ring.syncStamp) / 1000) : ring.position;
            ring.livePos = ring.duration > 0 ? Math.min(ring.duration, p) : p;
        }
    }
    readonly property real shownPos: scrubbing ? scrubSec : livePos
    readonly property real fraction: duration > 0 ? Math.max(0, Math.min(1, shownPos / duration)) : 0

    // ---- expand / settle (Mochy: springy out, calm back) ----
    NumberAnimation { id: outAnim; target: ring; property: "expand"; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
    NumberAnimation { id: backAnim; target: ring; property: "expand"; to: 0; duration: 520; easing.type: Easing.OutCubic }
    Timer { id: settleTimer; onTriggered: if (!ring.held) { outAnim.stop(); backAnim.start(); } }

    function peek(forMs) {
        backAnim.stop();
        if (ring.expand < 0.999 && !outAnim.running) outAnim.start();
        settleTimer.interval = forMs;
        settleTimer.restart();
    }
    function grab() { ring.held = true; settleTimer.stop(); backAnim.stop(); if (!outAnim.running && ring.expand < 0.999) outAnim.start(); }
    function letGo(afterMs) { ring.held = false; peek(afterMs); }

    // Out for three seconds whenever the music starts: play pressed or the next song begun
    property bool _wasPlaying: false
    property string _lastKey: ""
    function checkStart() {
        var started = ring.isPlaying && (!ring._wasPlaying || ring.trackKey !== ring._lastKey);
        ring._wasPlaying = ring.isPlaying;
        ring._lastKey = ring.trackKey;
        if (started && ring.live && !ring.held) peek(3000);
    }
    onIsPlayingChanged: checkStart()
    onTrackKeyChanged: checkStart()

    // ---- drawing ----
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: ring.duration > 0

        // the remaining part, a third as bright while resting on the cover
        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(1, 1, 1, 0.38 * ring.ink)
            strokeWidth: ring.lerp(3, 7, ring.expand)
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: ring.cx; centerY: ring.cy
                radiusX: ring.barR; radiusY: ring.barR
                startAngle: ring.a0; sweepAngle: ring.sweep
            }
        }
        // the played part
        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(1, 1, 1, 0.96 * ring.ink)
            strokeWidth: ring.lerp(3, 7, ring.expand)
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: ring.cx; centerY: ring.cy
                radiusX: ring.barR; radiusY: ring.barR
                startAngle: ring.a0
                sweepAngle: { var p = ring.sweep * ring.fraction; return Math.abs(p) < 0.01 ? 0.01 * Math.sign(ring.sweep || -1) : p; }
            }
        }
    }

    // A time just past one end of the bar, turned along the rim and kept the right way up
    component RimLabel: Text {
        id: lbl
        property real endDeg: 0
        property real outward: 1
        readonly property real gapDeg: ring.deg((implicitWidth / 2 + 8 + 10 * (1 - ring.labelsShown)) / Math.max(1, ring.barR))
        readonly property real at: endDeg + outward * gapDeg
        readonly property real rad: at * Math.PI / 180
        x: ring.cx + Math.cos(rad) * ring.barR - implicitWidth / 2
        y: ring.cy + Math.sin(rad) * ring.barR - implicitHeight / 2
        rotation: { var t = at - 90; while (t > 90) t -= 180; while (t < -90) t += 180; return t; }
        scale: 0.86 + 0.14 * ring.labelsShown
        opacity: ring.labelsShown
        visible: opacity > 0.01 && ring.duration > 0
        color: "#ffffff"
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
    }
    RimLabel { text: ring.fmt(ring.shownPos); endDeg: ring.a0; outward: -Math.sign(ring.sweep || -1) }
    RimLabel { text: ring.fmt(ring.duration); endDeg: ring.a0 + ring.sweep; outward: Math.sign(ring.sweep || -1) }

    // ---- input: only the band takes the mouse; everything else falls through to the cover below ----
    MouseArea {
        id: band
        anchors.fill: parent
        hoverEnabled: true
        enabled: ring.live && ring.duration > 0
        readonly property bool overBand: containsMouse && ring.onBand(mouseX, mouseY)
        // over the band: the scrub cursor; above the arc is the cover (opens Now Playing); below, plain
        cursorShape: (overBand || pressed) ? Qt.PointingHandCursor
                   : (Math.hypot(mouseX - ring.cx, mouseY - ring.cy) < ring.r ? Qt.PointingHandCursor : Qt.ArrowCursor)
        onOverBandChanged: {
            if (pressed) return;
            if (overBand) ring.grab();
            else if (ring.held) ring.letGo(700);
        }
        onPressed: mouse => {
            if (!ring.onBand(mouse.x, mouse.y)) { mouse.accepted = false; return; }
            ring.grab();
            ring.scrubSec = ring.duration * ring.fractionAt(mouse.x, mouse.y);
        }
        onPositionChanged: mouse => {
            if (pressed) ring.scrubSec = ring.duration * ring.fractionAt(mouse.x, mouse.y);
        }
        onReleased: {
            if (ring.scrubSec >= 0) ring.seekRequested(Math.max(0, Math.min(ring.duration, ring.scrubSec)));
            ring.livePos = ring.scrubSec;
            // keep showing the dragged time until the player has caught up with it
            holdScrub.restart();
            // still hovering the bar: it stays out; moved off it: settles after a moment
            if (overBand) ring.grab();
            else ring.letGo(1400);
        }
        onCanceled: { ring.scrubSec = -1; ring.letGo(1400); }
    }
    Timer { id: holdScrub; interval: 400; onTriggered: ring.scrubSec = -1 }
}
