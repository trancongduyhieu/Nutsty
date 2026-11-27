import QtQuick
import QtQuick.Shapes
import "window_frame_logic.js" as Frame

// Maximized-window frame (liner style): a dark glass band around the app with notches hanging from
// the top edge, one continuous shape so the 1px hairline runs unbroken around every notch.
// Content widths include the notch's own padding; 0 means that notch is absent.
// Takes no mouse input: whatever sits in the notches is drawn by the owner above this item.
Item {
    id: root
    property real leftContentWidth: 0
    property real centerContentWidth: 0
    property real rightContentWidth: 0
    property color fillColor: Qt.rgba(0, 0, 0, 0.35)
    property color hairlineColor: Qt.rgba(1, 1, 1, 0.10)

    // Where the owner lays out each notch's content (x of its content box; top is band + 0)
    readonly property real band: Frame.B
    readonly property real contentHeight: Frame.H - 4
    readonly property real centerNotchX: Frame.centerNotchX(Math.round(width), leftContentWidth, centerContentWidth, rightContentWidth)
    readonly property bool centerVisible: centerNotchX >= 0
    readonly property real centerContentX: centerNotchX + Frame.R
    readonly property real rightContentX: Math.round(width) - Frame.B - Frame.notchOuterWidth("end", rightContentWidth) + Frame.R
    readonly property real leftContentX: Frame.B

    readonly property bool sized: width > 0 && height > 0
    readonly property string holePath: sized
        ? Frame.innerPath(Math.round(width), Math.round(height), leftContentWidth, centerContentWidth, rightContentWidth) : ""
    readonly property string bandPath: sized
        ? Frame.framePath(Math.round(width), Math.round(height), leftContentWidth, centerContentWidth, rightContentWidth) : ""

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillRule: ShapePath.OddEvenFill
            fillColor: root.fillColor
            strokeWidth: -1
            PathSvg { path: root.bandPath }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.hairlineColor
            strokeWidth: 1
            PathSvg { path: root.holePath }
        }
    }
}
