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
    property bool lyricsRomanizationEnabled: true

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
            height: isInterlude ? (isCurrent ? root.lineHeight : 0) : root.lineHeight
            visible: isInterlude ? (isCurrent && height > 0.5) : (dist >= -1 && dist <= 4 && opacity > 0.01)
            clip: isInterlude && height < (root.lineHeight - 0.5)
            transformOrigin: Item.Left

            readonly property bool isInterlude: !!(modelData && modelData.isInterlude)
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

            opacity: isInterlude ? (isCurrent ? 1.0 : 0.0) : targetOpacity
            scale: isInterlude ? (isCurrent ? 1.0 : 0.0) : targetScale

            Behavior on height {
                enabled: lyricRow.isInterlude
                NumberAnimation {
                    duration: 950
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.42, 0.0, 0.16, 1.0, 1.0, 1.0]
                }
            }
            Behavior on opacity {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            // Depth of field: pure typography opacity and scale falloff (0 FBO overhead, zero thermal load)
            layer.enabled: false


            // ── 0. SimpMusic / Apple Music Interlude Countdown Beads (• • •) (1:1 Mochy-Music) ──
            Row {
                id: interludeBeadsRow
                visible: lyricRow.isInterlude && (lyricRow.height > 0.5)
                spacing: 16
                anchors.left: parent.left
                anchors.leftMargin: 0
                anchors.verticalCenter: parent.verticalCenter
                height: 28

                readonly property real gapStart: (modelData && modelData.time !== undefined) ? modelData.time : 0.0
                readonly property real gapEnd: (modelData && modelData.endTime !== undefined) ? modelData.endTime : (gapStart + 4.0)
                readonly property real gapSpan: Math.max(0.1, gapEnd - gapStart)
                readonly property real gapProgress: lyricRow.isCurrent ? Math.max(0.0, Math.min(1.0, (root.currentTime - gapStart) / gapSpan)) : 0.0

                function smoothstep(t) {
                    var x = Math.max(0.0, Math.min(1.0, t));
                    return x * x * (3.0 - 2.0 * x);
                }

                // Finale Swell (at 88% of gap): All 3 dots swell together
                readonly property real finaleNow: (gapProgress >= 0.88) ? smoothstep((gapProgress - 0.88) / 0.12) : 0.0

                Repeater {
                    model: 3

                    delegate: Item {
                        id: dotItem
                        width: 10
                        height: 10

                        readonly property real sliceStart: index / 3.0
                        readonly property real within: (interludeBeadsRow.gapProgress - sliceStart) * 3.0 / 0.55
                        readonly property real fill: interludeBeadsRow.smoothstep(within)

                        readonly property real litAt: sliceStart + 0.55 / 3.0
                        readonly property real glow: (interludeBeadsRow.gapProgress < litAt)
                            ? fill
                            : Math.exp(-((interludeBeadsRow.gapProgress - litAt) * interludeBeadsRow.gapSpan) / 0.9)
                        readonly property real effectiveGlow: Math.max(glow, Math.sin(Math.PI * interludeBeadsRow.finaleNow) * 0.7)

                        property real pop: lyricRow.isCurrent ? 1.0 : 0.0
                        Behavior on pop {
                            NumberAnimation {
                                duration: 320
                                easing.type: Easing.OutBack
                            }
                        }

                        scale: (0.8 + 0.3 * fill + 0.14 * interludeBeadsRow.finaleNow) * pop
                        opacity: (0.3 + 0.7 * Math.max(fill, interludeBeadsRow.finaleNow)) * pop

                        readonly property real bobPhase: (root.currentTime / 2.6) * 2.0 * Math.PI - index * 0.9
                        readonly property real bobY: lyricRow.isCurrent ? (Math.sin(bobPhase) * 1.8) : 0.0

                        transform: Translate {
                            y: dotItem.bobY
                        }

                        // Layer 1: Perfect 360-degree Organic Radial Halo (Zero FBO truncation, zero box artifacts)
                        Image {
                            id: auraImg
                            source: Qt.resolvedUrl("../assets/icons/dot-radial-glow.svg")
                            anchors.centerIn: parent
                            width: 64
                            height: 64
                            sourceSize.width: 64
                            sourceSize.height: 64
                            smooth: true
                            visible: false
                        }

                        MultiEffect {
                            source: auraImg
                            anchors.fill: auraImg
                            colorization: 1.0
                            colorizationColor: root.colHighlight || "#deb06c"
                            autoPaddingEnabled: false
                            opacity: 0.85 * dotItem.effectiveGlow
                            visible: dotItem.effectiveGlow > 0.01 && lyricRow.isCurrent
                        }

                        // Layer 2: Sharp Solid White Core Bead
                        Rectangle {
                            id: dotCore
                            anchors.centerIn: parent
                            width: 10
                            height: 10
                            radius: 5
                            color: "#ffffff"
                            opacity: 0.75 + 0.25 * dotItem.fill
                        }
                    }
                }
            }

            readonly property bool isBackgroundVocal: !!(modelData && modelData.isBackground)
            readonly property bool isEnsembleVoice: !!(modelData && (modelData.agent === "v1000" || modelData.isBackground))
            readonly property bool isAnsweringVoice: !!(modelData && !isEnsembleVoice && modelData.agent && modelData.agent !== "v1")

            // ── 1. Syllable Engine (AppleMusicWordFlow) ────────────────────────
            // Loads ONLY for genuine syllable lines (hasWords) around active line.
            Loader {
                id: flowLoader
                anchors.fill: parent
                active: !interludeBeadsRow.visible && lyricRow.hasWords && (lyricRow.dist >= -1 && lyricRow.dist <= 1)
                visible: active && (lyricRow.isCurrent || lyricRow.isHeldNoteActive)

                sourceComponent: Component {
                    AppleMusicWordFlow {
                        width: lyricRow.width
                        words: (modelData && modelData.words) ? modelData.words : []
                        currentTime: root.currentTime
                        isLineActive: lyricRow.isCurrent
                        isAnsweringVoice: lyricRow.isAnsweringVoice
                        isEnsembleVoice: lyricRow.isEnsembleVoice
                        fontSize: 28
                        fontFamily: Theme.fontFamily
                        fontWeight: Font.Bold
                        accentColor: "#ffffff"
                    }
                }
            }

            // ── 2. Static Typography ─────────────────────────────────────────
            // Exclusively visible when flowLoader is NOT active (upcoming, previous, or plain LRC).
            // When isCurrent: illuminates in crisp solid white (#ffffff) with subtle ambient shadow!
            readonly property bool hasRomanized: !modelData.isInterlude && root.lyricsRomanizationEnabled && !!(modelData && modelData.romanized && modelData.romanized.trim() !== "")

            Text {
                id: staticTxt
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: lyricRow.hasRomanized ? -9 : 0
                visible: !interludeBeadsRow.visible && !flowLoader.visible
                text: (modelData && modelData.text) ? modelData.text : ""
                font.family: Theme.fontFamily
                font.pixelSize: 28
                font.weight: Font.Bold
                font.italic: lyricRow.isBackgroundVocal
                color: lyricRow.isCurrent ? "#ffffff" : root.colPendingText
                elide: Text.ElideRight
                width: parent.width
                horizontalAlignment: lyricRow.isAnsweringVoice ? Text.AlignRight : (lyricRow.isEnsembleVoice ? Text.AlignHCenter : Text.AlignLeft)
                style: Text.Outline
                styleColor: root.colShadowAmb

                Behavior on color {
                    ColorAnimation { duration: 180 }
                }
            }

            // Secondary Romanization Row
            Text {
                id: romanizedDesktopTxt
                anchors.top: staticTxt.bottom
                anchors.topMargin: 0
                anchors.left: parent.left
                anchors.right: parent.right
                visible: lyricRow.hasRomanized
                text: (modelData && modelData.romanized) ? modelData.romanized : ""
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.weight: Font.DemiBold
                font.italic: true
                color: lyricRow.isCurrent ? Qt.rgba(255, 255, 255, 0.85) : root.colPendingText
                elide: Text.ElideRight
                horizontalAlignment: lyricRow.isAnsweringVoice ? Text.AlignRight : (lyricRow.isEnsembleVoice ? Text.AlignHCenter : Text.AlignLeft)
                style: Text.Outline
                styleColor: root.colShadowAmb

                Behavior on color {
                    ColorAnimation { duration: 180 }
                }
            }
        }
    }
}
