import QtQuick
import "."

// A scaled-down render of one desktop lyrics preset over a still of the wallpaper, as it will
// sit on the desktop. While `live` is false the render holds one frame: its clock stops, so a
// grid of previews costs a single card's worth of work. `loaded` false drops the render entirely.
Rectangle {
    id: root

    property var meta: LyricsPresets.get(LyricsPresets.fallbackId)
    property bool loaded: true
    property bool live: true
    property bool selected: false
    property bool isDemo: false
    property bool showSet: false          // preset 8: name the effect set on the frame
    property color accentColor: Theme.accent
    property string wallpaperSource: ""
    property string magicFontFamily: "Instrument Serif"
    property real restTime: 9.3           // the demo frame shown while held

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

    // The set preset 8 is drawing with, and the one the song would pick by itself
    readonly property string activeSet: (view.item && view.item.activeSet !== undefined) ? view.item.activeSet : ""
    readonly property string autoSet: (view.item && view.item.autoSet !== undefined) ? view.item.autoSet : ""

    property real heldTime: 0.0
    function hold() { root.heldTime = root.isDemo ? root.restTime : root.currentTime; }
    onLiveChanged: if (!live) hold()
    onIsDemoChanged: hold()
    onActiveLyricsChanged: if (!live) hold()
    Component.onCompleted: hold()

    clip: true
    color: Qt.rgba(0.04, 0.05, 0.08, 1.0)

    // Behind the wallpaper until it loads: the accent sinking into ink
    gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.darker(root.accentColor, 3.2) }
        GradientStop { position: 1.0; color: Qt.rgba(0.04, 0.05, 0.08, 1.0) }
    }

    Image {
        id: wall
        anchors.fill: parent
        source: root.wallpaperSource
        visible: status === Image.Ready
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: root.wallpaperSource.indexOf("itemgrabber:") === 0 ? 0 : 960
        asynchronous: true
        cache: true
    }

    // Dims a bright wallpaper just enough for the words to read, as a desktop shadow would
    Rectangle {
        anchors.fill: parent
        visible: wall.visible
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.30) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.50) }
        }
    }

    // The preset at its desktop size, scaled to fit, left-aligned like on the desktop
    Item {
        id: stage
        readonly property real nativeW: root.meta.width
        readonly property real nativeH: Math.max(1, view.implicitHeight)
        readonly property real fit: Math.min((root.width - 28) / nativeW, (root.height - 16) / nativeH)
        x: 14
        y: Math.round((root.height - nativeH * fit) / 2)
        width: nativeW
        height: nativeH
        scale: fit
        transformOrigin: Item.TopLeft

        LyricsPresetView {
            id: view
            anchors.fill: parent
            preset: root.meta.id
            compact: true
            active: root.loaded
            activeLyrics: root.activeLyrics
            currentTime: root.live ? root.currentTime : root.heldTime
            isPlaying: root.live && root.isPlaying
            currentTrack: root.currentTrack
            lyricsRomanizationEnabled: root.lyricsRomanizationEnabled
            kineticOptions: root.kineticOptions
            magicFontFamily: root.magicFontFamily
            colHighlight: root.colHighlight
            colActiveText: root.colActiveText
            colDeadText: root.colDeadText
            colShadowDir: root.colShadowDir
            colShadowAmb: root.colShadowAmb
            isLightArea: root.isLightArea
        }
    }

    // Which effect set preset 8 uses for this song
    Rectangle {
        visible: root.showSet && root.activeSet !== ""
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 8
        width: setLabel.implicitWidth + 16
        height: 20
        radius: 6
        color: Qt.rgba(0, 0, 0, 0.5)
        border.width: 1
        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)

        Text {
            id: setLabel
            anchors.centerIn: parent
            readonly property var s: LyricsPresets.kineticSet(root.activeSet)
            text: I18n.tr("Bộ " + s.vi, s.en + " set")
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.bold: true
            color: "#ffffff"
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
        radius: 6
        color: Qt.rgba(0, 0, 0, 0.5)

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
