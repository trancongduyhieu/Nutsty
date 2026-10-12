import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "."

Item {
    id: root

    property Item backgroundSourceItem: null
    property real extraDependency: 0.0
    property real radius: 16
    property real borderWidth: 1.5
    property color accentColor: Theme.accentColor
    property color subtleAccentColor: Qt.lighter(accentColor, 1.35)
    property int duration: 4000
    property bool isHovered: cardMouse.containsMouse

    default property alias contentData: innerContent.data

    implicitWidth: 760
    implicitHeight: 194

    // =========================================================================
    // 1. DYNAMIC LIQUID GLASS BACKGROUND SURFACE (Option 1: Optical Liquid Glass)
    // =========================================================================
    LiquidGlass {
        id: liquidSurface
        anchors.fill: parent
        radius: root.radius
        displacement: 18.0
        aberration: 0.03
        bevelWidth: 24.0
        tintColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
        backgroundSourceItem: root.backgroundSourceItem
        extraDependency: root.extraDependency
        isFlowActive: false

        // A. Subtle Dark Scrim on Surface (Ensures contrast & legibility per smooth-scrim-gradient)
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: Qt.rgba(0.04, 0.05, 0.07, 0.52)
        }

        // B. Horizontal Ambient Soft Gradient (Melts smoothly without muddy dark drag)
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, root.isHovered ? 0.22 : 0.16)
                    Behavior on color { ColorAnimation { duration: 250 } }
                }
                GradientStop {
                    position: 0.50
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, root.isHovered ? 0.11 : 0.07)
                    Behavior on color { ColorAnimation { duration: 250 } }
                }
                GradientStop {
                    position: 1.0
                    // Carry our own RGB with gentle alpha rather than black Color.Transparent (per smooth-scrim-gradient trap #2)
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, root.isHovered ? 0.06 : 0.03)
                    Behavior on color { ColorAnimation { duration: 250 } }
                }
            }
        }



        // D. Static Uniform Hairline Accent Border (360° perimeter, zero cold/black edge per liquid-glass-backdrop trap #1)
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: "transparent"
            border.color: root.isHovered ?
                Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35) :
                Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
            border.width: root.borderWidth
            Behavior on border.color { ColorAnimation { duration: 200 } }
        }
    }

    // 2. HOLLOW BORDER MASK (Pure stroke 1.5px, center is 100% transparent, ZERO light leaks from center)
    Shape {
        id: hollowBorderMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        ShapePath {
            strokeWidth: root.borderWidth
            strokeColor: "#ffffff"
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathRectangle {
                x: root.borderWidth / 2
                y: root.borderWidth / 2
                width: hollowBorderMask.width - root.borderWidth
                height: hollowBorderMask.height - root.borderWidth
                radius: root.radius
            }
        }
    }

    // 3. ROTATING BEAM (Masked strictly to hollow border stroke!)
    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: hollowBorderMask
            autoPaddingEnabled: false
        }

        Item {
            id: beamContainer
            anchors.centerIn: parent
            width: Math.max(root.width, root.height) * 1.6
            height: width

            Shape {
                anchors.fill: parent
                ShapePath {
                    strokeColor: "transparent"
                    fillGradient: ConicalGradient {
                        centerX: beamContainer.width / 2
                        centerY: beamContainer.height / 2
                        angle: 0

                        GradientStop { position: 0.00; color: "transparent" }
                        GradientStop { position: 0.03; color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.40) }
                        GradientStop { position: 0.07; color: "#ffffff" }
                        GradientStop { position: 0.11; color: root.subtleAccentColor }
                        GradientStop { position: 0.16; color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20) }
                        GradientStop { position: 0.20; color: "transparent" }
                        GradientStop { position: 1.00; color: "transparent" }
                    }
                    startX: 0; startY: 0
                    PathLine { x: beamContainer.width; y: 0 }
                    PathLine { x: beamContainer.width; y: beamContainer.height }
                    PathLine { x: 0; y: beamContainer.height }
                    PathLine { x: 0; y: 0 }
                }
            }

            NumberAnimation on rotation {
                from: 0
                to: 360
                duration: root.duration
                loops: Animation.Infinite
                running: root.hovered || cardMouse.containsMouse
            }
        }
    }

    // 4. INNER CONTENT SLOT
    Item {
        id: innerContent
        anchors.fill: parent
        anchors.margins: root.borderWidth
    }

    MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }
}
