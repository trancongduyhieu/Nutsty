import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import "."

Rectangle {
    id: root
    width: 240
    color: Qt.rgba(0.06, 0.07, 0.09, 0.42)
    radius: 12
    border.color: Qt.rgba(1, 1, 1, 0.05)
    border.width: 1

    property var playlists: []
    property var onlinePlaylists: []
    property var queueTracks: []
    property int selectedIndex: 0
    property string currentView: "home"
    property string activePlaylistId: ""
    property string playingPlaylistId: ""
    property var currentTrack: null
    property bool isPlaying: false
    property string sidebarTab: "playlists" // "playlists" or "queue"
    property bool isLoadingRadio: false
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent

    property var customPlaylists: []

    readonly property var allPlaylists: {
        var res = [];
        var seen = {};

        // 1. Custom playlists first in every view
        if (root.customPlaylists && Array.isArray(root.customPlaylists)) {
            for (var c = 0; c < root.customPlaylists.length; c++) {
                var cp = root.customPlaylists[c];
                if (!cp) continue;
                var ck = cp.id || cp.playlistId || ("cp_" + c);
                if (!seen[ck]) {
                    seen[ck] = true;
                    res.push(cp);
                }
            }
        }

        // 2. If in Downloads view: ONLY local collections (never online playlists)
        if (root.currentView === "library") {
            if (root.playlists && Array.isArray(root.playlists)) {
                for (var i = 0; i < root.playlists.length; i++) {
                    var p = root.playlists[i];
                    if (!p) continue;
                    if (!p.isLocal && p.playlistId && !String(p.playlistId).startsWith("custom_") && !p.isCustom && p.source !== "spotify_import") continue;
                    var k = p.id || p.playlistId || ("pl_" + i);
                    if (!seen[k]) {
                        seen[k] = true;
                        res.push(p);
                    }
                }
            }
        } else {
            // 3. In Home view: online featured playlists
            if (root.onlinePlaylists && Array.isArray(root.onlinePlaylists)) {
                for (var j = 0; j < root.onlinePlaylists.length; j++) {
                    var op = root.onlinePlaylists[j];
                    if (!op) continue;
                    var ok = op.id || op.playlistId || ("opl_" + j);
                    if (!seen[ok]) {
                        seen[ok] = true;
                        res.push(op);
                    }
                }
            }
        }
        return res;
    }

    signal homeSelected()
    signal librarySelected()
    signal settingsRequested()
    signal playlistSelected(int index, var pl)
    signal onlinePlaylistSelected(var pl)
    signal customPlaylistDeleteRequested(string playlistId)
    signal trackSelected(var trk)
    signal trackContextMenuRequested(var trk, real globalX, real globalY, bool isQueue)
    signal spotifyImportRequested()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        // 1. Primary Navigation Buttons (Home, Library/Downloads, Settings)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            // Home Button
            Rectangle {
                Layout.fillWidth: true
                height: 42
                radius: 6
                color: root.currentView === "home" ? Theme.bgHighlight : (homeH.hovered ? Theme.bgCardHover : "transparent")
                Behavior on color { ColorAnimation { duration: 100 } }

                HoverHandler { id: homeH }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 14

                    AppIcon {
                        source: "../assets/icons/go-home-symbolic.svg"
                        iconSize: 18
                        color: root.currentView === "home" ? root.accentColor : (homeH.hovered ? "#ffffff" : Theme.textSecondary)
                    }

                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Khám phá", "Home")
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                        color: root.currentView === "home" ? root.accentColor : (homeH.hovered ? "#ffffff" : Theme.textSecondary)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.homeSelected()
                }
            }

            // Downloads / Library Button
            Rectangle {
                Layout.fillWidth: true
                height: 42
                radius: 6
                color: root.currentView === "library" ? Theme.bgHighlight : (libH.hovered ? Theme.bgCardHover : "transparent")
                Behavior on color { ColorAnimation { duration: 100 } }

                HoverHandler { id: libH }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 14

                    AppIcon {
                        source: "../assets/icons/folder-music-symbolic.svg"
                        iconSize: 18
                        color: root.currentView === "library" ? root.accentColor : (libH.hovered ? "#ffffff" : Theme.textSecondary)
                    }

                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Tải xuống", "Downloads")
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                        color: root.currentView === "library" ? root.accentColor : (libH.hovered ? "#ffffff" : Theme.textSecondary)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.librarySelected()
                }
            }

            // Settings Button
            Rectangle {
                Layout.fillWidth: true
                height: 42
                radius: 6
                color: setH.hovered ? Theme.bgCardHover : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }

                HoverHandler { id: setH }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 14

                    AppIcon {
                        source: "../assets/icons/preferences-system-symbolic.svg"
                        iconSize: 18
                        color: setH.hovered ? "#ffffff" : Theme.textSecondary
                    }

                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Cài đặt & Tài khoản", "Settings & Account")
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                        color: setH.hovered ? "#ffffff" : Theme.textSecondary
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.settingsRequested()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.rgba(1.0, 1.0, 1.0, 0.08)
        }

        // 2. Interactive Segmented Tab Switcher [ Playlists | Queue ]
        Rectangle {
            Layout.fillWidth: true
            height: 36
            radius: 8
            color: Qt.rgba(1.0, 1.0, 1.0, 0.04)
            border.color: Qt.rgba(1.0, 1.0, 1.0, 0.08)
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 3
                spacing: 4

                // Playlists Tab Pill
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 6
                    color: root.sidebarTab === "playlists" ? Qt.rgba(1.0, 1.0, 1.0, 0.12) : (plTabH.hovered ? Qt.rgba(1.0, 1.0, 1.0, 0.06) : "transparent")
                    border.color: root.sidebarTab === "playlists" ? Qt.rgba(1.0, 1.0, 1.0, 0.16) : "transparent"
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Behavior on border.color { ColorAnimation { duration: 100 } }

                    HoverHandler { id: plTabH }

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        AppIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            source: "../assets/icons/media-playlist-consecutive-symbolic.svg"
                            iconSize: 13
                            color: root.sidebarTab === "playlists" ? root.accentColor : (plTabH.hovered ? "#ffffff" : Theme.textSecondary)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Danh sách phát", "Playlists")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: root.sidebarTab === "playlists"
                            color: root.sidebarTab === "playlists" ? "#ffffff" : (plTabH.hovered ? "#ffffff" : Theme.textSecondary)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.sidebarTab = "playlists"
                    }
                }

                // Queue Tab Pill
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 6
                    color: root.sidebarTab === "queue" ? Qt.rgba(1.0, 1.0, 1.0, 0.12) : (qTabH.hovered ? Qt.rgba(1.0, 1.0, 1.0, 0.06) : "transparent")
                    border.color: root.sidebarTab === "queue" ? Qt.rgba(1.0, 1.0, 1.0, 0.16) : "transparent"
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Behavior on border.color { ColorAnimation { duration: 100 } }

                    HoverHandler { id: qTabH }

                    Row {
                        anchors.centerIn: parent
                        spacing: 5

                        AppIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            source: "../assets/icons/view-queue-symbolic.svg"
                            iconSize: 13
                            color: root.sidebarTab === "queue" ? root.accentColor : (qTabH.hovered ? "#ffffff" : Theme.textSecondary)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Hàng đợi", "Queue")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: root.sidebarTab === "queue"
                            color: root.sidebarTab === "queue" ? "#ffffff" : (qTabH.hovered ? "#ffffff" : Theme.textSecondary)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: (root.queueTracks && root.queueTracks.length > 0) || root.isLoadingRadio
                            text: root.isLoadingRadio ? "(" + (root.queueTracks ? root.queueTracks.length : 0) + "+)" : ("(" + (root.queueTracks ? root.queueTracks.length : 0) + ")")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: root.sidebarTab === "queue"
                            color: root.sidebarTab === "queue" ? root.accentColor : Theme.textMuted
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.sidebarTab = "queue"
                    }
                }
            }
        }

        // 3. Tab Content (Playlists List or Queue List)
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.sidebarTab === "playlists" ? 0 : 1

            // Page 0: Playlists List
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 6

                    // Header subtitle
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4

                        Text {
                            Layout.fillWidth: true
                            text: root.currentView === "library" ? I18n.tr("Bộ sưu tập", "Collections") : I18n.tr("Danh sách phát nổi bật", "Featured Playlists")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                            color: Theme.textSecondary
                        }

                        Text {
                            text: (root.allPlaylists ? root.allPlaylists.length : 0) + ""
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textMuted
                        }

                        // Spotify Import Button (Subtle Glass Icon)
                        Rectangle {
                            width: 22
                            height: 22
                            radius: 6
                            color: spotifyImportNavMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22) : "transparent"
                            border.color: spotifyImportNavMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45) : "transparent"
                            border.width: 1

                            AppIcon {
                                anchors.centerIn: parent
                                source: "assets/icons/arrow-outward-symbolic.svg"
                                iconSize: 12
                                color: spotifyImportNavMouse.containsMouse ? root.accentColor : Theme.textMuted
                            }

                            MouseArea {
                                id: spotifyImportNavMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.spotifyImportRequested()
                            }
                        }
                    }

                    ListView {
                        id: plList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds
                        bottomMargin: 100
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        model: root.allPlaylists

                        delegate: Rectangle {
                            id: plItem
                            width: plList.width
                            height: 48
                            radius: 6
                            color: isCurrentlyPlaying ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16) : (isSelected ? Theme.bgHighlight : (plH.hovered ? Theme.bgCardHover : "transparent"))
                            Behavior on color { ColorAnimation { duration: 100 } }

                            readonly property bool isSelected: root.selectedIndex === index && root.currentView === "library"
                            readonly property bool isCurrentlyPlaying: (modelData.id || modelData.playlistId) === root.playingPlaylistId
                            readonly property bool isLocal: modelData.isLocal === true || !modelData.id || modelData.id.indexOf("local_") === 0
                            readonly property bool isCustom: modelData.isCustom === true

                            HoverHandler { id: plH }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 10

                                // Playlist Thumbnail or Icon
                                Rectangle {
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36
                                    radius: 4
                                    color: Theme.bgElevated
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        source: modelData.image || ""
                                        fillMode: Image.PreserveAspectCrop
                                        visible: modelData.image !== undefined && modelData.image !== ""
                                        asynchronous: true
                                        cache: true
                                    }

                                    // Fallback text initials if no image
                                    Text {
                                        anchors.centerIn: parent
                                        visible: !modelData.image
                                        text: (modelData.name || modelData.title || "P").charAt(0).toUpperCase()
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: Theme.textSecondary
                                    }
                                }

                                // Playlist Title & Meta
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.title || modelData.name || I18n.tr("Danh sách phát", "Playlist")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: plItem.isCurrentlyPlaying || plItem.isSelected
                                        color: plItem.isCurrentlyPlaying ? root.accentColor : (plItem.isSelected ? "#ffffff" : (plH.hovered ? "#ffffff" : Theme.textPrimary))
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.subtitle || (modelData.count ? (modelData.count + I18n.tr(" bài hát", " songs")) : (modelData.tracks ? (modelData.tracks.length + I18n.tr(" bài hát", " songs")) : (modelData.author || I18n.tr("Danh sách phát", "Playlist"))))
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Theme.textSecondary
                                        elide: Text.ElideRight
                                    }
                                }

                                // Equalizer indicator when active and playing
                                Row {
                                    Layout.preferredWidth: 16
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 2
                                    visible: plItem.isCurrentlyPlaying && root.isPlaying

                                    Repeater {
                                        model: 3
                                        Rectangle {
                                            width: 3
                                            height: index === 0 ? 10 : (index === 1 ? 14 : 8)
                                            radius: 1.5
                                            color: root.accentColor
                                            anchors.bottom: parent.bottom

                                            SequentialAnimation on height {
                                                running: plItem.isCurrentlyPlaying && root.isPlaying
                                                loops: Animation.Infinite
                                                NumberAnimation { to: index === 0 ? 14 : (index === 1 ? 7 : 13); duration: 240 + index * 90; easing.type: Easing.InOutQuad }
                                                NumberAnimation { to: index === 0 ? 6 : (index === 1 ? 14 : 5); duration: 240 + index * 90; easing.type: Easing.InOutQuad }
                                            }
                                        }
                                    }
                                }
                            }

                            // Delete Custom Playlist Button (Direct child with high z and separate geometry)
                            Item {
                                id: delBtn
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28
                                height: 28
                                visible: plItem.isCustom && plH.hovered
                                z: 50

                                HoverHandler { id: delH }

                                AppIcon {
                                    anchors.centerIn: parent
                                    source: "../assets/icons/user-trash-symbolic.svg"
                                    iconSize: 14
                                    color: delH.hovered ? "#ff5252" : Theme.textMuted
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    preventStealing: true
                                    onClicked: mouse => {
                                        mouse.accepted = true;
                                        root.customPlaylistDeleteRequested(modelData.id || modelData.playlistId);
                                    }
                                }
                            }

                            MouseArea {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.right: (plItem.isCustom && plH.hovered) ? delBtn.left : parent.right
                                z: 1
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.activePlaylistId = modelData.id || modelData.playlistId || "";
                                    if (plItem.isLocal) {
                                        root.selectedIndex = index;
                                        root.playlistSelected(index, modelData);
                                    } else {
                                        root.onlinePlaylistSelected(modelData);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Page 1: Queue List
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 6

                    // Header subtitle
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4

                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Hàng đợi đang phát", "Now Playing Queue")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                            color: Theme.textSecondary
                        }

                        Text {
                            text: (root.queueTracks ? root.queueTracks.length : 0) + I18n.tr(" bài", " tracks")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.textMuted
                        }
                    }

                    // Empty Queue Notice
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: "transparent"
                        visible: (!root.queueTracks || root.queueTracks.length === 0) && !root.isLoadingRadio

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            AppIcon {
                                Layout.alignment: Qt.AlignHCenter
                                source: "../assets/icons/view-queue-symbolic.svg"
                                iconSize: 28
                                color: Theme.textMuted
                            }

                            Text {
                                text: I18n.tr("Hàng đợi trống", "Queue is empty")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                color: Theme.textSecondary
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Text {
                                text: I18n.tr("Chọn bài hát để bắt đầu", "Play a playlist or track to start")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.textMuted
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    // Queue ListView
                    ListView {
                        id: qList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 3
                        visible: (root.queueTracks && root.queueTracks.length > 0) || root.isLoadingRadio
                        boundsBehavior: Flickable.StopAtBounds
                        bottomMargin: 100
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        footer: ColumnLayout {
                            width: qList.width
                            spacing: 3
                            visible: root.isLoadingRadio

                            Repeater {
                                model: [130, 110, 140, 95, 120]

                                SkeletonTrackRow {
                                    isCompact: true
                                    titleWidth: modelData
                                    subtitleWidth: 70
                                }
                            }
                        }

                        model: root.queueTracks

                        delegate: Rectangle {
                            id: qItem
                            width: qList.width
                            height: 48
                            radius: 8

                            readonly property bool isCurrent: Boolean(root.currentTrack && modelData && (
                                (modelData.videoId && root.currentTrack.videoId && modelData.videoId === root.currentTrack.videoId) ||
                                (modelData.path && root.currentTrack.path && modelData.path === root.currentTrack.path) ||
                                (modelData.id && root.currentTrack.id && modelData.id === root.currentTrack.id)
                            ))

                            color: isCurrent ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16) : (qRowH.hovered ? Qt.rgba(1.0, 1.0, 1.0, 0.05) : "transparent")
                            border.width: 0

                            Behavior on color { ColorAnimation { duration: 100 } }

                            HoverHandler { id: qRowH }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8

                                // Track Number or Miniature Cover
                                Item {
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32

                                    Rectangle {
                                        id: qThumbMask
                                        anchors.fill: parent
                                        radius: 5
                                        color: "#ffffff"
                                        visible: false
                                        layer.enabled: true
                                    }

                                    Item {
                                        anchors.fill: parent
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            maskEnabled: true
                                            maskSource: qThumbMask
                                            autoPaddingEnabled: false
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            color: "#202024"
                                            visible: !qCoverImg.visible || qCoverImg.status !== Image.Ready
                                        }

                                        Image {
                                            id: qCoverImg
                                            anchors.fill: parent
                                            source: modelData.image || ""
                                            fillMode: Image.PreserveAspectCrop
                                            scale: (implicitWidth > 0 && implicitHeight > 0 && (implicitWidth / implicitHeight > 1.3)) ? 1.48 : 1.0
                                            transformOrigin: Item.Center
                                            asynchronous: true
                                            visible: !!source
                                        }

                                        // Fallback index number
                                        Text {
                                            anchors.centerIn: parent
                                            visible: !modelData.image
                                            text: (index + 1) + ""
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            font.bold: true
                                            color: qItem.isCurrent ? root.accentColor : Theme.textMuted
                                        }

                                        // Overlay equalizer if current and playing
                                        Rectangle {
                                            anchors.fill: parent
                                            color: Qt.rgba(0, 0, 0, 0.6)
                                            visible: qItem.isCurrent && root.isPlaying

                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 2

                                                Repeater {
                                                    model: 3
                                                    Rectangle {
                                                        width: 2.5
                                                        height: index === 0 ? 8 : (index === 1 ? 12 : 6)
                                                        radius: 1
                                                        color: root.accentColor
                                                        anchors.bottom: parent.bottom

                                                        SequentialAnimation on height {
                                                            running: qItem.isCurrent && root.isPlaying
                                                            loops: Animation.Infinite
                                                            NumberAnimation { to: index === 0 ? 12 : (index === 1 ? 6 : 11); duration: 220 + index * 80; easing.type: Easing.InOutQuad }
                                                            NumberAnimation { to: index === 0 ? 5 : (index === 1 ? 12 : 4); duration: 220 + index * 80; easing.type: Easing.InOutQuad }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // 1px Hairline Border Overlay on top of thumbnail
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 6
                                        color: "transparent"
                                        border.color: qRowH.hovered ? Qt.rgba(1.0, 1.0, 1.0, 0.35) : Qt.rgba(1.0, 1.0, 1.0, 0.16)
                                        border.width: 1
                                        z: 1
                                        Behavior on border.color { ColorAnimation { duration: 100 } }
                                    }
                                }

                                // Track Details
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.title || modelData.name || "Track"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: qItem.isCurrent ? root.accentColor : (qRowH.hovered ? "#ffffff" : Theme.textPrimary)
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.artist || modelData.author || "Cloud Stream"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Theme.textSecondary
                                        elide: Text.ElideRight
                                    }
                                }

                                // Duration
                                Text {
                                    text: modelData.duration || ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.textMuted
                                    visible: !!text && text !== "--:--"
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) {
                                        var pt = qItem.mapToItem(null, mouse.x, mouse.y);
                                        root.trackContextMenuRequested(modelData, pt.x, pt.y, true);
                                    } else {
                                        root.trackSelected(modelData);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
