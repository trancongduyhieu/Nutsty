import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

PanelWindow {
    id: root

    property real currentTime: 0.0
    property real duration: 0.0
    property bool isPlaying: false
    property var currentTrack: null
    property var nextTrack: null
    property real widgetX: 80
    property real widgetY: 720

    signal playPauseClicked()
    signal nextClicked()
    signal prevClicked()
    signal seekRequested(real position)
    signal openFullAppRequested()
    signal savePositionRequested(real newX, real newY)
    // The X in the top-right corner: hide just this widget (music plays on) or quit Nutsty
    signal hideWidgetRequested()
    signal quitRequested()

    property bool closeChoiceOpen: false
    onVisibleChanged: if (!visible) closeChoiceOpen = false

    readonly property bool isWindows: Qt.platform.os === "windows"

    implicitWidth: isWindows ? 216 : ((screen && screen.geometry) ? screen.geometry.width : Screen.width)
    implicitHeight: isWindows ? 216 : ((screen && screen.geometry) ? screen.geometry.height : Screen.height)
    width: isWindows ? 216 : implicitWidth
    height: isWindows ? 216 : implicitHeight

    screen: Quickshell.screens[0]
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "nutsty:desktop_music_widget"
    color: "transparent"

    anchors {
        top: !isWindows
        bottom: !isWindows
        left: !isWindows
        right: !isWindows
    }

    // Dynamic input mask: Only un-mask during active drag movement so single/double clicks are never cancelled by Win32 SetWindowRgn
    mask: isWindows ? null : (dragArea.drag.active ? null : cardRegion)

    Region {
        id: cardRegion
        item: widgetContainer
    }

    Component.onCompleted: {
        if (root.isWindows) {
            root["x"] = Math.max(12, Math.min(root.widgetX, Screen.width - 216 - 12));
            root["y"] = Math.max(12, Math.min(root.widgetY, Screen.height - 216 - 52));
        }
    }

    // =========================================================================
    // Dynamic Adaptive Palette Engine (Synchronized with nutsty_palette.json)
    // =========================================================================
    property var frostifyPalette: ({
        "isLightArea": false,
        "baseTextColor": "#f8fafc",
        "highlightColor": "#deb06c",
        "deadTextColor": "#f1f5f9",
        "shadowDirectional": "#a6020305",
        "shadowAmbient": "#66000000"
    })

    Timer {
        id: delayedPaletteRead
        interval: 80
        repeat: false
        running: false
        onTriggered: {
            if (frostifyPaletteFile.loaded) {
                parseFrostifyPalette(frostifyPaletteFile.text());
            }
        }
    }

    FileView {
        id: frostifyPaletteFile
        path: Quickshell.env("HOME") + "/.config/noctalia/nutsty_palette.json"
        watchChanges: true
        onFileChanged: {
            this.reload();
            delayedPaletteRead.start();
        }
        onLoadedChanged: {
            if (this.loaded) {
                parseFrostifyPalette(this.text());
            }
        }
        Component.onCompleted: {
            if (this.loaded) {
                parseFrostifyPalette(this.text());
            }
        }
    }

    function parseFrostifyPalette(raw) {
        if (!raw || raw.trim() === "") return;
        try {
            var obj = JSON.parse(raw);
            var updated = Object.assign({}, root.frostifyPalette);
            for (var k in obj) {
                updated[k] = obj[k];
            }
            root.frostifyPalette = updated;
        } catch(e) {}
    }

    readonly property color colHighlight: root.frostifyPalette.highlightColor || "#deb06c"
    readonly property color colActiveText: root.frostifyPalette.baseTextColor || "#f8fafc"
    readonly property color colDeadText: root.frostifyPalette.deadTextColor || "#f1f5f9"

    // =========================================================================
    // Master Draggable Squircle Card (Dribbble/iOS Style: 216x216 px, Radius: 28)
    // Clean natural integration with desktop, zero artificial offset shadows
    // =========================================================================
    Item {
        id: widgetContainer
        x: root.isWindows ? 0 : Math.max(12, Math.min(root.widgetX, (root.width > 240 ? root.width : 800) - width - 12))
        y: root.isWindows ? 0 : Math.max(12, Math.min(root.widgetY, (root.height > 260 ? root.height : 600) - height - 52))
        width: 216
        height: 216

        Connections {
            target: root
            function onWidgetXChanged() {
                if (root.isWindows) {
                    if (!dragArea.isDraggingWindow) {
                        root["x"] = Math.max(12, Math.min(root.widgetX, Screen.width - root.width - 12));
                    }
                } else if (!dragArea.drag.active) {
                    widgetContainer.x = Math.max(12, Math.min(root.widgetX, (root.width > 240 ? root.width : 800) - widgetContainer.width - 12));
                }
            }
            function onWidgetYChanged() {
                if (root.isWindows) {
                    if (!dragArea.isDraggingWindow) {
                        root["y"] = Math.max(12, Math.min(root.widgetY, Screen.height - root.height - 52));
                    }
                } else if (!dragArea.drag.active) {
                    widgetContainer.y = Math.max(12, Math.min(root.widgetY, (root.height > 260 ? root.height : 600) - widgetContainer.height - 52));
                }
            }
        }

        // 1. Squircle Mask for pixel-perfect rounded corners (Zero corner bleed, zero dark gap)
        Rectangle {
            id: squircleMask
            anchors.fill: parent
            radius: 28
            color: "#ffffff"
            visible: false
            layer.enabled: true
        }

        // 2. Master Unified Background Surface (Image + Scrim masked in 1 pass, autoPadding: false)
        Item {
            id: backgroundSurface
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: squircleMask
                autoPaddingEnabled: false
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            // Fallback matte charcoal background
            Rectangle {
                anchors.fill: parent
                color: "#18181c"
            }

            // Album Artwork (Zoomed 1.34x inside clipped wrapper to strip YouTube 4:3 letterbox black bars)
            Item {
                anchors.fill: parent
                clip: true
                Image {
                    id: albumCoverImg
                    sourceSize: Qt.size(600, 600)
                    anchors.centerIn: parent
                    width: parent.width * 1.34
                    height: parent.height * 1.34
                    source: {
                        var raw = (root.currentTrack && (root.currentTrack.image || root.currentTrack.artUrl || root.currentTrack.cover))
                                  ? String(root.currentTrack.image || root.currentTrack.artUrl || root.currentTrack.cover) : "";
                        if (!raw) return "";
                        if (raw.startsWith("http://") || raw.startsWith("https://") || raw.startsWith("file://") || raw.startsWith("qrc:")) return raw;
                        var clean = raw.replace(/\\/g, "/");
                        return /^[A-Za-z]:/.test(clean) ? ("file:///" + clean) : ("file://" + clean);
                    }
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    visible: status === Image.Ready
                }
            }

            // MIO Matte Gradient Scrim (Light at top for artwork clarity, dark at bottom for controls)
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: Qt.rgba(0.04, 0.04, 0.06, 0.22) }
                    GradientStop { position: 0.40; color: Qt.rgba(0.04, 0.04, 0.06, 0.42) }
                    GradientStop { position: 0.72; color: Qt.rgba(0.02, 0.02, 0.04, 0.82) }
                    GradientStop { position: 1.0; color: Qt.rgba(0.01, 0.01, 0.02, 0.94) }
                }
            }
        }

        // 3. Subtle Matte Boundary (No glass effect, clean natural rim)
        Rectangle {
            anchors.fill: parent
            radius: 28
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.30)
        }

        // 4. Native Drag MouseArea covering whole card background
        MouseArea {
            id: dragArea
            anchors.fill: parent
            drag.target: root.isWindows ? null : widgetContainer
            drag.axis: Drag.XAndYAxis
            drag.minimumX: 10
            drag.minimumY: 10
            drag.maximumX: (root.screen ? root.screen.width : 1920) - widgetContainer.width - 10
            drag.maximumY: (root.screen ? root.screen.height : 1080) - widgetContainer.height - 10
            cursorShape: (drag.active || (root.isWindows && pressed)) ? Qt.ClosedHandCursor : Qt.OpenHandCursor

            property point dragStartPos: Qt.point(0, 0)
            property bool isDraggingWindow: false
            // A click that wobbles a pixel or two must stay a click, not nudge the window
            property bool dragThresholdPassed: false

            onPressed: mouse => {
                if (root.isWindows) {
                    dragStartPos = Qt.point(mouse.x, mouse.y);
                    isDraggingWindow = true;
                    dragThresholdPassed = false;
                }
            }

            onPositionChanged: mouse => {
                if (root.isWindows && isDraggingWindow && pressed) {
                    var dx = mouse.x - dragStartPos.x;
                    var dy = mouse.y - dragStartPos.y;
                    if (!dragThresholdPassed) {
                        if (Math.abs(dx) < 4 && Math.abs(dy) < 4) return;
                        dragThresholdPassed = true;
                    }
                    var curX = (typeof root["x"] !== "undefined") ? Number(root["x"]) : 0;
                    var curY = (typeof root["y"] !== "undefined") ? Number(root["y"]) : 0;
                    var newX = Math.max(12, Math.min(Screen.width - root.width - 12, curX + dx));
                    var newY = Math.max(12, Math.min(Screen.height - root.height - 52, curY + dy));
                    root["x"] = newX;
                    root["y"] = newY;
                }
            }

            onReleased: {
                if (root.isWindows) {
                    isDraggingWindow = false;
                    var finalX = (typeof root["x"] !== "undefined") ? Number(root["x"]) : root.widgetX;
                    var finalY = (typeof root["y"] !== "undefined") ? Number(root["y"]) : root.widgetY;
                    root.widgetX = finalX;
                    root.widgetY = finalY;
                    root.savePositionRequested(root.widgetX, root.widgetY);
                } else {
                    root.widgetX = widgetContainer.x;
                    root.widgetY = widgetContainer.y;
                    root.savePositionRequested(root.widgetX, root.widgetY);
                }
            }

            onDoubleClicked: {
                root.openFullAppRequested();
            }
        }

        // =====================================================================
        // TOP-LEFT: MIO Equalizer Soundwave Icon (Clickable to restore Full App)
        // =====================================================================
        Item {
            id: soundwaveButton
            z: 50
            anchors.top: parent.top
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.leftMargin: 8
            width: 52
            height: 40
            HoverHandler { id: waveH }

            // 3-Bar Equalizer Visualizer (|||)
            Row {
                anchors.centerIn: parent
                spacing: 3
                scale: waveH.hovered ? 1.15 : 1.0
                Behavior on scale { NumberAnimation { duration: 120 } }

                Rectangle {
                    id: bar1
                    width: 2.5
                    height: 12
                    radius: 1.25
                    color: waveH.hovered ? "#ffffff" : root.colHighlight
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on color { ColorAnimation { duration: 150 } }

                    SequentialAnimation on height {
                        running: root.visible && root.isPlaying
                        loops: Animation.Infinite
                        NumberAnimation { to: 4; duration: 420; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 14; duration: 380; easing.type: Easing.InOutQuad }
                    }
                }

                Rectangle {
                    id: bar2
                    width: 2.5
                    height: 16
                    radius: 1.25
                    color: waveH.hovered ? "#ffffff" : root.colHighlight
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on color { ColorAnimation { duration: 150 } }

                    SequentialAnimation on height {
                        running: root.visible && root.isPlaying
                        loops: Animation.Infinite
                        NumberAnimation { to: 16; duration: 320; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 6; duration: 450; easing.type: Easing.InOutQuad }
                    }
                }

                Rectangle {
                    id: bar3
                    width: 2.5
                    height: 10
                    radius: 1.25
                    color: waveH.hovered ? "#ffffff" : root.colHighlight
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on color { ColorAnimation { duration: 150 } }

                    SequentialAnimation on height {
                        running: root.visible && root.isPlaying
                        loops: Animation.Infinite
                        NumberAnimation { to: 6; duration: 360; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 13; duration: 400; easing.type: Easing.InOutQuad }
                    }
                }
            }

            // Click to restore / open Full App (Single touchpoint)
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                preventStealing: true
                onClicked: root.openFullAppRequested()
            }
        }

        // =====================================================================
        // TOP-RIGHT: Close button. Always on screen (new users never find the tray's ^),
        // brighter while the pointer is over the card
        // =====================================================================
        HoverHandler { id: cardH }

        Rectangle {
            id: closeBtn
            z: 50
            anchors.top: parent.top
            anchors.topMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: 12
            width: 28
            height: 28
            radius: 14
            visible: !root.closeChoiceOpen
            color: Qt.rgba(root.colHighlight.r, root.colHighlight.g, root.colHighlight.b, closeH.hovered ? 0.32 : 0.16)
            border.width: 1
            border.color: Qt.rgba(root.colHighlight.r, root.colHighlight.g, root.colHighlight.b, closeH.hovered ? 0.55 : 0.30)
            opacity: (cardH.hovered || closeH.hovered) ? 1.0 : 0.6
            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 140 } }
            HoverHandler { id: closeH }

            AppIcon {
                anchors.centerIn: parent
                source: "../assets/icons/window-close-symbolic.svg"
                iconSize: 12
                color: "#ffffff"
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                preventStealing: true
                onClicked: root.closeChoiceOpen = true
            }
        }

        // =====================================================================
        // CENTER SECTION: Inter Display Title & Artist (Left) + Big Circular Play/Pause (Right)
        // Generous whitespace, zero clutter, NEXT UP removed
        // =====================================================================
        Item {
            id: centerSection
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.top: soundwaveButton.bottom
            anchors.topMargin: 10
            anchors.bottom: bottomControls.top
            anchors.bottomMargin: 10

            // Left: Title and Artist with Inter Display Typography
            Column {
                anchors.left: parent.left
                anchors.right: playBtnCircle.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Text {
                    id: titleTxt
                    text: (root.currentTrack && root.currentTrack.title) ? root.currentTrack.title : I18n.pick("track.none", ["Chưa chọn bài hát", "Im ắng quá, chọn bài đi", "Loa đang ngồi chơi xơi nước", "Bài đâu rồi ta?", "Tai đang đói, cho ăn đi", "Chọn một bài cho đời thêm vui", "Sân khấu trống, mời bài lên"], ["No track playing", "Too quiet, pick a song", "The speakers are on a break", "Where's the song?", "Your ears are hungry, feed them", "Pick a song, brighten the day", "Empty stage, bring on a song"])
                    font.family: "Inter Display, Inter, sans-serif"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.2
                    color: "#ffffff"
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                    width: parent.width
                }

                Text {
                    id: artistTxt
                    text: (root.currentTrack && root.currentTrack.artist) ? root.currentTrack.artist : ""
                    font.family: "Inter, sans-serif"
                    font.pixelSize: 11
                    font.weight: Font.Normal
                    color: Qt.rgba(1, 1, 1, 0.72)
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    width: parent.width
                    visible: text.length > 0
                }
            }

            // Right: Big Floating Circular Play/Pause Button (Adaptive Wallpaper Color)
            Rectangle {
                id: playBtnCircle
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 46
                height: 46
                radius: 23
                color: playH.hovered ? Qt.lighter(root.colHighlight, 1.10) : root.colHighlight
                scale: playH.hovered ? 1.05 : 1.0
                Behavior on scale { NumberAnimation { duration: 120 } }
                Behavior on color { ColorAnimation { duration: 150 } }
                HoverHandler { id: playH }

                AppIcon {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: root.isPlaying ? 0 : 1.5
                    source: root.isPlaying ? "../assets/icons/media-playback-pause-symbolic.svg" : "../assets/icons/media-playback-start-symbolic.svg"
                    iconSize: 16
                    color: "#18181C"
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.playPauseClicked()
                }
            }
        }

        // =====================================================================
        // BOTTOM ROW: |<  —|—  >|  (Sleek Timeline with Vertical Needle)
        // =====================================================================
        Item {
            id: bottomControls
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            height: 28

            // 1. Prev Button
            Item {
                id: prevBtn
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24
                HoverHandler { id: prevH }

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/media-skip-backward-symbolic.svg"
                    iconSize: 14
                    color: prevH.hovered ? "#ffffff" : Qt.rgba(1, 1, 1, 0.75)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.prevClicked()
                }
            }

            // 2. Timeline with Signature Vertical Needle Indicator (|)
            Item {
                id: progressTrackItem
                anchors.left: prevBtn.right
                anchors.leftMargin: 10
                anchors.right: nextBtn.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                height: 20

                readonly property real progressRatio: root.duration > 0 ? Math.max(0, Math.min(1.0, root.currentTime / root.duration)) : 0.0

                // Background rail
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 2
                    radius: 1
                    color: Qt.rgba(1, 1, 1, 0.22)
                }

                // Active progress line
                Rectangle {
                    id: activeProgressLine
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    height: 2
                    radius: 1
                    width: Math.max(2, progressTrackItem.width * progressTrackItem.progressRatio)
                    color: root.colHighlight
                }

                // Vertical Needle Tick Indicator (|) (Signature Dribbble Element)
                Rectangle {
                    id: needleMarker
                    x: Math.max(0, Math.min(progressTrackItem.width - width, activeProgressLine.width - width / 2))
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2.5
                    height: 10
                    radius: 1.25
                    color: "#ffffff"

                    // Subtle glow around the needle
                    Rectangle {
                        anchors.centerIn: parent
                        width: 6
                        height: 14
                        radius: 3
                        color: Qt.alpha(root.colHighlight, 0.35)
                        z: -1
                    }
                }

                // Interactive Seek MouseArea
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true

                    function handleSeek(mouseX) {
                        var ratio = Math.max(0.0, Math.min(1.0, mouseX / progressTrackItem.width));
                        root.seekRequested(ratio * root.duration);
                    }

                    onClicked: (mouse) => handleSeek(mouse.x)
                    onPositionChanged: (mouse) => {
                        if (pressed) handleSeek(mouse.x);
                    }
                }
            }

            // 3. Next Button
            Item {
                id: nextBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24
                HoverHandler { id: nextH }

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/media-skip-forward-symbolic.svg"
                    iconSize: 14
                    color: nextH.hovered ? "#ffffff" : Qt.rgba(1, 1, 1, 0.75)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.nextClicked()
                }
            }
        }

        // =====================================================================
        // Close choice, drawn inside the card (no popup window): hide the widget or quit.
        // Clicking the dimmed card outside the buttons goes back
        // =====================================================================
        Rectangle {
            id: closeChoice
            z: 100
            anchors.fill: parent
            radius: 28
            color: Qt.rgba(0.03, 0.03, 0.05, 0.86)
            border.width: 1
            border.color: Qt.rgba(root.colHighlight.r, root.colHighlight.g, root.colHighlight.b, 0.25)
            opacity: root.closeChoiceOpen ? 1.0 : 0.0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

            MouseArea {
                anchors.fill: parent
                enabled: root.closeChoiceOpen
                onClicked: root.closeChoiceOpen = false
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - 36
                spacing: 8

                ChoiceButton {
                    iconSource: "../assets/icons/eye-slash-symbolic.svg"
                    label: I18n.tr("Ẩn trình phát nhỏ", "Hide mini player")
                    tint: root.colHighlight
                    onActivated: {
                        root.closeChoiceOpen = false;
                        root.hideWidgetRequested();
                    }
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: I18n.tr("Nhạc vẫn phát", "Music keeps playing")
                    font.family: "Inter, sans-serif"
                    font.pixelSize: 10
                    color: Qt.rgba(1, 1, 1, 0.62)
                }

                Item { width: 1; height: 2 }

                // Muted Rose: the destructive choice
                ChoiceButton {
                    iconSource: "../assets/icons/window-close-symbolic.svg"
                    label: I18n.tr("Thoát Nutsty", "Quit Nutsty")
                    tint: Qt.rgba(244 / 255, 63 / 255, 94 / 255, 1)
                    onActivated: {
                        root.closeChoiceOpen = false;
                        root.quitRequested();
                    }
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: I18n.tr("Quay lại", "Back")
                    font.family: "Inter, sans-serif"
                    font.pixelSize: 11
                    font.weight: backH.hovered ? Font.DemiBold : Font.Normal
                    color: backH.hovered ? "#ffffff" : Qt.rgba(1, 1, 1, 0.62)
                    topPadding: 4
                    HoverHandler { id: backH; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.closeChoiceOpen = false }
                }
            }
        }
    }

    component ChoiceButton: Rectangle {
        id: choiceBtn
        property url iconSource
        property string label
        property color tint
        signal activated()

        width: parent ? parent.width : 160
        height: 34
        radius: 8
        color: Qt.rgba(tint.r, tint.g, tint.b, choiceH.hovered ? 0.24 : 0.12)
        border.width: 1
        border.color: Qt.rgba(tint.r, tint.g, tint.b, choiceH.hovered ? 0.45 : 0.25)
        Behavior on color { ColorAnimation { duration: 120 } }
        HoverHandler { id: choiceH }

        Row {
            anchors.centerIn: parent
            spacing: 8
            AppIcon {
                anchors.verticalCenter: parent.verticalCenter
                source: choiceBtn.iconSource
                iconSize: 12
                color: "#ffffff"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: choiceBtn.label
                font.family: "Inter, sans-serif"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: "#ffffff"
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            preventStealing: true
            onClicked: choiceBtn.activated()
        }
    }
}
