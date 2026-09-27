import QtQuick

Item {
    id: root
    clip: true
    implicitHeight: innerText.implicitHeight
    implicitWidth: innerText.implicitWidth

    property alias text: innerText.text
    property alias font: innerText.font
    property alias color: innerText.color
    property bool active: true
    property int startDelay: 1200
    property int endDelay: 1500
    property int scrollSpeed: 28  // ms per px
    property int returnSpeed: 18  // ms per px

    readonly property real overflowDist: Math.max(0, innerText.implicitWidth - root.width)
    readonly property bool needsScroll: overflowDist > 6

    Text {
        id: innerText
        x: 0
        font.family: Theme.fontFamily
        font.pixelSize: 10
        color: Theme.textSecondary

        SequentialAnimation {
            id: anim
            running: root.active && root.visible && root.needsScroll
            loops: Animation.Infinite

            PauseAnimation { duration: root.startDelay }
            NumberAnimation {
                target: innerText
                property: "x"
                to: -root.overflowDist
                duration: Math.max(1200, root.overflowDist * root.scrollSpeed)
                easing.type: Easing.InOutQuad
            }
            PauseAnimation { duration: root.endDelay }
            NumberAnimation {
                target: innerText
                property: "x"
                to: 0
                duration: Math.max(800, root.overflowDist * root.returnSpeed)
                easing.type: Easing.InOutQuad
            }
        }

        onTextChanged: {
            anim.restart();
            innerText.x = 0;
        }
    }

    onVisibleChanged: {
        if (!visible) innerText.x = 0;
    }

    onActiveChanged: {
        if (!active) innerText.x = 0;
    }

    onNeedsScrollChanged: {
        if (!needsScroll) innerText.x = 0;
    }
}
