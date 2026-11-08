import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import Quickshell
import "."

Item {
    id: root
    anchors.fill: parent
    z: 9999
    visible: opacity > 0.001
    opacity: isOpen ? 1.0 : 0.0
    enabled: isOpen

    Behavior on opacity {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    property bool isOpen: false
    property Item backgroundSourceItem: null
    property Item targetAnchorItem: null
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent
    property bool isTimerActive: false
    property int remainingSeconds: 0
    property string timerMode: "" // "duration" or "end_of_track"
    property bool isCustomMode: false
    property int customMinutes: 20

    signal setTimerRequested(int minutes)
    signal setEndOfTrackRequested()
    signal cancelTimerRequested()

    function open() {
        isCustomMode = false;
        isOpen = true;
    }

    function close() {
        isCustomMode = false;
        isOpen = false;
    }

    function startCustomTimer() {
        var m = root.customMinutes;
        if (m < 1) m = 1;
        if (m > 720) m = 720;
        root.setTimerRequested(m);
        root.close();
    }

    function formatTime(totalSec) {
        if (totalSec <= 0) return "00:00";
        var m = Math.floor(totalSec / 60);
        var s = totalSec % 60;
        var mm = m < 10 ? "0" + m : String(m);
        var ss = s < 10 ? "0" + s : String(s);
        return mm + ":" + ss;
    }

    // Dismiss Backdrop with soft focus dimming
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true
        onClicked: root.close()

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0.0, 0.0, 0.0, 0.35)
        }
    }

    // Popover Card - Positioned directly above PlayerBar dock at moon button
    Item {
        id: cardWrapper
        width: 290
        height: cardContent.implicitHeight + 24

        // Exact anchor on top of centered bottomPlayer dock
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 92 // 16px player margin + 66px dock height + 10px gap
        anchors.right: parent.right
        anchors.rightMargin: Math.round((parent.width - Math.min(600, parent.width - 48)) / 2 + 10)

        scale: root.isOpen ? 1.0 : 0.85
        transformOrigin: Item.BottomRight
        Behavior on scale {
            NumberAnimation { duration: 220; easing.type: Easing.OutBack }
        }

        // Prevent clicking through to dismiss backdrop
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: true
        }

        // Deep Obsidian Frosted Foundation: Blocks text bleed-through from Up Next queue
        Rectangle {
            anchors.fill: parent
            radius: 18
            color: Qt.rgba(0.05, 0.06, 0.09, 0.90)
            z: 1
        }

        // Keo 502 Optical LiquidGlass Resin Container (Liquid Glass Spec)
        LiquidGlass {
            id: popoverGlass
            anchors.fill: parent
            radius: 18
            displacement: 16.0
            aberration: 0.03
            bevelWidth: 20.0
            tintColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
            backgroundSourceItem: root.backgroundSourceItem
            z: 2

            // 1px Concentric Hairline Accent Border
            Rectangle {
                anchors.fill: parent
                radius: 18
                color: "transparent"
                border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                border.width: 1
                z: 20
                Behavior on border.color { ColorAnimation { duration: 250 } }
            }

            // Subtle Frosted Scrim Underlay: Enhances contrast and text legibility
            Rectangle {
                anchors.fill: parent
                radius: 18
                color: Qt.rgba(0.04, 0.05, 0.08, 0.38)
                z: 1
            }

            ColumnLayout {
                id: cardContent
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10
                z: 10

                // 1. Header: Crescent Moon Icon + Title + Close Button
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    AppIcon {
                        source: "../assets/icons/sleep-timer-symbolic.svg"
                        iconSize: 16
                        color: root.accentColor
                    }

                    Text {
                        text: I18n.tr("Hẹn giờ ngủ", "Sleep Timer")
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        color: "#ffffff"
                        Layout.fillWidth: true
                    }

                    // Close Button
                    Rectangle {
                        width: 22; height: 22
                        radius: 11
                        color: closeMouse.containsMouse
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.30)
                            : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        AppIcon {
                            anchors.centerIn: parent
                            source: "../assets/icons/window-close-symbolic.svg"
                            iconSize: 10
                            color: closeMouse.containsMouse ? "#ffffff" : Qt.rgba(1.0, 1.0, 1.0, 0.65)
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.close()
                        }
                    }
                }

                // 2. Clean Active Status Row (Zero Capsule, Zero Blinking Dot)
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.isTimerActive
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: I18n.tr("Còn lại:", "Remaining:")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Qt.rgba(1.0, 1.0, 1.0, 0.75)
                        }

                        Text {
                            text: root.timerMode === "end_of_track"
                                ? (I18n.tr("Hết bài này", "End of track") + (root.remainingSeconds > 0 ? (" (" + root.formatTime(root.remainingSeconds) + ")") : ""))
                                : root.formatTime(root.remainingSeconds)
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            color: root.accentColor
                        }
                    }

                    // Cancel Button (Muted Rose)
                    Rectangle {
                        height: 24
                        implicitWidth: cancelText.implicitWidth + 16
                        radius: 7
                        color: cancelMouse.containsMouse
                            ? Qt.rgba(244, 63, 94, 0.32)
                            : Qt.rgba(244, 63, 94, 0.16)
                        border.color: cancelMouse.containsMouse
                            ? Qt.rgba(244, 63, 94, 0.70)
                            : Qt.rgba(244, 63, 94, 0.40)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            id: cancelText
                            anchors.centerIn: parent
                            text: I18n.tr("Hủy", "Cancel")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: "#fb7185"
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cancelTimerRequested()
                        }
                    }
                }

                // 3. Preset Duration Buttons (100% Dynamic Chromatic Salience - Zero Grey Buttons)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    // Row 1: 15 min & 30 min
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        component ChromaticPresetButton: Rectangle {
                            id: btnRoot
                            property int minutes: 15
                            property string labelText: ""
                            Layout.fillWidth: true
                            height: 34
                            radius: 10
                            color: btnMouse.containsMouse
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                                : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                            border.color: btnMouse.containsMouse
                                ? root.accentColor
                                : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.38)
                            border.width: 1
                            scale: btnMouse.containsMouse ? 1.02 : 1.0
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 100 } }

                            Text {
                                anchors.centerIn: parent
                                text: btnRoot.labelText
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: "#ffffff"
                            }

                            MouseArea {
                                id: btnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.setTimerRequested(btnRoot.minutes);
                                    root.close();
                                }
                            }
                        }

                        ChromaticPresetButton {
                            minutes: 15
                            labelText: "15 " + I18n.tr("phút", "min")
                        }

                        ChromaticPresetButton {
                            minutes: 30
                            labelText: "30 " + I18n.tr("phút", "min")
                        }
                    }

                    // Row 2: 45 min & 60 min
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        ChromaticPresetButton {
                            minutes: 45
                            labelText: "45 " + I18n.tr("phút", "min")
                        }

                        ChromaticPresetButton {
                            minutes: 60
                            labelText: "60 " + I18n.tr("phút", "min")
                        }
                    }

                    // Row 3: End of Current Track (shrunk) + Custom Duration Button
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        // 3A. Shrunk End of Track Button
                        Rectangle {
                            id: endTrackBtn
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            height: 34
                            radius: 10
                            color: endTrackMouse.containsMouse
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                                : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                            border.color: endTrackMouse.containsMouse
                                ? root.accentColor
                                : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.38)
                            border.width: 1
                            scale: endTrackMouse.containsMouse ? 1.02 : 1.0
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 100 } }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 5

                                AppIcon {
                                    source: "../assets/icons/media-playlist-consecutive-symbolic.svg"
                                    iconSize: 12
                                    color: root.accentColor
                                }

                                Text {
                                    text: I18n.tr("Hết bài", "End track")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    color: "#ffffff"
                                }
                            }

                            MouseArea {
                                id: endTrackMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.setEndOfTrackRequested();
                                    root.close();
                                }
                            }
                        }

                        // 3B. Custom Duration Button
                        Rectangle {
                            id: customBtn
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            height: 34
                            radius: 10
                            color: (customMouse.containsMouse || root.isCustomMode)
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                                : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                            border.color: (customMouse.containsMouse || root.isCustomMode)
                                ? root.accentColor
                                : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.38)
                            border.width: 1
                            scale: customMouse.containsMouse ? 1.02 : 1.0
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 100 } }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 5

                                AppIcon {
                                    source: "../assets/icons/preferences-system-symbolic.svg"
                                    iconSize: 12
                                    color: root.accentColor
                                }

                                Text {
                                    text: I18n.tr("Tùy chỉnh", "Custom")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    color: "#ffffff"
                                }
                            }

                            MouseArea {
                                id: customMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.isCustomMode = !root.isCustomMode;
                                    if (root.isCustomMode) {
                                        Qt.callLater(function() {
                                            if (customInput) customInput.forceActiveFocus();
                                        });
                                    }
                                }
                            }
                        }
                    }

                    // 4. Expandable Custom Duration Controls
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: root.isCustomMode

                        // Hairline accent separator
                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25)
                        }

                        // Stepper row [-] [ 20 phút ] [+]
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            // Decrement [-]
                            Rectangle {
                                width: 34; height: 34
                                radius: 10
                                color: minusMouse.containsMouse
                                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                                    : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                                border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.38)
                                border.width: 1
                                scale: minusMouse.containsMouse ? 1.04 : 1.0
                                Behavior on scale { NumberAnimation { duration: 80 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "−"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    id: minusMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var val = parseInt(customInput.text) || root.customMinutes;
                                        root.customMinutes = Math.max(1, val - 5);
                                        customInput.text = String(root.customMinutes);
                                    }
                                }
                            }

                            // Glass Input Container (Zero dark box, 100% Dynamic Chromatic Accent)
                            Rectangle {
                                Layout.fillWidth: true
                                height: 34
                                radius: 10
                                color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                                border.color: customInput.activeFocus
                                    ? root.accentColor
                                    : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.38)
                                border.width: customInput.activeFocus ? 1.5 : 1
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 4

                                    TextInput {
                                        id: customInput
                                        text: String(root.customMinutes)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        color: "#ffffff"
                                        horizontalAlignment: TextInput.AlignRight
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        validator: IntValidator { bottom: 1; top: 720 }
                                        selectByMouse: true
                                        onTextChanged: {
                                            var v = parseInt(text);
                                            if (!isNaN(v) && v >= 1 && v <= 720) {
                                                root.customMinutes = v;
                                            }
                                        }
                                        onAccepted: {
                                            root.startCustomTimer();
                                        }
                                    }

                                    Text {
                                        text: I18n.tr("phút", "min")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: Qt.rgba(1.0, 1.0, 1.0, 0.70)
                                    }
                                }
                            }

                            // Increment [+]
                            Rectangle {
                                width: 34; height: 34
                                radius: 10
                                color: plusMouse.containsMouse
                                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                                    : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                                border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.38)
                                border.width: 1
                                scale: plusMouse.containsMouse ? 1.04 : 1.0
                                Behavior on scale { NumberAnimation { duration: 80 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "+"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    id: plusMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var val = parseInt(customInput.text) || root.customMinutes;
                                        root.customMinutes = Math.min(720, val + 5);
                                        customInput.text = String(root.customMinutes);
                                    }
                                }
                            }
                        }

                        // Confirm Button
                        Rectangle {
                            Layout.fillWidth: true
                            height: 34
                            radius: 10
                            color: startCustomMouse.containsMouse
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                                : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.28)
                            border.color: root.accentColor
                            border.width: 1.5
                            scale: startCustomMouse.containsMouse ? 1.02 : 1.0
                            Behavior on scale { NumberAnimation { duration: 80 } }

                            Text {
                                anchors.centerIn: parent
                                text: I18n.tr("Đặt hẹn giờ", "Set Timer") + " (" + root.customMinutes + " " + I18n.tr("phút", "min") + ")"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: "#ffffff"
                            }

                            MouseArea {
                                id: startCustomMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.startCustomTimer()
                            }
                        }
                    }
                }
            }
        }
    }
}
