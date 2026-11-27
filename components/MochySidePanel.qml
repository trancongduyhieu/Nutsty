import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import "."

Item {
    id: root

    property var currentTrack: null
    property real currentTime: 0.0
    property real totalDuration: 0.0
    property bool isPlaying: false
    property bool isLiked: false
    property color accentColor: Theme.accent
    property var activeLyrics: []
    property bool isLoadingLyrics: false
    property string resolvedSquareImage: ""
    // Last real playback position from mpv and when it was read (ms); drives the per-frame lyric clock
    property real syncTime: 0.0
    property double syncStamp: 0
    property string activeTab: "lyrics" // "lyrics" | "queue" | "comments"
    property bool isLoggedIn: false
    // Corner radius declared once; everything nested derives from it (R_inner = R_outer - inset)
    readonly property real panelRadius: 24
    readonly property real dockInset: 8
    // Up Next lean, as a full perspective: turn about the vertical axis (rotY), tip forward or
    // back (rotX), roll in the screen plane (rotZ), viewing distance in px (smaller = stronger
    // perspective), and the pivot as fractions of the list (pivotY is the viewer's eye height).
    // Writable so UpNextTiltTuner can adjust them live.
    property real upNextRotY: 16
    property real upNextRotX: 0
    property real upNextRotZ: 0
    property real upNextPerspective: 780
    property real upNextPivotX: 0.42
    property real upNextPivotY: 0.61

    // origin * perspective * Rx * Ry * Rz * -origin. The perspective row turns depth into w and
    // drops z, so the result is a flat 2D projective transform: the scene graph and hit testing
    // agree on where every row is drawn.
    function upNextMatrix(w, h, px, py) {
        var ox = w * (px === undefined ? upNextPivotX : px), oy = h * (py === undefined ? upNextPivotY : py);
        var d2r = Math.PI / 180;
        var ax = -upNextRotY * d2r, bx = upNextRotX * d2r, cz = upNextRotZ * d2r;
        var ry = Qt.matrix4x4(Math.cos(ax), 0, Math.sin(ax), 0,  0, 1, 0, 0,  -Math.sin(ax), 0, Math.cos(ax), 0,  0, 0, 0, 1);
        var rx = Qt.matrix4x4(1, 0, 0, 0,  0, Math.cos(bx), -Math.sin(bx), 0,  0, Math.sin(bx), Math.cos(bx), 0,  0, 0, 0, 1);
        var rz = Qt.matrix4x4(Math.cos(cz), -Math.sin(cz), 0, 0,  Math.sin(cz), Math.cos(cz), 0, 0,  0, 0, 1, 0,  0, 0, 0, 1);
        var dist = Math.max(100, upNextPerspective);
        var persp = Qt.matrix4x4(1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 0, 0,  0, 0, -1 / dist, 1);
        var toO = Qt.matrix4x4(1, 0, 0, -ox,  0, 1, 0, -oy,  0, 0, 1, 0,  0, 0, 0, 1);
        var back = Qt.matrix4x4(1, 0, 0, ox,  0, 1, 0, oy,  0, 0, 1, 0,  0, 0, 0, 1);
        return back.times(persp).times(rx).times(ry).times(rz).times(toO);
    }
    readonly property bool liteMode: typeof win !== "undefined" && win && Boolean(win.liteMode)
    // No frame: every tab floats on the wallpaper, the tab buttons are big words and the cover's
    // outer edges dissolve into a blur
    // Playing Next list leans in perspective (upNextMatrix); off keeps it straight
    property bool upNextTilt: false
    // Style 2 (liner's queue drawer): the panel sits on a frosted card. The window backdrop under
    // the panel is blurred 48 px, the dark scrim goes back over it and a neutral wash
    // rgba(70, 70, 70, 0.2) lifts the card off the page; 14 px corners, no border.
    property bool cardLook: false
    property Item glassSource: null
    property Item glassScrim: null
    readonly property real cardRadius: 14
    // Style 2 swaps the big word tabs at the bottom for liner's queue header at the top
    readonly property real headerSpace: cardLook ? 64 : 0
    // The lyrics tab starts its cover right under the header
    readonly property real coverDrop: cardLook ? headerSpace - 24 : 0
    readonly property real dockSpace: cardLook ? dockInset : actionDock.height + actionDock.anchors.bottomMargin + dockInset
    property var currentTracks: []
    readonly property real targetPanelWidth: Math.max(380, Math.min(460, Math.round((parent ? parent.width : 1200) * 0.34)))

    // Performance Gating (Zero-overhead: disables all shaders, FBOs, and lyric updates when hidden, closed, or in another app)
    property bool isEffectivelyActive: true
    readonly property bool isPanelRenderable: root.visible && root.opacity > 0.01 && root.isEffectivelyActive

    Item {
        id: glassCard
        anchors.fill: parent
        z: -100
        visible: root.cardLook && root.isPanelRenderable
        readonly property bool blurOn: visible && !root.liteMode && !!root.glassSource
        // The settled panel rect in backdrop coordinates. The slide-in transform is left out on
        // purpose: the backdrop is soft, so sampling the resting spot during the 0.3 s slide reads
        // the same and spares a per-frame remap.
        readonly property rect sampleRect: root.parent && root.glassSource
            ? root.parent.mapToItem(root.glassSource, root.x, root.y, root.width, root.height)
            : Qt.rect(0, 0, 0, 0)

        Item {
            id: glassContent
            anchors.fill: parent
            visible: false
            layer.enabled: true

            ShaderEffectSource {
                id: glassBackdropCrop
                anchors.fill: parent
                visible: false
                live: glassCard.blurOn
                sourceItem: glassCard.blurOn ? root.glassSource : null
                sourceRect: glassCard.sampleRect
            }
            MultiEffect {
                anchors.fill: parent
                visible: glassCard.blurOn
                source: glassBackdropCrop
                blurEnabled: true
                blur: 1.0
                blurMax: 48
                autoPaddingEnabled: false
            }
            ShaderEffectSource {
                anchors.fill: parent
                visible: glassCard.blurOn && !!root.glassScrim
                live: visible
                sourceItem: visible ? root.glassScrim : null
                sourceRect: glassCard.sampleRect
            }
            // Lite mode or no backdrop: the same card as a flat fill, no shader
            Rectangle {
                anchors.fill: parent
                visible: !glassCard.blurOn
                color: Qt.rgba(0.06, 0.06, 0.07, 0.85)
            }
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(70 / 255, 70 / 255, 70 / 255, 0.2)
            }
        }

        Rectangle {
            id: glassMask
            anchors.fill: parent
            radius: root.cardRadius
            visible: false
            layer.enabled: true
        }

        MultiEffect {
            anchors.fill: parent
            source: glassContent
            maskEnabled: true
            maskSource: glassMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    // Style 2 header, liner's RightDrawerHeader: a back button that closes the panel, the tab's
    // name over a small count, and a pill of icon buttons for Lyrics, Comments and Up Next
    component HeaderAction: Rectangle {
        id: ha
        property string icon: ""
        property string tip: ""
        property bool active: false
        signal clicked()
        width: 36; height: 32
        radius: 7
        color: active ? Qt.rgba(1, 1, 1, 0.16) : (haHover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
        Behavior on color { ColorAnimation { duration: 150 } }
        scale: haMouse.pressed ? 0.94 : 1.0
        Behavior on scale { NumberAnimation { duration: 150 } }
        HoverHandler { id: haHover }
        AppIcon {
            anchors.centerIn: parent
            source: ha.icon
            iconSize: 18
            color: "#ffffff"
            opacity: ha.active || haHover.hovered ? 1.0 : 0.7
        }
        MouseArea { id: haMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ha.clicked() }
        ToolTip.visible: haHover.hovered && ha.tip !== ""
        ToolTip.delay: 400
        ToolTip.text: ha.tip
    }

    Item {
        id: cardHeader
        visible: root.cardLook
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 12
        height: 40
        z: 60

        Rectangle {
            id: cardBackBtn
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 44; height: 40
            radius: 10
            color: backHover.hovered ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.10)
            Behavior on color { ColorAnimation { duration: 150 } }
            scale: backMouse.pressed ? 0.94 : 1.0
            Behavior on scale { NumberAnimation { duration: 150 } }
            HoverHandler { id: backHover }
            AppIcon {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: backHover.hovered ? -2 : 0
                Behavior on anchors.horizontalCenterOffset { NumberAnimation { duration: 150 } }
                source: "../assets/icons/go-previous-symbolic.svg"
                iconSize: 20
                color: "#ffffff"
            }
            MouseArea { id: backMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.closeRequested() }
        }

        Column {
            anchors.left: cardBackBtn.right
            anchors.right: cardTabPill.left
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: root.activeTab === "queue" ? I18n.tr("Tiếp theo", "Up next")
                      : root.activeTab === "comments" ? I18n.tr("Bình luận", "Comments")
                      : I18n.tr("Lời bài hát", "Lyrics")
                color: "#ffffff"
                font.family: Theme.fontFamily
                font.pixelSize: 16
                font.weight: Font.DemiBold
                font.letterSpacing: -0.2
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                visible: text !== ""
                text: root.activeTab === "queue" ? I18n.tr(root.upNextTracks.length + " bài", root.upNextTracks.length + (root.upNextTracks.length === 1 ? " track" : " tracks"))
                      : root.activeTab === "comments" ? (commentsView.countText !== "" ? I18n.tr(commentsView.countText + " bình luận", commentsView.countText + " comments") : "")
                      : (root.currentTrack ? (root.currentTrack.title || "") : "")
                color: Qt.rgba(1, 1, 1, 0.45)
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
        }

        Rectangle {
            id: cardTabPill
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: tabRow.implicitWidth + 8
            height: 40
            radius: 10
            color: Qt.rgba(1, 1, 1, 0.10)
            Row {
                id: tabRow
                anchors.centerIn: parent
                spacing: 2
                HeaderAction {
                    icon: "../assets/icons/material/ms-lyrics.svg"
                    tip: I18n.tr("Lời bài hát", "Lyrics")
                    active: root.activeTab === "lyrics"
                    onClicked: root.tabRequested("lyrics")
                }
                HeaderAction {
                    icon: "../assets/icons/material/ms-forum.svg"
                    tip: I18n.tr("Bình luận", "Comments")
                    active: root.activeTab === "comments"
                    onClicked: root.tabRequested("comments")
                }
                HeaderAction {
                    icon: "../assets/icons/material/ms-queue_music.svg"
                    tip: I18n.tr("Tiếp theo", "Up next")
                    active: root.activeTab === "queue"
                    onClicked: root.tabRequested("queue")
                }
            }
        }
    }

    signal closeRequested()
    signal openDetailsRequested()
    signal seekRequested(real seconds)
    signal playPauseRequested()
    signal nextRequested()
    signal previousRequested()
    signal toggleLikeRequested()
    signal trackPlayRequested(var track, int index)
    signal trackContextMenuRequested(var track, real gx, real gy)
    signal tabRequested(string tab)

    readonly property var upNextTracks: {
        if (!root.currentTracks || root.currentTracks.length === 0) return [];
        var curIdx = -1;
        if (root.currentTrack) {
            for (var i = 0; i < root.currentTracks.length; ++i) {
                if (root.isSameTrack(root.currentTracks[i], root.currentTrack)) {
                    curIdx = i;
                    break;
                }
            }
        }
        if (curIdx >= 0) {
            return root.currentTracks.slice(curIdx + 1);
        }
        return root.currentTracks;
    }

    function isSameTrack(a, b) {
        if (!a || !b) return false;
        if (typeof win !== "undefined" && win && typeof win.isSameTrack === "function") {
            return win.isSameTrack(a, b);
        }
        if (a.id && b.id && a.id === b.id) return true;
        if (a.videoId && b.videoId && a.videoId === b.videoId) return true;
        if (a.path && b.path && a.path === b.path) return true;
        return (a.title && b.title && a.title === b.title && a.artist && b.artist && a.artist === b.artist);
    }

    function formatDuration(sec) {
        if (!sec || isNaN(sec) || sec <= 0) return "--:--";
        var m = Math.floor(sec / 60);
        var s = Math.floor(sec % 60);
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
    }

    function getTrackDuration(trk) {
        if (!trk) return "";
        if (typeof trk.duration === "number") return formatDuration(trk.duration);
        if (typeof trk.duration === "string" && trk.duration.length > 0) return trk.duration;
        if (trk.length) return formatDuration(trk.length);
        return "";
    }

    // -------------------------------------------------------------------------
    // EXPRESSIVE LYRICS SCHEDULE (Mochy ExpressiveText.kt timing model)
    // Every line gets a fixed timetable when the lyrics load: when it comes in,
    // when its singing ends, whether it overlaps the next line and when it leaves.
    // - Lines that don't overlap are replaced in place: the old one flies off
    //   while the new one rises into the same spot.
    // - Lines that overlap stack: the next one waits underneath, then glides up
    //   into the top spot as the line above flies off.
    // All motion is a pure function of a smooth per-frame clock, so nothing pops.
    // -------------------------------------------------------------------------
    property int currentLyricIndex: -1
    property bool isInterlude: false

    // -------------------------------------------------------------------------
    // POSTER TITLE (Mochy PosterText + ExpressiveTitle)
    // A new song opens on its title set big, words rising in one after another.
    // When its lyrics are found, the big title slides down and shrinks into the
    // small title under the artist while the lyrics take the space it leaves,
    // and slides back up if they go away. titleFound: 0 big title, 1 lyrics.
    // -------------------------------------------------------------------------
    readonly property bool hasSyncedLyrics: !!(root.activeLyrics && root.activeLyrics.length > 0)
    readonly property string trackTitle: root.currentTrack ? String(root.currentTrack.title || root.currentTrack.name || "") : ""
    readonly property string trackArtist: root.currentTrack ? String(root.currentTrack.artist || root.currentTrack.author || "") : ""
    readonly property string trackKey: root.currentTrack ? String(root.currentTrack.videoId || root.currentTrack.path || root.trackTitle) : ""
    property real titleFound: hasSyncedLyrics ? 1.0 : 0.0
    // Seconds since the title began coming in; it runs the same entrance clock as a lyric line
    property real titleClock: 99.0
    // What the poster shows: held on the old song until it has faded out, so text never swaps in view
    property string shownTitle: trackTitle
    property string shownArtist: trackArtist
    // 1: poster and credits shown, 0: faded out between two songs
    property real swapFade: 1.0
    // Desktop addition: the title holds this long on a new song before it gives way to the lyrics,
    // so it is seen even when the lyrics come from cache in the same instant
    readonly property int kTitleHoldMs: 1600

    // "No lyrics" is only said once nothing came back: no lyrics, not searching, and it stayed that
    // way for a moment after the song changed. Without the wait it flashed during the title hold
    // and in the gap before the lookup starts, then the lyrics arrived on top of it.
    property bool lyricsMissingConfirmed: false
    readonly property bool lyricsMissingNow: !root.hasSyncedLyrics && !root.isLoadingLyrics && root.trackKey !== ""
    onLyricsMissingNowChanged: {
        root.lyricsMissingConfirmed = false;
        if (root.lyricsMissingNow) lyricsMissingTimer.restart(); else lyricsMissingTimer.stop();
    }
    Timer {
        id: lyricsMissingTimer
        interval: 2500
        onTriggered: root.lyricsMissingConfirmed = root.lyricsMissingNow
    }

    NumberAnimation {
        id: titleFoundAnim
        target: root; property: "titleFound"; duration: 820
        easing.type: Easing.BezierSpline; easing.bezierCurve: [0.3, 0.0, 0.1, 1.0, 1.0, 1.0]
    }
    // A song change never cuts: the old poster and credits fade out, the new title is put in
    // place unseen, then its words rise in one after another as the credits fade back
    SequentialAnimation {
        id: trackSwapAnim
        NumberAnimation { target: root; property: "swapFade"; to: 0.0; duration: 260; easing.type: Easing.InOutQuad }
        ScriptAction { script: root.commitNewTrack() }
        ScriptAction { script: titleClockAnim.restart() }
        NumberAnimation { target: root; property: "swapFade"; to: 1.0; duration: 520; easing.type: Easing.OutCubic }
    }
    NumberAnimation { id: titleClockAnim; target: root; property: "titleClock"; from: 0.0; to: 6.0; duration: 6000 }
    Timer {
        id: titleHold
        interval: root.kTitleHoldMs
        onTriggered: root.settleTitle()
    }
    function settleTitle() {
        if (titleHold.running || trackSwapAnim.running) return;
        var target = root.hasSyncedLyrics ? 1.0 : 0.0;
        if (Math.abs(root.titleFound - target) < 0.001) return;
        titleFoundAnim.stop();
        titleFoundAnim.to = target;
        titleFoundAnim.start();
    }
    function commitNewTrack() {
        titleFoundAnim.stop();
        root.titleFound = 0.0;
        titleClockAnim.stop();
        root.titleClock = 0.0;
        root.shownTitle = root.trackTitle;
        root.shownArtist = root.trackArtist;
        root.shownKey = root.trackKey;
        titleHold.restart();
    }
    onTrackKeyChanged: {
        root.lyricsMissingConfirmed = false;
        if (root.lyricsMissingNow) lyricsMissingTimer.restart();
        trackSwapAnim.stop();
        // the old lyrics clear a moment before the key turns: don't let the old title rise while it fades
        titleFoundAnim.stop();
        if (root.trackTitle === "") { root.shownTitle = ""; root.shownArtist = ""; root.shownKey = root.trackKey; root.swapFade = 1.0; return; }
        trackSwapAnim.start();
    }
    // same song, details filled in later (artist arriving after the title): follow quietly
    // (title and key change together on a new song, in no set order: only follow when the key held)
    property string shownKey: trackKey
    onTrackTitleChanged: if (!trackSwapAnim.running && root.trackKey === root.shownKey) root.shownTitle = root.trackTitle
    onTrackArtistChanged: if (!trackSwapAnim.running && root.trackKey === root.shownKey) root.shownArtist = root.trackArtist
    onHasSyncedLyricsChanged: settleTitle()

    readonly property color mochyInk: "#F1ECEC"
    readonly property color mochyInkSoft: Qt.rgba(0.945, 0.925, 0.925, 0.62)
    readonly property color mochyInkDim: Qt.rgba(0.945, 0.925, 0.925, 0.40)
    readonly property string mochyFont: "Inter, Inter Display, SF Pro Display, system-ui, sans-serif"

    // Timing constants (seconds), mirrored from Mochy
    readonly property real kEnterLead: 0.42
    readonly property real kEnterDur: 0.56
    readonly property real kEnterStagger: 0.065
    readonly property real kExitDur: 0.46
    readonly property real kExitStagger: 0.04
    readonly property real kGapExitDelay: 0.45
    readonly property real kMinInterludeGap: 4.0

    // Per-line timetable, rebuilt whenever the lyrics change
    property var lyricSchedule: ({ count: 0, starts: [], ends: [], enter: [], exit: [], gone: [], overlaps: [], words: [], scales: [], fonts: [] })

    // Smooth clock: extrapolates between position samples every frame
    property real animClock: 0.0
    property real clockSample: 0.0
    property double clockStamp: 0
    // Latency compensation so words light up right on the beat
    readonly property real effectiveLyricTime: root.animClock + 0.06

    ListModel { id: visibleLinesModel }

    // Resolved cover image URL
    // Animated covers follow the app's setting (Settings > animated cover / canvas source)
    property bool animatedCoverEnabled: (typeof win !== "undefined" && win) ? win.animatedCoverEnabled : true
    property string canvasPreference: (typeof win !== "undefined" && win) ? win.canvasPreference : "apple_first"
    // Set when the cover cannot be opened (e.g. a cached thumbnail file that was cleaned up); the
    // panel then falls back to the video's YouTube thumbnail instead of showing nothing
    property bool coverUrlFailed: false
    readonly property string coverFallbackUrl: (root.currentTrack && root.currentTrack.videoId)
        ? "https://i.ytimg.com/vi/" + root.currentTrack.videoId + "/hqdefault.jpg" : ""
    onCoverImageUrlPrimaryChanged: root.coverUrlFailed = false
    readonly property string coverImageUrl: (root.coverUrlFailed && root.coverFallbackUrl !== "")
        ? root.coverFallbackUrl : root.coverImageUrlPrimary
    readonly property string coverImageUrlPrimary: {
        if (root.resolvedSquareImage !== "") {
            var r = root.resolvedSquareImage;
            return (r.startsWith("/") && !r.startsWith("file://")) ? ("file://" + r) : r;
        }
        if (!root.currentTrack) return "";
        var s = String(root.currentTrack.image || root.currentTrack.artUrl || root.currentTrack.cover || root.currentTrack.thumbnail || "");
        if (!s && root.currentTrack.videoId) {
            s = "https://i.ytimg.com/vi/" + root.currentTrack.videoId + "/hqdefault.jpg";
        }
        if (s.indexOf("i.ytimg.com") !== -1) s = s.split("?")[0];
        return (s.startsWith("/") && !s.startsWith("file://")) ? ("file://" + s) : s;
    }

    function easeOutCubic(x) {
        var c = Math.max(0.0, Math.min(1.0, x));
        var u = 1.0 - c;
        return 1.0 - u * u * u;
    }
    function smoothstep(x) {
        var c = Math.max(0.0, Math.min(1.0, x));
        return c * c * (3.0 - 2.0 * c);
    }
    function smootherstep(x) {
        var c = Math.max(0.0, Math.min(1.0, x));
        return c * c * c * (c * (c * 6.0 - 15.0) + 10.0);
    }

    // Mochy Dynamic Downscaling: long lines step down so they wrap cleanly
    function computeBaseFontSize(words) {
        if (!words || words.length === 0) return 26;
        var count = words.length;
        var totalChars = 0;
        for (var i = 0; i < words.length; ++i) {
            totalChars += (words[i].text || "").length;
        }
        if (count >= 12 || totalChars >= 42) return 18;
        if (count >= 9 || totalChars >= 30) return 21;
        if (count >= 6 || totalChars >= 20) return 24;
        return 27;
    }

    function toSec(val) {
        if (val === undefined || val === null) return 0.0;
        var n = Number(val);
        if (isNaN(n)) return 0.0;
        if (n > 10000) return n / 1000.0;
        return n;
    }

    function lineStartOf(entry) {
        return entry ? toSec(entry.time !== undefined ? entry.time : (entry.startTime || 0)) : 0.0;
    }

    // Word timings: the line's own when it has them, otherwise the time until the
    // next line shared out by word length, holding a little back for a breath.
    function parseWords(entry, idx) {
        if (!entry) return [];
        var rawText = (entry && entry.text) ? String(entry.text).trim() : "";
        var lineStart = lineStartOf(entry);
        var wList = [];
        if (entry.words && entry.words.length > 0) {
            for (var w = 0; w < entry.words.length; ++w) {
                var wd = entry.words[w];
                var wt = (wd && wd.text) ? String(wd.text).trim() : "";
                if (wt) {
                    var s = (wd.start !== undefined) ? toSec(wd.start) : (wd.startTime !== undefined ? toSec(wd.startTime) : lineStart);
                    var e = (wd.end !== undefined) ? toSec(wd.end) : (wd.endTime !== undefined ? toSec(wd.endTime) : (s + 0.25));
                    wList.push({ text: wt, start: s, end: e, duration: Math.max(0.05, e - s), isHeld: !!(wd.isHeld || (e - s >= 0.85)) });
                }
            }
        } else if (rawText) {
            var parts = rawText.split(/\s+/).filter(function(p) { return p.length > 0; });
            if (parts.length === 0) return [];
            var nextStart = (idx + 1 < activeLyrics.length) ? lineStartOf(activeLyrics[idx + 1]) : (lineStart + 4.0);
            var lineEnd = Math.max(nextStart, lineStart + 0.6);
            var singing = Math.min((lineEnd - lineStart) * 0.86, parts.length * 0.9);
            var total = 0;
            for (var k = 0; k < parts.length; ++k) total += parts[k].length + 1.5;
            var cursor = lineStart;
            for (var p = 0; p < parts.length; ++p) {
                var len = singing * (parts[p].length + 1.5) / total;
                wList.push({ text: parts[p], start: cursor, end: cursor + len, duration: Math.max(0.05, len), isHeld: false });
                cursor += len;
            }
        }
        return wList;
    }

    function rebuildSchedule() {
        var lines = activeLyrics || [];
        var n = lines.length;
        var sch = { count: n, starts: [], ends: [], enter: [], exit: [], gone: [], overlaps: [], words: [], scales: [], fonts: [] };
        for (var i = 0; i < n; ++i) {
            var ws = parseWords(lines[i], i);
            sch.words.push(ws);
            sch.scales.push(computeWordScales(ws));
            var st = lineStartOf(lines[i]);
            sch.starts.push(st);
            sch.ends.push(ws.length > 0 ? ws[ws.length - 1].end : st);
        }
        for (var a = 0; a < n; ++a) {
            if (a === 0) sch.enter.push(sch.starts[0] < kMinInterludeGap ? 0.0 : sch.starts[0] - kEnterLead);
            else sch.enter.push(Math.max(sch.starts[a] - kEnterLead, sch.starts[a - 1]));
        }
        for (var b = 0; b < n; ++b) {
            sch.overlaps.push(b < n - 1 && sch.ends[b] - 0.1 > sch.enter[b + 1]);
        }
        for (var c = 0; c < n; ++c) {
            var ex = -1;
            if (c < n - 1) {
                var nx = c + 1;
                var interlude = (sch.starts[nx] - sch.ends[c] >= kMinInterludeGap) && (sch.enter[nx] - (sch.ends[c] + kGapExitDelay + 0.25) > 1.5);
                if (interlude) ex = Math.min(sch.ends[c] + kGapExitDelay, sch.enter[nx]);
                else if (sch.overlaps[c]) ex = sch.ends[c] + 0.15;
                else ex = Math.max(sch.enter[nx], Math.min(sch.ends[c] - 0.1, Math.max(sch.enter[nx], sch.starts[nx])));
            }
            sch.exit.push(ex);
            sch.gone.push(ex < 0 ? Number.POSITIVE_INFINITY : ex + kExitDur + 12 * kExitStagger + 0.12);
            // Stacked lines share the canvas, so they come in a touch smaller
            var stacked = sch.overlaps[c] || (c > 0 && sch.overlaps[c - 1]);
            var base = computeBaseFontSize(sch.words[c]);
            sch.fonts.push(stacked ? Math.round(base * 0.86) : base);
        }
        lyricSchedule = sch;
        visibleLinesModel.clear();
        syncVisibleLines(root.effectiveLyricTime);
    }

    // Which lines are on screen at t: back from the newest line that has come in,
    // through every line not gone yet (an overlapping line keeps the scan going).
    function syncVisibleLines(t) {
        var sch = lyricSchedule;
        if (!sch || sch.count === 0) {
            if (visibleLinesModel.count > 0) visibleLinesModel.clear();
            return;
        }
        var lo = 0, hi = sch.count - 1, shown = -1;
        while (lo <= hi) {
            var mid = (lo + hi) >> 1;
            if (sch.enter[mid] <= t) { shown = mid; lo = mid + 1; } else hi = mid - 1;
        }
        var want = [];
        for (var j = shown; j >= 0 && want.length < 4; --j) {
            if (t < sch.gone[j]) want.unshift(j);
            else if (!sch.overlaps[j]) break;
        }
        // Diff into the model so lines already on screen keep their delegates
        for (var r = visibleLinesModel.count - 1; r >= 0; --r) {
            if (want.indexOf(visibleLinesModel.get(r).lineIdx) < 0) visibleLinesModel.remove(r);
        }
        for (var w = 0; w < want.length; ++w) {
            var pos = 0;
            var present = false;
            for (var m = 0; m < visibleLinesModel.count; ++m) {
                var li = visibleLinesModel.get(m).lineIdx;
                if (li === want[w]) { present = true; break; }
                if (li < want[w]) pos = m + 1;
            }
            if (!present) visibleLinesModel.insert(pos, { lineIdx: want[w] });
        }
    }

    function advanceClock() {
        var target = root.currentTime;
        // Extrapolate from mpv's last reported position every frame, not the 25 fps UI clock
        if (root.isPlaying && root.syncStamp > 0) {
            target = root.syncTime + Math.max(0.0, (Date.now() - root.syncStamp) / 1000.0);
        }
        // Monotonic while playing; small corrections are absorbed, only a real seek moves it back
        if (target > root.animClock || root.animClock - target > 0.3) root.animClock = target;
        syncVisibleLines(root.effectiveLyricTime);
    }

    FrameAnimation {
        running: root.isPanelRenderable && root.lyricSchedule.count > 0 && root.isPlaying
        onTriggered: root.advanceClock()
    }

    function updateLyricState() {
        if (!root.isPanelRenderable) return;
        if (!activeLyrics || activeLyrics.length === 0) {
            currentLyricIndex = -1;
            isInterlude = false;
            return;
        }
        var pos = root.currentTime;
        var idx = -1;
        for (var i = 0; i < activeLyrics.length; ++i) {
            if (lineStartOf(activeLyrics[i]) <= pos) idx = i;
            else break;
        }
        currentLyricIndex = idx;
        isInterlude = visibleLinesModel.count === 0;
    }

    onCurrentTimeChanged: {
        var jumped = Math.abs(root.currentTime - root.animClock) > 1.0;
        root.clockSample = root.currentTime;
        root.clockStamp = Date.now();
        if (!root.isPanelRenderable) return;
        if (jumped) {
            // Seek: start the clock fresh; lines that land now animate in from their birth
            root.animClock = root.currentTime;
            visibleLinesModel.clear();
        }
        advanceClock();
        updateLyricState();
    }
    onActiveLyricsChanged: {
        rebuildSchedule();
        if (root.isPanelRenderable) updateLyricState();
    }
    // Cover effects (feather, fade, glow, aura) are each the item's own layer.effect running the
    // cover_feather shader. There is no separate mask item: masks kept as their own layers went
    // stale when the panel was hidden or the window recreated, and the cover then drew unmasked as
    // a hard-edged box over the whole panel. They follow whether the panel is on screen, not
    // isPanelRenderable: that also drops while the window is shown but not focused (just opened,
    // reopened, another window clicked), and the cover then drew as a hard box until focused.
    readonly property bool fxOn: root.visible && root.opacity > 0.01 && !root.liteMode
    onIsPanelRenderableChanged: {
        if (isPanelRenderable) {
            root.animClock = root.currentTime;
            visibleLinesModel.clear();
            advanceClock();
            updateLyricState();
        }
    }
    Component.onCompleted: rebuildSchedule()

    // Mochy wordScales Algorithm (AlternatePlayerStyles.kt lines 89-102):
    // Shortest word >= 3 chars gets 1.55x (shout word).
    // Words >= 11 chars scale to 0.74x, >= 9 chars scale to 0.86x, else 1.0x.
    function computeWordScales(words) {
        if (!words || words.length === 0) return [];
        var minLen = 999;
        var shoutIdx = -1;
        for (var i = 0; i < words.length; ++i) {
            var str = words[i].text ? String(words[i].text) : "";
            var len = str.length;
            if (len >= 3 && len < minLen) {
                minLen = len;
                shoutIdx = i;
            }
        }

        var scales = [];
        for (var j = 0; j < words.length; ++j) {
            var s = words[j].text ? String(words[j].text) : "";
            var l = s.length;
            if (j === shoutIdx && words.length > 1) {
                scales.push(1.55);
            } else if (l >= 11) {
                scales.push(0.74);
            } else if (l >= 9) {
                scales.push(0.86);
            } else {
                scales.push(1.0);
            }
        }
        return scales;
    }

    // Big type look: the cover's square edges dissolve into its own blur instead of ending hard
    readonly property bool coverFeathered: root.fxOn
    // Big type look: the cover runs the full panel width and dissolves downward into the lyrics;
    // a blurred copy spills past the panel's own edges so no frame line shows (coverAura)
    property real auraSpill: 30
    property real auraStrength: 0.71
    // Big type cover box, live-tunable (LiveTuner in shell.qml): px offsets from the panel's top,
    // left and right edges (negative reaches outside), length as a multiple of the panel width,
    // edge blur in px, where the bottom fade starts and where the lyrics start (fractions of the cover)
    property real coverTop: -10
    property real coverLeft: -22
    property real coverRight: -13
    property real coverLength: 0.99
    property real coverFeather: 59
    property real coverFadeStart: 0.62
    property real coverLyricsAt: 0.94
    // The cover's edge is clear for its outer px and turns solid over a band as wide as a 64px
    // blur, centred a little inside coverFeather, so the image scatters out instead of ending in a line
    readonly property real featherSpread: 32
    readonly property real featherMid: root.coverFeather + 20
    readonly property real featherIn: root.featherMid - root.featherSpread
    readonly property real featherOut: root.featherMid + root.featherSpread
    // The blurred copy behind ends where the sharp cover does: it only softens the edge band and
    // never shows past it, where it read as a second, blurred cover behind the poster
    readonly property real glowIn: root.featherIn + 8
    readonly property real glowOut: root.featherOut

    // Big type look: the cover's blurred light spreads out past the panel's left and top edges and
    // fades into whatever is behind, so the cover has no box around it. It sits outside
    // panelContainer because that layer clips to the panel's bounds.
    Item {
        id: coverAura
        // Follows the cover box, reaching auraSpill further out on the left. The page clips at the
        // panel's top and right, so the light must be gone by those lines: the box starts at the
        // panel top, ends at its right edge, and the mask keeps a margin wider than its own blur
        // on every side, so the blurred mask reaches zero before any edge and never cuts a line.
        readonly property real pad: 80
        x: root.coverLeft - root.auraSpill - pad
        y: 0
        width: root.width - x
        height: Math.round(root.coverTop + root.width * root.coverLength * 1.3) + pad
        // On the card the light would spill past its edges and read as a sticker: off there
        visible: !root.cardLook && root.coverFeathered && root.fxOn && opacity > 0.01
        // fades in when its image arrives, so the blur never pops in a moment after the cover
        opacity: (root.activeTab === "lyrics" && auraSrc.status === Image.Ready) ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        // Opaque in the cover's middle, thinning to nothing at the far left, top, right and bottom
        layer.enabled: root.fxOn
        layer.effect: ShaderEffect {
            readonly property real w: Math.max(1, coverAura.width)
            readonly property real h: Math.max(1, coverAura.height)
            readonly property real inL: coverAura.pad + root.auraSpill * 0.3
            property point u_left: Qt.point((inL - 64) / w, (inL + 64) / w)
            property point u_right: Qt.point((coverAura.pad - 64) / w, (coverAura.pad + 64) / w)
            property point u_top: Qt.point((coverAura.pad - 64) / h, (coverAura.pad + 64) / h)
            property point u_bottom: Qt.point(0, (h - coverAura.pad - 0.45 * (h - coverAura.pad)) / h)
            fragmentShader: Qt.resolvedUrl("../assets/shaders/cover_feather.frag.qsb")
        }

        Image {
            id: auraSrc
            anchors.fill: parent
            // A few pixels only: the aura is the cover's colours as light, with no shapes left in it,
            // so it never reads as a second, blurred cover behind the sharp one
            sourceSize: Qt.size(6, 6)
            source: root.coverImageUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: false
            onStatusChanged: if (status === Image.Error && !root.coverUrlFailed && String(source) === root.coverImageUrlPrimary) root.coverUrlFailed = true
        }
        MultiEffect {
            anchors.fill: parent
            source: auraSrc
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            saturation: 0.8
            brightness: -0.05
            autoPaddingEnabled: false
            // half: the light stays a faint haze with a dark gap around the cover
            opacity: root.auraStrength * 0.5
        }
    }

    // Big type look: the cover lives here instead of inside panelContainer, so the text shadow that
    // layer casts does not draw a dark box around the cover's soft edges
    Item {
        id: coverHost
        anchors.fill: parent
        // On the card the cover stays inside it, below the header
        clip: root.cardLook
        opacity: lyricsView.opacity
        visible: opacity > 0.01
    }

    // -------------------------------------------------------------------------
    // 1. MASTER PANEL CONTAINER WITH CONCENTRIC CLIP
    // -------------------------------------------------------------------------
    Item {
        id: panelContainer
        anchors.fill: parent
        // Nothing to clip: the layer carries the shadow that keeps floating text readable. Off in
        // Lite mode, where the text goes without it.
        layer.enabled: root.isPanelRenderable && !root.liteMode
        layer.smooth: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.75)
            shadowBlur: 0.55
            shadowVerticalOffset: 3
        }

        // =====================================================================
        // VIEW 1: LYRICS MODE (Mochy CircleCover + Expressive Kinetic Canvas)
        // =====================================================================
        Item {
            id: lyricsView
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: root.activeTab === "lyrics" ? 1.0 : 0.0
            scale: root.activeTab === "lyrics" ? 1.0 : 0.94
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            // =====================================================================
            // LAYER B: CIRCLECOVER (MOCHY EXACT GEOMETRIC CIRCLE ARC - ELEVATED)
            // Center: (0.13 * W, -0.28 * W), Radius: 1.14 * W, Height: 0.88 * W
            // Sweeps through right edge at 0.457 W, left edge at 0.853 W
            // Elevated to give +130px generous breathing room for multi-line lyrics!
            // "ở trên rõ, ở dưới làm mờ"
            // =====================================================================
            Item {
                id: circleCover
            // Lives in coverHost, outside panelContainer, so that layer's text shadow does not
            // draw a dark box around the cover's soft edges
            parent: coverHost
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: root.coverTop + root.coverDrop
            anchors.leftMargin: root.coverLeft
            anchors.rightMargin: root.coverRight
            height: Math.round(root.width * root.coverLength)
            z: 2

            readonly property real cw: width

            // Cover glow: instead of a dark drop shadow under the arc, the artwork spills its own light
            // downward. A heavily blurred, saturated copy sits behind the sharp cover and extends past
            // the curve, fading out so the lyrics underneath stay readable.
            Item {
                id: coverGlow
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: parent.height + glowSpill
                readonly property real glowSpill: Math.round(circleCover.cw * 0.60)
                visible: root.fxOn
                // Every edge fades: the sides and top softly (the box runs past the panel edge, which
                // would otherwise clip it into a hard line), the bottom from halfway down so the
                // lyrics underneath stay readable.
                layer.enabled: root.fxOn
                layer.effect: ShaderEffect {
                    readonly property real w: Math.max(1, coverGlow.width)
                    readonly property real h: Math.max(1, coverGlow.height)
                    property point u_left: Qt.point(root.glowIn / w, root.glowOut / w)
                    property point u_right: Qt.point(root.glowIn / w, root.glowOut / w)
                    property point u_top: Qt.point(root.glowIn / h, root.glowOut / h)
                    // gone a little below the cover, so only a faint light reaches the lyrics
                    property point u_bottom: Qt.point(0.45, 0.8)
                    fragmentShader: Qt.resolvedUrl("../assets/shaders/cover_feather.frag.qsb")
                }

                // Cropped exactly like the sharp cover (its box, not the taller glow box), so the
                // blur under the edge band is the same picture and never a second, zoomed-in cover
                Image {
                    id: coverGlowSrc
                    sourceSize: Qt.size(128, 128)
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: circleCover.height
                    source: root.coverImageUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    visible: false
                }
                MultiEffect {
                    anchors.fill: coverGlowSrc
                    source: coverGlowSrc
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 64
                    saturation: 0.9
                    brightness: 0.0
                    autoPaddingEnabled: false
                    opacity: coverGlowSrc.status === Image.Ready ? 0.85 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                }
            }

            // Big type look: the sharp cover thins out over a wide band at its top and sides, showing
            // the blurred glow behind it, and fades top to bottom into the lyrics below
            Item {
                id: sharpImageContainer
                anchors.fill: parent
                layer.enabled: root.fxOn
                layer.effect: ShaderEffect {
                    readonly property real w: Math.max(1, sharpImageContainer.width)
                    readonly property real h: Math.max(1, sharpImageContainer.height)
                    property point u_left: Qt.point(root.featherIn / w, root.featherOut / w)
                    property point u_right: Qt.point(root.featherIn / w, root.featherOut / w)
                    property point u_top: Qt.point(root.featherIn / h, root.featherOut / h)
                    property point u_bottom: Qt.point(0, 1 - root.coverFadeStart)
                    fragmentShader: Qt.resolvedUrl("../assets/shaders/cover_feather.frag.qsb")
                }

                // 1. Album artwork: the shared cover surface, so a song with an Apple Music animated
                // cover or a Spotify Canvas plays it here (looped, muted, paused with the music);
                // without one it is the still cover. The arc mask above cuts it like the still did.
                MediaCoverSurface {
                    id: topSharpCover
                    anchors.fill: parent
                    track: root.currentTrack
                    radius: 0
                    showShadow: false
                    borderWidth: 0
                    showPlaceholder: false
                    overrideImage: root.coverImageUrl
                    isPlaying: root.isPlaying
                    animatedCoverEnabled: root.animatedCoverEnabled
                    canvasPreference: root.canvasPreference
                }
            }

            // No lit stroke or bloom on the arc: the curve is drawn by the artwork edge alone,
            // with the cover glow below carrying the light (a glowing line read as a sticker cut-out)

            // Click artwork to expand full-screen Now Playing
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openDetailsRequested()
            }
        }

        // Close mark: two thin accent strokes lying on the cover
        StrokeClose {
            id: closeBtn
            visible: !root.cardLook
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 16
            z: 20
            accentColor: root.accentColor
            onClicked: root.closeRequested()
        }

        // =====================================================================
        // LAYER D: BOTTOM DOCK, reserves the action row's space (Lyrics | Up Next) for the lyric canvas
        // =====================================================================
        Item {
            id: bottomDock
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.leftMargin: root.dockInset
            anchors.rightMargin: root.dockInset
            anchors.bottomMargin: root.dockInset
            height: root.cardLook ? 0 : actionDock.height
            z: 10

        }

        // =====================================================================
        // POSTER CREDITS (Mochy PosterText): the artist, then the title set small.
        // The small title shows only once the big one has slid down into it.
        // =====================================================================
        Column {
            id: posterCredits
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: bottomDock.top
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            anchors.bottomMargin: 16
            spacing: 3
            z: 5
            visible: root.currentTrack !== null
            opacity: root.swapFade

            MarqueeText {
                width: parent.width
                height: 18
                visible: root.shownArtist !== ""
                text: root.shownArtist
                color: root.mochyInkSoft
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
                active: root.isPanelRenderable
            }
            MarqueeText {
                id: posterSmallTitleBox
                width: parent.width
                height: 24
                text: root.shownTitle
                color: root.mochyInkSoft
                font.family: Theme.fontFamily
                font.pixelSize: 19
                font.weight: Font.Bold
                font.letterSpacing: -0.035 * 19
                active: root.isPanelRenderable && opacity > 0.99
                opacity: Math.max(0, Math.min(1, (root.titleFound - 0.6) / 0.4))
            }
        }
        // Landing point for the big title: where the small title's first glyph line starts
        Item {
            id: posterSmallTitle
            parent: posterSmallTitleBox
            readonly property real pixelSize: 19
            x: 0; y: Math.round((posterSmallTitleBox.height - pixelSize * 1.2) / 2)
            width: 1; height: 1
        }

        // =====================================================================
        // LAYER E: EXPANDED EXPRESSIVE POSTER CANVAS (CENTRAL REGION)
        // Sits directly below the elevated arc cut (top = 0.88 * W + 8px).
        // Uses FULL width (redundant right controls pill removed as requested).
        // Massive ~320px vertical breathing room!
        // Hosts:
        // 1. Interlude countdown 3-dots
        // 2. Kinetic Expressive Lyrics with auto-fitting font scale & dual-phase exit
        // 3. Expressive Title poster fallback
        // =====================================================================
        Item {
            id: expressiveCanvas
            anchors.top: parent.top
            // the lyrics start where the cover is mostly faded out
            anchors.topMargin: Math.round(root.coverTop + root.coverDrop + circleCover.height * root.coverLyricsAt)
            anchors.bottom: posterCredits.top
            anchors.bottomMargin: 12
            anchors.left: parent.left
            anchors.leftMargin: 24
            anchors.right: parent.right
            anchors.rightMargin: 24
            z: 5
            clip: false

            // -----------------------------------------------------------------
            // STATE 1: THREE-DOT INTERLUDE PAGER
            // Shows when counting down instrumental breaks or before singing
            // -----------------------------------------------------------------
            Item {
                id: interludeDotsBox
                anchors.fill: parent
                readonly property bool shouldShow: root.activeLyrics && root.activeLyrics.length > 0 && visibleLinesModel.count === 0 && root.titleFound > 0.999
                opacity: shouldShow ? 1.0 : 0.0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    spacing: 10

                    Repeater {
                        model: 3
                        Rectangle {
                            id: dotItem
                            required property int index
                            width: 10
                            height: 10
                            radius: 5
                            color: "#ffffff"

                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                running: interludeDotsBox.visible && root.isPanelRenderable
                                PauseAnimation { duration: dotItem.index * 180 }
                                NumberAnimation { from: 0.20; to: 0.95; duration: 420; easing.type: Easing.InOutQuad }
                                NumberAnimation { from: 0.95; to: 0.20; duration: 420; easing.type: Easing.InOutQuad }
                                PauseAnimation { duration: (2 - dotItem.index) * 180 }
                            }
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // STATE 2: EXPRESSIVE LYRICS ENGINE (MOCHY TIMETABLE)
            // One delegate per line on screen. Each word comes in staggered
            // (fade, rise, un-blur, zoom 0.94 -> 1) and leaves the same way
            // (fade, rise, zoom up, blur). A line below an overlapping line is
            // pushed down by it, then glides up as that line flies off.
            // -----------------------------------------------------------------
            Item {
                id: expressiveLyricsBox
                anchors.fill: parent
                visible: root.hasSyncedLyrics && opacity > 0.001
                // PosterText: the lyrics come up as the big title leaves
                opacity: root.swapFade * Math.max(0.0, Math.min(1.0, (root.titleFound - 0.25) / 0.75))

                Item {
                    id: linesStackContainer
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 16
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8

                    Repeater {
                        id: lineRepeater
                        model: visibleLinesModel

                        delegate: Item {
                            id: lineItem
                            required property int index
                            required property int lineIdx

                            readonly property var sch: root.lyricSchedule
                            readonly property bool validLine: lineIdx >= 0 && lineIdx < sch.count
                            readonly property var lineWords: validLine ? sch.words[lineIdx] : []
                            readonly property var lineScales: validLine ? sch.scales[lineIdx] : []
                            readonly property real baseFont: validLine ? sch.fonts[lineIdx] : 26
                            readonly property real exitAt: validLine ? sch.exit[lineIdx] : -1
                            readonly property bool overlapsNext: validLine && sch.overlaps[lineIdx]

                            // A line that lands late (a seek, the panel opening) still comes in
                            property real bornAt: 0.0
                            readonly property real enterAt: {
                                var planned = validLine ? sch.enter[lineIdx] : 0.0;
                                return (bornAt - planned > 0.25) ? bornAt : planned;
                            }
                            Component.onCompleted: bornAt = root.animClock

                            readonly property real t: root.effectiveLyricTime
                            readonly property real liftPx: baseFont

                            function enterOf(order) {
                                return root.easeOutCubic((t - enterAt - order * root.kEnterStagger) / root.kEnterDur);
                            }
                            function exitOf(order) {
                                if (exitAt < 0) return 0.0;
                                return root.smoothstep((t - exitAt - order * root.kExitStagger) / root.kExitDur);
                            }

                            // Overlapping lines above hold this one down, then let it glide up
                            readonly property real pushY: {
                                var y = 0.0;
                                var n = lineRepeater.count;
                                for (var k = 0; k < index && k < n; ++k) {
                                    var above = lineRepeater.itemAt(k);
                                    if (!above || !above.overlapsNext || above.exitAt < 0) continue;
                                    var hold = 1.0 - root.smootherstep((t - above.exitAt) / root.kExitDur);
                                    y += (above.height + above.baseFont * 0.28) * hold;
                                }
                                return y;
                            }

                            // Whole-line blur for the entrance and exit (one layer, only while moving)
                            readonly property real lineBlurPx: {
                                var mid = Math.max(0, Math.floor(lineWords.length / 2));
                                return (1.0 - enterOf(mid)) * 10.0 + exitOf(mid) * 12.0;
                            }

                            width: linesStackContainer.width
                            height: lineFlow.height
                            y: pushY
                            z: 10 - index

                            // Kept on for the line's whole life: toggling a layer mid-flight rebuilds it and hitches a frame
                            layer.enabled: root.isPanelRenderable
                            layer.effect: MultiEffect {
                                blurEnabled: true
                                blur: Math.min(1.0, lineItem.lineBlurPx / 16.0)
                                blurMax: 16
                                autoPaddingEnabled: true
                            }

                            // Sequential reading head for this line's words
                            readonly property int activeWordIndex: {
                                var ws = lineWords;
                                if (!ws || ws.length === 0) return -1;
                                var tt = t;
                                for (var i = 0; i < ws.length; i++) {
                                    var w = ws[i];
                                    if (tt < w.start) return i - 1;
                                    if (tt < w.end) return i;
                                }
                                return ws.length;
                            }

                            Flow {
                                id: lineFlow
                                width: parent.width
                                spacing: 8

                                FontMetrics {
                                    id: baseFontMetrics
                                    font.family: Theme.fontFamily
                                    font.pixelSize: lineItem.baseFont
                                    font.bold: Font.DemiBold
                                }

                                readonly property real maxRowHeight: Math.round(lineItem.baseFont * 1.55 * 1.42)
                                readonly property real baselineY: Math.round(lineItem.baseFont * 1.55 * 1.05)

                                Repeater {
                                    model: lineItem.lineWords

                                    delegate: Item {
                                        id: wordCell
                                        required property int index
                                        required property var modelData

                                        readonly property string wordText: modelData ? String(modelData.text || "") : ""
                                        readonly property real peakScale: (lineItem.lineScales && index < lineItem.lineScales.length) ? lineItem.lineScales[index] : 1.0
                                        readonly property bool isShoutWord: peakScale > 1.15
                                        property real shoutProgress: 0.0

                                        // Entrance / exit motion (Mochy GraphicsLayerScope.motion)
                                        readonly property real enterE: lineItem.enterOf(index)
                                        readonly property real exitO: lineItem.exitOf(index)
                                        readonly property real motionY: (1.0 - enterE) * lineItem.liftPx * 0.55 - exitO * exitO * lineItem.liftPx * 0.9
                                        readonly property real motionZoom: (0.94 + 0.06 * enterE) * (1.0 + 0.08 * exitO)
                                        opacity: Math.max(0.0, Math.min(1.0, enterE * (1.0 - exitO)))

                                        // The whole line zooms about its left edge and middle, so words keep their places
                                        transform: [
                                            Scale {
                                                xScale: wordCell.motionZoom
                                                yScale: wordCell.motionZoom
                                                origin.x: -wordCell.x
                                                origin.y: lineFlow.height / 2 - wordCell.y
                                            },
                                            Translate { y: wordCell.motionY }
                                        ]

                                        // Monotonic shout growth: no bounce, never shrinks back
                                        NumberAnimation {
                                            id: shoutAnim
                                            target: wordCell
                                            property: "shoutProgress"
                                            to: 1.0
                                            duration: Math.max(450, Math.min(750, Math.round(wordCell.wDur * 1000 * 1.15)))
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: [0.12, 0.88, 0.24, 1.0]
                                        }

                                        function checkAndTriggerShout() {
                                            if (isShoutWord && isSinging && shoutProgress < 0.99 && !shoutAnim.running) {
                                                shoutAnim.restart();
                                            }
                                        }
                                        onIsSingingChanged: checkAndTriggerShout()
                                        onIsShoutWordChanged: checkAndTriggerShout()
                                        onIsPastChanged: {
                                            if (isPast && isShoutWord && !shoutAnim.running) shoutProgress = 1.0;
                                        }
                                        Component.onCompleted: {
                                            if (isShoutWord) {
                                                if (isPast) shoutProgress = 1.0;
                                                else if (isSinging) checkAndTriggerShout();
                                            }
                                        }

                                        readonly property real wStart: (modelData && modelData.start !== undefined) ? Number(modelData.start) : 0.0
                                        readonly property real wEnd: (modelData && modelData.end !== undefined) ? Number(modelData.end) : (wStart + 0.1)
                                        readonly property real wDur: Math.max(0.05, (modelData && modelData.duration !== undefined) ? Number(modelData.duration) : (wEnd - wStart))
                                        readonly property bool isHeld: (modelData && modelData.isHeld !== undefined) ? !!modelData.isHeld : (wDur >= 0.85)

                                        // Strict monotonic reading head: never grows before the singer gets there
                                        readonly property bool isPast: (lineItem.activeWordIndex >= 0) && (index < lineItem.activeWordIndex || (index === lineItem.activeWordIndex && lineItem.t >= wEnd))
                                        readonly property bool isSinging: (lineItem.activeWordIndex >= 0) && (index === lineItem.activeWordIndex) && (lineItem.t >= wStart) && (lineItem.t < wEnd)
                                        readonly property real wordProgress: isPast ? 1.0 : (isSinging ? Math.max(0.0, Math.min(1.0, (lineItem.t - wStart) / wDur)) : 0.0)

                                        // The clock is already per-frame smooth, so the sweep reads it directly
                                        readonly property real smoothProg: wordProgress
                                        // Bloom head trails the sweep by 120ms (comet glow)
                                        readonly property real bloomProg: isSinging ? Math.max(0.0, Math.min(1.0, (lineItem.t - 0.12 - wStart) / wDur)) : 0.0
                                        readonly property real bloomLagDelta: wordCell.isSinging ? (wordCell.smoothProg - wordCell.bloomProg) : 0.0

                                        function cubicBezier(p0, p1, p2, p3, x) {
                                            var u = 1 - x;
                                            return 3 * u * u * x * p1 + 3 * u * x * x * p2 + x * x * x;
                                        }
                                        function empEasing(x) {
                                            if (x < 0.5) return cubicBezier(0.0, 0.3, 0.25, 1.0, x * 2.0);
                                            return 1.0 - cubicBezier(0.0, 0.5, 0.6, 1.0, (x - 0.5) * 2.0);
                                        }

                                        readonly property real yCurve: isSinging ? (isHeld ? empEasing(smoothProg) : Math.sin(Math.PI * smoothProg)) : 0.0
                                        readonly property real waveScale: 1.0 + (isHeld ? 0.045 : 0.010) * yCurve
                                        readonly property real effectiveScale: isShoutWord ? (1.0 + (peakScale - 1.0) * shoutProgress) : peakScale

                                        width: Math.round(charRow.implicitWidth * effectiveScale)
                                        height: lineFlow.maxRowHeight

                                        Item {
                                            id: innerTransformWrap
                                            x: Math.round((parent.width - charRow.implicitWidth) / 2)
                                            y: Math.round(lineFlow.baselineY - baseFontMetrics.ascent)
                                            width: charRow.implicitWidth
                                            height: charRow.implicitHeight

                                            transform: [
                                                Scale {
                                                    xScale: wordCell.effectiveScale
                                                    yScale: wordCell.effectiveScale
                                                    origin.x: charRow.implicitWidth / 2
                                                    origin.y: baseFontMetrics.ascent
                                                }
                                            ]

                                            Loader {
                                                id: glowLoader
                                                anchors.fill: charRow
                                                active: root.isPanelRenderable && wordCell.isSinging
                                                visible: active
                                                z: 0
                                                sourceComponent: Component {
                                                    MultiEffect {
                                                        source: charRow
                                                        anchors.fill: parent
                                                        shadowEnabled: true
                                                        shadowColor: (root.accentColor && root.accentColor !== "") ? root.accentColor : "#ffffff"
                                                        shadowBlur: 0.95
                                                        shadowOpacity: wordCell.isSinging ? (0.92 * Math.sin(Math.PI * wordCell.smoothProg)) : 0.0
                                                        shadowHorizontalOffset: -wordCell.bloomLagDelta * charRow.width * 0.45
                                                        shadowVerticalOffset: 0
                                                        shadowScale: 1.12
                                                        visible: shadowOpacity > 0.01
                                                    }
                                                }
                                            }

                                            Row {
                                                id: charRow
                                                spacing: 0
                                                z: 1

                                                Repeater {
                                                    model: (wordCell.wordText || "").split("")

                                                    delegate: Item {
                                                        id: charItem
                                                        required property var modelData
                                                        required property int index
                                                        readonly property string ch: modelData
                                                        readonly property int charCount: Math.max(1, (wordCell.wordText || "").length)
                                                        readonly property real charFrom: index / charCount
                                                        readonly property real charTo: (index + 1) / charCount
                                                        readonly property real charProgress: wordCell.isPast ? 1.0 :
                                                            (wordCell.isSinging ? Math.max(0.0, Math.min(1.0, (wordCell.smoothProg - charFrom) / Math.max(0.001, charTo - charFrom))) : 0.0)

                                                        // Persistent rolling lift once a letter is sung
                                                        property real liftProgress: (charProgress > 0.0 || wordCell.isPast) ? 1.0 : 0.0
                                                        Behavior on liftProgress {
                                                            NumberAnimation { duration: 750; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0.0, 0.2, 1.0] }
                                                        }
                                                        readonly property real hermiteLift: {
                                                            var w = Math.max(0.0, Math.min(1.0, liftProgress));
                                                            return w * w * (3.0 - 2.0 * w);
                                                        }

                                                        width: charText.implicitWidth
                                                        height: charText.implicitHeight

                                                        transform: [
                                                            Translate { y: -charItem.hermiteLift * 2.5 },
                                                            Scale {
                                                                xScale: wordCell.isShoutWord ? 1.0 : (1.0 + (wordCell.waveScale - 1.0) * 0.5)
                                                                yScale: wordCell.isShoutWord ? 1.0 : (1.0 + (wordCell.isHeld ? 0.06 : 0.04) * wordCell.yCurve)
                                                                origin.x: charItem.width / 2
                                                                origin.y: charItem.height
                                                            }
                                                        ]

                                                        Text {
                                                            id: charText
                                                            anchors.centerIn: parent
                                                            text: charItem.ch
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: lineItem.baseFont
                                                            font.bold: wordCell.effectiveScale > 1.2 ? true : Font.DemiBold
                                                            color: {
                                                                if (wordCell.isPast || charItem.charProgress >= 1.0) return "#ffffff";
                                                                if (charItem.charProgress <= 0.0) return Qt.rgba(1.0, 1.0, 1.0, 0.38);
                                                                return Qt.rgba(1.0, 1.0, 1.0, 0.38 + 0.62 * charItem.charProgress);
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // STATE 3: POSTER TITLE (Mochy ExpressiveTitle)
            // The song's title as a poster: one short word shouted at 1.55x, long words
            // stepped down, tight lines, words rising in one after another. It is the
            // big words while there are no lyrics; once they are found it slides into
            // the small title in the credits below.
            // -----------------------------------------------------------------
            Item {
                id: expressiveTitleBox
                anchors.fill: parent
                visible: root.titleFound < 0.999 && root.shownTitle !== ""
                opacity: root.swapFade

                readonly property var words: root.shownTitle.split(" ").filter(w => w.length > 0)
                readonly property var scales: {
                    var ws = words, emph = -1, minLen = 999;
                    for (var i = 0; i < ws.length; ++i)
                        if (ws[i].length >= 3 && ws[i].length < minLen) { minLen = ws[i].length; emph = i; }
                    var out = [];
                    for (var j = 0; j < ws.length; ++j) {
                        var n = ws[j].length;
                        out.push(j === emph && ws.length > 1 ? 1.55 : (n >= 11 ? 0.74 : (n >= 9 ? 0.86 : 1.0)));
                    }
                    return out;
                }
                readonly property real baseSize: 40
                readonly property real spacingRatio: 0.24
                // Space it may fill: above the "finding lyrics" note
                readonly property real fitHeight: Math.max(60, height - (statusRow.visible ? statusRow.height + 14 : 0))

                // Measured once at 100 px and scaled: a side-effect-free width for any size
                FontMetrics { id: boldMetrics; font.family: Theme.fontFamily; font.pixelSize: 100; font.weight: Font.Bold }
                FontMetrics { id: blackMetrics; font.family: Theme.fontFamily; font.pixelSize: 100; font.weight: Font.Black }
                function wordWidth(word, px, scale) {
                    var m = scale > 1 ? blackMetrics : boldMetrics;
                    var size = px * scale;
                    // letterSpacing -0.035em per glyph, as drawn
                    return (m.advanceWidth(word) / 100 - 0.035 * word.length) * size;
                }
                // fitTitle: long titles start smaller, then step down until no word runs past the
                // width and the wrapped rows fit the height
                function fits(px) {
                    var gap = px * spacingRatio, rowW = 0, rowH = 0, total = 0;
                    for (var i = 0; i < words.length; ++i) {
                        var w = wordWidth(words[i], px, scales[i]);
                        if (w > width) return false;
                        if (rowW > 0 && rowW + gap + w > width) { total += rowH; rowW = 0; rowH = 0; }
                        rowW += (rowW > 0 ? gap : 0) + w;
                        rowH = Math.max(rowH, px * scales[i] * 0.96);
                    }
                    return total + rowH <= fitHeight;
                }
                readonly property real fitted: {
                    if (width <= 0 || words.length === 0) return baseSize;
                    var len = Math.max(1, root.shownTitle.length);
                    var px = baseSize * Math.sqrt(Math.max(0.52, Math.min(1.0, 14 / len)));
                    for (var k = 0; k < 8 && !fits(px); ++k) px *= 0.9;
                    return px;
                }

                Item {
                    id: bigTitle
                    width: parent.width
                    height: titleFlow.implicitHeight
                    // Slide from here to the small title's place, shrinking from the top-left corner
                    readonly property point dest: {
                        root.titleFound; posterSmallTitle.y; expressiveCanvas.height;
                        return posterSmallTitle.mapToItem(expressiveTitleBox, 0, 0);
                    }
                    readonly property real f: root.titleFound
                    transform: [
                        Scale { xScale: 1 + (posterSmallTitle.pixelSize / expressiveTitleBox.fitted - 1) * bigTitle.f; yScale: xScale }
                    ]
                    x: bigTitle.dest.x * f
                    y: bigTitle.dest.y * f
                    // it becomes the small title in the last part of the slide
                    opacity: 1 - Math.max(0, Math.min(1, (f - 0.6) / 0.35))

                    // The whole title softens in and out of focus as a lyric line does (one layer)
                    readonly property real blurPx: {
                        var mid = Math.floor(Math.max(0, expressiveTitleBox.words.length - 1) / 2);
                        return (1.0 - root.easeOutCubic((root.titleClock - mid * root.kEnterStagger) / root.kEnterDur)) * 10.0;
                    }
                    layer.enabled: root.isPanelRenderable
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: Math.min(1.0, bigTitle.blurPx / 16.0)
                        blurMax: 16
                        autoPaddingEnabled: true
                    }

                    Flow {
                        id: titleFlow
                        width: parent.width
                        spacing: expressiveTitleBox.fitted * expressiveTitleBox.spacingRatio

                        Repeater {
                            model: expressiveTitleBox.words
                            // Each word comes in exactly like a lyric word: rises, fades and zooms
                            // from 0.94 with the same stagger and curve. The shout word arrives at
                            // normal size and only swells to its full size once the title has landed.
                            delegate: Item {
                                id: titleWord
                                required property string modelData
                                required property int index
                                readonly property real peak: expressiveTitleBox.scales[index] || 1.0
                                readonly property bool isShout: peak > 1.15
                                property real shoutProgress: 0.0
                                // set at peak size, drawn scaled down: crisp at every step of the swell
                                readonly property real drawScale: isShout ? (1.0 + (peak - 1.0) * shoutProgress) / peak : 1.0

                                readonly property real enterE: root.easeOutCubic((root.titleClock - index * root.kEnterStagger) / root.kEnterDur)
                                readonly property real motionZoom: 0.94 + 0.06 * enterE

                                // rows align on the bottom like FlowRow(itemVerticalAlignment = Bottom)
                                width: Math.round(wordText.implicitWidth * drawScale)
                                height: expressiveTitleBox.fitted * 1.55 * 0.96
                                opacity: Math.max(0.0, Math.min(1.0, enterE))
                                transform: [
                                    Scale {
                                        xScale: titleWord.motionZoom
                                        yScale: titleWord.motionZoom
                                        origin.x: -titleWord.x
                                        origin.y: titleFlow.height / 2 - titleWord.y
                                    },
                                    Translate { y: (1.0 - titleWord.enterE) * expressiveTitleBox.fitted * 0.55 }
                                ]

                                // the swell starts when the last word has come in, on the lyric shout curve
                                readonly property bool shoutDue: isShout
                                    && root.titleClock >= (expressiveTitleBox.words.length - 1) * root.kEnterStagger + root.kEnterDur * 0.85
                                onShoutDueChanged: {
                                    if (shoutDue) {
                                        if (shoutProgress < 0.99) shoutAnim.restart();
                                    } else {
                                        shoutAnim.stop();
                                        shoutProgress = 0.0;
                                    }
                                }
                                Component.onCompleted: if (shoutDue) shoutProgress = 1.0
                                NumberAnimation {
                                    id: shoutAnim
                                    target: titleWord; property: "shoutProgress"; to: 1.0; duration: 650
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.12, 0.88, 0.24, 1.0, 1.0, 1.0]
                                }

                                Text {
                                    id: wordText
                                    anchors.left: parent.left
                                    anchors.bottom: parent.bottom
                                    text: titleWord.modelData
                                    color: root.mochyInk
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Math.round(expressiveTitleBox.fitted * titleWord.peak)
                                    font.weight: titleWord.isShout ? Font.Black : Font.Bold
                                    font.letterSpacing: -0.035 * Math.round(expressiveTitleBox.fitted * titleWord.peak)
                                    transform: Scale {
                                        xScale: titleWord.drawScale
                                        yScale: titleWord.drawScale
                                        origin.x: 0
                                        origin.y: wordText.height
                                    }
                                }
                            }
                        }
                    }
                }

                // Material 3 empty states under the title (as in the Swiftify reference): while
                // searching, the morphing shape loader over a quiet line; with nothing found, the
                // shared EmptyState, a lyrics symbol on a tonal puffy badge that springs in.
                Item {
                    id: statusRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    // right under the title as first set, so it never lands on the credits
                    y: titleFlow.implicitHeight + 28
                    height: root.isLoadingLyrics ? loadingCol.implicitHeight : noLyricsState.implicitHeight
                    // Found lyrics hide it at once, even while the title is still held big; "no lyrics"
                    // waits until the search has really ended (see lyricsMissingConfirmed)
                    opacity: (root.hasSyncedLyrics || (!root.isLoadingLyrics && !root.lyricsMissingConfirmed))
                        ? 0.0 : Math.max(0, 1 - root.titleFound * 3)
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    visible: opacity > 0.01

                    Column {
                        id: loadingCol
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 14
                        visible: root.isLoadingLyrics

                        ShapeLoader {
                            anchors.horizontalCenter: parent.horizontalCenter
                            size: 36
                            running: loadingCol.visible && statusRow.visible
                            color: root.accentColor
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: I18n.tr("Đang tìm lời bài hát…", "Finding lyrics…")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            color: root.mochyInkSoft
                        }
                    }

                    EmptyState {
                        id: noLyricsState
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(parent.width, 320)
                        visible: !root.isLoadingLyrics
                        shape: "puffy"
                        badgeSize: 72
                        icon: "../assets/icons/material/ms-lyrics-fill.svg"
                        accentColor: root.accentColor
                        title: I18n.tr("Chưa có lời bài hát", "Lyrics unavailable")
                        description: I18n.tr("Bài này chưa có lời chạy theo nhạc", "This song has no synced lyrics yet")
                    }
                }
            }
        }
    }

        // =====================================================================
        // VIEW 2: QUEUE MODE ("Playing Next" List + Current Track Header)
        // =====================================================================
        Item {
            id: queueView
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: root.activeTab === "queue" ? 1.0 : 0.0
            scale: root.activeTab === "queue" ? 1.0 : 0.94
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            // No header and no panel behind it: the songs float on the wallpaper as one leaning
            // column, pinned at its right edge with the left edge receding toward the middle of
            // the window. The exact lean comes from upNextMatrix().
            Item {
                id: queueStage
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: root.cardLook ? root.headerSpace : 28
                anchors.leftMargin: 20
                anchors.rightMargin: 18
                anchors.bottomMargin: root.dockSpace + 8

                // Leans only when the Settings switch is on; straight otherwise
                transform: Matrix4x4 {
                    matrix: !root.upNextTilt ? Qt.matrix4x4() : root.upNextMatrix(queueStage.width, queueStage.height)
                }

                ListView {
                    id: queueListView
                    anchors.fill: parent
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.upNextTracks

                    // The song playing now heads the column, lifted off the page as an accent card
                    header: Item {
                        width: queueListView.width
                        height: root.currentTrack !== null ? 78 : 0
                        visible: root.currentTrack !== null

                        Item {
                            id: liftedCard
                            anchors.left: parent.left
                            anchors.right: parent.right
                            // Room on the far side for the card to grow into without being clipped
                            anchors.leftMargin: 32
                            anchors.top: parent.top
                            anchors.topMargin: 6
                            height: 60
                            // Wider than the rows and nearer the viewer: grows from the pinned edge
                            transformOrigin: Item.Right
                            scale: curCardHover.hovered ? 1.08 : 1.06
                            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutExpo } }

                            readonly property bool lightAccent: (0.2126 * root.accentColor.r + 0.7152 * root.accentColor.g + 0.0722 * root.accentColor.b) > 0.55
                            readonly property color inkColor: lightAccent ? "#121212" : "#ffffff"
                            readonly property color inkSoft: lightAccent ? Qt.rgba(0.07, 0.07, 0.07, 0.72) : Qt.rgba(1, 1, 1, 0.78)

                            // Contact shadow: offset down and soft, so the card reads as raised
                            Rectangle {
                                anchors.fill: parent
                                anchors.topMargin: 8
                                anchors.bottomMargin: -8
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                radius: 14
                                color: Qt.rgba(0, 0, 0, 0.45)
                                layer.enabled: !root.liteMode && root.activeTab === "queue"
                                layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 24 }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: 14
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.30)
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.78) }
                                    GradientStop { position: 1.0; color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.94) }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 12
                                z: 2

                                Item {
                                    Layout.preferredWidth: 42
                                    Layout.preferredHeight: 42

                                    RoundedImage {
                                        anchors.fill: parent
                                        radius: 8
                                        source: root.coverImageUrl
                                        fillMode: Image.PreserveAspectCrop
                                        fallbackIcon: "../assets/icons/folder-music-symbolic.svg"
                                        fallbackIconSize: 18
                                    }

                                    // Live bars over the cover while the song plays
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 8
                                        color: Qt.rgba(0, 0, 0, 0.45)
                                        visible: root.isPlaying

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 2.5
                                            Repeater {
                                                model: 3
                                                Rectangle {
                                                    required property int index
                                                    width: 3
                                                    height: 8 + (index % 2) * 6
                                                    radius: 1.5
                                                    color: "#ffffff"
                                                    SequentialAnimation on height {
                                                        running: root.isPlaying && root.visible && root.activeTab === "queue" && !root.liteMode
                                                        loops: Animation.Infinite
                                                        NumberAnimation { from: 5; to: 16; duration: 280 + index * 110; easing.type: Easing.InOutQuad }
                                                        NumberAnimation { from: 16; to: 5; duration: 280 + index * 110; easing.type: Easing.InOutQuad }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.currentTrack ? (root.currentTrack.title || root.currentTrack.name || I18n.tr("Bài hát Nutsty", "Nutsty Track")) : ""
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        color: liftedCard.inkColor
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.currentTrack ? (root.currentTrack.artist || root.currentTrack.artists || I18n.tr("Nghệ sĩ chưa rõ", "Unknown Artist")) : ""
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: liftedCard.inkSoft
                                        elide: Text.ElideRight
                                    }
                                }

                                Item {
                                    Layout.preferredWidth: 30
                                    Layout.preferredHeight: 30
                                    Layout.alignment: Qt.AlignVCenter
                                    z: 10

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 8
                                        color: curMoreH.hovered ? Qt.rgba(1, 1, 1, 0.22) : "transparent"
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }

                                    AppIcon {
                                        anchors.centerIn: parent
                                        source: "../assets/icons/view-more-symbolic.svg"
                                        iconSize: 18
                                        color: liftedCard.inkColor
                                    }

                                    HoverHandler { id: curMoreH }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onClicked: mouse => {
                                            mouse.accepted = true;
                                            var pt = mapToItem(null, mouse.x, mouse.y);
                                            root.trackContextMenuRequested(root.currentTrack, pt.x, pt.y);
                                        }
                                    }
                                }
                            }

                            HoverHandler { id: curCardHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                z: 1
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) {
                                        var pt = mapToItem(null, mouse.x, mouse.y);
                                        root.trackContextMenuRequested(root.currentTrack, pt.x, pt.y);
                                    } else {
                                        root.openDetailsRequested();
                                    }
                                }
                            }
                        }
                    }

                    delegate: Item {
                        id: queueItem
                        required property int index
                        required property var modelData

                        width: queueListView.width
                        height: 50
                        z: rowHover.hovered ? 5 : 0

                        // A hovered row steps a little out of the page, toward the pinned edge.
                        // Inset on the far side so the grown row stays inside the list's clip.
                        Item {
                            id: rowBody
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            transformOrigin: Item.Right
                            scale: rowHover.hovered ? 1.035 : 1.0
                            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutExpo } }

                            Rectangle {
                                anchors.fill: parent
                                radius: 12
                                color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, rowHover.hovered ? 0.22 : 0.0)
                                border.width: 1
                                border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, rowHover.hovered ? 0.45 : 0.0)
                                Behavior on color { ColorAnimation { duration: 160 } }
                                Behavior on border.color { ColorAnimation { duration: 160 } }
                            }

                            RowLayout {
                                // Above the row-wide play MouseArea (z: 1) so the three-dot button gets its click
                                z: 2
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 12

                                Item {
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36

                                    RoundedImage {
                                        anchors.fill: parent
                                        radius: 6
                                        source: {
                                            var trk = queueItem.modelData;
                                            if (!trk) return "";
                                            var s = trk.image || trk.artUrl || trk.cover || trk.thumbnail || "";
                                            if (!s && trk.videoId) {
                                                s = "https://i.ytimg.com/vi/" + trk.videoId + "/hqdefault.jpg";
                                            }
                                            if (s.indexOf("i.ytimg.com") !== -1) s = s.split("?")[0];
                                            return (s.startsWith("/") && !s.startsWith("file://")) ? ("file://" + s) : s;
                                        }
                                        fillMode: Image.PreserveAspectCrop
                                        fallbackIcon: "../assets/icons/media-optical-audio-symbolic.svg"
                                        fallbackIconSize: 16
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        Layout.fillWidth: true
                                        text: queueItem.modelData ? (queueItem.modelData.title || queueItem.modelData.name || I18n.tr("Bài hát", "Track")) : ""
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        color: "#ffffff"
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: queueItem.modelData ? (queueItem.modelData.artist || queueItem.modelData.artists || I18n.tr("Nghệ sĩ chưa rõ", "Unknown Artist")) : ""
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Qt.rgba(1, 1, 1, 0.74)
                                        elide: Text.ElideRight
                                    }
                                }

                                // Menu button: hidden until the row is pointed at; right-click opens it too
                                Item {
                                    Layout.preferredWidth: 30
                                    Layout.preferredHeight: 30
                                    Layout.alignment: Qt.AlignVCenter
                                    z: 10
                                    opacity: rowHover.hovered ? 1.0 : 0.0
                                    enabled: rowHover.hovered
                                    Behavior on opacity { NumberAnimation { duration: 140 } }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 8
                                        color: moreHover.hovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45) : "transparent"
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }

                                    AppIcon {
                                        anchors.centerIn: parent
                                        source: "../assets/icons/view-more-symbolic.svg"
                                        iconSize: 18
                                        color: "#ffffff"
                                    }

                                    HoverHandler { id: moreHover }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onClicked: mouse => {
                                            mouse.accepted = true;
                                            var pt = mapToItem(null, mouse.x, mouse.y);
                                            root.trackContextMenuRequested(queueItem.modelData, pt.x, pt.y);
                                        }
                                    }
                                }
                            }

                            HoverHandler { id: rowHover }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                z: 1
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) {
                                        var pt = mapToItem(null, mouse.x, mouse.y);
                                        root.trackContextMenuRequested(queueItem.modelData, pt.x, pt.y);
                                    } else {
                                        root.trackPlayRequested(queueItem.modelData, queueItem.index);
                                    }
                                }
                            }
                        }
                    }
                }

                ScrollEdgeFade {
                    flickable: queueListView
                    when: root.isPanelRenderable && root.activeTab === "queue"
                }
            }

            // Empty State
            Item {
                anchors.centerIn: parent
                width: parent.width - 40
                visible: root.upNextTracks.length === 0 && (root.currentTrack === null)

                EmptyState {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 32, 340)
                    icon: "../assets/icons/material/ms-queue_music.svg"
                    shape: "clover"
                    accentColor: root.accentColor
                    title: I18n.pick("queue.empty", ["Hàng đợi trống", "Chưa ai xếp hàng cả", "Vắng như chợ chiều", "Hàng đợi đang ngồi chơi", "Thêm bài đi, kẻo nhạc hết giữa chừng", "Trống trơn, xếp vài bài vào nhé", "Hàng đợi khum có ai"], ["Queue is empty", "Nobody's in line", "Empty as a market at closing time", "The queue is taking a break", "Add songs before the music runs out", "All empty, line up a few songs", "Not a soul in the queue"])
                    description: I18n.tr("Chọn bài hát để bắt đầu danh sách phát", "Play a track to start the queue")
                }
            }
        }

        // =====================================================================
        // VIEW 3: YOUTUBE COMMENTS
        // =====================================================================
        MochyCommentsView {
            id: commentsView
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: root.activeTab === "comments" ? 1.0 : 0.0
            scale: root.activeTab === "comments" ? 1.0 : 0.94
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            videoId: root.currentTrack && root.currentTrack.videoId ? root.currentTrack.videoId : ""
            accentColor: root.accentColor
            isLoggedIn: root.isLoggedIn
            active: root.activeTab === "comments" && root.isPanelRenderable
            bottomInset: root.dockSpace
            showHeader: !root.cardLook
            topInset: root.headerSpace
            sideInset: root.dockInset
            cornerRadius: root.panelRadius - root.dockInset
            onCloseRequested: root.closeRequested()
        }

        // Action row lives at panelContainer level so it stays visible on both tabs;
        // bottomDock inside lyricsView only reserves its space for the lyric canvas.
        Item {
            id: actionDock
            visible: !root.cardLook
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: root.dockInset
            anchors.rightMargin: root.dockInset
            anchors.bottomMargin: root.dockInset
            height: actionRow.implicitHeight
            z: 30

            NowPlayingActionRow {
                id: actionRow
                anchors.fill: parent
                activeTab: root.activeTab
                accentColor: root.accentColor
                onLyricsClicked: root.tabRequested("lyrics")
                onCommentsClicked: root.tabRequested(root.activeTab === "comments" ? "lyrics" : "comments")
                onQueueClicked: root.tabRequested(root.activeTab === "queue" ? "lyrics" : "queue")
            }
        }
    }
}
