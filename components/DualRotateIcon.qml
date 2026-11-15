import QtQuick
import "."

Item {
    id: root

    property string iconSource: ""
    property real size: 36
    property real iconSize: Math.round(size * 0.5)
    property real radius: size / 2

    // Dynamic Chromatic Salience & Palette binding
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent
    property color bgColor: isHovered
        ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.22)
        : Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.12)
    property color borderColor: isHovered
        ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.45)
        : Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.22)
    property real borderWidth: 1
    property color iconColor: isHovered ? "#ffffff" : Qt.rgba(1, 1, 1, 0.85)
    property bool showBackground: true

    // Dual-Rotation Angles: Plate turns +24 deg, Icon counter-rotates -10 deg
    // Reference: Swiftify ShapeIcon.qml
    property real bgRotationAngle: 24
    property real iconRotationAngle: -10

    // Hover & Press states: Can be set externally or detected internally if interactive
    property bool hovered: false
    property bool pressed: false
    property bool interactive: false

    readonly property bool isHovered: hovered || (interactive && mouseArea.containsMouse)
    readonly property bool isPressed: pressed || (interactive && mouseArea.pressed)

    // Squish đàn hồi (Spring squish scale)
    property bool enableSquish: true
    property real downScale: 0.88
    property real hoverScale: 1.06

    scale: !enabled ? 1.0 : (enableSquish ? (isPressed ? downScale : (isHovered ? hoverScale : 1.0)) : 1.0)
    Behavior on scale { SpringBounce {} }

    signal clicked()

    implicitWidth: size
    implicitHeight: size

    // Layer 1: Background Plate / Container (Rotates +24° on hover)
    Rectangle {
        id: bgPlate
        anchors.fill: parent
        radius: root.radius
        color: root.bgColor
        border.color: root.borderColor
        border.width: root.borderWidth
        visible: root.showBackground
        transformOrigin: Item.Center
        rotation: root.isHovered ? root.bgRotationAngle : 0

        Behavior on rotation { SpringBounce {} }
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
    }

    // Layer 2: Inner Icon Container (Counter-rotates -10° on hover)
    Item {
        id: iconContainer
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        transformOrigin: Item.Center
        rotation: root.isHovered ? root.iconRotationAngle : 0

        Behavior on rotation { SpringBounce {} }

        AppIcon {
            anchors.fill: parent
            source: root.iconSource
            iconSize: root.iconSize
            color: root.iconColor
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.interactive && root.enabled
        hoverEnabled: true
        cursorShape: (root.interactive && root.enabled) ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
