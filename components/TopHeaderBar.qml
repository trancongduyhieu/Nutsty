import QtQuick
import QtQuick.Layouts
import "."

Rectangle {
    id: headerRoot
    height: 64
    color: "transparent"
    z: 100

    property string currentTab: "all"
    property string currentView: "home"
    property string searchMode: currentView === "library" ? "offline" : "online"
    property var suggestions: []
    property bool isSearching: false
    property bool canGoBack: currentView !== "home"
    property bool isSidebarVisible: false
    property bool isMaximized: false
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent
    property Item backgroundSourceItem: null
    property string searchText: ""

    function fillSearchText(val) {
        searchText = val;
    }

    function setSearchText(val) {
        searchText = val;
        suggestions = [];
    }

    signal tabSelected(string tab)
    signal searchRequested(string query, string mode)
    signal searchSubmitted(string query, string mode)
    signal searchClicked()
    signal backRequested()
    signal forwardRequested()
    signal downloadPopoverRequested()
    signal toggleSidebarRequested()
    signal minimizeWindowRequested()
    signal maximizeWindowRequested()
    signal closeWindowRequested()
    signal homeClicked()
    signal libraryClicked()
    signal settingsClicked()
    signal notificationsClicked(real xPos, real yPos)
    property int unreadNotificationsCount: 0

    // Mood Bar Integration in Top Header
    property var moods: []
    property string selectedMood: "All"
    property bool isMoodIslandExpanded: false
    signal moodSelected(string title, string params)

    function formatMoodTitle(title) {
        return I18n.formatMoodChipTitle(title);
    }

    readonly property var activeMoodList: (headerRoot.moods && headerRoot.moods.length > 0) ? headerRoot.moods : [
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

    onCurrentViewChanged: {
        isMoodIslandExpanded = false;
        searchMode = (currentView === "library" ? "offline" : "online");
        suggestions = [];
        if (currentView !== "search" && (!searchText || searchText.trim() === "")) {
            isSearching = false;
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        spacing: 14

        // Top Navigation Cluster: Home, Search, Library, Downloads, Settings (Pure Borderless Icons matching wallpaper accent)
        RowLayout {
            spacing: 14

            // 1. Home Button
            Item {
                id: homeBtn
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/go-home-symbolic.svg"
                    iconSize: 17
                    color: headerRoot.accentColor
                    opacity: headerRoot.currentView === "home" ? 1.0 : (homeMouse.containsMouse ? 1.0 : 0.70)
                    scale: homeMouse.containsMouse ? 1.12 : (headerRoot.currentView === "home" ? 1.05 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                MouseArea {
                    id: homeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: headerRoot.homeClicked()
                }
            }

            // 2. Dedicated Search Button (SimpMusic / Spotify style borderless icon)
            Item {
                id: searchNavBtn
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/system-search-symbolic.svg"
                    iconSize: 17
                    color: headerRoot.accentColor
                    opacity: headerRoot.currentView === "search" ? 1.0 : (searchNavM.containsMouse ? 1.0 : 0.70)
                    scale: searchNavM.containsMouse ? 1.12 : (headerRoot.currentView === "search" ? 1.05 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                MouseArea {
                    id: searchNavM
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: headerRoot.searchClicked()
                }
            }

            // 3. Downloads / Local Library Button
            Item {
                id: libBtn
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32

                readonly property bool isLibActive: headerRoot.currentView === "library" || headerRoot.currentView === "custom_playlist_detail" || (headerRoot.currentView === "playlist" && typeof win !== "undefined" && win.previousView === "library")

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/folder-music-symbolic.svg"
                    iconSize: 17
                    color: headerRoot.accentColor
                    opacity: libBtn.isLibActive ? 1.0 : (libMouse.containsMouse ? 1.0 : 0.70)
                    scale: libMouse.containsMouse ? 1.12 : (libBtn.isLibActive ? 1.05 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                MouseArea {
                    id: libMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: headerRoot.libraryClicked()
                }
            }

            // 4. Downloads Queue Popover Button
            Item {
                id: downloadQueueBtn
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                readonly property bool hasActive: typeof downloadManager !== "undefined" && downloadManager && downloadManager.activeTasksCount > 0
                visible: true

                CircularSpinner {
                    anchors.centerIn: parent
                    visible: downloadQueueBtn.hasActive
                    running: downloadQueueBtn.hasActive
                    color: headerRoot.accentColor
                    size: 16
                    strokeWidth: 2
                }

                AppIcon {
                    anchors.centerIn: parent
                    visible: !downloadQueueBtn.hasActive
                    source: "../assets/icons/download-symbolic.svg"
                    iconSize: 17
                    color: headerRoot.accentColor
                    opacity: dlMouse.containsMouse ? 1.0 : 0.70
                    scale: dlMouse.containsMouse ? 1.12 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                MouseArea {
                    id: dlMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        headerRoot.downloadPopoverRequested();
                    }
                }
            }

            // 5. Settings & Account Button
            Item {
                id: setBtn
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32

                AppIcon {
                    anchors.centerIn: parent
                    source: "../assets/icons/preferences-system-symbolic.svg"
                    iconSize: 17
                    color: headerRoot.accentColor
                    opacity: setMouse.containsMouse ? 1.0 : 0.70
                    scale: setMouse.containsMouse ? 1.12 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                MouseArea {
                    id: setMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: headerRoot.settingsClicked()
                }
            }

            // 6. Notification Bell Button (Flat layout, accent indicator badge)
            Item {
                id: notificationBtn
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32

                AppIcon {
                    id: bellIcon
                    anchors.centerIn: parent
                    source: "../assets/icons/notifications-symbolic.svg"
                    iconSize: 17
                    color: headerRoot.accentColor
                    opacity: headerRoot.unreadNotificationsCount > 0 ? 1.0 : (notifMouse.containsMouse ? 1.0 : 0.70)
                    scale: notifMouse.containsMouse ? 1.12 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                // Flat Accent Badge (No heavy nested box)
                Rectangle {
                    id: notifBadge
                    visible: headerRoot.unreadNotificationsCount > 0
                    anchors.top: bellIcon.top
                    anchors.topMargin: -2
                    anchors.right: bellIcon.right
                    anchors.rightMargin: -4
                    width: Math.max(14, badgeText.implicitWidth + 6)
                    height: 14
                    radius: 7
                    color: headerRoot.accentColor

                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: headerRoot.unreadNotificationsCount > 9 ? "9+" : headerRoot.unreadNotificationsCount
                        font.family: Theme.fontFamily
                        font.pixelSize: 8
                        font.bold: true
                        color: (headerRoot.accentColor.r * 0.299 + headerRoot.accentColor.g * 0.587 + headerRoot.accentColor.b * 0.114) > 0.6 ? "#000000" : "#ffffff"
                    }
                }

                MouseArea {
                    id: notifMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var pt = notificationBtn.mapToItem(headerRoot, notificationBtn.width / 2, notificationBtn.height);
                        headerRoot.notificationsClicked(pt.x, pt.y);
                    }
                }
            }
        }

        // Center Area: Empty drag space between Left Cluster and Right Controls
        Item {
            id: centerHeaderArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            MouseArea {
                anchors.fill: parent
                onPressed: {
                    if (headerRoot.isMoodIslandExpanded) {
                        headerRoot.isMoodIslandExpanded = false;
                    }
                    if (typeof win !== "undefined" && win && typeof win.startSystemMove === "function") {
                        win.startSystemMove();
                    }
                }
                onDoubleClicked: {
                    headerRoot.maximizeWindowRequested();
                }
            }
        }

        // Window Maximize / Restore Button [ ◻ ]
        Rectangle {
            id: maxBtn
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: 16
            color: maxMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
            Behavior on color { ColorAnimation { duration: 150 } }

            AppIcon {
                anchors.centerIn: parent
                source: headerRoot.isMaximized ? "../assets/icons/window-restore-symbolic.svg" : "../assets/icons/window-maximize-symbolic.svg"
                iconSize: 14
                color: "#ffffff"
            }

            MouseArea {
                id: maxMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: headerRoot.maximizeWindowRequested()
            }
        }

        // Window Close Button [ ✕ ] (Closes / Minimizes to Desktop Widget)
        Rectangle {
            id: closeBtn
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: 16
            color: closeMouse.containsMouse ? "#E81123" : "transparent"
            Behavior on color { ColorAnimation { duration: 150 } }

            AppIcon {
                anchors.centerIn: parent
                source: "../assets/icons/window-close-symbolic.svg"
                iconSize: 14
                color: "#ffffff"
            }

            MouseArea {
                id: closeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: headerRoot.closeWindowRequested()
            }
        }
    }

    // -------------------------------------------------------------------------
    // Center Floating: Dynamic Mood Island (Direct child of headerRoot -> Dead Center!)
    // -------------------------------------------------------------------------
    Rectangle {
        id: dynamicMoodShadow
        anchors.horizontalCenter: dynamicMoodIsland.horizontalCenter
        anchors.verticalCenter: dynamicMoodIsland.verticalCenter
        anchors.verticalCenterOffset: 2
        width: dynamicMoodIsland.width
        height: dynamicMoodIsland.height
        radius: dynamicMoodIsland.radius
        color: "#55000000"
        visible: dynamicMoodIsland.visible && dynamicMoodIsland.width > 0
        z: 11
        Behavior on width {
            NumberAnimation {
                duration: 320
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.08, 0.72, 0.15, 1.0]
            }
        }
    }

    Rectangle {
        id: dynamicMoodIsland
        anchors.horizontalCenter: headerRoot.horizontalCenter
        anchors.verticalCenter: headerRoot.verticalCenter
        height: 34
        radius: 17
        z: 12
        clip: true
        visible: opacity > 0.01
        opacity: headerRoot.currentView === "home" ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 180 } }

        readonly property bool isExpanded: headerRoot.isMoodIslandExpanded
        readonly property real compactWidth: compactTxt.implicitWidth + 28
        readonly property real expandedTargetWidth: Math.min(headerRoot.width - 580, moodRow.width + 24)
        width: isExpanded ? expandedTargetWidth : compactWidth

        Behavior on width {
            NumberAnimation {
                duration: 320
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.08, 0.72, 0.15, 1.0]
            }
        }

        color: isExpanded 
            ? Qt.rgba(0.08, 0.08, 0.10, 0.82) 
            : Qt.rgba(headerRoot.accentColor.r, headerRoot.accentColor.g, headerRoot.accentColor.b, 0.95)
        border.width: 1
        border.color: isExpanded 
            ? Qt.rgba(1.0, 1.0, 1.0, 0.14) 
            : Qt.rgba(headerRoot.accentColor.r * 1.15, headerRoot.accentColor.g * 1.15, headerRoot.accentColor.b * 1.15, 0.95)

        Behavior on color { ColorAnimation { duration: 240 } }
        Behavior on border.color { ColorAnimation { duration: 240 } }

        scale: (!isExpanded && compactMouse.containsMouse) ? 1.05 : 1.0
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 16
            color: "transparent"
            border.color: Qt.rgba(1.0, 1.0, 1.0, dynamicMoodIsland.isExpanded ? 0.08 : (topMoodFlickable.accentLuminance > 0.55 ? 0.35 : 0.22))
            border.width: 1
            Behavior on border.color { ColorAnimation { duration: 200 } }
        }

        // Layer 1: Compact View (Single Active Mood Pill in Center)
        Text {
            id: compactTxt
            anchors.centerIn: parent
            text: headerRoot.formatMoodTitle(headerRoot.selectedMood)
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.bold: true
            color: topMoodFlickable.accentLuminance > 0.55 ? "#0f0f11" : "#ffffff"
            visible: opacity > 0.01
            opacity: dynamicMoodIsland.isExpanded ? 0.0 : 1.0
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }

        MouseArea {
            id: compactMouse
            anchors.fill: parent
            z: dynamicMoodIsland.isExpanded ? -1 : 10
            enabled: !dynamicMoodIsland.isExpanded
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                headerRoot.isMoodIslandExpanded = true;
                autoCollapseTimer.restart();
            }
        }

        // Layer 2: Expanded View (Full Moods Palette with Liquid Tint Glass)
        Flickable {
            id: topMoodFlickable
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            contentWidth: moodRow.width + 8
            contentHeight: height
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            pixelAligned: true
            clip: true
            interactive: contentWidth > width && dynamicMoodIsland.isExpanded
            enabled: dynamicMoodIsland.isExpanded
            visible: opacity > 0.01
            opacity: dynamicMoodIsland.isExpanded ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 200 } }

            readonly property real accentLuminance: (0.299 * headerRoot.accentColor.r + 0.587 * headerRoot.accentColor.g + 0.114 * headerRoot.accentColor.b)

            WheelHandler {
                target: topMoodFlickable
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    var delta = (event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x);
                    var maxScroll = Math.max(0, topMoodFlickable.contentWidth - topMoodFlickable.width);
                    topMoodFlickable.contentX = Math.max(0, Math.min(maxScroll, topMoodFlickable.contentX - delta * 1.2));
                }
            }

            Rectangle {
                id: activeMoodIndicator
                height: 26
                radius: 13
                y: (topMoodFlickable.height - height) / 2
                z: 2
                color: Qt.rgba(headerRoot.accentColor.r, headerRoot.accentColor.g, headerRoot.accentColor.b, 0.95)
                border.color: Qt.rgba(1.0, 1.0, 1.0, 0.45)
                border.width: 1
                visible: width > 0

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: 12
                    color: "transparent"
                    border.color: Qt.rgba(1.0, 1.0, 1.0, topMoodFlickable.accentLuminance > 0.55 ? 0.35 : 0.25)
                    border.width: 1
                }

                Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }

            Row {
                id: moodRow
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(4, (topMoodFlickable.width - width) / 2)
                z: 5
                onWidthChanged: Qt.callLater(topMoodFlickable.updateActiveIndicator)

                Repeater {
                    id: moodRepeater
                    model: headerRoot.activeMoodList

                    delegate: Item {
                        id: pillItem
                        height: 26
                        width: pillTxt.implicitWidth + 14
                        readonly property bool isSelected: headerRoot.selectedMood === modelData.title
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

                        Rectangle {
                            anchors.fill: parent
                            radius: 13
                            color: pillItem.isHovered 
                                ? Qt.rgba(headerRoot.accentColor.r, headerRoot.accentColor.g, headerRoot.accentColor.b, 0.20) 
                                : Qt.rgba(0.16, 0.16, 0.19, 0.85)
                            border.width: 1
                            border.color: pillItem.isHovered 
                                ? Qt.rgba(headerRoot.accentColor.r, headerRoot.accentColor.g, headerRoot.accentColor.b, 0.45) 
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
                            text: headerRoot.formatMoodTitle(modelData.title)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: pillItem.isSelected ? Font.Bold : Font.DemiBold
                            color: pillItem.isSelected 
                                   ? (topMoodFlickable.accentLuminance > 0.55 ? "#0f0f11" : "#ffffff") 
                                   : (pillItem.isHovered ? "#ffffff" : Qt.rgba(0.92, 0.92, 0.94, 0.90))
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        MouseArea {
                            id: pillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                headerRoot.selectedMood = modelData.title;
                                headerRoot.moodSelected(modelData.title, modelData.params || "");
                                headerRoot.isMoodIslandExpanded = false;
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

        // Optical Edge Fade Overlays
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 24
            z: 10
            visible: dynamicMoodIsland.isExpanded && topMoodFlickable.contentWidth > topMoodFlickable.width && topMoodFlickable.contentX > 4
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
            width: 24
            z: 10
            visible: dynamicMoodIsland.isExpanded && topMoodFlickable.contentWidth > topMoodFlickable.width && (topMoodFlickable.contentX < topMoodFlickable.contentWidth - topMoodFlickable.width - 4)
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
                if (headerRoot.isMoodIslandExpanded) {
                    headerRoot.isMoodIslandExpanded = false;
                }
            }
        }

        Connections {
            target: headerRoot
            function onIsMoodIslandExpandedChanged() {
                if (headerRoot.isMoodIslandExpanded) {
                    autoCollapseTimer.restart();
                    topMoodFlickable.updateActiveIndicator();
                } else {
                    autoCollapseTimer.stop();
                }
            }
        }
    }

    Connections {
        target: headerRoot
        function onSelectedMoodChanged() {
            topMoodFlickable.updateActiveIndicator();
        }
        function onMoodsChanged() {
            Qt.callLater(topMoodFlickable.updateActiveIndicator);
        }
    }

    Connections {
        target: I18n
        function onLocaleChanged() {
            Qt.callLater(topMoodFlickable.updateActiveIndicator);
        }
    }
}
