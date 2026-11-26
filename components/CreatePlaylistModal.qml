import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtCore
import "."
import "cover_art.js" as CoverArt

// Create / edit a playlist. The cover is the main control: click it to pick an image,
// or generate one. Pasting an image link is still possible but folded away.
Rectangle {
    id: root

    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.45)
    visible: false
    z: 10010

    property color accentColor: Theme.accent
    property string appDir: ""
    property string songCover: ""
    property bool editMode: false
    property string targetPlaylistId: ""
    property var attachedTracks: []
    property bool linkOpen: false
    // Glass: what the card bends (masterAppSurface from shell.qml); Lite mode draws a plain tint instead
    property Item backgroundSourceItem: null
    property bool liteMode: false

    signal closeRequested()
    signal playlistCreated(string title, string description, string cover, var tracks)
    signal playlistUpdated(string plId, string title, string description, string cover)

    // Same tinted-ground recipe as the cover panel, keyed to the app accent
    readonly property real accentHue: CoverArt.hexToOklch(accentColor.toString()).h
    readonly property color ground: CoverArt.oklchToHex(0.18, 0.025, accentHue)
    readonly property color field: CoverArt.oklchToHex(0.22, 0.03, accentHue)
    readonly property color mutedText: CoverArt.oklchToHex(0.80, 0.03, accentHue)
    readonly property color faintText: CoverArt.oklchToHex(0.62, 0.03, accentHue)
    readonly property color hairline: Qt.rgba(1, 1, 1, 0.10)
    readonly property bool hasCover: coverInput.text.trim() !== ""
    readonly property bool canSubmit: titleInput.text.trim().length > 0

    function isLink(s) { return /^https?:\/\//i.test(s || ""); }

    function openCreate(tracks) {
        root.editMode = false;
        root.targetPlaylistId = "";
        root.attachedTracks = (tracks && Array.isArray(tracks)) ? tracks : [];
        titleInput.text = "";
        descInput.text = "";
        coverInput.text = "";
        root.linkOpen = false;
        root.visible = true;
        titleInput.forceActiveFocus();
    }

    function openEdit(pl) {
        if (!pl) return;
        root.editMode = true;
        root.targetPlaylistId = pl.id || pl.playlistId || "";
        root.attachedTracks = pl.tracks || [];
        titleInput.text = pl.title || pl.name || "";
        descInput.text = pl.description || "";
        coverInput.text = pl.customCover || pl.cover || "";
        root.linkOpen = root.isLink(coverInput.text);
        root.visible = true;
        titleInput.forceActiveFocus();
    }

    function closeModal() {
        coverGenerator.close();
        titleInput.focus = false;
        descInput.focus = false;
        coverInput.focus = false;
        root.visible = false;
        root.closeRequested();
    }

    function submitForm() {
        var cleanTitle = titleInput.text.trim();
        if (!cleanTitle) return;
        var cleanDesc = descInput.text.trim();
        var cleanCover = coverInput.text.trim();

        if (root.editMode) {
            root.playlistUpdated(root.targetPlaylistId, cleanTitle, cleanDesc, cleanCover);
        } else {
            root.playlistCreated(cleanTitle, cleanDesc, cleanCover, root.attachedTracks);
        }
        root.closeModal();
    }

    Keys.onEscapePressed: root.closeModal()

    // ---------- small building blocks ----------
    component PillButton: Rectangle {
        id: btn
        property string label: ""
        property string icon: ""
        property bool primary: false
        property bool enabledState: true
        property string hint: ""
        signal clicked()
        implicitHeight: 38
        implicitWidth: btnRow.implicitWidth + (label !== "" ? (primary ? 36 : 28) : 18)
        radius: height / 2
        color: primary
               ? (btnArea.containsMouse ? Qt.lighter(root.accentColor, 1.10) : root.accentColor)
               : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, btnArea.containsMouse ? 0.24 : 0.14)
        opacity: enabledState ? 1.0 : 0.4
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
                iconSize: 15
                color: btn.primary ? CoverArt.contrast(root.accentColor.toString()) : Qt.lighter(root.accentColor, 1.35)
            }
            Text {
                visible: btn.label !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: btn.label
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: btn.primary ? Font.Bold : Font.Medium
                color: btn.primary ? CoverArt.contrast(root.accentColor.toString()) : "#ffffff"
            }
        }
        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: btn.enabledState
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    component FieldLabel: Text {
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: root.mutedText
    }

    component FieldBox: Rectangle {
        property bool focused: false
        radius: 12
        color: root.field
        border.width: 1
        border.color: focused ? root.accentColor : root.hairline
        Behavior on border.color { ColorAnimation { duration: 120 } }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.closeModal()
    }

    FileDialog {
        id: coverFileDialog
        title: I18n.tr("Chọn ảnh bìa", "Choose a cover image")
        fileMode: FileDialog.OpenFile
        nameFilters: [I18n.tr("Ảnh (*.png *.jpg *.jpeg *.webp *.gif *.bmp)", "Images (*.png *.jpg *.jpeg *.webp *.gif *.bmp)")]
        currentFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        // file:// URL works as an Image source on both Linux and Windows
        onAccepted: coverInput.text = String(selectedFile)
    }

    LiquidGlass {
        id: card
        readonly property bool wide: width >= 540
        width: Math.min(600, root.width - 32)
        height: formCol.implicitHeight
        anchors.centerIn: parent
        radius: 24
        displacement: 30.0
        aberration: 0.06
        bevelWidth: 30.0
        blurRadius: 1.1
        frost: 24
        opaque: true
        isFlowActive: false
        backgroundSourceItem: root.liteMode ? null : root.backgroundSourceItem
        tintColor: Qt.rgba(root.ground.r, root.ground.g, root.ground.b, root.liteMode || !root.backgroundSourceItem ? 0.96 : 0.5)

        MouseArea { anchors.fill: parent }

        // Readability wash over the frosted glass, and the hairline (brighter along the top edge)
        Rectangle {
            anchors.fill: parent
            radius: card.radius
            visible: !root.liteMode && !!root.backgroundSourceItem
            color: Qt.rgba(0.02, 0.02, 0.04, 0.30)
            z: -1
        }
        Rectangle {
            anchors.fill: parent
            radius: card.radius
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.16)
            z: 20
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 2 * card.radius
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
            id: formCol
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 0

            // ---------- header ----------
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 28
                Layout.rightMargin: 20
                Layout.topMargin: 22
                Layout.bottomMargin: 20
                spacing: 12

                Text {
                    Layout.fillWidth: true
                    text: root.editMode ? I18n.tr("Chỉnh sửa danh sách phát", "Edit playlist")
                                        : I18n.tr("Danh sách phát mới", "New playlist")
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                    font.weight: Font.Bold
                    color: "#ffffff"
                    elide: Text.ElideRight
                }

                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    radius: 17
                    color: closeArea.containsMouse
                           ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18) : "transparent"
                    Accessible.role: Accessible.Button
                    Accessible.name: I18n.tr("Đóng", "Close")
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
                        onClicked: root.closeModal()
                    }
                }
            }

            // ---------- body: cover | fields ----------
            GridLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 28
                Layout.rightMargin: 28
                columns: card.wide ? 2 : 1
                columnSpacing: 24
                rowSpacing: 20

                // Cover column
                ColumnLayout {
                    Layout.alignment: card.wide ? Qt.AlignTop : Qt.AlignHCenter
                    Layout.fillWidth: false
                    Layout.preferredWidth: 184
                    Layout.maximumWidth: 184
                    spacing: 12

                    Item {
                        id: coverBox
                        Layout.preferredWidth: 184
                        Layout.preferredHeight: 184
                        Accessible.role: Accessible.Button
                        Accessible.name: I18n.tr("Chọn ảnh bìa", "Choose a cover image")

                        PlaylistCollageThumbnail {
                            anchors.fill: parent
                            radius: 16
                            customCover: coverInput.text.trim()
                            tracks: root.attachedTracks
                            playlistTitle: titleInput.text.trim()
                            accentColor: root.accentColor
                        }

                        // Hover: "change image" over a scrim, same radius as the cover
                        Rectangle {
                            anchors.fill: parent
                            radius: 16
                            color: Qt.rgba(0, 0, 0, 0.55)
                            opacity: coverArea.containsMouse ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 140 } }
                            Column {
                                anchors.centerIn: parent
                                spacing: 8
                                AppIcon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    source: "../assets/icons/image-cover-symbolic.svg"
                                    iconSize: 26
                                    color: "#ffffff"
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.hasCover ? I18n.tr("Đổi ảnh", "Change image") : I18n.tr("Chọn ảnh", "Choose image")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    color: "#ffffff"
                                }
                            }
                        }

                        MouseArea {
                            id: coverArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: coverFileDialog.open()
                        }

                        // Remove the custom cover, back to the automatic one
                        Rectangle {
                            visible: root.hasCover
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 8
                            width: 30
                            height: 30
                            radius: 15
                            color: removeArea.containsMouse ? Qt.rgba(244 / 255, 63 / 255, 94 / 255, 0.85) : Qt.rgba(0, 0, 0, 0.55)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Accessible.role: Accessible.Button
                            Accessible.name: I18n.tr("Bỏ ảnh bìa", "Remove cover")
                            ToolTip.visible: removeArea.containsMouse
                            ToolTip.text: I18n.tr("Bỏ ảnh bìa", "Remove cover")
                            ToolTip.delay: 400
                            AppIcon {
                                anchors.centerIn: parent
                                source: "../assets/icons/material/ms-remove.svg"
                                iconSize: 15
                                color: "#ffffff"
                            }
                            MouseArea {
                                id: removeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { coverInput.text = ""; root.linkOpen = false; }
                            }
                        }
                    }

                    PillButton {
                        Layout.fillWidth: true
                        label: I18n.tr("Tạo ảnh bìa", "Generate cover")
                        icon: "../assets/icons/material/ms-palette.svg"
                        onClicked: coverGenerator.open(titleInput.text.trim())
                    }
                }

                // Fields column
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 8

                    FieldLabel { text: I18n.tr("Tên", "Name") }
                    FieldBox {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 46
                        focused: titleInput.activeFocus
                        TextField {
                            id: titleInput
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            verticalAlignment: TextInput.AlignVCenter
                            leftPadding: 0
                            rightPadding: 0
                            color: "#ffffff"
                            font.family: Theme.fontFamily
                            font.pixelSize: 15
                            font.weight: Font.Medium
                            placeholderText: I18n.tr("Đặt tên cho danh sách", "Give it a name")
                            placeholderTextColor: root.faintText
                            background: null
                            selectByMouse: true
                            Keys.onReturnPressed: root.submitForm()
                            Keys.onEnterPressed: root.submitForm()
                        }
                    }

                    FieldLabel {
                        Layout.topMargin: 10
                        text: I18n.tr("Mô tả", "Description")
                    }
                    FieldBox {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 96
                        focused: descInput.activeFocus
                        ScrollView {
                            anchors.fill: parent
                            anchors.margins: 2
                            TextArea {
                                id: descInput
                                leftPadding: 12
                                rightPadding: 12
                                topPadding: 10
                                bottomPadding: 10
                                wrapMode: TextEdit.Wrap
                                color: "#ffffff"
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                placeholderText: I18n.tr("Không bắt buộc", "Optional")
                                placeholderTextColor: root.faintText
                                background: null
                                selectByMouse: true
                                // Enter saves; Shift+Enter starts a new line
                                Keys.onReturnPressed: event => {
                                    if (event.modifiers & Qt.ShiftModifier) event.accepted = false;
                                    else root.submitForm();
                                }
                            }
                        }
                    }

                    // Image link: folded away, most people pick or generate instead
                    Text {
                        Layout.topMargin: 6
                        visible: !root.linkOpen
                        text: I18n.tr("Dùng liên kết ảnh", "Use an image link")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        font.underline: linkArea.containsMouse
                        color: Qt.lighter(root.accentColor, 1.3)
                        MouseArea {
                            id: linkArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.linkOpen = true; coverInput.forceActiveFocus(); }
                        }
                    }

                    FieldLabel {
                        Layout.topMargin: 10
                        visible: root.linkOpen
                        text: I18n.tr("Liên kết ảnh bìa", "Cover image link")
                    }
                    FieldBox {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        visible: root.linkOpen
                        focused: coverInput.activeFocus
                        TextField {
                            id: coverInput
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            verticalAlignment: TextInput.AlignVCenter
                            leftPadding: 0
                            rightPadding: 0
                            color: "#ffffff"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            placeholderText: I18n.tr("https://… hoặc đường dẫn tệp", "https://… or a file path")
                            placeholderTextColor: root.faintText
                            background: null
                            selectByMouse: true
                            Keys.onReturnPressed: root.submitForm()
                            Keys.onEnterPressed: root.submitForm()
                        }
                    }
                }
            }

            // ---------- footer ----------
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 24
                Layout.preferredHeight: 1
                color: root.hairline
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 28
                Layout.rightMargin: 20
                Layout.topMargin: 14
                Layout.bottomMargin: 16
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: root.attachedTracks.length > 0
                          ? I18n.tr(root.attachedTracks.length + " bài hát", root.attachedTracks.length + (root.attachedTracks.length === 1 ? " song" : " songs"))
                          : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: root.faintText
                    elide: Text.ElideRight
                }

                Text {
                    text: I18n.tr("Hủy", "Cancel")
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    color: cancelArea.containsMouse ? "#ffffff" : root.mutedText
                    Layout.rightMargin: 10
                    Accessible.role: Accessible.Button
                    Accessible.name: text
                    MouseArea {
                        id: cancelArea
                        anchors.fill: parent
                        anchors.margins: -10
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeModal()
                    }
                }

                PillButton {
                    primary: true
                    enabledState: root.canSubmit
                    label: root.editMode ? I18n.tr("Lưu", "Save") : I18n.tr("Tạo", "Create")
                    icon: root.editMode ? "../assets/icons/emblem-ok-symbolic.svg" : "../assets/icons/list-add-symbolic.svg"
                    onClicked: root.submitForm()
                }
            }
        }
    }

    CoverGeneratorPanel {
        id: coverGenerator
        z: 10
        accentColor: root.accentColor
        appDir: root.appDir
        songCover: root.songCover
        backgroundSourceItem: root.backgroundSourceItem
        liteMode: root.liteMode
        onCoverGenerated: url => coverInput.text = url
    }
}
