import QtQuick

// Text that never snaps: when `value` changes it fades out, swaps, fades back in.
Text {
    id: t
    property string value: ""
    property real motion: 1
    property var key: ""          // fade only when the key changes; live figures (percent, speed) update in place
    property bool ready: false
    property var lastKey: ""
    onValueChanged: {
        if (!ready) return;
        if (key === lastKey) { if (!swap.running) text = value; return; }
        lastKey = key;
        swap.restart();
    }
    onKeyChanged: { if (ready && key !== lastKey) { lastKey = key; swap.restart(); } }
    Component.onCompleted: { text = value; lastKey = key; ready = true; }
    SequentialAnimation {
        id: swap
        NumberAnimation { target: t; property: "opacity"; to: 0; duration: 110 * t.motion; easing.type: Easing.OutCubic }
        ScriptAction { script: t.text = t.value }
        NumberAnimation { target: t; property: "opacity"; to: 1; duration: 240 * t.motion; easing.type: Easing.OutExpo }
    }
}
