import QtQuick
import QtQuick.Shapes
import "."

// Giant outline lettering for the "Big type" right panel look: stroke only, no fill, so the
// wallpaper shows through the letters. Each entry of `lines` is one line. The bundled
// Montserrat Black is squeezed sideways to read as a condensed poster face.
Item {
    id: root

    property var lines: []
    property color strokeColor: Theme.accent
    property real strokeWidth: 1.4
    property real pixelSize: 140
    // Horizontal squeeze that turns the wide face into a condensed one
    property real squeeze: 0.72
    property real lineHeight: 0.86

    FontLoader { id: heavyFont; source: "../assets/fonts/Montserrat-Black.ttf" }
    readonly property string family: (heavyFont.status === FontLoader.Ready && heavyFont.name !== "") ? heavyFont.name : "Montserrat"

    FontMetrics {
        id: fm
        font.family: root.family
        font.pixelSize: root.pixelSize
        font.weight: Font.Black
    }

    readonly property real rowHeight: Math.round(pixelSize * lineHeight)
    implicitHeight: lines.length * rowHeight + Math.round(pixelSize * 0.12)

    Column {
        transform: Scale { xScale: root.squeeze }

        Repeater {
            model: root.lines

            delegate: Shape {
                id: lineShape
                required property string modelData
                width: Math.ceil(fm.advanceWidth(lineShape.modelData)) + 4
                height: root.rowHeight
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: root.strokeColor
                    // Widened to make up for the sideways squeeze thinning the vertical strokes
                    strokeWidth: root.strokeWidth / root.squeeze
                    fillColor: "transparent"
                    joinStyle: ShapePath.RoundJoin

                    PathText {
                        x: 2
                        // Baseline near the bottom of the row: capitals fill it, accents may poke above.
                        // PathText places the glyph box's top at y in practice, so step back by the ascent.
                        y: Math.round(root.pixelSize * 0.80 - fm.ascent)
                        text: lineShape.modelData
                        font.family: root.family
                        font.pixelSize: root.pixelSize
                        font.weight: Font.Black
                    }
                }
            }
        }
    }
}
