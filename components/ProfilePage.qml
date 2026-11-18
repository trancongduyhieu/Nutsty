import QtQuick
import QtQuick.Layouts

// The profile page that opens out of the listener card: photo, name and card number at the top
// (the morph flies them in from the card), then listening totals per period, what you played
// lately, your playlists and the artists you play most.
Item {
    id: root

    property string userName: ""
    property string avatarUrl: ""
    property string cardNumber: "NTY-0000-0000"
    property color accentColor: Theme.accent
    property bool liteMode: false
    property var playlists: []
    property var overview: null      // { periods, recent, artists } from /api/listening/profile
    // False while the flying copies are still in the air; the real ones take over on landing
    property bool landed: true
    // 0..1: the rows under the name rising in, one after another
    property real reveal: 1

    readonly property Item photoSlot: photo
    readonly property Item nameSlot: nameText
    readonly property Item numberSlot: numberText
    readonly property Item scroller: flick

    signal backRequested()
    signal trackRequested(var row)
    signal artistRequested(string name)
    signal playlistRequested(var playlist)

    readonly property color glassFill: Qt.rgba(0.04 + root.accentColor.r * 0.08, 0.04 + root.accentColor.g * 0.08,
                                               0.06 + root.accentColor.b * 0.10, 0.46)
    readonly property color softText: Qt.rgba(1, 1, 1, 0.62)
    // Quiet white for the big figures: reads as grey on any wallpaper without going dead grey
    readonly property color figureColor: Qt.rgba(1, 1, 1, 0.46)
    function rowProgress(i) {
        return Math.max(0, Math.min(1, (root.reveal - i * 0.1) / 0.5));
    }
    function periodLabel(key) {
        if (key === "week") return I18n.tr("7 NGÀY", "7 DAYS");
        if (key === "month") return I18n.tr("30 NGÀY", "30 DAYS");
        return I18n.tr("TẤT CẢ", "ALL TIME");
    }
    function timeFigure(minutes) {
        if (minutes < 60) return { value: minutes, unit: I18n.tr("Phút", minutes === 1 ? "Min" : "Mins") };
        var h = Math.floor(minutes / 60);
        return { value: h, unit: I18n.tr("Giờ", h === 1 ? "Hour" : "Hours") };
    }
    // Long numbers step down a size so the unit keeps its room
    function figureScale(value) {
        var n = String(value).length;
        return n >= 5 ? 0.7 : n === 4 ? 0.8 : n === 3 ? 0.9 : 1;
    }
    function fmt(n) { return Number(n || 0).toLocaleString(root.numberLocale, "f", 0); }

    readonly property var periods: (root.overview && root.overview.periods) ? root.overview.periods
                                    : [{ key: "week", plays: 0, songs: 0, total_minutes: 0 },
                                       { key: "month", plays: 0, songs: 0, total_minutes: 0 },
                                       { key: "all", plays: 0, songs: 0, total_minutes: 0 }]

    // A titled row of covers that pages sideways with the shared arrows
    component CoverRow: ColumnLayout {
        id: coverRow
        property string title: ""
        property string emptyText: ""
        property var items: []
        property int rowIndex: 0
        property bool round: false
        property Component card
        readonly property real cardWidth: 148
        Layout.fillWidth: true
        spacing: 12
        opacity: root.rowProgress(rowIndex)
        transform: Translate { y: (1 - root.rowProgress(coverRow.rowIndex)) * 24 }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: coverRow.title
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: 17
                font.weight: Font.Bold
                font.letterSpacing: -0.3
            }
            NavArrowButton {
                visible: list.contentWidth > list.width + 4
                direction: "left"
                accentColor: root.accentColor
                btnSize: 32
                iconSize: 14
                canScroll: list.contentX > 2
                onClicked: list.contentX = Math.max(0, list.contentX - (coverRow.cardWidth + 16) * 3)
            }
            NavArrowButton {
                visible: list.contentWidth > list.width + 4
                direction: "right"
                accentColor: root.accentColor
                btnSize: 32
                iconSize: 14
                canScroll: list.contentX < list.contentWidth - list.width - 2
                onClicked: list.contentX = Math.min(list.contentWidth - list.width, list.contentX + (coverRow.cardWidth + 16) * 3)
            }
        }

        Text {
            visible: coverRow.items.length === 0
            Layout.fillWidth: true
            text: coverRow.emptyText
            wrapMode: Text.WordWrap
            color: root.softText
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        ListView {
            id: list
            visible: coverRow.items.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: coverRow.cardWidth + 48
            orientation: ListView.Horizontal
            spacing: 16
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: coverRow.items
            Behavior on contentX { enabled: !root.liteMode; NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            // The card component is written where the row is used, so model roles reach it from the view
            delegate: coverRow.card
        }
        ScrollEdgeFade {
            flickable: list
            horizontal: true
            fadeLength: 32
        }
    }

    // One cover with a title and a line under it
    component CoverCard: Item {
        id: coverCard
        property string image: ""
        property string title: ""
        property string subtitle: ""
        property bool round: false
        signal activated()
        width: 148
        height: ListView.view ? ListView.view.height : 196

        HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: coverCard.activated() }

        RoundedImage {
            id: cover
            width: parent.width
            height: width
            radius: coverCard.round ? width / 2 : 12
            // A fixed decode size, as the other cover grids use; without it the zoom loops on 4:3 thumbnails
            sourceSize: Qt.size(296, 296)
            source: coverCard.image
            initialsText: coverCard.title
            fallbackIcon: Qt.resolvedUrl("../assets/icons/media-optical-audio-symbolic.svg")
            fallbackIconColor: root.accentColor
            borderColor: cardHover.hovered ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.07)
            borderWidth: 1
            scale: cardHover.hovered && !root.liteMode ? 1.03 : 1
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
        Text {
            anchors.top: cover.bottom
            anchors.topMargin: 8
            width: parent.width
            horizontalAlignment: coverCard.round ? Text.AlignHCenter : Text.AlignLeft
            text: coverCard.title
            elide: Text.ElideRight
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        Text {
            anchors.top: cover.bottom
            anchors.topMargin: 27
            width: parent.width
            horizontalAlignment: coverCard.round ? Text.AlignHCenter : Text.AlignLeft
            text: coverCard.subtitle
            elide: Text.ElideRight
            color: root.softText
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: Font.Medium
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + 72
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: column
            width: Math.min(parent.width - 48, 860)
            anchors.horizontalCenter: parent.horizontalCenter
            // Clears the pinned back button at any window width
            y: 60
            spacing: 0

            RoundedImage {
                id: photo
                Layout.topMargin: 8
                Layout.preferredWidth: 120
                Layout.preferredHeight: 120
                radius: 60
                source: root.avatarUrl
                initialsText: root.userName
                borderColor: Qt.rgba(1, 1, 1, 0.12)
                borderWidth: 1
                opacity: root.landed ? 1 : 0
            }

            // Name, with the card number in small mono type under it
            Text {
                id: nameText
                Layout.fillWidth: true
                Layout.topMargin: 18
                elide: Text.ElideRight
                text: root.userName
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: 56
                font.weight: Font.Bold
                font.letterSpacing: -2.6
                lineHeight: 1.05
                opacity: root.landed ? 1 : 0
            }
            Text {
                id: numberText
                Layout.fillWidth: true
                Layout.topMargin: 2
                text: "NUTSTY  " + root.cardNumber
                color: Qt.rgba(1, 1, 1, 0.7)
                font.family: "monospace"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                font.letterSpacing: -0.4
                opacity: root.landed ? 1 : 0
            }

            // Totals for three periods
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 36
                spacing: 14
                Repeater {
                    model: root.periods
                    delegate: Rectangle {
                        id: periodCard
                        required property var modelData
                        required property int index
                        readonly property var time: root.timeFigure(modelData.total_minutes || 0)
                        readonly property real p: root.rowProgress(2 + index * 0.4)
                        Layout.fillWidth: true
                        Layout.preferredHeight: periodBody.implicitHeight + 36
                        radius: 18
                        color: root.glassFill
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        opacity: p
                        transform: Translate { y: (1 - periodCard.p) * 24 }

                        ColumnLayout {
                            id: periodBody
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: 22
                            anchors.rightMargin: 16
                            anchors.topMargin: 18
                            spacing: 4
                            // "Total listens" with the period as a small mono tag on its baseline
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text {
                                    Layout.alignment: Qt.AlignBaseline
                                    text: I18n.tr("Tổng lượt nghe", "Total listens")
                                    color: Theme.textPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 17
                                    font.weight: Font.Bold
                                    font.letterSpacing: -0.7
                                }
                                Text {
                                    Layout.alignment: Qt.AlignBaseline
                                    Layout.fillWidth: true
                                    text: root.periodLabel(periodCard.modelData.key)
                                    elide: Text.ElideRight
                                    color: Qt.rgba(1, 1, 1, 0.5)
                                    font.family: "monospace"
                                    font.pixelSize: 10
                                    font.letterSpacing: 0.6
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 22
                                Repeater {
                                    model: [
                                        { value: periodCard.modelData.songs || 0,
                                          unit: I18n.tr("Bài", (periodCard.modelData.songs || 0) === 1 ? "Song" : "Songs") },
                                        { value: periodCard.time.value, unit: periodCard.time.unit }
                                    ]
                                    // Big quiet figures; the title above carries the emphasis
                                    delegate: RowLayout {
                                        id: figure
                                        required property var modelData
                                        readonly property real k: root.figureScale(modelData.value)
                                        spacing: 4
                                        Text {
                                            text: root.fmt(figure.modelData.value)
                                            color: root.figureColor
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Math.round(44 * figure.k)
                                            font.weight: Font.Bold
                                            font.letterSpacing: -2
                                            font.features: { "tnum": 1 }
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignBottom
                                            Layout.bottomMargin: Math.round(7 * figure.k)
                                            text: figure.modelData.unit
                                            color: root.figureColor
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Math.round(19 * figure.k)
                                            font.weight: Font.Bold
                                            font.letterSpacing: -0.6
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            CoverRow {
                Layout.topMargin: 40
                rowIndex: 3
                title: I18n.tr("Nghe gần đây", "Recently played")
                emptyText: I18n.tr("Bài bạn nghe sẽ hiện ở đây.", "Songs you play will show up here.")
                items: (root.overview && root.overview.recent) ? root.overview.recent : []
                card: CoverCard {
                    image: modelData.cover_url || ""
                    title: modelData.title || ""
                    subtitle: modelData.artist || ""
                    onActivated: root.trackRequested(modelData)
                }
            }

            CoverRow {
                Layout.topMargin: 32
                rowIndex: 4
                title: I18n.tr("Danh sách phát", "Playlists")
                emptyText: I18n.tr("Bạn chưa tạo danh sách phát nào.", "You haven't made a playlist yet.")
                items: root.playlists || []
                card: CoverCard {
                    image: modelData.customCover || modelData.image || modelData.cover || ""
                    title: modelData.title || modelData.name || ""
                    subtitle: {
                        var n = (modelData.tracks && modelData.tracks.length) ? modelData.tracks.length : 0;
                        return I18n.tr(root.fmt(n) + " bài", root.fmt(n) + (n === 1 ? " song" : " songs"));
                    }
                    onActivated: root.playlistRequested(modelData)
                }
            }

            CoverRow {
                Layout.topMargin: 32
                rowIndex: 5
                title: I18n.tr("Nghệ sĩ nghe nhiều", "Your top artists")
                emptyText: I18n.tr("Nghe thêm vài bài là nghệ sĩ của bạn sẽ hiện ở đây.",
                                   "Play a few more songs and your artists will show up here.")
                items: (root.overview && root.overview.artists) ? root.overview.artists : []
                card: CoverCard {
                    round: true
                    image: modelData.cover_url || ""
                    title: modelData.artist || ""
                    subtitle: I18n.tr(root.fmt(modelData.plays) + " lượt nghe",
                                      root.fmt(modelData.plays) + (modelData.plays === 1 ? " play" : " plays"))
                    onActivated: root.artistRequested(modelData.artist || "")
                }
            }
        }
    }

    // Content softens out at the top and bottom edges while there is more to scroll
    ScrollEdgeFade {
        flickable: flick
        fadeLength: 40
    }

    // Back: pinned top left like the other detail pages, so it stays put while the page scrolls
    Rectangle {
        id: backButton
        x: 20
        y: 16
        z: 10
        width: 36
        height: 36
        radius: 18
        color: Qt.rgba(root.accentColor.r * 0.35, root.accentColor.g * 0.35, root.accentColor.b * 0.35,
                       backHover.hovered ? 0.85 : 0.6)
        border.width: 1
        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, backHover.hovered ? 0.5 : 0.28)
        opacity: root.rowProgress(0)
        Behavior on color { ColorAnimation { duration: 150 } }
        AppIcon {
            anchors.centerIn: parent
            source: Qt.resolvedUrl("../assets/icons/go-previous-symbolic.svg")
            iconSize: 16
            color: Theme.textPrimary
        }
        HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.backRequested() }
    }
}
