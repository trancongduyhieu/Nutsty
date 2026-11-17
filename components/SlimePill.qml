import QtQuick

// Selection pill that moves like slime: the edge on the side it travels toward lands quickly,
// the other edge is dragged behind and wobbles before it settles. Set targetX / targetWidth
// (in the parent's coordinates); y, height, radius and colours are set by the user.
Rectangle {
    id: pill

    property real targetX: 0
    property real targetWidth: 0
    // Leading edge: fast and only slightly springy. Trailing edge: slower and bouncy.
    property real leadSpring: 7.0
    property real leadDamping: 0.55
    property real trailSpring: 2.6
    property real trailDamping: 0.3
    // How far the trailing edge may squeeze the pill when it overshoots (fraction of targetWidth)
    property real minSquash: 0.8

    property real leftEdge: 0
    property real rightEdge: 0
    property bool movingRight: true
    property bool ready: false

    // The leading edge is the anchor; when the trailing edge overshoots, the pill squeezes a little
    // instead of collapsing, which reads as the wobble of a soft blob
    width: Math.max(targetWidth * minSquash, rightEdge - leftEdge)
    x: movingRight ? rightEdge - width : leftEdge

    function settle() {
        var nl = targetX, nr = targetX + targetWidth;
        // No place yet (first layout pass): jump there instead of growing out of the corner
        if (rightEdge - leftEdge <= 0.5) {
            ready = false;
            leftEdge = nl;
            rightEdge = nr;
            ready = true;
            return;
        }
        if (nl !== leftEdge) movingRight = nl > leftEdge;
        else if (nr !== rightEdge) movingRight = nr > rightEdge;
        leftEdge = nl;
        rightEdge = nr;
    }
    onTargetXChanged: settle()
    onTargetWidthChanged: settle()
    Component.onCompleted: { settle(); ready = true; }

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
