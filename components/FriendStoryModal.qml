import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import "."

Item {
    id: root
    anchors.fill: parent
    z: 9999
    visible: opacity > 0.001
    opacity: isOpen ? 1.0 : 0.0
    enabled: isOpen

    Behavior on opacity {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }

    property bool isOpen: false
    property var friendsNotes: []
    property int currentIndex: 0
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent
    property Item backgroundSourceItem: null

    signal listenAlongRequested(var friendData)
    signal playTrackRequested(var track)

    readonly property var currentFriend: (friendsNotes && friendsNotes.length > currentIndex && currentIndex >= 0) ? friendsNotes[currentIndex] : null
    readonly property var attachedTrack: (currentFriend && currentFriend.track) ? currentFriend.track : null
    readonly property string trackTitle: attachedTrack ? String(attachedTrack.title || attachedTrack.name || "").trim() : ""
    readonly property string trackArtist: attachedTrack ? String(attachedTrack.artist || "").trim() : ""

    readonly property bool isThisTrackPlaying: {
        if (!attachedTrack || typeof win === "undefined" || !win.isPlaying || !win.currentTrack) return false;
        var curId = win.currentTrack.videoId || win.currentTrack.id || "";
        var attId = attachedTrack.videoId || attachedTrack.id || "";
        if (curId && attId && curId === attId) return true;
        var curTitle = win.currentTrack.title || win.currentTrack.name || "";
        var attTitle = attachedTrack.title || attachedTrack.name || "";
        return curTitle && attTitle && curTitle === attTitle;
    }

    function openWithIndex(idx) {
        if (friendsNotes && idx >= 0 && idx < friendsNotes.length) {
            currentIndex = idx;
        } else {
            currentIndex = 0;
        }
        isOpen = true;
    }

    function openWithFriend(friend) {
        if (!friendsNotes || friendsNotes.length === 0) {
            friendsNotes = friend ? [friend] : [];
            currentIndex = 0;
        } else {
            var found = -1;
            for (var i = 0; i < friendsNotes.length; i++) {
                if (friendsNotes[i].user_email === friend.user_email) {
                    found = i;
                    break;
                }
            }
            if (found >= 0) currentIndex = found;
            else {
                friendsNotes.push(friend);
                currentIndex = friendsNotes.length - 1;
            }
        }
        isOpen = true;
    }

    function close() {
        isOpen = false;
    }

    function nextStory() {
        if (currentIndex < friendsNotes.length - 1) {
            currentIndex++;
        }
    }

    function prevStory() {
        if (currentIndex > 0) {
            currentIndex--;
        }
    }

    function formatTimeAgo(isoStr) {
        if (!isoStr || isoStr === 0 || isoStr === "0") return "";
        try {
            var d = new Date(isoStr);
            if (isNaN(d.getTime())) return "";
            var diffSec = Math.floor((Date.now() - d.getTime()) / 1000);
            if (diffSec < 60) return I18n.tr("Vừa xong", "Just now");
            var diffMin = Math.floor(diffSec / 60);
            if (diffMin < 60) return diffMin + I18n.tr(" phút trước", "m ago");
            var diffHours = Math.floor(diffMin / 60);
            if (diffHours < 24) return diffHours + I18n.tr(" giờ trước", "h ago");
            return Math.floor(diffHours / 24) + I18n.tr(" ngày trước", "d ago");
        } catch(e) {
            return I18n.tr("Hôm nay", "Today");
        }
    }

    // Dismiss Backdrop
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.58)

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    // Center Dialog Container with Carousel Nav Buttons
    Row {
        anchors.centerIn: parent
        spacing: 24

        // Left Navigation Arrow
        NavArrowButton {
            direction: "left"
            accentColor: root.accentColor
            btnSize: 38
            iconSize: 15
            canScroll: root.currentIndex > 0
            onClicked: root.prevStory()
        }

        // Center Container wrapping Dialog and Elevation Shadow
        Item {
            width: 420
            height: 480

            // Elevation: MultiEffect Drop Shadow behind Dialog
            Rectangle {
                id: shadowShape
                anchors.fill: parent
                radius: 20
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

            // Main Dialog Card: Keo 502 Optical Resin (LiquidGlass, 20px Radius)
            LiquidGlass {
                id: dialogCard
                anchors.fill: parent
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
                // HEADER: Friend Mini Avatar + Name (Left) & Close Button (Far Right)
                // ==========================================
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32

                    // Mini circular avatar + Friend info
                    RowLayout {
                        spacing: 10
                        Layout.alignment: Qt.AlignVCenter

                        RoundedImage {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            radius: 16
                            source: root.currentFriend ? (root.currentFriend.avatar_url || "") : ""
                            initialsText: root.currentFriend ? (root.currentFriend.user_name || "") : ""
                            fallbackIcon: "../assets/icons/contact-new-symbolic.svg"
                            fallbackIconColor: root.accentColor
                        }

                        ColumnLayout {
                            spacing: 1

                            Text {
                                text: root.currentFriend ? (root.currentFriend.user_name || I18n.tr("Bạn bè", "Friend")) : ""
                                color: Theme.textPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                text: {
                                    if (!root.currentFriend) return "";
                                    if (!friendBubbleContainer.hasNoteContent) {
                                        return (root.currentFriend.is_online)
                                            ? I18n.tr("Đang trực tuyến", "Online")
                                            : I18n.tr("Ngoại tuyến", "Offline");
                                    }
                                    return root.formatTimeAgo(root.currentFriend.created_at);
                                }
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
                            onClicked: root.close()
                        }
                    }
                }

                // ==========================================
                // CENTER: Thought Bubble + Soft Droplet Tail + Clean Avatar + Mini Play/Stop
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
                            id: friendBubbleContainer
                            readonly property bool hasNoteContent: {
                                if (!root.currentFriend) return false;
                                var txt = String(root.currentFriend.note_text || "").trim();
                                return txt.length > 0 || root.attachedTrack !== null;
                            }
                            visible: hasNoteContent
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: Math.max(160, Math.min(320, friendBubbleCol.implicitWidth + 36))
                            Layout.preferredHeight: hasNoteContent ? (friendBubbleBg.height + 10) : 0

                            // Seamless Droplet Tail (Rotated rounded square)
                            Rectangle {
                                id: friendBubbleTail
                                anchors.top: friendBubbleBg.bottom
                                anchors.topMargin: -6
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 14
                                height: 14
                                radius: 3
                                rotation: 45
                                color: friendBubbleBg.color
                                border.color: friendBubbleBg.border.color
                                border.width: 1
                                z: 1
                            }

                            // Thought Bubble Card (Dynamic Chromatic Salience - No dead grey)
                            Rectangle {
                                id: friendBubbleBg
                                anchors.top: parent.top
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width
                                height: friendBubbleCol.implicitHeight + 22
                                radius: 20
                                color: {
                                    var isPlaying = root.isThisTrackPlaying;
                                    if (isPlaying) {
                                        return friendBubbleMouse.containsMouse
                                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                                            : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22);
                                    } else {
                                        return friendBubbleMouse.containsMouse
                                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                                            : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10);
                                    }
                                }
                                border.color: {
                                    var isPlaying = root.isThisTrackPlaying;
                                    if (isPlaying) {
                                        return friendBubbleMouse.containsMouse
                                            ? root.accentColor
                                            : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.55);
                                    } else {
                                        return friendBubbleMouse.containsMouse
                                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                                            : Qt.rgba(255, 255, 255, 0.12);
                                    }
                                }
                                border.width: 1
                                z: 2

                                scale: friendBubbleMouse.containsMouse ? 1.02 : 1.0
                                Behavior on scale { NumberAnimation { duration: 150 } }
                                Behavior on color { ColorAnimation { duration: 250 } }
                                Behavior on border.color { ColorAnimation { duration: 200 } }

                                ColumnLayout {
                                    id: friendBubbleCol
                                    anchors.centerIn: parent
                                    width: parent.width - 24
                                    spacing: 5

                                    // Note Text
                                    Text {
                                        Layout.fillWidth: true
                                        visible: text.length > 0
                                        Layout.preferredHeight: text.length > 0 ? -1 : 0
                                        text: root.currentFriend ? String(root.currentFriend.note_text || "").trim() : ""
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
                                        Layout.fillWidth: true
                                        spacing: 2
                                        visible: root.attachedTrack !== null

                                        RowLayout {
                                            Layout.alignment: Qt.AlignHCenter
                                            spacing: 6

                                            // Audio Waveform Visualizer
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

                                            // Song Title
                                            Text {
                                                Layout.maximumWidth: friendBubbleCol.width - 24
                                                text: root.trackTitle
                                                color: "#ffffff"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 13
                                                font.bold: true
                                                elide: Text.ElideRight
                                                horizontalAlignment: Text.AlignHCenter
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
                                    id: friendBubbleMouse
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

                        // 2. CLEAN CIRCULAR FRIEND AVATAR (80x80, Single Ring, Zero Concentric Gaps)
                        RoundedImage {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 80
                            Layout.preferredHeight: 80
                            Layout.topMargin: friendBubbleContainer.hasNoteContent ? 6 : 0
                            radius: 40
                            source: root.currentFriend ? (root.currentFriend.avatar_url || "") : ""
                            initialsText: root.currentFriend ? (root.currentFriend.user_name || "") : ""
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
                                id: friendPlayStopCircle
                                anchors.centerIn: parent
                                width: 32; height: 32; radius: 16
                                color: {
                                    var isPlaying = root.isThisTrackPlaying;
                                    if (isPlaying) {
                                        return friendPlayStopMouse.containsMouse
                                            ? Qt.lighter(root.accentColor, 1.15)
                                            : root.accentColor;
                                    } else {
                                        return friendPlayStopMouse.containsMouse
                                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.40)
                                            : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22);
                                    }
                                }
                                border.color: root.isThisTrackPlaying
                                    ? Qt.rgba(255, 255, 255, 0.4)
                                    : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                                border.width: 1

                                scale: friendPlayStopMouse.containsMouse ? 1.08 : 1.0
                                Behavior on scale { NumberAnimation { duration: 120 } }
                                Behavior on color { ColorAnimation { duration: 150 } }

                                AppIcon {
                                    anchors.centerIn: parent
                                    source: root.isThisTrackPlaying ? "../assets/icons/media-playback-pause-symbolic.svg" : "../assets/icons/media-playback-start-symbolic.svg"
                                    iconSize: 12
                                    color: root.isThisTrackPlaying ? "#000000" : "#ffffff"
                                }

                                MouseArea {
                                    id: friendPlayStopMouse
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

                        // 4. FRIEND NAME
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 8
                            text: root.currentFriend ? (root.currentFriend.user_name || I18n.tr("Bạn bè", "Friend")) : ""
                            color: "#ffffff"
                            font.family: Theme.fontFamily
                            font.pixelSize: 17
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        // 5. SHARING SUBTEXT
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 4
                            text: friendBubbleContainer.hasNoteContent
                                ? I18n.tr("Đã chia sẻ với bạn bè", "Shared with friends")
                                : I18n.tr("Chưa đăng ghi chú nào", "No note posted yet")
                            color: Qt.rgba(1, 1, 1, 0.60)
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                    }
                }

                // ==========================================
                // FOOTER: [🎧 Nghe cùng bạn] LIVE LISTENING SECTION (Mặt phẳng, không bo con nhộng)
                // ==========================================
                Rectangle {
                    id: liveListenBtn
                    readonly property var liveTrack: {
                        if (!root.currentFriend) return null;
                        var np = root.currentFriend.now_playing;
                        if (!np) return null;
                        if (typeof np === "string") {
                            var trimmed = np.trim();
                            if (trimmed.startsWith("{")) {
                                try {
                                    var parsed = JSON.parse(trimmed);
                                    if (parsed && (parsed.title || parsed.name) && parsed.is_playing !== false) return parsed;
                                } catch(_) {}
                            }
                            return trimmed.length > 0 ? { title: trimmed, name: trimmed, is_playing: true } : null;
                        }
                        if (typeof np === "object") {
                            if ((np.title || np.name) && np.is_playing !== false) return np;
                        }
                        return null;
                    }
                    readonly property bool isLiveActive: liveTrack !== null && Boolean(root.currentFriend && root.currentFriend.is_online)
                    readonly property color btnAccent: (liveTrack && liveTrack.accent_color && String(liveTrack.accent_color).trim() !== "") ? liveTrack.accent_color : root.accentColor
                    visible: isLiveActive
                    Layout.fillWidth: true
                    Layout.preferredHeight: isLiveActive ? 52 : 0
                    radius: 12
                    color: liveListenMouse.containsMouse
                        ? Qt.rgba(btnAccent.r, btnAccent.g, btnAccent.b, 0.22)
                        : Qt.rgba(btnAccent.r, btnAccent.g, btnAccent.b, 0.08)
                    border.color: liveListenMouse.containsMouse
                        ? Qt.rgba(btnAccent.r, btnAccent.g, btnAccent.b, 0.50)
                        : Qt.rgba(btnAccent.r, btnAccent.g, btnAccent.b, 0.25)
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 12
                        spacing: 10

                        // 1. Track Avatar / Album Cover (Tái sử dụng RoundedImage chống vỡ góc)
                        RoundedImage {
                            Layout.preferredWidth: 38
                            Layout.preferredHeight: 38
                            radius: 8
                            source: {
                                var np = liveListenBtn.liveTrack;
                                if (np && (np.cover || np.image || np.thumbnail)) return np.cover || np.image || np.thumbnail;
                                var att = root.attachedTrack;
                                if (att && (att.cover || att.image || att.thumbnail)) return att.cover || att.image || att.thumbnail;
                                return "";
                            }
                            fallbackIcon: "../assets/icons/media-optical-audio-symbolic.svg"
                            fallbackIconColor: liveListenBtn.btnAccent
                            borderColor: Qt.rgba(liveListenBtn.btnAccent.r, liveListenBtn.btnAccent.g, liveListenBtn.btnAccent.b, 0.35)
                            borderWidth: 1.0
                            placeholderColor: Qt.rgba(liveListenBtn.btnAccent.r, liveListenBtn.btnAccent.g, liveListenBtn.btnAccent.b, 0.20)
                        }

                        // 2. Information: {{user}} đang nghe bài ... bấm vào để nghe cùng (Marquee cuộn vòng khi dài)
                        Item {
                            id: marqueeContainer
                            Layout.fillWidth: true
                            implicitHeight: marqueeText.implicitHeight
                            clip: true

                            Text {
                                id: marqueeText
                                text: {
                                    var uName = root.currentFriend ? (root.currentFriend.user_name || I18n.tr("Bạn bè", "Friend")) : I18n.tr("Bạn bè", "Friend");
                                    var sTitle = liveListenBtn.liveTrack ? (liveListenBtn.liveTrack.title || liveListenBtn.liveTrack.name || "") : (root.trackTitle || "");
                                    if (!sTitle) sTitle = I18n.tr("bài hát", "a track");
                                    return I18n.tr(uName + " đang nghe " + sTitle + " • Bấm vào để nghe cùng", uName + " is listening to " + sTitle + " • Click to listen along");
                                }
                                color: "#ffffff"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                x: 0

                                readonly property real overflowDist: Math.max(0, implicitWidth - marqueeContainer.width)
                                readonly property bool needsScroll: overflowDist > 6

                                SequentialAnimation {
                                    id: marqueeAnim
                                    running: marqueeText.needsScroll
                                    loops: Animation.Infinite

                                    PauseAnimation { duration: 1800 }
                                    NumberAnimation {
                                        target: marqueeText
                                        property: "x"
                                        to: -marqueeText.overflowDist
                                        duration: Math.max(1200, marqueeText.overflowDist * 28)
                                        easing.type: Easing.InOutQuad
                                    }
                                    PauseAnimation { duration: 1800 }
                                    NumberAnimation {
                                        target: marqueeText
                                        property: "x"
                                        to: 0
                                        duration: Math.max(1200, marqueeText.overflowDist * 28)
                                        easing.type: Easing.InOutQuad
                                    }
                                }

                                onNeedsScrollChanged: if (!needsScroll) x = 0
                                onTextChanged: x = 0
                            }
                        }

                        // 3. Play Icon Indicator
                        AppIcon {
                            source: "../assets/icons/media-playback-start-symbolic.svg"
                            iconSize: 14
                            color: liveListenMouse.containsMouse ? root.accentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.70)
                        }
                    }

                    MouseArea {
                        id: liveListenMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var f = root.currentFriend;
                            root.close();
                            if (f) {
                                root.listenAlongRequested(f);
                            }
                        }
                    }
                }
            }
        }
    }

        // Right Navigation Arrow
        NavArrowButton {
            direction: "right"
            accentColor: root.accentColor
            btnSize: 38
            iconSize: 15
            canScroll: root.currentIndex < (root.friendsNotes ? root.friendsNotes.length - 1 : 0)
            onClicked: root.nextStory()
        }
    }
}
