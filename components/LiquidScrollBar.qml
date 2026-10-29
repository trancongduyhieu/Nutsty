import QtQuick
import QtQuick.Controls.Basic
import "."

// =============================================================================
// LiquidScrollBar.qml
// Deep Module: Reusable Liquid Glass ScrollBar with Snell Refraction
// Follows /codebase-design & /improve-codebase-architecture:
// Small interface, deep implementation, 100% locality, zero clutter when idle.
// Automatically fades out completely (opacity = 0) when not scrolling.
// =============================================================================
ScrollBar {
    id: control

    property Item backgroundSourceItem: (typeof masterAppSurface !== "undefined" ? masterAppSurface : null)
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent

    implicitWidth: 10
    implicitHeight: 100
    policy: ScrollBar.AsNeeded
    hoverEnabled: true

    // Auto-hide Timer: Appears on scroll/drag/hover, fades out completely when idle
    property bool isScrolling: false

    Timer {
        id: fadeTimer
        interval: 900
        repeat: false
        onTriggered: control.isScrolling = false
    }

    onPositionChanged: {
        if (control.size < 1.0) {
            control.isScrolling = true;
            fadeTimer.restart();
        }
    }

    onPressedChanged: {
        if (control.pressed) {
            fadeTimer.stop();
            control.isScrolling = true;
        } else {
            fadeTimer.restart();
        }
    }

    // Fully invisible (opacity = 0.0) when idle; 1.0 when scrolling, hovered or dragging
    readonly property bool shouldBeVisible: (control.size < 1.0) && (control.hovered || control.pressed || control.isScrolling)
    opacity: shouldBeVisible ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    background: Rectangle {
        color: "transparent"
    }

    contentItem: Item {
        id: thumbSlot
        implicitWidth: 8
        implicitHeight: 60
        visible: control.size < 1.0

        // Adaptive thumb width: 6px resting, 9px on hover/drag
        property real thumbWidth: (control.hovered || control.pressed) ? 9 : 6
        Behavior on thumbWidth { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }

        Item {
            anchors.centerIn: parent
            width: thumbSlot.thumbWidth
            height: parent.height

            LiquidGlass {
                anchors.fill: parent
                radius: width / 2
                displacement: 14.0
                aberration: 0.05
                bevelWidth: Math.max(3.0, width / 2)
                blurRadius: 0.5
                colorBleed: 0.94
                tintColor: Qt.rgba(control.accentColor.r, control.accentColor.g, control.accentColor.b, (control.hovered || control.pressed) ? 0.45 : 0.28)
                backgroundSourceItem: control.backgroundSourceItem
                isFlowActive: control.pressed
            }
        }
    }
}
