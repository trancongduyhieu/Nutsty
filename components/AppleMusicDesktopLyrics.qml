import QtQuick
import QtQuick.Effects
import "."
import "lyric_lines.js" as LyricLines

// Preset 2: Apple Music style lines on the desktop. It follows the Now Playing lyrics view
// (YTMusicNowPlayingView): same AppleMusicWordFlow sweep, white lines that fade by distance,
// real depth-of-field blur and the same slow glide, plus one soft cinematic shadow under the
// whole stack so it reads on any wallpaper (no outline, no halo).
Item {
    id: root

    // =========================================================================
    // Lyrics Data and State (Passed from LyricsPresetView)
    // =========================================================================
    property var activeLyrics: []
    property real currentTime: 0.0
    property bool isPlaying: false
    property var currentTrack: null
    property bool lyricsRomanizationEnabled: true

    // Adaptive Palette / Styling
    property color colHighlight: "#deb06c"
    property color colActiveText: "#ffffff"
    property color colShadowDir: "#a6020305"
    property color colShadowAmb: "#66000000"
    property bool isLightArea: false
    property bool depthOfField: true

    // Visible lines: one sung line above the active one, the rest upcoming
    property int visibleLinesCount: 5

    // Sizing (matches Now Playing: 28px bold, 1.28 line height)
    readonly property int fontSize: 28
    readonly property int rowMinHeight: 50
    readonly property int lineGap: 16
    readonly property int slotHeight: rowMinHeight + lineGap
    // Now Playing motion curve for glide, scale and fade
    readonly property var glideCurve: [0.42, 0.0, 0.16, 1.0, 1.0, 1.0]

    implicitHeight: slotHeight * visibleLinesCount
    implicitWidth: 880

    visible: root.activeLyrics && root.activeLyrics.length > 0 && root.currentLyricIndex >= 0

    // =========================================================================
    // Synchronized Timing Engine
    // =========================================================================
    property int currentLyricIndex: -1

    onCurrentTimeChanged: updateProgress()
    onActiveLyricsChanged: {
        currentLyricIndex = -1;
        updateProgress();
    }
    Component.onCompleted: updateProgress()

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
        if (idx === -1 && cur < activeLyrics[0].time) idx = 0;

        if (idx !== currentLyricIndex) {
            var old = currentLyricIndex;
            currentLyricIndex = idx;
            if (idx < 0) return;
            if (old >= 0 && Math.abs(idx - old) === 1) {
                recenter(true);
                // An interlude row grows or collapses over 950ms; follow where the line ends up
                settleTimer.restart();
            } else {
                // Seek or new lyrics: snap, then again once the rows around it exist
                recenter(false);
                snapTimer.restart();
            }
        }
    }

    // Active line top sits one slot below the box top, whatever the rows above measure
    function targetContentY() {
        var it = lyricsList.itemAtIndex(root.currentLyricIndex);
        var y = it ? it.y : root.currentLyricIndex * root.slotHeight;
        return y - root.slotHeight;
    }

    function recenter(animate) {
        if (root.currentLyricIndex < 0) return;
        var target = targetContentY();
        if (Math.abs(target - lyricsList.contentY) < 0.5) return;
        scrollAnim.stop();
        if (animate) {
            scrollAnim.from = lyricsList.contentY;
            scrollAnim.to = target;
            scrollAnim.start();
        } else {
            lyricsList.contentY = target;
        }
    }

    NumberAnimation {
        id: scrollAnim
        target: lyricsList
        property: "contentY"
        duration: 950
        easing.type: Easing.BezierSpline
        easing.bezierCurve: root.glideCurve
    }

    // Dies with the view (a callLater could fire after a preview card unloads it)
    Timer {
        id: snapTimer
        interval: 0
        onTriggered: root.recenter(false)
    }

    Timer {
        id: settleTimer
        interval: 980
        onTriggered: root.recenter(true)
    }

    // =========================================================================
    // Line stack. One shadow layer for all lines replaces the per-glyph outline.
    // =========================================================================
    Item {
        id: stage
        anchors.fill: parent

        layer.enabled: root.visible
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: root.colShadowDir
            shadowOpacity: root.isLightArea ? 1.0 : 0.85
            shadowBlur: 0.55
            shadowVerticalOffset: 2
            shadowHorizontalOffset: 0
            blurMax: 20
            autoPaddingEnabled: true
        }

        ListView {
            id: lyricsList
            anchors.fill: parent
            clip: true
            interactive: false
            model: root.activeLyrics
            spacing: root.lineGap
            topMargin: root.slotHeight * root.visibleLinesCount
            bottomMargin: root.slotHeight * root.visibleLinesCount
            cacheBuffer: root.slotHeight * 4
            boundsBehavior: Flickable.StopAtBounds
            highlightRangeMode: ListView.NoHighlightRange
            currentIndex: root.currentLyricIndex

            delegate: Item {
                id: lyricRow
                width: lyricsList.width

                readonly property bool isInterlude: !!(modelData && modelData.isInterlude)
                readonly property int dist: index - root.currentLyricIndex
                readonly property bool isCurrent: dist === 0
                readonly property bool isHeldNoteActive: dist === -1 && flowLoader.item !== null && flowLoader.item.hasActiveHeldWord
                readonly property bool isLit: isCurrent || isHeldNoteActive
                // Bracketed words are the backing vocal: split out and bloomed open under the line
                readonly property var lineParts: LyricLines.splitBackingVocal(modelData ? (modelData.text || "") : "", (modelData && modelData.words) ? modelData.words : null)
                readonly property string leadText: lineParts.lead
                readonly property var leadWords: lineParts.leadWords
                readonly property string backingText: lineParts.backing
                readonly property bool hasBackingVocal: !isInterlude && backingText.length > 0
                readonly property bool hasWords: !!(modelData && modelData.hasWords && !modelData.isSynthetic && leadWords && leadWords.length > 0)
                readonly property bool hasRomanized: !isInterlude && root.lyricsRomanizationEnabled && !!(modelData && modelData.romanized && modelData.romanized.trim() !== "")

                readonly property bool isBackgroundVocal: !!(modelData && modelData.isBackground)
                readonly property bool isEnsembleVoice: !!(modelData && (modelData.agent === "v1000" || modelData.isBackground))
                readonly property bool isAnsweringVoice: !!(modelData && !isEnsembleVoice && modelData.agent && modelData.agent !== "v1")

                height: isInterlude ? (isCurrent ? root.rowMinHeight : 0) : Math.max(root.rowMinHeight, lineContent.implicitHeight + 12)
                visible: isInterlude ? (isCurrent && height > 0.5) : (dist >= -1 && dist < root.visibleLinesCount && opacity > 0.01)
                clip: isInterlude && height < (root.rowMinHeight - 0.5)

                // ── Depth of field (Now Playing values, one more step for the 5th line) ──
                readonly property real targetOpacity: {
                    if (isLit) return 1.0;
                    if (dist < 0) return 0.28;
                    if (dist === 1) return 0.52;
                    if (dist === 2) return 0.32;
                    if (dist === 3) return 0.20;
                    return 0.12;
                }
                readonly property real targetScale: {
                    if (!hasWords || isLit) return 1.0; // plain lines stay still, like Now Playing
                    return dist === 1 ? 0.93 : 0.88;
                }
                readonly property real targetBlur: {
                    if (isLit || !root.depthOfField) return 0.0;
                    if (dist === -1 || dist === 1) return 0.30;
                    if (dist === 2) return 0.55;
                    return 0.80;
                }

                opacity: isInterlude ? (isCurrent ? 1.0 : 0.0) : targetOpacity
                scale: isInterlude ? (isCurrent ? 1.0 : 0.0) : targetScale
                transformOrigin: isAnsweringVoice ? Item.Right : (isEnsembleVoice ? Item.Center : Item.Left)

                // Blur eases in and out instead of popping when a line changes state
                property real blurAmount: targetBlur
                Behavior on blurAmount {
                    NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
                }

                Behavior on height {
                    enabled: lyricRow.isInterlude
                    NumberAnimation { duration: 950; easing.type: Easing.BezierSpline; easing.bezierCurve: root.glideCurve }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 850; easing.type: Easing.BezierSpline; easing.bezierCurve: root.glideCurve }
                }
                Behavior on scale {
                    NumberAnimation { duration: 950; easing.type: Easing.BezierSpline; easing.bezierCurve: root.glideCurve }
                }

                layer.enabled: lyricRow.visible && !lyricRow.isInterlude && lyricRow.blurAmount > 0.01
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: lyricRow.blurAmount
                    blurMax: 16
                    autoPaddingEnabled: true
                }

                Column {
                    id: lineContent
                    width: parent.width
                    anchors.top: parent.top
                    anchors.topMargin: lyricRow.isInterlude ? 11 : 6
                    spacing: 2

                    Item {
                        id: leadBox
                        width: parent.width
                        visible: lyricRow.isInterlude || lyricRow.leadText.length > 0
                        height: !visible ? 0 : lyricRow.isInterlude ? 28
                            : ((flowLoader.visible && flowLoader.item) ? flowLoader.item.implicitHeight : staticTxt.implicitHeight)

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

                        // ── Syllable sweep: only the sung line and its neighbours load the flow ──
                        Loader {
                            id: flowLoader
                            anchors.left: parent.left
                            anchors.right: parent.right
                            active: !lyricRow.isInterlude && lyricRow.hasWords && lyricRow.dist >= -1 && lyricRow.dist <= 1
                            visible: active && lyricRow.isLit

                            sourceComponent: Component {
                                AppleMusicWordFlow {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    words: lyricRow.leadWords
                                    currentTime: root.currentTime
                                    isLineActive: lyricRow.isCurrent
                                    isAnsweringVoice: lyricRow.isAnsweringVoice
                                    isEnsembleVoice: lyricRow.isEnsembleVoice
                                    fontSize: root.fontSize
                                    fontFamily: Theme.fontFamily
                                    fontWeight: Font.Bold
                                    accentColor: root.colActiveText
                                }
                            }
                        }

                        // ── Static line: plain LRC, and every line the flow is not drawing ──
                        Text {
                            id: staticTxt
                            visible: !lyricRow.isInterlude && !flowLoader.visible
                            anchors.left: (!lyricRow.isAnsweringVoice && !lyricRow.isEnsembleVoice) ? parent.left : undefined
                            anchors.right: lyricRow.isAnsweringVoice ? parent.right : undefined
                            anchors.horizontalCenter: lyricRow.isEnsembleVoice ? parent.horizontalCenter : undefined
                            width: Math.min(parent.width * (lyricRow.isAnsweringVoice ? 0.82 : 0.88), implicitWidth)
                            horizontalAlignment: lyricRow.isAnsweringVoice ? Text.AlignRight : (lyricRow.isEnsembleVoice ? Text.AlignHCenter : Text.AlignLeft)
                            textFormat: Text.PlainText
                            text: lyricRow.leadText
                            font.family: Theme.fontFamily
                            font.pixelSize: root.fontSize
                            font.weight: Font.Bold
                            font.italic: lyricRow.isBackgroundVocal
                            color: root.colActiveText
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            lineHeight: 1.28
                        }
                    }

                    BackingVocalLine {
                        width: parent.width
                        visible: lyricRow.hasBackingVocal && smoothExpand > 0.001
                        text: lyricRow.backingText
                        words: lyricRow.lineParts.backingWords
                        currentTime: root.currentTime
                        lineIsActive: lyricRow.isCurrent
                        slide: lyricRow.leadText.length > 0
                        isAnsweringVoice: lyricRow.isAnsweringVoice
                        isEnsembleVoice: lyricRow.isEnsembleVoice
                        accentColor: root.colActiveText
                    }

                    // Secondary Romanization Row (Romaji / Romaja / Pinyin)
                    Text {
                        visible: lyricRow.hasRomanized
                        anchors.left: (!lyricRow.isAnsweringVoice && !lyricRow.isEnsembleVoice) ? parent.left : undefined
                        anchors.right: lyricRow.isAnsweringVoice ? parent.right : undefined
                        anchors.horizontalCenter: lyricRow.isEnsembleVoice ? parent.horizontalCenter : undefined
                        width: Math.min(parent.width * 0.82, implicitWidth)
                        horizontalAlignment: lyricRow.isAnsweringVoice ? Text.AlignRight : (lyricRow.isEnsembleVoice ? Text.AlignHCenter : Text.AlignLeft)
                        textFormat: Text.PlainText
                        text: (modelData && modelData.romanized) ? modelData.romanized : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        font.italic: true
                        color: Qt.rgba(1, 1, 1, lyricRow.isLit ? 0.82 : 0.60)
                        wrapMode: Text.Wrap
                        lineHeight: 1.18
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                }
            }
        }
    }
}
