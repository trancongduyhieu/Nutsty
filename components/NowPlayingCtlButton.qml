import QtQuick
import "."

// Frameless white transport button used by NowPlayingControls (SimpMusic-like, no accent tint).
// `toggle` buttons (shuffle / repeat) dim when off and show a small dot when on.
Item {
    id: cb
    property string icon: ""
    property bool on: false
    property bool toggle: false
    property real size: 40
    property real iconScale: 0.6
    signal clicked()
    width: size; height: size

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Qt.rgba(1, 1, 1, cbMouse.pressed ? 0.16 : (cbH.hovered ? 0.09 : 0.0))
        Behavior on color { ColorAnimation { duration: 120 } }
    }
    HoverHandler { id: cbH }
    AppIcon {
        anchors.centerIn: parent
        source: cb.icon
        iconSize: Math.round(cb.size * cb.iconScale)
        color: "#ffffff"
        opacity: (!cb.toggle || cb.on) ? 1.0 : (cbH.hovered ? 0.8 : 0.5)
        // AppIcon's brightness lift pushes white-filled SVGs past their alpha, so plain opacity left them
        // fully white; rendering into a layer clamps the colour first, then opacity dims it correctly
        layer.enabled: cb.toggle
        scale: cbMouse.pressed ? 0.9 : 1.0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }
    }
    Rectangle {
        visible: cb.toggle
        opacity: cb.on ? 1 : 0
        width: 4; height: 4; radius: 2
        color: "#ffffff"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 1
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }
    MouseArea { id: cbMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: cb.clicked() }
}
