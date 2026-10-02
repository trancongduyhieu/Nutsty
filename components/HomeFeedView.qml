import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import "."

Rectangle {
    id: root
    color: "transparent"
    radius: Theme.radiusCard
    clip: true

    property var moods: []
    property string selectedMood: "All"
    property var sections: []
    property var quickPicks: []
    property var featuredPlaylists: []
    property bool isLoading: false
    property var currentTrack: null
    property bool isPlaying: false
    property bool isLoadingAudio: false
    property Item backgroundSourceItem: null
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent
    property string accountName: ""
    property string accountThumb: ""
    property int arrowStylePreset: 1
    readonly property real accentLum: (0.299 * root.accentColor.r + 0.587 * root.accentColor.g + 0.114 * root.accentColor.b)

    property var friendsNotes: []
    property var myLatestNote: null

    signal moodSelected(string title, string params)
    signal trackPlayRequested(var trk)
    signal playSectionRequested(var trackList)
    signal playlistSelected(var pl)
    signal trackContextMenuRequested(var trk, real globalX, real globalY)
    signal postNoteRequested()
    signal userNoteDetailRequested()
    signal playFriendTrackRequested(var trk)
    signal addFriendRequested()
    signal openStoryRequested(var friendData, int index)

    function getGreeting() {
        var h = new Date().getHours();
        var greet = "";
        if (h >= 5 && h < 12) greet = I18n.tr("Chào buổi sáng", "Good Morning");
        else if (h >= 12 && h < 18) greet = I18n.tr("Chào buổi chiều", "Good Afternoon");
        else greet = I18n.tr("Chào buổi tối", "Good Evening");

        if (root.accountName && root.accountName.trim() !== "") {
            return greet + ", " + root.accountName.trim();
        }
        return greet;
    }

    function openFriendNote(idx) {
        if (friendsPulseBar) friendsPulseBar.openFriendNote(idx);
    }

    function scrollToTop() {
        feedListView.positionViewAtBeginning();
    }

    function formatMoodTitle(title) {
        return I18n.formatMoodChipTitle(title);
    }

    function formatSectionTitle(title) {
        return I18n.formatSectionTitle(title);
    }

    function formatSectionSubtitle(sub) {
        if (!sub) return "";
        var s = String(sub).trim();
        if (root.accountName && s.toLowerCase() === root.accountName.trim().toLowerCase()) {
            return "";
        }
        var upper = s.toUpperCase();
        if (upper === "LOADING") return I18n.tr("ĐANG TẢI", "LOADING");
        if (upper === "DISCOVER") return I18n.tr("KHÁM PHÁ", "DISCOVER");
        if (upper === "LET'S START WITH A RADIO") return I18n.tr("BẮT ĐẦU VỚI MỘT ĐÀI PHÁT", "LET'S START WITH A RADIO");
        if (upper === "START RADIO") return I18n.tr("BẮT ĐẦU ĐÀI PHÁT", "START RADIO");
        return s;
    }

    // Dynamic feed sections model with fallbacks
    readonly property var activeFeedSections: {
        if (root.sections && root.sections.length > 0) {
            return root.sections;
        }
        if (root.isLoading) {
            return [
                { type: "skeleton_section", title: I18n.tr("Được đề xuất cho bạn", "Recommended for you"), subtitle: I18n.tr("ĐANG TẢI", "LOADING"), items: [1, 2, 3, 4, 5, 6] },
                { type: "skeleton_section", title: I18n.tr("Nghe lại", "Listen again"), subtitle: I18n.tr("KHÁM PHÁ", "DISCOVER"), items: [1, 2, 3, 4, 5, 6] }
            ];
        }
        var fallbacks = [];
        if (root.quickPicks && root.quickPicks.length > 0) {
            fallbacks.push({
                type: "fallback_quick_picks",
                title: I18n.tr("Tuyển tập nhanh", "Quick picks"),
                subtitle: I18n.tr("BẮT ĐẦU VỚI MỘT ĐÀI PHÁT", "LET'S START WITH A RADIO"),
                items: root.quickPicks
            });
        }
        if (root.featuredPlaylists && root.featuredPlaylists.length > 0) {
            fallbacks.push({
                type: "fallback_playlists",
                title: root.selectedMood === "All" ? I18n.tr("Danh sách phát nổi bật cho bạn", "Featured playlists for you") : (root.formatMoodTitle(root.selectedMood) + I18n.tr(" - Danh sách phát", " Playlists")),
                items: root.featuredPlaylists
            });
        }
        return fallbacks;
    }

    // =========================================================================
    // VIRTUALIZED MAIN VIEWPORT (ListView with Culling, Recycling & CacheBuffer)
    // =========================================================================
    ListView {
        id: feedListView
        anchors.fill: parent
        clip: true
        spacing: 28
        boundsBehavior: Flickable.StopAtBounds
        pixelAligned: true
        maximumFlickVelocity: 6000
        flickDeceleration: 1500
        cacheBuffer: 800
        reuseItems: true
        model: root.activeFeedSections

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        // ---------------------------------------------------------------------
        // 1. Header: Greeting & Mood Pills Bar
        // ---------------------------------------------------------------------
        header: Item {
            width: feedListView.width
            height: headerCol.implicitHeight + 16

            ColumnLayout {
                id: headerCol
                anchors.top: parent.top
                anchors.topMargin: 16
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                spacing: 14

                Text {
                    text: root.getGreeting()
                    font.family: Theme.fontFamily
                    font.pixelSize: 28
                    font.bold: true
                    color: Theme.textPrimary
                }

                // Friends Pulse: 24h Ephemeral Music Notes Bar (Stories Style)
                FriendsPulseBar {
                    id: friendsPulseBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: height
                    friendsNotes: root.friendsNotes
                    myLatestNote: root.myLatestNote
                    currentTrack: root.currentTrack
                    isPlaying: root.isPlaying
                    accentColor: root.accentColor
                    userAvatar: root.accountThumb
                    userName: root.accountName
                    onPostNoteClicked: root.postNoteRequested()
                    onUserNoteDetailClicked: root.userNoteDetailRequested()
                    onOpenStoryRequested: (friendData, idx) => root.openStoryRequested(friendData, idx)
                    onPlayTrackRequested: track => root.playFriendTrackRequested(track)
                    onAddFriendClicked: root.addFriendRequested()
                }

                // Separated Mood Filter Pills with Sliding Liquid Glass Lens (True Keo 502 Refraction)
                Item {
                    id: moodDockContainer
                    Layout.fillWidth: true
                    height: 38

                    // Horizontal Scrollable Mood Items
                    Flickable {
                        id: homeMoodFlickable
                        anchors.fill: parent
                        anchors.leftMargin: 24
                        anchors.rightMargin: 24
                        contentWidth: moodRow.width + 16
                        contentHeight: height
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.HorizontalFlick
                        pixelAligned: true
                        clip: true

                        DragHandler {
                            target: null
                            xAxis.enabled: true
                            yAxis.enabled: false
                            cursorShape: Qt.OpenHandCursor
                            property real startContentX: 0
                            onActiveChanged: {
                                if (active) {
                                    startContentX = homeMoodFlickable.contentX;
                                }
                            }
                            onTranslationChanged: {
                                if (active) {
                                    var maxScroll = Math.max(0, homeMoodFlickable.contentWidth - homeMoodFlickable.width);
                                    homeMoodFlickable.contentX = Math.max(0, Math.min(maxScroll, startContentX - translation.x));
                                }
                            }
                        }

                        WheelHandler {
                            target: homeMoodFlickable
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: event => {
                                var delta = (event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x);
                                homeMoodFlickable.contentX = Math.max(0, Math.min(homeMoodFlickable.contentWidth - homeMoodFlickable.width, homeMoodFlickable.contentX - delta));
                            }
                        }

                        readonly property real accentLuminance: (0.299 * root.accentColor.r + 0.587 * root.accentColor.g + 0.114 * root.accentColor.b)

                        // Ambient drop shadow for the sliding active Keo 502 gel capsule
                        MultiEffect {
                            anchors.fill: activeMoodIndicator
                            source: activeMoodIndicator
                            shadowEnabled: true
                            shadowColor: "#50000000"
                            shadowVerticalOffset: 2
                            shadowBlur: 0.45
                            visible: activeMoodIndicator.width > 0
                            z: 1
                        }

                        // Sliding Keo 502 Glossy Gel Capsule (Fluid Meniscus, Rich Solid-Glass Contrast, ZERO glare streaks!)
                        Rectangle {
                            id: activeMoodIndicator
                            height: 30
                            radius: 15
                            y: (homeMoodFlickable.height - height) / 2
                            z: 2
                            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.90)
                            border.color: Qt.rgba(root.accentColor.r * 1.15, root.accentColor.g * 1.15, root.accentColor.b * 1.15, 0.95)
                            border.width: 1
                            visible: width > 0

                            // Inner Meniscus Specular Rim (Tension highlight without bleaching text)
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: 14
                                color: "transparent"
                                border.color: Qt.rgba(1.0, 1.0, 1.0, homeMoodFlickable.accentLuminance > 0.55 ? 0.35 : 0.22)
                                border.width: 1
                            }

                            Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                            Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }
                        }

                        // Separated Mood Pills Row
                        Row {
                            id: moodRow
                            spacing: 8
                            anchors.verticalCenter: parent.verticalCenter
                            z: 5
                            onWidthChanged: Qt.callLater(homeMoodFlickable.updateActiveIndicator)

                            Repeater {
                                id: moodRepeater
                                model: root.moods.length > 0 ? root.moods : [
                                    { "title": "All", "params": "" },
                                    { "title": "Relax", "params": "ggM8SgQIBxADSgQIBRABSgQICRABSgQIChABSgQIDRABSgQIDhABSgQIAxABSgQICBABSgQIBhABSgQIBBAB" },
                                    { "title": "Sleep", "params": "ggM8SgQIBxABSgQIBRADSgQICRABSgQIChABSgQIDRABSgQIDhABSgQIAxABSgQICBABSgQIBhABSgQIBBAB" },
                                    { "title": "Energize", "params": "ggM8SgQIBxABSgQIBRABSgQICRADSgQIChABSgQIDRABSgQIDhABSgQIAxABSgQICBABSgQIBhABSgQIBBAB" },
                                    { "title": "Sad", "params": "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChADSgQIDRABSgQIDhABSgQIAxABSgQICBABSgQIBhABSgQIBBAB" },
                                    { "title": "Romance", "params": "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRADSgQIDhABSgQIAxABSgQICBABSgQIBhABSgQIBBAB" },
                                    { "title": "Party", "params": "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQIDhADSgQIAxABSgQICBABSgQIBhABSgQIBBAB" },
                                    { "title": "Commute", "params": "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQIDhABSgQIAxADSgQICBABSgQIBhABSgQIBBAB" },
                                    { "title": "Feel good", "params": "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQIDhABSgQIAxABSgQICBADSgQIBhABSgQIBBAB" },
                                    { "title": "Focus", "params": "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQIDhABSgQIAxABSgQICBABSgQIBhADSgQIBBAB" },
                                    { "title": "Workout", "params": "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQIDhABSgQIAxABSgQICBABSgQIBhABSgQIBBAD" }
                                ]

                                delegate: Item {
                                    id: pillItem
                                    height: 30
                                    width: pillTxt.implicitWidth + 24
                                    readonly property bool isSelected: root.selectedMood === modelData.title
                                    readonly property bool isHovered: pillMouse.containsMouse

                                    onXChanged: {
                                        if (isSelected) activeMoodIndicator.x = pillItem.x;
                                    }
                                    onWidthChanged: {
                                        if (isSelected) activeMoodIndicator.width = pillItem.width;
                                    }
                                    onIsSelectedChanged: {
                                        if (isSelected) {
                                            activeMoodIndicator.x = pillItem.x;
                                            activeMoodIndicator.width = pillItem.width;
                                        }
                                    }
                                    Component.onCompleted: {
                                        if (isSelected) {
                                            activeMoodIndicator.x = pillItem.x;
                                            activeMoodIndicator.width = pillItem.width;
                                        }
                                    }

                                    // Standalone Inactive Dark Glass Capsule (Zero white glare streaks, clean optical glass)
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 15
                                        color: pillItem.isHovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16) : Qt.rgba(1.0, 1.0, 1.0, 0.06)
                                        border.width: 1
                                        border.color: pillItem.isHovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35) : Qt.rgba(1.0, 1.0, 1.0, 0.10)
                                        opacity: pillItem.isSelected ? 0.0 : 1.0
                                        scale: (pillItem.isHovered && !pillItem.isSelected) ? 1.03 : 1.0

                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Behavior on border.color { ColorAnimation { duration: 150 } }
                                        Behavior on scale { NumberAnimation { duration: 120 } }
                                    }

                                    Text {
                                        id: pillTxt
                                        anchors.centerIn: parent
                                        text: root.formatMoodTitle(modelData.title)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.weight: pillItem.isSelected ? Font.Bold : Font.DemiBold
                                        color: pillItem.isSelected 
                                               ? (homeMoodFlickable.accentLuminance > 0.55 ? "#0f0f11" : "#ffffff") 
                                               : (pillItem.isHovered ? "#ffffff" : Qt.rgba(1.0, 1.0, 1.0, 0.70))
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }

                                    MouseArea {
                                        id: pillMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.selectedMood = modelData.title;
                                            root.moodSelected(modelData.title, modelData.params || "");
                                        }
                                    }
                                }
                            }
                        }

                        function updateActiveIndicator() {
                            for (var i = 0; i < moodRepeater.count; ++i) {
                                var itm = moodRepeater.itemAt(i);
                                if (itm && itm.isSelected) {
                                    activeMoodIndicator.x = itm.x;
                                    activeMoodIndicator.width = itm.width;
                                    return;
                                }
                            }
                        }

                        Component.onCompleted: Qt.callLater(updateActiveIndicator)
                    }

                    Connections {
                        target: root
                        function onSelectedMoodChanged() {
                            homeMoodFlickable.updateActiveIndicator();
                        }
                        function onMoodsChanged() {
                            Qt.callLater(homeMoodFlickable.updateActiveIndicator);
                        }
                    }

                    Connections {
                        target: I18n
                        function onLocaleChanged() {
                            Qt.callLater(homeMoodFlickable.updateActiveIndicator);
                        }
                    }
                }
            }
        }

        // ---------------------------------------------------------------------
        // 2. Footer: Bottom Padding for Floating Player Bar Dock
        // ---------------------------------------------------------------------
        footer: Item {
            width: feedListView.width
            height: 120
        }

        // ---------------------------------------------------------------------
        // 3. Delegate: Virtualized Section Renderer (3-Archetype Architecture)
        // ---------------------------------------------------------------------
        delegate: Item {
            id: secDelegate
            width: feedListView.width
            height: sectionCol.implicitHeight

            property var activeFlickable: {
                if (modelData.type === "video_carousel") return videoFlick;
                if (modelData.type === "track_grid") return trackGridFlick;
                if (modelData.type === "album_carousel" || modelData.type === "card_carousel") return albumFlick;
                return null;
            }

            NumberAnimation {
                id: scrollAnim
                target: null
                property: "contentX"
                duration: 320
                easing.type: Easing.OutCubic
            }

            function scrollBy(delta) {
                if (!activeFlickable) return;
                var maxX = Math.max(0, activeFlickable.contentWidth - activeFlickable.width);
                var targetX = Math.max(0, Math.min(maxX, activeFlickable.contentX + delta));
                scrollAnim.stop();
                scrollAnim.target = activeFlickable;
                scrollAnim.to = targetX;
                scrollAnim.restart();
            }

            ColumnLayout {
                id: sectionCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                spacing: 12

                // --- Section Header Row ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: root.formatSectionSubtitle(modelData.subtitle)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                            color: Theme.textSecondary
                            visible: text.length > 0
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.formatSectionTitle(modelData.title)
                            font.family: Theme.fontFamily
                            font.pixelSize: 22
                            font.bold: true
                            color: Theme.textPrimary
                        }
                    }

                    // Right Controls: Carousel Navigation (< and >) - Standardized NavArrowButton
                    RowLayout {
                        id: arrowNavControls
                        spacing: 8
                        visible: secDelegate.activeFlickable && secDelegate.activeFlickable.contentWidth > secDelegate.activeFlickable.width

                        NavArrowButton {
                            direction: "left"
                            accentColor: root.accentColor
                            btnSize: 32
                            iconSize: 14
                            canScroll: (secDelegate.activeFlickable && secDelegate.activeFlickable.contentX > 2)
                            onClicked: secDelegate.scrollBy(-540)
                        }

                        NavArrowButton {
                            direction: "right"
                            accentColor: root.accentColor
                            btnSize: 32
                            iconSize: 14
                            canScroll: (secDelegate.activeFlickable && secDelegate.activeFlickable.contentX < (secDelegate.activeFlickable.contentWidth - secDelegate.activeFlickable.width - 10))
                            onClicked: secDelegate.scrollBy(540)
                        }
                    }
                }

                // =============================================================
                // Archetype 1: Video Carousel (16:9 Landscape Video Cards - Image 1 & 2)
                // =============================================================
                Flickable {
                    id: videoFlick
                    Layout.fillWidth: true
                    height: 245
                    visible: modelData.type === "video_carousel"
                    contentWidth: videoRow.implicitWidth
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    pixelAligned: true
                    clip: true

                    RowLayout {
                        id: videoRow
                        spacing: 16

                        Repeater {
                            model: modelData.type === "video_carousel" ? modelData.items : []

                            Rectangle {
                                id: vCard
                                width: 260
                                height: 238
                                radius: 10
                                color: vCardMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.05) : "transparent"
                                border.color: vCardMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.15) : "transparent"
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    spacing: 8

                                    // 16:9 Widescreen Artwork Container
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Math.round(width * 9 / 16) // ~142px

                                        Rectangle {
                                            id: vCoverMask
                                            anchors.fill: parent
                                            radius: 10
                                            color: "#ffffff"
                                            visible: false
                                            layer.enabled: true
                                        }

                                        Item {
                                            anchors.fill: parent
                                            layer.enabled: true
                                            layer.effect: MultiEffect {
                                                maskEnabled: true
                                                maskSource: vCoverMask
                                                autoPaddingEnabled: false
                                            }

                                            Image {
                                                id: vCoverImg
                                                anchors.fill: parent
                                                source: {
                                                    var u = modelData.image || "";
                                                    if (u.indexOf("i.ytimg.com") !== -1) return u.split("?")[0];
                                                    if (u.indexOf("googleusercontent.com") !== -1 || u.indexOf("ggpht.com") !== -1) {
                                                        return u.replace(/=w\d+-h\d+[^=]*$/, "=w1280-h720-l90-rj");
                                                    }
                                                    return u;
                                                }
                                                fillMode: Image.PreserveAspectCrop
                                                sourceSize: Qt.size(720, 404)
                                                asynchronous: true
                                                visible: status === Image.Ready
                                                mipmap: true
                                                smooth: true
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                color: "#242428"
                                                visible: vCoverImg.status !== Image.Ready
                                                SequentialAnimation on opacity {
                                                    running: parent.visible
                                                    loops: Animation.Infinite
                                                    NumberAnimation { from: 0.30; to: 0.70; duration: 750; easing.type: Easing.InOutQuad }
                                                    NumberAnimation { from: 0.70; to: 0.30; duration: 750; easing.type: Easing.InOutQuad }
                                                }
                                            }
                                        }

                                        // 1px Subtle Border Overlay
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 10
                                            color: "transparent"
                                            border.color: vCardMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.30) : Qt.rgba(1.0, 1.0, 1.0, 0.10)
                                            border.width: 1
                                            z: 1
                                            Behavior on border.color { ColorAnimation { duration: 120 } }
                                        }

                                        // Centered Play Button (Image 1 & 2)
                                        Rectangle {
                                            width: 44
                                            height: 44
                                            radius: 22
                                            anchors.centerIn: parent
                                            color: Qt.rgba(0, 0, 0, 0.55)
                                            border.color: Qt.rgba(1, 1, 1, 0.25)
                                            border.width: 1
                                            opacity: vCardMouse.containsMouse ? 1.0 : 0.85
                                            scale: vCardMouse.containsMouse ? 1.08 : 1.0
                                            z: 2
                                            Behavior on opacity { NumberAnimation { duration: 120 } }
                                            Behavior on scale { NumberAnimation { duration: 120 } }

                                            readonly property bool isThisTrack: !!(root.currentTrack && modelData && (root.currentTrack.path === modelData.path || (modelData.videoId && root.currentTrack.videoId === modelData.videoId)))
                                            readonly property bool isThisLoading: isThisTrack && root.isLoadingAudio

                                            CircularSpinner {
                                                anchors.centerIn: parent
                                                size: 22
                                                strokeWidth: 2.5
                                                color: "#ffffff"
                                                visible: parent.isThisLoading
                                                running: parent.isThisLoading
                                            }

                                            AppIcon {
                                                anchors.centerIn: parent
                                                anchors.horizontalCenterOffset: 1
                                                visible: !parent.isThisLoading
                                                source: (parent.isThisTrack && root.isPlaying)
                                                        ? "../assets/icons/media-playback-pause-symbolic.svg"
                                                        : "../assets/icons/media-playback-start-symbolic.svg"
                                                iconSize: 20
                                                color: "#ffffff"
                                            }
                                        }
                                    }

                                    // Metadata Text
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        spacing: 3

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.title || modelData.name || ""
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13
                                            font.bold: true
                                            color: (root.currentTrack && root.currentTrack.path === modelData.path) ? root.accentColor : Theme.textPrimary
                                            elide: Text.ElideRight
                                            maximumLineCount: 2
                                            wrapMode: Text.Wrap
                                            lineHeight: 1.15
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.subtitle || ((modelData.artist || "") + (modelData.views ? " • " + modelData.views : "")) || "YouTube Music"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            color: Theme.textSecondary
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }

                                        Item { Layout.fillHeight: true }
                                    }
                                }

                                MouseArea {
                                    id: vCardMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    preventStealing: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: mouse => {
                                        if (mouse.button === Qt.RightButton) {
                                            var pt = vCard.mapToItem(null, mouse.x, mouse.y);
                                            root.trackContextMenuRequested(modelData, pt.x, pt.y);
                                        } else {
                                            root.trackPlayRequested(modelData);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // =============================================================
                // Archetype 2: Multi-row Track Grid (4 Rows per Column - Image 2)
                // =============================================================
                Flickable {
                    id: trackGridFlick
                    Layout.fillWidth: true
                    height: 248
                    visible: modelData.type === "track_grid"
                    contentWidth: trackGridFlow.implicitWidth
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    pixelAligned: true
                    clip: true

                    Grid {
                        id: trackGridFlow
                        rows: 4
                        flow: Grid.TopToBottom
                        rowSpacing: 8
                        columnSpacing: 14

                        Repeater {
                            model: modelData.type === "track_grid" ? modelData.items : []

                            Rectangle {
                                id: gridItem
                                width: Math.max(300, Math.min(380, Math.floor((feedListView.width - 48 - 28) / (root.width > 1100 ? 3 : 2))))
                                height: 54
                                radius: 6
                                clip: true
                                color: (root.currentTrack && root.currentTrack.path === modelData.path)
                                       ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14)
                                       : (rowMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.07) : Qt.rgba(1.0, 1.0, 1.0, 0.02))
                                border.color: (root.currentTrack && root.currentTrack.path === modelData.path)
                                              ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                                              : (rowMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.18) : Qt.rgba(1.0, 1.0, 1.0, 0.06))
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Behavior on border.color { ColorAnimation { duration: 100 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 5
                                    spacing: 10

                                    Item {
                                        width: 44
                                        height: 44

                                        Rectangle {
                                            id: rowImgMask
                                            anchors.fill: parent
                                            radius: 6
                                            color: "#ffffff"
                                            visible: false
                                            layer.enabled: true
                                        }

                                        Item {
                                            anchors.fill: parent
                                            layer.enabled: true
                                            layer.effect: MultiEffect {
                                                maskEnabled: true
                                                maskSource: rowImgMask
                                                autoPaddingEnabled: false
                                            }

                                            Image {
                                                id: rowImg
                                                anchors.fill: parent
                                                source: {
                                                    var u = modelData.image || "";
                                                    if (u.indexOf("i.ytimg.com") !== -1) return u.split("?")[0];
                                                    if (u.indexOf("googleusercontent.com") !== -1 || u.indexOf("ggpht.com") !== -1) {
                                                        return u.replace(/=w\d+-h\d+[^=]*$/, "=w1200-h1200-l90-rj");
                                                    }
                                                    return u;
                                                }
                                                fillMode: Image.PreserveAspectCrop
                                                sourceSize: Qt.size(256, 256)
                                                asynchronous: true
                                                visible: status === Image.Ready
                                                mipmap: true
                                                smooth: true
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                color: "#2c2c34"
                                                visible: rowImg.status !== Image.Ready
                                                SequentialAnimation on opacity {
                                                    running: parent.visible
                                                    loops: Animation.Infinite
                                                    NumberAnimation { from: 0.30; to: 0.70; duration: 750; easing.type: Easing.InOutQuad }
                                                    NumberAnimation { from: 0.70; to: 0.30; duration: 750; easing.type: Easing.InOutQuad }
                                                }
                                            }
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 6
                                            color: Qt.rgba(0, 0, 0, 0.45)
                                            visible: !!(rowMouse.containsMouse || (root.currentTrack && modelData && (root.currentTrack.path === modelData.path || (modelData.videoId && root.currentTrack.videoId === modelData.videoId))))

                                            readonly property bool isThisTrack: !!(root.currentTrack && modelData && (root.currentTrack.path === modelData.path || (modelData.videoId && root.currentTrack.videoId === modelData.videoId)))
                                            readonly property bool isThisLoading: isThisTrack && root.isLoadingAudio

                                            CircularSpinner {
                                                anchors.centerIn: parent
                                                size: 18
                                                strokeWidth: 2.2
                                                color: root.accentColor
                                                visible: parent.isThisLoading
                                                running: parent.isThisLoading
                                            }

                                            AppIcon {
                                                anchors.centerIn: parent
                                                visible: !parent.isThisLoading
                                                source: (parent.isThisTrack && root.isPlaying)
                                                        ? "../assets/icons/media-playback-pause-symbolic.svg"
                                                        : "../assets/icons/media-playback-start-symbolic.svg"
                                                iconSize: 18
                                                color: root.accentColor
                                            }
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 6
                                            color: "transparent"
                                            border.color: Qt.rgba(1, 1, 1, 0.12)
                                            border.width: 1
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.title || modelData.name || ""
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13
                                            font.bold: true
                                            color: (root.currentTrack && root.currentTrack.path === modelData.path) ? root.accentColor : Theme.textPrimary
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: (modelData.subtitle || modelData.artist || "Cloud Stream").split("\n")[0]
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            color: Theme.textSecondary
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }
                                    }
                                }

                                MouseArea {
                                    id: rowMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    preventStealing: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: mouse => {
                                        if (mouse.button === Qt.RightButton) {
                                            var pt = gridItem.mapToItem(null, mouse.x, mouse.y);
                                            root.trackContextMenuRequested(modelData, pt.x, pt.y);
                                        } else {
                                            root.trackPlayRequested(modelData);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // =============================================================
                // Archetype 3: Large Square Album & Playlist Carousel (Image 3)
                // =============================================================
                Flickable {
                    id: albumFlick
                    Layout.fillWidth: true
                    height: 265
                    visible: modelData.type === "album_carousel" || modelData.type === "card_carousel"
                    contentWidth: albumRow.implicitWidth
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    pixelAligned: true
                    clip: true

                    RowLayout {
                        id: albumRow
                        spacing: 16

                        Repeater {
                            model: (modelData.type === "album_carousel" || modelData.type === "card_carousel") ? modelData.items : []

                            Rectangle {
                                id: aCard
                                width: 175
                                height: 255
                                radius: 10
                                color: aCardMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.05) : "transparent"
                                border.color: aCardMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.15) : "transparent"
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    spacing: 8

                                    // 1:1 Large Square Artwork
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: width // 1:1 square! (~167px)

                                        Rectangle {
                                            id: aCoverMask
                                            anchors.fill: parent
                                            radius: 10
                                            color: "#ffffff"
                                            visible: false
                                            layer.enabled: true
                                        }

                                        Item {
                                            anchors.fill: parent
                                            layer.enabled: true
                                            layer.effect: MultiEffect {
                                                maskEnabled: true
                                                maskSource: aCoverMask
                                                autoPaddingEnabled: false
                                            }

                                            Image {
                                                id: aCoverImg
                                                anchors.fill: parent
                                                source: {
                                                    var u = modelData.image || "";
                                                    if (u.indexOf("i.ytimg.com") !== -1) return u.split("?")[0];
                                                    if (u.indexOf("googleusercontent.com") !== -1 || u.indexOf("ggpht.com") !== -1) {
                                                        return u.replace(/=w\d+-h\d+[^=]*$/, "=w1200-h1200-l90-rj");
                                                    }
                                                    return u;
                                                }
                                                fillMode: Image.PreserveAspectCrop
                                                sourceSize: Qt.size(600, 600)
                                                asynchronous: true
                                                visible: status === Image.Ready
                                                mipmap: true
                                                smooth: true
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                color: "#242428"
                                                visible: aCoverImg.status !== Image.Ready
                                                SequentialAnimation on opacity {
                                                    running: parent.visible
                                                    loops: Animation.Infinite
                                                    NumberAnimation { from: 0.30; to: 0.70; duration: 750; easing.type: Easing.InOutQuad }
                                                    NumberAnimation { from: 0.70; to: 0.30; duration: 750; easing.type: Easing.InOutQuad }
                                                }
                                            }
                                        }

                                        // 1px Subtle Border Overlay
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 10
                                            color: "transparent"
                                            border.color: aCardMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.35) : Qt.rgba(1.0, 1.0, 1.0, 0.12)
                                            border.width: 1
                                            z: 1
                                            Behavior on border.color { ColorAnimation { duration: 120 } }
                                        }

                                        // Creator Avatar Badge for Community Playlists (Image 3)
                                        Rectangle {
                                            id: creatorBadge
                                            width: 26
                                            height: 26
                                            radius: 13
                                            anchors.left: parent.left
                                            anchors.bottom: parent.bottom
                                            anchors.margins: 8
                                            z: 2
                                            visible: Boolean(modelData && modelData.creatorInitial && modelData.creatorInitial.length > 0)
                                            color: modelData.creatorColor || "#00bcd4"
                                            border.color: "#121214"
                                            border.width: 2

                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.creatorInitial || ""
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                font.bold: true
                                                color: "#ffffff"
                                            }
                                        }

                                        // Bottom-Right Hover Play Circle
                                        Rectangle {
                                            width: 38
                                            height: 38
                                            radius: 19
                                            color: root.accentColor
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.margins: 8
                                            visible: aCardMouse.containsMouse
                                            scale: aCardMouse.containsMouse ? 1.0 : 0.8
                                            z: 3
                                            Behavior on scale { NumberAnimation { duration: 120 } }

                                            AppIcon {
                                                anchors.centerIn: parent
                                                anchors.horizontalCenterOffset: 1
                                                source: "../assets/icons/media-playback-start-symbolic.svg"
                                                iconSize: 16
                                                color: "#000000"
                                            }
                                        }

                                        // Top-Right Favorite Heart Button
                                        Rectangle {
                                            id: aFavBtn
                                            readonly property string plKey: String((modelData ? (modelData.id || modelData.playlistId || modelData.browseId) : "") || "")
                                            readonly property bool isFav: (typeof win !== "undefined" && win.isPlaylistFavorite && plKey)
                                                                          ? win.isPlaylistFavorite(aFavBtn.plKey)
                                                                          : false
                                            width: 32
                                            height: 32
                                            radius: 16
                                            color: isFav ? Qt.rgba(0, 0, 0, 0.65) : (aFavArea.containsMouse ? Qt.rgba(0, 0, 0, 0.75) : Qt.rgba(0, 0, 0, 0.45))
                                            border.color: isFav ? root.accentColor : Qt.rgba(255, 255, 255, 0.2)
                                            border.width: 1
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: 8
                                            visible: aFavBtn.isFav || aCardMouse.containsMouse
                                            scale: aFavArea.containsMouse ? 1.1 : 1.0
                                            z: 4
                                            Behavior on scale { NumberAnimation { duration: 120 } }
                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            AppIcon {
                                                anchors.centerIn: parent
                                                source: "../assets/icons/emblem-favorite-symbolic.svg"
                                                iconSize: 15
                                                color: aFavBtn.isFav ? root.accentColor : "#ffffff"
                                            }

                                            MouseArea {
                                                id: aFavArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: mouse => {
                                                    mouse.accepted = true;
                                                    if (typeof win !== "undefined" && win.toggleFavoritePlaylist) {
                                                        win.toggleFavoritePlaylist(modelData);
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Text Metadata
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        spacing: 3

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.title || modelData.name || ""
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 14
                                            font.bold: true
                                            color: Theme.textPrimary
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.subtitle || modelData.artist || "Playlist"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            color: Theme.textSecondary
                                            elide: Text.ElideRight
                                            maximumLineCount: 2
                                            wrapMode: Text.Wrap
                                        }

                                        Item { Layout.fillHeight: true }
                                    }
                                }

                                MouseArea {
                                    id: aCardMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    preventStealing: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: mouse => {
                                        if (mouse.button === Qt.RightButton) {
                                            var pt = aCard.mapToItem(null, mouse.x, mouse.y);
                                            root.trackContextMenuRequested(modelData, pt.x, pt.y);
                                        } else {
                                            if (modelData.type === "album" || (modelData.browseId && String(modelData.browseId).startsWith("MPREb_")) || (modelData.playlistId && String(modelData.playlistId).startsWith("MPREb_"))) {
                                                root.playlistSelected(modelData);
                                            } else if (modelData.type === "track" || (modelData.path && modelData.path.indexOf("ytdl://") === 0) || modelData.videoId) {
                                                root.trackPlayRequested(modelData);
                                            } else {
                                                root.playlistSelected(modelData);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // =============================================================
                // Case C: Fallback Quick Picks Grid
                // =============================================================
                GridLayout {
                    Layout.fillWidth: true
                    visible: modelData.type === "fallback_quick_picks"
                    columns: root.width > 900 ? 3 : 2
                    rowSpacing: 8
                    columnSpacing: 12

                    Repeater {
                        model: modelData.type === "fallback_quick_picks" ? modelData.items.slice(0, 18) : []

                        Rectangle {
                            id: qpCard
                            Layout.fillWidth: true
                            height: 56
                            radius: 6
                            clip: true
                            color: (root.currentTrack && root.currentTrack.path === modelData.path)
                                   ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
                                   : (qpMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.07) : Qt.rgba(1.0, 1.0, 1.0, 0.02))
                            border.color: (root.currentTrack && root.currentTrack.path === modelData.path)
                                          ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                                          : (qpMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.18) : Qt.rgba(1.0, 1.0, 1.0, 0.06))
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 100 } }
                            Behavior on border.color { ColorAnimation { duration: 100 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 12

                                Rectangle {
                                    width: 44
                                    height: 44
                                    radius: 4
                                    color: "#282828"
                                    clip: true

                                    Image {
                                        id: qpImg
                                        anchors.fill: parent
                                        source: modelData.image || ""
                                        fillMode: Image.PreserveAspectCrop
                                        sourceSize: Qt.size(64, 64)
                                        asynchronous: true
                                        visible: status === Image.Ready
                                    }

                                    // Skeleton Pulsing Shimmer Placeholder
                                    Rectangle {
                                        anchors.fill: parent
                                        color: "#2c2c34"
                                        visible: qpImg.status !== Image.Ready
                                        SequentialAnimation on opacity {
                                            running: parent.visible
                                            loops: Animation.Infinite
                                            NumberAnimation { from: 0.30; to: 0.70; duration: 750; easing.type: Easing.InOutQuad }
                                            NumberAnimation { from: 0.70; to: 0.30; duration: 750; easing.type: Easing.InOutQuad }
                                        }
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        color: Qt.rgba(0, 0, 0, 0.4)
                                        visible: qpMouse.containsMouse || (root.currentTrack && modelData && (root.currentTrack.path === modelData.path || (modelData.videoId && root.currentTrack.videoId === modelData.videoId)))

                                        readonly property bool isThisTrack: !!(root.currentTrack && modelData && (root.currentTrack.path === modelData.path || (modelData.videoId && root.currentTrack.videoId === modelData.videoId)))
                                        readonly property bool isThisLoading: isThisTrack && root.isLoadingAudio

                                        CircularSpinner {
                                            anchors.centerIn: parent
                                            size: 18
                                            strokeWidth: 2.2
                                            color: root.accentColor
                                            visible: parent.isThisLoading
                                            running: parent.isThisLoading
                                        }

                                        AppIcon {
                                            anchors.centerIn: parent
                                            visible: !parent.isThisLoading
                                            source: (parent.isThisTrack && root.isPlaying)
                                                    ? "../assets/icons/media-playback-pause-symbolic.svg"
                                                    : "../assets/icons/media-playback-start-symbolic.svg"
                                            iconSize: 18
                                            color: root.accentColor
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.title || modelData.name || ""
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: (root.currentTrack && root.currentTrack.path === modelData.path) ? root.accentColor : Theme.textPrimary
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: (modelData.artist || "Cloud Stream").split("\n")[0]
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: Theme.textSecondary
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }
                                }
                            }

                            MouseArea {
                                id: qpMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) {
                                        var pt = qpCard.mapToItem(null, mouse.x, mouse.y);
                                        root.trackContextMenuRequested(modelData, pt.x, pt.y);
                                    } else {
                                        root.trackPlayRequested(modelData);
                                    }
                                }
                            }
                        }
                    }
                }

                // =============================================================
                // Case D: Fallback Featured Playlists Flow
                // =============================================================
                Flow {
                    Layout.fillWidth: true
                    spacing: 16
                    visible: modelData.type === "fallback_playlists"

                    Repeater {
                        model: modelData.type === "fallback_playlists" ? modelData.items : []

                        Rectangle {
                            width: 172
                            height: 240
                            radius: Theme.radiusCard
                            color: plMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.06) : Qt.rgba(1.0, 1.0, 1.0, 0.02)
                            border.color: plMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.18) : Qt.rgba(1.0, 1.0, 1.0, 0.06)
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: width
                                    radius: 6
                                    color: "#282828"
                                    clip: true

                                    Image {
                                        id: plImg
                                        anchors.fill: parent
                                        source: modelData.image || ""
                                        fillMode: Image.PreserveAspectCrop
                                        sourceSize: Qt.size(200, 200)
                                        asynchronous: true
                                        visible: status === Image.Ready
                                    }

                                    // Skeleton Pulsing Shimmer Placeholder
                                    Rectangle {
                                        anchors.fill: parent
                                        color: "#2c2c34"
                                        visible: plImg.status !== Image.Ready
                                        SequentialAnimation on opacity {
                                            running: parent.visible
                                            loops: Animation.Infinite
                                            NumberAnimation { from: 0.30; to: 0.70; duration: 750; easing.type: Easing.InOutQuad }
                                            NumberAnimation { from: 0.70; to: 0.30; duration: 750; easing.type: Easing.InOutQuad }
                                        }
                                    }

                                    Rectangle {
                                        width: 40
                                        height: 40
                                        radius: 20
                                        color: root.accentColor
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 8
                                        visible: plMouse.containsMouse

                                        AppIcon {
                                            anchors.centerIn: parent
                                            anchors.horizontalCenterOffset: 1
                                            source: "../assets/icons/media-playback-start-symbolic.svg"
                                            iconSize: 18
                                            color: "#000000"
                                        }
                                    }

                                    // Top-Right Favorite Heart Button
                                    Rectangle {
                                        id: dFavBtn
                                        readonly property string plKey: String((modelData ? (modelData.id || modelData.playlistId || modelData.browseId) : "") || "")
                                        readonly property bool isFav: (typeof win !== "undefined" && win.isPlaylistFavorite && plKey)
                                                                      ? win.isPlaylistFavorite(dFavBtn.plKey)
                                                                      : false
                                        width: 32
                                        height: 32
                                        radius: 16
                                        color: isFav ? Qt.rgba(0, 0, 0, 0.65) : (dFavArea.containsMouse ? Qt.rgba(0, 0, 0, 0.75) : Qt.rgba(0, 0, 0, 0.45))
                                        border.color: isFav ? root.accentColor : Qt.rgba(255, 255, 255, 0.2)
                                        border.width: 1
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 8
                                        visible: dFavBtn.isFav || plMouse.containsMouse
                                        scale: dFavArea.containsMouse ? 1.1 : 1.0
                                        z: 4
                                        Behavior on scale { NumberAnimation { duration: 120 } }
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        AppIcon {
                                            anchors.centerIn: parent
                                            source: "../assets/icons/emblem-favorite-symbolic.svg"
                                            iconSize: 15
                                            color: dFavBtn.isFav ? root.accentColor : "#ffffff"
                                        }

                                        MouseArea {
                                            id: dFavArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: mouse => {
                                                mouse.accepted = true;
                                                if (typeof win !== "undefined" && win.toggleFavoritePlaylist) {
                                                    win.toggleFavoritePlaylist(modelData);
                                                }
                                            }
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.title || ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.bold: true
                                    color: Theme.textPrimary
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.subtitle || "Playlist"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Theme.textSecondary
                                    elide: Text.ElideRight
                                    maximumLineCount: 2
                                    wrapMode: Text.Wrap
                                }

                                Item { Layout.fillHeight: true }
                            }

                            MouseArea {
                                id: plMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.playlistSelected(modelData)
                            }
                        }
                    }
                }

                // =============================================================
                // Case E: Skeleton Placeholder Row (Initial Loading State)
                // =============================================================
                Flickable {
                    Layout.fillWidth: true
                    height: 250
                    visible: modelData.type === "skeleton_section"
                    contentWidth: skelRow.implicitWidth
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    clip: true
                    interactive: false

                    RowLayout {
                        id: skelRow
                        spacing: 16

                        Repeater {
                            model: [
                                { tw: 120, sw: 80 },
                                { tw: 140, sw: 95 },
                                { tw: 110, sw: 75 },
                                { tw: 130, sw: 85 },
                                { tw: 125, sw: 90 },
                                { tw: 135, sw: 80 }
                            ]

                            SkeletonTrackCard {
                                width: 160
                                height: 230
                                titleWidth: modelData.tw
                                subtitleWidth: modelData.sw
                            }
                        }
                    }
                }

                Item { height: 16 }
            }
        }
    }
}
