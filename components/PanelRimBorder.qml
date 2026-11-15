import QtQuick
import QtQuick.Effects

// Shared hairline rim for floating panels (SSOT: edit the rim look here only).
// Mirrors the LiquidGlass shader rim (white light blended with the song accent, brighter toward the
// top light source) so a panel looks identical whether its backdrop is glass or cover art.
// Host it OUTSIDE any masked layer: its own antialiased edge then covers the mask edge (no black jaggies).
Item {
    id: rim

    property color accentColor: Theme.accent
    property real topLeftRadius: 20
    property real bottomLeftRadius: 20
    property real topRightRadius: 20
    property real bottomRightRadius: 20
    property real borderWidth: 1.2

    property color rimAccent: accentColor
    Behavior on rimAccent { ColorAnimation { duration: 400; easing.type: Easing.InOutQuad } }
    // dynamicRimColor in liquid_glass.frag: mix(white, accent * 1.5, ~0.75)
    readonly property color rimColor: Qt.rgba(
        0.25 + 0.75 * Math.min(1.0, rimAccent.r * 1.5),
        0.25 + 0.75 * Math.min(1.0, rimAccent.g * 1.5),
        0.25 + 0.75 * Math.min(1.0, rimAccent.b * 1.5), 1.0)

    // Base optical hairline around the whole edge
    Rectangle {
        anchors.fill: parent
        topLeftRadius: rim.topLeftRadius
        bottomLeftRadius: rim.bottomLeftRadius
        topRightRadius: rim.topRightRadius
        bottomRightRadius: rim.bottomRightRadius
        color: "transparent"
        antialiasing: true
        border.width: rim.borderWidth
        border.color: Qt.rgba(rim.rimColor.r, rim.rimColor.g, rim.rimColor.b, 0.40)
    }

    // Specular sheen: extra light on the upper edge, fading out downward
    Rectangle {
        id: sheen
        anchors.fill: parent
        topLeftRadius: rim.topLeftRadius
        bottomLeftRadius: rim.bottomLeftRadius
        topRightRadius: rim.topRightRadius
        bottomRightRadius: rim.bottomRightRadius
        color: "transparent"
        antialiasing: true
        border.width: rim.borderWidth
        border.color: Qt.rgba(rim.rimColor.r, rim.rimColor.g, rim.rimColor.b, 0.55)
        visible: false
        layer.enabled: rim.visible && rim.width > 0
    }
    Rectangle {
        id: sheenFade
        anchors.fill: parent
        visible: false
        layer.enabled: rim.visible && rim.width > 0
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#ffffffff" }
            GradientStop { position: 0.35; color: "#55ffffff" }
            GradientStop { position: 0.7; color: "#00ffffff" }
        }
    }
    MultiEffect {
        anchors.fill: parent
        source: sheen
        maskEnabled: true
        maskSource: sheenFade
        maskThresholdMin: 0.0
        maskSpreadAtMin: 1.0
        autoPaddingEnabled: false
    }
}
