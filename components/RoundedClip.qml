import QtQuick

// Rounds another item's corners with an SDF shader (rounded_clip.frag): one anti-aliased pass,
// no dark fringe at the corners (a MultiEffect mask leaves one). Each corner can differ. The source item is hidden while
// radius > 0, so put this as a sibling filling the same area.
ShaderEffect {
    id: clip

    required property Item target
    property real radius: 0
    property real topLeftRadius: radius
    property real topRightRadius: radius
    property real bottomRightRadius: radius
    property real bottomLeftRadius: radius
    readonly property bool rounded: topLeftRadius > 0 || topRightRadius > 0 || bottomRightRadius > 0 || bottomLeftRadius > 0

    visible: rounded

    property variant source: ShaderEffectSource {
        sourceItem: clip.target
        hideSource: clip.rounded
        live: true
    }
    property vector2d u_resolution: Qt.vector2d(Math.max(1, width), Math.max(1, height))
    property vector4d u_radii: Qt.vector4d(topLeftRadius, topRightRadius, bottomRightRadius, bottomLeftRadius)
    fragmentShader: Qt.resolvedUrl("../assets/shaders/rounded_clip.frag.qsb")
}
