import QtQuick

// Selection pill that moves like slime. The edge on the side it travels toward runs ahead and
// stops dead at the target as if it hit a wall: that side flattens and the blob splats (wider
// and squatter for a moment, then jiggles back). The other edge is dragged behind on a softer
// spring and wobbles before it settles. Set targetX / targetWidth (parent coordinates);
// y, height, radius and colours are set by the user.
Rectangle {
    id: pill

    property real targetX: 0
    property real targetWidth: 0
    // Leading edge: fast; it would overshoot, but the wall stops it at the target
    property real leadSpring: 5.0
    property real leadDamping: 0.45
    // Trailing edge: slower and bouncy
    property real trailSpring: 1.7
    property real trailDamping: 0.2
    // How far the trailing edge may squeeze the pill when it overshoots (fraction of targetWidth)
    property real minSquash: 0.76
    // Splat on impact: share of the width pushed into height for a moment
    property real impactStrength: 0.12

    property real leftEdge: 0
    property real rightEdge: 0
    property real goalLeft: 0
    property real goalRight: 0
    property bool movingRight: true
    property bool ready: false
    property bool impactArmed: false
    property real impact: 0

    // The wall: the leading edge never passes its goal
    readonly property real wallLeft: movingRight ? leftEdge : Math.max(leftEdge, goalLeft)
    readonly property real wallRight: movingRight ? Math.min(rightEdge, goalRight) : rightEdge

    // The leading edge is the anchor; when the trailing edge overshoots, the pill squeezes a little
    // instead of collapsing, which reads as the wobble of a soft blob
    width: Math.max(targetWidth * minSquash, wallRight - wallLeft)
    x: movingRight ? wallRight - width : wallLeft

    // Flatten the side that hit the wall while the splat lasts
    readonly property real wallRadius: radius * Math.max(0.35, 1 - impact * 0.9)
    topLeftRadius: movingRight ? radius : wallRadius
    bottomLeftRadius: movingRight ? radius : wallRadius
    topRightRadius: movingRight ? wallRadius : radius
    bottomRightRadius: movingRight ? wallRadius : radius

    transform: Scale {
        origin.x: pill.movingRight ? pill.width : 0
        origin.y: pill.height / 2
        xScale: 1 - pill.impact * pill.impactStrength
        yScale: 1 + pill.impact * pill.impactStrength * 0.7
    }

    function settle() {
        var nl = targetX, nr = targetX + targetWidth;
        goalLeft = nl;
        goalRight = nr;
        // No place yet (first layout pass): jump there instead of growing out of the corner
        if (rightEdge - leftEdge <= 0.5) {
            ready = false;
            leftEdge = nl;
            rightEdge = nr;
            ready = true;
            return;
        }
        var dir = nl !== leftEdge ? nl > leftEdge : nr > rightEdge;
        // Only a real move (not a width tweak) hits the wall
        if (Math.abs(nl - leftEdge) > 4) {
            movingRight = dir;
            impactArmed = true;
            // The leading edge leaves now; the trailing edge stays stuck for a moment and is then
            // dragged after it, so the leading side clearly reaches the wall first
            if (movingRight) rightEdge = nr; else leftEdge = nl;
            trailRelease.restart();
            return;
        }
        trailRelease.stop();
        leftEdge = nl;
        rightEdge = nr;
    }
    property int trailDelay: 120
    Timer {
        id: trailRelease
        interval: pill.trailDelay
        onTriggered: {
            if (pill.movingRight) pill.leftEdge = pill.goalLeft;
            else pill.rightEdge = pill.goalRight;
        }
    }
    onTargetXChanged: settle()
    onTargetWidthChanged: settle()
    Component.onCompleted: { settle(); ready = true; }

    // The leading edge reaching the wall starts the splat once per move
    function checkImpact() {
        if (!impactArmed) return;
        var hit = movingRight ? rightEdge >= goalRight - 0.5 : leftEdge <= goalLeft + 0.5;
        if (hit) {
            impactArmed = false;
            splat.restart();
        }
    }
    onRightEdgeChanged: checkImpact()
    onLeftEdgeChanged: checkImpact()

    SequentialAnimation {
        id: splat
        NumberAnimation { target: pill; property: "impact"; to: 1; duration: 130; easing.type: Easing.OutQuad }
        NumberAnimation { target: pill; property: "impact"; to: 0; duration: 900; easing.type: Easing.OutElastic; easing.amplitude: 1.0; easing.period: 0.55 }
    }

    Behavior on leftEdge {
        enabled: pill.ready
        SpringAnimation {
            spring: pill.movingRight ? pill.trailSpring : pill.leadSpring
            damping: pill.movingRight ? pill.trailDamping : pill.leadDamping
            epsilon: 0.25
        }
    }
    Behavior on rightEdge {
        enabled: pill.ready
        SpringAnimation {
            spring: pill.movingRight ? pill.leadSpring : pill.trailSpring
            damping: pill.movingRight ? pill.leadDamping : pill.trailDamping
            epsilon: 0.25
        }
    }
}
