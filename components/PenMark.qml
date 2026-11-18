import QtQuick
import QtQuick.Shapes

// A hand-drawn pen mark for the type stage (presets 7 and 8): any number of strokes, each a list of
// { x, y } points from kinetic_stage.js (penStrokes / doodleStrokes). Short marks are drawn
// twice in the maximal cut. Kept in its own file: Quickshell's hot reload loses inline components.
Shape {
    id: pen
    property var strokes: []
    property color ink: "white"
    property real penW: 2
    property int cap: ShapePath.RoundCap
    function poly(i) { return i < strokes.length ? strokes[i].map(function (p) { return Qt.point(p.x, p.y); }) : []; }
    function rest() { var out = []; for (var i = 1; i < strokes.length; i++) out.push(poly(i)); return out; }
    visible: strokes.length > 0
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        strokeColor: pen.strokes.length > 0 ? pen.ink : "transparent"
        strokeWidth: pen.penW
        fillColor: "transparent"
        capStyle: pen.cap
        joinStyle: ShapePath.RoundJoin
        PathPolyline { path: pen.poly(0) }
    }
    // every stroke after the first in one path, so a mark can have as many as it needs (rays, dashes)
    ShapePath {
        strokeColor: pen.strokes.length > 1 ? pen.ink : "transparent"
        strokeWidth: pen.penW * 0.85
        fillColor: "transparent"
        capStyle: pen.cap
        joinStyle: ShapePath.RoundJoin
        PathMultiline { paths: pen.rest() }
    }
}
