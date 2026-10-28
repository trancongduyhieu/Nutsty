import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import Quickshell.Io
import "."

Item {
    id: root
    width: parent ? parent.width : 800
    height: 130
    implicitHeight: 130
    Layout.fillWidth: true
    Layout.preferredHeight: height

    property var friendsNotes: []
    property color accentColor: Theme.accent
    property var myLatestNote: null
    property var currentTrack: null
    property bool isPlaying: false
    property string userAvatar: ""
    property string userName: ""

    property color userTrackExtractedAccent: "transparent"
    property string lastExtractedUserTrackCover: ""

    Process {
        id: userTrackPaletteProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (!data || data.trim() === "") return;
                try {
                    var parsed = JSON.parse(data);
                    if (parsed && parsed.highlightColor) {
                        root.userTrackExtractedAccent = parsed.highlightColor;
                    }
                } catch(e) {}
            }
        }
    }

    function checkAndExtractUserTrackCover() {
        if (!userNoteItem.effectiveTrack) {
            userTrackExtractedAccent = "transparent";
            lastExtractedUserTrackCover = "";
            return;
        }
        var trk = userNoteItem.effectiveTrack;
        if (trk.accent_color && String(trk.accent_color).trim() !== "") {
            userTrackExtractedAccent = trk.accent_color;
            return;
        }
        if (typeof win !== "undefined" && win.currentTrack && win.isSameTrack(trk, win.currentTrack) && win.songAccentColor && win.songAccentColor !== win.wallpaperAccentColor) {
            userTrackExtractedAccent = win.songAccentColor;
            return;
        }
        var cov = trk.cover || trk.image || trk.thumbnail || trk.artUrl || "";
        if (cov && typeof cov === "string" && cov.trim() !== "" && cov !== lastExtractedUserTrackCover) {
            lastExtractedUserTrackCover = cov;
            var appDir = (typeof win !== "undefined" && win.appDir) ? win.appDir : (Quickshell.env("NUTSTY_APP_DIR") || (Quickshell.env("HOME") + "/Applications/FrostifyLocal"));
            userTrackPaletteProc.running = false;
            userTrackPaletteProc.command = [
                "python3", "-u",
                appDir + "/backend/palette_extractor.py",
                "song_palette",
                cov
            ];
            userTrackPaletteProc.running = true;
        }
    }

    signal postNoteClicked()
    signal userNoteDetailClicked()
    signal addFriendClicked()
    signal openStoryRequested(var friendData, int index)
    signal playTrackRequested(var track)

    function openFriendNote(idx) {
        if (root.friendsNotes && idx >= 0 && idx < root.friendsNotes.length) {
            root.openStoryRequested(root.friendsNotes[idx], idx);
        }
    }

    // Scroll Left Arrow Button
    NavArrowButton {
        id: leftNavBtn
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        z: 10
        direction: "left"
        accentColor: root.accentColor
        visible: friendsFlickable.contentWidth > friendsFlickable.width && friendsFlickable.contentX > 8
        canScroll: friendsFlickable.contentX > 0
        onClicked: {
            var targetX = Math.max(0, friendsFlickable.contentX - 220);
            scrollAnim.to = targetX;
            scrollAnim.restart();
        }
    }

    // Scroll Right Arrow Button
    NavArrowButton {
        id: rightNavBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        z: 10
        direction: "right"
        accentColor: root.accentColor
        visible: friendsFlickable.contentWidth > friendsFlickable.width && friendsFlickable.contentX < (friendsFlickable.contentWidth - friendsFlickable.width - 8)
        canScroll: friendsFlickable.contentX < (friendsFlickable.contentWidth - friendsFlickable.width)
        onClicked: {
            var maxScroll = Math.max(0, friendsFlickable.contentWidth - friendsFlickable.width);
            var targetX = Math.min(maxScroll, friendsFlickable.contentX + 220);
            scrollAnim.to = targetX;
            scrollAnim.restart();
        }
    }

    NumberAnimation {
        id: scrollAnim
        target: friendsFlickable
        property: "contentX"
        duration: 220
        easing.type: Easing.OutCubic
    }

    // Horizontal Scrollable Container
    Flickable {
        id: friendsFlickable
        anchors.fill: parent
        anchors.leftMargin: leftNavBtn.visible ? 36 : 0
        anchors.rightMargin: rightNavBtn.visible ? 36 : 0
        contentWidth: itemsRow.width + 16
        contentHeight: height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick

        Behavior on anchors.leftMargin { NumberAnimation { duration: 150 } }
        Behavior on anchors.rightMargin { NumberAnimation { duration: 150 } }

        // Desktop Linux Mouse Wheel Handler (Captures Vertical Wheel Delta Y to Scroll Horizontally)
        WheelHandler {
            target: friendsFlickable
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                var delta = (event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x);
                var maxScroll = Math.max(0, friendsFlickable.contentWidth - friendsFlickable.width);
                friendsFlickable.contentX = Math.max(0, Math.min(maxScroll, friendsFlickable.contentX - delta * 1.2));
            }
        }

        // Touchpad / Mouse Drag Handler
        DragHandler {
            target: null
            grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType
            property real startContentX: 0
            onActiveChanged: {
                if (active) startContentX = friendsFlickable.contentX;
            }
            onTranslationChanged: {
                if (active) {
                    var maxScroll = Math.max(0, friendsFlickable.contentWidth - friendsFlickable.width);
                    friendsFlickable.contentX = Math.max(0, Math.min(maxScroll, startContentX - translation.x));
                }
            }
        }

        Row {
            id: itemsRow
            x: 8
            height: parent.height
            spacing: 12

            // ==========================================
            // ITEM 0: CURRENT USER NOTE / POST NOTE (Messenger Pattern - Ảnh 2)
            // ==========================================
            Item {
                id: userNoteItem
                property string noteStr: root.myLatestNote ? String(root.myLatestNote.note_text || "").replace(/[\r\n]+/g, " ").trim() : I18n.tr("Chia sẻ suy nghĩ...", "Share a thought...")
                property var effectiveTrack: (root.myLatestNote && root.myLatestNote.track && (root.myLatestNote.track.title || root.myLatestNote.track.name || root.myLatestNote.track.id)) ? root.myLatestNote.track : null
                property string trackStr: effectiveTrack ? String(effectiveTrack.title || effectiveTrack.name || "").trim() : ""
                property bool hasTrack: trackStr.length > 0
                property bool isNoteTextEmpty: root.myLatestNote ? (String(root.myLatestNote.note_text || "").trim().length === 0) : false
                property bool isTrackOnly: root.myLatestNote !== null && isNoteTextEmpty && hasTrack

                property var userNowPlayingObj: {
                    if (!root.myLatestNote || !root.myLatestNote.now_playing) return null;
                    var np = root.myLatestNote.now_playing;
                    if (typeof np === "object") return np;
                    if (typeof np === "string" && np.trim().startsWith("{")) {
                        try { return JSON.parse(np); } catch(e) { return null; }
                    }
                    return null;
                }

                onEffectiveTrackChanged: root.checkAndExtractUserTrackCover()
                Component.onCompleted: root.checkAndExtractUserTrackCover()

                readonly property color userSongAccent: {
                    if (effectiveTrack && effectiveTrack.accent_color && String(effectiveTrack.accent_color).trim() !== "") {
                        return effectiveTrack.accent_color;
                    }
                    if (root.userTrackExtractedAccent && root.userTrackExtractedAccent !== "transparent" && String(root.userTrackExtractedAccent) !== "#00000000") {
                        return root.userTrackExtractedAccent;
                    }
                    if (root.myLatestNote && root.myLatestNote.accent_color && String(root.myLatestNote.accent_color).trim() !== "") {
                        return root.myLatestNote.accent_color;
                    }
                    if (userNowPlayingObj && typeof userNowPlayingObj === "object" && userNowPlayingObj.accent_color && String(userNowPlayingObj.accent_color).trim() !== "") {
                        return userNowPlayingObj.accent_color;
                    }
                    if (typeof win !== "undefined" && win.currentTrack && win.songAccentColor && win.songAccentColor !== win.wallpaperAccentColor) {
                        return win.songAccentColor;
                    }
                    return root.accentColor;
                }
                readonly property bool hasCustomUserAccent: Boolean((effectiveTrack && effectiveTrack.accent_color)
                    || (root.userTrackExtractedAccent && root.userTrackExtractedAccent !== "transparent" && String(root.userTrackExtractedAccent) !== "#00000000")
                    || (root.myLatestNote && root.myLatestNote.accent_color)
                    || (userNowPlayingObj && typeof userNowPlayingObj === "object" && userNowPlayingObj.accent_color)
                    || (typeof win !== "undefined" && win.currentTrack && win.songAccentColor && win.songAccentColor !== win.wallpaperAccentColor))
                readonly property color effectiveUserNoteAccent: hasCustomUserAccent ? userSongAccent : root.accentColor

                width: 80
                height: friendsFlickable.height

                // Mini Thought Bubble above user avatar (Messenger Compact: 80px width, 2-line wrap, z: 10 layer trên)
                Rectangle {
                    id: userBubbleBox
                    anchors.bottom: userAvatarWrapper.top
                    anchors.bottomMargin: 6
                    anchors.horizontalCenter: userAvatarWrapper.horizontalCenter
                    z: 10
                    width: 80
                    height: userNoteItem.isTrackOnly ? 24 : Math.max(24, Math.min(48, userBubbleCol.implicitHeight + 8))
                    radius: userNoteItem.isTrackOnly ? 12 : Math.min(14, height / 2)
                    color: userMouseArea.containsMouse
                        ? Qt.rgba(userNoteItem.effectiveUserNoteAccent.r, userNoteItem.effectiveUserNoteAccent.g, userNoteItem.effectiveUserNoteAccent.b, 0.28)
                        : (root.myLatestNote ? Qt.rgba(userNoteItem.effectiveUserNoteAccent.r, userNoteItem.effectiveUserNoteAccent.g, userNoteItem.effectiveUserNoteAccent.b, 0.18) : Qt.rgba(1, 1, 1, 0.06))
                    border.color: userMouseArea.containsMouse
                        ? userNoteItem.effectiveUserNoteAccent
                        : (root.myLatestNote ? Qt.rgba(userNoteItem.effectiveUserNoteAccent.r, userNoteItem.effectiveUserNoteAccent.g, userNoteItem.effectiveUserNoteAccent.b, 0.45) : Qt.rgba(1, 1, 1, 0.16))
                    border.width: 1
                    scale: userMouseArea.containsMouse ? 1.05 : 1.0
                    Behavior on scale { NumberAnimation { duration: 150 } }
                    Behavior on color { ColorAnimation { duration: 250 } }
                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    // Connector Dot 1 (top dot)
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.bottom
                        anchors.topMargin: 1
                        width: 5; height: 5; radius: 2.5
                        color: userBubbleBox.color
                        border.color: userBubbleBox.border.color
                        border.width: 0.5
                        z: 10
                    }

                    // Connector Dot 2 (bottom dot, closer to avatar)
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.bottom
                        anchors.topMargin: 5
                        width: 3.5; height: 3.5; radius: 1.75
                        color: userBubbleBox.color
                        border.color: userBubbleBox.border.color
                        border.width: 0.5
                        z: 10
                    }

                    ColumnLayout {
                        id: userBubbleCol
                        anchors.centerIn: parent
                        width: parent.width - 8
                        spacing: 1

                        // Line 1 & 2: Note Text with 2-line wrapping
                        Text {
                            id: userBubbleText
                            Layout.fillWidth: true
                            visible: userNoteItem.noteStr.length > 0 && !userNoteItem.isTrackOnly
                            text: userNoteItem.noteStr
                            color: root.myLatestNote ? "#ffffff" : Qt.rgba(1, 1, 1, 0.65)
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.bold: root.myLatestNote !== null
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            lineHeight: 1.05
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }

                        // Line 2 (or 3): Attached / Currently Playing Track (sóng âm visualizer)
                        RowLayout {
                            id: userTrackRow
                            Layout.fillWidth: true
                            spacing: 3
                            visible: userNoteItem.hasTrack
                            Layout.alignment: Qt.AlignHCenter

                            // Audio Waveform Visualizer (Sóng âm 3 cột chuyển động)
                            Row {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1.5
                                height: 8

                                Rectangle {
                                    width: 1.8; height: 5; radius: 0.9
                                    color: userNoteItem.effectiveUserNoteAccent
                                    anchors.bottom: parent.bottom
                                    SequentialAnimation on height {
                                        running: userNoteItem.hasTrack
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 8; duration: 340; easing.type: Easing.InOutQuad }
                                        NumberAnimation { to: 3; duration: 340; easing.type: Easing.InOutQuad }
                                    }
                                }
                                Rectangle {
                                    width: 1.8; height: 8; radius: 0.9
                                    color: userNoteItem.effectiveUserNoteAccent
                                    anchors.bottom: parent.bottom
                                    SequentialAnimation on height {
                                        running: userNoteItem.hasTrack
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 3.5; duration: 260; easing.type: Easing.InOutQuad }
                                        NumberAnimation { to: 8; duration: 260; easing.type: Easing.InOutQuad }
                                    }
                                }
                                Rectangle {
                                    width: 1.8; height: 6; radius: 0.9
                                    color: userNoteItem.effectiveUserNoteAccent
                                    anchors.bottom: parent.bottom
                                    SequentialAnimation on height {
                                        running: userNoteItem.hasTrack
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 7.5; duration: 400; easing.type: Easing.InOutQuad }
                                        NumberAnimation { to: 2.5; duration: 400; easing.type: Easing.InOutQuad }
                                    }
                                }
                            }

                            Text {
                                id: userTrackText
                                Layout.fillWidth: true
                                text: userNoteItem.trackStr
                                color: userNoteItem.effectiveUserNoteAccent
                                font.family: Theme.fontFamily
                                font.pixelSize: 8
                                font.bold: true
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }

                // User Circular Avatar Wrapper (48x48, z: 1 so bubble at z: 10 is on top)
                Item {
                    id: userAvatarWrapper
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 18
                    anchors.horizontalCenter: parent.horizontalCenter
                    z: 1
                    width: 48; height: 48
                    scale: userMouseArea.containsMouse ? 1.08 : 1.0
                    Behavior on scale { NumberAnimation { duration: 150 } }

                    // Outer Border / Pulse Ring if track is attached
                    Rectangle {
                        anchors.fill: parent
                        radius: 24
                        color: "transparent"
                        border.color: userMouseArea.containsMouse
                            ? root.accentColor
                            : (root.myLatestNote ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.55) : Qt.rgba(1, 1, 1, 0.16))
                        border.width: 1.5
                    }

                    // User Avatar with Hardware SDF Circle Masking (Zero FBOs, 100% round)
                    RoundedImage {
                        id: userAvatarImg
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: 22
                        source: root.userAvatar || ""
                        fillMode: Image.PreserveAspectCrop
                        initialsText: root.userName || "U"
                        placeholderColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                        asynchronous: true
                    }

                    // Plus / Edit Action Badge at bottom-right of avatar
                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        width: 16; height: 16; radius: 8
                        color: root.accentColor
                        border.color: "#08090d"
                        border.width: 1.5

                        AppIcon {
                            anchors.centerIn: parent
                            source: "../assets/icons/list-add-symbolic.svg"
                            iconSize: 9
                            color: "#ffffff"
                        }
                    }
                }

                // Label below user avatar
                Text {
                    anchors.top: userAvatarWrapper.bottom
                    anchors.topMargin: 2
                    anchors.horizontalCenter: userAvatarWrapper.horizontalCenter
                    text: root.myLatestNote ? I18n.tr("Note của bạn", "Your Note") : I18n.tr("Ghi chú của bạn", "Your note")
                    color: userMouseArea.containsMouse ? "#ffffff" : Qt.rgba(1, 1, 1, 0.70)
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.bold: true
                    elide: Text.ElideRight
                    width: 70
                    horizontalAlignment: Text.AlignHCenter
                }

                MouseArea {
                    id: userMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.myLatestNote !== null) {
                            root.userNoteDetailClicked();
                        } else {
                            root.postNoteClicked();
                        }
                    }
                }
            }

            // ==========================================
            // ITEMS 1..N: FRIENDS NOTES (Messenger Pattern - 74px column, 80px bubble, 2-line wrap)
            // ==========================================
            Repeater {
                model: root.friendsNotes

                delegate: Item {
                    id: friendDelegateItem
                    property string friendNoteStr: String(modelData.note_text || "").replace(/[\r\n]+/g, " ").trim()
                    property var friendTrackObj: modelData.track
                    property var friendNowPlayingObj: {
                        var np = modelData.now_playing;
                        if (!np) return null;
                        if (typeof np === "object") return np;
                        if (typeof np === "string" && np.trim().startsWith("{")) {
                            try { return JSON.parse(np); } catch(e) { return null; }
                        }
                        return null;
                    }
                    property string friendTrackStr: (friendTrackObj && (friendTrackObj.title || friendTrackObj.name || friendTrackObj.id)) ? String(friendTrackObj.title || friendTrackObj.name || "").trim() : ""
                    property bool hasFriendTrack: friendTrackStr.length > 0
                    property bool hasAnyNote: friendNoteStr.length > 0 || hasFriendTrack
                    property bool isFriendTrackOnly: hasFriendTrack && friendNoteStr.length === 0

                    readonly property color friendSongAccent: {
                        if (friendTrackObj && friendTrackObj.accent_color && String(friendTrackObj.accent_color).trim() !== "") {
                            return friendTrackObj.accent_color;
                        }
                        if (modelData.accent_color && String(modelData.accent_color).trim() !== "") {
                            return modelData.accent_color;
                        }
                        if (friendNowPlayingObj && typeof friendNowPlayingObj === "object" && friendNowPlayingObj.accent_color && String(friendNowPlayingObj.accent_color).trim() !== "") {
                            return friendNowPlayingObj.accent_color;
                        }
                        return root.accentColor;
                    }
                    readonly property bool hasCustomFriendAccent: (friendTrackObj && friendTrackObj.accent_color) || (modelData.accent_color) || (friendNowPlayingObj && typeof friendNowPlayingObj === "object" && friendNowPlayingObj.accent_color)
                    readonly property color effectiveFriendNoteAccent: hasCustomFriendAccent ? friendSongAccent : root.accentColor

                    width: 80
                    height: friendsFlickable.height

                    // Mini Thought Bubble above friend avatar (Messenger Compact: 80px width, 2-line wrap, z: 10 layer trên)
                    Rectangle {
                        id: friendBubbleBox
                        visible: friendDelegateItem.hasAnyNote
                        anchors.bottom: friendAvatarWrapper.top
                        anchors.bottomMargin: 6
                        anchors.horizontalCenter: friendAvatarWrapper.horizontalCenter
                        z: 10
                        width: 80
                        height: friendDelegateItem.isFriendTrackOnly ? 24 : Math.max(24, Math.min(48, friendBubbleCol.implicitHeight + 8))
                        radius: friendDelegateItem.isFriendTrackOnly ? 12 : Math.min(14, height / 2)
                        color: friendArea.containsMouse
                            ? Qt.rgba(friendDelegateItem.effectiveFriendNoteAccent.r, friendDelegateItem.effectiveFriendNoteAccent.g, friendDelegateItem.effectiveFriendNoteAccent.b, 0.28)
                            : Qt.rgba(friendDelegateItem.effectiveFriendNoteAccent.r, friendDelegateItem.effectiveFriendNoteAccent.g, friendDelegateItem.effectiveFriendNoteAccent.b, 0.16)
                        border.color: friendArea.containsMouse
                            ? friendDelegateItem.effectiveFriendNoteAccent
                            : Qt.rgba(friendDelegateItem.effectiveFriendNoteAccent.r, friendDelegateItem.effectiveFriendNoteAccent.g, friendDelegateItem.effectiveFriendNoteAccent.b, 0.40)
                        border.width: 1
                        scale: friendArea.containsMouse ? 1.05 : 1.0
                        Behavior on scale { NumberAnimation { duration: 150 } }
                        Behavior on color { ColorAnimation { duration: 250 } }
                        Behavior on border.color { ColorAnimation { duration: 200 } }

                        // Connector Dot 1 (top dot)
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.bottom
                            anchors.topMargin: 1
                            width: 5; height: 5; radius: 2.5
                            color: friendBubbleBox.color
                            border.color: friendBubbleBox.border.color
                            border.width: 0.5
                            z: 10
                        }

                        // Connector Dot 2 (bottom dot, closer to avatar)
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.bottom
                            anchors.topMargin: 5
                            width: 3.5; height: 3.5; radius: 1.75
                            color: friendBubbleBox.color
                            border.color: friendBubbleBox.border.color
                            border.width: 0.5
                            z: 10
                        }

                        ColumnLayout {
                            id: friendBubbleCol
                            anchors.centerIn: parent
                            width: parent.width - 8
                            spacing: 1

                            // Line 1 & 2: Note Text with 2-line wrapping
                            Text {
                                id: friendNoteText
                                Layout.fillWidth: true
                                visible: friendDelegateItem.friendNoteStr.length > 0
                                text: friendDelegateItem.friendNoteStr
                                color: "#ffffff"
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.bold: true
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                lineHeight: 1.05
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // Line 2 (or 3): Attached Track (sóng âm visualizer)
                            RowLayout {
                                id: friendTrackRow
                                Layout.fillWidth: true
                                spacing: 3
                                visible: friendDelegateItem.hasFriendTrack
                                Layout.alignment: Qt.AlignHCenter

                                // Audio Waveform Visualizer (Sóng âm 3 cột chuyển động)
                                Row {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1.5
                                height: 8

                                Rectangle {
                                    width: 1.8; height: 5; radius: 0.9
                                    color: friendDelegateItem.effectiveFriendNoteAccent
                                    anchors.bottom: parent.bottom
                                    SequentialAnimation on height {
                                        running: friendDelegateItem.hasFriendTrack
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 8; duration: 340; easing.type: Easing.InOutQuad }
                                        NumberAnimation { to: 3; duration: 340; easing.type: Easing.InOutQuad }
                                    }
                                }
                                Rectangle {
                                    width: 1.8; height: 8; radius: 0.9
                                    color: friendDelegateItem.effectiveFriendNoteAccent
                                    anchors.bottom: parent.bottom
                                    SequentialAnimation on height {
                                        running: friendDelegateItem.hasFriendTrack
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 3.5; duration: 260; easing.type: Easing.InOutQuad }
                                        NumberAnimation { to: 8; duration: 260; easing.type: Easing.InOutQuad }
                                    }
                                }
                                Rectangle {
                                    width: 1.8; height: 6; radius: 0.9
                                    color: friendDelegateItem.effectiveFriendNoteAccent
                                    anchors.bottom: parent.bottom
                                    SequentialAnimation on height {
                                        running: friendDelegateItem.hasFriendTrack
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 7.5; duration: 400; easing.type: Easing.InOutQuad }
                                        NumberAnimation { to: 2.5; duration: 400; easing.type: Easing.InOutQuad }
                                    }
                                }
                            }

                            Text {
                                id: friendTrackText
                                Layout.fillWidth: true
                                text: friendDelegateItem.friendTrackStr
                                color: friendDelegateItem.effectiveFriendNoteAccent
                                font.family: Theme.fontFamily
                                font.pixelSize: 8
                                font.bold: true
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }

                    // Friend Circular Avatar Wrapper (48x48, z: 1 so bubble at z: 10 is on top)
                    Item {
                        id: friendAvatarWrapper
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 18
                        anchors.horizontalCenter: parent.horizontalCenter
                        z: 1
                        width: 48; height: 48
                        scale: friendArea.containsMouse ? 1.08 : 1.0
                        Behavior on scale { NumberAnimation { duration: 150 } }

                        // Outer Pulse Ring when music is attached
                        Rectangle {
                            anchors.fill: parent
                            radius: 24
                            color: "transparent"
                            border.color: friendArea.containsMouse
                                ? friendDelegateItem.effectiveFriendNoteAccent
                                : Qt.rgba(friendDelegateItem.effectiveFriendNoteAccent.r, friendDelegateItem.effectiveFriendNoteAccent.g, friendDelegateItem.effectiveFriendNoteAccent.b, 0.45)
                            border.width: 1.5
                        }

                        // Friend Avatar with Hardware SDF Circle Masking (Zero FBOs, 100% round)
                        RoundedImage {
                            id: friendAvatarImg
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 22
                            source: modelData.avatar_url || ""
                            fillMode: Image.PreserveAspectCrop
                            initialsText: modelData.user_name || "F"
                            placeholderColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25)
                            asynchronous: true
                        }

                        // Green Online Indicator Dot (Only visible when friend is online)
                        Rectangle {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            width: 12; height: 12; radius: 6
                            color: "#10b981"
                            border.color: "#08090d"
                            border.width: 2
                            visible: Boolean(modelData && modelData.is_online)
                        }
                    }

                    // Friend Name below avatar
                    Text {
                        anchors.top: friendAvatarWrapper.bottom
                        anchors.topMargin: 2
                        anchors.horizontalCenter: friendAvatarWrapper.horizontalCenter
                        text: modelData.user_name || "Friend"
                        color: friendArea.containsMouse ? "#ffffff" : Qt.rgba(1, 1, 1, 0.6)
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        elide: Text.ElideRight
                        width: 70
                        horizontalAlignment: Text.AlignHCenter
                    }

                    MouseArea {
                        id: friendArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openStoryRequested(modelData, index)
                    }
                }
            }

            // ==========================================
            // TAIL ITEM: ADD FRIEND ACTION (74px width)
            // ==========================================
            Item {
                id: addFriendItem
                width: 80
                height: friendsFlickable.height

                // Placeholder space matching thought bubble height to preserve exact avatar baseline
                Item {
                    anchors.top: parent.top
                    anchors.topMargin: 4
                    width: parent.width
                    height: 24
                }

                // Circular Add Friend Avatar Container (48x48)
                Rectangle {
                    id: addFriendCircle
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 18
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 48; height: 48; radius: 24
                    color: addFriendMouse.containsMouse
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                        : Qt.rgba(1, 1, 1, 0.04)
                    border.color: addFriendMouse.containsMouse
                        ? root.accentColor
                        : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                    border.width: 1.5
                    scale: addFriendMouse.containsMouse ? 1.08 : 1.0
                    Behavior on scale { NumberAnimation { duration: 150 } }

                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/list-add-symbolic.svg"
                        iconSize: 16
                        color: addFriendMouse.containsMouse ? "#ffffff" : root.accentColor
                    }
                }

                // Label below Add Friend avatar
                Text {
                    anchors.top: addFriendCircle.bottom
                    anchors.topMargin: 2
                    anchors.horizontalCenter: addFriendCircle.horizontalCenter
                    text: I18n.tr("Thêm bạn", "Add friend")
                    color: addFriendMouse.containsMouse ? "#ffffff" : Qt.rgba(1, 1, 1, 0.60)
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.bold: true
                    elide: Text.ElideRight
                    width: 70
                    horizontalAlignment: Text.AlignHCenter
                }

                MouseArea {
                    id: addFriendMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.addFriendClicked()
                }
            }
        }
    }
}
