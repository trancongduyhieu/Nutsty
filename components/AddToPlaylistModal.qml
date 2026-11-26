import QtQuick
import QtQuick.Layouts
import "."
import "cover_art.js" as CoverArt

// "Add to playlist" picker, opened from the track context menu: one glass panel over the page lists the
// user's playlists by cover and name. A playlist that already holds the track is ticked and not clickable.
// The first row makes a new playlist with the track. Closes on the backdrop, Esc or the close button.
Rectangle {
    id: root

    anchors.fill: parent
    color: "transparent"
    visible: root.shown || panel.opacity > 0
    z: 10009

    property color accentColor: Theme.accent
    property var playlists: []
    property var track: null
    property bool shown: false
    property Item backgroundSourceItem: null
    property bool liteMode: false

    signal addRequested(var track, string playlistId)
    signal createRequested(var track)

    // Text tints keyed to the app accent, as in the create-playlist modal
    readonly property real accentHue: CoverArt.hexToOklch(accentColor.toString()).h
    readonly property color mutedText: CoverArt.oklchToHex(0.80, 0.03, accentHue)
    readonly property color faintText: Qt.rgba(1, 1, 1, 0.66)


    function openFor(t) {
        root.track = t;
        root.shown = true;
        list.contentY = 0;
        root.forceActiveFocus();
    }

    function closeModal() { root.shown = false; }

    function trackKey(t) {
        if (!t) return "";
        if (t.videoId) return String(t.videoId);
        var p = String(t.path || "");
        return p.startsWith("ytdl://") ? p.substring(7) : p;
    }

    function holds(pl) {
        var k = root.trackKey(root.track);
        var ts = (pl && pl.tracks) || [];
        if (!k) return false;
        for (var i = 0; i < ts.length; i++) if (root.trackKey(ts[i]) === k) return true;
        return false;
    }

    function pick(pl) {
        var t = root.track;
        root.closeModal();
        if (t && pl && pl.id) root.addRequested(t, pl.id);
    }

    focus: root.shown
    Keys.onEscapePressed: root.closeModal()

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.closeModal()
    }

    // Liquid glass over the app backdrop, tinted by the accent. Lite mode skips the shader:
    // without a backdrop LiquidGlass draws its tint as a plain fill, so the tint turns near opaque there.
    LiquidGlass {
        id: panel
        width: Math.min(400, root.width - 48)
        height: Math.min(col.implicitHeight + 32, root.height - 64)
        anchors.centerIn: parent
        radius: 24
        displacement: 30.0
        aberration: 0.06
        bevelWidth: 30.0
        blurRadius: 1.1
        backgroundSourceItem: root.liteMode ? null : root.backgroundSourceItem
        tintColor: Qt.rgba(0.04 + root.accentColor.r * 0.10, 0.04 + root.accentColor.g * 0.10,
                           0.06 + root.accentColor.b * 0.10, root.liteMode || !root.backgroundSourceItem ? 0.94 : 0.56)
        isFlowActive: false
        frost: 40
        opaque: true
        clip: true
        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

        // Readability: a light dark wash over the bent content, thin enough that it still shows
        Rectangle {
            anchors.fill: parent
            radius: panel.radius
            visible: !root.liteMode && !!root.backgroundSourceItem
            color: Qt.rgba(0.02, 0.02, 0.04, 0.40)
            z: 1
        }

        // Hairline, a touch brighter along the top edge where light hits the glass
        Rectangle {
            anchors.fill: parent
            radius: panel.radius
            color: "transparent"
            z: 20
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.16)
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            width: parent.width - 2 * panel.radius
            height: 1
            z: 21
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.38) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
            }
        }

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 16
            spacing: 14

            // Header: what is being added, and where
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                spacing: 12

                RoundedImage {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    radius: 8
                    source: (root.track && root.track.image) ? root.track.image : ""
                    sourceSize: Qt.size(88, 88)
                    fallbackIcon: "../assets/icons/material/ms-music_note.svg"
                    fallbackIconColor: root.accentColor
                    borderColor: Qt.rgba(1, 1, 1, 0.10)
                    borderWidth: 1
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Thêm vào danh sách phát", "Add to playlist")
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.track ? ((root.track.title || root.track.name || "") + (root.track.artist ? " · " + root.track.artist : "")) : ""
                        color: root.faintText
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    Layout.alignment: Qt.AlignTop
                    radius: 8
                    color: closeMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16) : "transparent"
                    AppIcon {
                        anchors.centerIn: parent
                        source: "../assets/icons/material/ms-close.svg"
                        color: root.mutedText
                        iconSize: 18
                    }
                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeModal()
                    }
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: contentHeight
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: [{ isNew: true }].concat(root.playlists || [])

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool isNew: !!modelData.isNew
                    readonly property bool already: !isNew && root.holds(modelData)
                    readonly property int count: (modelData.tracks && modelData.tracks.length) || 0
                    width: ListView.view.width
                    height: 60
                    radius: 12
                    color: rowMouse.containsMouse && !already ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16) : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 12
                        spacing: 12

                        // New playlist: an accent tile with a plus where a cover would be
                        Rectangle {
                            visible: row.isNew
                            Layout.preferredWidth: 48
                            Layout.preferredHeight: 48
                            radius: 8
                            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                            border.width: 1
                            AppIcon {
                                anchors.centerIn: parent
                                source: "../assets/icons/material/ms-add.svg"
                                color: root.accentColor
                                iconSize: 22
                            }
                        }

                        RoundedImage {
                            visible: !row.isNew
                            Layout.preferredWidth: 48
                            Layout.preferredHeight: 48
                            radius: 8
                            source: row.isNew ? "" : (row.modelData.customCover || row.modelData.image || "")
                            sourceSize: Qt.size(96, 96)
                            initialsText: row.isNew ? "" : (row.modelData.title || row.modelData.name || "")
                            fallbackIconColor: root.accentColor
                            borderColor: Qt.rgba(1, 1, 1, 0.10)
                            borderWidth: 1
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text {
                                Layout.fillWidth: true
                                text: row.isNew ? I18n.tr("Danh sách phát mới", "New playlist")
                                                : (row.modelData.title || row.modelData.name || I18n.tr("Danh sách phát", "Playlist"))
                                color: row.isNew ? root.accentColor : "#ffffff"
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: row.isNew ? I18n.tr("Tạo danh sách mới có sẵn bài này", "Start a new one with this song")
                                      : row.already ? I18n.tr("Đã có bài này", "Already has this song")
                                      : I18n.tr("%1 bài hát", "%1 songs").arg(row.count)
                                color: row.already ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.9) : root.faintText
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }

                        AppIcon {
                            visible: row.already
                            source: "../assets/icons/material/ms-check.svg"
                            color: root.accentColor
                            iconSize: 18
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !row.already
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (row.isNew) {
                                var t = root.track;
                                root.closeModal();
                                if (t) root.createRequested(t);
                            } else {
                                root.pick(row.modelData);
                            }
                        }
                    }
                }
            }
        }
    }
}
