import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "."

Item {
    id: root
    implicitWidth: 600
    implicitHeight: 66
    height: 66

    property real radius: 16
    property Item backgroundSourceItem: null
    property var currentTrack: null
    property bool isPlaying: false
    property real currentTime: 0.0
    property real totalDuration: 1.0
    property real volume: 100.0
    property real prevVolume: 100.0
    property bool isShuffle: false
    property bool isRepeat: false
    property bool isLyricsActive: false
    property bool isNowPlayingOpen: false
    property bool isQueueActive: false
    property bool isScrubbingProgress: false
    property real scrubTime: 0.0
    property bool isScrubbingVolume: false
    property bool isLoadingAudio: false
    property bool isSleepTimerActive: false
    property var listeningAlongFriend: null
    property var activeCoListenersDetails: []
    property bool isChatInputOpen: false
    readonly property bool isCoListeningActive: (root.listeningAlongFriend !== null && root.listeningAlongFriend !== undefined) || (root.activeCoListenersDetails && root.activeCoListenersDetails.length > 0)
    property int sleepTimerRemainingSeconds: 0
    property color accentColor: "#deb06c"
    property string resolvedSquareImage: ""
    property bool squareFailed: false
    onResolvedSquareImageChanged: squareFailed = false
    onCurrentTrackChanged: squareFailed = false

    signal playPauseClicked()
    signal nextClicked()
    signal prevClicked()
    signal toggleShuffle()
    signal toggleRepeat()
    signal seekRequested(real seconds)
    signal reqVolumeChange(real newVol)
    signal openDetailsRequested()
    signal queueClicked()
    signal openArtistRequested(string artistName, string channelId)
    signal sleepTimerClicked()
    signal exitListeningAlongRequested()
    signal openCoListenersRequested(real targetX, real targetY)
    signal sendChatMessageRequested(string messageText)

    function fmtTime(sec) {
        if (!sec || sec < 0) return "0:00";
        var m = Math.floor(sec / 60);
        var s = Math.floor(sec % 60);
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    // Outer Ambient Glow & Soft Drop Shadow for Floating Capsule Elevation
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 3
        anchors.bottomMargin: -3
        radius: root.radius + 1
        color: Qt.rgba(0.0, 0.0, 0.0, 0.40)
        z: 0
    }

    // Liquid Glass Capsule Container (Apple Squircle & Snell Refraction with Dynamic Chromatic Rim)
    LiquidGlass {
        id: glassDock
        anchors.fill: parent
        radius: root.radius
        displacement: (typeof win !== "undefined" && win.liquidGlassDisplacement !== undefined) ? win.liquidGlassDisplacement : 22.0
        aberration: (typeof win !== "undefined" && win.liquidGlassAberration !== undefined) ? win.liquidGlassAberration : 0.040
        bevelWidth: (typeof win !== "undefined" && win.liquidGlassBevelWidth !== undefined) ? win.liquidGlassBevelWidth : 20.0
        blurRadius: (typeof win !== "undefined" && win.liquidGlassBlur !== undefined) ? win.liquidGlassBlur : 2.0
        colorBleed: (typeof win !== "undefined" && win.liquidGlassColorBleed !== undefined) ? win.liquidGlassColorBleed : 0.45
        tintColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
        backgroundSourceItem: root.backgroundSourceItem
        isFlowActive: root.isPlaying && root.currentTrack !== null
        z: 2

        // =====================================================================
        // 1. LEFT SECTION (Mini cover + Track title & artist)
        // =====================================================================
        RowLayout {
            id: leftSection
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: centerSection.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -2
            spacing: 10

            // Mini Cover Artwork (38x38)
            Item {
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38

                RoundedImage {
                    id: miniCover
                    anchors.fill: parent
                    radius: 8
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
                    sourceSize: Qt.size(80, 80)
                    fallbackIcon: "../assets/icons/folder-music-symbolic.svg"
                    fallbackIconSize: 18
                    onStatusChanged: {
                        if (status === Image.Error && root.resolvedSquareImage !== "" && !root.squareFailed) {
                            root.squareFailed = true;
                        }
                    }
                }

                // 1px Hairline Border
                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: "transparent"
                    border.color: miniCoverMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.40) : Qt.rgba(1.0, 1.0, 1.0, 0.16)
                    border.width: 1
                    z: 1
                    Behavior on border.color { ColorAnimation { duration: 120 } }
                }

                MouseArea {
                    id: miniCoverMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openDetailsRequested()
                }
            }

            // Track Title and Artist (with Ping-Pong Loop & Matching Colors)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                // Title Container with Ping-Pong Marquee Loop
                Item {
                    id: titleContainer
                    Layout.fillWidth: true
                    implicitHeight: titleText.implicitHeight
                    clip: true

                    Text {
                        id: titleText
                        text: root.currentTrack ? (root.currentTrack.title || root.currentTrack.name || "Nutsty Track") : "Nutsty Desktop"
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.bold: true
                        color: titleH.hovered ? "#ffffff" : Theme.textPrimary
                        x: 0

                        readonly property real overflowDist: Math.max(0, implicitWidth - titleContainer.width)
                        readonly property bool needsScroll: titleContainer.width > 0 && overflowDist > 6

                        SequentialAnimation {
                            id: titleAnim
                            running: titleText.needsScroll
                            loops: Animation.Infinite

                            PauseAnimation { duration: 1800 }
                            NumberAnimation {
                                target: titleText
                                property: "x"
                                to: -titleText.overflowDist
                                duration: Math.max(1200, titleText.overflowDist * 28)
                                easing.type: Easing.InOutQuad
                            }
                            PauseAnimation { duration: 1800 }
                            NumberAnimation {
                                target: titleText
                                property: "x"
                                to: 0
                                duration: Math.max(1200, titleText.overflowDist * 28)
                                easing.type: Easing.InOutQuad
                            }
                        }

                        onNeedsScrollChanged: if (!needsScroll) x = 0
                        onTextChanged: x = 0

                        HoverHandler { id: titleH }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openDetailsRequested()
                        }
                    }
                }

                // Artist Container with Ping-Pong Marquee Loop & Matching Color
                Item {
                    id: artistContainer
                    Layout.fillWidth: true
                    implicitHeight: artistLabel.implicitHeight
                    clip: true

                    Text {
                        id: artistLabel
                        text: {
                            if (!root.currentTrack) return I18n.tr("Sẵn sàng phát", "Ready to play");
                            var raw = String(root.currentTrack.artist || "").trim();
                            var clean = raw.split(/\s*•\s*/)[0].replace(/\s*\d+([.,]\d+)?[KMBkmb]?\s*(views|plays|lượt xem|lượt nghe).*/i, "").trim();
                            return clean || raw || "Nutsty Desktop";
                        }
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        // User explicitly requested: "tên nghệ sĩ cùng màu với tên bài hát"
                        color: (root.currentTrack && artistMouse.containsMouse) ? root.accentColor : Theme.textPrimary
                        x: 0

                        readonly property real overflowDist: Math.max(0, implicitWidth - artistContainer.width)
                        readonly property bool needsScroll: artistContainer.width > 0 && overflowDist > 6

                        SequentialAnimation {
                            id: artistAnim
                            running: artistLabel.needsScroll
                            loops: Animation.Infinite

                            PauseAnimation { duration: 2000 }
                            NumberAnimation {
                                target: artistLabel
                                property: "x"
                                to: -artistLabel.overflowDist
                                duration: Math.max(1200, artistLabel.overflowDist * 28)
                                easing.type: Easing.InOutQuad
                            }
                            PauseAnimation { duration: 2000 }
                            NumberAnimation {
                                target: artistLabel
                                property: "x"
                                to: 0
                                duration: Math.max(1200, artistLabel.overflowDist * 28)
                                easing.type: Easing.InOutQuad
                            }
                        }

                        onNeedsScrollChanged: if (!needsScroll) x = 0
                        onTextChanged: x = 0

                        MouseArea {
                            id: artistMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: root.currentTrack ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (root.currentTrack && root.currentTrack.artist) {
                                    root.openArtistRequested(artistLabel.text, root.currentTrack.channelId || "");
                                }
                            }
                        }
                    }
                }
            }
        }

        // =====================================================================
        // 2. CENTER SECTION (Playback Controls)
        // =====================================================================
        Row {
            id: centerSection
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -2
            spacing: 8

            // --- Shuffle Button ---
            Item {
                width: 28; height: 28
                anchors.verticalCenter: parent.verticalCenter
                HoverHandler { id: shufHover }

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/media-playlist-shuffle-symbolic.svg"
                    iconSize: 15
                    color: root.isShuffle ? root.accentColor : (shufHover.hovered ? "#ffffff" : "#b3b3b3")
                }

                Rectangle {
                    width: 3; height: 3; radius: 1.5
                    color: root.accentColor
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.isShuffle
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleShuffle()
                }
            }

            // --- Prev Button ---
            Item {
                width: 30; height: 30
                anchors.verticalCenter: parent.verticalCenter
                opacity: root.currentTrack ? 1.0 : 0.4
                Behavior on opacity { NumberAnimation { duration: 150 } }
                HoverHandler { id: prevHover; enabled: !!root.currentTrack }

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/media-skip-backward-symbolic.svg"
                    iconSize: 17
                    color: prevHover.hovered ? "#ffffff" : "#b3b3b3"
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !!root.currentTrack
                    cursorShape: root.currentTrack ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.prevClicked()
                }
            }

            // --- Play / Pause Button (Dynamic Keo 502 Accent Circle) ---
            Rectangle {
                id: playPauseBtn
                width: 36
                height: 36
                radius: 18
                anchors.verticalCenter: parent.verticalCenter
                opacity: root.currentTrack ? 1.0 : 0.65
                Behavior on opacity { NumberAnimation { duration: 150 } }

                readonly property bool isLightAccent: (root.accentColor.r * 0.299 + root.accentColor.g * 0.587 + root.accentColor.b * 0.114) > 0.55
                readonly property color contrastColor: isLightAccent ? "#0c0d10" : "#ffffff"

                color: (playHover.hovered && root.currentTrack) ? Qt.lighter(root.accentColor, 1.15) : root.accentColor
                scale: (playHover.hovered && root.currentTrack) ? 1.06 : 1.0
                Behavior on scale { NumberAnimation { duration: 100 } }
                Behavior on color { ColorAnimation { duration: 250 } }
                HoverHandler { id: playHover; enabled: !!root.currentTrack }

                // Playback Glow Ring
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -2
                    radius: parent.radius + 2
                    color: "transparent"
                    border.width: 1.5
                    border.color: root.isPlaying ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45) : "transparent"
                    visible: root.isPlaying && !!root.currentTrack
                    Behavior on border.color { ColorAnimation { duration: 250 } }
                }

                CircularSpinner {
                    anchors.centerIn: parent
                    size: 18
                    strokeWidth: 2.2
                    color: playPauseBtn.contrastColor
                    visible: root.isLoadingAudio
                }

                AppIcon {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: (!root.isPlaying && !root.isLoadingAudio) ? 1.5 : 0
                    source: root.isPlaying ? "../assets/icons/media-playback-pause-symbolic.svg" : "../assets/icons/media-playback-start-symbolic.svg"
                    iconSize: 17
                    color: playPauseBtn.contrastColor
                    visible: !root.isLoadingAudio
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !!root.currentTrack
                    cursorShape: root.currentTrack ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.playPauseClicked()
                }
            }

            // --- Next Button ---
            Item {
                width: 30; height: 30
                anchors.verticalCenter: parent.verticalCenter
                opacity: root.currentTrack ? 1.0 : 0.4
                Behavior on opacity { NumberAnimation { duration: 150 } }
                HoverHandler { id: nextHover; enabled: !!root.currentTrack }

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/media-skip-forward-symbolic.svg"
                    iconSize: 17
                    color: nextHover.hovered ? "#ffffff" : "#b3b3b3"
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !!root.currentTrack
                    cursorShape: root.currentTrack ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.nextClicked()
                }
            }

            // --- Repeat Button ---
            Item {
                width: 28; height: 28
                anchors.verticalCenter: parent.verticalCenter
                HoverHandler { id: repHover }

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/media-playlist-repeat-symbolic.svg"
                    iconSize: 15
                    color: root.isRepeat ? root.accentColor : (repHover.hovered ? "#ffffff" : "#b3b3b3")
                }

                Rectangle {
                    width: 3; height: 3; radius: 1.5
                    color: root.accentColor
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.isRepeat
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleRepeat()
                }
            }
        }

        // =====================================================================
        // 3. RIGHT SECTION (Queue, Volume - Zero MIC, Minimalist Clean)
        // =====================================================================
        Row {
            id: rightSection
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.left: centerSection.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -2
            spacing: 8
            layoutDirection: Qt.RightToLeft

            // Volume Section (Slider + Speaker Icon)
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                layoutDirection: Qt.LeftToRight

                Item {
                    width: 26; height: 26
                    anchors.verticalCenter: parent.verticalCenter
                    HoverHandler { id: volIconH }

                    AppIcon {
                        anchors.centerIn: parent
                        source: root.volume === 0 ? "../assets/icons/audio-volume-muted-symbolic.svg" : "../assets/icons/audio-volume-high-symbolic.svg"
                        iconSize: 16
                        color: volIconH.hovered ? "#ffffff" : "#b3b3b3"
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.volume > 0) {
                                root.prevVolume = root.volume;
                                root.reqVolumeChange(0);
                            } else {
                                root.reqVolumeChange(root.prevVolume > 0 ? root.prevVolume : 100);
                            }
                        }
                    }
                }

                // Volume Bar
                Item {
                    id: volSlider
                    width: root.isCoListeningActive ? 42 : 52
                    height: 18
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: volMouse.containsMouse || root.isScrubbingVolume ? 4 : 2.5
                        radius: height / 2
                        color: Qt.rgba(1, 1, 1, 0.20)
                        Behavior on height { NumberAnimation { duration: 120 } }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: Math.max(0, parent.width * (root.volume / 100.0))
                            radius: parent.radius
                            color: volMouse.containsMouse || root.isScrubbingVolume ? root.accentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.85)
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        Rectangle {
                            width: 7; height: 7; radius: 3.5
                            color: root.accentColor
                            border.color: "#ffffff"
                            border.width: 1
                            anchors.verticalCenter: parent.verticalCenter
                            x: Math.min(parent.width - width, Math.max(0, parent.width * (root.volume / 100.0) - width / 2))
                            opacity: volMouse.containsMouse || root.isScrubbingVolume ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }
                    }

                    MouseArea {
                        id: volMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        function updateVolPos(mouseX) {
                            var frac = Math.max(0.0, Math.min(1.0, mouseX / width));
                            var newVol = Math.round(frac * 100);
                            if (newVol !== root.volume) {
                                root.reqVolumeChange(newVol);
                            }
                        }

                        onPressed: mouse => {
                            root.isScrubbingVolume = true;
                            updateVolPos(mouse.x);
                        }
                        onPositionChanged: mouse => {
                            if (root.isScrubbingVolume) updateVolPos(mouse.x);
                        }
                        onReleased: mouse => {
                            if (root.isScrubbingVolume) {
                                updateVolPos(mouse.x);
                                root.isScrubbingVolume = false;
                            }
                        }
                        onCanceled: root.isScrubbingVolume = false
                    }
                }
            }

            // Sleep Timer Button [ 🌙 ]
            Item {
                width: 28; height: 28
                anchors.verticalCenter: parent.verticalCenter
                HoverHandler { id: sleepH }

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/sleep-timer-symbolic.svg"
                    iconSize: 15
                    color: root.isSleepTimerActive ? root.accentColor : (sleepH.hovered ? "#ffffff" : "#b3b3b3")
                }

                // Glowing indicator dot when active
                Rectangle {
                    width: 3; height: 3; radius: 1.5
                    color: root.accentColor
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.isSleepTimerActive
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sleepTimerClicked()
                }
            }

            // Now Playing Expand / Collapse Chevron Button [ ∨ / ∧ ] (YouTube Music Style)
            Item {
                width: 28; height: 28
                anchors.verticalCenter: parent.verticalCenter
                HoverHandler { id: chevronH }

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/go-previous-symbolic.svg"
                    iconSize: 14
                    rotation: root.isNowPlayingOpen ? -90 : 90
                    Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }
                    color: root.isNowPlayingOpen ? root.accentColor : (chevronH.hovered ? "#ffffff" : "#b3b3b3")
                }

                Rectangle {
                    width: 3; height: 3; radius: 1.5
                    color: root.accentColor
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.isNowPlayingOpen
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openDetailsRequested()
                }
            }

            // --- Co-Listening Section (Listener: Host Avatar + [✕] | Host: Overlapping Avatars + Live Pulse | Mini Chat Button) ---
            Row {
                id: coListenRow
                visible: root.isCoListeningActive
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                layoutDirection: Qt.LeftToRight

                // Mini Chat Button [ 💬 ]
                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.isChatInputOpen ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25) : (chatBtnHover.hovered ? Qt.rgba(1, 1, 1, 0.12) : "transparent")
                    border.color: root.isChatInputOpen ? root.accentColor : (chatBtnHover.hovered ? Qt.rgba(1, 1, 1, 0.20) : "transparent")
                    border.width: 1

                    HoverHandler { id: chatBtnHover }

                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/chat-message-new-symbolic.svg"
                        iconSize: 12
                        color: root.isChatInputOpen ? root.accentColor : (chatBtnHover.hovered ? "#ffffff" : "#b3b3b3")
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.isChatInputOpen = !root.isChatInputOpen;
                            if (root.isChatInputOpen) chatTextInput.forceActiveFocus();
                        }
                    }
                }

                // 1. Phía Listener: 1 Host Avatar tròn 24px + Chấm xanh Live Pulse + Nút icon [✕] nhỏ gọn 18px Muted Rose
                Row {
                    id: listenerPill
                    visible: root.listeningAlongFriend !== null && root.listeningAlongFriend !== undefined
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Item {
                        width: 24
                        height: 24
                        anchors.verticalCenter: parent.verticalCenter

                        RoundedImage {
                            anchors.fill: parent
                            radius: 12
                            borderColor: root.accentColor
                            borderWidth: 1.5
                            source: root.listeningAlongFriend ? (root.listeningAlongFriend.avatar_url || root.listeningAlongFriend.avatar || "") : ""
                            fallbackIcon: "../assets/icons/preferences-system-symbolic.svg"
                            placeholderColor: "#27272a"
                        }
                    }

                    // Leave Button [✕] nhỏ gọn 18px Muted Rose
                    Rectangle {
                        width: 18
                        height: 18
                        radius: 9
                        anchors.verticalCenter: parent.verticalCenter
                        color: exitMouse.containsMouse ? Qt.rgba(244/255, 63/255, 94/255, 0.30) : Qt.rgba(244/255, 63/255, 94/255, 0.16)
                        border.color: Qt.rgba(244/255, 63/255, 94/255, 0.40)
                        border.width: 1

                        AppIcon {
                            anchors.centerIn: parent
                            source: "../assets/icons/window-close-symbolic.svg"
                            iconSize: 8
                            color: "#fda4af"
                        }

                        MouseArea {
                            id: exitMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.exitListeningAlongRequested()
                        }
                    }
                }

                // 2. Phía Host: Cụm Overlapping Avatars tròn 24px xếp chồng so le (-8px offset) + Chấm Live Pulse
                Item {
                    id: hostAvatarsCluster
                    visible: !root.listeningAlongFriend && root.activeCoListenersDetails && root.activeCoListenersDetails.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    property int count: root.activeCoListenersDetails ? root.activeCoListenersDetails.length : 0
                    width: count <= 1 ? 24 : (count === 2 ? 40 : 58)
                    height: 24

                    // Avatar 1
                    RoundedImage {
                        x: 0
                        width: 24; height: 24; radius: 12
                        borderColor: root.accentColor
                        borderWidth: 1.5
                        source: (hostAvatarsCluster.count > 0 && root.activeCoListenersDetails[0]) ? (root.activeCoListenersDetails[0].avatar || "") : ""
                        fallbackIcon: "../assets/icons/preferences-system-symbolic.svg"
                        placeholderColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                        visible: hostAvatarsCluster.count > 0
                    }

                    // Avatar 2 (Overlapping with -8px offset -> x = 16)
                    RoundedImage {
                        x: 16
                        width: 24; height: 24; radius: 12
                        borderColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.85)
                        borderWidth: 1.5
                        source: (hostAvatarsCluster.count > 1 && root.activeCoListenersDetails[1]) ? (root.activeCoListenersDetails[1].avatar || "") : ""
                        fallbackIcon: "../assets/icons/preferences-system-symbolic.svg"
                        placeholderColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                        visible: hostAvatarsCluster.count > 1
                    }

                    // Badge +N (if count > 2)
                    Rectangle {
                        x: 34
                        width: 22; height: 22; radius: 11
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(root.accentColor.r * 0.3, root.accentColor.g * 0.3, root.accentColor.b * 0.3, 0.90)
                        border.color: root.accentColor
                        border.width: 1.5
                        visible: hostAvatarsCluster.count > 2

                        Text {
                            anchors.centerIn: parent
                            text: "+" + (hostAvatarsCluster.count - 2)
                            color: "#ffffff"
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.Bold
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var pt = hostAvatarsCluster.mapToItem(null, hostAvatarsCluster.width / 2, 0);
                            root.openCoListenersRequested(pt.x, pt.y);
                        }
                    }
                }
            }
        }

        // =====================================================================
        // Floating Chat Input Capsule (Danmaku Messenger Bar)
        // =====================================================================
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

        // =====================================================================
        // 4. SLIM PROGRESS BAR AT BOTTOM EDGE (Emerald Green, Scrubbing & Time Tooltip)
        // =====================================================================
        Item {
            id: progressBarContainer
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            anchors.left: parent.left
            anchors.leftMargin: 24
            anchors.right: parent.right
            anchors.rightMargin: 24
            height: 10
            z: 20

            property real progressFraction: {
                if (root.isScrubbingProgress) {
                    return root.totalDuration > 0 ? (root.scrubTime / root.totalDuration) : 0.0;
                }
                return (root.totalDuration > 0) ? Math.min(1.0, Math.max(0.0, root.currentTime / root.totalDuration)) : 0.0;
            }

            // Time Tooltip Bubble (Visible on Hover / Scrubbing)
            Rectangle {
                anchors.bottom: parent.top
                anchors.bottomMargin: 4
                x: Math.min(parent.width - width, Math.max(0, parent.width * progressBarContainer.progressFraction - width / 2))
                width: timeLabelText.implicitWidth + 12
                height: 18
                radius: 9
                color: Qt.rgba(0.08, 0.09, 0.12, 0.88)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.22)
                visible: progressMouse.containsMouse || root.isScrubbingProgress
                opacity: visible ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 120 } }

                Text {
                    id: timeLabelText
                    anchors.centerIn: parent
                    text: root.fmtTime(root.isScrubbingProgress ? root.scrubTime : root.currentTime) + " / " + root.fmtTime(root.totalDuration)
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    color: "#ffffff"
                }
            }

            Rectangle {
                id: progressBg
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                height: progressMouse.containsMouse || root.isScrubbingProgress ? 3.5 : 2.0
                radius: height / 2
                color: "transparent"
                Behavior on height { NumberAnimation { duration: 120 } }

                // Dynamic Accent Elapsed Fill
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Math.max(0, parent.width * progressBarContainer.progressFraction)
                    radius: parent.radius
                    color: root.accentColor
                    Behavior on color { ColorAnimation { duration: 250 } }
                }

                // Scrub Handle Dot
                Rectangle {
                    width: 7; height: 7; radius: 3.5
                    color: root.accentColor
                    border.color: "#ffffff"
                    border.width: 1
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.min(parent.width - width, Math.max(0, parent.width * progressBarContainer.progressFraction - width / 2))
                    opacity: progressMouse.containsMouse || root.isScrubbingProgress ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
            }

            MouseArea {
                id: progressMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !!root.currentTrack && root.totalDuration > 0

                function updateScrubPos(mouseX) {
                    var frac = Math.max(0.0, Math.min(1.0, mouseX / width));
                    root.scrubTime = frac * root.totalDuration;
                }

                onPressed: mouse => {
                    root.isScrubbingProgress = true;
                    updateScrubPos(mouse.x);
                }
                onPositionChanged: mouse => {
                    if (root.isScrubbingProgress) updateScrubPos(mouse.x);
                }
                onReleased: mouse => {
                    if (root.isScrubbingProgress) {
                        updateScrubPos(mouse.x);
                        root.seekRequested(root.scrubTime);
                        root.isScrubbingProgress = false;
                    }
                }
                onCanceled: root.isScrubbingProgress = false
            }
        }
    }
}
