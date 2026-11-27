import QtQuick
import QtQuick.Shapes
import "window_frame_logic.js" as Frame

// Window frame (liner style): a dark glass band around the app with notches hanging from
// the top edge, one continuous shape so the 1px hairline runs unbroken around every notch.
// Content widths include the notch's own padding; 0 means that notch is absent.
// Takes no mouse input: whatever sits in the notches is drawn by the owner above this item.
Item {
    id: root
    property real leftContentWidth: 0
    property real centerContentWidth: 0
    property real rightContentWidth: 0
    // the hole's corner radius: concentric with the window corner (24 - band) when windowed
    property real cornerRadius: Frame.RC
    // extra depth of the center notch while it is open (it grows down like a Dynamic Island)
    property real centerExtraHeight: 0
    // extra darkness over the center notch alone (0..1): it deepens while open so it reads as one island
    property real centerTint: 0
    property color fillColor: Qt.rgba(0, 0, 0, 0.35)
    property color hairlineColor: Qt.rgba(1, 1, 1, 0.10)

    // Where the owner lays out each notch's content (x of its content box; top is band + 0)
    readonly property real band: Frame.B
    readonly property real contentHeight: Frame.H - 4
    readonly property real centerNotchX: Frame.centerNotchX(Math.round(width), leftContentWidth, centerContentWidth, rightContentWidth)
    readonly property bool centerVisible: centerNotchX >= 0
    readonly property real centerContentX: centerNotchX + Frame.R
    // horizontal middle of the center notch: content stays anchored here while the notch grows
    readonly property real centerMid: centerContentX + Math.ceil(Math.max(0, centerContentWidth) / 2) * 2 / 2
    readonly property real rightContentX: Math.round(width) - Frame.B - Frame.notchOuterWidth("end", rightContentWidth) + Frame.R
    readonly property real leftContentX: Frame.B

    readonly property bool sized: width > 0 && height > 0
    readonly property string holePath: sized
        ? Frame.innerPath(Math.round(width), Math.round(height), leftContentWidth, centerContentWidth, rightContentWidth, cornerRadius, centerExtraHeight) : ""
    readonly property string bandPath: sized
        ? Frame.framePath(Math.round(width), Math.round(height), leftContentWidth, centerContentWidth, rightContentWidth, cornerRadius, centerExtraHeight) : ""

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
            fillColor: Qt.rgba(0, 0, 0, root.centerTint)
            strokeWidth: -1
            PathSvg { path: root.centerTint > 0.001 && root.sized
                ? Frame.centerNotchPath(Math.round(root.width), root.leftContentWidth, root.centerContentWidth, root.rightContentWidth, root.centerExtraHeight) : "" }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.hairlineColor
            strokeWidth: 1
            PathSvg { path: root.holePath }
        }
    }
}
