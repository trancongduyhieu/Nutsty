import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import "cover_art.js" as CoverArt

// Square generated cover. Same variant + seedName + colors always draws the same picture.
Item {
    id: root

    property string variant: "marble"
    property string seedName: "Nutsty"
    property var colors: []
    // Playlist name written on the cover (bottom-left, Playfair Display), part of the saved PNG
    property string title: ""
    property bool showTitle: false
    property string titleFont: "Playfair Display"

    readonly property var d: CoverArt.layout(variant, seedName, colors)

    // Corner radius for on-screen use. Drawn with the same SDF shader as RoundedImage (one pass, no
    // dark fringe at the corners, unlike a MultiEffect mask). The saved PNG uses radius 0.
    property real radius: 0

    Item {
        id: content
        anchors.fill: parent
        clip: true

        Item {
            id: canvas
            width: root.d.size
            height: root.d.size
            scale: root.width / root.d.size
            transformOrigin: Item.TopLeft

            // ---------- marble ----------
            // Backdrop = background + blurred first shape. The blurred second shape goes over it with the
            // "overlay" blend (cover_overlay.frag), as upstream does with mix-blend-mode: overlay.
            Item {
                anchors.fill: parent
                visible: root.variant === "marble"

                Item {
                    id: marbleBack
                    anchors.fill: parent
                    visible: false

                    Rectangle { anchors.fill: parent; color: root.d.bg || "transparent" }

                    Item {
                        id: marbleShapeA
                        anchors.fill: parent
                        visible: false

                        Shape {
                            width: 80; height: 80
                            preferredRendererType: Shape.CurveRenderer
                            transform: [
                                Scale { xScale: root.d.a ? root.d.a.scale : 1; yScale: root.d.a ? root.d.a.scale : 1 },
                                Rotation { origin.x: 40; origin.y: 40; angle: root.d.a ? root.d.a.rotate : 0 },
                                Translate { x: root.d.a ? root.d.a.tx : 0; y: root.d.a ? root.d.a.ty : 0 }
                            ]
                            ShapePath {
                                strokeWidth: -1
                                fillColor: root.d.a ? root.d.a.color : "transparent"
                                PathSvg { path: "M32.414 59.35L50.376 70.5H72.5v-71H33.728L26.5 13.381l19.057 27.08L32.414 59.35z" }
                            }
                        }
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: marbleShapeA
                        autoPaddingEnabled: false
                        blurEnabled: true
                        blurMax: 44
                        blur: 1.0
                    }
                }

                Item {
                    id: marbleFront
                    anchors.fill: parent
                    visible: false

                    Item {
                        id: marbleShapeB
                        anchors.fill: parent
                        visible: false

                        Shape {
                            width: 80; height: 80
                            preferredRendererType: Shape.CurveRenderer
                            transform: [
                                Scale { xScale: root.d.b ? root.d.b.scale : 1; yScale: root.d.b ? root.d.b.scale : 1 },
                                Rotation { origin.x: 40; origin.y: 40; angle: root.d.b ? root.d.b.rotate : 0 },
                                Translate { x: root.d.b ? root.d.b.tx : 0; y: root.d.b ? root.d.b.ty : 0 }
                            ]
                            ShapePath {
                                strokeWidth: -1
                                fillColor: root.d.b ? root.d.b.color : "transparent"
                                PathSvg { path: "M22.216 24L0 46.75l14.108 38.129L78 86l-3.081-59.276-22.378 4.005 12.972 20.186-23.35 27.395L22.215 24z" }
                            }
                        }
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: marbleShapeB
                        autoPaddingEnabled: false
                        blurEnabled: true
                        blurMax: 44
                        blur: 1.0
                    }
                }

                ShaderEffect {
                    anchors.fill: parent
                    visible: root.variant === "marble"
                    property variant backdrop: ShaderEffectSource { sourceItem: marbleBack; textureSize: Qt.size(256, 256) }
                    property variant source: ShaderEffectSource { sourceItem: marbleFront; textureSize: Qt.size(256, 256) }
                    fragmentShader: Qt.resolvedUrl("../assets/shaders/cover_overlay.frag.qsb")
                }
            }

            // ---------- bauhaus ----------
            Item {
                anchors.fill: parent
                visible: root.variant === "bauhaus"

                Rectangle { anchors.fill: parent; color: root.d.bg || "transparent" }

                Rectangle {
                    x: 10; y: 30
                    width: 80
                    height: root.d.rectSquare ? 80 : 10
                    color: root.d.rect ? root.d.rect.color : "transparent"
                    antialiasing: true
                    transform: [
                        Rotation { origin.x: 30; origin.y: 10; angle: root.d.rect ? root.d.rect.rotate : 0 },
                        Translate { x: root.d.rect ? root.d.rect.tx : 0; y: root.d.rect ? root.d.rect.ty : 0 }
                    ]
                }

                Rectangle {
                    x: 24; y: 24
                    width: 32; height: 32; radius: 16
                    antialiasing: true
                    color: root.d.circle ? root.d.circle.color : "transparent"
                    transform: Translate { x: root.d.circle ? root.d.circle.tx : 0; y: root.d.circle ? root.d.circle.ty : 0 }
                }

                Rectangle {
                    x: 0; y: 39
                    width: 80; height: 2
                    antialiasing: true
                    color: root.d.line ? root.d.line.color : "transparent"
                    transform: [
                        Rotation { origin.x: 40; origin.y: 1; angle: root.d.line ? root.d.line.rotate : 0 },
                        Translate { x: root.d.line ? root.d.line.tx : 0; y: root.d.line ? root.d.line.ty : 0 }
                    ]
                }
            }

            // ---------- sunset ----------
            Column {
                anchors.fill: parent
                visible: root.variant === "sunset"

                Repeater {
                    model: 2
                    Rectangle {
                        required property int index
                        width: 80; height: 40
                        gradient: Gradient {
                            GradientStop { position: 0; color: root.d.colors ? root.d.colors[index * 2] : "transparent" }
                            GradientStop { position: 1; color: root.d.colors ? root.d.colors[index * 2 + 1] : "transparent" }
                        }
                    }
                }
            }

            // ---------- ring ----------
            Item {
                anchors.fill: parent
                visible: root.variant === "ring"

                Repeater {
                    model: root.variant === "ring" ? [
                        "M0 0h90v45H0z", "M0 45h90v45H0z",
                        "M83 45a38 38 0 00-76 0h76z", "M83 45a38 38 0 01-76 0h76z",
                        "M77 45a32 32 0 10-64 0h64z", "M77 45a32 32 0 11-64 0h64z",
                        "M71 45a26 26 0 00-52 0h52z", "M71 45a26 26 0 01-52 0h52z"
                    ] : []
                    Shape {
                        required property int index
                        required property string modelData
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeWidth: -1
                            fillColor: root.d.colors ? root.d.colors[index] : "transparent"
                            PathSvg { path: modelData }
                        }
                    }
                }

                Rectangle {
                    x: 22; y: 22
                    width: 46; height: 46; radius: 23
                    antialiasing: true
                    color: root.d.colors ? root.d.colors[8] : "transparent"
                }
            }

            // ---------- pixel ----------
            Item {
                anchors.fill: parent
                visible: root.variant === "pixel"

                Repeater {
                    model: root.variant === "pixel" && root.d.cells ? root.d.cells : []
                    Rectangle {
                        required property var modelData
                        x: modelData.x; y: modelData.y
                        width: 10; height: 10
                        color: modelData.color
                    }
                }
            }

            // ---------- waves, stripes, tiles, dots, aurora, folds: filled SVG paths ----------
            Item {
                anchors.fill: parent
                visible: !!root.d.layers

                Rectangle { anchors.fill: parent; color: root.d.bg || "transparent" }

                Item {
                    anchors.fill: parent
                    // aurora: the shapes melt into each other
                    layer.enabled: !!root.d.blur
                    layer.textureSize: Qt.size(160, 160)
                    layer.effect: MultiEffect {
                        autoPaddingEnabled: false
                        blurEnabled: true
                        blurMax: 48
                        blur: 1.0
                    }

                    Repeater {
                        model: root.d.layers || []
                        Shape {
                            required property var modelData
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                // a hair of the shape's own colour hides antialiasing seams between neighbours
                                strokeWidth: root.d.seal ? 0.35 : -1
                                strokeColor: root.d.seal ? modelData.color : "transparent"
                                joinStyle: ShapePath.MiterJoin
                                fillRule: ShapePath.WindingFill
                                fillColor: modelData.color
                                PathSvg { path: modelData.path }
                            }
                        }
                    }
                }
            }

            // ---------- beam ----------
            Item {
                anchors.fill: parent
                visible: root.variant === "beam"

                Rectangle { anchors.fill: parent; color: root.d.bg || "transparent" }

                Rectangle {
                    width: 36; height: 36
                    antialiasing: true
                    radius: root.d.round ? 18 : 6
                    color: root.d.wrapper || "transparent"
                    transform: [
                        Scale { xScale: root.d.scale || 1; yScale: root.d.scale || 1 },
                        Rotation { origin.x: 18; origin.y: 18; angle: root.d.rotate || 0 },
                        Translate { x: root.d.tx || 0; y: root.d.ty || 0 }
                    ]
                }

                Item {
                    width: 36; height: 36
                    transform: [
                        Rotation { origin.x: 18; origin.y: 18; angle: root.d.faceRotate || 0 },
                        Translate { x: root.d.faceTx || 0; y: root.d.faceTy || 0 }
                    ]

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: root.d.mouthOpen ? (root.d.face || "transparent") : "transparent"
                            strokeWidth: root.d.mouthOpen ? 1 : -1
                            capStyle: ShapePath.RoundCap
                            fillColor: root.d.mouthOpen ? "transparent" : (root.d.face || "transparent")
                            PathSvg {
                                path: root.d.mouthOpen
                                      ? "M15 " + (19 + (root.d.mouthSpread || 0)) + "c2 1 4 1 6 0"
                                      : "M13," + (19 + (root.d.mouthSpread || 0)) + " a1,0.75 0 0,0 10,0"
                            }
                        }
                    }

                    Rectangle {
                        x: 14 - (root.d.eyeSpread || 0); y: 14
                        width: 1.5; height: 2; radius: 0.75
                        antialiasing: true
                        color: root.d.face || "transparent"
                    }

                    Rectangle {
                        x: 20 + (root.d.eyeSpread || 0); y: 14
                        width: 1.5; height: 2; radius: 0.75
                        antialiasing: true
                        color: root.d.face || "transparent"
                    }
                }
            }
        }

        Text {
            visible: root.showTitle && root.title !== ""
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: root.width * 0.075
            text: root.title
            font.family: root.titleFont
            font.pixelSize: Math.max(8, root.width * 0.14)
            lineHeight: 0.95
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            color: "#ffffff"
            layer.enabled: visible
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.6)
                shadowBlur: 0.8
                shadowHorizontalOffset: 0
                shadowVerticalOffset: root.width * 0.01
            }
        }
    }

    RoundedClip {
        anchors.fill: parent
        target: content
        radius: root.radius
    }
}
