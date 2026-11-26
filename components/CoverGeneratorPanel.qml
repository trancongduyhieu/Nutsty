import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "."
import "cover_art.js" as CoverArt

// Generated playlist cover picker: layout + colour source + free OKLCH editing.
// "Use this cover" renders the preview to a PNG under <config>/nutsty_covers and
// hands back its file URL, so every existing cover view shows it unchanged.
Rectangle {
    id: root

    anchors.fill: parent
    color: "transparent"
    visible: false

    property color accentColor: Theme.accent
    property string appDir: ""
    property string songCover: ""
    property string playlistTitle: ""

    signal coverGenerated(string url)

    property string variant: "marble"
    property var swatches: CoverArt.PRESETS[0].colors.slice()
    property int count: 5
    property int selected: 0
    property string coverName: ""
    property bool showTitle: true
    property int seedKey: 0     // which reroll of the name the preview uses
    property int batch: 0       // suggestion grid shows seeds batch*2 and batch*2+1
    property string sourceId: "classic"
    property var wallColors: []
    property var songColors: []
    property string coverDir: ""
    property bool saving: false
    // Glass: what the card bends (masterAppSurface from shell.qml); Lite mode draws a plain tint instead
    property Item backgroundSourceItem: null
    property bool liteMode: false

    readonly property var activeColors: swatches.slice(0, count)
    readonly property string seedName: seedFor(seedKey)
    readonly property string titleFont: (serifFont.status === FontLoader.Ready && serifFont.name !== "") ? serifFont.name : "Playfair Display"
    readonly property var selectedLch: CoverArt.hexToOklch(swatches[selected] || "#808080")
    readonly property color tint: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 1)
    // The panel takes its ground and secondary text from the cover's own first colour
    readonly property real paletteHue: CoverArt.hexToOklch(activeColors[0] || "#808080").h
    readonly property color ground: CoverArt.oklchToHex(0.18, 0.03, paletteHue)
    readonly property color groundRaised: CoverArt.oklchToHex(0.23, 0.035, paletteHue)
    readonly property color mutedText: CoverArt.oklchToHex(0.80, 0.035, paletteHue)
    readonly property color hairline: Qt.rgba(1, 1, 1, 0.10)

    readonly property var sources: {
        var out = [];
        if (wallColors.length) out.push({ id: "wallpaper", colors: wallColors });
        if (songColors.length) out.push({ id: "song", colors: songColors });
        return out.concat(CoverArt.PRESETS);
    }

    function sourceLabel(id) {
        switch (id) {
        case "wallpaper": return I18n.tr("Hình nền", "Wallpaper");
        case "song": return I18n.tr("Đang phát", "Now playing");
        case "classic": return I18n.tr("Cổ điển", "Classic");
        case "sunset": return I18n.tr("Hoàng hôn", "Sunset");
        case "sea": return I18n.tr("Biển đêm", "Night sea");
        case "matcha": return I18n.tr("Trà xanh", "Matcha");
        case "peach": return I18n.tr("Đào", "Peach");
        case "berry": return I18n.tr("Dâu rừng", "Berry");
        case "forest": return I18n.tr("Rừng thông", "Forest");
        case "desert": return I18n.tr("Sa mạc", "Desert");
        case "retro": return I18n.tr("Hoài cổ", "Retro");
        case "lavender": return I18n.tr("Oải hương", "Lavender");
        case "citrus": return I18n.tr("Cam chanh", "Citrus");
        case "midnight": return I18n.tr("Nửa đêm", "Midnight");
        case "candy": return I18n.tr("Kẹo ngọt", "Candy");
        case "mono": return I18n.tr("Đen trắng", "Mono");
        default: return I18n.tr("Rực rỡ", "Neon");
        }
    }

    function variantLabel(v) {
        switch (v) {
        case "bauhaus": return I18n.tr("Hình khối", "Bauhaus");
        case "sunset": return I18n.tr("Chuyển sắc", "Gradient");
        case "ring": return I18n.tr("Vòng tròn", "Rings");
        case "pixel": return I18n.tr("Điểm ảnh", "Pixel");
        case "beam": return I18n.tr("Mặt cười", "Smiley");
        case "waves": return I18n.tr("Sóng", "Waves");
        case "stripes": return I18n.tr("Sọc", "Stripes");
        case "tiles": return I18n.tr("Ô gạch", "Tiles");
        case "dots": return I18n.tr("Chấm bi", "Dots");
        case "aurora": return I18n.tr("Cực quang", "Aurora");
        case "folds": return I18n.tr("Gấp giấy", "Folds");
        default: return I18n.tr("Loang màu", "Marble");
        }
    }

    function seedFor(key) { return (coverName.trim() || "Nutsty") + (key > 0 ? "#" + key : ""); }

    function open(title) {
        root.playlistTitle = title || "";
        root.coverName = root.playlistTitle;
        root.seedKey = 0;
        root.batch = 0;
        root.saving = false;
        root.visible = true;
        wallProc.command = ["python3", root.appDir + "/backend/palette_extractor.py", "cover_colors", ""];
        wallProc.running = true;
        if (root.songCover) {
            songProc.command = ["python3", root.appDir + "/backend/palette_extractor.py", "cover_colors", root.songCover];
            songProc.running = true;
        }
    }

    function close() { root.visible = false; }

    function useSource(src) {
        root.sourceId = src.id;
        root.swatches = src.colors.slice();
        root.count = Math.min(5, src.colors.length);
        root.selected = 0;
    }

    function setSwatch(i, hex) {
        var s = root.swatches.slice();
        s[i] = hex;
        root.swatches = s;
        root.sourceId = "";
    }

    function editSelected(l, c, h) { setSwatch(root.selected, CoverArt.oklchToHex(l, c, h)); }

    // Saving draws a separate 640 px cover (grabbing the 180 px preview would upscale its text and layers)
    function save() {
        if (root.saving) return;
        root.saving = true;
        exportLoader.active = true;
    }

    function finishSave(item) {
        var dir = root.coverDir || (Quickshell.env("HOME") + "/.config/noctalia");
        var path = dir + "/cover_" + Date.now() + ".png";
        var ok = item.grabToImage(function (result) {
            var saved = result.saveToFile(path);
            root.saving = false;
            exportLoader.active = false;
            if (saved) {
                root.coverGenerated(CoverArt.fileUrl(path));
                root.close();
            }
        });
        if (!ok) {
            root.saving = false;
            exportLoader.active = false;
        }
    }

    Loader {
        id: exportLoader
        active: false
        x: root.width + 64   // outside the window but still in the scene, so it can be grabbed
        sourceComponent: GeneratedCover {
            width: 640
            height: 640
            variant: root.variant
            seedName: root.seedName
            colors: root.activeColors
            title: root.coverName.trim()
            showTitle: root.showTitle
            titleFont: root.titleFont
        }
        onLoaded: exportTimer.start()
    }

    // One short wait so the effect layers and the font have drawn before the grab
    Timer {
        id: exportTimer
        interval: 60
        onTriggered: if (exportLoader.item) root.finishSave(exportLoader.item)
    }

    function applyLive(line, isWall) {
        var obj;
        try { obj = JSON.parse(line); } catch (e) { return; }
        if (obj.coverDir) root.coverDir = obj.coverDir;
        if (!obj.colors || obj.colors.length < 3) return;
        if (isWall) {
            root.wallColors = obj.colors;
            if (root.sourceId === "classic") root.useSource({ id: "wallpaper", colors: obj.colors });
        } else {
            root.songColors = obj.colors;
        }
    }

    Process {
        id: wallProc
        stdout: SplitParser { onRead: data => root.applyLive(data, true) }
    }

    Process {
        id: songProc
        stdout: SplitParser { onRead: data => root.applyLive(data, false) }
    }

    // Playfair Display (OFL): Instrument Serif has no Vietnamese glyphs, so names like "Bồ" fell back to another font
    FontLoader { id: serifFont; source: "../assets/fonts/PlayfairDisplay.ttf" }

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    // Quiet text button; "primary" fills it with the accent for the one main action
    component ActionButton: Rectangle {
        id: btn
        property string label: ""
        property string icon: ""
        property bool primary: false
        property bool busy: false
        property string hint: ""     // tooltip + accessible name for an icon-only button
        signal clicked()
        implicitHeight: 36
        implicitWidth: btnRow.implicitWidth + (primary ? 32 : 24)
        radius: height / 2
        color: primary
               ? (btnArea.containsMouse ? Qt.lighter(root.tint, 1.12) : root.tint)
               : Qt.rgba(root.tint.r, root.tint.g, root.tint.b, btnArea.containsMouse ? 0.18 : 0.0)
        opacity: busy ? 0.6 : 1.0
        Behavior on color { ColorAnimation { duration: 120 } }
        Accessible.role: Accessible.Button
        Accessible.name: label !== "" ? label : hint
        ToolTip.visible: hint !== "" && btnArea.containsMouse
        ToolTip.text: hint
        ToolTip.delay: 400
        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: 7
            AppIcon {
                visible: btn.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                source: btn.icon
                iconSize: 14
                color: btn.primary ? CoverArt.contrast(root.tint) : Qt.lighter(root.tint, 1.4)
            }
            Text {
                visible: btn.label !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: btn.label
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: btn.primary ? Font.Bold : Font.Medium
                color: btn.primary ? CoverArt.contrast(root.tint) : "#ffffff"
            }
        }
        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !btn.busy
            onClicked: btn.clicked()
        }
    }

    component SectionLabel: Text {
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: root.mutedText
    }

    component ColorSlider: Slider {
        id: cs
        property var stops: []
        Layout.fillWidth: true
        implicitHeight: 22
        background: Rectangle {
            x: cs.leftPadding
            y: cs.topPadding + cs.availableHeight / 2 - height / 2
            width: cs.availableWidth
            height: 8
            radius: 4
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: cs.stops[0] || "black" }
                GradientStop { position: 1 / 6; color: cs.stops[1] || "black" }
                GradientStop { position: 2 / 6; color: cs.stops[2] || "black" }
                GradientStop { position: 3 / 6; color: cs.stops[3] || "black" }
                GradientStop { position: 4 / 6; color: cs.stops[4] || "black" }
                GradientStop { position: 5 / 6; color: cs.stops[5] || "black" }
                GradientStop { position: 1.0; color: cs.stops[6] || "black" }
            }
        }
        handle: Rectangle {
            x: cs.leftPadding + cs.visualPosition * (cs.availableWidth - width)
            y: cs.topPadding + cs.availableHeight / 2 - height / 2
            width: 16; height: 16; radius: 8
            color: "#ffffff"
            border.color: Qt.rgba(0, 0, 0, 0.35)
            border.width: 1
            scale: cs.pressed ? 1.15 : 1.0
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
    }

    // A selectable cover thumbnail: variant + seed, with a ring outside the art when chosen
    component CoverTile: Item {
        id: tile
        property string tileVariant: "marble"
        property string tileSeed: ""
        property bool chosen: false
        property string caption: ""
        signal picked()
        implicitWidth: tileGrid.tileSize
        implicitHeight: tileGrid.tileSize + (caption !== "" ? 20 : 0)
        Accessible.role: Accessible.RadioButton
        Accessible.name: caption !== "" ? caption : tileVariant
        Accessible.checked: chosen

        Rectangle {
            x: -3; y: -3
            width: tileGrid.tileSize + 6
            height: tileGrid.tileSize + 6
            radius: 13
            color: "transparent"
            border.width: 2
            border.color: tile.chosen ? "#ffffff" : (tileArea.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : "transparent")
        }

        GeneratedCover {
            width: tileGrid.tileSize
            height: tileGrid.tileSize
            radius: 10
            variant: tile.tileVariant
            seedName: tile.tileSeed
            colors: root.activeColors
        }

        Text {
            visible: tile.caption !== ""
            y: tileGrid.tileSize + 6
            width: tileGrid.tileSize
            horizontalAlignment: Text.AlignHCenter
            text: tile.caption
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: tile.chosen ? Font.DemiBold : Font.Normal
            color: tile.chosen ? "#ffffff" : root.mutedText
        }

        MouseArea {
            id: tileArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.picked()
        }
    }

    function hueStops() {
        var l = Math.max(selectedLch.l, 0.6), c = Math.max(selectedLch.c, 0.12), out = [];
        for (var i = 0; i < 7; i++) out.push(CoverArt.oklchToHex(l, c, i * 60));
        return out;
    }
    function chromaStops() {
        var out = [];
        for (var i = 0; i < 7; i++) out.push(CoverArt.oklchToHex(selectedLch.l, 0.32 * i / 6, selectedLch.h));
        return out;
    }
    function lightStops() {
        var out = [];
        for (var i = 0; i < 7; i++) out.push(CoverArt.oklchToHex(0.12 + 0.85 * i / 6, selectedLch.c, selectedLch.h));
        return out;
    }

    GlassPanel {
        id: card
        width: Math.min(880, root.width - 32)
        height: Math.min(Math.max(stage.implicitHeight, controls.implicitHeight + 48) + 16, root.height - 32)
        anchors.centerIn: parent
        glassSource: root.backgroundSourceItem
        liteMode: root.liteMode
        ground: root.ground

        MouseArea { anchors.fill: parent }

        // ---------- stage: the cover, large, on its own blurred light ----------
        Item {
            id: stage
            x: 8; y: 8
            width: card.width >= 780 ? 320 : 248
            height: card.height - 16
            implicitHeight: stageCol.implicitHeight + 64

            Rectangle {
                id: stageMask
                anchors.fill: parent
                radius: 16           // card radius 24 - 8 inset
                visible: false
                layer.enabled: true
                antialiasing: true
            }

            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: stageMask
                    autoPaddingEnabled: false
                }

                Rectangle { anchors.fill: parent; color: root.groundRaised }

                // Square source, so it is sized past the stage's longer side to leave no hard edge
                MultiEffect {
                    width: Math.max(parent.width, parent.height) * 1.5
                    height: width
                    anchors.centerIn: parent
                    source: coverRender
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blurMax: 64
                    blur: 1.0
                    opacity: 0.55
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.10) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.45) }
                    }
                }
            }

            ColumnLayout {
                id: stageCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 32
                anchors.rightMargin: 32
                spacing: 0

                Item {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: stage.width - 64
                    Layout.preferredHeight: stage.width - 64

                    RectangularShadow {
                        anchors.fill: parent
                        offset.y: 14
                        radius: 14
                        blur: 36
                        spread: -6
                        color: Qt.rgba(0, 0, 0, 0.55)
                    }

                    GeneratedCover {
                        id: coverRender
                        anchors.fill: parent
                        radius: 14
                        variant: root.variant
                        seedName: root.seedName
                        colors: root.activeColors
                        title: root.coverName.trim()
                        showTitle: root.showTitle
                        titleFont: root.titleFont
                    }
                }

                // The name is typed in the same serif the cover prints it in
                TextField {
                    id: nameInput
                    Layout.fillWidth: true
                    Layout.topMargin: 26
                    horizontalAlignment: TextInput.AlignHCenter
                    background: Rectangle {
                        y: parent.height - 1
                        width: parent.width
                        height: 1
                        color: nameInput.activeFocus ? Qt.lighter(root.tint, 1.3) : Qt.rgba(1, 1, 1, 0.22)
                    }
                    leftPadding: 0
                    rightPadding: 0
                    bottomPadding: 8
                    color: "#ffffff"
                    selectionColor: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.55)
                    selectedTextColor: "#ffffff"
                    font.family: root.titleFont
                    font.pixelSize: 24
                    selectByMouse: true
                    maximumLength: 60
                    placeholderText: I18n.tr("Tên danh sách phát", "Playlist name")
                    placeholderTextColor: Qt.rgba(1, 1, 1, 0.45)
                    text: root.coverName
                    onTextEdited: root.coverName = text
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 14
                    spacing: 10

                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("In tên lên ảnh", "Print the name on the cover")
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: "#ffffff"
                        elide: Text.ElideRight
                    }

                    Switch {
                        id: titleSwitch
                        checked: root.showTitle
                        onToggled: root.showTitle = checked
                        Accessible.name: I18n.tr("In tên lên ảnh", "Print the name on the cover")
                        indicator: Rectangle {
                            implicitWidth: 38
                            implicitHeight: 22
                            x: titleSwitch.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: 11
                            color: titleSwitch.checked ? root.tint : Qt.rgba(1, 1, 1, 0.18)
                            Behavior on color { ColorAnimation { duration: 140 } }
                            Rectangle {
                                x: titleSwitch.checked ? parent.width - width - 3 : 3
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16; height: 16; radius: 8
                                color: titleSwitch.checked ? CoverArt.contrast(root.tint) : "#ffffff"
                                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }
            }
        }

        // ---------- controls ----------
        Flickable {
            id: scroller
            anchors.left: stage.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            // 6 px narrower than the visual column on each side: the selection ring sits 3 px outside a
            // tile, and the Flickable clips when it scrolls
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            anchors.topMargin: 24
            anchors.bottomMargin: 24
            contentWidth: width
            contentHeight: controls.implicitHeight
            clip: contentHeight > height
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: controls
                x: 6
                width: scroller.width - 12
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Tạo ảnh bìa", "Make a cover")
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }
                    Item {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        Accessible.role: Accessible.Button
                        Accessible.name: I18n.tr("Đóng", "Close")
                        Rectangle {
                            anchors.fill: parent
                            radius: 16
                            color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, closeArea.containsMouse ? 0.2 : 0.0)
                        }
                        AppIcon {
                            anchors.centerIn: parent
                            source: "../assets/icons/window-close-symbolic.svg"
                            iconSize: 14
                            color: closeArea.containsMouse ? "#ffffff" : root.mutedText
                        }
                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.close()
                        }
                    }
                }

                // Layout: the six styles, each drawn with the current seed
                SectionLabel { Layout.topMargin: 22; text: I18n.tr("Kiểu", "Style") }
                GridLayout {
                    id: tileGrid
                    Layout.fillWidth: true
                    Layout.topMargin: 12
                    columns: 6
                    columnSpacing: 12
                    rowSpacing: 12
                    readonly property real tileSize: Math.max(40, Math.floor((controls.width - 5 * columnSpacing) / 6))

                    Repeater {
                        model: CoverArt.VARIANTS
                        CoverTile {
                            required property string modelData
                            tileVariant: modelData
                            tileSeed: root.seedName
                            caption: root.variantLabel(modelData)
                            chosen: root.variant === modelData
                            onPicked: root.variant = modelData
                        }
                    }
                }

                // Versions: the chosen style drawn from six more seeds of the name
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 22
                    SectionLabel {
                        Layout.fillWidth: true
                        text: I18n.tr("Phiên bản khác", "Other versions")
                    }
                    ActionButton {
                        implicitHeight: 30
                        icon: "../assets/icons/view-refresh-symbolic.svg"
                        label: I18n.tr("Đổi bộ khác", "Show more")
                        onClicked: root.batch = root.batch + 1
                    }
                }
                GridLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    columns: 6
                    columnSpacing: 12

                    Repeater {
                        model: 6
                        CoverTile {
                            required property int index
                            readonly property int key: root.batch * 6 + index
                            tileVariant: root.variant
                            tileSeed: root.seedFor(key)
                            chosen: root.seedKey === key
                            onPicked: root.seedKey = key
                        }
                    }
                }

                // Palettes: live colours first, then the fixed presets
                SectionLabel { Layout.topMargin: 24; text: I18n.tr("Bảng màu", "Palette") }
                GridLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    columns: controls.width >= 420 ? 3 : 2
                    columnSpacing: 6
                    rowSpacing: 4

                    Repeater {
                        model: root.sources
                        Rectangle {
                            id: srcRow
                            required property var modelData
                            readonly property bool active: root.sourceId === modelData.id
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1     // equal columns regardless of label length
                            Layout.preferredHeight: 36
                            radius: 10
                            color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, active ? 0.22 : (srcArea.containsMouse ? 0.10 : 0.0))
                            border.color: active ? Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.7) : "transparent"
                            border.width: 1
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: root.sourceLabel(modelData.id)
                            Accessible.checked: active

                            Row {
                                id: strip
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                Repeater {
                                    model: srcRow.modelData.colors.slice(0, 5)
                                    Rectangle {
                                        required property string modelData
                                        required property int index
                                        width: 11; height: 20
                                        radius: (index === 0 || index === 4) ? 5 : 0
                                        color: modelData
                                        // square inner edges: round only the outer ends of the strip
                                        Rectangle {
                                            visible: parent.index === 0 || parent.index === 4
                                            x: parent.index === 0 ? parent.width / 2 : 0
                                            width: parent.width / 2
                                            height: parent.height
                                            color: parent.modelData
                                        }
                                    }
                                }
                            }

                            Text {
                                anchors.left: strip.right
                                anchors.leftMargin: 8
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.sourceLabel(srcRow.modelData.id)
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: srcRow.active ? Font.DemiBold : Font.Normal
                                color: "#ffffff"
                            }

                            MouseArea {
                                id: srcArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.useSource(srcRow.modelData)
                            }
                        }
                    }
                }

                // Fine-tune one colour of the palette
                SectionLabel { Layout.topMargin: 24; text: I18n.tr("Chỉnh từng màu", "Adjust a colour") }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    spacing: 8

                    Repeater {
                        model: 5
                        Item {
                            id: slot
                            required property int index
                            readonly property bool used: index < root.count
                            readonly property bool picked: index === root.selected
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 34
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: I18n.tr("Màu %1", "Colour %1").arg(index + 1)
                            Accessible.checked: picked

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -3
                                radius: 11
                                color: "transparent"
                                border.width: 2
                                border.color: slot.picked ? "#ffffff" : "transparent"
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: slot.used ? (root.swatches[slot.index] || "#808080") : "transparent"
                                border.width: slot.used ? 0 : 1
                                border.color: Qt.rgba(1, 1, 1, 0.3)
                                AppIcon {
                                    visible: !slot.used
                                    anchors.centerIn: parent
                                    source: "../assets/icons/list-add-symbolic.svg"
                                    iconSize: 12
                                    color: root.mutedText
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!slot.used) root.count = slot.index + 1;
                                    root.selected = slot.index;
                                }
                            }
                        }
                    }

                    // Fewer than 3 colours makes shapes vanish into the background
                    ActionButton {
                        visible: root.count > 3
                        implicitHeight: 34
                        implicitWidth: 34
                        icon: "../assets/icons/material/ms-remove.svg"
                        hint: I18n.tr("Bớt một màu", "Remove a colour")
                        onClicked: {
                            root.count = root.count - 1;
                            if (root.selected >= root.count) root.selected = root.count - 1;
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: 96
                        Layout.preferredHeight: 32
                        radius: 8
                        color: Qt.rgba(0, 0, 0, 0.22)
                        border.color: hexInput.activeFocus ? Qt.lighter(root.tint, 1.3) : root.hairline
                        border.width: 1
                        TextField {
                            id: hexInput
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            background: null
                            color: "#ffffff"
                            selectionColor: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.55)
                            font.family: "monospace"
                            font.pixelSize: 12
                            font.capitalization: Font.AllUppercase
                            selectByMouse: true
                            Accessible.name: I18n.tr("Mã màu", "Colour code")
                            text: root.swatches[root.selected] || ""
                            onEditingFinished: {
                                var v = text.trim();
                                if (/^#?[0-9a-fA-F]{6}$/.test(v)) root.setSwatch(root.selected, v[0] === "#" ? v : "#" + v);
                                else text = Qt.binding(() => root.swatches[root.selected] || "");
                            }
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 14
                    columns: 3
                    columnSpacing: 12
                    rowSpacing: 8

                    SectionLabel { text: I18n.tr("Sắc màu", "Hue"); Layout.preferredWidth: 64 }
                    ColorSlider {
                        id: hueSlider
                        from: 0; to: 360
                        value: root.selectedLch.h
                        stops: root.hueStops()
                        onMoved: root.editSelected(root.selectedLch.l, Math.max(root.selectedLch.c, 0.02), value)
                    }
                    SectionLabel {
                        text: Math.round(hueSlider.value) + "°"
                        horizontalAlignment: Text.AlignRight
                        font.features: { "tnum": 1 }
                        Layout.preferredWidth: 36
                    }

                    SectionLabel { text: I18n.tr("Độ đậm", "Saturation"); Layout.preferredWidth: 64 }
                    ColorSlider {
                        id: chromaSlider
                        from: 0; to: 0.32
                        value: root.selectedLch.c
                        stops: root.chromaStops()
                        onMoved: root.editSelected(root.selectedLch.l, value, root.selectedLch.h)
                    }
                    SectionLabel {
                        text: Math.round(chromaSlider.value / 0.32 * 100) + "%"
                        horizontalAlignment: Text.AlignRight
                        font.features: { "tnum": 1 }
                        Layout.preferredWidth: 36
                    }

                    SectionLabel { text: I18n.tr("Độ sáng", "Lightness"); Layout.preferredWidth: 64 }
                    ColorSlider {
                        id: lightSlider
                        from: 0.12; to: 0.97
                        value: root.selectedLch.l
                        stops: root.lightStops()
                        onMoved: root.editSelected(value, root.selectedLch.c, root.selectedLch.h)
                    }
                    SectionLabel {
                        text: Math.round(lightSlider.value * 100) + "%"
                        horizontalAlignment: Text.AlignRight
                        font.features: { "tnum": 1 }
                        Layout.preferredWidth: 36
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    Layout.leftMargin: -12   // ghost buttons: line their text up with the column, not their hover pill
                    spacing: 4

                    ActionButton {
                        implicitHeight: 30
                        icon: "../assets/icons/material/ms-palette.svg"
                        label: I18n.tr("Phối từ màu này", "Build from this colour")
                        onClicked: {
                            root.swatches = CoverArt.harmony(root.swatches[root.selected]);
                            root.count = 5;
                            root.sourceId = "";
                        }
                    }
                    ActionButton {
                        implicitHeight: 30
                        icon: "../assets/icons/media-playlist-shuffle-symbolic.svg"
                        label: I18n.tr("Xoay màu", "Rotate colours")
                        onClicked: {
                            var s = root.swatches.slice(0, root.count);
                            s.push(s.shift());
                            root.swatches = s.concat(root.swatches.slice(root.count));
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 22
                    Layout.preferredHeight: 1
                    color: root.hairline
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    spacing: 8

                    Item { Layout.fillWidth: true }

                    ActionButton {
                        label: I18n.tr("Hủy", "Cancel")
                        onClicked: root.close()
                    }

                    ActionButton {
                        primary: true
                        busy: root.saving
                        icon: "../assets/icons/emblem-ok-symbolic.svg"
                        label: root.saving ? I18n.tr("Đang lưu", "Saving") : I18n.tr("Dùng ảnh này", "Use this cover")
                        onClicked: root.save()
                    }
                }
            }
        }
    }
}
