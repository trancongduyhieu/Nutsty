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

    onCurrentViewChanged: {
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

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            MouseArea {
                anchors.fill: parent
                onPressed: {
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
}
