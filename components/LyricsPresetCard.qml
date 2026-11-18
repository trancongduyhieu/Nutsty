import QtQuick
import "."

// One preset in the settings picker: its name, a radio badge, and a live, scaled-down render
// of the preset (LyricsPresetView) over the wallpaper. The render only exists while
// `running` is true, so cards scrolled away or a closed picker cost nothing.
Rectangle {
    id: root

    property var meta: LyricsPresets.get(LyricsPresets.fallbackId)
    property bool selected: false
    property bool running: false
    property bool isDemo: false
    property color accentColor: Theme.accent
    property string wallpaperSource: ""
    property string magicFontFamily: "Instrument Serif"

    property var activeLyrics: []
    property real currentTime: 0.0
    property bool isPlaying: false
    property var currentTrack: null
    property bool lyricsRomanizationEnabled: true
    property color colHighlight: "#deb06c"
    property color colActiveText: "#f8fafc"
    property color colDeadText: "#f1f5f9"
    property color colShadowDir: "#a6020305"
    property color colShadowAmb: "#66000000"
    property bool isLightArea: false

    signal picked()

    readonly property int padding: 8
    readonly property int previewHeight: 124

    implicitHeight: header.height + previewBox.height + padding * 3
    radius: 16
    color: hover.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }

    HoverHandler { id: hover }

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
            anchors.right: radio.left
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

    // Live preview, concentric with the card: inner radius = 16 - 8
    Rectangle {
        id: previewBox
        anchors.top: header.bottom
        anchors.topMargin: root.padding
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding
        height: root.previewHeight
        radius: root.radius - root.padding
        clip: true
        color: Qt.rgba(0.04, 0.05, 0.08, 1.0)

        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.darker(root.accentColor, 3.2) }
            GradientStop { position: 1.0; color: Qt.rgba(0.04, 0.05, 0.08, 1.0) }
        }

        // The desktop the lyrics will sit on
        Image {
            anchors.fill: parent
            source: root.wallpaperSource
            visible: status === Image.Ready
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 640
            asynchronous: true
            cache: true
        }

        // The preset at its desktop size, scaled to fit, left-aligned like on the desktop
        Item {
            id: stage
            readonly property real nativeW: root.meta.width
            readonly property real nativeH: Math.max(1, view.implicitHeight)
            readonly property real fit: Math.min((previewBox.width - 28) / nativeW, (previewBox.height - 16) / nativeH)
            x: 14
            y: Math.round((previewBox.height - nativeH * fit) / 2)
            width: nativeW
            height: nativeH
            scale: fit
            transformOrigin: Item.TopLeft

            LyricsPresetView {
                id: view
                anchors.fill: parent
                preset: root.meta.id
                compact: true
                active: root.running
                activeLyrics: root.activeLyrics
                currentTime: root.currentTime
                isPlaying: root.isPlaying
                currentTrack: root.currentTrack
                lyricsRomanizationEnabled: root.lyricsRomanizationEnabled
                magicFontFamily: root.magicFontFamily
                colHighlight: root.colHighlight
                colActiveText: root.colActiveText
                colDeadText: root.colDeadText
                colShadowDir: root.colShadowDir
                colShadowAmb: root.colShadowAmb
                isLightArea: root.isLightArea
            }
        }

        // Says when the preview plays the built-in demo instead of the current song
        Rectangle {
            visible: root.isDemo
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            width: demoLabel.implicitWidth + 16
            height: 20
            radius: 10
            color: Qt.rgba(0, 0, 0, 0.42)

            Text {
                id: demoLabel
                anchors.centerIn: parent
                text: I18n.tr("Bài mẫu", "Demo song")
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.bold: true
                color: Qt.rgba(1, 1, 1, 0.85)
            }
        }

        // Selected ring, drawn over the preview
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: root.selected ? 1.5 : 1
            border.color: root.selected ? root.accentColor : Qt.rgba(1, 1, 1, 0.08)
            Behavior on border.color { ColorAnimation { duration: 120 } }
        }
    }

    MouseArea {
        anchors.fill: parent
        preventStealing: false
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked()
    }
}
