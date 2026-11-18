import QtQuick
import QtQuick.Shapes

// A hand-drawn pen mark for the type stage (presets 7 and 8): up to six strokes, each a list of
// { x, y } points from kinetic_stage.js (penStrokes / doodleStrokes). Three strokes, each drawn
// twice in the maximal cut. Kept in its own file: Quickshell's hot reload loses inline components.
Shape {
    id: pen
    property var strokes: []
    property color ink: "white"
    property real penW: 2
    property int cap: ShapePath.RoundCap
    function poly(i) { return i < strokes.length ? strokes[i].map(function (p) { return Qt.point(p.x, p.y); }) : []; }
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
    ShapePath {
        strokeColor: pen.strokes.length > 1 ? pen.ink : "transparent"
        strokeWidth: pen.penW * 0.85
        fillColor: "transparent"
        capStyle: pen.cap
        joinStyle: ShapePath.RoundJoin
        PathPolyline { path: pen.poly(1) }
    }
    ShapePath {
        strokeColor: pen.strokes.length > 2 ? pen.ink : "transparent"
        strokeWidth: pen.penW * 0.85
        fillColor: "transparent"
        capStyle: pen.cap
        joinStyle: ShapePath.RoundJoin
        PathPolyline { path: pen.poly(2) }
    }
    ShapePath {
        strokeColor: pen.strokes.length > 3 ? pen.ink : "transparent"
        strokeWidth: pen.penW * 0.85
        fillColor: "transparent"
        capStyle: pen.cap
        joinStyle: ShapePath.RoundJoin
        PathPolyline { path: pen.poly(3) }
    }
    ShapePath {
        strokeColor: pen.strokes.length > 4 ? pen.ink : "transparent"
        strokeWidth: pen.penW * 0.85
        fillColor: "transparent"
        capStyle: pen.cap
        joinStyle: ShapePath.RoundJoin
        PathPolyline { path: pen.poly(4) }
    }
    ShapePath {
        strokeColor: pen.strokes.length > 5 ? pen.ink : "transparent"
        strokeWidth: pen.penW * 0.85
        fillColor: "transparent"
        capStyle: pen.cap
        joinStyle: ShapePath.RoundJoin
        PathPolyline { path: pen.poly(5) }
    }
}
