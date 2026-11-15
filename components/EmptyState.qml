import QtQuick
import "."

// Reusable empty state: an icon on a soft polar shape that pops in and spins one full turn
// whenever it becomes visible, then a title and an optional description underneath.
// Shapes reuse the reveal petal formula: r = 1 - depth + depth * ((0.5 + 0.5 cos(lobes * t)) ^ sharp).
Item {
    id: es

    property string icon: "../assets/icons/material/ms-music_note.svg"
    property string title: ""
    property string description: ""
    property color accentColor: Theme.accent
    property real badgeSize: 88
    // "cookie" | "flower" | "clover" | "burst" | "puffy"
    property string shape: "cookie"
    // Optional call-to-action pill under the description
    property string actionText: ""
    signal actionClicked()

    readonly property var _shapes: ({
        "cookie": [9, 0.09, 1.0],
        "flower": [8, 0.30, 0.5],
        "clover": [4, 0.40, 0.55],
        "burst": [12, 0.20, 2.6],
        "puffy": [6, 0.16, 0.5]
    })

    implicitWidth: Math.max(badge.width, titleText.implicitWidth, 240)
    implicitHeight: col.implicitHeight

    function play() {
        arriveAnim.restart();
    }
    onVisibleChanged: if (visible) play()
    Component.onCompleted: if (visible) play()

    Column {
        id: col
        anchors.centerIn: parent
        width: parent.width
        spacing: 14

        Item {
            id: badge
            width: es.badgeSize
            height: es.badgeSize
            anchors.horizontalCenter: parent.horizontalCenter
            scale: 1.0

            Canvas {
                id: shapeCanvas
                anchors.fill: parent
                antialiasing: true
                renderStrategy: Canvas.Cooperative
                property color fill: Qt.rgba(es.accentColor.r, es.accentColor.g, es.accentColor.b, 0.30)
                onFillChanged: requestPaint()
                onWidthChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var p = es._shapes[es.shape] || es._shapes["cookie"];
                    var lobes = p[0], depth = p[1], sharp = p[2];
                    var cx = width / 2, cy = height / 2, R = Math.min(cx, cy) - 1;
                    ctx.beginPath();
                    var steps = 180;
                    for (var i = 0; i <= steps; ++i) {
                        var t = i / steps * Math.PI * 2;
                        var r = R * ((1 - depth) + depth * Math.pow(0.5 + 0.5 * Math.cos(lobes * t), sharp));
                        var x = cx + r * Math.cos(t), y = cy + r * Math.sin(t);
                        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                    }
                    ctx.closePath();
                    ctx.fillStyle = fill;
                    ctx.fill();
                }
            }

            AppIcon {
                id: badgeIcon
                anchors.centerIn: parent
                source: es.icon
                iconSize: Math.round(es.badgeSize * 0.4)
                color: "#ffffff"
            }
        }

        Text {
            id: titleText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: es.title
            visible: text.length > 0
            wrapMode: Text.WordWrap
            font.family: Theme.fontFamily
            font.pixelSize: 18
            font.weight: Font.Bold
            color: "#ffffff"
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: es.description
            visible: text.length > 0
            wrapMode: Text.WordWrap
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.Medium
            color: Qt.rgba(1, 1, 1, 0.6)
        }

        Rectangle {
            visible: es.actionText.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            width: actionLabel.implicitWidth + 36
            height: 38
            radius: 19
            color: Qt.rgba(es.accentColor.r, es.accentColor.g, es.accentColor.b, actionMouse.containsMouse ? 0.42 : 0.28)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)
            scale: actionMouse.pressed ? 0.96 : (actionMouse.containsMouse ? 1.04 : 1.0)
            Behavior on color { ColorAnimation { duration: 140 } }
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
            Text {
                id: actionLabel
                anchors.centerIn: parent
                text: es.actionText
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.Bold
                color: "#ffffff"
            }
            MouseArea {
                id: actionMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: es.actionClicked()
            }
        }
    }

    ParallelAnimation {
        id: arriveAnim
        NumberAnimation { target: badge; property: "scale"; from: 0.4; to: 1.0; duration: 700; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
        NumberAnimation { target: shapeCanvas; property: "rotation"; from: -360; to: 0; duration: 1100; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        NumberAnimation { target: badgeIcon; property: "scale"; from: 0.6; to: 1.0; duration: 600; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
        NumberAnimation { target: col; property: "opacity"; from: 0.0; to: 1.0; duration: 260; easing.type: Easing.OutCubic }
    }
}
