import QtQuick
import "."

// Preset 8's own settings, laid over the settings dialog: a large live preview on top, then the
// effect set (auto or forced), how many lines peak, how many doodles, and the old film look.
// Every change is sent up as changeOption(key, value); the preview redraws from `options`.
Rectangle {
    id: root

    property bool open: false
    property var options: ({})
    property color accentColor: Theme.accent
    property bool lite: false

    property string wallpaperSource: ""
    property string magicFontFamily: "Instrument Serif"
    property var activeLyrics: []
    property real currentTime: 0.0
    property bool isPlaying: false
    property var currentTrack: null
    property bool isDemo: true
    property bool lyricsRomanizationEnabled: true
    property color colHighlight: "#deb06c"
    property color colActiveText: "#f8fafc"
    property color colDeadText: "#f1f5f9"
    property color colShadowDir: "#a6020305"
    property color colShadowAmb: "#66000000"
    property bool isLightArea: false

    signal changeOption(string key, var value)
    signal closed()

    readonly property string setValue: (root.options && root.options.set) ? root.options.set : "auto"
    readonly property string peaksValue: (root.options && root.options.peaks) ? root.options.peaks : "natural"
    readonly property string doodlesValue: (root.options && root.options.doodles) ? root.options.doodles : "normal"
    readonly property bool filmValue: !(root.options && root.options.film === false)
    readonly property bool isDefault: root.setValue === "auto" && root.peaksValue === "natural"
                                      && root.doodlesValue === "normal" && root.filmValue
    // The set chip under the pointer, else the chosen one: its description is shown below the chips
    property string hoverSet: ""
    readonly property string aboutSet: root.hoverSet !== "" ? root.hoverSet
                                       : (root.setValue === "auto" ? preview.autoSet : root.setValue)

    readonly property int pad: 20
    readonly property int motionMs: root.lite ? 0 : 160

    visible: opacity > 0
    opacity: root.open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: root.motionMs; easing.type: Easing.OutCubic } }
    radius: 20
    color: Qt.rgba(0.06 + root.accentColor.r * 0.08, 0.06 + root.accentColor.g * 0.08, 0.08 + root.accentColor.b * 0.12, 1.0)
    border.width: 1
    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)

    // Swallow clicks and wheel so nothing behind the panel reacts
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onWheel: (wheel) => wheel.accepted = true
    }

    Keys.onEscapePressed: root.closed()
    onOpenChanged: if (open) { body.contentY = 0; root.forceActiveFocus(); }

    // ---- Header -------------------------------------------------------------------------------
    Item {
        id: header
        x: root.pad
        y: 16
        width: root.width - root.pad * 2
        height: 40
        transform: Translate { y: root.open ? 0 : 8; Behavior on y { NumberAnimation { duration: root.motionMs; easing.type: Easing.OutCubic } } }

        IconButton {
            id: backBtn
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            icon: "../assets/icons/go-previous-symbolic.svg"
            onClicked: root.closed()
        }

        Column {
            anchors.left: backBtn.right
            anchors.leftMargin: 12
            anchors.right: resetBtn.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: I18n.tr("Tùy chỉnh Mẫu 8", "Customize preset 8")
                font.family: Theme.fontFamily
                font.pixelSize: 16
                font.bold: true
                color: "#ffffff"
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: I18n.tr("Thay đổi áp dụng ngay cho lời bài hát trên màn hình", "Changes apply right away to the lyrics on your desktop")
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.textSecondary
                elide: Text.ElideRight
            }
        }

        // Back to defaults; quiet until something differs from them
        Rectangle {
            id: resetBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: resetRow.implicitWidth + 20
            height: 30
            radius: 8
            opacity: root.isDefault ? 0.45 : 1.0
            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, resetMouse.containsMouse && !root.isDefault ? 0.22 : 0.12)
            border.width: 1
            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, resetMouse.containsMouse && !root.isDefault ? 0.45 : 0.25)
            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on opacity { NumberAnimation { duration: 150 } }

            Row {
                id: resetRow
                anchors.centerIn: parent
                spacing: 6
                AppIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    source: "../assets/icons/view-refresh-symbolic.svg"
                    iconSize: 12
                    color: root.accentColor
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Mặc định", "Defaults")
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                    color: "#ffffff"
                }
            }

            MouseArea {
                id: resetMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !root.isDefault
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.changeOption("set", "auto");
                    root.changeOption("peaks", "natural");
                    root.changeOption("doodles", "normal");
                    root.changeOption("film", true);
                }
            }
        }
    }

    // ---- Body ---------------------------------------------------------------------------------
    Flickable {
        id: body
        anchors.top: header.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 1
        anchors.leftMargin: 1
        anchors.rightMargin: 1
        clip: true
        contentWidth: width
        contentHeight: content.implicitHeight + root.pad
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
            id: content
            x: root.pad - 1
            width: body.width - (root.pad - 1) * 2
            spacing: 22

            // Live preview: plays only while the panel is open
            LyricsPresetPreview {
                id: preview
                width: parent.width
                height: Math.round(width * 0.42)
                radius: 12
                meta: LyricsPresets.get(8)
                loaded: root.open
                live: root.open
                selected: false
                isDemo: root.isDemo
                showSet: true
                accentColor: root.accentColor
                wallpaperSource: root.wallpaperSource
                magicFontFamily: root.magicFontFamily
                activeLyrics: root.activeLyrics
                currentTime: root.currentTime
                isPlaying: root.isPlaying
                currentTrack: root.currentTrack
                lyricsRomanizationEnabled: root.lyricsRomanizationEnabled
                kineticOptions: root.options
                colHighlight: root.colHighlight
                colActiveText: root.colActiveText
                colDeadText: root.colDeadText
                colShadowDir: root.colShadowDir
                colShadowAmb: root.colShadowAmb
                isLightArea: root.isLightArea
            }

            // -- Effect set
            Column {
                width: parent.width
                spacing: 10

                SectionHead {
                    title: I18n.tr("Bộ hiệu ứng", "Effect set")
                    note: {
                        var s = LyricsPresets.kineticSet(preview.autoSet);
                        var name = I18n.tr(s.vi, s.en);
                        var t = root.currentTrack;
                        var song = (!root.isDemo && t && t.title) ? t.title : "";
                        if (song !== "")
                            return I18n.tr("Thể loại của “" + song + "” hợp với bộ " + name,
                                           "“" + song + "” fits the " + name + " set");
                        return I18n.tr("Bài mẫu hợp với bộ " + name, "The demo song fits the " + name + " set");
                    }
                }

                Flow {
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: [{ key: "auto" }].concat(LyricsPresets.kineticSets)

                        delegate: Chip {
                            required property var modelData
                            readonly property bool isAuto: modelData.key === "auto"
                            label: isAuto ? I18n.tr("Tự động", "Auto") : I18n.tr(modelData.vi, modelData.en)
                            // Auto names the set it lands on, so nobody has to guess
                            hint: {
                                if (!isAuto || preview.autoSet === "") return "";
                                var s = LyricsPresets.kineticSet(preview.autoSet);
                                return I18n.tr(s.vi, s.en);
                            }
                            selected: root.setValue === modelData.key
                            onHoveredChanged: {
                                if (hovered) root.hoverSet = isAuto ? preview.autoSet : modelData.key;
                                else if (root.hoverSet === (isAuto ? preview.autoSet : modelData.key)) root.hoverSet = "";
                            }
                            onClicked: root.changeOption("set", modelData.key)
                        }
                    }
                }

                Text {
                    width: parent.width
                    readonly property var s: LyricsPresets.kineticSet(root.aboutSet)
                    text: I18n.tr(s.aboutVi, s.aboutEn)
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.textSecondary
                    wrapMode: Text.WordWrap
                }
            }

            // -- Peaks
            OptionRow {
                title: I18n.tr("Câu cao trào", "Peak lines")
                note: root.peaksValue === "every"
                      ? I18n.tr("Câu nào cũng bung hiệu ứng lớn", "Every line gets a big move")
                      : root.peaksValue === "more"
                        ? I18n.tr("Bung thường xuyên hơn, nhưng không hai câu liền nhau", "More often, but never two lines in a row")
                        : I18n.tr("Chỉ bung khi bài hát chậm lại hoặc ngân dài", "Only when the song slows down or holds a note")
                choices: [
                    { key: "natural", label: I18n.tr("Tự nhiên", "Natural") },
                    { key: "more",    label: I18n.tr("Nhiều", "More") },
                    { key: "every",   label: I18n.tr("Mọi câu", "Every line") }
                ]
                value: root.peaksValue
                onChosen: (key) => root.changeOption("peaks", key)
            }

            // -- Doodles
            OptionRow {
                title: I18n.tr("Hình vẽ", "Doodles")
                note: root.doodlesValue === "few"
                      ? I18n.tr("Gọn gàng, chữ là chính", "Tidy, the words lead")
                      : root.doodlesValue === "lots"
                        ? I18n.tr("Vẽ dày quanh từng câu", "Drawn thick around every line")
                        : I18n.tr("Vừa đủ quanh các câu", "A few around each line")
                choices: [
                    { key: "few",    label: I18n.tr("Ít", "Few") },
                    { key: "normal", label: I18n.tr("Vừa", "Some") },
                    { key: "lots",   label: I18n.tr("Nhiều", "Lots") }
                ]
                value: root.doodlesValue
                onChosen: (key) => root.changeOption("doodles", key)
            }

            // -- Film look
            Item {
                width: parent.width
                height: Math.max(filmHead.implicitHeight, 26)

                SectionHead {
                    id: filmHead
                    anchors.left: parent.left
                    anchors.right: filmToggle.left
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    title: I18n.tr("Chất phim cũ", "Old film look")
                    note: I18n.tr("Hạt nhiễu và vệt xước như cuộn phim chiếu bóng", "Grain and scratches like a reel of film")
                }

                Rectangle {
                    id: filmToggle
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 24
                    radius: 12
                    color: root.filmValue ? root.accentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Rectangle {
                        width: 18
                        height: 18
                        radius: 9
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.filmValue ? parent.width - width - 3 : 3
                        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.changeOption("film", !root.filmValue)
                    }
                }
            }
        }
    }

    ScrollEdgeFade {
        flickable: body
        when: root.open
    }

    // ---- Pieces -------------------------------------------------------------------------------
    component IconButton: Rectangle {
        id: ib
        property string icon: ""
        signal clicked()
        width: 32
        height: 32
        radius: 8
        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, ibMouse.containsMouse ? 0.22 : 0.12)
        border.width: 1
        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, ibMouse.containsMouse ? 0.45 : 0.25)
        Behavior on color { ColorAnimation { duration: 150 } }
        AppIcon {
            anchors.centerIn: parent
            source: ib.icon
            iconSize: 14
            color: "#ffffff"
        }
        MouseArea {
            id: ibMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ib.clicked()
        }
    }

    component SectionHead: Column {
        property string title: ""
        property string note: ""
        spacing: 3
        Text {
            width: parent.width
            text: parent.title
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.bold: true
            color: "#ffffff"
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: parent.note
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.textSecondary
            wrapMode: Text.WordWrap
        }
    }

    component Chip: Rectangle {
        id: chip
        property string label: ""
        property string hint: ""
        property bool selected: false
        readonly property bool hovered: chipMouse.containsMouse
        signal clicked()
        width: chipRow.implicitWidth + 22
        height: 30
        radius: 8
        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b,
                       chip.selected ? 0.26 : (chip.hovered ? 0.14 : 0.06))
        border.width: 1
        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b,
                              chip.selected ? 0.6 : (chip.hovered ? 0.35 : 0.18))
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: chip.selected ? Font.DemiBold : Font.Normal
                color: "#ffffff"
                opacity: chip.selected ? 1.0 : 0.8
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: chip.hint !== ""
                text: chip.hint
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: root.accentColor
            }
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    // Title and note on the left, a three-way segmented picker on the right (below when narrow)
    component OptionRow: Item {
        id: row
        property string title: ""
        property string note: ""
        property var choices: []
        property string value: ""
        signal chosen(string key)
        readonly property bool stacked: width < 440
        width: parent ? parent.width : 0
        height: stacked ? head.implicitHeight + 10 + seg.height : Math.max(head.implicitHeight, seg.height)

        SectionHead {
            id: head
            anchors.left: parent.left
            anchors.right: row.stacked ? parent.right : seg.left
            anchors.rightMargin: row.stacked ? 0 : 16
            y: row.stacked ? 0 : Math.round((row.height - implicitHeight) / 2)
            title: row.title
            note: row.note
        }

        Rectangle {
            id: seg
            readonly property real segW: 76
            readonly property int selIndex: {
                for (var i = 0; i < row.choices.length; i++) if (row.choices[i].key === row.value) return i;
                return 0;
            }
            anchors.right: parent.right
            y: row.stacked ? head.implicitHeight + 10 : Math.round((row.height - height) / 2)
            width: segW * row.choices.length + 6
            height: 32
            radius: 8
            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
            border.width: 1
            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25)

            Rectangle {
                x: 3 + seg.selIndex * seg.segW
                y: 3
                width: seg.segW
                height: parent.height - 6
                radius: 5
                color: root.accentColor
                Behavior on x { NumberAnimation { duration: root.lite ? 0 : 340; easing.type: Easing.OutCubic } }
            }

            Row {
                x: 3
                y: 3
                Repeater {
                    model: row.choices
                    delegate: Item {
                        required property var modelData
                        required property int index
                        readonly property bool selected: index === seg.selIndex
                        width: seg.segW
                        height: seg.height - 6

                        Rectangle {
                            anchors.fill: parent
                            radius: 5
                            color: root.accentColor
                            opacity: !parent.selected && segMouse.containsMouse ? 0.16 : 0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: parent.selected ? Font.DemiBold : Font.Normal
                            color: parent.selected ? "#000000" : "#ffffff"
                            opacity: parent.selected ? 1.0 : 0.75
                        }
                        MouseArea {
                            id: segMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (!parent.selected) row.chosen(parent.modelData.key)
                        }
                    }
                }
            }
        }
    }
}
