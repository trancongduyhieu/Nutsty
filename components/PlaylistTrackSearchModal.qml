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

    property var playlist: null
    property var currentTrack: null
    property bool isPlaying: false
    property var availableTracks: []
    property color accentColor: Theme.accent
    property Item backgroundSourceItem: null

    property string trackSearchQuery: ""
    property var onlineSearchResults: []
    property bool isSearchingOnline: false
    property var addedTrackKeys: ({}) // trackKey -> true for instant UI feedback

    signal closeRequested()
    signal trackAddRequested(var track)
    signal previewTrackRequested(var track)

    function isSameTrack(a, b) {
        if (!a || !b) return false;
        if (a.videoId && b.videoId && a.videoId === b.videoId) return true;
        if (a.path && b.path && a.path === b.path) return true;
        if (a.id && b.id && a.id === b.id) return true;
        return (a.title && b.title && a.title === b.title && a.artist === b.artist);
    }

    function getTrackKey(t) {
        if (!t) return "";
        if (t.videoId) return "yt_" + t.videoId;
        if (t.path) {
            if (t.path.startsWith("ytdl://")) return "yt_" + t.path.replace("ytdl://", "");
            return "local_" + t.path;
        }
        if (t.id) return "id_" + t.id;
        return (t.title || "") + "_" + (t.artist || "");
    }

    function isTrackInPlaylist(t) {
        var key = getTrackKey(t);
        if (!key) return false;
        if (addedTrackKeys[key]) return true;
        if (!root.playlist || !root.playlist.tracks) return false;
        var trks = root.playlist.tracks;
        var len = trks.length || 0;
        for (var i = 0; i < len; i++) {
            if (getTrackKey(trks[i]) === key) return true;
        }
        return false;
    }

    function openModal(pl) {
        root.playlist = pl || null;
        root.trackSearchQuery = "";
        root.onlineSearchResults = [];
        root.isSearchingOnline = false;
        root.addedTrackKeys = {};
        root.visible = true;
        searchInput.text = "";
        searchInput.forceActiveFocus();
    }

    function closeModal() {
        searchInput.focus = false;
        root.visible = false;
        root.closeRequested();
    }

    property string _activeSearchQuery: ""

    function performOnlineSearch() {
        var q = root.trackSearchQuery.trim();
        if (!q) {
            searchDebounceTimer.stop();
            root._activeSearchQuery = "";
            root.onlineSearchResults = [];
            root.isSearchingOnline = false;
            return;
        }
        root._activeSearchQuery = q;
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
                        console.log("PlaylistTrackSearchModal search parse error:", e);
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
        onClicked: root.closeModal()
    }

    // Outer Drop Shadow (MultiEffect standard, 100% matched with PostNoteModal)
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
        width: Math.min(520, parent.width - 32)
        height: Math.min(560, parent.height - 48)
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

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12
            z: 5

            // TOP BAR: Title & Playlist Subtitle | Close Button '✕' (All Borderless Clean)
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Thêm bài hát vào danh sách phát", "Add Songs to Playlist")
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.bold: true
                        color: "#ffffff"
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.playlist ? (root.playlist.title || root.playlist.name || "") : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                        color: root.accentColor
                        elide: Text.ElideRight
                        visible: text.length > 0
                    }
                }

                // Plain '✕' Close Button (Pinned firmly to top-right corner)
                MouseArea {
                    id: closeMouse
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                    width: 28; height: 28
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeModal()

                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/window-close-symbolic.svg"
                        iconSize: 15
                        color: closeMouse.containsMouse ? "#f43f5e" : Qt.rgba(1, 1, 1, 0.75)
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }
            }

            // Search Pill Container (Identical to PostNoteModal)
            Rectangle {
                Layout.fillWidth: true
                height: 38
                radius: 19
                color: Qt.rgba(1, 1, 1, 0.08)
                border.color: searchInput.activeFocus 
                              ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.40) 
                              : Qt.rgba(1, 1, 1, 0.06)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    spacing: 8

                    AppIcon {
                        source: "../assets/icons/system-search-symbolic.svg"
                        iconSize: 15
                        color: searchInput.activeFocus ? root.accentColor : Qt.rgba(1, 1, 1, 0.5)
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        clip: true
                        selectByMouse: true

                        function updateQuery() {
                            var pt = (searchInput.preeditText !== undefined && searchInput.preeditText !== null) ? String(searchInput.preeditText).trim() : "";
                            var t = (searchInput.text !== undefined && searchInput.text !== null) ? String(searchInput.text).trim() : "";
                            var q = (pt.length > 0) ? (t + " " + pt).replace(/\s+/g, " ").trim() : t;
                            root.trackSearchQuery = q;
                            searchDebounceTimer.restart();
                        }

                        onTextChanged: updateQuery()
                        onPreeditTextChanged: updateQuery()
                        onAccepted: {
                            searchDebounceTimer.stop();
                            root.performOnlineSearch();
                        }

                        Text {
                            anchors.fill: parent
                            text: I18n.tr("Nhập tên bài hát hoặc ca sĩ...", "Search song or artist name...")
                            color: Qt.rgba(1, 1, 1, 0.45)
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            visible: !searchInput.text && !searchInput.inputMethodComposing
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    // Clear search button '✕'
                    MouseArea {
                        visible: searchInput.text.length > 0
                        width: 20
                        height: 20
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            searchInput.text = "";
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

            // Searching Status Indicator (Identical to PostNoteModal)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.isSearchingOnline ? 14 : 0
                visible: root.isSearchingOnline
                clip: true

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    AppIcon {
                        source: "../assets/icons/process-working-symbolic.svg"
                        iconSize: 11
                        color: root.accentColor
                    }
                    Text {
                        text: I18n.tr("Đang tìm kiếm bài hát trực tuyến...", "Searching online music...")
                        color: Qt.rgba(1, 1, 1, 0.5)
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                }
            }

            // Results List & Skeleton Loading Container
            ColumnLayout {
                id: searchSkeletonCol
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6
                visible: root.isSearchingOnline && (!resultsList.model || resultsList.model.length === 0)

                Repeater {
                    model: 5
                    SkeletonTrackRow {
                        Layout.fillWidth: true
                        isCompact: false
                    }
                }

                Item { Layout.fillHeight: true }
            }

            // Results List
            ListView {
                id: resultsList
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !searchSkeletonCol.visible
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                model: {
                    var q = root.trackSearchQuery.trim();
                    if (q.length > 0) {
                        if (root.onlineSearchResults && root.onlineSearchResults.length > 0) {
                            return root.onlineSearchResults;
                        }
                        // Instant local search filter while typing
                        var qLower = q.toLowerCase();
                        var locals = (root.availableTracks || []).filter(function(t) {
                            return (t.title && t.title.toLowerCase().indexOf(qLower) !== -1) ||
                                   (t.name && t.name.toLowerCase().indexOf(qLower) !== -1) ||
                                   (t.artist && t.artist.toLowerCase().indexOf(qLower) !== -1);
                        });
                        return locals;
                    }
                    return [];
                }

                delegate: Rectangle {
                    id: rowCard
                    width: resultsList.width
                    height: 56
                    radius: 10
                    readonly property var trk: modelData
                    readonly property bool inPl: root.isTrackInPlaylist(trk)
                    readonly property bool isThisPlaying: (root.currentTrack && root.isSameTrack(root.currentTrack, trk) && root.isPlaying)
                    color: isThisPlaying 
                           ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14) 
                           : (rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")

                    Behavior on color { ColorAnimation { duration: 120 } }

                    // Double-click row area to add track (leaves 90px on right for prevBtn and addBtn)
                    MouseArea {
                        id: rowMouse
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        anchors.rightMargin: 90
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onDoubleClicked: {
                            if (!rowCard.inPl) {
                                var k = root.getTrackKey(trk);
                                if (k) {
                                    var updated = Object.assign({}, root.addedTrackKeys);
                                    updated[k] = true;
                                    root.addedTrackKeys = updated;
                                }
                                root.trackAddRequested(trk);
                            }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 12

                        // Cover Artwork Thumbnail (44x44, R=8 using unified RoundedImage)
                        RoundedImage {
                            width: 44
                            height: 44
                            radius: 8
                            source: trk ? (trk.image || trk.cover || trk.thumbnail || "") : ""
                            initialsText: trk ? (trk.title || trk.name || "") : ""
                            placeholderColor: Qt.rgba(1, 1, 1, 0.08)
                            fallbackIcon: "../assets/icons/folder-music-symbolic.svg"
                            fallbackIconSize: 18
                            fallbackIconColor: root.accentColor
                        }

                        // Middle: Song Title (bold, 13px) & Artist (11px, muted)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                Layout.fillWidth: true
                                text: trk ? (trk.title || trk.name || "Track") : "Track"
                                color: rowCard.isThisPlaying ? root.accentColor : "#ffffff"
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: trk ? (trk.artist || I18n.tr("Nghệ sĩ chưa rõ", "Unknown Artist")) : ""
                                color: Qt.rgba(1, 1, 1, 0.55)
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }

                        // Right: Preview Button (32x32 circular, identical style to PostNoteModal playBtn)
                        Rectangle {
                            id: prevBtn
                            width: 32
                            height: 32
                            radius: 16
                            z: 2
                            color: rowCard.isThisPlaying 
                                   ? root.accentColor 
                                   : (prevMouse.containsMouse ? root.accentColor : Qt.rgba(1, 1, 1, 0.10))
                            Behavior on color { ColorAnimation { duration: 120 } }

                            AppIcon {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: rowCard.isThisPlaying ? 0 : 1
                                source: rowCard.isThisPlaying ? "../assets/icons/media-playback-pause-symbolic.svg" : "../assets/icons/media-playback-start-symbolic.svg"
                                iconSize: 12
                                color: "#ffffff"
                            }

                            MouseArea {
                                id: prevMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                preventStealing: true
                                onClicked: root.previewTrackRequested(trk)
                            }
                        }

                        // Right: Add / Added Action Button (32x32 circular)
                        Rectangle {
                            id: addBtn
                            width: 32
                            height: 32
                            radius: 16
                            z: 2
                            color: rowCard.inPl 
                                   ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25)
                                   : (addMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35) : Qt.rgba(1, 1, 1, 0.10))
                            border.color: rowCard.inPl ? root.accentColor : Qt.rgba(255, 255, 255, 0.12)
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            AppIcon {
                                anchors.centerIn: parent
                                source: rowCard.inPl ? "../assets/icons/emblem-ok-symbolic.svg" : "../assets/icons/list-add-symbolic.svg"
                                iconSize: 13
                                color: rowCard.inPl ? root.accentColor : (addMouse.containsMouse ? "#ffffff" : Qt.rgba(255, 255, 255, 0.80))
                            }

                            MouseArea {
                                id: addMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: rowCard.inPl ? Qt.ArrowCursor : Qt.PointingHandCursor
                                preventStealing: true
                                onClicked: {
                                    if (!rowCard.inPl) {
                                        var k = root.getTrackKey(trk);
                                        if (k) {
                                            var updated = Object.assign({}, root.addedTrackKeys);
                                            updated[k] = true;
                                            root.addedTrackKeys = updated;
                                        }
                                        root.trackAddRequested(trk);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Empty State Prompt (ui-layout-design-rules & PostNoteModal standard)
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: resultsList.count === 0 && !root.isSearchingOnline

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 12

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 52
                        height: 52
                        radius: 26
                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25)
                        border.width: 1

                        AppIcon {
                            anchors.centerIn: parent
                            source: root.trackSearchQuery.trim().length === 0 
                                    ? "../assets/icons/system-search-symbolic.svg" 
                                    : "../assets/icons/dialog-information-symbolic.svg"
                            iconSize: 22
                            color: root.accentColor
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.trackSearchQuery.trim().length === 0
                              ? I18n.tr("Tìm kiếm bài hát yêu thích", "Search for your favorite songs")
                              : I18n.tr("Không tìm thấy bài hát nào", "No songs found")
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                        color: "#ffffff"
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.trackSearchQuery.trim().length === 0
                              ? I18n.tr("Nhập tên bài hát hoặc nghệ sĩ để tìm kiếm, nghe thử và thêm vào danh sách", "Type song or artist to search, preview, and add to playlist")
                              : I18n.tr("Hãy thử tìm kiếm với từ khóa khác", "Try searching with different keywords")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Qt.rgba(1, 1, 1, 0.5)
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }
}

