import QtQuick
import "."

// Tab words at the bottom of the Mochy side panel: Lyrics, YouTube comments, Up Next. The active
// word is filled with the accent at full size; the others are smaller outlines on the same baseline.
Item {
    id: root

    property string activeTab: "lyrics"
    property color accentColor: "#ffffff"

    signal lyricsClicked()
    signal commentsClicked()
    signal queueClicked()

    readonly property var tabs: ["lyrics", "comments", "queue"]
    readonly property int activeIndex: Math.max(0, tabs.indexOf(activeTab))

    function activate(i) {
        if (i === 0) root.lyricsClicked();
        else if (i === 1) root.commentsClicked();
        else root.queueClicked();
    }

    implicitHeight: 50
    implicitWidth: 240

    FontLoader { id: heavyFont; source: "../assets/fonts/Montserrat-Black.ttf" }
    readonly property string heavyFamily: (heavyFont.status === FontLoader.Ready && heavyFont.name !== "") ? heavyFont.name : "Montserrat"
    readonly property real wordPx: 32
    readonly property real wordSqueeze: 0.72

    Row {
        id: wordRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        spacing: 22

        Repeater {
            model: [
                I18n.tr("LỜI", "LYRICS"),
                I18n.tr("BÌNH LUẬN", "COMMENTS"),
                I18n.tr("TIẾP THEO", "UP NEXT")
            ]

            delegate: Item {
                id: word
                required property string modelData
                required property int index
                readonly property bool active: root.activeIndex === word.index
                // Inactive words sit smaller on the same baseline
                property real s: active ? 1.0 : (wordH.hovered ? 0.72 : 0.64)
                Behavior on s { NumberAnimation { duration: 280; easing.type: Easing.OutBack } }

                width: Math.ceil(fill.implicitWidth * root.wordSqueeze * word.s)
                height: Math.round(root.wordPx * 0.86)

                Item {
                    id: glyphs
                    width: fill.implicitWidth * root.wordSqueeze
                    height: parent.height
                    transform: Scale { origin.x: 0; origin.y: glyphs.height; xScale: word.s; yScale: word.s }

                    OutlineType {
                        lines: [word.modelData]
                        pixelSize: root.wordPx
                        squeeze: root.wordSqueeze
                        strokeWidth: 1.6
                        strokeColor: Qt.rgba(1, 1, 1, wordH.hovered ? 0.85 : 0.6)
                        opacity: word.active ? 0 : 1
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                    Text {
                        id: fill
                        text: word.modelData
                        y: Math.round(root.wordPx * 0.80) - fill.baselineOffset
                        font.family: root.heavyFamily
                        font.pixelSize: root.wordPx
                        font.weight: Font.Black
                        color: root.accentColor
                        opacity: word.active ? 1 : 0
                        transform: Scale { xScale: root.wordSqueeze }
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                }

                HoverHandler { id: wordH; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -10
                    onClicked: root.activate(word.index)
                }
            }
        }
    }
}
