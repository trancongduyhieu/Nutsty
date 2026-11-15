import QtQuick
import "."

// Expressive loading indicator: a soft polar shape that keeps spinning while morphing
// through a sequence of shapes (cookie -> flower -> clover -> burst -> puffy -> ...).
// Same petal formula as EmptyState: r = 1 - depth + depth * ((0.5 + 0.5 cos(lobes * t)) ^ sharp).
// Morphing blends the two radius functions, so different lobe counts transition smoothly.
Item {
    id: sl

    property color color: Theme.accent
    property real size: 48
    property bool running: visible

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    readonly property var _shapes: [
        [9, 0.10, 1.0],
        [8, 0.30, 0.5],
        [4, 0.40, 0.55],
        [12, 0.20, 2.6],
        [6, 0.16, 0.5]
    ]
    // 0..N continuous: integer part = from-shape, fraction = morph progress (eased below)
    property real phase: 0
    NumberAnimation on phase {
        running: sl.running
        from: 0
        to: sl._shapes.length
        duration: 650 * sl._shapes.length
        loops: Animation.Infinite
    }
    onPhaseChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        renderStrategy: Canvas.Cooperative
        // Spin continuously; a little extra kick during each morph reads as "expressive"
        rotation: sl.phase * 140
        scale: 0.92 + 0.08 * Math.sin((sl.phase % 1) * Math.PI)
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var n = sl._shapes.length;
            var i0 = Math.floor(sl.phase) % n, i1 = (i0 + 1) % n;
            var f = sl.phase - Math.floor(sl.phase);
            // Hold each shape for the first 40% of its slot, then ease into the next one
            var k = Math.max(0, (f - 0.4) / 0.6);
            k = k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2;
            var a = sl._shapes[i0], b = sl._shapes[i1];
            var cx = width / 2, cy = height / 2, R = Math.min(cx, cy) - 1;
            ctx.beginPath();
            var steps = 160;
            for (var s = 0; s <= steps; ++s) {
                var t = s / steps * Math.PI * 2;
                var ra = (1 - a[1]) + a[1] * Math.pow(0.5 + 0.5 * Math.cos(a[0] * t), a[2]);
                var rb = (1 - b[1]) + b[1] * Math.pow(0.5 + 0.5 * Math.cos(b[0] * t), b[2]);
                var r = R * (ra + (rb - ra) * k);
                var x = cx + r * Math.cos(t), y = cy + r * Math.sin(t);
                if (s === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            }
            ctx.closePath();
            ctx.fillStyle = sl.color;
            ctx.fill();
        }
    }
}
