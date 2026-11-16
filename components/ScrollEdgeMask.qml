import QtQuick

// Alpha mask that fades a list's content out at its top and bottom edges, like a scroll edge
// effect. Put it beside the list with anchors.fill: list and use it as a MultiEffect maskSource
// (maskThresholdMin 0.5 + maskSpreadAtMin 1.0 reads the alpha as a smooth ramp).
// Each edge only fades while there is more content past it.
Item {
    id: root

    property Flickable flickable: null
    property real fadeLength: 28

    readonly property bool fadeTop: flickable !== null && !flickable.atYBeginning
    readonly property bool fadeBottom: flickable !== null && !flickable.atYEnd
    readonly property real frac: height > 0 ? Math.min(0.45, fadeLength / height) : 0

    visible: false
    layer.enabled: true

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.fadeTop ? "transparent" : "#ffffff" }
            GradientStop { position: root.frac; color: "#ffffff" }
            GradientStop { position: 1.0 - root.frac; color: "#ffffff" }
            GradientStop { position: 1.0; color: root.fadeBottom ? "transparent" : "#ffffff" }
        }
    }
}
