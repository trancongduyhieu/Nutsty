import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import "."

Item {
    id: root
    anchors.fill: parent
    z: 10007
    visible: opacity > 0.001
    opacity: isOpen ? 1.0 : 0.0
    enabled: isOpen

    Behavior on opacity {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }

    property bool isOpen: false
    property var noteData: null
    property string userAvatar: ""
    property string userName: ""
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent
    property bool isTrackPlaying: false
    property Item backgroundSourceItem: null

    signal closeRequested()
    signal changeNoteRequested()
    signal deleteNoteRequested()
    signal playTrackRequested(var track)

    function openModal(data) {
        root.noteData = data;
        root.isOpen = true;
    }

    function closeModal() {
        root.isOpen = false;
        root.closeRequested();
    }

    function formatExpiryText(isoStr) {
        if (!isoStr) return I18n.tr("Hết hạn sau 24 giờ", "Expires in 24 hours");
        try {
            var d = new Date(isoStr);
            var diffMs = d.getTime() - Date.now();
            if (diffMs <= 0) return I18n.tr("Đã hết hạn", "Expired");
            var diffHours = Math.floor(diffMs / (1000 * 60 * 60));
            var diffMins = Math.floor((diffMs % (1000 * 60 * 60)) / (1000 * 60));
            if (diffHours > 0) {
                return I18n.tr("Hết hạn sau " + diffHours + " giờ", "Expires in " + diffHours + " hours");
            } else {
                return I18n.tr("Hết hạn sau " + Math.max(1, diffMins) + " phút", "Expires in " + Math.max(1, diffMins) + " minutes");
            }
        } catch(e) {
            return I18n.tr("Hết hạn sau 24 giờ", "Expires in 24 hours");
        }
    }

    function formatTimeAgo(isoStr) {
        if (!isoStr) return I18n.tr("Vừa xong", "Just now");
        try {
            var d = new Date(isoStr);
            var diffSec = Math.floor((Date.now() - d.getTime()) / 1000);
            if (diffSec < 60) return I18n.tr("Vừa xong", "Just now");
            var diffMin = Math.floor(diffSec / 60);
            if (diffMin < 60) return diffMin + I18n.tr(" phút trước", "m ago");
            var diffHours = Math.floor(diffMin / 60);
            if (diffHours < 24) return diffHours + I18n.tr(" giờ trước", "h ago");
            return Math.floor(diffHours / 24) + I18n.tr(" ngày trước", "d ago");
        } catch(e) {
            return I18n.tr("Vừa xong", "Just now");
        }
    }

    readonly property string displayNoteText: root.noteData ? String(root.noteData.note_text || "").trim() : ""
    readonly property var attachedTrack: (root.noteData && root.noteData.track) ? root.noteData.track : null
    readonly property string trackTitle: attachedTrack ? String(attachedTrack.title || attachedTrack.name || "").trim() : ""
    readonly property string trackArtist: attachedTrack ? String(attachedTrack.artist || "").trim() : ""
    readonly property string attachedCover: attachedTrack ? String(attachedTrack.cover || attachedTrack.image || "").trim() : ""

    readonly property bool isThisTrackPlaying: {
        if (!attachedTrack || typeof win === "undefined" || !win.isPlaying || !win.currentTrack) return false;
        var curId = win.currentTrack.videoId || win.currentTrack.id || "";
        var attId = attachedTrack.videoId || attachedTrack.id || "";
        if (curId && attId && curId === attId) return true;
        var curTitle = win.currentTrack.title || win.currentTrack.name || "";
        var attTitle = attachedTrack.title || attachedTrack.name || "";
        return curTitle && attTitle && curTitle === attTitle;
    }

    // Backdrop Dismiss Area
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.58)

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeModal()
        }
    }

    // Elevation: MultiEffect Drop Shadow behind Dialog
    Rectangle {
        id: shadowShape
        anchors.fill: dialogCard
        radius: dialogCard.radius
        color: "#000000"
        visible: false
    }

    MultiEffect {
        anchors.fill: shadowShape
        source: shadowShape
        shadowEnabled: true
        shadowColor: "#80000000"
        shadowVerticalOffset: 6
        shadowBlur: 0.65
        z: 1
    }

    // Modal Main Floating Card: Keo 502 Optical Resin (LiquidGlass, 20px Radius)
    LiquidGlass {
        id: dialogCard
        width: 420
        height: 480
        anchors.centerIn: parent
        radius: 20
        displacement: 22.0
        aberration: 0.03
        bevelWidth: 26.0
        tintColor: Qt.rgba(0.04, 0.05, 0.08, 0.92)
        backgroundSourceItem: root.backgroundSourceItem
        isFlowActive: (typeof win !== "undefined" && win.isPlaying && win.currentTrack !== null)
        clip: true
        z: 2

        scale: root.isOpen ? 1.0 : 0.94
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        // Shaded Tint Overlay: Ensures effortless text contrast
        Rectangle {
            anchors.fill: parent
            radius: dialogCard.radius
            color: Qt.rgba(0.04, 0.05, 0.08, 0.82)
            z: 1
        }

        // 1px Hairline Border: Keo 502 Surface Tension Rim
        Rectangle {
            anchors.fill: parent
            radius: dialogCard.radius
            color: "transparent"
            border.color: Qt.rgba(255, 255, 255, 0.18)
            border.width: 1
            z: 20
        }

        // Prevent click-through
        MouseArea {
            anchors.fill: parent
            z: 2
            onClicked: (mouse) => { mouse.accepted = true; }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 0
            z: 5

            // ==========================================
            // HEADER: Mini Avatar + Name (Left) & Close Button (Far Right)
            // ==========================================
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32

                // Mini circular avatar + User info
                RowLayout {
                    spacing: 10
                    Layout.alignment: Qt.AlignVCenter

                    RoundedImage {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: 16
                        source: root.userAvatar
                        initialsText: root.userName
                        fallbackIcon: "../assets/icons/contact-new-symbolic.svg"
                        fallbackIconColor: root.accentColor
                    }

                    ColumnLayout {
                        spacing: 1
                        Text {
                            text: root.userName || I18n.tr("Bạn", "You")
                            color: Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text {
                            text: root.formatTimeAgo(root.noteData ? root.noteData.created_at : "")
                            color: Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }
                }

                Item { Layout.fillWidth: true } // Far right push!

                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: closeHover.hovered ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.05)
                    border.color: closeHover.hovered ? Qt.rgba(255, 255, 255, 0.16) : Qt.rgba(255, 255, 255, 0.08)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }

                    HoverHandler { id: closeHover }

                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/window-close-symbolic.svg"
                        iconSize: 12
                        color: closeHover.hovered ? "#ffffff" : Theme.textSecondary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeModal()
                    }
                }
            }

            // ==========================================
            // CENTER: Thought Bubble + Soft Droplet Tail + Clean Avatar + Play Control
            // ==========================================
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: 0

                    // 1. THOUGHT BUBBLE CONTAINER
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: Math.max(160, Math.min(320, bubbleContentCol.implicitWidth + 36))
                        Layout.preferredHeight: bubbleBg.height + 10

                        // Seamless Droplet Tail (Rotated rounded square)
                        Rectangle {
                            id: bubbleTail
                            anchors.top: bubbleBg.bottom
                            anchors.topMargin: -6
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 14
                            height: 14
                            radius: 3
                            rotation: 45
                            color: bubbleBg.color
                            border.color: bubbleBg.border.color
                            border.width: 1
                            z: 1
                        }

                        // The Rounded Thought Bubble Card (Dynamic Chromatic Salience - No dead grey)
                        Rectangle {
                            id: bubbleBg
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width
                            height: bubbleContentCol.implicitHeight + 22
                            radius: 20
                            color: {
                                var isPlaying = root.isThisTrackPlaying;
                                if (isPlaying) {
                                    return bubbleMouse.containsMouse
                                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                                        : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22);
                                } else {
                                    return bubbleMouse.containsMouse
                                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                                        : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10);
                                }
                            }
                            border.color: {
                                var isPlaying = root.isThisTrackPlaying;
                                if (isPlaying) {
                                    return bubbleMouse.containsMouse
                                        ? root.accentColor
                                        : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.55);
                                } else {
                                    return bubbleMouse.containsMouse
                                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                                        : Qt.rgba(255, 255, 255, 0.12);
                                }
                            }
                            border.width: 1
                            z: 2

                            scale: bubbleMouse.containsMouse ? 1.02 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150 } }
                            Behavior on color { ColorAnimation { duration: 250 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            ColumnLayout {
                                id: bubbleContentCol
                                anchors.centerIn: parent
                                width: parent.width - 24
                                spacing: 5

                                // Note Text
                                Text {
                                    id: bubbleNoteText
                                    Layout.fillWidth: true
                                    visible: root.displayNoteText.length > 0
                                    text: root.displayNoteText
                                    color: "#ffffff"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                    font.bold: true
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 3
                                    lineHeight: 1.15
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                // Attached Music Section (Waveform + Song + Artist)
                                ColumnLayout {
                                    id: bubbleMusicSection
                                    Layout.fillWidth: true
                                    spacing: 2
                                    visible: root.attachedTrack !== null

                                    RowLayout {
                                        Layout.alignment: Qt.AlignHCenter
                                        spacing: 6

                                        // Audio Waveform Visualizer (3 Animated Bars)
                                        Row {
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: 2
                                            height: 12

                                            Rectangle {
                                                width: 2.2; height: 6; radius: 1.1
                                                color: root.accentColor
                                                anchors.bottom: parent.bottom
                                                SequentialAnimation on height {
                                                    running: root.attachedTrack !== null
                                                    loops: Animation.Infinite
                                                    NumberAnimation { to: 12; duration: 340; easing.type: Easing.InOutQuad }
                                                    NumberAnimation { to: 4; duration: 340; easing.type: Easing.InOutQuad }
                                                }
                                            }
                                            Rectangle {
                                                width: 2.2; height: 12; radius: 1.1
                                                color: root.accentColor
                                                anchors.bottom: parent.bottom
                                                SequentialAnimation on height {
                                                    running: root.attachedTrack !== null
                                                    loops: Animation.Infinite
                                                    NumberAnimation { to: 5; duration: 260; easing.type: Easing.InOutQuad }
                                                    NumberAnimation { to: 12; duration: 260; easing.type: Easing.InOutQuad }
                                                }
                                            }
                                            Rectangle {
                                                width: 2.2; height: 8; radius: 1.1
                                                color: root.accentColor
                                                anchors.bottom: parent.bottom
                                                SequentialAnimation on height {
                                                    running: root.attachedTrack !== null
                                                    loops: Animation.Infinite
                                                    NumberAnimation { to: 11; duration: 400; easing.type: Easing.InOutQuad }
                                                    NumberAnimation { to: 3; duration: 400; easing.type: Easing.InOutQuad }
                                                }
                                            }
                                        }

                                        // Song Title (Marquee when long)
                                        Item {
                                            id: userNoteTrackTitleBox
                                            Layout.maximumWidth: bubbleContentCol.width - 24
                                            Layout.preferredWidth: Math.min(bubbleContentCol.width - 24, userNoteTrackTitleText.implicitWidth)
                                            implicitHeight: userNoteTrackTitleText.implicitHeight
                                            clip: true

                                            Text {
                                                id: userNoteTrackTitleText
                                                text: root.trackTitle
                                                color: "#ffffff"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 13
                                                font.bold: true
                                                x: 0

                                                readonly property real overflowDist: Math.max(0, implicitWidth - userNoteTrackTitleBox.width)
                                                readonly property bool needsScroll: overflowDist > 6

                                                onTextChanged: {
                                                    userNoteTrackTitleText.x = 0;
                                                }

                                                SequentialAnimation {
                                                    running: userNoteTrackTitleText.needsScroll
                                                    loops: Animation.Infinite

                                                    PauseAnimation { duration: 1800 }
                                                    NumberAnimation {
                                                        target: userNoteTrackTitleText
                                                        property: "x"
                                                        to: -userNoteTrackTitleText.overflowDist
                                                        duration: Math.max(1200, userNoteTrackTitleText.overflowDist * 28)
                                                        easing.type: Easing.InOutQuad
                                                    }
                                                    PauseAnimation { duration: 1800 }
                                                    NumberAnimation {
                                                        target: userNoteTrackTitleText
                                                        property: "x"
                                                        to: 0
                                                        duration: Math.max(1200, userNoteTrackTitleText.overflowDist * 28)
                                                        easing.type: Easing.InOutQuad
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Artist Name
                                    Text {
                                        Layout.fillWidth: true
                                        text: root.trackArtist
                                        color: Qt.rgba(1, 1, 1, 0.65)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }
                            }

                            // Interactive Area to play attached song immediately
                            MouseArea {
                                id: bubbleMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: root.attachedTrack ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (root.attachedTrack) {
                                        root.playTrackRequested(root.attachedTrack);
                                    }
                                }
                            }
                        }
                    }

                    // 2. CLEAN CIRCULAR USER AVATAR (80x80, Single Ring, Zero Concentric Gaps)
                    RoundedImage {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 80
                        Layout.preferredHeight: 80
                        Layout.topMargin: 6
                        radius: 40
                        source: root.userAvatar
                        initialsText: root.userName
                        borderColor: Qt.rgba(255, 255, 255, 0.15)
                        borderWidth: 1
                        fallbackIcon: "../assets/icons/contact-new-symbolic.svg"
                        fallbackIconColor: root.accentColor
                        fallbackIconSize: 32
                    }

                    // 3. CIRCULAR MINI PLAY/STOP BUTTON (Direct under avatar - Messenger Style)
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        Layout.topMargin: 8
                        visible: root.attachedTrack !== null

                        // Spinning Progress Ring when playing
                        Rectangle {
                            anchors.fill: parent
                            radius: 18
                            color: "transparent"
                            border.color: root.isThisTrackPlaying ? root.accentColor : "transparent"
                            border.width: 1.5
                            visible: root.isThisTrackPlaying

                            RotationAnimation on rotation {
                                running: root.isThisTrackPlaying
                                loops: Animation.Infinite
                                from: 0; to: 360; duration: 2500
                            }
                        }

                        Rectangle {
                            id: playStopCircle
                            anchors.centerIn: parent
                            width: 32; height: 32; radius: 16
                            color: {
                                var isPlaying = root.isThisTrackPlaying;
                                if (isPlaying) {
                                    return playStopMouse.containsMouse
                                        ? Qt.lighter(root.accentColor, 1.15)
                                        : root.accentColor;
                                } else {
                                    return playStopMouse.containsMouse
                                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.40)
                                        : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22);
                                }
                            }
                            border.color: root.isThisTrackPlaying
                                ? Qt.rgba(255, 255, 255, 0.4)
                                : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                            border.width: 1

                            scale: playStopMouse.containsMouse ? 1.08 : 1.0
                            Behavior on scale { NumberAnimation { duration: 120 } }
                            Behavior on color { ColorAnimation { duration: 150 } }

                            AppIcon {
                                anchors.centerIn: parent
                                source: root.isThisTrackPlaying ? "../assets/icons/media-playback-pause-symbolic.svg" : "../assets/icons/media-playback-start-symbolic.svg"
                                iconSize: 12
                                color: root.isThisTrackPlaying ? "#000000" : "#ffffff"
                            }

                            MouseArea {
                                id: playStopMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.attachedTrack) {
                                        if (root.isThisTrackPlaying && typeof win !== "undefined") {
                                            win.togglePlay();
                                        } else {
                                            root.playTrackRequested(root.attachedTrack);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 4. USER NAME
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 8
                        text: root.userName || I18n.tr("Bạn", "You")
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 17
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    // 5. SHARING & EXPIRATION SUBTEXT
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 4
                        text: I18n.tr("Đã chia sẻ với bạn bè", "Shared with friends")
                        color: Qt.rgba(1, 1, 1, 0.60)
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 2
                        text: root.formatExpiryText(root.noteData ? (root.noteData.expires_at || "") : "")
                        color: Qt.rgba(1, 1, 1, 0.40)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }
            }

            // ==========================================
            // FOOTER: Exactly 1 Button (Thay ghi chú - Flat Surface Action)
            // ==========================================
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                Layout.bottomMargin: 4

                Item { Layout.fillWidth: true }

                Rectangle {
                    id: changeBtn
                    Layout.preferredHeight: 36
                    Layout.preferredWidth: changeRow.implicitWidth + 24
                    radius: 8
                    color: changeMouse.containsMouse
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                        : "transparent"
                    border.color: changeMouse.containsMouse
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                        : "transparent"
                    border.width: 1

                    scale: changeMouse.containsMouse ? 1.03 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        id: changeRow
                        anchors.centerIn: parent
                        spacing: 8

                        AppIcon {
                            source: "../assets/icons/list-add-symbolic.svg"
                            iconSize: 15
                            color: root.accentColor
                        }

                        Text {
                            text: I18n.tr("Thay ghi chú", "Change note")
                            color: root.accentColor
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                        }
                    }

                    MouseArea {
                        id: changeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.closeModal();
                            root.changeNoteRequested();
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }
    }
}
