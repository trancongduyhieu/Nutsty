import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import "."
import "lyrics_offset_logic.js" as LyricsOffset

// Fine-tune panel for the song's lyrics offset (liner's offset popover): a typed value in ms or s,
// - / + steps, and quick jumps from -1 s to +1 s. Negative shows lyrics earlier, positive later.
Popup {
    id: root
    property int offsetMs: 0
    property color accentColor: "#ffffff"
    property string unit: "ms"
    signal offsetRequested(int ms)

    width: 272
    padding: 12
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    enter: Transition { ParallelAnimation {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.95; to: 1; duration: 120; easing.type: Easing.OutCubic } } }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 100 } }
    background: Rectangle {
        radius: 14
        color: Qt.rgba(0.04, 0.04, 0.05, 0.92)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.10)
    }

    function shown(ms) { return root.unit === "ms" ? String(ms) : String(ms / 1000); }
    function applyTyped(text) {
        var v = parseFloat(String(text).replace(",", "."));
        if (isNaN(v)) return;
        root.offsetRequested(LyricsOffset.clampMs(root.unit === "ms" ? v : v * 1000));
    }
    onOffsetMsChanged: if (!valueInput.activeFocus) valueInput.text = shown(offsetMs)
    onUnitChanged: valueInput.text = shown(offsetMs)
    onOpened: valueInput.text = shown(offsetMs)

    readonly property color tintSoft: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.10)
    readonly property color tintHover: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.22)

    component PanelButton: Rectangle {
        id: pb
        property string label: ""
        property string icon: ""
        property bool filled: true
        signal clicked()
        radius: 8
        color: pbH.hovered ? root.tintHover : (filled ? root.tintSoft : "transparent")
        Behavior on color { ColorAnimation { duration: 120 } }
        HoverHandler { id: pbH }
        scale: pbM.pressed ? 0.95 : 1.0
        Behavior on scale { NumberAnimation { duration: 90 } }
        Text {
            visible: pb.label !== ""
            anchors.centerIn: parent
            text: pb.label
            color: pbH.hovered ? "#ffffff" : Qt.rgba(1, 1, 1, 0.75)
            font.family: "monospace"
            font.pixelSize: 11
        }
        AppIcon {
            visible: pb.icon !== ""
            anchors.centerIn: parent
            source: pb.icon
            iconSize: 13
            color: "#ffffff"
            opacity: pbH.hovered ? 1.0 : 0.7
        }
        MouseArea { id: pbM; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: pb.clicked() }
    }

    contentItem: ColumnLayout {
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            AppIcon { source: "../assets/icons/material/ms-schedule.svg"; iconSize: 14; color: "#ffffff" }
            Text {
                Layout.fillWidth: true
                text: I18n.tr("Lệch thời gian lời", "Lyrics offset")
                color: "#ffffff"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            PanelButton {
                visible: root.offsetMs !== 0
                filled: false
                Layout.preferredHeight: 22
                Layout.preferredWidth: resetRow.implicitWidth + 12
                onClicked: root.offsetRequested(0)
                Row {
                    id: resetRow
                    anchors.centerIn: parent
                    spacing: 4
                    AppIcon { anchors.verticalCenter: parent.verticalCenter; source: "../assets/icons/material/ms-history.svg"; iconSize: 12; color: "#ffffff"; opacity: 0.8 }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Đặt lại", "Reset")
                        color: Qt.rgba(1, 1, 1, 0.8)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                }
            }
        }

        // - [value] + [ms|s]
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            radius: 10
            color: root.tintSoft
            RowLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 6
                PanelButton {
                    filled: false
                    icon: "../assets/icons/material/ms-remove.svg"
                    Layout.preferredWidth: 26; Layout.preferredHeight: 26
                    onClicked: root.offsetRequested(LyricsOffset.clampMs(root.offsetMs - (root.unit === "ms" ? 50 : 100)))
                }
                TextInput {
                    id: valueInput
                    Layout.fillWidth: true
                    horizontalAlignment: TextInput.AlignHCenter
                    color: "#ffffff"
                    selectionColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.5)
                    font.family: "monospace"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    selectByMouse: true
                    validator: RegularExpressionValidator { regularExpression: /^-?\d{0,5}([.,]\d{0,3})?$/ }
                    onTextEdited: root.applyTyped(text)
                    onEditingFinished: text = root.shown(root.offsetMs)
                    Keys.onUpPressed: root.offsetRequested(LyricsOffset.clampMs(root.offsetMs + (root.unit === "ms" ? 50 : 100)))
                    Keys.onDownPressed: root.offsetRequested(LyricsOffset.clampMs(root.offsetMs - (root.unit === "ms" ? 50 : 100)))
                    Keys.onReturnPressed: focus = false
                }
                PanelButton {
                    filled: false
                    icon: "../assets/icons/material/ms-add.svg"
                    Layout.preferredWidth: 26; Layout.preferredHeight: 26
                    onClicked: root.offsetRequested(LyricsOffset.clampMs(root.offsetMs + (root.unit === "ms" ? 50 : 100)))
                }
                Rectangle {
                    Layout.preferredWidth: unitRow.implicitWidth + 4
                    Layout.preferredHeight: 22
                    radius: 6
                    color: Qt.rgba(1, 1, 1, 0.08)
                    Row {
                        id: unitRow
                        anchors.centerIn: parent
                        spacing: 2
                        Repeater {
                            model: ["ms", "s"]
                            delegate: Rectangle {
                                required property string modelData
                                width: unitTxt.implicitWidth + 10; height: 18
                                radius: 4
                                color: root.unit === modelData ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35) : "transparent"
                                Text {
                                    id: unitTxt
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: root.unit === modelData ? "#ffffff" : Qt.rgba(1, 1, 1, 0.5)
                                    font.family: "monospace"
                                    font.pixelSize: 10
                                    font.weight: root.unit === modelData ? Font.DemiBold : Font.Normal
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.unit = modelData }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: I18n.tr("Sớm hơn (-)", "Earlier (-)")
                color: Qt.rgba(1, 1, 1, 0.5)
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Medium
            }
            Text {
                text: I18n.tr("Muộn hơn (+)", "Later (+)")
                color: Qt.rgba(1, 1, 1, 0.5)
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Medium
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 4
            rowSpacing: 4
            columnSpacing: 4
            Repeater {
                model: [-1000, -500, -200, -100, 100, 200, 500, 1000]
                delegate: PanelButton {
                    required property int modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    label: (modelData > 0 ? "+" : "") + (modelData / 1000) + "s"
                    onClicked: root.offsetRequested(LyricsOffset.clampMs(root.offsetMs + modelData))
                }
            }
        }
    }
}
