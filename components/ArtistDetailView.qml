import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "."

Item {
    id: root
    Layout.fillWidth: true
    Layout.fillHeight: true

    property var artistData: null
    property bool isLoading: false
    property var currentTrack: null
    property bool isPlaying: false
    property var followedArtists: []
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent

    readonly property bool isFollowed: {
        if (!artistData || !artistData.metadata) return false;
        var chId = artistData.metadata.channelId || artistData.metadata.browseId || "";
        var aName = (artistData.metadata.name || "").toLowerCase().trim();
        if (root.followedArtists && root.followedArtists.length > 0) {
            for (var i = 0; i < root.followedArtists.length; i++) {
                var f = root.followedArtists[i];
                if ((chId && f.channelId === chId) || (aName && (f.name || "").toLowerCase().trim() === aName)) {
                    return true;
                }
            }
        }
        return !!(artistData.metadata && artistData.metadata.subscribed);
    }

    signal backRequested()
    signal playTrackRequested(var trk, int index, var trackList)
    signal startRadioRequested(var item)
    signal shuffleArtistRequested(var artistObj)
    signal viewAlbumRequested(var alb)
    signal openArtistRequested(string artistName, string channelId)
    signal trackContextMenuRequested(var trk, real mouseX, real mouseY)
    signal toggleFollowRequested(string channelId, string artistName, bool currentlyFollowed)

    // Background container (transparent to preserve acrylic window glass)
    Rectangle {
        anchors.fill: parent
        color: "transparent"
    }

    // Scrollable Content
    Flickable {
        id: mainScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentCol.implicitHeight + 80
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        clip: true

        ColumnLayout {
            id: contentCol
            width: parent.width
            spacing: 28

            // 1. Hero Artist Header
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(220, heroRow.implicitHeight + 60)

                // Ambient glow behind header (disabled to avoid foggy white/slate tint over backdrop blur)
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 280
                    visible: false
                }

                RowLayout {
                    id: heroRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 56
                    anchors.leftMargin: 28
                    anchors.rightMargin: 28
                    spacing: 24

                    // Large Round Artist Avatar
                    Item {
                        Layout.preferredWidth: 140
                        Layout.preferredHeight: 140

                        // Shimmer placeholder when loading
                        Rectangle {
                            anchors.fill: parent
                            radius: 70
                            color: "#28282c"
                            visible: heroAvatar.status !== Image.Ready
                            SequentialAnimation on opacity {
                                running: heroAvatar.status !== Image.Ready
                                loops: Animation.Infinite
                                NumberAnimation { from: 0.3; to: 0.7; duration: 800; easing.type: Easing.InOutQuad }
                                NumberAnimation { from: 0.7; to: 0.3; duration: 800; easing.type: Easing.InOutQuad }
                            }
                        }

                        Image {
                            id: heroAvatar
                            anchors.fill: parent
                            source: (root.artistData && root.artistData.metadata && root.artistData.metadata.image) ? root.artistData.metadata.image : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: false
                        }

                        Rectangle {
                            id: heroAvatarMask
                            anchors.fill: parent
                            radius: 70
                            color: "#000000"
                            visible: false
                            layer.enabled: true
                        }

                        MultiEffect {
                            anchors.fill: parent
                            source: heroAvatar
                            maskEnabled: true
                            maskSource: heroAvatarMask
                            visible: heroAvatar.status === Image.Ready
                        }

                        // Border ring
                        Rectangle {
                            anchors.fill: parent
                            radius: 70
                            color: "transparent"
                            border.color: Qt.rgba(1, 1, 1, 0.18)
                            border.width: 2
                        }
                    }

                    // Artist Info & 3 Action Buttons
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // Category Pill
                        Rectangle {
                            Layout.preferredWidth: badgeText.implicitWidth + 18
                            Layout.preferredHeight: 24
                            radius: 12
                            color: Qt.rgba(1, 1, 1, 0.10)
                            border.color: Qt.rgba(1, 1, 1, 0.16)
                            border.width: 1

                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: I18n.tr("Nghệ sĩ", "Artist")
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.bold: true
                                color: root.accentColor
                            }
                        }

                        // Artist Name
                        Text {
                            Layout.fillWidth: true
                            text: (root.artistData && root.artistData.metadata && root.artistData.metadata.name) ? root.artistData.metadata.name : (root.isLoading ? I18n.tr("Đang tải nghệ sĩ...", "Loading artist...") : I18n.tr("Nghệ sĩ", "Artist"))
                            font.family: Theme.fontFamily
                            font.pixelSize: 32
                            font.bold: true
                            color: "#ffffff"
                            elide: Text.ElideRight
                        }

                        // Stats (Subscribers & Views)
                        Text {
                            Layout.fillWidth: true
                            text: {
                                var s = "";
                                if (root.artistData && root.artistData.metadata) {
                                    if (root.artistData.metadata.subscribers) s += root.artistData.metadata.subscribers + I18n.tr(" người đăng ký", " subscribers");
                                    if (root.artistData.metadata.views) {
                                        if (s) s += " • ";
                                        s += root.artistData.metadata.views;
                                    }
                                }
                                return s || I18n.tr("Nghệ sĩ âm nhạc", "Musical Artist");
                            }
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: Theme.textMuted
                            elide: Text.ElideRight
                        }

                        Item { Layout.fillHeight: true }

                        // 3 Action Buttons: Radio, Shuffle, Subscribe
                        RowLayout {
                            spacing: 12

                            // Button 1: Radio
                            Rectangle {
                                height: 36
                                width: radRow.implicitWidth + 28
                                radius: 18
                                color: radMouse.containsMouse ? Qt.lighter(root.accentColor, 1.15) : root.accentColor
                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    id: radRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    AppIcon {
                                        source: "../assets/icons/radio-symbolic.svg"
                                        iconSize: 15
                                        color: "#0c0d10"
                                    }

                                    Text {
                                        text: I18n.tr("Đài phát", "Radio")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: "#0c0d10"
                                    }
                                }

                                MouseArea {
                                    id: radMouse
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    onClicked: {
                                        if (root.artistData && root.artistData.metadata) {
                                            root.startRadioRequested({
                                                id: root.artistData.metadata.radioId || root.artistData.metadata.channelId,
                                                name: root.artistData.metadata.name,
                                                title: root.artistData.metadata.name,
                                                isRadio: true
                                            });
                                        }
                                    }
                                }
                            }

                            // Button 2: Shuffle (Unified SSOT)
                            ShuffleButton {
                                Layout.preferredHeight: 38
                                Layout.preferredWidth: implicitWidth
                                accentColor: root.accentColor
                                text: I18n.tr("Xáo trộn", "Shuffle")
                                onClicked: {
                                    if (root.artistData) {
                                        root.shuffleArtistRequested(root.artistData);
                                    }
                                }
                            }

                            // Button 3: Follow / Subscribe (Dynamic Toggle)
                            Rectangle {
                                Layout.preferredHeight: 38
                                Layout.preferredWidth: followRow.implicitWidth + 28
                                radius: 19
                                color: root.isFollowed ? root.accentColor : (followBtnMouse.containsMouse ? "#2e2e34" : "#222226")
                                border.color: root.isFollowed ? root.accentColor : Qt.rgba(1, 1, 1, 0.18)
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    id: followRow
                                    anchors.centerIn: parent
                                    spacing: 8

                                    AppIcon {
                                        source: root.isFollowed ? "../assets/icons/emblem-ok-symbolic.svg" : "../assets/icons/list-add-symbolic.svg"
                                        iconSize: 15
                                        color: root.isFollowed ? "#000000" : "#ffffff"
                                    }

                                    Text {
                                        text: root.isFollowed ? I18n.tr("Đã theo dõi", "Following") : I18n.tr("Theo dõi", "Follow")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: root.isFollowed ? "#000000" : "#ffffff"
                                    }
                                }

                                MouseArea {
                                    id: followBtnMouse
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    onClicked: {
                                        if (root.artistData && root.artistData.metadata) {
                                            var chId = root.artistData.metadata.channelId || root.artistData.metadata.browseId || "";
                                            var aName = root.artistData.metadata.name || "";
                                            root.toggleFollowRequested(chId, aName, root.isFollowed);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // SKELETON LOADING STATE (When isLoading is true)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 28
                Layout.rightMargin: 28
                spacing: 12
                visible: root.isLoading

                Rectangle {
                    Layout.preferredWidth: 160
                    Layout.preferredHeight: 22
                    radius: 4
                    color: Qt.rgba(1, 1, 1, 0.12)
                }

                Repeater {
                    model: 5
                    SkeletonTrackRow {
                        Layout.fillWidth: true
                    }
                }
            }

            // 2. Section: Popular Songs (Phổ biến)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 28
                Layout.rightMargin: 28
                spacing: 12
                visible: !root.isLoading && (root.artistData && root.artistData.popular && root.artistData.popular.length > 0)

                Text {
                    text: I18n.tr("Phổ biến", "Popular")
                    font.family: Theme.fontFamily
                    font.pixelSize: 22
                    font.bold: true
                    color: "#ffffff"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: (root.artistData && root.artistData.popular) ? root.artistData.popular : []

                        Rectangle {
                            id: trackRowItem
                            Layout.fillWidth: true
                            Layout.preferredHeight: 56
                            color: trackRowItem.isCurrentPlaying
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                                : (rowMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                            border.color: "transparent"
                            border.width: 0
                            Behavior on color { ColorAnimation { duration: 120 } }

                            readonly property bool isCurrentPlaying: {
                                if (!root.currentTrack) return false;
                                var p1 = root.currentTrack.videoId || root.currentTrack.path;
                                var p2 = modelData.videoId || modelData.path;
                                return (p1 && p2 && p1 === p2);
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 16
                                spacing: 14

                                // Index or Play Icon
                                Item {
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20

                                    Text {
                                        anchors.centerIn: parent
                                        text: String(index + 1)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 14
                                        font.bold: true
                                        color: trackRowItem.isCurrentPlaying ? root.accentColor : Theme.textMuted
                                        visible: !rowMouseArea.containsMouse && !trackRowItem.isCurrentPlaying
                                    }

                                    // Playing soundwave indicator
                                    AppIcon {
                                        anchors.centerIn: parent
                                        source: "../assets/icons/media-optical-audio-symbolic.svg"
                                        iconSize: 16
                                        color: root.accentColor
                                        visible: trackRowItem.isCurrentPlaying && !rowMouseArea.containsMouse
                                    }

                                    // Play icon on hover
                                    AppIcon {
                                        anchors.centerIn: parent
                                        source: "../assets/icons/media-playback-start-symbolic.svg"
                                        iconSize: 16
                                        color: "#ffffff"
                                        visible: rowMouseArea.containsMouse
                                    }
                                }

                                // Track Artwork (Concentric MultiEffect Mask with zero black artifacts)
                                Item {
                                    Layout.preferredWidth: 42
                                    Layout.preferredHeight: 42

                                    Rectangle {
                                        id: artRowMask
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
                                            maskSource: artRowMask
                                            autoPaddingEnabled: false
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            color: "#202024"
                                            visible: !artRowImg.visible || artRowImg.status !== Image.Ready
                                        }

                                        Image {
                                            id: artRowImg
                                            anchors.fill: parent
                                            source: modelData.image || ""
                                            fillMode: Image.PreserveAspectCrop
                                            scale: (implicitWidth > 0 && implicitHeight > 0 && (implicitWidth / implicitHeight > 1.3)) ? 1.48 : 1.0
                                            transformOrigin: Item.Center
                                            asynchronous: true
                                            visible: status === Image.Ready
                                        }
                                    }
                                }

                                // Title & Album/Artist
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.title || modelData.name || ""
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 14
                                        font.bold: true
                                        color: trackRowItem.isCurrentPlaying ? root.accentColor : (rowMouseArea.containsMouse ? "#ffffff" : "#e0e0e4")
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.album || modelData.artist || "Single"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: Theme.textMuted
                                        elide: Text.ElideRight
                                    }
                                }

                                // Duration
                                Text {
                                    text: modelData.duration || ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    color: Theme.textMuted
                                    visible: text !== "" && text !== "--:--"
                                }
                            }

                            MouseArea {
                                id: rowMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) {
                                        var pt = trackRowItem.mapToItem(null, mouse.x, mouse.y);
                                        root.trackContextMenuRequested(modelData, pt.x, pt.y);
                                    } else {
                                        root.playTrackRequested(modelData, index, root.artistData.popular);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 3. Section: Albums Carousel
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 28
                Layout.rightMargin: 28
                spacing: 12
                visible: !root.isLoading && (root.artistData && root.artistData.albums && root.artistData.albums.length > 0)

                // Header with title and pagination arrows
                CarouselSectionHeader {
                    title: I18n.tr("Tuyển tập", "Albums")
                    targetFlickable: albumFlick
                    accentColor: root.accentColor
                }

                Flickable {
                    id: albumFlick
                    Layout.fillWidth: true
                    height: 236
                    contentWidth: albumRow.implicitWidth
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    clip: true

                    RowLayout {
                        id: albumRow
                        spacing: 16

                        Repeater {
                            model: (root.artistData && root.artistData.albums) ? root.artistData.albums : []

                            Rectangle {
                                width: 160
                                height: 228
                                radius: 10
                                color: albCardMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.08) : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 8

                                    Item {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: width

                                        Rectangle {
                                            id: albCoverMask
                                            anchors.fill: parent
                                            radius: 7
                                            color: "#ffffff"
                                            visible: false
                                            layer.enabled: true
                                        }

                                        Item {
                                            anchors.fill: parent
                                            layer.enabled: true
                                            layer.effect: MultiEffect {
                                                maskEnabled: true
                                                maskSource: albCoverMask
                                                autoPaddingEnabled: false
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                color: "#202024"
                                                visible: !albCoverImg.visible || albCoverImg.status !== Image.Ready
                                            }

                                            Image {
                                                id: albCoverImg
                                                anchors.fill: parent
                                                source: modelData.image || ""
                                                fillMode: Image.PreserveAspectCrop
                                                scale: (implicitWidth > 0 && implicitHeight > 0 && (implicitWidth / implicitHeight > 1.3)) ? 1.48 : 1.0
                                                transformOrigin: Item.Center
                                                asynchronous: true
                                                visible: status === Image.Ready
                                            }
                                        }

                                        // Play hover pill
                                        Rectangle {
                                            width: 36
                                            height: 36
                                            radius: 18
                                            color: root.accentColor
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.margins: 6
                                            visible: albCardMouse.containsMouse
                                            z: 2

                                            AppIcon {
                                                anchors.centerIn: parent
                                                anchors.horizontalCenterOffset: 1
                                                source: "../assets/icons/media-playback-start-symbolic.svg"
                                                iconSize: 16
                                                color: "#000000"
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.title || ""
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: "#ffffff"
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: (modelData.year ? (modelData.year + " • ") : "") + (modelData.type || "Album")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: Theme.textMuted
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: albCardMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.viewAlbumRequested(modelData);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 4. Section: Singles & EPs Carousel
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 28
                Layout.rightMargin: 28
                spacing: 12
                visible: !root.isLoading && (root.artistData && root.artistData.singles && root.artistData.singles.length > 0)

                // Header with title and pagination arrows
                CarouselSectionHeader {
                    title: I18n.tr("Đĩa đơn & EPs", "Singles & EPs")
                    targetFlickable: singleFlick
                    accentColor: root.accentColor
                }

                Flickable {
                    id: singleFlick
                    Layout.fillWidth: true
                    height: 236
                    contentWidth: singleRow.implicitWidth
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    clip: true

                    RowLayout {
                        id: singleRow
                        spacing: 16

                        Repeater {
                            model: (root.artistData && root.artistData.singles) ? root.artistData.singles : []

                            Rectangle {
                                width: 160
                                height: 228
                                radius: 10
                                color: singleCardMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.08) : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 8

                                    Item {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: width

                                        Rectangle {
                                            id: singleCoverMask
                                            anchors.fill: parent
                                            radius: 7
                                            color: "#ffffff"
                                            visible: false
                                            layer.enabled: true
                                        }

                                        Item {
                                            anchors.fill: parent
                                            layer.enabled: true
                                            layer.effect: MultiEffect {
                                                maskEnabled: true
                                                maskSource: singleCoverMask
                                                autoPaddingEnabled: false
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                color: "#202024"
                                                visible: !singleCoverImg.visible || singleCoverImg.status !== Image.Ready
                                            }

                                            Image {
                                                id: singleCoverImg
                                                anchors.fill: parent
                                                source: modelData.image || ""
                                                fillMode: Image.PreserveAspectCrop
                                                scale: (implicitWidth > 0 && implicitHeight > 0 && (implicitWidth / implicitHeight > 1.3)) ? 1.48 : 1.0
                                                transformOrigin: Item.Center
                                                asynchronous: true
                                                visible: status === Image.Ready
                                            }
                                        }

                                        // Play hover pill
                                        Rectangle {
                                            width: 36
                                            height: 36
                                            radius: 18
                                            color: root.accentColor
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.margins: 6
                                            visible: singleCardMouse.containsMouse
                                            z: 2

                                            AppIcon {
                                                anchors.centerIn: parent
                                                anchors.horizontalCenterOffset: 1
                                                source: "../assets/icons/media-playback-start-symbolic.svg"
                                                iconSize: 16
                                                color: "#000000"
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.title || ""
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: "#ffffff"
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: (modelData.year ? (modelData.year + " • ") : "") + I18n.tr("Đĩa đơn", "Single")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: Theme.textMuted
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: singleCardMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.viewAlbumRequested(modelData);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 5. Section: Videos Carousel
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 28
                Layout.rightMargin: 28
                spacing: 12
                visible: !root.isLoading && (root.artistData && root.artistData.videos && root.artistData.videos.length > 0)

                CarouselSectionHeader {
                    title: I18n.tr("Video âm nhạc", "Music Videos")
                    targetFlickable: videoFlick
                    accentColor: root.accentColor
                }

                Flickable {
                    id: videoFlick
                    Layout.fillWidth: true
                    height: 180
                    contentWidth: videoRow.implicitWidth
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    clip: true

                    RowLayout {
                        id: videoRow
                        spacing: 16

                        Repeater {
                            model: (root.artistData && root.artistData.videos) ? root.artistData.videos : []

                            Rectangle {
                                width: 220
                                height: 172
                                radius: 10
                                color: vidCardMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.08) : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8

                                    // Video thumbnail (16:9 MultiEffect Mask with zero black artifacts)
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 114

                                        Rectangle {
                                            id: vidThumbMask
                                            anchors.fill: parent
                                            radius: 5.5
                                            color: "#ffffff"
                                            visible: false
                                            layer.enabled: true
                                        }

                                        Item {
                                            anchors.fill: parent
                                            layer.enabled: true
                                            layer.effect: MultiEffect {
                                                maskEnabled: true
                                                maskSource: vidThumbMask
                                                autoPaddingEnabled: false
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                color: "#202024"
                                                visible: !vidCoverImg.visible || vidCoverImg.status !== Image.Ready
                                            }

                                            Image {
                                                id: vidCoverImg
                                                anchors.fill: parent
                                                source: modelData.image || ""
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                visible: status === Image.Ready
                                            }
                                        }

                                        // Play hover icon
                                        Rectangle {
                                            width: 34
                                            height: 34
                                            radius: 17
                                            color: root.accentColor
                                            anchors.centerIn: parent
                                            visible: vidCardMouse.containsMouse
                                            z: 2

                                            AppIcon {
                                                anchors.centerIn: parent
                                                anchors.horizontalCenterOffset: 1
                                                source: "../assets/icons/media-playback-start-symbolic.svg"
                                                iconSize: 15
                                                color: "#000000"
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.title || ""
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: "#ffffff"
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.views || I18n.tr("Video âm nhạc", "Music Video")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Theme.textMuted
                                        elide: Text.ElideRight
                                        visible: text !== ""
                                    }
                                }

                                MouseArea {
                                    id: vidCardMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var trk = {
                                            title: modelData.title,
                                            name: modelData.title,
                                            artist: (root.artistData && root.artistData.metadata) ? root.artistData.metadata.name : "Artist",
                                            videoId: modelData.videoId,
                                            path: "ytdl://" + modelData.videoId,
                                            image: modelData.image
                                        };
                                        root.playTrackRequested(trk, 0, [trk]);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 6. Section: Similar Artists Carousel
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 28
                Layout.rightMargin: 28
                spacing: 12
                visible: !root.isLoading && (root.artistData && root.artistData.related && root.artistData.related.length > 0)

                CarouselSectionHeader {
                    title: I18n.tr("Nghệ sĩ liên quan", "Fans Also Like")
                    targetFlickable: relFlick
                    accentColor: root.accentColor
                }

                Flickable {
                    id: relFlick
                    Layout.fillWidth: true
                    height: 196
                    contentWidth: relRow.implicitWidth
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    clip: true

                    RowLayout {
                        id: relRow
                        spacing: 20

                        Repeater {
                            model: (root.artistData && root.artistData.related) ? root.artistData.related : []

                            Rectangle {
                                width: 140
                                height: 188
                                radius: 10
                                color: relCardMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 8

                                    // Round Avatar
                                    Item {
                                        Layout.preferredWidth: 108
                                        Layout.preferredHeight: 108
                                        Layout.alignment: Qt.AlignHCenter

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 54
                                            color: "#26262a"
                                            visible: relAvatarImg.status !== Image.Ready
                                        }

                                        Image {
                                            id: relAvatarImg
                                            anchors.fill: parent
                                            source: modelData.image || ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            visible: false
                                        }

                                        Rectangle {
                                            id: relAvatarMask
                                            anchors.fill: parent
                                            radius: 54
                                            color: "#ffffff"
                                            visible: false
                                            layer.enabled: true
                                        }

                                        MultiEffect {
                                            anchors.fill: parent
                                            source: relAvatarImg
                                            maskEnabled: true
                                            maskSource: relAvatarMask
                                            visible: relAvatarImg.status === Image.Ready
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 54
                                            color: "transparent"
                                            border.color: relCardMouse.containsMouse ? root.accentColor : "transparent"
                                            border.width: 1.5
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.name || modelData.title || ""
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: relCardMouse.containsMouse ? root.accentColor : "#ffffff"
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.subscribers ? (modelData.subscribers + I18n.tr(" người đăng ký", " subs")) : I18n.tr("Nghệ sĩ", "Artist")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Theme.textMuted
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: relCardMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.openArtistRequested(modelData.name || modelData.title, modelData.browseId);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 7. Section: Bio / Description Card
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 28
                Layout.rightMargin: 28
                spacing: 12
                visible: !root.isLoading && (root.artistData && root.artistData.metadata && root.artistData.metadata.description)

                Text {
                    text: I18n.tr("Giới thiệu", "About")
                    font.family: Theme.fontFamily
                    font.pixelSize: 22
                    font.bold: true
                    color: "#ffffff"
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: bioCol.implicitHeight + 32
                    radius: 12
                    color: "#161618"
                    border.color: "#28282c"
                    border.width: 1

                    property bool isExpanded: false

                    ColumnLayout {
                        id: bioCol
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        Text {
                            Layout.fillWidth: true
                            text: (root.artistData && root.artistData.metadata) ? root.artistData.metadata.description : ""
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            lineHeight: 1.4
                            color: "#c8c8cc"
                            wrapMode: Text.Wrap
                            maximumLineCount: parent.parent.isExpanded ? 100 : 4
                            elide: Text.ElideRight
                        }

                        Text {
                            text: parent.parent.isExpanded ? I18n.tr("Thu gọn ▲", "Show less ▲") : I18n.tr("Xem thêm ▼", "Show more ▼")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                            color: root.accentColor
                            visible: ((root.artistData && root.artistData.metadata && root.artistData.metadata.description) ? root.artistData.metadata.description.length : 0) > 220

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: parent.parent.parent.isExpanded = !parent.parent.parent.isExpanded
                            }
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 30 }
        }
    }

    // Top Floating Navigation (Back Button only, no black header bar)
    Item {
        anchors.left: parent.left
        anchors.top: parent.top
        width: 80
        height: 60
        z: 10

        // Floating Back Button
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 20
            width: 36
            height: 36
            radius: 18
            color: backMouse.containsMouse ? "#323236" : Qt.rgba(0, 0, 0, 0.55)
            border.color: Qt.rgba(1, 1, 1, 0.15)
            border.width: 1
            Behavior on color { ColorAnimation { duration: 100 } }

            AppIcon {
                anchors.centerIn: parent
                source: "../assets/icons/go-previous-symbolic.svg"
                iconSize: 16
                color: "#ffffff"
            }

            MouseArea {
                id: backMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: root.backRequested()
            }
        }
    }
}
