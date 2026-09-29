import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    // =========================================================================
    // Core Lyrics Data & State
    // =========================================================================
    property var activeLyrics: []
    property real currentTime: 0.0
    property bool isPlaying: false
    property var currentTrack: null
    property bool enabled: true
    property int lyricsPreset: 2 // 1: Cinematic Serif, 2: Apple Music 5-Line Fluid Sync, 3: Minimalist Slide-Up Motion Blur, 4: Motion Typography
    property int customX: -1
    property int customY: -1

    signal positionChanged(int newX, int newY)
    signal playPauseRequested()
    signal volumeChangeRequested(real delta)

    screen: Quickshell.screens[0]
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "frostify:desktop_lyrics"
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Dynamic input mask: Passes through desktop clicks when idle; full grab when dragging
    mask: (universalDragArea.pressed || universalDragArea.drag.active) ? null : lyricsRegion

    Region {
        id: lyricsRegion
        item: containerBox
    }

    // =========================================================================
    // Cinematic Typefaces (Instrument Serif)
    // =========================================================================
    FontLoader {
        id: instrumentSerifFont
        source: "../assets/fonts/InstrumentSerif-Regular.ttf"
    }

    FontLoader {
        id: instrumentSerifItalicFont
        source: "../assets/fonts/InstrumentSerif-Italic.ttf"
    }

    readonly property string magicFontFamily: (instrumentSerifFont.status === FontLoader.Ready && instrumentSerifFont.name !== "") ? instrumentSerifFont.name : "Instrument Serif"

    FontLoader {
        id: montserratBlackFont
        source: "../assets/fonts/Montserrat-Black.ttf"
    }

    readonly property string heavyFontFamily: (montserratBlackFont.status === FontLoader.Ready && montserratBlackFont.name !== "") ? montserratBlackFont.name : "Montserrat"

    // =========================================================================
    // Dynamic Adaptive Palette Engine (Auto-syncs with active wallpaper)
    // =========================================================================
    property var frostifyPalette: ({
        "isLightArea": false,
        "baseTextColor": "#f8fafc",
        "highlightColor": "#deb06c",
        "deadTextColor": "#f1f5f9",
        "shadowDirectional": "#a6020305",
        "shadowAmbient": "#66000000"
    })

    Timer {
        id: delayedPaletteRead
        interval: 80
        repeat: false
        running: false
        onTriggered: {
            if (frostifyPaletteFile.loaded) {
                parseFrostifyPalette(frostifyPaletteFile.text());
            }
        }
    }

    FileView {
        id: frostifyPaletteFile
        path: Quickshell.env("HOME") + "/.config/noctalia/nutsty_palette.json"
        watchChanges: true
        onFileChanged: {
            this.reload();
            delayedPaletteRead.start();
        }
        onLoadedChanged: {
            if (this.loaded) {
                parseFrostifyPalette(this.text());
            }
        }
        Component.onCompleted: {
            if (this.loaded) {
                parseFrostifyPalette(this.text());
            }
        }
    }

    function parseFrostifyPalette(raw) {
        if (!raw || raw.trim() === "") return;
        try {
            var obj = JSON.parse(raw);
            var updated = Object.assign({}, root.frostifyPalette);
            for (var k in obj) {
                updated[k] = obj[k];
            }
            root.frostifyPalette = updated;
        } catch(e) {}
    }

    readonly property color colHighlight: root.frostifyPalette.highlightColor || "#deb06c"
    readonly property color colActiveText: root.frostifyPalette.baseTextColor || "#f8fafc"
    readonly property color colDeadText: root.frostifyPalette.deadTextColor || "#f1f5f9"
    readonly property color colShadowDir: root.frostifyPalette.shadowDirectional || "#a6020305"
    readonly property color colShadowAmb: root.frostifyPalette.shadowAmbient || "#66000000"
    readonly property bool isLightArea: !!root.frostifyPalette.isLightArea

    // =========================================================================
    // Universal Positioning & Dynamic Sizing Engine
    // =========================================================================
    readonly property int defaultX: Math.round(root.width * 0.14)
    readonly property int defaultY: (root.lyricsPreset === 1)
        ? Math.round(root.height * 0.725)
        : ((root.lyricsPreset === 3)
            ? Math.round(root.height * 0.70)
            : ((root.lyricsPreset === 4)
                ? Math.round(root.height * 0.68)
                : Math.round(root.height * 0.62)))

    readonly property int currentPresetMaxWidth: (root.lyricsPreset === 1)
        ? Math.min(740, Math.round(root.width * 0.45))
        : ((root.lyricsPreset === 3)
            ? Math.min(760, Math.round(root.width * 0.50))
            : ((root.lyricsPreset === 4)
                ? Math.min(960, Math.round(root.width * 0.65))
                : Math.min(880, Math.round(root.width * 0.55))))

    onCustomXChanged: {
        containerBox.x = (customX >= 0) ? customX : defaultX;
    }
    onCustomYChanged: {
        containerBox.y = (customY >= 0) ? customY : defaultY;
    }
    onWidthChanged: {
        if (customX < 0) containerBox.x = defaultX;
    }
    onHeightChanged: {
        if (customY < 0) containerBox.y = defaultY;
    }
    Component.onCompleted: {
        containerBox.x = (customX >= 0) ? customX : defaultX;
        containerBox.y = (customY >= 0) ? customY : defaultY;
    }

    // =========================================================================
    // Universal Draggable Container Box (Zero-clutter, full-screen freedom)
    // =========================================================================
    Item {
        id: containerBox
        x: (root.customX >= 0) ? root.customX : root.defaultX
        y: (root.customY >= 0) ? root.customY : root.defaultY
        width: Math.min(root.currentPresetMaxWidth, Math.max(120, root.width - containerBox.x))
        height: (root.lyricsPreset === 1)
            ? 120
            : ((root.lyricsPreset === 3)
                ? (minimalistView.implicitHeight > 0 ? minimalistView.implicitHeight : 140)
                : ((root.lyricsPreset === 4)
                    ? (animeMVView.implicitHeight > 0 ? animeMVView.implicitHeight : 260)
                    : (appleMusicView.implicitHeight > 0 ? appleMusicView.implicitHeight : 300)))
        visible: root.enabled && root.activeLyrics && root.activeLyrics.length > 0

        // Universal Full-Screen Drag & Gesture Area (Shared across ALL presets)
        MouseArea {
            id: universalDragArea
            anchors.fill: parent
            z: 100
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton

            property bool isSuperPressed: false
            property int startDragX: 0
            property int startDragY: 0

            cursorShape: (drag.active || isSuperPressed)
                ? Qt.ClosedHandCursor
                : (containsMouse ? Qt.OpenHandCursor : Qt.ArrowCursor)

            drag.target: containerBox
            drag.threshold: 8
            drag.axis: Drag.XAndYAxis
            drag.minimumX: 0
            drag.maximumX: Math.max(0, root.width - 120)
            drag.minimumY: 0
            drag.maximumY: Math.max(0, root.height - containerBox.height)

            onPressed: (mouse) => {
                isSuperPressed = !!(mouse.modifiers & Qt.MetaModifier);
                startDragX = containerBox.x;
                startDragY = containerBox.y;
            }

            onDoubleClicked: (mouse) => {
                root.playPauseRequested();
            }

            onWheel: (wheel) => {
                var delta = (wheel.angleDelta.y > 0) ? 3.0 : -3.0;
                root.volumeChangeRequested(delta);
            }

            onReleased: {
                isSuperPressed = false;
                if (Math.abs(containerBox.x - startDragX) > 2 || Math.abs(containerBox.y - startDragY) > 2) {
                    root.positionChanged(containerBox.x, containerBox.y);
                }
            }

            onCanceled: {
                isSuperPressed = false;
            }
        }

        // =====================================================================
        // Preset 1: Cinematic Serif View Plugin
        // =====================================================================
        GachaAnimeLyricsView {
            id: gachaView
            anchors.fill: parent
            visible: root.lyricsPreset === 1
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

        // =====================================================================
        // Preset 2: Apple Music Parametric Multi-Line Fluid Sync View Plugin
        // =====================================================================
        // Preset 2: Apple Music Parametric Multi-Line Fluid Sync View Plugin
        // =====================================================================
        AppleMusicDesktopLyrics {
            id: appleMusicView
            anchors.fill: parent
            visible: root.lyricsPreset === 2
            activeLyrics: root.activeLyrics
            currentTime: root.currentTime
            isPlaying: root.isPlaying
            currentTrack: root.currentTrack
            colHighlight: root.colHighlight
            colActiveText: root.colActiveText
            colPendingText: "#a0a5b5"
            colShadowDir: root.colShadowDir
            colShadowAmb: root.colShadowAmb
            visibleLinesCount: 5
        }

        // =====================================================================
        // Preset 3: Minimalist Slide-Up Motion Blur View Plugin
        // =====================================================================
        MinimalistLyricsView {
            id: minimalistView
            anchors.fill: parent
            visible: root.lyricsPreset === 3
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

        // =====================================================================
        // Preset 4: Motion Typography View Plugin
        // =====================================================================
        AnimeMVKineticLyrics {
            id: animeMVView
            anchors.fill: parent
            visible: root.lyricsPreset === 4
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
