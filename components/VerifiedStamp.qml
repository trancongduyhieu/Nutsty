import QtQuick
import QtQuick.Shapes

// The "verified" stamp that lands on the back of the listener card once the barcode scans.
// A clean seal: a cream disc so it reads over the bars, two green rings with NUTSTY running
// between them, a check and the word in the middle. Everything is static items; the landing is
// only scale and opacity on the whole stamp, so nothing is repainted per frame.
Item {
    id: root

    property real progress: 0            // 0..1 from the owner; the stamp lands over 0.2..0.45
    property real unit: 1
    property color ink: "#0B8A4F"
    property real cx: width * 0.7
    property real cy: height * 0.56
    property real radius: height * 0.38
    property real tilt: -12
    property string word: I18n.tr("ĐÃ XÁC MINH", "VERIFIED")
    property string dateText: Qt.formatDate(new Date(), "dd.MM.yyyy")
    readonly property string ringText: "NUTSTY • NUTSTY • NUTSTY • "

    readonly property real land: Math.max(0, Math.min(1, (progress - 0.2) / 0.25))
    function easeOutBack(t) { var c1 = 1.6, c3 = c1 + 1; return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2); }

    visible: land > 0

    Item {
        id: seal
        x: root.cx - width / 2
        y: root.cy - height / 2
        width: root.radius * 2
        height: width
        rotation: root.tilt
        scale: 1.7 - 0.7 * root.easeOutBack(root.land)
        opacity: Math.min(1, root.land * 2.2)

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.rgba(0.99, 0.96, 0.89, 0.94)
            border.width: 3 * root.unit
            border.color: root.ink
        }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.68
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1.5 * root.unit
            border.color: root.ink
        }

        // NUTSTY around the ring, one letter per slot
        Repeater {
            model: root.ringText.length
            Text {
                readonly property real a: (index / root.ringText.length) * 360
                x: seal.width / 2 - width / 2
                y: seal.height / 2 - height / 2
                text: root.ringText.charAt(index)
                color: root.ink
                font.family: Theme.fontFamily
                font.pixelSize: root.radius * 0.17
                font.weight: Font.Black
                transform: [
                    Translate { y: -root.radius * 0.84 },
                    Rotation { origin.x: width / 2; origin.y: height / 2; angle: a }
                ]
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: root.radius * 0.03

            Shape {
                id: check
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.radius * 0.36
                height: root.radius * 0.26
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: root.ink
                    strokeWidth: 3.2 * root.unit
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    startX: check.width * 0.08; startY: check.height * 0.55
                    PathLine { x: check.width * 0.38; y: check.height * 0.88 }
                    PathLine { x: check.width * 0.94; y: check.height * 0.1 }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.word
                color: root.ink
                font.family: Theme.fontFamily
                font.weight: Font.Black
                font.pixelSize: root.radius * (root.word.length > 9 ? 0.17 : 0.22)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.dateText
                color: root.ink
                opacity: 0.85
                font.family: "monospace"
                font.weight: Font.Bold
                font.pixelSize: root.radius * 0.11
            }
        }
    }
}
