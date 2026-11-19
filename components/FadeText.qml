import QtQuick

// Text that never snaps: when `value` changes it fades out, swaps, fades back in.
Text {
    id: t
    property string value: ""
    property real motion: 1
    property bool ready: false
    onValueChanged: { if (ready) swap.restart(); }
    Component.onCompleted: { text = value; ready = true; }
    SequentialAnimation {
        id: swap
        NumberAnimation { target: t; property: "opacity"; to: 0; duration: 110 * t.motion; easing.type: Easing.OutCubic }
        ScriptAction { script: t.text = t.value }
        NumberAnimation { target: t; property: "opacity"; to: 1; duration: 240 * t.motion; easing.type: Easing.OutExpo }
    }
}
