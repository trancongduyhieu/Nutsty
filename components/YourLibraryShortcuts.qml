import QtQuick
import QtQuick.Layouts
import "."
import "cover_art.js" as CoverArt

// "Của bạn" on Home: liked songs, downloads and your playlists, one click from opening the app.
// Clicking a tile opens it; the round button plays it straight away.
ColumnLayout {
    id: root

    property color accentColor: Theme.accent
    property int likedCount: 0
    property int downloadsCount: 0
    property var playlists: []          // custom playlists, the one playing first
    property string playingId: ""       // "liked", "downloads" or a playlist id
    property bool isPlaying: false

    signal openRequested(string kind, var pl)
    signal playRequested(string kind, var pl)

    readonly property int columns: width >= 900 ? 4 : (width >= 560 ? 3 : 2)

    // Built without looking at `columns`: a new array would make the Repeater rebuild every tile
    // (and flash) each time the column count changes while the side panel slides
    readonly property int maxTiles: 8
    readonly property var entries: {
        var list = [];
        if (likedCount > 0) list.push({ kind: "liked", key: "liked", pl: null });
        if (downloadsCount > 0) list.push({ kind: "downloads", key: "downloads", pl: null });
        var pls = playlists || [];
        for (var i = 0; i < pls.length && list.length < maxTiles; i++) {
            if (pls[i] && pls[i].tracks && pls[i].tracks.length > 0)
                list.push({ kind: "playlist", key: pls[i].id || pls[i].playlistId || "", pl: pls[i] });
        }
        return list;
    }
    readonly property int shownCount: Math.min(entries.length, columns * 2)

    visible: entries.length > 0
    spacing: 12

    Text {
        text: I18n.tr("Của bạn", "Yours")
        font.family: Theme.fontFamily
        font.pixelSize: 22
        font.bold: true
        color: Theme.textPrimary
    }

    // Tiles are placed by hand rather than in a GridLayout so that, like the other Home rows,
    // their width and position follow the window with the same spring when the side panel opens
    readonly property int gap: 10
    readonly property int tileHeight: 60
    // Fewer tiles than columns: the tiles share the whole row instead of leaving a gap at the end
    readonly property int usedColumns: Math.max(1, Math.min(columns, shownCount))
    readonly property int rows: Math.ceil(shownCount / usedColumns)
    // Only the tile width springs, like the card widths of the other Home rows. Positions are
    // computed from the animated width, so neighbours always sit exactly one gap apart.
    property real tileWidth: (width - (usedColumns - 1) * gap) / usedColumns
    Behavior on tileWidth { SpringAnimation { spring: 4; damping: 0.4; epsilon: 0.25 } }
    property real gridHeight: rows * tileHeight + Math.max(0, rows - 1) * gap
    Behavior on gridHeight { SpringAnimation { spring: 4; damping: 0.4; epsilon: 0.25 } }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: root.gridHeight

        Repeater {
            model: root.entries
            delegate: Rectangle {
                id: tile
                required property var modelData
                required property int index
                x: (index % root.usedColumns) * (root.tileWidth + root.gap)
                y: Math.floor(index / root.usedColumns) * (root.tileHeight + root.gap)
                width: root.tileWidth
                height: root.tileHeight
                // Tiles beyond two rows are kept but hidden; they fade in when a column is added
                readonly property bool shown: index < root.shownCount
                opacity: shown ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                readonly property string kind: modelData.kind
                readonly property var pl: modelData.pl
                readonly property bool current: root.playingId !== "" && root.playingId === modelData.key
                readonly property string title: kind === "liked" ? I18n.tr("Bài hát yêu thích", "Liked songs")
                    : kind === "downloads" ? I18n.tr("Đã tải", "Downloads")
                    : (pl.title || pl.name || "")
                readonly property int count: kind === "liked" ? root.likedCount
                    : kind === "downloads" ? root.downloadsCount : (pl.tracks ? pl.tracks.length : 0)

                // Content layer, not glass: a thin material like the queue rows (translucent fill,
                // lighter at the top, 1px hairline). Hover and "playing" are told by the accent hairline.
                radius: 14
                gradient: Gradient {
                    GradientStop { position: 0.0; color: hover.hovered ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(1, 1, 1, 0.075) }
                    GradientStop { position: 1.0; color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, hover.hovered ? 0.10 : 0.04) }
                }
                border.width: 1
                border.color: tile.current ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                    : hover.hovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.30) : Qt.rgba(1, 1, 1, 0.10)
                Behavior on border.color { ColorAnimation { duration: 150 } }

                // Specular top edge: a 1px light line just inside the hairline
                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 2 * parent.radius
                    height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.16) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                Accessible.role: Accessible.Button
                Accessible.name: tile.title

                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.openRequested(tile.kind, tile.pl) }

                // Cover: 48px, inset 6 so its radius is concentric with the tile (14 - 6 = 8)
                Item {
                    id: art
                    width: 48; height: 48
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter

                    PlaylistCollageThumbnail {
                        anchors.fill: parent
                        visible: tile.kind === "playlist"
                        radius: 8
                        customCover: tile.pl ? (tile.pl.customCover || tile.pl.cover || "") : ""
                        tracks: tile.pl ? (tile.pl.tracks || []) : []
                        playlistTitle: tile.title
                        accentColor: root.accentColor
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: tile.kind !== "playlist"
                        radius: 8
                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                        border.width: 1
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.30)
                        AppIcon {
                            anchors.centerIn: parent
                            source: tile.kind === "liked" ? "../assets/icons/material/ms-favorite-fill.svg" : "../assets/icons/material/ms-download.svg"
                            iconSize: 20
                            color: Qt.lighter(root.accentColor, 1.2)
                        }
                    }
                    // 1px hairline on the cover edge
                    Rectangle {
                        anchors.fill: parent
                        visible: tile.kind === "playlist"
                        radius: 8
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.12)
                    }
                }

                Column {
                    anchors.left: art.right
                    anchors.leftMargin: 12
                    anchors.right: playBtn.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        width: parent.width
                        text: tile.title
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        color: tile.current ? Qt.lighter(root.accentColor, 1.25) : "#ffffff"
                    }
                    Text {
                        width: parent.width
                        text: I18n.tr(tile.count + " bài", tile.count + (tile.count === 1 ? " song" : " songs"))
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.textSecondary
                    }
                }

                // Play: shown on hover; the source that is playing keeps an equalizer mark instead
                Rectangle {
                    id: playBtn
                    width: 34; height: 34; radius: 17
                    anchors.right: parent.right
                    anchors.rightMargin: 13
                    anchors.verticalCenter: parent.verticalCenter
                    color: playArea.containsMouse ? Qt.lighter(root.accentColor, 1.12) : root.accentColor
                    opacity: hover.hovered ? 1 : 0
                    scale: hover.hovered ? 1 : 0.85
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    AppIcon {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: 1
                        source: "../assets/icons/material/ms-play_arrow-fill.svg"
                        iconSize: 18
                        color: CoverArt.contrast(root.accentColor.toString())
                    }
                    MouseArea {
                        id: playArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.playRequested(tile.kind, tile.pl)
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: I18n.tr("Phát " + tile.title, "Play " + tile.title)
                }
                AppIcon {
                    anchors.centerIn: playBtn
                    visible: tile.current && root.isPlaying && !hover.hovered
                    source: "../assets/icons/material/ms-graphic_eq.svg"
                    iconSize: 18
                    color: Qt.lighter(root.accentColor, 1.25)
                }
            }
        }
    }
}
