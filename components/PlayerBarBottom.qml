import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Shapes
import "."

Item {
    id: root
    implicitWidth: 710 + coListenPill.targetWidth
    implicitHeight: 60
    height: 60

    property real radius: 30
    property Item backgroundSourceItem: null
    property var currentTrack: null
    property var audioSpecs: null
    property bool isPlaying: false
    property real currentTime: 0.0
    property real totalDuration: 1.0
    property real volume: 100.0
    property real prevVolume: 100.0
    property bool isShuffle: false
    property string repeatMode: "off"   // "off" | "all" (queue) | "one" (current song)
    readonly property bool repeatOn: repeatMode !== "off"
    property bool isLyricsActive: false
    property bool isNowPlayingOpen: false
    property bool isQueueActive: false
    property bool isScrubbingProgress: false
    property real scrubTime: 0.0
    property bool isScrubbingVolume: false
    property bool isLoadingAudio: false
    property bool mixing: false // AutoMix is blending: the centre shows "Cooking" in place of the audio specs
    // "Cooking" stays for the whole blend, however long the AutoMix settings make it, and leaves once the
    // new track has fully taken over. "mixing" can blink off for a moment while the engine switches tracks,
    // so it only counts as finished after staying off briefly
    property bool cookingShown: false
    onMixingChanged: {
        if (mixing) { cookingHideDelay.stop(); cookingShown = true; }
        else cookingHideDelay.restart();
    }
    Timer { id: cookingHideDelay; interval: 450; onTriggered: root.cookingShown = false }
    // 0 = title + cover, 1 = "Cooking": drives the push-up handover between the two
    property real cookT: cookingShown ? 1 : 0
    Behavior on cookT { NumberAnimation { duration: 560; easing.type: Easing.OutCubic } }
    property bool isSleepTimerActive: false
    property var listeningAlongFriend: null
    property var activeCoListenersDetails: []
    property bool isChatInputOpen: false
    readonly property bool isCoListeningActive: (root.listeningAlongFriend !== null && root.listeningAlongFriend !== undefined) || (root.activeCoListenersDetails && root.activeCoListenersDetails.length > 0)
    property int sleepTimerRemainingSeconds: 0
    property color accentColor: "#deb06c"
    property string resolvedSquareImage: ""
    property bool squareFailed: false
    onResolvedSquareImageChanged: root.squareFailed = false
    onCurrentTrackChanged: {
        root.squareFailed = false;
        root.triggerBackdropUpdate();
    }
    onWidthChanged: root.triggerBackdropUpdate()
    onIsBarHeldChanged: if (!root.isBarHeld) root.triggerBackdropUpdate()
    onIsNowPlayingOpenChanged: {
        backdropCropSource.scheduleUpdate();
        root.triggerBackdropUpdate();
    }
    onIsLyricsActiveChanged: {
        backdropCropSource.scheduleUpdate();
        root.triggerBackdropUpdate();
    }
    Component.onCompleted: root.triggerBackdropUpdate()

    property bool isLiked: false
    property bool isVolumePopupOpen: false
    property bool isVolumeSliding: false
    property bool isMousePressed: false
    readonly property bool isBarHeld: barPointer.active || isMousePressed
    property real spotlightX: width / 2
    property real spotlightY: height / 2
    property real holdIntensity: isBarHeld ? 1.0 : 0.0

    signal playPauseClicked()
    signal nextClicked()
    signal prevClicked()
    signal toggleShuffle()
    signal toggleRepeat()
    signal seekRequested(real seconds)
    signal reqVolumeChange(real newVol)
    signal openDetailsRequested()
    // Centre of the mini cover in `item` coordinates (origin of the Now Playing shape reveal)
    function coverCenterIn(item) {
        return miniCoverContainer.mapToItem(item, miniCoverContainer.width / 2, miniCoverContainer.height / 2);
    }
    signal barClicked()
    signal lyricsClicked()
    signal queueClicked()
    signal openArtistRequested(string artistName, string channelId)
    signal closeClicked()
    signal exitListeningAlongRequested()
    signal openCoListenersRequested(real targetX, real targetY)
    signal sendChatMessageRequested(string messageText)
    signal toggleLikeClicked()
    signal openVolumePopoverRequested()

    readonly property bool isBodyHovered: (backgroundDragArea.containsMouse || centerHoverHandler.hovered) && !miniCoverHover.hovered && !root.isScrubbingProgress && !miniProgressBarHover.hovered

    property alias volumeButtonAnchorItem: volumeButtonAnchor

    function fmtTime(sec) {
        if (!sec || sec < 0) return "00:00";
        var m = Math.floor(sec / 60);
        var s = Math.floor(sec % 60);
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
    }

    Behavior on holdIntensity {
        NumberAnimation {
            duration: root.isBarHeld ? 160 : 320
            easing.type: root.isBarHeld ? Easing.OutQuad : Easing.OutCubic
        }
    }

    // SimpMusic pressedScale: 1.04f with spring dampingRatio: 0.5, stiffness: 300
    scale: isBarHeld ? 1.04 : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: root.isBarHeld ? 180 : 320
            easing.type: root.isBarHeld ? Easing.OutCubic : Easing.OutBack
            easing.overshoot: 1.10
        }
    }

    // Pointer Tracking (Follows cursor coordinates continuously while held)
    PointHandler {
        id: barPointer
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchScreen | PointerDevice.Stylus
        onActiveChanged: {
            if (active) {
                root.spotlightX = point.position.x;
                root.spotlightY = point.position.y;
            }
        }
        onPointChanged: {
            if (active) {
                root.spotlightX = Math.max(0, Math.min(root.width, point.position.x));
                root.spotlightY = Math.max(0, Math.min(root.height, point.position.y));
            }
        }
    }

    // Background Drag & Body Click MouseArea: Strictly distinguishes Click (toggle Mochy) vs Hold (Spotlight)
    MouseArea {
        id: backgroundDragArea
        anchors.fill: parent
        z: 1
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton

        property real pressStartTime: 0
        property real pressStartX: 0
        property real pressStartY: 0
        property bool isDragOrHoldDetected: false

        onPressed: mouse => {
            if (mouse.button !== Qt.LeftButton) return;
            pressStartTime = Date.now();
            pressStartX = mouse.x;
            pressStartY = mouse.y;
            isDragOrHoldDetected = false;
            root.isMousePressed = true;
            root.spotlightX = mouse.x;
            root.spotlightY = mouse.y;
        }

        onPositionChanged: mouse => {
            if (pressed) {
                root.spotlightX = Math.max(0, Math.min(root.width, mouse.x));
                root.spotlightY = Math.max(0, Math.min(root.height, mouse.y));
                var dx = mouse.x - pressStartX;
                var dy = mouse.y - pressStartY;
                if ((dx * dx + dy * dy) > 25) {
                    isDragOrHoldDetected = true;
                }
            }
        }

        onReleased: mouse => {
            var elapsed = Date.now() - pressStartTime;
            var wasHoldOrDrag = isDragOrHoldDetected || (elapsed >= 220);
            root.isMousePressed = false;
            isDragOrHoldDetected = false;

            // Only fire barClicked if it was a genuine short click without dragging/holding
            if (!wasHoldOrDrag && elapsed < 220) {
                root.barClicked();
            }
        }

        onCanceled: {
            root.isMousePressed = false;
            isDragOrHoldDetected = false;
        }
    }

    // =========================================================================
    // Capsule Mask (Pure Pill shape: radius = height / 2 = 30px)
    // =========================================================================
    Item {
        id: capsuleMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: "#ffffff"
        }
    }

    // =========================================================================
    // 1. LIQUID GLASS BACKDROP BLUR (SimpMusic / MultiEffect Hardware Blur)
    // Dynamically crops the exact area behind playerbar and runs 48px GPU Gaussian Blur!
    // Dissolves any background text or image into a silky, illegible haze!
    // =========================================================================
    Item {
        id: cropAnchorHelper
        property point cropPos: {
            if (!root.backgroundSourceItem) return Qt.point(root.x, root.y);
            var _dep = root.x + root.y + root.width + root.height + (root.parent ? (root.parent.width + root.parent.height) : 0);
            return root.mapToItem(root.backgroundSourceItem, 0, 0);
        }
        onCropPosChanged: root.triggerBackdropUpdate()
    }

    ShaderEffectSource {
        id: backdropCropSource
        sourceItem: root.backgroundSourceItem
        sourceRect: Qt.rect(cropAnchorHelper.cropPos.x, cropAnchorHelper.cropPos.y, root.width, root.height)
        visible: false
        live: root.isBarHeld || root.isScrubbingProgress || root.isScrubbingVolume || backdropLiveDebounce.running
        smooth: true
    }

    Timer {
        id: backdropLiveDebounce
        interval: 260
        repeat: false
        onTriggered: {
            backdropCropSource.scheduleUpdate();
        }
    }

    function triggerBackdropUpdate() {
        backdropLiveDebounce.restart();
    }

    MultiEffect {
        anchors.fill: parent
        source: backdropCropSource
        blurEnabled: (root.backgroundSourceItem !== null) && (typeof win === "undefined" || !win || Boolean(win.isWindowEffectivelyActive))
        blur: 1.0
        blurMax: Theme.blurAtmosphere
        saturation: 1.55
        brightness: -0.05
        maskEnabled: true
        maskSource: capsuleMask
        autoPaddingEnabled: false
        visible: root.backgroundSourceItem !== null
        z: 1
    }

    // Adaptive Dark Scrim (SimpMusic: 48% dark overlay so white text & controls pop with 100% contrast!)
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Qt.rgba(0.08, 0.09, 0.12, 0.48)
        border.color: root.isBarHeld ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.40) : (root.isBodyHovered ? Qt.rgba(1, 1, 1, 0.32) : Qt.rgba(1, 1, 1, 0.18))
        border.width: 1
        Behavior on border.color { ColorAnimation { duration: 200 } }
        z: 2
    }

    // =========================================================================
    // 2. INTERACTIVE RADIAL SPOTLIGHT (SimpMusic LiquidGlassContainer radial gradient + blur)
    // STRICTLY DORMANT (0.0) ON HOVER — EXCITED ONLY ON HOLD!
    // Diffuse, soft ambient phosphor glow without harsh center disc!
    // =========================================================================
    Item {
        id: spotlightLayer
        anchors.fill: parent
        visible: root.holdIntensity > 0.001
        z: 3
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: capsuleMask
            autoPaddingEnabled: false
        }

        Item {
            id: spotlightGlow
            width: 320
            height: 320
            x: root.spotlightX - width / 2
            y: root.spotlightY - height / 2
            opacity: root.holdIntensity

            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: root.holdIntensity > 0.001 && (typeof win === "undefined" || !win || Boolean(win.isWindowEffectivelyActive))
                blur: 0.95
                blurMax: Theme.blurAtmosphere
            }

            Shape {
                anchors.fill: parent
                ShapePath {
                    strokeColor: "transparent"
                    fillGradient: RadialGradient {
                        centerX: 160; centerY: 160; centerRadius: 160
                        focalX: 160; focalY: 160; focalRadius: 0
                        GradientStop { position: 0.00; color: Qt.rgba(1.0, 1.0, 1.0, 0.24) }
                        GradientStop { position: 0.25; color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18) }
                        GradientStop { position: 0.60; color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.06) }
                        GradientStop { position: 0.85; color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.015) }
                        GradientStop { position: 1.00; color: "transparent" }
                    }
                    startX: 0; startY: 0
                    PathRectangle { x: 0; y: 0; width: 320; height: 320 }
                }
            }
        }
    }

    // Capsule Rim Hairline
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: root.isBarHeld ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.40) : (root.isBodyHovered ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.12))
        Behavior on border.color { ColorAnimation { duration: 200 } }
        z: 4
    }

    // =========================================================================
    // 3. THREE-SECTION CONTENT ROW: [LEFT: 200px] | [DIV1: 29px] | [CENTER: 300px] | [DIV2: 29px] | [RIGHT]
    // =========================================================================
    Row {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 0
        z: 5

        // ---------------------------------------------------------------------
        // SECTION 1: LEFT (PlayerControlLayout - Fixed 200px width, SpaceEvenly)
        // ---------------------------------------------------------------------
        Item {
            id: leftSectionBox
            width: 200
            height: root.height

            Row {
                anchors.fill: parent
                spacing: 0

                // 1. Shuffle (White icon, 20px, NOT accent color!)
                Item {
                    width: 40; height: parent.height
                    HoverHandler { id: shufH }
                    scale: shufH.hovered ? 1.08 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/media-playlist-shuffle-symbolic.svg"
                        iconSize: 20
                        color: root.isShuffle ? root.accentColor : "#ffffff"
                    }
                    Rectangle {
                        width: 3; height: 3; radius: 1.5
                        color: root.accentColor
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 8
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.isShuffle
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleShuffle()
                    }
                }

                // 2. Previous (22px)
                Item {
                    width: 40; height: parent.height
                    HoverHandler { id: prevH }
                    scale: prevH.hovered ? 1.08 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/media-skip-backward-symbolic.svg"
                        iconSize: 22
                        color: "#ffffff"
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.prevClicked()
                    }
                }

                // 3. Play / Pause (Bare glyph ▶ / ⏸ — NO solid circle, SimpMusic plainPlayPause = true!)
                Item {
                    width: 40; height: parent.height
                    HoverHandler { id: playH }
                    AppIcon {
                        anchors.centerIn: parent
                        source: root.isPlaying ? "../assets/icons/media-playback-pause-symbolic.svg" : "../assets/icons/media-playback-start-symbolic.svg"
                        iconSize: 26
                        color: playH.hovered ? "#ffffff" : "#f1f5f9"
                    }
                    scale: playH.hovered ? 1.08 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.playPauseClicked()
                    }
                }

                // 4. Next (22px)
                Item {
                    width: 40; height: parent.height
                    HoverHandler { id: nextH }
                    scale: nextH.hovered ? 1.08 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/media-skip-forward-symbolic.svg"
                        iconSize: 22
                        color: "#ffffff"
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.nextClicked()
                    }
                }

                // 5. Repeat (White icon, 20px, 40px width away from divider!)
                Item {
                    width: 40; height: parent.height
                    HoverHandler { id: repH }
                    scale: repH.hovered ? 1.08 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    // Material repeat / repeat_one (the "1" sits inside the loop), same pair as NowPlayingControls
                    AppIcon {
                        anchors.centerIn: parent
                        source: root.repeatMode === "one" ? "../assets/icons/material/ms-repeat_one.svg"
                                                          : "../assets/icons/material/ms-repeat.svg"
                        iconSize: 26
                        color: root.repeatOn ? root.accentColor : "#ffffff"
                    }
                    // Loop the queue: a dot under the icon
                    Rectangle {
                        width: 3; height: 3; radius: 1.5
                        color: root.accentColor
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 8
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.repeatMode === "all"
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleRepeat()
                    }
                }
            }
        }

        // --- Vertical Divider 1 (height: 28dp, padding: 14dp each side = 29px) ---
        Item {
            width: 29
            height: root.height
            Rectangle {
                anchors.centerIn: parent
                width: 1
                height: 28
                color: Qt.rgba(1, 1, 1, 0.20)
            }
        }

        // ---------------------------------------------------------------------
        // SECTION 2: CENTER (Fixed 300px width: Artwork + Title/Artist + Scrubber)
        // ---------------------------------------------------------------------
        Item {
            id: centerSectionBox
            width: 300
            height: root.height

            // Persistent hover zone covering middle text/metadata area (excludes mini cover at left: 0-42px)
            Item {
                id: centerHoverZone
                anchors.left: parent.left
                anchors.leftMargin: 42
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                z: 2

                HoverHandler {
                    id: centerHoverHandler
                }
            }

            // Hover shows the timeline (old behaviour). While AutoMix blends, the timeline with "Cooking" holds
            // until the new track has taken over, then the centre returns to title + cover
            readonly property bool showScrubber: ((centerHoverHandler.hovered || miniProgressBarHover.hovered || root.isScrubbingProgress) && !miniCoverHover.hovered) || root.cookingShown
            property real infoAlpha: showScrubber ? 0.0 : 1.0
            // The Cooking handover is slower than a hover so the push-up motion reads clearly
            Behavior on infoAlpha { NumberAnimation { duration: (root.cookingShown || root.cookT > 0.01) ? 420 : 220; easing.type: Easing.InOutQuad } }

            // --- State A: Artwork (32x32, bo 6dp) + Track Title & Artist (Rest State) ---
            RowLayout {
                anchors.fill: parent
                anchors.bottomMargin: 10
                spacing: 10
                opacity: centerSectionBox.infoAlpha
                visible: opacity > 0.01
                // Cooking handover: title + cover lift away as "Cooking" rises in, and settle back down after
                transform: Translate { y: -9 * root.cookT }
                scale: 1.0 - 0.04 * root.cookT

                // Thumbnail Artwork (32x32, radius 6px) with Spring Hover-Zoom & open_in_full overlay
                Item {
                    id: miniCoverContainer
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32

                    Item {
                        id: miniCoverScalable
                        anchors.fill: parent
                        scale: miniCoverHover.hovered ? 1.15 : 1.0
                        transformOrigin: Item.Center
                        z: miniCoverHover.hovered ? 10 : 1

                        Behavior on scale {
                            SpringAnimation {
                                spring: 7
                                damping: 0.24
                                epsilon: 0.002
                            }
                        }

                        // Soft diffuse shadow behind miniCover on hover (Swiftify style)
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -3
                            radius: 8
                            color: Qt.rgba(0, 0, 0, miniCoverHover.hovered ? 0.55 : 0.0)
                            z: -1
                            Behavior on color { ColorAnimation { duration: 160 } }
                        }

                        RoundedImage {
                            id: miniCover
                            anchors.fill: parent
                            radius: 6
                            source: {
                                if (root.resolvedSquareImage !== "" && !root.squareFailed) {
                                    var r = root.resolvedSquareImage;
                                    return (r.startsWith("/") && !r.startsWith("file://")) ? ("file://" + r) : r;
                                }
                                if (!root.currentTrack) return "";
                                var s = root.currentTrack.image || root.currentTrack.artUrl || root.currentTrack.cover || root.currentTrack.thumbnail || "";
                                if (!s && root.currentTrack.videoId) {
                                    s = "https://i.ytimg.com/vi/" + root.currentTrack.videoId + "/hqdefault.jpg";
                                }
                                if (s.indexOf("i.ytimg.com") !== -1) s = s.split("?")[0];
                                return (s.startsWith("/") && !s.startsWith("file://")) ? ("file://" + s) : s;
                            }
                            fillMode: Image.PreserveAspectCrop
                            autoCropBlackBars: true
                            sourceSize: Qt.size(128, 128)
                            fallbackIcon: "../assets/icons/folder-music-symbolic.svg"
                            fallbackIconSize: 16
                            onStatusChanged: {
                                if (status === Image.Error && root.resolvedSquareImage !== "" && !root.squareFailed) {
                                    root.squareFailed = true;
                                }
                            }
                        }

                        // Subtle dark overlay on hover
                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            color: Qt.rgba(0, 0, 0, 0.40)
                            opacity: miniCoverHover.hovered ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 140 } }
                        }

                        // open_in_full icon on hover
                        AppIcon {
                            anchors.centerIn: parent
                            source: "../assets/icons/open-in-full-symbolic.svg"
                            iconSize: 15
                            color: "#ffffff"
                            opacity: miniCoverHover.hovered ? 1.0 : 0.0
                            scale: miniCoverHover.hovered ? 1.0 : 0.7
                            Behavior on opacity { NumberAnimation { duration: 140 } }
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                        }

                        // Concentric border
                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            color: "transparent"
                            border.color: miniCoverHover.hovered ? Qt.rgba(1.0, 1.0, 1.0, 0.45) : Qt.rgba(1.0, 1.0, 1.0, 0.18)
                            border.width: 1
                            Behavior on border.color { ColorAnimation { duration: 140 } }
                        }
                    }

                    // Same reason as miniProgressBarHover: a click here hides the bar (Now Playing opens), which can
                    // leave MouseArea.containsMouse stuck; HoverHandler reports leaving reliably
                    HoverHandler { id: miniCoverHover }

                    MouseArea {
                        id: miniCoverMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            mouse.accepted = true;
                            root.openDetailsRequested();
                        }
                    }
                }

                // Metadata Text (State A: Title & Artist)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        Layout.fillWidth: true
                        text: root.currentTrack ? (root.currentTrack.title || root.currentTrack.name || "Nutsty Track") : "Nutsty Desktop"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                        color: "#ffffff"
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: {
                            if (!root.currentTrack) return I18n.tr("Sẵn sàng phát", "Ready to play");
                            var raw = String(root.currentTrack.artist || "").trim();
                            var clean = raw.split(/\s*•\s*/)[0].replace(/\s*\d+([.,]\d+)?[KMBkmb]?\s*(views|plays|lượt xem|lượt nghe).*/i, "").trim();
                            return clean || raw || "Nutsty Desktop";
                        }
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Qt.rgba(1, 1, 1, 0.70)
                        elide: Text.ElideRight
                    }
                }
            }

            // --- State B: Scrubber Timestamps & Quality Text (SimpMusic Clean Typography - NO PILL!) ---
            Item {
                id: stateBContainer
                anchors.fill: parent
                anchors.bottomMargin: 10
                opacity: 1.0 - centerSectionBox.infoAlpha
                visible: opacity > 0.01

                // Elapsed Time (Left)
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.fmtTime(root.isScrubbingProgress ? root.scrubTime : root.currentTime)
                    font.family: "Segoe UI, Inter, monospace"
                    font.pixelSize: 11
                    color: Qt.rgba(1, 1, 1, 0.70)
                }

                // AutoMix blending: "Cooking" takes the audio-specs spot for the whole blend; afterwards
                // hovering shows the normal audio specs again
                ShimmerText {
                    anchors.centerIn: parent
                    text: I18n.tr("Cooking", "Cooking")
                    pixelSize: 11
                    running: root.cookingShown
                    opacity: root.cookT
                    visible: opacity > 0.01
                    // Rises from below with its letters drawing together, and sinks back as they spread on exit
                    letterSpacing: 0.6 + 2.4 * (1.0 - root.cookT)
                    scale: 0.86 + 0.14 * root.cookT
                    transform: Translate { y: 9 * (1.0 - root.cookT) }
                }

                // Audio Quality Line (Center: Clean Optical Icon + Text, True Optical Horizontal Center)
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    opacity: 1.0 - root.cookT
                    visible: opacity > 0.01

                    AppIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        source: "../assets/icons/media-optical-audio-symbolic.svg"
                        iconSize: 13
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (root.audioSpecs && (root.audioSpecs.bitrate_str || root.audioSpecs.bitrate)) {
                                var codecName = (root.audioSpecs.codec || "AAC").toUpperCase();
                                var bStr = root.audioSpecs.bitrate_str || (root.audioSpecs.bitrate + " kbps");
                                return codecName + " • " + bStr;
                            }
                            if (root.currentTrack && root.currentTrack.path) {
                                var p = root.currentTrack.path.toLowerCase();
                                if (p.endsWith(".flac")) return "FLAC • Lossless";
                                if (p.endsWith(".mp3")) return "MP3 • 320 kbps";
                            }
                            return "AAC • 128 kbps";
                        }
                        font.family: "Segoe UI, Inter, sans-serif"
                        font.pixelSize: 11
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }
                }

                // Remaining Signed Time (Right: "-mm:ss")
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "−" + root.fmtTime(Math.max(0, root.totalDuration - (root.isScrubbingProgress ? root.scrubTime : root.currentTime)))
                    font.family: "Segoe UI, Inter, monospace"
                    font.pixelSize: 11
                    color: Qt.rgba(1, 1, 1, 0.70)
                }
            }

            // --- CapsuleProgress (Bottom of 300px Center Section - 2dp expands to 4dp) ---
            Item {
                id: miniProgressBar
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                anchors.left: parent.left
                anchors.right: parent.right
                height: 16

                property real progressFraction: {
                    if (root.isScrubbingProgress) {
                        return root.totalDuration > 0 ? (root.scrubTime / root.totalDuration) : 0.0;
                    }
                    return (root.totalDuration > 0) ? Math.min(1.0, Math.max(0.0, root.currentTime / root.totalDuration)) : 0.0;
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: centerSectionBox.showScrubber ? 4 : 2
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.20)
                    Behavior on height { NumberAnimation { duration: 120 } }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: Math.max(0, parent.width * miniProgressBar.progressFraction)
                        radius: parent.radius
                        color: "#ffffff"
                    }

                    // Progress Thumb Dot (SimpMusic thumb indicator on hover/scrub)
                    Rectangle {
                        width: 7; height: 7; radius: 3.5
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.max(0, Math.min(parent.width - width, parent.width * miniProgressBar.progressFraction - width / 2))
                        visible: centerSectionBox.showScrubber && miniProgressBar.progressFraction > 0.005
                    }
                }

                // Hover is read from a HoverHandler: after a press-drag-release seek, MouseArea.containsMouse can
                // stay true once the pointer has left (Wayland), which pinned the bar on the timeline view
                HoverHandler { id: miniProgressBarHover }

                MouseArea {
                    id: miniProgressBarMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Never toggle enabled with the duration: disabling a hovered MouseArea leaves containsMouse
                    // stuck true (the bar then stays on the timeline view). Guard the seek instead.
                    enabled: !!root.currentTrack

                    function updateSeek(mx) {
                        var f = Math.max(0.0, Math.min(1.0, mx / width));
                        root.scrubTime = f * root.totalDuration;
                    }

                    onPressed: mouse => {
                        if (!(root.totalDuration > 0)) return;
                        root.isScrubbingProgress = true;
                        updateSeek(mouse.x);
                    }
                    onPositionChanged: mouse => {
                        if (root.isScrubbingProgress) updateSeek(mouse.x);
                    }
                    onReleased: {
                        if (root.isScrubbingProgress) {
                            root.seekRequested(root.scrubTime);
                            root.isScrubbingProgress = false;
                        }
                    }
                    onCanceled: root.isScrubbingProgress = false
                }
            }
        }

        // --- Vertical Divider 2 (height: 28dp, padding: 14dp each side = 29px) ---
        Item {
            width: 29
            height: root.height
            Rectangle {
                anchors.centerIn: parent
                width: 1
                height: 28
                color: Qt.rgba(1, 1, 1, 0.20)
            }
        }

        // ---------------------------------------------------------------------
        // SECTION 3: RIGHT (Action Cluster: Like, Listen Along capsule, Volume, Close; Lyrics / Up Next live in Now Playing)
        // ---------------------------------------------------------------------
        Item {
            id: rightSectionBox
            width: 120 + coListenPill.width
            height: root.height

            Row {
                anchors.fill: parent
                spacing: 0

                // 1. Like / Heart (Heart outline when unliked, vibrant Rose Pink #f43f5e when liked + Fireworks Pop)
                Item {
                    id: likeButtonContainer
                    width: 40; height: parent.height

                    HoverHandler { id: likeH }

                    // Fireworks Confetti Particles + Halo Ring
                    Item {
                        id: heartFireworks
                        anchors.centerIn: parent
                        width: 0; height: 0
                        property real burstProgress: 0.0
                        visible: burstProgress > 0.001

                        NumberAnimation {
                            id: burstAnim
                            target: heartFireworks
                            property: "burstProgress"
                            from: 0.0
                            to: 1.0
                            duration: 480
                            easing.type: Easing.OutQuad
                        }

                        // Expanding Halo Ripple
                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.round(36 * heartFireworks.burstProgress)
                            height: width
                            radius: width / 2
                            color: "transparent"
                            border.color: "#f43f5e"
                            border.width: Math.max(0.5, 2.0 * (1.0 - heartFireworks.burstProgress))
                            opacity: Math.max(0.0, 0.85 - heartFireworks.burstProgress * 0.9)
                        }

                        // 8 Radiating Confetti Particles
                        Repeater {
                            model: 8
                            delegate: Rectangle {
                                required property int index
                                readonly property real angle: index * (Math.PI / 4)
                                readonly property real dist: 28 * heartFireworks.burstProgress
                                x: Math.cos(angle) * dist - width / 2
                                y: Math.sin(angle) * dist - height / 2
                                width: Math.max(1, Math.round((index % 2 === 0 ? 4.5 : 3.0) * (1.0 - heartFireworks.burstProgress * 0.45)))
                                height: width
                                radius: width / 2
                                color: ["#f43f5e", "#fb7185", "#f59e0b", "#facc15", "#c084fc", "#e879f9", "#38bdf8", "#ffffff"][index % 8]
                                opacity: Math.max(0.0, 1.0 - heartFireworks.burstProgress * 1.15)
                            }
                        }
                    }

                    SequentialAnimation {
                        id: heartBounceAnim
                        NumberAnimation { target: heartIconWrapper; property: "scale"; to: 1.45; duration: 110; easing.type: Easing.OutBack }
                        NumberAnimation { target: heartIconWrapper; property: "scale"; to: 0.82; duration: 90; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: heartIconWrapper; property: "scale"; to: 1.18; duration: 80; easing.type: Easing.OutQuad }
                        NumberAnimation { target: heartIconWrapper; property: "scale"; to: 1.0; duration: 70; easing.type: Easing.InOutQuad }
                    }

                    Item {
                        id: heartIconWrapper
                        anchors.fill: parent
                        scale: likeH.hovered ? 1.08 : 1.0
                        transformOrigin: Item.Center
                        Behavior on scale { NumberAnimation { duration: 120 } }

                        AppIcon {
                            id: heartIcon
                            anchors.centerIn: parent
                            source: root.isLiked ? "../assets/icons/emblem-favorite-symbolic.svg" : "../assets/icons/favorite-border-symbolic.svg"
                            iconSize: 20
                            color: root.isLiked ? "#f43f5e" : "#ffffff"
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.isLiked) {
                                burstAnim.restart();
                                heartBounceAnim.restart();
                            }
                            root.toggleLikeClicked();
                        }
                    }
                }

                // Listen Along capsule (SimpMusic-style pill after Like): slides open only while
                // friends listen together, holding the floating chat and the listeners / leave controls.
                Item {
                    id: coListenPill
                    readonly property bool isListener: root.listeningAlongFriend !== null && root.listeningAlongFriend !== undefined
                    readonly property int listenerCount: root.activeCoListenersDetails ? root.activeCoListenersDetails.length : 0
                    readonly property real targetWidth: root.isCoListeningActive ? pillRow.implicitWidth + 24 : 0
                    width: targetWidth
                    height: parent.height
                    clip: true
                    visible: width > 0.5
                    opacity: root.isCoListeningActive ? 1.0 : 0.0
                    Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    Rectangle {
                        anchors.centerIn: parent
                        width: pillRow.implicitWidth + 12
                        height: 36
                        radius: 18
                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14)
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.32)
                        border.width: 1

                        Row {
                            id: pillRow
                            anchors.centerIn: parent
                            spacing: 2

                            // Floating chat: friends see the message drift across their screen
                            Rectangle {
                                width: 30; height: 30; radius: 15
                                color: root.isChatInputOpen ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.30) : (chatPillH.hovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18) : "transparent")
                                HoverHandler { id: chatPillH }
                                AppIcon {
                                    anchors.centerIn: parent
                                    source: "../assets/icons/chat-message-new-symbolic.svg"
                                    iconSize: 16
                                    color: root.isChatInputOpen ? root.accentColor : "#ffffff"
                                }
                                ToolTip.visible: chatPillH.hovered
                                ToolTip.text: I18n.tr("Gửi bình luận bay", "Send a floating comment")
                                ToolTip.delay: 350
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.isChatInputOpen = !root.isChatInputOpen;
                                        if (root.isChatInputOpen) chatTextInput.forceActiveFocus();
                                    }
                                }
                            }

                            Rectangle {
                                width: 1; height: 16
                                anchors.verticalCenter: parent.verticalCenter
                                color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                            }

                            // Host side: manage who is listening (switch track permission, remove)
                            Rectangle {
                                id: listenersPillBtn
                                visible: !coListenPill.isListener
                                width: listenersRow.implicitWidth + 14; height: 30; radius: 15
                                color: listenersPillH.hovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18) : "transparent"
                                HoverHandler { id: listenersPillH }
                                Row {
                                    id: listenersRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    AppIcon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        source: "../assets/icons/system-users-symbolic.svg"
                                        iconSize: 16
                                        color: "#ffffff"
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: coListenPill.listenerCount
                                        color: root.accentColor
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                    }
                                }
                                ToolTip.visible: listenersPillH.hovered
                                ToolTip.text: I18n.tr("Quản lý người nghe cùng", "Manage listeners")
                                ToolTip.delay: 350
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var pt = listenersPillBtn.mapToItem(null, listenersPillBtn.width / 2, 0);
                                        root.openCoListenersRequested(pt.x, pt.y);
                                    }
                                }
                            }

                            // Listener side: whose music you follow, plus a Muted Rose leave button
                            Row {
                                visible: coListenPill.isListener
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                leftPadding: 4
                                RoundedImage {
                                    width: 24; height: 24; radius: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    borderColor: root.accentColor
                                    borderWidth: 1.5
                                    source: coListenPill.isListener ? (root.listeningAlongFriend.avatar_url || root.listeningAlongFriend.avatar || "") : ""
                                    fallbackIcon: "../assets/icons/system-users-symbolic.svg"
                                    placeholderColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                                }
                                Rectangle {
                                    width: 26; height: 26; radius: 13
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: leavePillH.hovered ? Qt.rgba(244/255, 63/255, 94/255, 0.30) : Qt.rgba(244/255, 63/255, 94/255, 0.12)
                                    HoverHandler { id: leavePillH }
                                    AppIcon {
                                        anchors.centerIn: parent
                                        source: "../assets/icons/window-close-symbolic.svg"
                                        iconSize: 10
                                        color: "#fda4af"
                                    }
                                    ToolTip.visible: leavePillH.hovered
                                    ToolTip.text: I18n.tr("Rời phiên nghe cùng", "Leave Listen Along")
                                    ToolTip.delay: 350
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.exitListeningAlongRequested()
                                    }
                                }
                            }
                        }
                    }
                }

                // 4. Volume Button (Speaker Icon - click toggles Vertical Volume Popup)
                Item {
                    id: volumeButtonAnchor
                    width: 40; height: parent.height
                    z: 50
                    scale: volBtnHover.hovered ? 1.08 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120 } }

                    HoverHandler { id: volBtnHover }

                    AppIcon {
                        anchors.centerIn: parent
                        source: root.volume === 0 ? "../assets/icons/audio-volume-muted-symbolic.svg" : "../assets/icons/audio-volume-high-symbolic.svg"
                        iconSize: 20
                        color: root.isVolumePopupOpen ? root.accentColor : "#ffffff"
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.isVolumePopupOpen = !root.isVolumePopupOpen;
                        }
                        onWheel: wheel => {
                            var step = wheel.angleDelta.y > 0 ? 5 : -5;
                            root.reqVolumeChange(Math.max(0, Math.min(100, root.volume + step)));
                        }
                    }
                }

                // 5. Close Button [ ✕ ] (SimpMusic Close: clears current track & returns to empty playerbar)
                Item {
                    width: 40; height: parent.height
                    HoverHandler { id: closeH }
                    scale: closeH.hovered ? 1.08 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/window-close-symbolic.svg"
                        iconSize: 18
                        color: closeH.hovered ? "#ff5252" : "#ffffff"
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeClicked()
                    }
                }
            }
        }
    }

    // =========================================================================
    // Floating Chat Input Capsule (Danmaku Messenger Bar)
    // =========================================================================
    Rectangle {
        id: chatInputCapsule
        visible: root.isChatInputOpen && root.isCoListeningActive
        anchors.bottom: parent.top
        anchors.bottomMargin: 8
        anchors.right: parent.right
        anchors.rightMargin: 16
        width: 260
        height: 36
        radius: 18
        color: Qt.rgba(0.08, 0.08, 0.10, 0.95)
        border.color: root.accentColor
        border.width: 1
        z: 100

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 8
            spacing: 6

            AppIcon {
                source: "../assets/icons/chat-message-new-symbolic.svg"
                iconSize: 13
                color: root.accentColor
            }

            TextInput {
                id: chatTextInput
                Layout.fillWidth: true
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: "#ffffff"
                clip: true
                selectByMouse: true

                Text {
                    anchors.fill: parent
                    text: I18n.tr("Nhập tin nhắn bay...", "Send flying message...")
                    color: "#71717a"
                    font: parent.font
                    visible: !parent.text && !parent.activeFocus
                }

                onAccepted: {
                    if (text.trim() !== "") {
                        root.sendChatMessageRequested(text.trim());
                        text = "";
                        root.isChatInputOpen = false;
                    }
                }

                Keys.onEscapePressed: {
                    root.isChatInputOpen = false;
                }
            }

            // Send button
            Rectangle {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                radius: 11
                color: sendHover.hovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35) : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)

                HoverHandler { id: sendHover }

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/media-playback-start-symbolic.svg"
                    iconSize: 9
                    color: root.accentColor
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (chatTextInput.text.trim() !== "") {
                            root.sendChatMessageRequested(chatTextInput.text.trim());
                            chatTextInput.text = "";
                            root.isChatInputOpen = false;
                        }
                    }
                }
            }

            // Close button
            Rectangle {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                radius: 9
                color: "transparent"

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/window-close-symbolic.svg"
                    iconSize: 8
                    color: "#a1a1aa"
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.isChatInputOpen = false
                }
            }
        }
    }
}
