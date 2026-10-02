import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import "."

Rectangle {
    id: root
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.58)
    visible: false
    z: 10006

    property var currentTrack: null
    property string resolvedCover: ""
    property var availableTracks: []
    property string userAvatar: ""
    property string userName: ""
    property color accentColor: Theme.accent
    property Item backgroundSourceItem: null

    property var attachedTrack: null
    property bool isPickingTrack: false
    property string trackSearchQuery: ""
    property var onlineSearchResults: []
    property bool isSearchingOnline: false
    property string activeNoteText: ""

    signal closeRequested()
    signal noteSubmitted(string text, var track)
    signal previewTrackRequested(var track)
    signal togglePreviewRequested()
    signal restoreAudioBeforePreviewRequested()

    property var previewingTrack: null
    property bool isPreviewPlaying: false

    onIsPickingTrackChanged: {
        if (!isPickingTrack && root.previewingTrack !== null) {
            root.restoreAudioBeforePreviewRequested();
        }
    }

    function isSameTrack(a, b) {
        if (!a || !b) return false;
        if (a.path && b.path && a.path === b.path) return true;
        var vidA = a.videoId || (a.path && a.path.startsWith("ytdl://") ? a.path.replace("ytdl://", "") : "");
        var vidB = b.videoId || (b.path && b.path.startsWith("ytdl://") ? b.path.replace("ytdl://", "") : "");
        if (vidA && vidB && vidA === vidB) return true;
        var nameA = a.title || a.name || "";
        var nameB = b.title || b.name || "";
        if (nameA && nameB && nameA === nameB && a.artist && b.artist && a.artist === b.artist) return true;
        return false;
    }

    function updateActiveNoteText() {
        var pt = (noteInput.preeditText !== undefined && noteInput.preeditText !== null) ? String(noteInput.preeditText).trim() : "";
        var t = (noteInput.text !== undefined && noteInput.text !== null) ? String(noteInput.text).trim() : "";
        if (pt.length > 0) {
            root.activeNoteText = (t.length > 0) ? (t + " " + pt).replace(/\s+/g, " ").trim() : pt;
        } else {
            root.activeNoteText = t;
        }
    }

    function getCurrentNoteText() {
        updateActiveNoteText();
        return root.activeNoteText;
    }

    function submitCurrentNote() {
        noteInput.focus = false;
        var t = getCurrentNoteText();
        var clean = t ? t.replace(/[\r\n]+/g, " ").trim() : "";
        if (clean.length > 60) return;
        if (!clean && !root.attachedTrack) return;
        root.noteSubmitted(clean, root.attachedTrack);
    }

    function openModal() {
        root.isPickingTrack = false;
        root.trackSearchQuery = "";
        root.onlineSearchResults = [];
        root.isSearchingOnline = false;
        root.previewingTrack = null;
        root.isPreviewPlaying = false;
        noteInput.text = "";
        root.activeNoteText = "";
        root.attachedTrack = root.currentTrack;
        root.visible = true;
        noteInput.forceActiveFocus();
    }

    function performOnlineSearch() {
        var q = root.trackSearchQuery.trim();
        if (!q) {
            searchDebounceTimer.stop();
            root.onlineSearchResults = [];
            root.isSearchingOnline = false;
            return;
        }
        root.isSearchingOnline = true;
        var xhr = new XMLHttpRequest();
        var url = "http://127.0.0.1:17890/api/filter_search?q=" + encodeURIComponent(q) + "&filter=songs&limit=25";
        xhr.open("GET", url, true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                // Ignore stale out-of-order responses if user has typed a newer query
                if (root.trackSearchQuery.trim() !== q) {
                    return;
                }
                root.isSearchingOnline = false;
                if (xhr.status === 200) {
                    try {
                        var res = JSON.parse(xhr.responseText);
                        if (Array.isArray(res)) {
                            root.onlineSearchResults = res;
                        }
                    } catch(e) {
                        console.log("PostNoteModal search parse error:", e);
                    }
                }
            }
        };
        xhr.send();
    }

    Timer {
        id: searchDebounceTimer
        interval: 320
        repeat: false
        onTriggered: root.performOnlineSearch()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (root.isPickingTrack) {
                root.isPickingTrack = false;
            } else {
                root.closeRequested();
            }
        }
    }

    // Outer Drop Shadow (MultiEffect standard)
    Rectangle {
        id: shadowSourceRect
        anchors.fill: dialogCard
        radius: dialogCard.radius
        color: "#000000"
        visible: false
    }

    MultiEffect {
        anchors.fill: shadowSourceRect
        source: shadowSourceRect
        shadowEnabled: true
        shadowColor: "#80000000"
        shadowVerticalOffset: 6
        shadowBlur: 0.65
        z: 1
    }

    // Modal Main Container: Keo 502 Optical Resin (LiquidGlass, 20px Radius)
    LiquidGlass {
        id: dialogCard
        width: 440
        height: root.isPickingTrack ? 490 : 390
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

        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

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
            onClicked: (mouse) => {
                mouse.accepted = true;
            }
        }

        // ==========================================
        // VIEW 1: NOTE CREATION VIEW (!root.isPickingTrack)
        // ==========================================
        ColumnLayout {
            id: noteCreationCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 0
            visible: !root.isPickingTrack
            z: 5

            // TOP BAR: '✕' (Left) | Title (Center) | 'Chia sẻ' (Right) - ALL BORDERLESS
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32

                // Plain '✕' Close Button (Zero border, zero background box)
                MouseArea {
                    id: closeMouse
                    width: 28; height: 28
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeRequested()

                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/window-close-symbolic.svg"
                        iconSize: 15
                        color: closeMouse.containsMouse ? "#f43f5e" : Qt.rgba(1, 1, 1, 0.75)
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }

                Item { Layout.fillWidth: true }

                // Title "Ghi chú mới"
                Text {
                    text: I18n.tr("Ghi chú mới", "New note")
                    color: "#ffffff"
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                // Plain "Chia sẻ" Share Text Button (Zero border, zero background box)
                Text {
                    id: shareBtnText
                    text: I18n.tr("Chia sẻ", "Share")
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.bold: true

                    readonly property bool canSubmit: (root.activeNoteText.length > 0 || root.attachedTrack !== null) && root.activeNoteText.length <= 60

                    color: !canSubmit
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                        : (shareMouse.containsMouse ? "#ffffff" : root.accentColor)
                    Behavior on color { ColorAnimation { duration: 150 } }

                    MouseArea {
                        id: shareMouse
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: shareBtnText.canSubmit ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (shareBtnText.canSubmit) {
                                root.submitCurrentNote();
                            }
                        }
                    }
                }
            }

            // Spacing
            Item { Layout.fillWidth: true; Layout.preferredHeight: 14 }

            // CENTER: FLOATING THOUGHT BUBBLE + CIRCULAR AVATAR (Messenger Style - Ảnh 1 & 2)
            Item {
                id: centerArea
                Layout.fillWidth: true
                Layout.preferredHeight: 250

                // User Circular Avatar (68x68) - Anchored at bottom of center area (Clean RoundedImage)
                Item {
                    id: modalAvatarWrapper
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 10
                    width: 68; height: 68

                    RoundedImage {
                        anchors.fill: parent
                        radius: 34
                        source: root.userAvatar || ""
                        placeholderColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25)
                        borderColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.55)
                        borderWidth: 1.5
                        fallbackIcon: "../assets/icons/preferences-system-symbolic.svg"
                        fallbackIconSize: 28
                        fallbackIconColor: root.accentColor
                    }
                }

                // Connector Dot 1 (Small: 5px, just above avatar)
                Rectangle {
                    id: dot1
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: modalAvatarWrapper.top
                    anchors.bottomMargin: 4
                    width: 5; height: 5; radius: 2.5
                    color: thoughtBubble.color
                }

                // Connector Dot 2 (Medium: 8px, above dot1)
                Rectangle {
                    id: dot2
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: dot1.top
                    anchors.bottomMargin: 3
                    width: 8; height: 8; radius: 4
                    color: thoughtBubble.color
                }

                // Floating Thought Bubble Container (Grows upwards from dot2, desktop width: 340)
                Rectangle {
                    id: thoughtBubble
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: dot2.top
                    anchors.bottomMargin: 3
                    width: 340
                    height: bubbleCol.implicitHeight + 26
                    radius: 18
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, (typeof win !== "undefined" && win.isPlaying) ? 0.24 : 0.14)
                    border.color: root.activeNoteText.length > 60
                        ? "#f43f5e"
                        : (noteInput.activeFocus ? root.accentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.40))
                    border.width: 1.5

                    Behavior on color { ColorAnimation { duration: 250 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    ColumnLayout {
                        id: bubbleCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 8

                        // Text Input Area
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.max(34, noteInput.contentHeight)

                            // Placeholder: Centered, disappears immediately when typing
                            Text {
                                anchors.fill: parent
                                text: I18n.tr("Chia sẻ suy nghĩ...", "Share a thought...")
                                color: Qt.rgba(1, 1, 1, 0.40)
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                visible: root.activeNoteText.length === 0
                            }

                            TextEdit {
                                id: noteInput
                                anchors.fill: parent
                                color: "#ffffff"
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                wrapMode: TextEdit.Wrap
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                selectByMouse: true

                                onTextChanged: root.updateActiveNoteText()
                                onPreeditTextChanged: root.updateActiveNoteText()
                                onInputMethodComposingChanged: root.updateActiveNoteText()

                                Keys.onReturnPressed: (event) => {
                                    event.accepted = true;
                                    if (shareBtnText.canSubmit) {
                                        root.submitCurrentNote();
                                    }
                                }
                            }
                        }

                        // Red Warning if > 60 characters (NO "0/60" shown normally)
                        Text {
                            visible: root.activeNoteText.length > 60
                            text: I18n.tr("Đã vượt quá 60 ký tự (" + root.activeNoteText.length + "/60)", "Exceeded 60 chars (" + root.activeNoteText.length + "/60)")
                            color: "#f43f5e"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: true
                            Layout.alignment: Qt.AlignHCenter
                        }

                        // Attached Track Music Row (Inside thought bubble)
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            visible: true

                            // Case 1: Track attached -> Show track info, change button and remove button
                            RowLayout {
                                anchors.fill: parent
                                spacing: 8
                                visible: !!root.attachedTrack

                                // Album Art Thumbnail (28x28, R=6 using unified RoundedImage with border)
                                RoundedImage {
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: 6
                                    source: {
                                        if (!root.attachedTrack) return "";
                                        if (root.attachedTrack === root.currentTrack && root.resolvedCover) return root.resolvedCover;
                                        return root.attachedTrack.image || root.attachedTrack.cover || "";
                                    }
                                    placeholderColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                                    borderColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                                    borderWidth: 1.0
                                    fallbackIcon: "../assets/icons/folder-music-symbolic.svg"
                                    fallbackIconSize: 12
                                    fallbackIconColor: root.accentColor
                                }

                                // Title & Artist (Marquee animation when title is long)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 2

                                    Item {
                                        id: noteTrackTitleContainer
                                        Layout.fillWidth: true
                                        implicitHeight: noteTrackTitleText.implicitHeight
                                        clip: true

                                        Text {
                                            id: noteTrackTitleText
                                            text: root.attachedTrack ? (root.attachedTrack.title || root.attachedTrack.name || "Track") : ""
                                            color: "#ffffff"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            font.bold: true
                                            x: 0

                                            readonly property real overflowDist: Math.max(0, implicitWidth - noteTrackTitleContainer.width)
                                            readonly property bool needsScroll: overflowDist > 6

                                            onTextChanged: {
                                                noteTrackTitleText.x = 0;
                                            }

                                            SequentialAnimation {
                                                id: noteTrackMarqueeAnim
                                                running: noteTrackTitleText.needsScroll
                                                loops: Animation.Infinite

                                                PauseAnimation { duration: 1800 }
                                                NumberAnimation {
                                                    target: noteTrackTitleText
                                                    property: "x"
                                                    to: -noteTrackTitleText.overflowDist
                                                    duration: Math.max(1200, noteTrackTitleText.overflowDist * 28)
                                                    easing.type: Easing.InOutQuad
                                                }
                                                PauseAnimation { duration: 1800 }
                                                NumberAnimation {
                                                    target: noteTrackTitleText
                                                    property: "x"
                                                    to: 0
                                                    duration: Math.max(1200, noteTrackTitleText.overflowDist * 28)
                                                    easing.type: Easing.InOutQuad
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.attachedTrack ? (root.attachedTrack.artist || "") : ""
                                        color: Qt.rgba(1, 1, 1, 0.6)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                        visible: text.length > 0
                                    }
                                }

                                // 🔍 Change Track Button
                                MouseArea {
                                    id: changeTrackBtn
                                    Layout.preferredWidth: 24
                                    Layout.preferredHeight: 24
                                    Layout.alignment: Qt.AlignVCenter
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.trackSearchQuery = "";
                                        pickerSearchInput.text = "";
                                        root.onlineSearchResults = [];
                                        root.isPickingTrack = true;
                                        pickerSearchInput.forceActiveFocus();
                                    }

                                    AppIcon {
                                        anchors.centerIn: parent
                                        source: "../assets/icons/system-search-symbolic.svg"
                                        iconSize: 13
                                        color: changeTrackBtn.containsMouse ? "#ffffff" : root.accentColor
                                    }
                                }

                                // ✕ Remove / Detach Track Button
                                MouseArea {
                                    id: removeTrackBtn
                                    Layout.preferredWidth: 24
                                    Layout.preferredHeight: 24
                                    Layout.alignment: Qt.AlignVCenter
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.attachedTrack = null;
                                        root.isPickingTrack = false;
                                    }

                                    AppIcon {
                                        anchors.centerIn: parent
                                        source: "../assets/icons/window-close-symbolic.svg"
                                        iconSize: 13
                                        color: removeTrackBtn.containsMouse ? "#f43f5e" : Qt.rgba(1, 1, 1, 0.55)
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }
                                }
                            }

                            // Case 2: No track attached -> Centered subtle action pills to attach/search music
                            RowLayout {
                                anchors.fill: parent
                                spacing: 8
                                visible: !root.attachedTrack

                                Item { Layout.fillWidth: true }

                                // Option A: Attach currently playing song (if playing in background)
                                Rectangle {
                                    id: attachCurBtn
                                    visible: !!root.currentTrack
                                    Layout.preferredHeight: 26
                                    Layout.preferredWidth: attachCurRow.implicitWidth + 18
                                    radius: 13
                                    color: attachCurMouse.containsMouse 
                                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22) 
                                        : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
                                    border.color: attachCurMouse.containsMouse 
                                        ? root.accentColor 
                                        : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.28)
                                    border.width: 1

                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Behavior on border.color { ColorAnimation { duration: 120 } }

                                    MouseArea {
                                        id: attachCurMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.attachedTrack = root.currentTrack;
                                        }
                                    }

                                    Row {
                                        id: attachCurRow
                                        anchors.centerIn: parent
                                        spacing: 5

                                        AppIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            source: "../assets/icons/folder-music-symbolic.svg"
                                            iconSize: 12
                                            color: attachCurMouse.containsMouse ? "#ffffff" : root.accentColor
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: I18n.tr("Bài đang phát", "Current song")
                                            color: attachCurMouse.containsMouse ? "#ffffff" : root.accentColor
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }
                                }

                                // Option B: Search & pick song
                                Rectangle {
                                    id: pickOtherBtn
                                    Layout.preferredHeight: 26
                                    Layout.preferredWidth: pickOtherRow.implicitWidth + 18
                                    radius: 13
                                    color: pickOtherMouse.containsMouse 
                                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22) 
                                        : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
                                    border.color: pickOtherMouse.containsMouse 
                                        ? root.accentColor 
                                        : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.28)
                                    border.width: 1

                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Behavior on border.color { ColorAnimation { duration: 120 } }

                                    MouseArea {
                                        id: pickOtherMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.trackSearchQuery = "";
                                            pickerSearchInput.text = "";
                                            root.onlineSearchResults = [];
                                            root.isPickingTrack = true;
                                            pickerSearchInput.forceActiveFocus();
                                        }
                                    }

                                    Row {
                                        id: pickOtherRow
                                        anchors.centerIn: parent
                                        spacing: 5

                                        AppIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            source: "../assets/icons/system-search-symbolic.svg"
                                            iconSize: 12
                                            color: pickOtherMouse.containsMouse ? "#ffffff" : root.accentColor
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: I18n.tr("Thêm bài hát...", "Add song...")
                                            color: pickOtherMouse.containsMouse ? "#ffffff" : Qt.rgba(1, 1, 1, 0.85)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }
                            }
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true; Layout.fillHeight: true }

            // BOTTOM SUBTITLE (Messenger Style)
            Text {
                Layout.fillWidth: true
                text: I18n.tr("Bạn bè có thể xem ghi chú của bạn trong 24 giờ", "Friends can see your note for 24 hours")
                color: Qt.rgba(1, 1, 1, 0.45)
                font.family: Theme.fontFamily
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // ==========================================
        // VIEW 2: MUSIC SEARCH VIEW (Ảnh 1: media_1789810673070.jpg)
        // ==========================================
        ColumnLayout {
            id: searchMusicCol
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12
            visible: root.isPickingTrack
            z: 5


            // TOP SEARCH HEADER (Ảnh 1: Back Arrow + Search Pill)
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // Back Arrow Button '←'
                MouseArea {
                    id: backSearchMouse
                    width: 32; height: 32
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.isPickingTrack = false;
                        noteInput.forceActiveFocus();
                    }

                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/go-previous-symbolic.svg"
                        iconSize: 16
                        color: backSearchMouse.containsMouse ? root.accentColor : "#ffffff"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                }

                // Search Pill Container (Ảnh 1)
                Rectangle {
                    Layout.fillWidth: true
                    height: 38
                    radius: 19
                    color: Qt.rgba(1, 1, 1, 0.08)
                    border.color: pickerSearchInput.activeFocus ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.4) : Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 8

                        AppIcon {
                            source: "../assets/icons/system-search-symbolic.svg"
                            iconSize: 15
                            color: pickerSearchInput.activeFocus ? root.accentColor : Qt.rgba(1, 1, 1, 0.5)
                        }

                        TextInput {
                            id: pickerSearchInput
                            Layout.fillWidth: true
                            color: "#ffffff"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            clip: true
                            selectByMouse: true

                            function updatePickerQuery() {
                                var pt = (pickerSearchInput.preeditText !== undefined && pickerSearchInput.preeditText !== null) ? String(pickerSearchInput.preeditText).trim() : "";
                                var t = (pickerSearchInput.text !== undefined && pickerSearchInput.text !== null) ? String(pickerSearchInput.text).trim() : "";
                                var q = (pt.length > 0) ? (t + " " + pt).replace(/\s+/g, " ").trim() : t;
                                root.trackSearchQuery = q;
                                searchDebounceTimer.restart();
                            }

                            onTextChanged: updatePickerQuery()
                            onPreeditTextChanged: updatePickerQuery()
                            onInputMethodComposingChanged: updatePickerQuery()
                            onAccepted: root.performOnlineSearch()

                            Text {
                                anchors.fill: parent
                                text: I18n.tr("Tìm kiếm nhạc", "Search music")
                                color: Qt.rgba(1, 1, 1, 0.45)
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                visible: !pickerSearchInput.text && !pickerSearchInput.inputMethodComposing
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        // Clear search button '✕'
                        MouseArea {
                            visible: pickerSearchInput.text.length > 0
                            width: 20; height: 20
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                pickerSearchInput.text = "";
                                root.trackSearchQuery = "";
                                root.onlineSearchResults = [];
                            }

                            AppIcon {
                                anchors.centerIn: parent
                                source: "../assets/icons/window-close-symbolic.svg"
                                iconSize: 11
                                color: Qt.rgba(1, 1, 1, 0.6)
                            }
                        }
                    }
                }
            }

            // Status Indicator (Searching...)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 14
                visible: root.isSearchingOnline

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    AppIcon {
                        source: "../assets/icons/process-working-symbolic.svg"
                        iconSize: 11
                        color: root.accentColor
                    }
                    Text {
                        text: I18n.tr("Đang tìm kiếm nhạc trực tuyến...", "Searching online music...")
                        color: Qt.rgba(1, 1, 1, 0.5)
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                }
            }

            // Tracks ListView (Styled exactly like Ảnh 1: media_1789810673070.jpg)
            ListView {
                id: pickerListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6

                model: {
                    var q = root.trackSearchQuery.trim();
                    if (q.length > 0) {
                        if (root.onlineSearchResults && root.onlineSearchResults.length > 0) {
                            return root.onlineSearchResults;
                        }
                        var qLower = q.toLowerCase();
                        var locals = (root.availableTracks || []).filter(function(t) {
                            return (t.title && t.title.toLowerCase().indexOf(qLower) !== -1) ||
                                   (t.name && t.name.toLowerCase().indexOf(qLower) !== -1) ||
                                   (t.artist && t.artist.toLowerCase().indexOf(qLower) !== -1);
                        });
                        return locals;
                    }
                    // Fallback to queue and library tracks when search query is empty
                    var list = (root.availableTracks && root.availableTracks.length > 0) ? root.availableTracks : (root.currentTrack ? [root.currentTrack] : []);
                    return list;
                }

                delegate: Rectangle {
                    id: songRowCard
                    width: pickerListView.width
                    height: 56
                    radius: 10
                    readonly property bool isThisPreviewing: root.isSameTrack(root.previewingTrack, modelData) && root.isPreviewPlaying
                    color: songRowCard.isThisPreviewing ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14) : (songRowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")

                    Behavior on color { ColorAnimation { duration: 120 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 12

                        // Album Artwork Thumbnail (44x44, R=8 using unified RoundedImage)
                        RoundedImage {
                            width: 44; height: 44
                            radius: 8
                            source: modelData.image || modelData.cover || ""
                            placeholderColor: Qt.rgba(1, 1, 1, 0.08)
                            fallbackIcon: "../assets/icons/folder-music-symbolic.svg"
                            fallbackIconSize: 18
                            fallbackIconColor: root.accentColor
                        }

                        // Middle: Song Title (bold, 13px) & Artist (11px, muted)
                        Column {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                text: modelData.title || modelData.name || "Track"
                                color: songRowCard.isThisPreviewing ? root.accentColor : "#ffffff"
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                elide: Text.ElideRight
                                width: songRowCard.width - 120
                            }

                            Text {
                                text: modelData.artist || "Unknown Artist"
                                color: Qt.rgba(1, 1, 1, 0.55)
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                elide: Text.ElideRight
                                width: songRowCard.width - 120
                            }
                        }

                        // Right: Circular Action Button (32x32, R=16, Play / Pause Preview)
                        Rectangle {
                            id: playBtn
                            width: 32; height: 32
                            radius: 16
                            color: songRowCard.isThisPreviewing ? root.accentColor : (playBtnMouse.containsMouse ? root.accentColor : Qt.rgba(1, 1, 1, 0.10))
                            Behavior on color { ColorAnimation { duration: 120 } }

                            AppIcon {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: songRowCard.isThisPreviewing ? 0 : 1
                                source: songRowCard.isThisPreviewing ? "../assets/icons/media-playback-pause-symbolic.svg" : "../assets/icons/media-playback-start-symbolic.svg"
                                iconSize: 12
                                color: "#ffffff"
                            }

                            MouseArea {
                                id: playBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (songRowCard.isThisPreviewing) {
                                        root.togglePreviewRequested();
                                    } else if (root.isSameTrack(root.previewingTrack, modelData)) {
                                        root.togglePreviewRequested();
                                    } else {
                                        root.previewTrackRequested(modelData);
                                    }
                                }
                            }
                        }
                    }

                    // MouseArea for row selection (attaches song to note, keeps music playing)
                    MouseArea {
                        id: songRowMouse
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        anchors.rightMargin: 48 // leaves space for playBtn so click won't clash
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // If user is currently previewing this track, promote it to current playing track so it keeps playing!
                            if (root.previewingTrack && root.isSameTrack(root.previewingTrack, modelData)) {
                                if (typeof win !== "undefined") {
                                    win.currentTrack = modelData;
                                    win.trackBeforeNotePreview = null;
                                    win.wasPlayingBeforeNotePreview = true;
                                }
                                root.previewingTrack = null;
                            }
                            root.attachedTrack = modelData;
                            root.isPickingTrack = false;
                            noteInput.forceActiveFocus();
                        }
                    }
                }
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            root.openModal();
        } else {
            if (root.previewingTrack !== null) {
                root.restoreAudioBeforePreviewRequested();
            }
        }
    }
}
