import QtQuick
import "."

Rectangle {
    id: root

    // Sizing & Geometry
    property real btnSize: 40
    property real btnHeight: 36
    property real btnWidth: 0
    property string text: ""
    property real radiusValue: height / 2
    radius: radiusValue

    implicitHeight: text !== "" ? btnHeight : btnSize
    implicitWidth: btnWidth > 0 ? btnWidth : (text !== "" ? (contentRow.implicitWidth + 24) : btnSize)

    // Icon & Typography
    property string iconSource: ""
    property real iconSize: text !== "" ? 15 : Math.round(btnSize * 0.5)
    property string fontFamily: Theme.fontFamily
    property int fontSize: 13
    property bool fontBold: true

    // Variants: "glass" (Liquid Glass, default), "ghost" (transparent transport), "filled" (solid CTA), "rose" (danger/delete)
    property string variant: "glass"

    // Dynamic Chromatic Salience & Palette binding
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent
    property color activeColor: accentColor
    property bool active: false
    property bool showActiveDot: false

    // Expressive Spring Squish & Hover Scale
    // Reference: Swiftify ShapeButton.qml (scale: down ? 0.88 : 1 with SpringAnimation)
    property real downScale: 0.88
    property real hoverScale: 1.06
    property bool enableSquish: true

    // Dual-Rotation feature: when enabled, background plate rotates +24° and icon rotates -10°
    property bool dualRotate: false
    property real bgRotationAngle: 24
    property real iconRotationAngle: -10

    // Tooltip
    property string tooltip: ""

    // Signal
    signal clicked()

    // State bindings
    readonly property bool isHovered: mouseArea.containsMouse && root.enabled
    readonly property bool isPressed: mouseArea.pressed && root.enabled

    scale: !enabled ? 1.0 : (enableSquish ? (isPressed ? downScale : (isHovered ? hoverScale : 1.0)) : 1.0)
    opacity: enabled ? 1.0 : 0.40

    // Transform rotation on root/background when dualRotate is true
    transformOrigin: Item.Center
    rotation: (dualRotate && isHovered) ? bgRotationAngle : 0

    // Material 3 Expressive Spatial Spring Behavior
    Behavior on scale { SpringBounce {} }
    Behavior on rotation { SpringBounce {} }
    Behavior on opacity { NumberAnimation { duration: 150 } }

    // Color resolution based on variant and state
    color: {
        if (variant === "ghost") {
            if (isPressed) return Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.25);
            if (isHovered) return Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.14);
            return "transparent";
        }
        if (variant === "filled") {
            if (isPressed) return Qt.darker(accentColor, 1.10);
            if (isHovered) return Qt.lighter(accentColor, 1.12);
            return accentColor;
        }
        if (variant === "rose") {
            if (isPressed) return Qt.rgba(244 / 255, 63 / 255, 94 / 255, 0.36);
            if (isHovered) return Qt.rgba(244 / 255, 63 / 255, 94 / 255, 0.24);
            return Qt.rgba(244 / 255, 63 / 255, 94 / 255, 0.12);
        }
        // "glass" default
        if (isPressed) return Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.32);
        if (isHovered) return Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.22);
        return Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.12);
    }

    border.width: 1
    border.color: {
        if (variant === "ghost") {
            if (isPressed) return Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.45);
            if (isHovered) return Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.25);
            return "transparent";
        }
        if (variant === "filled") {
            return "transparent";
        }
        if (variant === "rose") {
            if (isPressed) return Qt.rgba(244 / 255, 63 / 255, 94 / 255, 0.70);
            if (isHovered) return Qt.rgba(244 / 255, 63 / 255, 94 / 255, 0.50);
            return Qt.rgba(244 / 255, 63 / 255, 94 / 255, 0.28);
        }
        // "glass" default
        if (isPressed) return Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.65);
        if (isHovered) return Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.48);
        return Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.24);
    }

    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }

    // Content: Layout handling icon, text, and counter-rotation
    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: 8

        // Icon item with counter-rotation if dualRotate is true
        Item {
            id: iconWrapper
            visible: root.iconSource !== ""
            width: root.iconSize
            height: root.iconSize
            anchors.verticalCenter: parent.verticalCenter
            transformOrigin: Item.Center
            rotation: (root.dualRotate && root.isHovered) ? root.iconRotationAngle : 0

            Behavior on rotation { SpringBounce {} }

            AppIcon {
                anchors.fill: parent
                source: root.iconSource
                iconSize: root.iconSize
                color: {
                    if (root.variant === "filled") {
                        return Theme.isColorDark(root.accentColor) ? "#ffffff" : "#000000";
                    }
                    if (root.variant === "rose") return "#f43f5e";
                    if (root.active) return root.activeColor;
                    if (root.isHovered) return "#ffffff";
                    return Qt.rgba(1, 1, 1, 0.85);
                }
            }
        }

        // Text label
        Text {
            id: labelText
            visible: root.text !== ""
            text: root.text
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
            font.bold: root.fontBold
            anchors.verticalCenter: parent.verticalCenter
            color: {
                if (root.variant === "filled") {
                    return Theme.isColorDark(root.accentColor) ? "#ffffff" : "#000000";
                }
                if (root.variant === "rose") return "#f43f5e";
                if (root.active) return root.activeColor;
                if (root.isHovered) return "#ffffff";
                return Qt.rgba(1, 1, 1, 0.85);
            }
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    // Active Indicator Dot (e.g. for Shuffle / Repeat toggle state)
    Rectangle {
        id: activeDotIndicator
        width: 3
        height: 3
        radius: 1.5
        color: root.activeColor
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.showActiveDot && root.active
    }

    // Tooltip presentation
    Rectangle {
        id: tooltipBox
        visible: root.tooltip !== "" && root.isHovered
        anchors.bottom: parent.top
        anchors.bottomMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        width: tooltipText.implicitWidth + 14
        height: 24
        radius: 6
        color: Qt.rgba(0.08, 0.08, 0.10, 0.95)
        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
        border.width: 1
        z: 999

        Text {
            id: tooltipText
            anchors.centerIn: parent
            text: root.tooltip
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: "#ffffff"
        }
    }

    // Interaction handler
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.enabled) {
                root.clicked();
            }
        }
    }
}
