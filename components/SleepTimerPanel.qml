import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Shapes
import "."

// Sleep timer tab of the Now Playing right panel (Swiftify-like layout):
// hour / minute steppers (a draining countdown ring in their place while it runs),
// a three-way fade picker, the start / cancel pill and a line explaining the fade.
Item {
    id: root

    property color accentColor: Theme.accent
    property bool isActive: false
    property int remainingSeconds: 0
    property int totalSeconds: 0
    property string mode: ""      // "duration" | "end_of_track"
    property string fade: "final" // the host's current fade, used as the picker's start value

    signal startRequested(int seconds, string fade)
    signal endOfTrackRequested()
    signal cancelRequested()

    readonly property var fades: ["none", "final", "entire"]
    property int fadeIndex: Math.max(0, fades.indexOf(fade))
    property int hours: 0
    property int minutes: 30
    readonly property int pickedSeconds: hours * 3600 + minutes * 60

    readonly property color textSecondary: Qt.rgba(1, 1, 1, 0.62)
    // Accent-tinted glass for the controls' tracks (no dead greys)
    readonly property color trackFill: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.18)
    readonly property color trackBorder: Qt.rgba(1, 1, 1, 0.10)
    readonly property color rose: Qt.rgba(244 / 255, 63 / 255, 94 / 255, 1.0)

    function explanation(i) {
        if (i === 0) return I18n.tr("Nhạc dừng ngay khi hết giờ", "Music just stops when the timer runs out");
        if (i === 1) return I18n.tr("Nhạc nhỏ dần trong 10 giây cuối", "Music fades out over the last 10 seconds");
        return I18n.tr("Nhạc nhỏ dần suốt thời gian hẹn giờ, âm lượng bị khóa trong lúc này",
                       "Music fades out across the whole timer; volume is locked meanwhile");
    }

    function positional(total) {
        var t = Math.max(0, total);
        var h = Math.floor(t / 3600), m = Math.floor(t % 3600 / 60), s = t % 60;
        return (h > 0 ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (s < 10 ? "0" : "") + s;
    }

    // ---- pill stepper: [ - value unit + ]; clicks step by `step`, the wheel by 1 ----
    component Stepper: Rectangle {
        id: stepper
        property int value: 0
        property int maximum: 59
        property int step: 1
        property string unit: ""
        signal stepped(int value)

        function nudge(dir, amount) {
            var next = dir > 0 ? Math.floor(stepper.value / amount) * amount + amount
                               : Math.ceil(stepper.value / amount) * amount - amount;
            next = Math.max(0, Math.min(stepper.maximum, next));
            if (next !== stepper.value) stepper.stepped(next);
        }

        implicitWidth: stepRow.implicitWidth + 8
        implicitHeight: 48
        radius: height / 2
        color: root.trackFill
        border.width: 1
        border.color: root.trackBorder

        Row {
            id: stepRow
            anchors.centerIn: parent
            spacing: 2
            Repeater {
                model: [-1, 0, 1]
                delegate: Item {
                    id: cell
                    required property int modelData
                    width: modelData === 0 ? 76 : 40
                    height: 40
                    readonly property bool canStep: modelData < 0 ? stepper.value > 0 : stepper.value < stepper.maximum

                    Text {
                        visible: cell.modelData === 0
                        anchors.centerIn: parent
                        text: stepper.value + " " + stepper.unit
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 17
                        font.weight: Font.Medium
                        font.features: { "tnum": 1 }
                    }
                    Rectangle {
                        visible: cell.modelData !== 0
                        anchors.fill: parent
                        radius: height / 2 // concentric: 24 outer - 4 inset
                        color: Qt.rgba(1, 1, 1, cellMouse.pressed ? 0.16 : (cellHover.hovered && cell.canStep ? 0.10 : 0.0))
                        Behavior on color { ColorAnimation { duration: 140 } }
                        AppIcon {
                            anchors.centerIn: parent
                            source: cell.modelData < 0 ? "../assets/icons/material/ms-remove.svg" : "../assets/icons/material/ms-add.svg"
                            iconSize: 20
                            color: "#ffffff"
                            opacity: cell.canStep ? 1.0 : 0.32
                            scale: cellMouse.pressed ? 0.86 : 1.0
                            Behavior on scale { NumberAnimation { duration: 110 } }
                        }
                        HoverHandler { id: cellHover }
                        MouseArea {
                            id: cellMouse
                            anchors.fill: parent
                            enabled: cell.canStep
                            cursorShape: Qt.PointingHandCursor
                            pressAndHoldInterval: 380
                            onClicked: stepper.nudge(cell.modelData, stepper.step)
                            onPressAndHold: holdTimer.start()
                            onReleased: holdTimer.stop()
                            onCanceled: holdTimer.stop()
                            Timer {
                                id: holdTimer
                                interval: 110
                                repeat: true
                                onTriggered: stepper.nudge(cell.modelData, stepper.step)
                            }
                        }
                    }
                }
            }
        }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                if (event.angleDelta.y !== 0) stepper.nudge(event.angleDelta.y > 0 ? 1 : -1, 1);
            }
        }
    }

    Column {
        id: column
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -24
        width: Math.min(parent.width - 32, 420)
        spacing: 20

        // Pickers and countdown share one place and cross-fade; the place grows to hold the ring
        Item {
            width: parent.width
            height: root.isActive ? countdown.height : pickers.implicitHeight
            Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

            Row {
                id: pickers
                anchors.centerIn: parent
                spacing: 14
                opacity: root.isActive ? 0 : 1
                visible: opacity > 0.001
                Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.InOutQuad } }

                Stepper {
                    value: root.hours
                    maximum: 12
                    unit: I18n.tr("giờ", "h")
                    onStepped: v => root.hours = v
                }
                Stepper {
                    value: root.minutes
                    maximum: 59
                    step: 5
                    unit: I18n.tr("phút", "min")
                    onStepped: v => root.minutes = v
                }
            }

            Item {
                id: countdown
                anchors.centerIn: parent
                width: 228
                height: 228
                opacity: root.isActive ? 1 : 0
                visible: opacity > 0.001
                Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.InOutQuad } }

                property real progress: root.mode === "duration" && root.totalSeconds > 0
                                        ? Math.min(1, root.remainingSeconds / root.totalSeconds) : 1
                Behavior on progress { NumberAnimation { duration: 1000 } }

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Qt.rgba(1, 1, 1, 0.14)
                        strokeWidth: 5
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: countdown.width / 2; centerY: countdown.height / 2
                            radiusX: countdown.width / 2 - 4; radiusY: countdown.height / 2 - 4
                            startAngle: -90; sweepAngle: 360
                        }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Qt.lighter(root.accentColor, 1.35)
                        strokeWidth: 5
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: countdown.width / 2; centerY: countdown.height / 2
                            radiusX: countdown.width / 2 - 4; radiusY: countdown.height / 2 - 4
                            startAngle: -90; sweepAngle: 360 * countdown.progress
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.positional(root.remainingSeconds)
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 40
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: countdown.width - 48
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: root.mode === "end_of_track" ? I18n.tr("đến khi hết bài này", "until this song ends")
                                                           : I18n.tr("đến khi dừng phát", "until playback stops")
                        color: root.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }
                }
            }
        }

        // ---- fade picker: segmented track with a sliding light pill ----
        Rectangle {
            id: fadePicker
            width: parent.width
            height: 50
            radius: height / 2
            color: root.trackFill
            border.width: 1
            border.color: root.trackBorder
            enabled: !root.isActive
            opacity: enabled ? 1.0 : 0.38
            Behavior on opacity { NumberAnimation { duration: 200 } }
            readonly property real inset: 4
            readonly property real segW: (width - 2 * inset) / 3

            Rectangle {
                x: fadePicker.inset + root.fadeIndex * fadePicker.segW
                y: fadePicker.inset
                width: fadePicker.segW
                height: fadePicker.height - 2 * fadePicker.inset
                radius: height / 2 // concentric: 25 outer - 4 inset
                color: Qt.rgba(1, 1, 1, 0.92)
                Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            }

            Row {
                x: fadePicker.inset
                y: fadePicker.inset
                Repeater {
                    model: [I18n.tr("Không", "None"), I18n.tr("10 giây cuối", "Last 10 seconds"), I18n.tr("Suốt hẹn giờ", "Whole timer")]
                    delegate: Item {
                        id: seg
                        required property int index
                        required property string modelData
                        width: fadePicker.segW
                        height: fadePicker.height - 2 * fadePicker.inset
                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 16
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: seg.modelData
                            color: root.fadeIndex === seg.index ? "#141414" : Qt.rgba(1, 1, 1, segHover.hovered ? 0.95 : 0.80)
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.weight: root.fadeIndex === seg.index ? Font.DemiBold : Font.Medium
                            Behavior on color { ColorAnimation { duration: 180 } }
                        }
                        HoverHandler { id: segHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.fadeIndex = seg.index
                        }
                    }
                }
            }
        }

        Column {
            width: parent.width
            spacing: 10

            // Start (accent glass) / Cancel (Muted Rose)
            Rectangle {
                id: mainBtn
                anchors.horizontalCenter: parent.horizontalCenter
                readonly property bool canStart: root.isActive || root.pickedSeconds > 0
                width: mainRow.implicitWidth + 44
                height: 48
                radius: height / 2
                color: root.isActive
                       ? Qt.rgba(root.rose.r, root.rose.g, root.rose.b, mainHover.hovered ? 0.20 : 0.12)
                       : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, mainHover.hovered && canStart ? 0.42 : 0.30)
                border.width: 1
                border.color: root.isActive ? Qt.rgba(root.rose.r, root.rose.g, root.rose.b, 0.28) : Qt.rgba(1, 1, 1, 0.14)
                opacity: canStart ? 1.0 : 0.45
                scale: mainMouse.pressed ? 0.96 : (mainHover.hovered && canStart ? 1.03 : 1.0)
                Behavior on color { ColorAnimation { duration: 160 } }
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                Row {
                    id: mainRow
                    anchors.centerIn: parent
                    spacing: 10
                    AppIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        source: root.isActive ? "../assets/icons/material/ms-close.svg" : "../assets/icons/material/ms-bedtime.svg"
                        iconSize: 20
                        color: root.isActive ? "#fda4af" : "#ffffff"
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.isActive ? I18n.tr("Hủy hẹn giờ", "Cancel timer") : I18n.tr("Bắt đầu hẹn giờ", "Start timer")
                        color: root.isActive ? "#fda4af" : "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }
                }
                HoverHandler { id: mainHover }
                MouseArea {
                    id: mainMouse
                    anchors.fill: parent
                    enabled: mainBtn.canStart
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.isActive) root.cancelRequested();
                        else root.startRequested(root.pickedSeconds, root.fades[root.fadeIndex]);
                    }
                }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.isActive && root.mode === "end_of_track"
                      ? I18n.tr("Nhạc nhỏ dần trong 5 giây cuối bài", "Music fades out over the song's last 5 seconds")
                      : root.explanation(root.fadeIndex)
                color: root.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }

            // Secondary choice kept from the old popover: stop once the current song ends
            Item { width: 1; height: 2 }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !root.isActive
                width: eotRow.implicitWidth + 28
                height: 36
                radius: height / 2
                color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, eotHover.hovered ? 0.18 : 0.0)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, eotHover.hovered ? 0.14 : 0.08)
                Behavior on color { ColorAnimation { duration: 160 } }
                Row {
                    id: eotRow
                    anchors.centerIn: parent
                    spacing: 8
                    AppIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        source: "../assets/icons/material/ms-music_note.svg"
                        iconSize: 16
                        color: "#ffffff"
                        opacity: 0.85
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Dừng khi hết bài này", "Stop after this song")
                        color: Qt.rgba(1, 1, 1, 0.85)
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                }
                HoverHandler { id: eotHover }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.endOfTrackRequested()
                }
            }
        }
    }
}
