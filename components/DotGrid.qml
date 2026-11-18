import QtQuick

// A quiet grid of white dots, painted once per size. Used behind the listener card header and
// across the whole window while the profile page is open.
Canvas {
    id: root
    property real step: 16
    property real dotRadius: 1.1
    property real dotAlpha: 0.07

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        ctx.fillStyle = "rgba(255, 255, 255, " + root.dotAlpha + ")";
        for (var y = root.step / 2; y < height; y += root.step) {
            for (var x = root.step / 2; x < width; x += root.step) {
                ctx.beginPath();
                ctx.arc(x, y, root.dotRadius, 0, Math.PI * 2);
                ctx.fill();
            }
        }
    }
}
