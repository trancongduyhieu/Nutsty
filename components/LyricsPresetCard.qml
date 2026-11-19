import QtQuick
import "."

// One preset in the settings picker: its name, a radio badge, and a scaled-down render of the
// preset over the wallpaper. Only the picked card and the one under the pointer play; the rest
// hold a still frame. Nothing is rendered while `running` is false (scrolled away, tab closed).
Rectangle {
    id: root

    property var meta: LyricsPresets.get(LyricsPresets.fallbackId)
    property bool selected: false
    property bool running: false
    property bool isDemo: false
    property bool customizable: false       // shows the "Customize" button (preset 8)
    property color accentColor: Theme.accent
    property string wallpaperSource: ""
    property string magicFontFamily: "Instrument Serif"

    property var activeLyrics: []
    property real currentTime: 0.0
    property bool isPlaying: false
    property var currentTrack: null
    property bool lyricsRomanizationEnabled: true
    property var kineticOptions: ({})
    property color colHighlight: "#deb06c"
    property color colActiveText: "#f8fafc"
    property color colDeadText: "#f1f5f9"
    property color colShadowDir: "#a6020305"
    property color colShadowAmb: "#66000000"
    property bool isLightArea: false

    signal picked()
    signal customize()

    readonly property int padding: 8
    readonly property int previewHeight: 124
    readonly property bool live: root.running && (root.selected || hover.hovered)

    implicitHeight: header.height + preview.height + padding * 3
    radius: 16
    color: hover.hovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.07) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }

    HoverHandler { id: hover }

    MouseArea {
        anchors.fill: parent
        preventStealing: false
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked()
    }

    Item {
        id: header
        anchors.top: parent.top
        anchors.topMargin: root.padding
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding
        height: 38

        Column {
            anchors.left: parent.left
            anchors.right: customizeBtn.visible ? customizeBtn.left : radio.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: I18n.tr(root.meta.titleVi, root.meta.titleEn)
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.bold: true
                color: (root.selected || hover.hovered) ? "#ffffff" : Theme.textPrimary
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: I18n.tr(root.meta.subtitleVi, root.meta.subtitleEn)
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.textSecondary
                elide: Text.ElideRight
            }
        }

        // Opens the preset's own settings; accent-tinted like every other control
        Rectangle {
            id: customizeBtn
            visible: root.customizable
            anchors.right: radio.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: customizeRow.implicitWidth + 20
            height: 28
            radius: 8
            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, customizeMouse.containsMouse ? 0.22 : 0.12)
            border.width: 1
            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, customizeMouse.containsMouse ? 0.45 : 0.25)
            Behavior on color { ColorAnimation { duration: 150 } }

            Row {
                id: customizeRow
                anchors.centerIn: parent
                spacing: 6

                AppIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    source: "../assets/icons/preferences-system-symbolic.svg"
                    iconSize: 13
                    color: root.accentColor
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Tùy chỉnh", "Customize")
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                    color: "#ffffff"
                }
            }

            MouseArea {
                id: customizeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.customize()
            }
        }

        // Circular radio badge
        Rectangle {
            id: radio
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: 20
            radius: 10
            color: root.selected ? root.accentColor : "transparent"
            border.color: root.selected ? root.accentColor : (hover.hovered ? Qt.rgba(1, 1, 1, 0.40) : Qt.rgba(1, 1, 1, 0.20))
            border.width: root.selected ? 0 : 1.5
            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on border.color { ColorAnimation { duration: 120 } }

            AppIcon {
                anchors.centerIn: parent
                source: "../assets/icons/emblem-ok-symbolic.svg"
                iconSize: 12
                color: "#000000"
                visible: root.selected
            }
        }
    }

    // Concentric with the card: inner radius = 16 - 8
    LyricsPresetPreview {
        id: preview
        anchors.top: header.bottom
        anchors.topMargin: root.padding
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding
        height: root.previewHeight
        radius: root.radius - root.padding

        meta: root.meta
        loaded: root.running
        live: root.live
        selected: root.selected
        isDemo: root.isDemo
        showSet: root.customizable
        accentColor: root.accentColor
        wallpaperSource: root.wallpaperSource
        magicFontFamily: root.magicFontFamily
        activeLyrics: root.activeLyrics
        currentTime: root.currentTime
        isPlaying: root.isPlaying
        currentTrack: root.currentTrack
        lyricsRomanizationEnabled: root.lyricsRomanizationEnabled
        kineticOptions: root.kineticOptions
        colHighlight: root.colHighlight
        colActiveText: root.colActiveText
        colDeadText: root.colDeadText
        colShadowDir: root.colShadowDir
        colShadowAmb: root.colShadowAmb
        isLightArea: root.isLightArea
    }
}
