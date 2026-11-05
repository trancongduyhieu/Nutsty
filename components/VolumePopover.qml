import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "."

Item {
    id: root
    anchors.fill: parent
    z: 9999
    visible: opacity > 0.001
    opacity: isOpen ? 1.0 : 0.0
    enabled: isOpen

    Behavior on opacity {
        NumberAnimation { duration: 160; easing.type: Easing.OutQuad }
    }

    property bool isOpen: false
    property Item targetAnchorItem: null
    property real volume: 100.0
    property real prevVolume: 100.0
    property bool isSliding: false

    signal volumeChangeRequested(real newVol)

    function open() {
        isOpen = true;
    }

    function close() {
        isSliding = false;
        isOpen = false;
    }

    function toggle() {
        if (isOpen) close();
        else open();
    }

    // Dismiss Backdrop: Click anywhere outside to close and block click-through
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.ArrowCursor
        preventStealing: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: root.close()
    }

    // Capsule Popover Card
    Rectangle {
        id: capsuleCard
        width: 48
        height: 180
        radius: 14
        color: Qt.rgba(0.10, 0.11, 0.15, 0.96)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.20)

        // Drop shadow for clear elevation
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.50)
            shadowBlur: 0.8
            shadowVerticalOffset: 4
        }

        // Position dynamically directly above targetAnchorItem (volume button on PlayerBar)
        x: {
            if (root.targetAnchorItem) {
                var pt = root.targetAnchorItem.mapToItem(root, 0, 0);
                return Math.round(pt.x + (root.targetAnchorItem.width - width) / 2);
            }
            return Math.round(root.width - 240);
        }
        y: {
            if (root.targetAnchorItem) {
                var pt2 = root.targetAnchorItem.mapToItem(root, 0, 0);
                return Math.round(pt2.y - height - 12);
            }
            return Math.round(root.height - height - 80);
        }

        scale: root.isOpen ? 1.0 : 0.92
        transformOrigin: Item.Bottom
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        // Touch & Drag MouseArea for 1-click Volume Tuning
        MouseArea {
            id: volSliderMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            preventStealing: true

            function updateFromY(my) {
                var topY = 28.0;
                var botY = 146.0;
                var clamped = Math.max(topY, Math.min(botY, my));
                var frac = 1.0 - ((clamped - topY) / (botY - topY));
                var newVol = Math.round(Math.max(0, Math.min(100, frac * 100)));
                root.volumeChangeRequested(newVol);
            }

            onPressed: mouse => {
                root.isSliding = true;
                updateFromY(mouse.y);
            }
            onPositionChanged: mouse => {
                if (pressed || root.isSliding) {
                    updateFromY(mouse.y);
                }
            }
            onReleased: {
                root.isSliding = false;
            }
            onCanceled: {
                root.isSliding = false;
            }
            onWheel: wheel => {
                var step = wheel.angleDelta.y > 0 ? 5 : -5;
                root.volumeChangeRequested(Math.max(0, Math.min(100, root.volume + step)));
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            spacing: 8

            // 1. Percentage Text (Top)
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Math.round(root.volume)
                font.family: "Segoe UI, Inter, monospace"
                font.pixelSize: 11
                font.bold: true
                color: Qt.rgba(1, 1, 1, 0.85)
            }

            // 2. Vertical Slider Track (Middle)
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                width: 40

                Rectangle {
                    id: trackBg
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 4
                    radius: 2
                    color: Qt.rgba(1, 1, 1, 0.25)

                    // White fill from bottom to top
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: 4
                        height: parent.height * (root.volume / 100.0)
                        radius: 2
                        color: "#ffffff"
                    }

                    // Tactile knob dot
                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: "#ffffff"
                        border.color: Qt.rgba(0, 0, 0, 0.35)
                        border.width: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Math.max(0, Math.min(trackBg.height - height, trackBg.height * (1.0 - root.volume / 100.0) - height / 2))
                    }
                }
            }

            // 3. Mini Speaker Icon (Bottom) - Click to Mute / Unmute
            Item {
                Layout.alignment: Qt.AlignHCenter
                width: 24; height: 24
                z: 10

                AppIcon {
                    anchors.centerIn: parent
                    source: root.volume === 0 ? "../assets/icons/audio-volume-muted-symbolic.svg" : "../assets/icons/audio-volume-high-symbolic.svg"
                    iconSize: 15
                    color: root.volume === 0 ? "#ff5252" : Qt.rgba(1, 1, 1, 0.70)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.volume > 0) {
                            root.prevVolume = root.volume;
                            root.volumeChangeRequested(0);
                        } else {
                            root.volumeChangeRequested(root.prevVolume > 0 ? root.prevVolume : 100);
                        }
                    }
                }
            }
        }
    }
}
