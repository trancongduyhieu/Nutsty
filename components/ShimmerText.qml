import QtQuick

// Shared shimmering label (SSOT for the AutoMix "Cooking" word): the text rests dim and a soft band
// of light sweeps across it left to right (text_shimmer.frag), lighting each letter up and dimming it again.
Item {
    id: root

    property string text: ""
    property bool running: true
    property int pixelSize: 12
    property int fontWeight: Font.DemiBold
    property real letterSpacing: 0.6
    property real band: 0.32
    property real baseLevel: 0.42
    property int period: 1600

    implicitWidth: base.implicitWidth
    implicitHeight: base.implicitHeight
    width: implicitWidth
    height: implicitHeight

    property real sweep: 0
    NumberAnimation on sweep {
        from: 0; to: 1; duration: root.period; loops: Animation.Infinite
        easing.type: Easing.InOutSine
        running: root.visible && root.running
    }

    Text {
        id: base
        text: root.text
        font.family: Theme.fontFamily
        font.pixelSize: root.pixelSize
        font.weight: root.fontWeight
        font.letterSpacing: root.letterSpacing
        color: "#ffffff"
    }
    ShaderEffectSource {
        id: tex
        sourceItem: base
        hideSource: true
        live: true
        visible: false
    }
    ShaderEffect {
        anchors.fill: base
        property var source: tex
        property real u_sweep: root.sweep
        property real u_band: root.band
        property real u_base: root.baseLevel
        fragmentShader: Qt.resolvedUrl("../assets/shaders/text_shimmer.frag.qsb")
    }
}
