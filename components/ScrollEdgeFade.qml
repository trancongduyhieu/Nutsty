pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

// Scroll edge effect for any Flickable/ListView: content fades out at an edge while there is
// more to scroll past it. Declare it next to the list, `ScrollEdgeFade { flickable: myList }`;
// it moves itself beside the list and installs a MultiEffect mask as the list's layer.effect.
// The layer is only on while the content overflows, so lists that fit cost nothing.
Item {
    id: root

    property Flickable flickable: null
    property real fadeLength: 28
    // Inferred from which axis overflows; set it explicitly for a list that can overflow both ways
    property bool horizontal: flickable !== null && flickable.contentWidth > flickable.width + 1
                              && flickable.contentHeight <= flickable.height + 1
    // Extra gate for lists that stay alive while hidden (closed panel, inactive tab)
    property bool when: true

    readonly property bool overflows: flickable !== null
        && (horizontal ? flickable.contentWidth > flickable.width + 1 : flickable.contentHeight > flickable.height + 1)
    // Off in Lite mode: any change inside the list re-renders the whole layer and mask
    readonly property bool liteMode: typeof win !== "undefined" && win && Boolean(win.liteMode)
    readonly property bool active: Theme.scrollEdgeFadeEnabled && !liteMode && when && overflows && flickable.visible
    readonly property bool fadeStart: flickable !== null && (horizontal ? !flickable.atXBeginning : !flickable.atYBeginning)
    readonly property bool fadeEnd: flickable !== null && (horizontal ? !flickable.atXEnd : !flickable.atYEnd)
    readonly property real span: horizontal ? width : height
    readonly property real frac: span > 0 ? Math.min(0.45, fadeLength / span) : 0

    // Whatever scrolls under the player bar changes what its frosted glass shows: wake it.
    // (The bar freezes its glass between updates so an idle window costs nothing.)
    Connections {
        target: root.flickable
        function onContentYChanged() { root.wakeGlass(); }
        function onContentXChanged() { root.wakeGlass(); }
    }
    function wakeGlass() {
        if (typeof win !== "undefined" && win && typeof win.triggerBackdropUpdate === "function") win.triggerBackdropUpdate();
    }

    parent: flickable ? flickable.parent : null
    // Plain geometry, not anchors: the host is often a Layout, which warns about anchored children
    x: flickable ? flickable.x : 0
    y: flickable ? flickable.y : 0
    width: flickable ? flickable.width : 0
    height: flickable ? flickable.height : 0
    visible: false
    layer.enabled: active

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: root.horizontal ? Gradient.Horizontal : Gradient.Vertical
            GradientStop { position: 0.0; color: root.fadeStart ? "transparent" : "#ffffff" }
            GradientStop { position: root.frac; color: "#ffffff" }
            GradientStop { position: 1.0 - root.frac; color: "#ffffff" }
            GradientStop { position: 1.0; color: root.fadeEnd ? "transparent" : "#ffffff" }
        }
    }

    Component {
        id: fadeEffect
        // maskThresholdMin 0.5 + maskSpreadAtMin 1.0 read the mask alpha as a smooth ramp
        MultiEffect {
            maskEnabled: true
            maskSource: root
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
            autoPaddingEnabled: false
        }
    }

    function install() {
        if (!flickable) return;
        flickable.layer.effect = fadeEffect;
        flickable.layer.enabled = Qt.binding(function() { return root.active; });
    }
    onFlickableChanged: install()
    Component.onCompleted: install()
}
