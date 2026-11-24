pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import "."

// Live slider panel for tuning numbers on a target item while watching it (the Up Next lean, the
// big type cover). Each row names one property of `target`. Nothing here is saved: the chosen
// numbers, read off the bottom line, become the panel's defaults in code.
Rectangle {
    id: tuner

    property Item target: null
    property color accentColor: Theme.accent
    property string title: ""
    // [{ label, prop, from, to, step, digits }]
    property var rows: []
    // { prop: value } restored by the reset button
    property var defaults: ({})

    width: 320
    implicitHeight: body.implicitHeight + 32
    height: implicitHeight
    radius: 16
    color: Qt.rgba(0.05, 0.06, 0.09, 0.92)
    border.width: 1
    border.color: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.45)

    // Swallow clicks so they do not fall through to the page underneath
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: wheel => wheel.accepted = true }


    function fmt(v, digits) { return Number(v).toFixed(digits); }
    function summary() {
        if (!target) return "";
        var parts = [];
        for (var i = 0; i < rows.length; ++i)
            parts.push(rows[i].prop + " " + fmt(target[rows[i].prop], rows[i].digits === undefined ? 1 : rows[i].digits));
        return parts.join(" · ");
    }

    component TuneRow: ColumnLayout {
        id: row
        required property string label
        required property string prop
        required property real from
        required property real to
        property real step: 0.5
        property int digits: 1
        Layout.fillWidth: true
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: row.label
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Qt.rgba(1, 1, 1, 0.86)
                elide: Text.ElideRight
            }
            Text {
                text: tuner.target ? tuner.fmt(tuner.target[row.prop], row.digits) : ""
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
                color: tuner.accentColor
            }
        }

        Slider {
            id: slider
            Layout.fillWidth: true
            from: row.from
            to: row.to
            stepSize: row.step
            value: tuner.target ? tuner.target[row.prop] : 0
            onMoved: if (tuner.target) tuner.target[row.prop] = value

            background: Rectangle {
                x: slider.leftPadding
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: slider.availableWidth
                height: 4
                radius: 2
                color: Qt.rgba(tuner.accentColor.r, tuner.accentColor.g, tuner.accentColor.b, 0.22)
                Rectangle {
                    width: slider.visualPosition * parent.width
                    height: parent.height
                    radius: 2
                    color: tuner.accentColor
                }
            }
            handle: Rectangle {
                x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: 16
                height: 16
                radius: 8
                color: "#ffffff"
                border.width: 2
                border.color: tuner.accentColor
            }
        }
    }

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: tuner.title
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
                color: "#ffffff"
                elide: Text.ElideRight
            }
            Rectangle {
                Layout.preferredWidth: resetLabel.implicitWidth + 20
                Layout.preferredHeight: 26
                radius: 8
                color: Qt.rgba(tuner.accentColor.r, tuner.accentColor.g, tuner.accentColor.b, resetH.hovered ? 0.45 : 0.22)
                border.width: 1
                border.color: Qt.rgba(tuner.accentColor.r, tuner.accentColor.g, tuner.accentColor.b, 0.45)
                Text {
                    id: resetLabel
                    anchors.centerIn: parent
                    text: I18n.tr("Đặt lại", "Reset")
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: "#ffffff"
                }
                HoverHandler { id: resetH }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!tuner.target) return;
                        for (var k in tuner.defaults) tuner.target[k] = tuner.defaults[k];
                    }
                }
            }
        }

        Repeater {
            model: tuner.rows
            delegate: TuneRow {
                required property var modelData
                label: modelData.label
                prop: modelData.prop
                from: modelData.from
                to: modelData.to
                step: modelData.step === undefined ? 0.5 : modelData.step
                digits: modelData.digits === undefined ? 1 : modelData.digits
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 4
            text: I18n.tr("Gửi dòng này cho Claude:", "Send this line to Claude:")
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Qt.rgba(1, 1, 1, 0.70)
        }
        TextEdit {
            Layout.fillWidth: true
            text: tuner.summary()
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: "#ffffff"
            selectionColor: Qt.rgba(tuner.accentColor.r, tuner.accentColor.g, tuner.accentColor.b, 0.6)
        }
    }
}
