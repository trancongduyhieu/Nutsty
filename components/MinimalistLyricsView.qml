import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "."

Item {
    id: root

    // =========================================================================
    // Reactive Properties forwarded from DesktopLyricsWidget harness
    // =========================================================================
    property var activeLyrics: []
    property real currentTime: 0.0
    property bool isPlaying: false
    property string magicFontFamily: "Instrument Serif"

    // Adaptive Palette Colors
    property color colHighlight: "#deb06c"
    property color colActiveText: "#ffffff"
    property color colDeadText: "#a0aab8"
    property color colShadowDir: "#a6020305"
    property color colShadowAmb: "#66000000"
    property bool isLightArea: false

    implicitHeight: 140
    implicitWidth: 760

    // Smart Font Fallback: Vietnamese -> Noto Serif, English -> Instrument Serif
    readonly property bool hasVietnamese: /[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ]/i.test(currentRawText)
    readonly property string activeFontFamily: hasVietnamese ? "Noto Serif" : (root.magicFontFamily !== "" ? root.magicFontFamily : "Instrument Serif")

    // =========================================================================
    // Synchronized Timing & Sentence Splitting Engine
    // =========================================================================
    property int currentLyricIndex: -1
    property real currentLineStart: 0.0
    property real currentLineEnd: 0.0
    property real lineDuration: 1.0
    property real lineProgress: 0.0

    property string currentRawText: ""
    property var line1WordData: []
    property var line2WordData: []
    property real line1SplitRatio: 0.50

    // Down-to-Line-2 trigger: active when lineProgress reaches line1SplitRatio and Line 2 has words
    readonly property bool isLine2Active: (line2WordData.length > 0) && (lineProgress >= line1SplitRatio)

    // Outgoing Sentence Exit Stage (400ms Slide-Up Full-Sentence Motion Blur)
    property string exitingLine1Text: ""
    property string exitingLine2Text: ""
    property real exitProgress: 1.0
    readonly property bool isExiting: exitProgress < 1.0

    // Measured widths cache for Line 1 words (to calculate exact dynamic push-left X)
    property var line1WordWidths: ({})

    onCurrentTimeChanged: updateProgress()
    onActiveLyricsChanged: updateProgress()

    function updateProgress() {
        if (!activeLyrics || activeLyrics.length === 0) {
            if (currentLyricIndex !== -1) {
                currentLyricIndex = -1;
                lineProgress = 0.0;
                currentRawText = "";
                line1WordData = [];
                line2WordData = [];
                exitProgress = 1.0;
            }
            return;
        }

        var idx = -1;
        for (var i = 0; i < activeLyrics.length; i++) {
            var st = activeLyrics[i].time;
            var et = (i + 1 < activeLyrics.length) ? activeLyrics[i + 1].time : (st + 5.0);
            if (currentTime >= st && currentTime < et) {
                idx = i;
                currentLineStart = st;
                currentLineEnd = et;
                lineDuration = Math.min(6.5, Math.max(0.6, et - st));
                lineProgress = Math.min(1.0, Math.max(0.0, (currentTime - st) / lineDuration));
                break;
            }
        }

        if (idx !== currentLyricIndex) {
            if (idx >= 0 && idx < activeLyrics.length) {
                var rawNew = activeLyrics[idx].text ? activeLyrics[idx].text.trim().toLowerCase() : "";

                // Snapshot previous sentence for Slide-Up Full-Sentence Motion Blur exit
                if (currentLyricIndex !== -1 && isPlaying) {
                    var prevL1 = [];
                    for (var k1 = 0; k1 < line1WordData.length; k1++) {
                        prevL1.push(line1WordData[k1].word);
                    }
                    var prevL2 = [];
                    for (var k2 = 0; k2 < line2WordData.length; k2++) {
                        prevL2.push(line2WordData[k2].word);
                    }
                    exitingLine1Text = prevL1.join(" ");
                    exitingLine2Text = prevL2.join(" ");
                    exitAnim.restart();
                } else {
                    exitingLine1Text = "";
                    exitingLine2Text = "";
                    exitProgress = 1.0;
                }

                currentLyricIndex = idx;
                currentRawText = rawNew;
                line1WordWidths = {};
                assembleSentence(rawNew);
            } else {
                currentLyricIndex = -1;
                lineProgress = 0.0;
                currentRawText = "";
                line1WordData = [];
                line2WordData = [];
                exitProgress = 1.0;
            }
        }
    }

    // =========================================================================
    // Sentence Word-Splitter & Timing Allocator (1 Câu chia 2 Hàng)
    // =========================================================================
    function assembleSentence(raw) {
        if (!raw || raw.trim() === "") {
            line1WordData = [];
            line2WordData = [];
            return;
        }

        var words = raw.split(/\s+/).filter(function(w) { return w.length > 0; });
        if (words.length === 0) {
            line1WordData = [];
            line2WordData = [];
            return;
        }

        var l1Words = [];
        var l2Words = [];

        if (words.length <= 3) {
            l1Words = words;
            l2Words = [];
            line1SplitRatio = 1.0;
        } else {
            var splitIdx = Math.ceil(words.length / 2);
            l1Words = words.slice(0, splitIdx);
            l2Words = words.slice(splitIdx);

            var l1Chars = l1Words.join(" ").length;
            var l2Chars = l2Words.join(" ").length;
            var totalChars = l1Chars + l2Chars;
            line1SplitRatio = totalChars > 0 ? Math.max(0.38, Math.min(0.62, l1Chars / totalChars)) : 0.50;
        }

        // Allocate timing for Line 1 (0.0 to line1SplitRatio)
        var l1List = [];
        var curChar1 = 0;
        var totalL1Chars = Math.max(1, l1Words.join("").length);
        for (var i = 0; i < l1Words.length; i++) {
            var w1 = l1Words[i];
            var startP1 = (curChar1 / totalL1Chars) * line1SplitRatio;
            curChar1 += w1.length;
            var endP1 = (curChar1 / totalL1Chars) * line1SplitRatio;
            l1List.push({
                "word": w1,
                "idx": i,
                "startProg": startP1,
                "endProg": endP1
            });
        }
        line1WordData = l1List;

        // Allocate timing for Line 2 (line1SplitRatio to 1.0)
        var l2List = [];
        var curChar2 = 0;
        var totalL2Chars = Math.max(1, l2Words.join("").length);
        var remainingRatio = 1.0 - line1SplitRatio;
        for (var j = 0; j < l2Words.length; j++) {
            var w2 = l2Words[j];
            var startP2 = line1SplitRatio + (curChar2 / totalL2Chars) * remainingRatio;
            curChar2 += w2.length;
            var endP2 = line1SplitRatio + (curChar2 / totalL2Chars) * remainingRatio;
            l2List.push({
                "word": w2,
                "idx": j,
                "startProg": startP2,
                "endProg": endP2
            });
        }
        line2WordData = l2List;
    }

    // =========================================================================
    // Dynamic Push-Left (Trục X) & Push-Up (Trục Y) Calculations
    // =========================================================================

    // Trục Y của Hàng 1:
    // - Khi chỉ có Hàng 1: Nằm ở vị trí cơ sở trung tâm y: 50 (hoặc 28 nếu câu ngắn 1 hàng)
    // - Khi Hàng 2 xuất hiện (isLine2Active === true): Bị đẩy vọt lên trên y: 6
    readonly property real targetLine1Y: isLine2Active ? 6 : (line2WordData.length > 0 ? 50 : 28)

    // Trục X của Hàng 1 (Đẩy từ sang trái: X = 3 -> 2 -> 1):
    // - Từ 1 xuất hiện ở bên phải.
    // - Mỗi khi từ mới xuất hiện, Hàng 1 trượt mượt sang trái đúng bằng độ rộng các từ chưa xuất hiện.
    // - Khi Hàng 1 đã xuất hiện đủ tất cả các từ (hoặc isLine2Active === true): Khóa cố định ở x: 0 (không đẩy nữa).
    readonly property real dynamicLine1ShiftX: {
        if (line1WordData.length === 0 || isLine2Active) return 0.0;

        var unappearedAccum = 0.0;
        for (var k = 0; k < line1WordData.length; k++) {
            if (lineProgress < line1WordData[k].startProg) {
                var wWidth = (line1WordWidths && line1WordWidths[k] > 0) ? line1WordWidths[k] : Math.max(28.0, line1WordData[k].word.length * 16.0);
                unappearedAccum += (wWidth + 9.0);
            }
        }
        return Math.min(380.0, unappearedAccum);
    }

    // =========================================================================
    // 0.4s Slide-Up Full-Sentence Motion Blur Exit Animation
    // =========================================================================
    NumberAnimation {
        id: exitAnim
        target: root
        property: "exitProgress"
        from: 0.0
        to: 1.0
        duration: 400
        easing.type: Easing.OutCubic
    }

    readonly property real exitBlurVal: (1.0 - exitProgress) * 0.85
    readonly property real exitStreakOffset: (1.0 - exitProgress) * 20.0

    // =========================================================================
    // Main Stage Display Container
    // =========================================================================
    Item {
        id: stageContainer
        anchors.fill: parent
        clip: false

        // ---------------------------------------------------------------------
        // 1. EXITING SENTENCE (Both Lines Slide Up & Blur Out - Image 3)
        // ---------------------------------------------------------------------
        Item {
            id: exitingSentenceItem
            width: parent.width
            height: 110
            visible: root.isExiting && (root.exitingLine1Text.length > 0 || root.exitingLine2Text.length > 0)
            y: -root.exitProgress * 44
            opacity: Math.max(0.0, 1.0 - root.exitProgress * 1.5)

            layer.enabled: root.isExiting && (root.exitBlurVal > 0.03)
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: root.exitBlurVal
                blurMax: Theme.blurMedium
                shadowEnabled: true
                shadowColor: root.colShadowAmb
                shadowBlur: 0.35
                shadowVerticalOffset: 2
            }

            // Exiting Line 1 Ghost Streaks
            Text {
                visible: root.isExiting && root.exitingLine1Text.length > 0
                x: -root.exitStreakOffset * 1.2
                y: 6
                text: root.exitingLine1Text
                font.family: root.activeFontFamily
                font.pixelSize: 34
                color: root.colActiveText
                opacity: (1.0 - root.exitProgress) * 0.35
            }
            Text {
                visible: root.isExiting && root.exitingLine1Text.length > 0
                x: root.exitStreakOffset * 1.2
                y: 6
                text: root.exitingLine1Text
                font.family: root.activeFontFamily
                font.pixelSize: 34
                color: root.colActiveText
                opacity: (1.0 - root.exitProgress) * 0.35
            }

            // Exiting Line 1 Main Text
            Text {
                id: exitL1Main
                x: 0
                y: 6
                text: root.exitingLine1Text
                font.family: root.activeFontFamily
                font.pixelSize: 34
                color: root.colActiveText
                style: Text.Outline
                styleColor: root.colShadowDir
            }

            // Exiting Line 2 Ghost Streaks
            Text {
                visible: root.isExiting && root.exitingLine2Text.length > 0
                x: -root.exitStreakOffset * 1.2
                y: 54
                text: root.exitingLine2Text
                font.family: root.activeFontFamily
                font.pixelSize: 34
                color: root.colActiveText
                opacity: (1.0 - root.exitProgress) * 0.35
            }
            Text {
                visible: root.isExiting && root.exitingLine2Text.length > 0
                x: root.exitStreakOffset * 1.2
                y: 54
                text: root.exitingLine2Text
                font.family: root.activeFontFamily
                font.pixelSize: 34
                color: root.colActiveText
                opacity: (1.0 - root.exitProgress) * 0.35
            }

            // Exiting Line 2 Main Text
            Text {
                id: exitL2Main
                x: 0
                y: 54
                text: root.exitingLine2Text
                font.family: root.activeFontFamily
                font.pixelSize: 34
                color: root.colActiveText
                style: Text.Outline
                styleColor: root.colShadowDir
            }
        }

        // ---------------------------------------------------------------------
        // 2. ACTIVE SENTENCE (1 Câu chia 2 Hàng, Word-by-Word Motion Blur)
        // ---------------------------------------------------------------------
        Item {
            id: activeSentenceItem
            anchors.fill: parent
            visible: !root.isExiting || root.exitProgress > 0.4

            // --- HÀNG 1: Nửa đầu câu (Line 1) ---
            Item {
                id: line1Container
                width: parent.width
                height: 48
                y: root.targetLine1Y
                Behavior on y {
                    NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                }
                clip: false

                Row {
                    id: line1Row
                    spacing: 9
                    anchors.verticalCenter: parent.verticalCenter

                    // Trục X đẩy sang trái mượt mà khi từ mới xuất hiện
                    x: root.dynamicLine1ShiftX
                    Behavior on x {
                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                    }

                    Repeater {
                        model: root.line1WordData

                        Item {
                            id: wordItem1
                            width: wordTxt1.implicitWidth
                            height: 48

                            // Trigger appearance when lineProgress reaches startProg
                            property bool shouldAppear: root.lineProgress >= modelData.startProg
                            property bool isAppeared: false

                            property real wordAlpha: 0.0
                            property real wordBlur: 0.0
                            property real streakOffset: 0.0
                            property real wordGlideX: 18.0

                            layer.enabled: wordItem1.isAppeared && (wordItem1.wordBlur > 0.02)
                            layer.effect: MultiEffect {
                                blurEnabled: true
                                blur: wordItem1.wordBlur
                                blurMax: Theme.blurMedium
                                shadowEnabled: true
                                shadowColor: root.colShadowAmb
                                shadowBlur: 0.35
                                shadowVerticalOffset: 2
                            }

                            onShouldAppearChanged: {
                                if (shouldAppear && !isAppeared) {
                                    isAppeared = true;
                                    if (Math.abs(root.lineProgress - modelData.startProg) < 0.12) {
                                        wordAnim1.restart();
                                    } else {
                                        wordAlpha = 1.0;
                                        wordBlur = 0.0;
                                        streakOffset = 0.0;
                                        wordGlideX = 0.0;
                                    }
                                } else if (!shouldAppear && isAppeared) {
                                    isAppeared = false;
                                    wordAlpha = 0.0;
                                    wordBlur = 0.0;
                                    streakOffset = 0.0;
                                    wordGlideX = 18.0;
                                }
                            }

                            // 200ms Word-by-Word Motion Blur Animation
                            ParallelAnimation {
                                id: wordAnim1
                                NumberAnimation { target: wordItem1; property: "wordAlpha"; from: 0.0; to: 1.0; duration: 140; easing.type: Easing.OutQuad }
                                NumberAnimation { target: wordItem1; property: "wordBlur"; from: 0.85; to: 0.0; duration: 220; easing.type: Easing.OutCubic }
                                NumberAnimation { target: wordItem1; property: "streakOffset"; from: 18.0; to: 0.0; duration: 220; easing.type: Easing.OutCubic }
                                NumberAnimation { target: wordItem1; property: "wordGlideX"; from: 18.0; to: 0.0; duration: 220; easing.type: Easing.OutCubic }
                            }

                            // Motion Blur Twin Ghost Streaks (Horizontal Speed Streaks)
                            Text {
                                visible: wordItem1.isAppeared && wordItem1.streakOffset > 0.5
                                x: wordItem1.wordGlideX - wordItem1.streakOffset * 1.2
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.word
                                font.family: root.activeFontFamily
                                font.pixelSize: 34
                                color: root.colActiveText
                                opacity: (wordItem1.streakOffset / 18.0) * 0.35
                            }
                            Text {
                                visible: wordItem1.isAppeared && wordItem1.streakOffset > 0.5
                                x: wordItem1.wordGlideX + wordItem1.streakOffset * 1.2
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.word
                                font.family: root.activeFontFamily
                                font.pixelSize: 34
                                color: root.colActiveText
                                opacity: (wordItem1.streakOffset / 18.0) * 0.35
                            }

                            // Main Word Text
                            Text {
                                id: wordTxt1
                                x: wordItem1.wordGlideX
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.word
                                font.family: root.activeFontFamily
                                font.pixelSize: 34
                                color: root.colActiveText
                                opacity: wordItem1.wordAlpha
                                visible: wordItem1.isAppeared

                                style: Text.Outline
                                styleColor: root.colShadowDir

                                onImplicitWidthChanged: {
                                    if (implicitWidth > 0 && modelData && modelData.idx !== undefined) {
                                        var copy = Object.assign({}, root.line1WordWidths);
                                        copy[modelData.idx] = implicitWidth;
                                        root.line1WordWidths = copy;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // --- HÀNG 2: Nửa sau câu (Line 2) ---
            Item {
                id: line2Container
                width: parent.width
                height: 48
                y: 54
                clip: false
                visible: root.line2WordData.length > 0 && root.isLine2Active

                Row {
                    id: line2Row
                    x: 0
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 9

                    Repeater {
                        model: root.line2WordData

                        Item {
                            id: wordItem2
                            width: wordTxt2.implicitWidth
                            height: 48

                            // Trigger appearance when lineProgress reaches startProg (starts after Line 1 is done)
                            property bool shouldAppear2: root.lineProgress >= modelData.startProg
                            property bool isAppeared2: false

                            property real wordAlpha2: 0.0
                            property real wordBlur2: 0.0
                            property real streakOffset2: 0.0
                            property real wordGlideX2: 18.0

                            layer.enabled: wordItem2.isAppeared2 && (wordItem2.wordBlur2 > 0.02)
                            layer.effect: MultiEffect {
                                blurEnabled: true
                                blur: wordItem2.wordBlur2
                                blurMax: Theme.blurMedium
                                shadowEnabled: true
                                shadowColor: root.colShadowAmb
                                shadowBlur: 0.35
                                shadowVerticalOffset: 2
                            }

                            onShouldAppear2Changed: {
                                if (shouldAppear2 && !isAppeared2) {
                                    isAppeared2 = true;
                                    if (Math.abs(root.lineProgress - modelData.startProg) < 0.12) {
                                        wordAnim2.restart();
                                    } else {
                                        wordAlpha2 = 1.0;
                                        wordBlur2 = 0.0;
                                        streakOffset2 = 0.0;
                                        wordGlideX2 = 0.0;
                                    }
                                } else if (!shouldAppear2 && isAppeared2) {
                                    isAppeared2 = false;
                                    wordAlpha2 = 0.0;
                                    wordBlur2 = 0.0;
                                    streakOffset2 = 0.0;
                                    wordGlideX2 = 18.0;
                                }
                            }

                            // 200ms Word-by-Word Motion Blur Animation for Line 2
                            ParallelAnimation {
                                id: wordAnim2
                                NumberAnimation { target: wordItem2; property: "wordAlpha2"; from: 0.0; to: 1.0; duration: 140; easing.type: Easing.OutQuad }
                                NumberAnimation { target: wordItem2; property: "wordBlur2"; from: 0.85; to: 0.0; duration: 220; easing.type: Easing.OutCubic }
                                NumberAnimation { target: wordItem2; property: "streakOffset2"; from: 18.0; to: 0.0; duration: 220; easing.type: Easing.OutCubic }
                                NumberAnimation { target: wordItem2; property: "wordGlideX2"; from: 18.0; to: 0.0; duration: 220; easing.type: Easing.OutCubic }
                            }

                            // Ghost Streaks
                            Text {
                                visible: wordItem2.isAppeared2 && wordItem2.streakOffset2 > 0.5
                                x: wordItem2.wordGlideX2 - wordItem2.streakOffset2 * 1.2
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.word
                                font.family: root.activeFontFamily
                                font.pixelSize: 34
                                color: root.colActiveText
                                opacity: (wordItem2.streakOffset2 / 18.0) * 0.35
                            }
                            Text {
                                visible: wordItem2.isAppeared2 && wordItem2.streakOffset2 > 0.5
                                x: wordItem2.wordGlideX2 + wordItem2.streakOffset2 * 1.2
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.word
                                font.family: root.activeFontFamily
                                font.pixelSize: 34
                                color: root.colActiveText
                                opacity: (wordItem2.streakOffset2 / 18.0) * 0.35
                            }

                            // Main Word Text
                            Text {
                                id: wordTxt2
                                x: wordItem2.wordGlideX2
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.word
                                font.family: root.activeFontFamily
                                font.pixelSize: 34
                                color: root.colActiveText
                                opacity: wordItem2.wordAlpha2
                                visible: wordItem2.isAppeared2

                                style: Text.Outline
                                styleColor: root.colShadowDir
                            }
                        }
                    }
                }
            }
        }
    }
}
