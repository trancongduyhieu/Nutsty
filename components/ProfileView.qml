import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// Profile area. A glass header holds the gold listener card over a dot grid, a greeting above it,
// and a giant NUTSTY sliding up the right edge. Under the header sits the all-time listening total.
// Clicking the card opens the profile page (ProfilePage.qml): the card's photo, name and number
// fly to their places on it while the header fades back. Back or Esc plays it the other way.
Item {
    id: root

    property string userName: ""
    property string userTag: ""
    property string avatarUrl: ""
    property double joinedAt: 0
    property string cardNumber: "NTY-0000-0000"
    property bool liteMode: false
    property color accentColor: Theme.accent
    property string apiUrl: "http://127.0.0.1:17890"
    // True once a monthly recap is waiting; the pull hint then says so now and then
    // Monthly recap: GET /api/listening/recap. forceRecap (NUTSTY_FORCE_RECAP=1) opens it with anything played.
    property bool forceRecap: false
    property var recap: null
    readonly property bool recapReady: !!(root.recap && root.recap.ready)
    // the window-sized item the story covers; the profile itself when there is none
    property Item storyHost: null
    property real storyRadius: Theme.radiusApp
    readonly property bool storyActive: recapStory.active

    property var playlists: []

    // Where the welcome overlay flies its card to
    readonly property Item cardSlot: card

    signal trackRequested(var row)
    signal artistRequested(string name)
    signal playlistRequested(var playlist)

    // 0 = the card header, 1 = the profile page; the flying copies interpolate on it
    property real morph: 0
    property bool flying: false
    property bool pageOpen: false
    property var overview: null

    property int playCount: 0
    property real totalHours: 0
    property double firstPlay: 0
    property bool loaded: false

    function refresh() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", root.apiUrl + "/api/listening/totals", true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try {
                    var res = JSON.parse(xhr.responseText);
                    if (res && res.success && res.totals) {
                        root.playCount = res.totals.play_count || 0;
                        root.totalHours = res.totals.total_hours || 0;
                        root.firstPlay = res.totals.first_play ? Date.parse(String(res.totals.first_play).replace(" ", "T")) : 0;
                    }
                } catch (e) {}
            }
            root.loaded = true;
        };
        xhr.send();

        var px = new XMLHttpRequest();
        px.open("GET", root.apiUrl + "/api/listening/profile", true);
        px.onreadystatechange = function() {
            if (px.readyState !== XMLHttpRequest.DONE || px.status !== 200) return;
            try {
                var res = JSON.parse(px.responseText);
                if (res && res.success && res.profile) root.overview = res.profile;
            } catch (e) {}
        };
        px.send();

        var rx = new XMLHttpRequest();
        rx.open("GET", root.apiUrl + "/api/listening/recap" + (root.forceRecap ? "?force=1" : ""), true);
        rx.onreadystatechange = function() {
            if (rx.readyState !== XMLHttpRequest.DONE || rx.status !== 200) return;
            try {
                var res = JSON.parse(rx.responseText);
                if (res && res.success && res.recap) root.recap = res.recap;
            } catch (e) {}
        };
        rx.send();
    }

    // --- Pull down for the recap ---------------------------------------------------------
    // collapsed -> pulling -> expanding -> expanded (scratch) -> scanning -> story | invalid
    property string stage: "collapsed"
    property real expand: 0              // 0 = the header as laid out, 1 = filling the view
    property bool cardFlipped: false
    property real scan: 0
    // which greeting the header shows; rolled once per view
    property int greetIndex: Math.floor(Math.random() * 5)
    property real stamp: 0               // 0..1, the "verified" stamp landing after a good scan
    property bool scanFailed: false
    readonly property real collapsedHeaderH: headerBody.implicitHeight
    readonly property real expandedHeaderH: Math.max(root.collapsedHeaderH, overviewFlick.height - 48)
    readonly property real pullRange: Math.max(1, root.expandedHeaderH - root.collapsedHeaderH)
    readonly property bool recapOpen: root.stage !== "collapsed"

    function animateExpand(to, ms) {
        expandAnim.stop();
        expandAnim.to = to;
        expandAnim.duration = root.liteMode ? 1 : ms;
        expandAnim.start();
    }

    function pullTo(dy) {
        if (root.stage !== "collapsed" && root.stage !== "pulling") return;
        if (root.stage === "collapsed" && (dy <= 0 || overviewFlick.contentY > 1 || root.pageOpen || root.flying)) return;
        expandAnim.stop();
        root.stage = dy > 0 ? "pulling" : "collapsed";
        root.expand = Math.max(0, Math.min(0.8, dy * 0.62 / root.pullRange));
    }

    function pullEnd(dy, velocityY) {
        if (root.stage !== "pulling") return;
        if (root.expand > 0.16 || velocityY > 1600) root.expandFully();
        else root.collapse();
    }

    function expandFully() {
        root.stage = "expanding";
        card.resetScratch();
        root.scan = 0;
        root.scanFailed = false;
        root.stamp = 0;
        overviewFlick.contentY = 0;
        root.animateExpand(1, 760);
        flipTimer.restart();
        root.forceActiveFocus();
    }

    function collapse() {
        flipTimer.stop(); scanAnim.stop(); dissolveAnim.stop(); stampAnim.stop();
        root.stage = "collapsed";
        root.cardFlipped = false;
        root.animateExpand(0, 650);
        resetTimer.restart();
    }

    // Expanded, a drag up folds it away again
    function foldMove(dy) {
        expandAnim.stop();
        root.expand = Math.max(0.4, Math.min(1, 1 + Math.min(0, dy) / root.pullRange * 0.8));
    }
    function foldEnd(dy) {
        if (dy < -64) root.collapse();
        else root.animateExpand(1, 300);
    }

    function onScratched() {
        if (root.stage !== "expanded") return;
        root.stage = "scanning";
        dissolveAnim.restart();
    }

    function afterDissolve() {
        if (root.stage !== "scanning") return;
        root.scanFailed = !root.recapReady;
        scanAnim.duration = root.liteMode ? 1 : (root.scanFailed ? 1950 : 1300);
        scanAnim.restart();
    }

    function afterScan() {
        if (root.stage !== "scanning") return;
        if (root.scanFailed) { root.stage = "invalid"; return; }
        stampAnim.restart();
    }

    function afterStamp() {
        if (root.stage !== "scanning") return;
        root.stage = "story";
        // the story's standing column starts and ends exactly on the header's giant word
        var c = headerArt.mapToItem(recapStory, headerArt.width - 14 - giantMetrics.capHeight / 2, 0);
        recapStory.columnX = c.x;
        recapStory.columnCap = giantMetrics.capHeight;
        recapStory.open();
    }

    function closeStory() {
        recapStory.close();
        root.collapse();
    }

    // From the last page: the header folds back at once under the story, then the ending's card
    // flies home into the header card's spot
    function finishStory() {
        if (root.stage !== "story") return;
        root.collapse();
        expandAnim.complete();
        Qt.callLater(() => recapStory.flyHome(card));
    }

    // Why the code did not scan: how many more songs, or that the month opens on day 3
    readonly property string comeBackText: {
        var r = root.recap;
        if (!r || r.ready) return "";
        if (new Date().getDate() < (r.first_day || 3))
            return I18n.tr("Tổng kết tháng này mở từ ngày %1.", "This month's recap opens on day %1.").arg(r.first_day || 3);
        var n = r.missing_songs || 0;
        return I18n.tr("Nghe thêm %1 bài khác nhau trong tháng này để mở tổng kết.",
                       n === 1 ? "Play %1 more song this month to open your recap." : "Play %1 more different songs this month to open your recap.").arg(n);
    }

    NumberAnimation {
        id: expandAnim
        target: root; property: "expand"
        easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
    }
    Timer {
        id: flipTimer
        interval: root.liteMode ? 1 : 140
        onTriggered: { root.cardFlipped = true; settleTimer.restart(); }
    }
    Timer {
        id: settleTimer
        interval: root.liteMode ? 1 : 640
        onTriggered: if (root.stage === "expanding") root.stage = "expanded"
    }
    Timer {
        id: resetTimer
        interval: root.liteMode ? 1 : 660
        onTriggered: if (root.stage === "collapsed") { card.resetScratch(); root.scan = 0; root.scanFailed = false; root.stamp = 0; }
    }
    NumberAnimation {
        id: dissolveAnim
        target: card; property: "coating"; to: 0
        duration: root.liteMode ? 1 : 480; easing.type: Easing.InOutCubic
        onFinished: root.afterDissolve()
    }
    NumberAnimation {
        id: scanAnim
        target: root; property: "scan"; from: 0; to: 1
        onFinished: root.afterScan()
    }
    // Lite mode shows the stamp already down and moves on quickly
    NumberAnimation {
        id: stampAnim
        target: root; property: "stamp"; from: root.liteMode ? 0.99 : 0; to: 1
        duration: root.liteMode ? 400 : 1500
        onFinished: root.afterStamp()
    }

    // --- Card to page morph ---------------------------------------------------------------
    function rectIn(item) {
        var a = item.mapToItem(root, 0, 0);
        var b = item.mapToItem(root, item.width, item.height);
        return Qt.rect(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(b.x - a.x), Math.abs(b.y - a.y));
    }

    // Measure both ends live, so a scrolled page or a tilted card still lines up
    function measureFlight() {
        flyer.photoFrom = rectIn(card.photoItem);
        flyer.photoTo = rectIn(page.photoSlot);
        flyer.nameFrom = card.nameItem.mapToItem(root, 0, 0);
        flyer.nameTo = page.nameSlot.mapToItem(root, 0, 0);
        flyer.nameFromScale = card.nameItem.font.pixelSize / page.nameSlot.font.pixelSize;
        flyer.numberFrom = card.numberItem.mapToItem(root, 0, 0);
        flyer.numberTo = page.numberSlot.mapToItem(root, 0, 0);
        flyer.numberFromScale = card.numberItem.font.pixelSize / page.numberSlot.font.pixelSize;
    }

    function openProfile() {
        if (root.flying || root.pageOpen) return;
        closeAnim.stop();
        page.scroller.contentY = 0;
        page.landed = false;
        page.reveal = 0;
        root.measureFlight();
        root.flying = true;
        openAnim.restart();
        root.forceActiveFocus();
    }

    function closeProfile() {
        if (!root.pageOpen || root.flying) return;
        openAnim.stop();
        root.measureFlight();
        root.flying = true;
        page.landed = false;
        closeAnim.restart();
    }

    Keys.onEscapePressed: event => {
        if (root.stage === "story") { root.closeStory(); event.accepted = true; }
        else if (root.stage !== "collapsed") { root.collapse(); event.accepted = true; }
        else if (root.pageOpen) { root.closeProfile(); event.accepted = true; }
        else event.accepted = false;
    }

    readonly property int flightMs: root.liteMode ? 1 : 560

    SequentialAnimation {
        id: openAnim
        ParallelAnimation {
            NumberAnimation { target: root; property: "morph"; to: 1; duration: root.flightMs; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] }
            SequentialAnimation {
                PauseAnimation { duration: root.liteMode ? 0 : 280 }
                NumberAnimation { target: page; property: "reveal"; to: 1; duration: root.liteMode ? 1 : 760; easing.type: Easing.OutCubic }
            }
            SequentialAnimation {
                PauseAnimation { duration: root.flightMs }
                ScriptAction { script: { page.landed = true; root.flying = false; root.pageOpen = true; } }
            }
        }
    }

    SequentialAnimation {
        id: closeAnim
        NumberAnimation { target: page; property: "reveal"; to: 0; duration: root.liteMode ? 1 : 180; easing.type: Easing.InQuad }
        NumberAnimation { target: root; property: "morph"; to: 0; duration: root.flightMs; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] }
        ScriptAction { script: { root.flying = false; root.pageOpen = false; page.landed = true; } }
    }

    readonly property var numberLocale: Qt.locale(I18n.locale === "vi" ? "vi_VN" : "en_US")
    readonly property int totalMinutes: Math.max(0, Math.round(root.totalHours * 60))
    // Counts up when the figure arrives
    property real shownMinutes: 0
    Behavior on shownMinutes {
        enabled: !root.liteMode
        NumberAnimation { duration: 900; easing.type: Easing.OutCubic }
    }
    onTotalMinutesChanged: shownMinutes = totalMinutes

    // Surfaces borrow the wallpaper or song colour and stay translucent, so the glass shows through
    readonly property color glassFill: Qt.rgba(0.04 + root.accentColor.r * 0.08, 0.04 + root.accentColor.g * 0.08,
                                               0.06 + root.accentColor.b * 0.10, 0.46)
    readonly property color glassLine: Qt.rgba(1, 1, 1, 0.08)
    readonly property color softText: Qt.rgba(1, 1, 1, 0.62)

    readonly property string displayName: root.userName !== "" ? root.userName : I18n.tr("bạn", "there")

    onVisibleChanged: {
        if (visible) { refresh(); return; }
        // leaving the tab mid-flight or on the page comes back to the card
        openAnim.stop(); closeAnim.stop();
        root.morph = 0; root.flying = false; root.pageOpen = false; page.landed = true;
        if (root.stage === "story") recapStory.close();
        if (root.stage !== "collapsed") { root.collapse(); expandAnim.complete(); }
    }
    Component.onCompleted: {
        // drag with the mouse pulls the header; the wheel still scrolls (acceptedButtons is Qt 6.9+)
        if ("acceptedButtons" in overviewFlick) overviewFlick.acceptedButtons = Qt.NoButton;
        if (visible) refresh();
    }

    Flickable {
        id: overviewFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + 64
        enabled: !root.pageOpen && !root.flying && root.stage !== "story"
        interactive: root.stage === "collapsed"
        visible: opacity > 0.001
        // the story covers it; the expanded card would otherwise show through
        opacity: (1 - root.morph) * (1 - recapStory.shown)
        scale: 1 + 0.04 * root.morph
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: column
            width: Math.min(parent.width - 48, 720)
            anchors.horizontalCenter: parent.horizontalCenter
            y: 24
            spacing: 0

            // ---- the header ----
            Item {
                id: header
                Layout.fillWidth: true
                Layout.preferredHeight: root.collapsedHeaderH + (root.expandedHeaderH - root.collapsedHeaderH) * root.expand

                readonly property real pad: 28
                readonly property real giantSize: Math.round(Math.max(120, Math.min(180, root.collapsedHeaderH * 0.38)))
                // Width of the giant word's visible band, from the right edge
                readonly property real giantBand: giantMetrics.capHeight + 14

                Rectangle {
                    id: headerShape
                    anchors.fill: parent
                    radius: Theme.radiusApp
                    // darkens toward the recap's night as it stretches
                    color: Qt.rgba(root.glassFill.r * (1 - root.expand * 0.6), root.glassFill.g * (1 - root.expand * 0.6),
                                   root.glassFill.b * (1 - root.expand * 0.6), root.glassFill.a + (0.88 - root.glassFill.a) * root.expand)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.07)
                }

                // Pull down anywhere on the header; expanded, drag up to fold it away
                DragHandler {
                    id: headerPull
                    target: null
                    xAxis.enabled: false
                    enabled: !root.pageOpen && !root.flying && !card.scratching
                             && ["collapsed", "pulling", "expanded", "invalid"].indexOf(root.stage) >= 0
                    property bool folding: false
                    property real lastDy: 0
                    onActiveChanged: {
                        if (active) { folding = root.stage === "expanded" || root.stage === "invalid"; lastDy = 0; return; }
                        if (folding) root.foldEnd(lastDy);
                        else root.pullEnd(lastDy, centroid.velocity.y);
                    }
                    onActiveTranslationChanged: {
                        if (!active) return;
                        lastDy = activeTranslation.y;
                        if (folding) root.foldMove(lastDy);
                        else root.pullTo(lastDy);
                    }
                }

                // Dot grid and the giant word, masked to the header's rounded shape
                Item {
                    id: headerArt
                    anchors.fill: parent
                    anchors.margins: 1
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: headerMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }

                    DotGrid {
                        id: dots
                        anchors.fill: parent
                    }

                    // NUTSTY reading top to bottom, drifting upward forever
                    Item {
                        id: giantTrack
                        readonly property real wordLength: giantProbe.implicitWidth
                        readonly property int copies: Math.ceil(headerArt.height / Math.max(1, wordLength)) + 1
                        x: headerArt.width - 14 + (giantMetrics.ascent - giantMetrics.capHeight)
                        y: 0
                        width: wordLength * copies
                        height: header.giantSize
                        rotation: 90
                        transformOrigin: Item.TopLeft

                        Text {
                            id: giantProbe
                            visible: false
                            text: "NUTSTY "
                            font.family: Theme.fontFamily
                            font.pixelSize: header.giantSize
                            font.weight: Font.Black
                            font.letterSpacing: -4
                        }

                        FontMetrics {
                            id: giantMetrics
                            font: giantProbe.font
                            // Height of the capitals, which is all the word uses
                            // tightBoundingRect is a call, so name the font size to re-run it when the font changes
                            readonly property real capHeight: font.pixelSize > 0 ? tightBoundingRect("NUTSY").height : 0
                        }

                        Row {
                            id: giantRow
                            property real drift: 0
                            x: -drift
                            Repeater {
                                model: giantTrack.copies + 1
                                Text {
                                    text: "NUTSTY "
                                    color: Qt.rgba(1, 1, 1, 0.06)
                                    font: giantProbe.font
                                }
                            }
                            NumberAnimation on drift {
                                from: 0
                                to: giantTrack.wordLength
                                duration: Math.max(1, giantTrack.wordLength) * 45
                                loops: Animation.Infinite
                                running: root.visible && !root.liteMode
                            }
                        }
                    }
                }

                Rectangle {
                    id: headerMask
                    anchors.fill: headerArt
                    radius: Theme.radiusApp - 1
                    visible: false
                    layer.enabled: true
                }

                // Under the expanded card: "scratch it!", or why the code did not scan
                Column {
                    id: scratchWords
                    width: Math.min(parent.width - 80, 460)
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.expandedHeaderH * 0.42 + card.height * 0.56 + 34 + (1 - root.expand) * 40
                    spacing: 6
                    opacity: Math.max(0, Math.min(1, (root.expand - 0.75) / 0.25))
                    visible: opacity > 0.001
                    readonly property bool invalid: root.stage === "invalid"

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: scratchWords.invalid ? I18n.tr("Quay lại sau nhé", "Come back later") : I18n.tr("Cào thử đi!", "Scratch it!")
                        opacity: scratchWords.invalid ? 1 : card.coating
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: 22
                        font.weight: Font.Bold
                        font.letterSpacing: -0.4
                    }
                    Text {
                        width: parent.width
                        visible: scratchWords.invalid
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: root.comeBackText
                        color: Qt.rgba(1, 1, 1, 0.6)
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    Item { width: 1; height: 20; visible: scratchWords.invalid }
                    Text {
                        width: parent.width
                        visible: scratchWords.invalid || root.stage === "expanded"
                        horizontalAlignment: Text.AlignHCenter
                        text: I18n.tr("KÉO LÊN HOẶC ESC ĐỂ ĐÓNG", "DRAG UP OR PRESS ESC TO CLOSE")
                        color: Qt.rgba(1, 1, 1, 0.35)
                        font.family: "monospace"
                        font.pixelSize: 11
                        font.letterSpacing: 1
                    }
                }

                ColumnLayout {
                    id: headerBody
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: header.pad
                    anchors.rightMargin: header.pad
                    spacing: 0

                    AppIcon {
                        Layout.topMargin: header.pad
                        source: Qt.resolvedUrl("../assets/icons/nutsty-outline-symbolic.svg")
                        iconSize: 32
                        color: Theme.textPrimary
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 12
                        Layout.rightMargin: header.giantBand
                        opacity: Math.max(0, 1 - root.expand * 2.5)
                        text: [I18n.tr("Chào bạn nhé, %1!", "Hey there, %1!"), I18n.tr("Ủa %1 đó hả!", "Oh, it's %1!"), I18n.tr("Lại gặp %1 rồi!", "%1, back again!"), I18n.tr("Hôm nay nghe gì, %1?", "What's playing, %1?"), I18n.tr("Bá khí quá, %1!", "Aura check, %1!")][root.greetIndex].arg(root.displayName)
                        elide: Text.ElideRight
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: 28
                        font.weight: Font.Bold
                        font.letterSpacing: -0.7
                    }

                    ListenerCard {
                        id: card
                        Layout.topMargin: 22
                        Layout.preferredWidth: Math.min(420, header.width - header.pad * 2 - header.giantBand)
                        Layout.preferredHeight: Layout.preferredWidth / 1.89
                        userName: root.userName
                        userTag: root.userTag
                        avatarUrl: root.avatarUrl
                        joinedAt: root.joinedAt
                        cardNumber: root.cardNumber
                        liteMode: root.liteMode
                        opensProfile: true
                        partsHidden: root.flying || root.pageOpen
                        interactive: root.stage === "collapsed" || root.stage === "pulling"
                        pullable: true
                        coated: true
                        flipped: root.cardFlipped
                        scratchMode: root.stage === "expanded"
                        scanProgress: root.scan
                        scanFailed: root.scanFailed
                        stampProgress: root.stamp
                        onOpenRequested: if (root.stage === "collapsed") root.openProfile()
                        onPullMoved: dy => root.pullTo(dy)
                        onPullReleased: (dy, vy) => root.pullEnd(dy, vy)
                        onScratched: root.onScratched()

                        // Expanded, the card moves to the middle and grows a little
                        readonly property real liftScale: 1 + 0.12 * root.expand
                        scale: liftScale
                        // its double is in flight from the recap's last page
                        opacity: recapStory.homing ? 0 : 1
                        transform: Translate {
                            x: root.expand * (header.width / 2 - header.pad - card.width / 2)
                            y: root.expand * (root.expandedHeaderH * 0.42 - card.height / 2 - card.y)
                        }
                    }

                    // Pull hint: a chevron that, with a recap waiting, turns into words now and then
                    Item {
                        id: hint
                        Layout.preferredWidth: card.width
                        Layout.preferredHeight: 52
                        opacity: Math.max(0, 1 - root.expand * 4)
                        property real words: 0
                        property real bob: 0

                        SequentialAnimation on bob {
                            running: root.visible && !root.liteMode
                            loops: Animation.Infinite
                            NumberAnimation { from: 0; to: 4; duration: 1300; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 4; to: 0; duration: 1300; easing.type: Easing.InOutSine }
                        }

                        SequentialAnimation {
                            running: root.visible && root.recapReady && !root.liteMode
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) hint.words = 0
                            PauseAnimation { duration: 3600 }
                            NumberAnimation { target: hint; property: "words"; to: 1; duration: 520; easing.type: Easing.InOutCubic }
                            PauseAnimation { duration: 2400 }
                            NumberAnimation { target: hint; property: "words"; to: 0; duration: 520; easing.type: Easing.InOutCubic }
                        }

                        AppIcon {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: hint.bob - 2
                            source: Qt.resolvedUrl("../assets/icons/go-down-symbolic.svg")
                            iconSize: 22
                            color: Qt.rgba(1, 1, 1, 0.35)
                            opacity: 1 - hint.words
                            scale: 1 - 0.3 * hint.words
                        }
                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: hint.bob - 2
                            visible: root.recapReady
                            text: I18n.tr("kéo xuống đây!!", "pull down here!!")
                            color: Qt.rgba(1, 1, 1, 0.6)
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            opacity: hint.words
                            scale: 0.85 + 0.15 * hint.words
                        }
                    }
                }
            }

            // ---- total listening time ----
            Rectangle {
                id: listenCard
                Layout.fillWidth: true
                opacity: Math.max(0, 1 - root.expand * 2)
                Layout.topMargin: 16
                Layout.preferredHeight: listenBody.implicitHeight + 48
                radius: Theme.radiusApp
                color: root.glassFill
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.07)

                ColumnLayout {
                    id: listenBody
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 24
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Repeater {
                            model: [
                                { value: Math.floor(root.shownMinutes / 60), unit: "h" },
                                { value: Math.floor(root.shownMinutes) % 60, unit: I18n.tr("p", "m") }
                            ]
                            delegate: RowLayout {
                                spacing: 0
                                Rectangle {
                                    visible: index > 0
                                    Layout.preferredWidth: 1
                                    Layout.preferredHeight: 40
                                    Layout.leftMargin: 18
                                    Layout.rightMargin: 18
                                    color: Qt.rgba(1, 1, 1, 0.3)
                                }
                                Text {
                                    text: root.loaded ? modelData.value.toLocaleString(root.numberLocale, "f", 0) : "--"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 56
                                    font.weight: Font.Bold
                                    font.letterSpacing: -2.5
                                    font.features: { "tnum": 1 }
                                }
                                Text {
                                    Layout.alignment: Qt.AlignBottom
                                    Layout.leftMargin: 2
                                    Layout.bottomMargin: 10
                                    text: modelData.unit
                                    color: Theme.textPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 20
                                    font.weight: Font.Bold
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 16
                            Layout.alignment: Qt.AlignVCenter
                            horizontalAlignment: Text.AlignRight
                            wrapMode: Text.WordWrap
                            text: I18n.tr("Tổng thời gian nghe", "Total listening time")
                            color: root.softText
                            font.family: Theme.fontFamily
                            font.pixelSize: 15
                            font.weight: Font.Medium
                            lineHeight: 1.15
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 18
                        Layout.preferredHeight: 1
                        color: root.glassLine
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 14
                        wrapMode: Text.WordWrap
                        color: root.softText
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        text: {
                            if (!root.loaded) return " ";
                            if (root.playCount === 0)
                                return I18n.tr("Bài nào nghe đủ 30 giây sẽ được tính vào đây.",
                                               "Every song you play for 30 seconds or more is counted here.");
                            var plays = root.playCount.toLocaleString(root.numberLocale, "f", 0);
                            var since = root.firstPlay > 0 ? Qt.formatDate(new Date(root.firstPlay), I18n.locale === "vi" ? "dd/MM/yyyy" : "MMM d, yyyy") : "";
                            var line = I18n.tr("%1 lượt nghe", root.playCount === 1 ? "%1 play" : "%1 plays").arg(plays);
                            if (since !== "") line += I18n.tr(" · nghe từ %1", " · since %1").arg(since);
                            return line;
                        }
                    }
                }
            }
        }
    }

    ProfilePage {
        id: page
        anchors.fill: parent
        visible: opacity > 0.001
        opacity: root.morph
        enabled: root.pageOpen
        userName: root.userName
        avatarUrl: root.avatarUrl
        cardNumber: root.cardNumber
        accentColor: root.accentColor
        liteMode: root.liteMode
        playlists: root.playlists
        overview: root.overview
        onBackRequested: root.closeProfile()
        onTrackRequested: row => root.trackRequested(row)
        onArtistRequested: name => root.artistRequested(name)
        onPlaylistRequested: pl => root.playlistRequested(pl)
    }

    RecapStory {
        id: recapStory
        objectName: "recapStory"
        // drawn over the whole window, header and player bar included, when the host gives one
        parent: root.storyHost ? root.storyHost : root
        anchors.fill: parent
        z: 500
        apiUrl: root.apiUrl
        cornerRadius: root.storyRadius
        recap: root.recap
        userName: root.displayName
        avatarUrl: root.avatarUrl
        cardNumber: root.cardNumber
        joinedAt: root.joinedAt > 0 ? root.joinedAt : root.firstPlay
        accentColor: root.accentColor
        liteMode: root.liteMode
        introCardFrom: card
        onCloseRequested: root.closeStory()
        onFinishRequested: root.finishStory()
    }

    // Copies of the card's photo, name and number in flight between the card and the page
    Item {
        id: flyer
        anchors.fill: parent
        visible: root.flying
        property rect photoFrom: Qt.rect(0, 0, 0, 0)
        property rect photoTo: Qt.rect(0, 0, 0, 0)
        property point nameFrom: Qt.point(0, 0)
        property point nameTo: Qt.point(0, 0)
        property real nameFromScale: 1
        property point numberFrom: Qt.point(0, 0)
        property point numberTo: Qt.point(0, 0)
        property real numberFromScale: 1
        readonly property real m: root.morph
        function mix(a, b) { return a + (b - a) * flyer.m; }
        function mixColor(a, b) {
            return Qt.rgba(mix(a.r, b.r), mix(a.g, b.g), mix(a.b, b.b), mix(a.a, b.a));
        }

        RoundedImage {
            x: flyer.mix(flyer.photoFrom.x, flyer.photoTo.x)
            y: flyer.mix(flyer.photoFrom.y, flyer.photoTo.y)
            width: Math.max(1, flyer.mix(flyer.photoFrom.width, flyer.photoTo.width))
            height: width
            radius: width / 2
            source: root.avatarUrl
            initialsText: root.userName
            borderColor: Qt.rgba(1, 1, 1, 0.12)
            borderWidth: 1
        }
        Text {
            x: flyer.mix(flyer.nameFrom.x, flyer.nameTo.x)
            y: flyer.mix(flyer.nameFrom.y, flyer.nameTo.y)
            transformOrigin: Item.TopLeft
            scale: flyer.mix(flyer.nameFromScale, 1)
            text: root.userName
            color: flyer.mixColor(Qt.color("#24180A"), Qt.color("#ffffff"))
            font: page.nameSlot.font
        }
        Text {
            x: flyer.mix(flyer.numberFrom.x, flyer.numberTo.x)
            y: flyer.mix(flyer.numberFrom.y, flyer.numberTo.y)
            transformOrigin: Item.TopLeft
            scale: flyer.mix(flyer.numberFromScale, 1)
            text: "NUTSTY  " + root.cardNumber
            color: flyer.mixColor(Qt.color("#5A4220"), Qt.rgba(1, 1, 1, 0.62))
            font: page.numberSlot.font
        }
    }
}
