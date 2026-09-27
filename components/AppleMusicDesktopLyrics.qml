import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "."

Item {
    id: root

    // =========================================================================
    // Lyrics Data and State (Passed from Universal DesktopLyricsWidget)
    // =========================================================================
    property var activeLyrics: []
    property real currentTime: 0.0
    property bool isPlaying: false
    property var currentTrack: null

    // Adaptive Palette / Styling
    property color colHighlight: "#deb06c"
    property color colActiveText: "#ffffff"
    property color colPendingText: "#a0a5b5"
    property color colShadowDir: "#a6020305"
    property color colShadowAmb: "#66000000"

    // 5 Visible Lines Layout (Slot 0: Prev, Slot 1: Active, Slots 2..4: Upcoming)
    property int visibleLinesCount: 5

    // Sizing constants
    readonly property int lineHeight: 46
    readonly property int lineGap: 14
    readonly property int slotHeight: lineHeight + lineGap // 60px

    implicitHeight: slotHeight * visibleLinesCount // 300px
    implicitWidth: 880

    visible: root.activeLyrics && root.activeLyrics.length > 0 && root.currentLyricIndex >= 0

    // =========================================================================
    // Synchronized Timing Engine
    // =========================================================================
    property int currentLyricIndex: -1
    property int prevLyricIndex: -1

    onCurrentTimeChanged: updateProgress()
    onActiveLyricsChanged: {
        currentLyricIndex = -1;
        prevLyricIndex = -1;
        updateProgress();
        if (currentLyricIndex >= 0) {
            scrollBehavior.enabled = false;
            lyricsList.contentY = (currentLyricIndex - 1) * root.slotHeight;
            scrollBehavior.enabled = true;
        }
    }

    Component.onCompleted: {
        updateProgress();
        if (currentLyricIndex >= 0) {
            scrollBehavior.enabled = false;
            lyricsList.contentY = (currentLyricIndex - 1) * root.slotHeight;
            scrollBehavior.enabled = true;
        }
    }

    function updateProgress() {
        if (!activeLyrics || activeLyrics.length === 0) {
            currentLyricIndex = -1;
            return;
        }

        var cur = root.currentTime;
        var idx = -1;
        for (var i = 0; i < activeLyrics.length; i++) {
            var t = activeLyrics[i].time;
            var nextT = (i + 1 < activeLyrics.length) ? activeLyrics[i + 1].time : 999999;
            if (cur >= t && cur < nextT) {
                idx = i;
                break;
            }
        }
        if (idx === -1 && cur < activeLyrics[0].time) {
            idx = 0;
        }

        if (idx !== currentLyricIndex) {
            var old = currentLyricIndex;
            prevLyricIndex = old;
            currentLyricIndex = idx;

            if (idx >= 0) {
                var targetY = (idx - 1) * root.slotHeight;
                if (old >= 0 && Math.abs(idx - old) === 1) {
                    // Consecutive line change -> smooth Apple Bezier glide!
                    lyricsList.contentY = targetY;
                } else {
                    // Big jump (seek or initial load) -> instant snap without animation
                    scrollBehavior.enabled = false;
                    lyricsList.contentY = targetY;
                    scrollBehavior.enabled = true;
                }
            }
        }
    }

    // =========================================================================
    // Native 5-Line Lyrics ListView Engine
    // Active line sits permanently at Slot 1 (y = root.slotHeight = 60px)
    // =========================================================================
    ListView {
        id: lyricsList
        anchors.fill: parent
        clip: true
        interactive: false
        model: root.activeLyrics
        spacing: root.lineGap
        topMargin: root.slotHeight
        bottomMargin: root.slotHeight * 6
        boundsBehavior: Flickable.StopAtBounds
        highlightRangeMode: ListView.NoHighlightRange
        currentIndex: root.currentLyricIndex

        // AMLL-accurate scroll animation: cubic-bezier(0.4, 0, 0.2, 1) (snappy 340ms)
        Behavior on contentY {
            id: scrollBehavior
            NumberAnimation {
                id: scrollAnim
                duration: 340
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.4, 0.0, 0.2, 1.0, 1.0, 1.0]
            }
        }

        delegate: Item {
            id: lyricRow
            width: lyricsList.width
            height: root.lineHeight
            transformOrigin: Item.Left

            readonly property int dist: index - root.currentLyricIndex
            readonly property bool isCurrent: dist === 0
            readonly property bool isHeldNoteActive: dist === -1 && flowLoader.item !== null && flowLoader.item.hasActiveHeldWord
            readonly property bool hasWords: !!(modelData && modelData.hasWords && !modelData.isSynthetic && modelData.words && modelData.words.length > 0)

            // ── Optical Depth-of-Field Formulas ──────────────────────────────
            readonly property real targetOpacity: {
                if (isCurrent || isHeldNoteActive) return 1.0;
                if (dist === -1 || dist === 1) return 0.50;
                if (dist === 2) return 0.24;
                if (dist === 3) return 0.10;
                return 0.0;
            }

            readonly property real targetScale: {
                if (!hasWords) return 1.0; // Plain lines stay completely still
                if (isCurrent || isHeldNoteActive) return 1.0;
                if (dist === -1 || dist === 1) return 0.92;
                if (dist === 2) return 0.84;
                if (dist === 3) return 0.76;
                return 0.68;
            }

            readonly property real targetBlur: {
                if (isCurrent || isHeldNoteActive) return 0.0;
                if (dist === -1 || dist === 1) return 0.22;
                if (dist === 2) return 0.45;
                if (dist === 3) return 0.70;
                return 0.90;
            }

            opacity: targetOpacity
            scale: targetScale
            visible: dist >= -1 && dist <= 4 && opacity > 0.01

            Behavior on opacity {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            // Depth of field blur layer (disabled on active line for zero FBO overhead)
            layer.enabled: targetBlur > 0.01 && dist >= -1 && dist <= 4
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: lyricRow.targetBlur
                blurMax: 32
            }

            // ── 1. Syllable Engine (AppleMusicWordFlow) ────────────────────────
            // Loads ONLY for genuine syllable lines (hasWords) around active line.
            // Starts with words dim (#757a88, layer 1) and lights up word-by-word into white bloom (layer 2).
            Loader {
                id: flowLoader
                anchors.fill: parent
                active: lyricRow.hasWords && (lyricRow.dist >= -1 && lyricRow.dist <= 1)
                visible: active && (lyricRow.isCurrent || lyricRow.isHeldNoteActive)

                sourceComponent: Component {
                    AppleMusicWordFlow {
                        width: lyricRow.width
                        words: (modelData && modelData.words) ? modelData.words : []
                        currentTime: root.currentTime
                        isLineActive: lyricRow.isCurrent
                        fontSize: 28
                        fontFamily: Theme.fontFamily
                        fontWeight: Font.Bold
                        accentColor: root.colHighlight
                    }
                }
            }

            // ── 2. Static Typography ─────────────────────────────────────────
            // Exclusively visible when flowLoader is NOT active (upcoming, previous, or plain LRC).
            // When isCurrent: illuminates in crisp solid white (#ffffff) with subtle ambient shadow!
            Text {
                id: staticTxt
                anchors.verticalCenter: parent.verticalCenter
                visible: !flowLoader.visible
                text: (modelData && modelData.text) ? modelData.text : ""
                font.family: Theme.fontFamily
                font.pixelSize: 28
                font.weight: Font.Bold
                color: lyricRow.isCurrent ? "#ffffff" : root.colPendingText
                elide: Text.ElideRight
                width: parent.width
                style: Text.Outline
                styleColor: root.colShadowAmb

                Behavior on color {
                    ColorAnimation { duration: 180 }
                }
            }
        }
    }
}
