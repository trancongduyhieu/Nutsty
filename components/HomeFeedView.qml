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
    property bool isMoodIslandExpanded: false

    readonly property var activeMoodList: (root.moods && root.moods.length > 0) ? root.moods : [
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

    // Staggered Cascade Animation & Seen State Cache (Mochy-Music RevealSeenState)
    property var seenKeys: ({})
    function hasSeen(key) {
        if (!key) return false;
        return !!root.seenKeys[key];
    }
    function markSeen(key) {
        if (!key) return;
        if (!root.seenKeys[key]) {
            root.seenKeys[key] = true;
        }
    }
    function clearSeen() {
        root.seenKeys = ({});
    }

    onSelectedMoodChanged: {
        root.clearSeen();
        // If switching to an uncached mood that has no sections yet, reset reveal state to show clean skeleton wave
        var hasData = (root.sections && root.sections.length > 0);
        if (!hasData) {
            root.hasInitialLoaded = false;
            root.skeletonOpacity = 1.0;
        }
    }
    onSectionsChanged: {
        root.clearSeen();
        checkRevealTrigger();
    }
    onQuickPicksChanged: {
        root.clearSeen();
        checkRevealTrigger();
    }
    onFeaturedPlaylistsChanged: {
        root.clearSeen();
        checkRevealTrigger();
    }

    // RevealWhenLoaded (Mochy-Music 3-Beat Staggered Transition & In-Place Swap)
    property bool hasInitialLoaded: false
    property real skeletonOpacity: 1.0

    SequentialAnimation {
        id: revealWhenLoadedAnim
        // Nhịp 1: Khung xương BonesHost mờ dần (opacity -> 0 trong 200ms)
        NumberAnimation {
            target: root
            property: "skeletonOpacity"
            to: 0.0
            duration: 200
            easing.type: Easing.OutQuad
        }
        // Nhịp 2: Khoảng đệm quang học ngắn 50ms
        PauseAnimation {
            duration: 50
        }
        // Nhịp 3: Chuyển cờ hasInitialLoaded = true -> Dữ liệu thật xuất hiện với Staggered Cascade
        ScriptAction {
            script: {
                root.hasInitialLoaded = true;
                root.skeletonOpacity = 1.0;
            }
        }
    }

    function checkRevealTrigger() {
        if (!root.hasInitialLoaded && !revealWhenLoadedAnim.running) {
            var hasData = (root.sections && root.sections.length > 0) ||
                          (root.selectedMood === "All" && ((root.quickPicks && root.quickPicks.length > 0) || (root.featuredPlaylists && root.featuredPlaylists.length > 0)));
            if (!root.isLoading && hasData) {
                revealWhenLoadedAnim.restart();
            }
        }
    }

    onIsLoadingChanged: checkRevealTrigger()
    Component.onCompleted: checkRevealTrigger()

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

    function toggleMoodIsland() {
        root.isMoodIslandExpanded = !root.isMoodIslandExpanded;
        console.log("[DynamicMoodIsland] toggleMoodIsland: isExpanded =", root.isMoodIslandExpanded);
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

    function chunkArray(arr, size) {
        if (!arr || !arr.length) return [];
        var res = [];
        for (var i = 0; i < arr.length; i += size) {
            res.push(arr.slice(i, i + size));
        }
        return res;
    }

    // Dynamic feed sections model with 3-beat RevealWhenLoaded & In-Place Swap
    readonly property var activeFeedSections: {
        // 1. If real sections exist and reveal is ready, return real sections
        if (root.sections && root.sections.length > 0 && root.hasInitialLoaded) {
            return root.sections;
        }

        // 2. Fallbacks: ONLY for "All" when not loading (e.g. offline cache)
        if (root.selectedMood === "All" && !root.isLoading && root.hasInitialLoaded) {
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
                    title: I18n.tr("Danh sách phát nổi bật cho bạn", "Featured playlists for you"),
                    items: root.featuredPlaylists
                });
            }
            if (fallbacks.length > 0) return fallbacks;
        }

        // 3. Loading state (Initial boot or uncached mood fetch): BonesHost Skeleton Wave
        return [
            {
                type: "skeleton_section",
                title: root.selectedMood === "All" ? I18n.tr("Được đề xuất cho bạn", "Recommended for you") : root.formatMoodTitle(root.selectedMood),
                subtitle: I18n.tr("ĐANG TẢI", "LOADING"),
                items: [1, 2, 3, 4, 5, 6]
            },
            {
                type: "skeleton_section",
                title: I18n.tr("Nghe lại", "Listen again"),
                subtitle: I18n.tr("KHÁM PHÁ", "DISCOVER"),
                items: [1, 2, 3, 4, 5, 6]
            }
        ];
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
        cacheBuffer: 260
        reuseItems: true
        model: root.activeFeedSections

        onContentYChanged: {
            if (typeof win !== "undefined" && win && typeof win.triggerBackdropUpdate === "function") {
                win.triggerBackdropUpdate();
            }
        }

        ScrollBar.vertical: LiquidScrollBar {
            backgroundSourceItem: root.backgroundSourceItem
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
                anchors.topMargin: 12
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                spacing: 16

                // 1. Dynamic Island Mood Dock: Positioned under top navigation icons and above Greeting
                Item {
                    id: moodDockContainer
                    Layout.fillWidth: true
                    height: 38
                    z: 20

                    // Ambient drop shadow for the Dynamic Island
                    Rectangle {
                        anchors.horizontalCenter: dynamicMoodIsland.horizontalCenter
                        anchors.verticalCenter: dynamicMoodIsland.verticalCenter
                        anchors.verticalCenterOffset: 2
                        width: dynamicMoodIsland.width
                        height: dynamicMoodIsland.height
                        radius: dynamicMoodIsland.radius
                        color: "#55000000"
                        visible: dynamicMoodIsland.width > 0
                        z: 1
                        Behavior on width {
                            NumberAnimation {
                                duration: 320
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: [0.08, 0.72, 0.15, 1.0]
                            }
                        }
                    }

                    // Main Dynamic Island Morphing Capsule
                    Rectangle {
                        id: dynamicMoodIsland
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        height: 34
                        radius: 17
                        z: 2
                        clip: true
                        readonly property bool isExpanded: root.isMoodIslandExpanded
                        readonly property real compactWidth: compactTxt.implicitWidth + 28
                        readonly property real expandedTargetWidth: Math.min(moodDockContainer.width, moodRow.width + 24)
                        width: isExpanded ? expandedTargetWidth : compactWidth

                        Behavior on width {
                            NumberAnimation {
                                duration: 320
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: [0.08, 0.72, 0.15, 1.0]
                            }
                        }

                        // Background & Border Morph: Vibrant Accent Pill when idle, Refined Dark Glass Dock when expanded
                        color: isExpanded 
                            ? Qt.rgba(0.08, 0.08, 0.10, 0.82) 
                            : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.95)
                        border.width: 1
                        border.color: isExpanded 
                            ? Qt.rgba(1.0, 1.0, 1.0, 0.14) 
                            : Qt.rgba(root.accentColor.r * 1.15, root.accentColor.g * 1.15, root.accentColor.b * 1.15, 0.95)

                        Behavior on color { ColorAnimation { duration: 240 } }
                        Behavior on border.color { ColorAnimation { duration: 240 } }

                        // Micro-interaction scale affordance when hovering over collapsed island
                        scale: (!isExpanded && compactMouse.containsMouse) ? 1.05 : 1.0
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }

                        // Inner Specular Rim (Tension highlight)
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: 16
                            color: "transparent"
                            border.color: Qt.rgba(1.0, 1.0, 1.0, dynamicMoodIsland.isExpanded ? 0.08 : (homeMoodFlickable.accentLuminance > 0.55 ? 0.35 : 0.22))
                            border.width: 1
                            Behavior on border.color { ColorAnimation { duration: 200 } }
                        }

                        // -------------------------------------------------------------
                        // Layer 1: Compact View (Single Active Mood Pill in Center)
                        // -------------------------------------------------------------
                        Text {
                            id: compactTxt
                            anchors.centerIn: parent
                            text: root.formatMoodTitle(root.selectedMood)
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                            color: homeMoodFlickable.accentLuminance > 0.55 ? "#0f0f11" : "#ffffff"
                            visible: opacity > 0.01
                            opacity: dynamicMoodIsland.isExpanded ? 0.0 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                        }

                        MouseArea {
                            id: compactMouse
                            anchors.fill: parent
                            enabled: !dynamicMoodIsland.isExpanded
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.isMoodIslandExpanded = true;
                                autoCollapseTimer.restart();
                            }
                        }

                        // -------------------------------------------------------------
                        // Layer 2: Expanded View (Full Moods Palette with Liquid Tint Glass)
                        // -------------------------------------------------------------
                        Flickable {
                            id: homeMoodFlickable
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            contentWidth: moodRow.width + 8
                            contentHeight: height
                            boundsBehavior: Flickable.StopAtBounds
                            flickableDirection: Flickable.HorizontalFlick
                            pixelAligned: true
                            clip: true
                            interactive: contentWidth > width
                            visible: opacity > 0.01
                            opacity: dynamicMoodIsland.isExpanded ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 200 } }

                            readonly property real accentLuminance: (0.299 * root.accentColor.r + 0.587 * root.accentColor.g + 0.114 * root.accentColor.b)

                            // Sliding Keo 502 Glossy Gel Capsule
                            Rectangle {
                                id: activeMoodIndicator
                                height: 26
                                radius: 13
                                y: (homeMoodFlickable.height - height) / 2
                                z: 2
                                color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.95)
                                border.color: Qt.rgba(1.0, 1.0, 1.0, 0.45)
                                border.width: 1
                                visible: width > 0

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    radius: 12
                                    color: "transparent"
                                    border.color: Qt.rgba(1.0, 1.0, 1.0, homeMoodFlickable.accentLuminance > 0.55 ? 0.35 : 0.25)
                                    border.width: 1
                                }

                                Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            }

                            Row {
                                id: moodRow
                                spacing: (moodDockContainer.width < 820) ? 5 : 7
                                anchors.verticalCenter: parent.verticalCenter
                                x: Math.max(4, (homeMoodFlickable.width - width) / 2)
                                z: 5
                                onWidthChanged: Qt.callLater(homeMoodFlickable.updateActiveIndicator)

                                Repeater {
                                    id: moodRepeater
                                    model: root.activeMoodList

                                    delegate: Item {
                                        id: pillItem
                                        height: 26
                                        width: pillTxt.implicitWidth + 14
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

                                        // Refined Dark Glass Pill Frame (Matching reference image)
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 13
                                            color: pillItem.isHovered 
                                                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20) 
                                                : Qt.rgba(0.16, 0.16, 0.19, 0.85)
                                            border.width: 1
                                            border.color: pillItem.isHovered 
                                                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45) 
                                                : Qt.rgba(1.0, 1.0, 1.0, 0.08)
                                            opacity: pillItem.isSelected ? 0.0 : 1.0
                                            scale: (pillItem.isHovered && !pillItem.isSelected) ? 1.04 : 1.0

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
                                            font.pixelSize: 11
                                            font.weight: pillItem.isSelected ? Font.Bold : Font.DemiBold
                                            color: pillItem.isSelected 
                                                   ? (homeMoodFlickable.accentLuminance > 0.55 ? "#0f0f11" : "#ffffff") 
                                                   : (pillItem.isHovered ? "#ffffff" : Qt.rgba(0.92, 0.92, 0.94, 0.90))
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
                                                root.isMoodIslandExpanded = false;
                                            }
                                            onPositionChanged: autoCollapseTimer.restart()
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

                        // Optical Edge Fade Overlays (Smooth transition at scroll edges)
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 28
                            z: 10
                            visible: dynamicMoodIsland.isExpanded && homeMoodFlickable.contentWidth > homeMoodFlickable.width && homeMoodFlickable.contentX > 4
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: dynamicMoodIsland.color }
                                GradientStop { position: 1.0; color: "transparent" }
                            }
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 28
                            z: 10
                            visible: dynamicMoodIsland.isExpanded && homeMoodFlickable.contentWidth > homeMoodFlickable.width && (homeMoodFlickable.contentX < homeMoodFlickable.contentWidth - homeMoodFlickable.width - 4)
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 1.0; color: dynamicMoodIsland.color }
                            }
                        }

                        // Smart Auto-Collapse Timer: 4500ms idle timer
                        Timer {
                            id: autoCollapseTimer
                            interval: 4500
                            repeat: false
                            running: false
                            onTriggered: {
                                if (root.isMoodIslandExpanded) {
                                    root.isMoodIslandExpanded = false;
                                }
                            }
                        }

                        Connections {
                            target: root
                            function onIsMoodIslandExpandedChanged() {
                                if (root.isMoodIslandExpanded) {
                                    autoCollapseTimer.restart();
                                    homeMoodFlickable.updateActiveIndicator();
                                } else {
                                    autoCollapseTimer.stop();
                                }
                            }
                        }
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

                    // Auto-collapse when user scrolls the feed
                    Connections {
                        target: feedListView
                        function onContentYChanged() {
                            if (root.isMoodIslandExpanded) {
                                root.isMoodIslandExpanded = false;
                            }
                        }
                    }
                }

                // 2. Greeting Text
                Text {
                    text: root.getGreeting()
                    font.family: Theme.fontFamily
                    font.pixelSize: 28
                    font.bold: true
                    color: Theme.textPrimary
                }

                // 3. Friends Pulse: 24h Ephemeral Music Notes Bar (Stories Style)
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

            readonly property var sectionData: modelData

            // Responsive Metric Engine: Flush-fit 100% width, zero edge gaps ("không thiếu không dư")
            readonly property real availableWidth: Math.max(300, secDelegate.width - 48)

            // Video Carousel (16:9 Landscape cards - "Nghe lại")
            readonly property int cardVideoCount: Math.max(2, Math.round((availableWidth + 16) / (250 + 16)))
            property real cardVideoWidth: (availableWidth - (cardVideoCount - 1) * 16) / cardVideoCount
            Behavior on cardVideoWidth { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
            property real cardVideoHeight: Math.round((cardVideoWidth - 8) * 9 / 16) + 78
            Behavior on cardVideoHeight { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

            // Square Carousel (1:1 Album/Playlist cards)
            readonly property int cardSquareCount: Math.max(3, Math.round((availableWidth + 16) / (172 + 16)))
            property real cardSquareWidth: (availableWidth - (cardSquareCount - 1) * 16) / cardSquareCount
            Behavior on cardSquareWidth { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
            property real cardSquareHeight: Math.round(cardSquareWidth - 8) + 78
            Behavior on cardSquareHeight { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

            // Multi-row Track Grid (4 rows per column)
            readonly property int cardGridColCount: Math.max(1, Math.round((availableWidth + 14) / (320 + 14)))
            property real cardGridColWidth: (availableWidth - (cardGridColCount - 1) * 14) / cardGridColCount
            Behavior on cardGridColWidth { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
            readonly property real cardGridColHeight: 240

            property var activeFlickable: {
                if (!sectionData) return null;
                if (sectionData.type === "video_carousel") return videoFlick;
                if (sectionData.type === "track_grid") return trackGridFlick;
                if (sectionData.type === "album_carousel" || sectionData.type === "card_carousel") return albumFlick;
                if (sectionData.type === "fallback_quick_picks") return fallbackQuickPicksFlick;
                if (sectionData.type === "fallback_playlists") return fallbackPlaylistFlick;
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
                    opacity: (secDelegate.sectionData && secDelegate.sectionData.type === "skeleton_section") ? root.skeletonOpacity : 1.0

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: root.formatSectionSubtitle(secDelegate.sectionData ? secDelegate.sectionData.subtitle : "")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                            color: Theme.textSecondary
                            visible: text.length > 0
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.formatSectionTitle(secDelegate.sectionData ? secDelegate.sectionData.title : "")
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
                            onClicked: {
                                var spacing = (secDelegate.sectionData && (secDelegate.sectionData.type === "track_grid" || secDelegate.sectionData.type === "fallback_quick_picks")) ? 14 : 16;
                                var cardStep = (secDelegate.sectionData && secDelegate.sectionData.type === "video_carousel") ? (secDelegate.cardVideoWidth + spacing) : ((secDelegate.sectionData && (secDelegate.sectionData.type === "track_grid" || secDelegate.sectionData.type === "fallback_quick_picks")) ? (secDelegate.cardGridColWidth + spacing) : (secDelegate.cardSquareWidth + spacing));
                                var step = secDelegate.activeFlickable ? (Math.max(1, Math.round((secDelegate.activeFlickable.width + spacing) / cardStep)) * cardStep) : 564;
                                secDelegate.scrollBy(-step);
                            }
                        }

                        NavArrowButton {
                            direction: "right"
                            accentColor: root.accentColor
                            btnSize: 32
                            iconSize: 14
                            canScroll: (secDelegate.activeFlickable && secDelegate.activeFlickable.contentX < (secDelegate.activeFlickable.contentWidth - secDelegate.activeFlickable.width - 10))
                            onClicked: {
                                var spacing = (secDelegate.sectionData && (secDelegate.sectionData.type === "track_grid" || secDelegate.sectionData.type === "fallback_quick_picks")) ? 14 : 16;
                                var cardStep = (secDelegate.sectionData && secDelegate.sectionData.type === "video_carousel") ? (secDelegate.cardVideoWidth + spacing) : ((secDelegate.sectionData && (secDelegate.sectionData.type === "track_grid" || secDelegate.sectionData.type === "fallback_quick_picks")) ? (secDelegate.cardGridColWidth + spacing) : (secDelegate.cardSquareWidth + spacing));
                                var step = secDelegate.activeFlickable ? (Math.max(1, Math.round((secDelegate.activeFlickable.width + spacing) / cardStep)) * cardStep) : 564;
                                secDelegate.scrollBy(step);
                            }
                        }
                    }
                }

                // =============================================================
                // Archetype 1: Video Carousel (16:9 Landscape Video Cards - Image 1 & 2)
                // =============================================================
                ListView {
                    id: videoFlick
                    Layout.fillWidth: true
                    height: secDelegate.cardVideoHeight + 8
                    visible: secDelegate.sectionData && secDelegate.sectionData.type === "video_carousel"
                    orientation: ListView.Horizontal
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    snapMode: ListView.SnapToItem
                    pixelAligned: true
                    reuseItems: true
                    cacheBuffer: 160
                    clip: true
                    spacing: 16
                    model: (secDelegate.sectionData && secDelegate.sectionData.type === "video_carousel") ? (secDelegate.sectionData.items || []) : []

                    delegate: Rectangle {
                        id: vCard
                        width: secDelegate.cardVideoWidth
                        height: secDelegate.cardVideoHeight
                        radius: 10
                        clip: true
                        color: vCardMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.05) : "transparent"
                        border.color: vCardMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.15) : "transparent"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        property real revealOpacity: 1.0

                        opacity: revealOpacity
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                        readonly property string itemKey: String((modelData ? (modelData.videoId || modelData.path || modelData.title) : "") || "")
                        property string lastCheckedKey: ""
                        readonly property int staggerIndex: index
                        transform: Translate { id: vTrans; y: 0 }

                        function checkReveal() {
                            if (!itemKey) {
                                vRevealAnim.stop();
                                revealOpacity = 1.0;
                                vTrans.y = 0;
                                return;
                            }
                            if (itemKey === lastCheckedKey) return;
                            lastCheckedKey = itemKey;

                            if (root.hasSeen(itemKey) || root.hasInitialLoaded) {
                                vRevealAnim.stop();
                                revealOpacity = 1.0;
                                vTrans.y = 0;
                            } else {
                                root.markSeen(itemKey);
                                revealOpacity = 0.0;
                                vTrans.y = 14;
                                vRevealAnim.restart();
                            }
                        }

                        onItemKeyChanged: checkReveal()
                        Component.onCompleted: checkReveal()

                        Connections {
                            target: root
                            function onSeenKeysChanged() {
                                if (!root.hasInitialLoaded) {
                                    vCard.lastCheckedKey = "";
                                    vCard.checkReveal();
                                }
                            }
                        }

                        SequentialAnimation {
                            id: vRevealAnim
                            PauseAnimation { duration: Math.max(0, (vCard.staggerIndex % 8) * 35) }
                            ParallelAnimation {
                                NumberAnimation {
                                    target: vCard
                                    property: "revealOpacity"
                                    from: 0.0
                                    to: 1.0
                                    duration: 260
                                    easing.type: Easing.OutCubic
                                }
                                NumberAnimation {
                                    target: vTrans
                                    property: "y"
                                    from: 14
                                    to: 0
                                    duration: 260
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 8

                            // 16:9 Widescreen Artwork Container
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.round(width * 9 / 16) // ~142px

                                RoundedImage {
                                    id: vCoverImg
                                    anchors.fill: parent
                                    radius: 10
                                    source: {
                                        var u = modelData.image || "";
                                        if (u.indexOf("i.ytimg.com") !== -1) return u.split("?")[0];
                                        if (u.indexOf("googleusercontent.com") !== -1 || u.indexOf("ggpht.com") !== -1) {
                                            return u.replace(/=w\d+-h\d+[^=]*$/, "=w540-h304-l90-rj");
                                        }
                                        return u;
                                    }
                                    fillMode: Image.PreserveAspectCrop
                                    autoCropBlackBars: false
                                    sourceSize: Qt.size(360, 202)
                                    asynchronous: true
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

                // =============================================================
                // Archetype 2: Multi-row Track Grid (4 Rows per Column - Image 2)
                // =============================================================
                ListView {
                    id: trackGridFlick
                    Layout.fillWidth: true
                    height: 248
                    visible: secDelegate.sectionData && secDelegate.sectionData.type === "track_grid"
                    orientation: ListView.Horizontal
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    snapMode: ListView.SnapToItem
                    pixelAligned: true
                    reuseItems: true
                    cacheBuffer: 160
                    clip: true
                    spacing: 14
                    model: (secDelegate.sectionData && secDelegate.sectionData.type === "track_grid") ? root.chunkArray(secDelegate.sectionData.items, 4) : []

                    delegate: Item {
                        id: colWrapper
                        width: secDelegate.cardGridColWidth
                        height: secDelegate.cardGridColHeight
                        readonly property var chunkTracks: modelData

                        opacity: 1.0

                        Column {
                            anchors.fill: parent
                            spacing: 8

                            Repeater {
                                model: colWrapper.chunkTracks

                                Rectangle {
                                    id: gridItem
                                    width: colWrapper.width
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

                                    readonly property string itemKey: String((modelData ? (modelData.videoId || modelData.path || modelData.title) : "") || "")
                                    property string lastCheckedKey: ""
                                    readonly property int staggerIndex: colWrapper.index * 4 + index
                                    transform: Translate { id: gridTrans; y: 0 }

                                    function checkReveal() {
                                        if (!itemKey) {
                                            gridRevealAnim.stop();
                                            opacity = 1.0;
                                            gridTrans.y = 0;
                                            return;
                                        }
                                        if (itemKey === lastCheckedKey) return;
                                        lastCheckedKey = itemKey;

                                        if (root.hasSeen(itemKey) || root.hasInitialLoaded) {
                                            gridRevealAnim.stop();
                                            opacity = 1.0;
                                            gridTrans.y = 0;
                                        } else {
                                            root.markSeen(itemKey);
                                            opacity = 0.0;
                                            gridTrans.y = 14;
                                            gridRevealAnim.restart();
                                        }
                                    }

                                    onItemKeyChanged: checkReveal()
                                    Component.onCompleted: checkReveal()

                                    Connections {
                                        target: root
                                        function onSeenKeysChanged() {
                                            if (!root.hasInitialLoaded) {
                                                gridItem.lastCheckedKey = "";
                                                gridItem.checkReveal();
                                            }
                                        }
                                    }

                                    SequentialAnimation {
                                        id: gridRevealAnim
                                        PauseAnimation { duration: Math.max(0, (gridItem.staggerIndex % 8) * 35) }
                                        ParallelAnimation {
                                            NumberAnimation {
                                                target: gridItem
                                                property: "opacity"
                                                from: 0.0
                                                to: 1.0
                                                duration: 260
                                                easing.type: Easing.OutCubic
                                            }
                                            NumberAnimation {
                                                target: gridTrans
                                                property: "y"
                                                from: 14
                                                to: 0
                                                duration: 260
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 5
                                        spacing: 10

                                        Item {
                                            width: 44
                                            height: 44

                                            RoundedImage {
                                                id: rowImg
                                                anchors.fill: parent
                                                radius: 6
                                                source: {
                                                    var u = modelData.image || "";
                                                    if (u.indexOf("i.ytimg.com") !== -1) return u.split("?")[0];
                                                    if (u.indexOf("googleusercontent.com") !== -1 || u.indexOf("ggpht.com") !== -1) {
                                                        return u.replace(/=w\d+-h\d+[^=]*$/, "=w120-h120-l90-rj");
                                                    }
                                                    return u;
                                                }
                                                fillMode: Image.PreserveAspectCrop
                                                sourceSize: Qt.size(88, 88)
                                                asynchronous: true
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
                }

                // =============================================================
                // Archetype 3: Large Square Album & Playlist Carousel (Image 3)
                // =============================================================
                ListView {
                    id: albumFlick
                    Layout.fillWidth: true
                    height: secDelegate.cardSquareHeight + 8
                    visible: secDelegate.sectionData && (secDelegate.sectionData.type === "album_carousel" || secDelegate.sectionData.type === "card_carousel")
                    orientation: ListView.Horizontal
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    snapMode: ListView.SnapToItem
                    pixelAligned: true
                    reuseItems: true
                    cacheBuffer: 160
                    clip: true
                    spacing: 16
                    model: (secDelegate.sectionData && (secDelegate.sectionData.type === "album_carousel" || secDelegate.sectionData.type === "card_carousel")) ? (secDelegate.sectionData.items || []) : []

                    delegate: Rectangle {
                        id: aCard
                        width: secDelegate.cardSquareWidth
                        height: secDelegate.cardSquareHeight
                        radius: 10
                        clip: true
                        color: aCardMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.05) : "transparent"
                        border.color: aCardMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.15) : "transparent"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        property real revealOpacity: 1.0

                        opacity: revealOpacity
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                        readonly property string itemKey: String((modelData ? (modelData.browseId || modelData.playlistId || modelData.id || modelData.title) : "") || "")
                        property string lastCheckedKey: ""
                        readonly property int staggerIndex: index
                        transform: Translate { id: aTrans; y: 0 }

                        function checkReveal() {
                            if (!itemKey) {
                                aRevealAnim.stop();
                                revealOpacity = 1.0;
                                aTrans.y = 0;
                                return;
                            }
                            if (itemKey === lastCheckedKey) return;
                            lastCheckedKey = itemKey;

                            if (root.hasSeen(itemKey) || root.hasInitialLoaded) {
                                aRevealAnim.stop();
                                revealOpacity = 1.0;
                                aTrans.y = 0;
                            } else {
                                root.markSeen(itemKey);
                                revealOpacity = 0.0;
                                aTrans.y = 14;
                                aRevealAnim.restart();
                            }
                        }

                        onItemKeyChanged: checkReveal()
                        Component.onCompleted: checkReveal()

                        Connections {
                            target: root
                            function onSeenKeysChanged() {
                                if (!root.hasInitialLoaded) {
                                    aCard.lastCheckedKey = "";
                                    aCard.checkReveal();
                                }
                            }
                        }

                        SequentialAnimation {
                            id: aRevealAnim
                            PauseAnimation { duration: Math.max(0, (aCard.staggerIndex % 8) * 35) }
                            ParallelAnimation {
                                NumberAnimation {
                                    target: aCard
                                    property: "revealOpacity"
                                    from: 0.0
                                    to: 1.0
                                    duration: 260
                                    easing.type: Easing.OutCubic
                                }
                                NumberAnimation {
                                    target: aTrans
                                    property: "y"
                                    from: 14
                                    to: 0
                                    duration: 260
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 8

                            // 1:1 Large Square Artwork
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: width // 1:1 square! (~167px)

                                RoundedImage {
                                    id: aCoverImg
                                    anchors.fill: parent
                                    radius: 10
                                    source: {
                                        var u = modelData.image || "";
                                        if (u.indexOf("i.ytimg.com") !== -1) return u.split("?")[0];
                                        if (u.indexOf("googleusercontent.com") !== -1 || u.indexOf("ggpht.com") !== -1) {
                                            return u.replace(/=w\d+-h\d+[^=]*$/, "=w360-h360-l90-rj");
                                        }
                                        return u;
                                    }
                                    fillMode: Image.PreserveAspectCrop
                                    autoCropBlackBars: true
                                    sourceSize: Qt.size(240, 240)
                                    asynchronous: true
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

                // =============================================================
                // Case C: Fallback Quick Picks (Virtualized Multi-Row Carousel)
                // =============================================================
                ListView {
                    id: fallbackQuickPicksFlick
                    Layout.fillWidth: true
                    height: 248
                    visible: secDelegate.sectionData && secDelegate.sectionData.type === "fallback_quick_picks"
                    orientation: ListView.Horizontal
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    snapMode: ListView.SnapToItem
                    pixelAligned: true
                    reuseItems: true
                    cacheBuffer: 160
                    clip: true
                    spacing: 14
                    model: (secDelegate.sectionData && secDelegate.sectionData.type === "fallback_quick_picks") ? root.chunkArray(secDelegate.sectionData.items, 4) : []

                    delegate: Item {
                        id: qpColWrapper
                        width: secDelegate.cardGridColWidth
                        height: secDelegate.cardGridColHeight
                        readonly property var chunkTracks: modelData

                        opacity: 1.0

                        Column {
                            anchors.fill: parent
                            spacing: 8

                            Repeater {
                                model: qpColWrapper.chunkTracks

                                Rectangle {
                                    id: qpCard
                                    width: qpColWrapper.width
                                    height: 54
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

                                    readonly property string itemKey: String((modelData ? (modelData.videoId || modelData.path || modelData.title) : "") || "")
                                    property string lastCheckedKey: ""
                                    readonly property int staggerIndex: qpColWrapper.index * 4 + index
                                    transform: Translate { id: qpTrans; y: 0 }

                                    function checkReveal() {
                                        if (!itemKey) {
                                            qpRevealAnim.stop();
                                            opacity = 1.0;
                                            qpTrans.y = 0;
                                            return;
                                        }
                                        if (itemKey === lastCheckedKey) return;
                                        lastCheckedKey = itemKey;

                                        if (root.hasSeen(itemKey) || root.hasInitialLoaded) {
                                            qpRevealAnim.stop();
                                            opacity = 1.0;
                                            qpTrans.y = 0;
                                        } else {
                                            root.markSeen(itemKey);
                                            opacity = 0.0;
                                            qpTrans.y = 14;
                                            qpRevealAnim.restart();
                                        }
                                    }

                                    onItemKeyChanged: checkReveal()
                                    Component.onCompleted: checkReveal()

                                    Connections {
                                        target: root
                                        function onSeenKeysChanged() {
                                            if (!root.hasInitialLoaded) {
                                                qpCard.lastCheckedKey = "";
                                                qpCard.checkReveal();
                                            }
                                        }
                                    }

                                    SequentialAnimation {
                                        id: qpRevealAnim
                                        PauseAnimation { duration: Math.max(0, (qpCard.staggerIndex % 8) * 35) }
                                        ParallelAnimation {
                                            NumberAnimation {
                                                target: qpCard
                                                property: "opacity"
                                                from: 0.0
                                                to: 1.0
                                                duration: 260
                                                easing.type: Easing.OutCubic
                                            }
                                            NumberAnimation {
                                                target: qpTrans
                                                property: "y"
                                                from: 14
                                                to: 0
                                                duration: 260
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 12

                                        RoundedImage {
                                            id: qpImg
                                            width: 44
                                            height: 44
                                            radius: 4
                                            source: modelData.image || ""
                                            fillMode: Image.PreserveAspectCrop
                                            sourceSize: Qt.size(64, 64)
                                            asynchronous: true

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 4
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
                    }
                }

                // =============================================================
                // Case D: Fallback Featured Playlists (Virtualized Horizontal Carousel)
                // =============================================================
                ListView {
                    id: fallbackPlaylistFlick
                    Layout.fillWidth: true
                    height: secDelegate.cardSquareHeight + 8
                    visible: secDelegate.sectionData && secDelegate.sectionData.type === "fallback_playlists"
                    orientation: ListView.Horizontal
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    snapMode: ListView.SnapToItem
                    pixelAligned: true
                    reuseItems: true
                    cacheBuffer: 160
                    clip: true
                    spacing: 16
                    model: (secDelegate.sectionData && secDelegate.sectionData.type === "fallback_playlists") ? (secDelegate.sectionData.items || []) : []

                    delegate: Rectangle {
                        id: plCard
                        width: secDelegate.cardSquareWidth
                        height: secDelegate.cardSquareHeight
                        radius: Theme.radiusCard
                        clip: true
                        color: plMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.06) : Qt.rgba(1.0, 1.0, 1.0, 0.02)
                        border.color: plMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.18) : Qt.rgba(1.0, 1.0, 1.0, 0.06)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        property real revealOpacity: 1.0

                        opacity: revealOpacity
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                        readonly property string itemKey: String((modelData ? (modelData.browseId || modelData.playlistId || modelData.id || modelData.title) : "") || "")
                        property string lastCheckedKey: ""
                        readonly property int staggerIndex: index
                        transform: Translate { id: plTrans; y: 0 }

                        function checkReveal() {
                            if (!itemKey) {
                                plRevealAnim.stop();
                                revealOpacity = 1.0;
                                plTrans.y = 0;
                                return;
                            }
                            if (itemKey === lastCheckedKey) return;
                            lastCheckedKey = itemKey;

                            if (root.hasSeen(itemKey) || root.hasInitialLoaded) {
                                plRevealAnim.stop();
                                revealOpacity = 1.0;
                                plTrans.y = 0;
                            } else {
                                root.markSeen(itemKey);
                                revealOpacity = 0.0;
                                plTrans.y = 14;
                                plRevealAnim.restart();
                            }
                        }

                        onItemKeyChanged: checkReveal()
                        Component.onCompleted: checkReveal()

                        Connections {
                            target: root
                            function onSeenKeysChanged() {
                                if (!root.hasInitialLoaded) {
                                    plCard.lastCheckedKey = "";
                                    plCard.checkReveal();
                                }
                            }
                        }

                        SequentialAnimation {
                            id: plRevealAnim
                            PauseAnimation { duration: Math.max(0, (plCard.staggerIndex % 8) * 35) }
                            ParallelAnimation {
                                NumberAnimation {
                                    target: plCard
                                    property: "revealOpacity"
                                    from: 0.0
                                    to: 1.0
                                    duration: 260
                                    easing.type: Easing.OutCubic
                                }
                                NumberAnimation {
                                    target: plTrans
                                    property: "y"
                                    from: 14
                                    to: 0
                                    duration: 260
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            RoundedImage {
                                id: plImg
                                Layout.fillWidth: true
                                Layout.preferredHeight: width
                                radius: 6
                                source: modelData.image || ""
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(200, 200)
                                asynchronous: true

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

                // =============================================================
                // Case E: Skeleton Placeholder Row (Initial Loading State)
                // =============================================================
                BonesHost {
                    id: skeletonBonesHost
                    Layout.fillWidth: true
                    height: 250
                    visible: secDelegate.sectionData && secDelegate.sectionData.type === "skeleton_section"
                    opacity: root.skeletonOpacity

                    ListView {
                        anchors.fill: parent
                        orientation: ListView.Horizontal
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.HorizontalFlick
                        clip: true
                        interactive: false
                        spacing: 16
                        model: [
                            { tw: 120, sw: 80 },
                            { tw: 140, sw: 95 },
                            { tw: 110, sw: 75 },
                            { tw: 130, sw: 85 },
                            { tw: 125, sw: 90 },
                            { tw: 135, sw: 80 }
                        ]

                        delegate: SkeletonTrackCard {
                            width: secDelegate.cardSquareWidth
                            height: secDelegate.cardSquareHeight
                            titleWidth: modelData.tw
                            subtitleWidth: modelData.sw
                        }
                    }
                }

                Item { height: 16 }
            }
        }
    }
}
