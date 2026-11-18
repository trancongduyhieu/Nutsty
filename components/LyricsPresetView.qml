import QtQuick
import "."

// One desktop lyrics preset, picked by id from LyricsPresets. The desktop widget and the
// live previews in the settings picker both render through this, so a preset looks the
// same in both places. A new preset needs an entry in LyricsPresets.qml and a Component
// in viewFor() below.
Item {
    id: root

    property int preset: LyricsPresets.fallbackId
    property bool active: true
    // Previews pass true: fewer lines, so the view still reads when scaled down
    property bool compact: false

    property var activeLyrics: []
    property real currentTime: 0.0
    property bool isPlaying: false
    property var currentTrack: null
    property bool lyricsRomanizationEnabled: true
    property string magicFontFamily: "Instrument Serif"

    property color colHighlight: "#deb06c"
    property color colActiveText: "#f8fafc"
    property color colDeadText: "#f1f5f9"
    property color colShadowDir: "#a6020305"
    property color colShadowAmb: "#66000000"
    property bool isLightArea: false

    readonly property var meta: LyricsPresets.get(root.preset)
    readonly property Item item: viewLoader.item

    implicitWidth: meta.width
    implicitHeight: (viewLoader.item && viewLoader.item.implicitHeight > 0) ? viewLoader.item.implicitHeight : meta.height

    function viewFor(id) {
        switch (id) {
        case 1: return cinematicSerif;
        case 2: return appleMusic;
        case 3: return minimalGlide;
        case 4: return motionTypography;
        }
        return appleMusic;
    }

    Loader {
        id: viewLoader
        anchors.fill: parent
        active: root.active
        sourceComponent: root.viewFor(root.meta.id)
    }

    Component {
        id: cinematicSerif
        GachaAnimeLyricsView {
            activeLyrics: root.activeLyrics
            currentTime: root.currentTime
            isPlaying: root.isPlaying
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

    Component {
        id: appleMusic
        AppleMusicDesktopLyrics {
            activeLyrics: root.activeLyrics
            currentTime: root.currentTime
            isPlaying: root.isPlaying
            currentTrack: root.currentTrack
            lyricsRomanizationEnabled: root.lyricsRomanizationEnabled
            colHighlight: root.colHighlight
            colActiveText: root.colActiveText
            colShadowDir: root.colShadowDir
            colShadowAmb: root.colShadowAmb
            isLightArea: root.isLightArea
            visibleLinesCount: root.compact ? 3 : 5
        }
    }

    Component {
        id: minimalGlide
        MinimalistLyricsView {
            activeLyrics: root.activeLyrics
            currentTime: root.currentTime
            isPlaying: root.isPlaying
            magicFontFamily: root.magicFontFamily
            colHighlight: root.colHighlight
            colActiveText: root.colActiveText
            colDeadText: root.colDeadText
            colShadowDir: root.colShadowDir
            colShadowAmb: root.colShadowAmb
            isLightArea: root.isLightArea
        }
    }

    Component {
        id: motionTypography
        AnimeMVKineticLyrics {
            activeLyrics: root.activeLyrics
            currentTime: root.currentTime
            isPlaying: root.isPlaying
            magicFontFamily: root.magicFontFamily
            colHighlight: root.colHighlight
            colActiveText: root.colActiveText
            colDeadText: root.colDeadText
            colShadowDir: root.colShadowDir
            colShadowAmb: root.colShadowAmb
            isLightArea: root.isLightArea
        }
    }
}
