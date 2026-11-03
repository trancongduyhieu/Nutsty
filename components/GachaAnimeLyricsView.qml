import QtQuick
import QtQuick.Layouts
import "."

Item {
    id: root

    // =========================================================================
    // Properties & Inputs passed from DesktopLyricsWidget harness
    // =========================================================================
    property var activeLyrics: []
    property real currentTime: 0.0
    property bool isPlaying: false
    property string magicFontFamily: "Instrument Serif"
    property bool lyricsRomanizationEnabled: true

    // Adaptive Palette Colors
    property color colHighlight: "#deb06c"
    property color colActiveText: "#f8fafc"
    property color colDeadText: "#f1f5f9"
    property color colShadowDir: "#a6020305"
    property color colShadowAmb: "#66000000"
    property bool isLightArea: false

    implicitHeight: 120
    implicitWidth: 740

    // =========================================================================
    // Synchronized Timing Engine (Single Line Active + Deep Languid Exiting Fade)
    // =========================================================================
    property int currentLyricIndex: -1
    property real currentLineStart: 0.0
    property real currentLineEnd: 0.0
    property real lineProgress: 0.0

    property string activeLineText: ""
    property string activeRomanizedText: ""
    property string fadingLineText: ""

    onCurrentTimeChanged: updateProgress()
    onActiveLyricsChanged: updateProgress()

    function updateProgress() {
        if (!activeLyrics || activeLyrics.length === 0) {
            currentLyricIndex = -1;
            lineProgress = 0.0;
            activeLineText = "";
            fadingLineText = "";
            return;
        }

        var idx = -1;
        for (var i = 0; i < activeLyrics.length; i++) {
            var startTime = activeLyrics[i].time;
            var nextTime = (i + 1 < activeLyrics.length) ? activeLyrics[i + 1].time : (startTime + 5.0);
            if (currentTime >= startTime && currentTime < nextTime) {
                idx = i;
                currentLineStart = startTime;
                currentLineEnd = nextTime;
                var duration = Math.max(0.4, nextTime - startTime);
                lineProgress = Math.min(1.0, Math.max(0.0, (currentTime - startTime) / duration));
                break;
            }
        }

        if (idx !== currentLyricIndex) {
            if (currentLyricIndex >= 0 && idx > currentLyricIndex && activeLyrics && currentLyricIndex < activeLyrics.length) {
                // Completed previous line -> trigger smooth, deep fade-down exit!
                triggerFadeOutLine(activeLyrics[currentLyricIndex].text);
            }
            currentLyricIndex = idx;
            if (idx >= 0 && activeLyrics && idx < activeLyrics.length) {
                activeLineText = activeLyrics[idx].text;
                activeRomanizedText = (activeLyrics[idx].romanized || "");
            } else {
                activeLineText = "";
                activeRomanizedText = "";
            }
        }
    }

    function triggerFadeOutLine(oldText) {
        fadingLineText = oldText;
        fadingContainer.opacity = 0.78;
        fadingContainer.y = 0;
        fadingContainer.rotation = 0;
        fadeDownExitAnim.restart();
    }

    // =========================================================================
    // Visual Layer: Exiting Line (Falls & Fades) + Active Line (Gacha Pop)
    // =========================================================================

    // EXITING LINE: Sinks deep (+52px), lingers gracefully, then fades smoothly to 0
    Item {
        id: fadingContainer
        x: 0
        y: 0
        width: parent.width
        height: 68
        transformOrigin: Item.Left
        opacity: 0.0
        visible: fadingLineText !== "" && opacity > 0.01

        EnchantingSentence {
            id: fadingSentence
            anchors.fill: parent
            text: root.fadingLineText
            progress: 1.0
            isActive: false
            isDead: true
            fontFamily: root.magicFontFamily
            fontSize: 35
            colHighlight: root.colHighlight
            colActiveText: root.colActiveText
            colDeadText: root.colDeadText
            colShadowDirectional: root.colShadowDir
            colShadowAmbient: root.colShadowAmb
            isLightArea: root.isLightArea
        }

        SequentialAnimation {
            id: fadeDownExitAnim

            ParallelAnimation {
                NumberAnimation {
                    target: fadingContainer
                    property: "y"
                    from: 0
                    to: 52
                    duration: 1600
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: fadingContainer
                    property: "rotation"
                    from: 0
                    to: 1.8
                    duration: 1600
                    easing.type: Easing.OutCubic
                }
                SequentialAnimation {
                    NumberAnimation {
                        target: fadingContainer
                        property: "opacity"
                        from: 0.78
                        to: 0.65
                        duration: 450
                        easing.type: Easing.Linear
                    }
                    NumberAnimation {
                        target: fadingContainer
                        property: "opacity"
                        from: 0.65
                        to: 0.0
                        duration: 1150
                        easing.type: Easing.OutQuad
                    }
                }
            }

            ScriptAction {
                script: {
                    root.fadingLineText = "";
                }
            }
        }
    }

    // ACTIVE LYRIC LINE: 1-Line only
    Item {
        id: activeContainer
        x: 0
        y: 0
        width: parent.width
        height: 68

        readonly property bool isCurrentInterlude: (root.currentLyricIndex >= 0 && root.activeLyrics && root.currentLyricIndex < root.activeLyrics.length && !!root.activeLyrics[root.currentLyricIndex].isInterlude)
        readonly property var activeLineObj: (root.currentLyricIndex >= 0 && root.activeLyrics && root.currentLyricIndex < root.activeLyrics.length) ? root.activeLyrics[root.currentLyricIndex] : null

        Row {
            id: interludeDotsRow
            visible: activeContainer.isCurrentInterlude
            spacing: 16
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: 48

            Repeater {
                model: (activeContainer.activeLineObj && activeContainer.activeLineObj.words && activeContainer.activeLineObj.words.length === 3) ? activeContainer.activeLineObj.words : 3

                Rectangle {
                    id: dotBall
                    readonly property real dotStart: (typeof modelData === "object" && modelData.start !== undefined) ? modelData.start : 0
                    readonly property real dotEnd: (typeof modelData === "object" && modelData.end !== undefined) ? modelData.end : 0
                    readonly property bool isLit: root.currentTime >= dotStart
                    readonly property bool isPulse: root.currentTime >= dotStart && root.currentTime < dotEnd

                    width: 14
                    height: 14
                    radius: 7
                    anchors.verticalCenter: parent.verticalCenter
                    scale: isPulse ? 1.45 : (isLit ? 1.20 : 1.0)
                    color: isLit ? root.colHighlight : Qt.rgba(255, 255, 255, 0.28)

                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                    Behavior on color { ColorAnimation { duration: 180 } }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 16
                        height: parent.height + 16
                        radius: width / 2
                        color: root.colHighlight
                        opacity: dotBall.isPulse ? 0.50 : (dotBall.isLit ? 0.25 : 0.0)
                        z: -1
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                    }
                }
            }
        }

        EnchantingSentence {
            id: activeSentence
            visible: !activeContainer.isCurrentInterlude
            anchors.fill: parent
            text: root.activeLineText
            progress: root.lineProgress
            isActive: root.currentLyricIndex >= 0
            isDead: false
            fontFamily: root.magicFontFamily
            fontSize: 35
            colHighlight: root.colHighlight
            colActiveText: root.colActiveText
            colDeadText: root.colDeadText
            colShadowDirectional: root.colShadowDir
            colShadowAmbient: root.colShadowAmb
            isLightArea: root.isLightArea
        }

        Text {
            id: activeRomanizedTextItem
            anchors.top: activeSentence.bottom
            anchors.topMargin: -4
            anchors.left: parent.left
            anchors.right: parent.right
            visible: !activeContainer.isCurrentInterlude && root.lyricsRomanizationEnabled && !!root.activeRomanizedText
            text: root.activeRomanizedText
            font.family: Theme.fontFamily
            font.pixelSize: 16
            font.weight: Font.DemiBold
            font.italic: true
            color: Qt.rgba(248, 250, 252, 0.85)
            elide: Text.ElideRight
            style: Text.Outline
            styleColor: root.colShadowAmb
        }
    }
}
