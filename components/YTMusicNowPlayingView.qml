import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Io
import "."
import "lyric_lines.js" as LyricLines
import "playback_engine.js" as PlaybackEngine
import "quality_label.js" as QualityLabel

Item {
    id: root

    property var track: null
    property real currentTime: 0.0
    property real totalDuration: 1.0
    property bool isPlaying: false
    property bool isLoadingAudio: false
    // True while AutoMix is blending two songs (drives the "Cooking" labels here and on the player bar)
    readonly property bool autoMixing: autoMix.mixing
    // Maximized window: the collapse button lives in the frame's left notch instead
    property bool chromeInNotch: false
    // the header's center notch slot: in notch mode the mode switcher lives there instead of
    // floating top-right (liner keeps its lyric controls in the notch the same way)
    property Item notchHost: null
    property bool isShuffle: false
    property string repeatMode: "off"
    property real volume: 100
    property var queueTracks: []
    property string playingPlaylistTitle: I18n.tr("Hàng đợi", "Queue")
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent
    property Item backgroundSourceItem: null
    property string appDir: (typeof win !== "undefined" && win && win.appDir) ? win.appDir : (Quickshell.env("NUTSTY_APP_DIR") || (Quickshell.env("HOME") + "/Applications/FrostifyLocal"))

    // Mood chips are not shown in the Swiftify-style queue panel, so their network fetch is off
    readonly property bool moodChipsEnabled: false
    property string activeTab: "artwork" // "artwork" | "lyrics" | "up_next" | "sleep"
    readonly property bool isArtworkMode: activeTab === "artwork"
    // Panel currently rendered on the right; lags activeTab during the swap cross-fade
    property string shownPanel: "lyrics"
    property string _prevTab: "artwork"

    // Swiftify-like panel motion: open = slide in from the right + fade, close = slide out + fade,
    // lyrics <-> up next = quick fade out, swap, slower decelerating fade in.
    ParallelAnimation {
        id: panelOpenAnim
        NumberAnimation { target: rightPanel; property: "shift"; to: 0; duration: 320; easing.type: Easing.OutCubic }
        NumberAnimation { target: rightPanel; property: "opacity"; to: 1; duration: 320; easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: panelCloseAnim
        NumberAnimation { target: rightPanel; property: "shift"; to: 1; duration: 260; easing.type: Easing.OutQuad }
        NumberAnimation { target: rightPanel; property: "opacity"; to: 0; duration: 260; easing.type: Easing.OutQuad }
    }
    SequentialAnimation {
        id: panelSwapAnim
        property string nextPanel: "lyrics"
        NumberAnimation { target: rightPanel; property: "opacity"; to: 0; duration: 160; easing.type: Easing.OutQuad }
        ScriptAction { script: root.shownPanel = panelSwapAnim.nextPanel }
        ParallelAnimation {
            NumberAnimation { target: rightPanel; property: "opacity"; to: 1; duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] }
            NumberAnimation { target: rightPanel; property: "shift"; to: 0; duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] }
        }
    }

    function runPanelTransition(prev, next) {
        panelOpenAnim.stop();
        panelCloseAnim.stop();
        panelSwapAnim.stop();
        if (next === "artwork") {
            panelCloseAnim.start();
        } else if (prev === "artwork" || rightPanel.opacity < 0.05) {
            root.shownPanel = next;
            panelOpenAnim.start();
        } else if (root.shownPanel !== next) {
            panelSwapAnim.nextPanel = next;
            panelSwapAnim.start();
        } else {
            panelOpenAnim.start();
        }
    }

    Component.onCompleted: {
        if (!root.isArtworkMode) {
            root.shownPanel = root.activeTab;
            rightPanel.shift = 0;
            rightPanel.opacity = 1;
        }
        root._prevTab = root.activeTab;
    }

    onActiveTabChanged: {
        root.runPanelTransition(root._prevTab, activeTab);
        root._prevTab = activeTab;
        if (activeTab === "lyrics") {
            root.followPlayback = true;
            userScrollTimer.stop();
            Qt.callLater(function() {
                root.recenterToCurrentLyric(false);
            });
        }
    }

    property bool followPlayback: true

    property var activeLyrics: []
    property int currentLyricIndex: -1
    property bool lyricsRomanizationEnabled: (typeof win !== "undefined" && win && win.lyricsRomanizationEnabled !== undefined) ? win.lyricsRomanizationEnabled : true
    property bool hasLyrics: false
    property bool isLoadingLyrics: false
    property var audioSpecs: null
    property string lyricsSource: ""

    readonly property bool isLyricsWordByWord: {
        if (!root.activeLyrics || root.activeLyrics.length === 0) return false;
        for (var i = 0; i < root.activeLyrics.length; ++i) {
            var l = root.activeLyrics[i];
            if (l && l.hasWords && !l.isSynthetic && l.words && l.words.length > 0 && !l.isInterlude) {
                return true;
            }
        }
        return false;
    }

    // Duet detection matching Mochy-Music: usesAgentAlignment(lines)
    // Left and right only mean something when the song really has more than one voice; untagged lines count as lead (v1), background lines don't count
    property bool hasDuetVoices: false

    function computeHasDuetVoices(lyricsList) {
        if (!lyricsList || lyricsList.length === 0) return false;
        var leadAgents = {};
        var count = 0;
        for (var i = 0; i < lyricsList.length; ++i) {
            var entry = lyricsList[i];
            if (entry && !entry.isBackground && !entry.isInterlude) {
                var ag = entry.agent || "v1";
                if (!leadAgents[ag]) {
                    leadAgents[ag] = true;
                    count++;
                }
            }
        }
        return count > 1;
    }

    onActiveLyricsChanged: {
        hasDuetVoices = computeHasDuetVoices(activeLyrics);
        root.followPlayback = true;
        userScrollTimer.stop();
        Qt.callLater(function() {
            root.recenterToCurrentLyric(false);
        });
    }

    // 1:1 Mochy-Music multi-active anchor (LyricsScreen.kt lyricAnchorIndex)
    // Walks backward from current line while an earlier singer is still singing/holding a note
    readonly property int anchorLyricIndex: {
        var cur = root.currentLyricIndex;
        if (cur <= 0 || !root.activeLyrics || cur >= root.activeLyrics.length) return cur;
        var pos = root.currentTime;
        var i = cur;
        while (i > 0) {
            var prev = i - 1;
            var prevLine = root.activeLyrics[prev];
            if (!prevLine) return i;
            var endSec = 0.0;
            if (prevLine.words && prevLine.words.length > 0) {
                var lastW = prevLine.words[prevLine.words.length - 1];
                endSec = (lastW.end !== undefined) ? Number(lastW.end) : 0.0;
            } else if (prevLine.endTime !== undefined) {
                endSec = Number(prevLine.endTime);
            }
            if (endSec <= pos) return i;
            i = prev;
        }
        return i;
    }

    onAnchorLyricIndexChanged: {
        if (root.followPlayback && !userScrollTimer.running && !lyricsView.moving && !lyricsView.dragging && !lyricsView.flicking && root.activeTab === "lyrics") {
            root.recenterToCurrentLyric(true);
        }
    }

    // Sanitize word timestamps to guarantee monotonically non-decreasing start times and positive duration
    // Shared with the desktop Apple Music preset (lyric_lines.js)
    function sanitizeWordList(wList) {
        return LyricLines.sanitizeWordList(wList);
    }

    // 1:1 Mochy-Music splitBackingVocal: separates lead text and bracketed backing vocal
    function splitBackingVocal(text, words) {
        return LyricLines.splitBackingVocal(text, words);
    }

    function formatLyricSourceName(rawSrc) {
        if (!rawSrc) return "";
        var s = String(rawSrc).trim();
        if (s.toLowerCase() === "local file" || s.toLowerCase() === "tập tin cục bộ") {
            return I18n.tr("Tập tin cục bộ", "Local File");
        }
        if (s.toLowerCase() === "cache" || s.toLowerCase() === "bộ nhớ đệm") {
            return I18n.tr("Bộ nhớ đệm", "Cached Lyrics");
        }
        return s;
    }

    readonly property string audioQualityText: root.track ? QualityLabel.formatQualityLabel(root.audioSpecs, I18n.tr) : ""

    // Lyrics credit, shown as a footer after the last lyric line (Mochy-like: it scrolls in as the song ends).
    // Audio quality moved to the middle of the progress bar (NowPlayingControls.qualityText).
    readonly property string lyricsCreditText: {
        if (!root.track || !root.hasLyrics) return "";
        var rawSrc = root.lyricsSource;
        if (!rawSrc) rawSrc = root.isLyricsWordByWord ? "Spotify" : "LRCLIB";
        var srcName = formatLyricSourceName(rawSrc);
        if (!srcName) return "";
        return root.isLyricsWordByWord
            ? I18n.tr("Lời từng từ được cung cấp bởi ", "Word-by-word lyrics provided by ") + srcName
            : I18n.tr("Lời bài hát được cung cấp bởi ", "Lyrics provided by ") + srcName;
    }


    property string currentLikeStatus: "INDIFFERENT"
    property var dislikedSongsMap: ({})

    property var moodChips: []
    property int selectedMoodIndex: 0
    property bool isLoadingMoodChips: false
    property bool isLoadingMoodQueue: false
    property string lastMoodChipsVid: ""
    property bool highResFailed: false
    property var originalAlbumQueue: []
    property string lastAlbumQueueTitle: ""

    function isAlbumOrPlaylistSource() {
        if (!root.playingPlaylistTitle) return false;
        var t = String(root.playingPlaylistTitle).trim();
        if (!t) return false;
        if (t === "Queue" || t === "Hàng đợi" || t === I18n.tr("Hàng đợi", "Queue")) return false;
        if (t === "Home" || t === "Trang chủ" || t === I18n.tr("Trang chủ", "Home")) return false;
        if (t === "Downloads" || t === "Tải xuống" || t === I18n.tr("Tải xuống", "Downloads")) return false;
        if (t.startsWith("Search") || t.startsWith("Tìm kiếm")) return false;
        if (t === "Automix Queue" || t === "Hàng đợi tự động" || t === I18n.tr("Hàng đợi tự động", "Automix Queue")) return false;
        return true;
    }

    onPlayingPlaylistTitleChanged: {
        root.lastAlbumQueueTitle = root.playingPlaylistTitle;
        root.originalAlbumQueue = [];
        if (isAlbumOrPlaylistSource() && root.selectedMoodIndex === 0 && root.queueTracks && root.queueTracks.length > 0) {
            root.originalAlbumQueue = root.queueTracks.slice();
        }
    }

    onQueueTracksChanged: {
        if (isAlbumOrPlaylistSource() && root.selectedMoodIndex === 0) {
            if (root.queueTracks && root.queueTracks.length > 0) {
                root.originalAlbumQueue = root.queueTracks.slice();
                root.lastAlbumQueueTitle = root.playingPlaylistTitle;
            }
        }
    }

    property bool animatedCoverEnabled: (typeof win !== "undefined" && win) ? win.animatedCoverEnabled : true
    property string canvasPreference: (typeof win !== "undefined" && win) ? win.canvasPreference : "apple_first"
    property string animatedArtworkUrl: ""
    property bool isLoadingAnimatedArtwork: false
    onAnimatedCoverEnabledChanged: {
        if (animatedCoverEnabled && canvasPreference !== "off") {
            fetchAnimatedArtwork();
        } else {
            animatedArtworkUrl = "";
        }
    }
    onCanvasPreferenceChanged: {
        if (animatedCoverEnabled && canvasPreference !== "off") {
            fetchAnimatedArtwork();
        } else {
            animatedArtworkUrl = "";
        }
    }

    property string resolvedSquareImage: ""
    property bool resolvedIsSquare: false
    property bool squareImageFailed: false
    property string lastResolvedCoverKey: ""
    signal squareCoverResolved(string url, bool isSquare)

    signal seekRequested(real seconds)
    signal playTrackRequested(var trk, int index)
    signal trackContextMenuRequested(var trk, real globalX, real globalY, bool isQueue)
    // The cover "more" button: same menu plus the lyrics source picker
    signal nowPlayingMenuRequested(var trk, real globalX, real globalY)
    // Sleep timer is its own right-panel tab (Swiftify-like); the host owns the countdown
    signal sleepTimerStartRequested(int seconds, string fade)
    signal sleepTimerEndOfTrackRequested()
    signal sleepTimerCancelRequested()
    property bool isSleepTimerActive: false
    property int sleepTimerRemainingSeconds: 0
    property int sleepTimerTotalSeconds: 0
    property string sleepTimerMode: ""
    property string sleepTimerFade: "final"

    // Settings are written by a detached process, so give it a moment before the helper re-reads them.
    function refetchLyricsSoon() { lyricsRefetchTimer.restart(); }
    // Apply the copy the lyrics source probe already fetched for `key` (instant, no new search)
    function applyLyricsSource(key) {
        var title = (track && (track.title || track.name)) ? (track.title || track.name) : "";
        if (title === "" || key === "auto") { refetchLyricsSoon(); return; }
        lyricsRefetchTimer.stop();
        activeLyrics = [];
        currentLyricIndex = -1;
        hasLyrics = false;
        isLoadingLyrics = true;
        lyricsProc.running = false;
        lyricsProc.command = ["python3", "-u", root.appDir + "/backend/lyrics_helper.py", "--apply", key, title, (track && track.artist) ? track.artist : ""];
        lyricsProc.running = true;
    }
    Timer { id: lyricsRefetchTimer; interval: 450; repeat: false; onTriggered: root.fetchLyrics() }
    signal playlistSelected(var pl)
    signal artistSelected(string name, string channelId)
    signal collapseRequested()
    signal playPauseRequested()
    signal nextRequested()
    signal prevRequested()
    signal shuffleToggleRequested()
    signal repeatToggleRequested()
    signal volumeChangeRequested(real newVol)
    signal rateSongRequested(string videoId, string rating)
    signal songDisliked(var trk)
    signal downloadRequested(var trk)
    signal queueUpdated(var newTracks)
    signal exitListeningAlongRequested()

    property var listeningAlongFriend: null
    // AutoMix transition card (see AutoMixBridge.qml)
    property var mixUpcoming: null
    property var mixActive: null

    FileView {
        id: dislikedFileView
        path: Quickshell.env("HOME") + "/.config/noctalia/nutsty_disliked_songs.json"
        watchChanges: true
        onFileChanged: {
            reload();
            try {
                var txt = text();
                if (txt && txt.length > 2) dislikedSongsMap = JSON.parse(txt);
            } catch (e) {}
        }
        Component.onCompleted: {
            try {
                var txt = text();
                if (txt && txt.length > 2) dislikedSongsMap = JSON.parse(txt);
            } catch (e) {}
        }
    }

    function isTrackDisliked(vid) {
        if (!vid || !dislikedSongsMap) return false;
        var clean = String(vid).replace("ytdl://", "").replace("yt_", "");
        return !!dislikedSongsMap[clean];
    }

    function toggleLike() {
        if (!root.track) return;
        var vid = root.track.videoId || (root.track.path && root.track.path.startsWith("ytdl://") ? root.track.path.replace("ytdl://", "") : "");
        if (!vid) return;
        var newStatus = (currentLikeStatus === "LIKE") ? "INDIFFERENT" : "LIKE";
        currentLikeStatus = newStatus;
        root.rateSongRequested(vid, newStatus);
    }

    function dislikeCurrentTrack() {
        if (!root.track) return;
        currentLikeStatus = "DISLIKE";
        var vid = root.track.videoId || (root.track.path && root.track.path.startsWith("ytdl://") ? root.track.path.replace("ytdl://", "") : "");
        if (vid) {
            root.rateSongRequested(vid, "DISLIKE");
        }
        root.songDisliked(root.track);
    }

    function downloadCurrentTrack() {
        if (!root.track) return;
        root.downloadRequested(root.track);
    }

    onTrackChanged: {
        if (!root.track) {
            currentLikeStatus = "INDIFFERENT";
            root.moodChips = [];
            root.selectedMoodIndex = 0;
            root.resolvedSquareImage = "";
            root.resolvedIsSquare = false;
            root.squareImageFailed = false;
            root.lastResolvedCoverKey = "";
            return;
        }
        root.highResFailed = false;
        root.squareImageFailed = false;
        resolveCoverArt(root.track);
        var vid = root.track.videoId || (root.track.path && root.track.path.startsWith("ytdl://") ? root.track.path.replace("ytdl://", "") : "");
        currentLikeStatus = (vid && isTrackDisliked(vid)) ? "DISLIKE" : "INDIFFERENT";

        // Check if the newly playing track is already part of the active queue (e.g. playing next within the current mood)
        var isAlreadyInQueue = false;
        if (root.queueTracks && root.queueTracks.length > 1) {
            for (var i = 0; i < root.queueTracks.length; ++i) {
                var qTrk = root.queueTracks[i];
                if (typeof win !== "undefined" && win && win.isSameTrack(qTrk, root.track)) {
                    isAlreadyInQueue = true;
                    break;
                }
            }
        }

        root.lyricsSource = "";
        fetchLyrics();
        fetchAnimatedArtwork();
        delayedAudioSpecsTimer.restart();

        if (!isAlreadyInQueue) {
            // New seed track selected from outside the current queue (Home / Downloads / Search / New Album):
            // Reset mood index, clear cached vid, and fetch fresh mood chips + queue!
            root.selectedMoodIndex = 0;
            root.lastMoodChipsVid = "";
            root.originalAlbumQueue = [];
            fetchMoodChips();
        }
        // If already in queue: keep current queueTracks & selectedMoodIndex untouched!
    }

    onVisibleChanged: {
        if (visible) {
            delayedAudioSpecsTimer.restart();
            updateActiveLyric(true);
        }
        if (visible && root.track && (!root.moodChips || root.moodChips.length === 0)) {
            fetchMoodChips();
        }
        if (visible && root.track && root.resolvedSquareImage === "") {
            resolveCoverArt(root.track);
        }
        if (visible && root.track && root.animatedCoverEnabled && (!root.animatedArtworkUrl || root.animatedArtworkUrl === "") && !root.isLoadingAnimatedArtwork) {
            fetchAnimatedArtwork();
        }
    }

    onCurrentTimeChanged: {
        if (root.visible) {
            updateActiveLyric(false);
        }
    }

    Timer {
        id: userScrollTimer
        interval: 3500
        repeat: false
        onTriggered: {
            if (!lyricsView.moving && !lyricsView.dragging && !lyricsView.flicking) {
                root.followPlayback = true;
                root.recenterToCurrentLyric(true);
            }
        }
    }

    // 1:1 Mochy-Music independent smooth recenter controller (LyricsScreen.kt)
    // RecenterDurationMs = 950ms, CubicBezierEasing(0.42f, 0f, 0.16f, 1f), MinPastLineVisibleHeight = 72.dp
    function recenterToCurrentLyric(smooth) {
        if (!lyricsView || !activeLyrics || activeLyrics.length === 0) return;
        var targetIdx = root.anchorLyricIndex;
        if (targetIdx < 0 || targetIdx >= activeLyrics.length) targetIdx = root.currentLyricIndex;
        if (targetIdx < 0 || targetIdx >= activeLyrics.length) return;

        var restingOffset = Math.max(72, Math.round(lyricsView.height * 0.055));
        var targetItem = lyricsView.itemAtIndex(targetIdx);

        if (!targetItem) {
            lyricsView.positionViewAtIndex(targetIdx, ListView.Beginning);
            targetItem = lyricsView.itemAtIndex(targetIdx);
        }

        if (targetItem) {
            var destY = targetItem.y - restingOffset;
            var minContentY = -lyricsView.topMargin;
            var maxContentY = Math.max(minContentY, lyricsView.contentHeight + lyricsView.bottomMargin - lyricsView.height);
            destY = Math.max(minContentY, Math.min(maxContentY, destY));

            if (smooth) {
                smoothRecenterAnim.stop();
                smoothRecenterAnim.to = destY;
                smoothRecenterAnim.start();
            } else {
                smoothRecenterAnim.stop();
                lyricsView.contentY = destY;
            }
        }
    }

    NumberAnimation {
        id: smoothRecenterAnim
        target: (typeof lyricsView !== "undefined") ? lyricsView : null
        property: "contentY"
        duration: 950
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.42, 0.0, 0.16, 1.0, 1.0, 1.0]
    }


    function getHighResImage(url) {
        if (!url || typeof url !== "string") return "";
        if (url.indexOf("googleusercontent.com") !== -1 || url.indexOf("ggpht.com") !== -1) {
            if (/=w\d+-h\d+/.test(url)) {
                return url.replace(/=w\d+-h\d+[^=]*$/, "=w1200-h1200-l90-rj");
            } else if (url.indexOf("=") !== -1) {
                return url.split("=")[0] + "=w1200-h1200-l90-rj";
            } else {
                return url + "=w1200-h1200-l90-rj";
            }
        }
        if (url.indexOf("mzstatic.com") !== -1) {
            return url.replace(/\d+x\d+bb/, "1200x1200bb");
        }
        if (url.indexOf("i.ytimg.com") !== -1) {
            if (url.indexOf("maxresdefault.jpg") !== -1) {
                return url.split("?")[0];
            }
            var clean = url.split("?")[0];
            return clean.replace(/\/(hqdefault|mqdefault|sddefault|default|hq720)\.jpg/, "/maxresdefault.jpg");
        }
        return url;
    }

    function getRawTrackImage(trk) {
        if (!trk) return "";
        var img = trk.image || trk.artUrl || trk.cover || trk.thumbnail || "";
        if (!img) {
            var vid = trk.videoId || (trk.path && trk.path.startsWith("ytdl://") ? trk.path.replace("ytdl://", "") : "");
            if (vid) {
                img = "https://i.ytimg.com/vi/" + vid + "/hqdefault.jpg";
            }
        }
        return img;
    }

    // ---- Square cover lookup (shared by the current track and AutoMix prefetch) ----------------
    // One cache per session keyed like the resolver, so the next track's artwork can be resolved
    // and decoded before the switch and the main cover never shows the previous track's image.
    property var coverCache: ({})
    property var coverInflight: ({})
    property int coverCacheRev: 0

    function coverInfoOf(trk) {
        if (!trk) return null;
        var tTitle = (trk.title || trk.name || "").trim();
        var tArtist = (trk.artist || "").trim();
        var tVid = trk.videoId || (trk.path && trk.path.startsWith("ytdl://") ? trk.path.replace("ytdl://", "") : "");
        var tImg = root.getRawTrackImage(trk);
        // If videoId is missing, extract it directly from YouTube image URL
        if (!tVid && tImg && tImg.indexOf("i.ytimg.com") !== -1) {
            var m = tImg.match(/vi\/([a-zA-Z0-9_-]{11})\//);
            if (m && m[1]) tVid = m[1];
        }
        return { title: tTitle, artist: tArtist, vid: tVid, img: tImg, key: (tVid ? tVid : (tTitle + "_" + tArtist)) };
    }
    function storeCover(key, r) {
        var c = root.coverCache;
        c[key] = r;
        root.coverCache = c;
        root.coverCacheRev++;
    }
    // Resolved artwork for a track if it is already known, else "" (bind with coverCacheRev)
    function cachedCoverFor(trk) {
        var info = coverInfoOf(trk);
        var c = info ? root.coverCache[info.key] : null;
        return (c && c.url) ? c.url : "";
    }
    // Same answer resolveCoverArt would give; cb(result, info) with result {url, isSquare}
    function lookupCover(trk, cb) {
        var info = coverInfoOf(trk);
        if (!info) return;
        var hit = root.coverCache[info.key];
        if (hit) { if (cb) cb(hit, info); return; }
        // Tier 0: Already native square Google CDN image
        if (info.img && (info.img.indexOf("googleusercontent.com") !== -1 || info.img.indexOf("ggpht.com") !== -1)) {
            storeCover(info.key, { url: root.getHighResImage(info.img), isSquare: true });
        } else if (info.img && (info.img.startsWith("/") || info.img.startsWith("file://"))) {
            // Local embedded artwork file (extracted jpg/png in local filesystem)
            storeCover(info.key, { url: info.img, isSquare: true });
        }
        hit = root.coverCache[info.key];
        if (hit) { if (cb) cb(hit, info); return; }

        var waiting = root.coverInflight[info.key];
        if (waiting) { if (cb) waiting.push(cb); return; }
        root.coverInflight[info.key] = cb ? [cb] : [];
        function finish(r, cacheIt) {
            if (cacheIt) storeCover(info.key, r);
            var cbs = root.coverInflight[info.key] || [];
            delete root.coverInflight[info.key];
            for (var i = 0; i < cbs.length; ++i) cbs[i](r, info);
        }
        // Tier 1: Query resident HTTP daemon /api/resolve_cover for official 1:1 square artwork
        var apiUrl = "http://127.0.0.1:17890/api/resolve_cover?" +
                     "title=" + encodeURIComponent(info.title) +
                     "&artist=" + encodeURIComponent(info.artist) +
                     "&videoId=" + encodeURIComponent(info.vid) +
                     "&current=" + encodeURIComponent(info.img);
        var xhr = new XMLHttpRequest();
        xhr.open("GET", apiUrl);
        xhr.timeout = 8000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status !== 200) { finish({ url: "", isSquare: false }, false); return; }
            try {
                var res = JSON.parse(xhr.responseText);
                if (res && res.url) finish({ url: root.getHighResImage(res.url), isSquare: res.is_square === true }, true);
                else finish({ url: "", isSquare: false }, true);
            } catch (e) {
                finish({ url: "", isSquare: false }, false);
            }
        };
        xhr.ontimeout = function() { finish({ url: "", isSquare: false }, false); };
        xhr.send();
    }
    // Background prefetch for the next track: resolve it, then decode it at the main cover's size
    function prefetchCoverArt(trk) {
        lookupCover(trk, function(r, info) {
            coverPreloader.source = coverSurface.formatImageUrl(r.url || root.getHighResImage(info.img));
        });
    }

    function resolveCoverArt(trk) {
        if (!trk) {
            root.resolvedSquareImage = "";
            root.resolvedIsSquare = false;
            root.squareImageFailed = false;
            root.highResFailed = false;
            root.lastResolvedCoverKey = "";
            return;
        }
        var info = coverInfoOf(trk);
        if (root.lastResolvedCoverKey === info.key && (root.resolvedSquareImage !== "" || root.resolvedIsSquare)) {
            return;
        }
        root.lastResolvedCoverKey = info.key;
        root.squareImageFailed = false;
        root.highResFailed = false;
        // Never keep showing the previous track's artwork while this one resolves
        if (!root.coverCache[info.key]) {
            root.resolvedSquareImage = "";
            root.resolvedIsSquare = false;
        }
        lookupCover(trk, function(r, inf) {
            if (root.lastResolvedCoverKey !== inf.key) return;
            if (r.url) {
                root.resolvedSquareImage = r.url;
                root.resolvedIsSquare = r.isSquare;
                root.squareCoverResolved(r.url, r.isSquare);
            } else {
                root.resolvedSquareImage = "";
                root.resolvedIsSquare = false;
                root.squareCoverResolved(inf.img, false);
            }
        });
    }

    function fetchLyrics() {
        activeLyrics = [];
        currentLyricIndex = -1;
        hasLyrics = false;
        isLoadingLyrics = true;

        var songTitle = (track && (track.title || track.name)) ? (track.title || track.name) : "";
        var songArtist = (track && track.artist) ? track.artist : "";
        var songVid = (track && track.videoId) ? track.videoId : "";
        var songPath = (track && (track.path || track.file_path || track.filePath)) ? (track.path || track.file_path || track.filePath) : "";

        if (songTitle !== "") {
            // The song's own length first: the player's length can still be the previous song's
            var ownDur = PlaybackEngine.extractTrackDuration(track);
            var durSec = ownDur > 1 ? ownDur : root.totalDuration;
            var songDur = durSec > 1 ? String(Math.round(durSec)) : "";
            lyricsProc.running = false;
            lyricsProc.command = [
                "python3", "-u",
                root.appDir + "/backend/lyrics_helper.py",
                songTitle, songArtist, songVid, songPath, songDur
            ];
            lyricsProc.running = true;
        } else {
            isLoadingLyrics = false;
            hasLyrics = false;
        }
    }

    Process {
        id: lyricsProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (!data || data.trim() === "") return;
                try {
                    var parsed = JSON.parse(data);
                    if (Array.isArray(parsed) && parsed.length > 0) {
                        root.hasDuetVoices = root.computeHasDuetVoices(parsed);
                        root.activeLyrics = parsed;
                        root.hasLyrics = true;
                        root.isLoadingLyrics = false;
                        var src = "";
                        for (var i = 0; i < parsed.length; ++i) {
                            if (parsed[i].source) {
                                src = parsed[i].source;
                                break;
                            }
                        }
                        root.lyricsSource = src;
                        Qt.callLater(function() { root.updateActiveLyric(true); });
                    } else {
                        root.activeLyrics = [];
                        root.hasLyrics = false;
                        root.lyricsSource = "";
                        root.isLoadingLyrics = false;
                    }
                } catch (e) {
                    root.activeLyrics = [];
                    root.hasLyrics = false;
                    root.lyricsSource = "";
                    root.isLoadingLyrics = false;
                }
            }
        }
        onExited: (code, status) => {
            root.isLoadingLyrics = false;
        }
    }

    function fetchAudioSpecs() {
        // SSOT: root.audioSpecs is bound to win.audioSpecs, updated in real time via nutsty-bridge status.
    }

    Timer {
        id: delayedAudioSpecsTimer
        interval: 800
        repeat: false
        onTriggered: fetchAudioSpecs()
    }

    Process {
        id: amArtworkProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (!data || data.trim() === "") return;
                try {
                    var res = JSON.parse(data);
                    if (res && res.found && res.video_url) {
                        console.log("[Nutsty] Found Apple Music Animated Artwork:", res.album_name, res.video_url);
                        root.animatedArtworkUrl = res.video_url;
                    } else {
                        root.animatedArtworkUrl = "";
                    }
                } catch (e) {
                    root.animatedArtworkUrl = "";
                }
                root.isLoadingAnimatedArtwork = false;
            }
        }
        onExited: (code, status) => {
            root.isLoadingAnimatedArtwork = false;
        }
    }

    function fetchAnimatedArtwork() {
        root.animatedArtworkUrl = "";
        if (!root.animatedCoverEnabled || root.canvasPreference === "off" || !root.track) {
            root.isLoadingAnimatedArtwork = false;
            return;
        }
        var songTitle = (root.track && (root.track.title || root.track.name)) ? (root.track.title || root.track.name) : "";
        var songArtist = (root.track && root.track.artist) ? root.track.artist : "";
        var dur = 0;
        if (root.track && root.track.durationMs && !isNaN(root.track.durationMs)) {
            dur = Math.round(root.track.durationMs / 1000);
        } else if (root.track && typeof root.track.duration === "number" && !isNaN(root.track.duration)) {
            dur = Math.round(root.track.duration);
        } else if (root.track && typeof root.track.duration === "string" && root.track.duration.indexOf(":") !== -1) {
            var parts = root.track.duration.split(":");
            if (parts.length === 2) {
                dur = parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
            } else if (parts.length === 3) {
                dur = parseInt(parts[0], 10) * 3600 + parseInt(parts[1], 10) * 60 + parseInt(parts[2], 10);
            }
        }
        if (!dur || isNaN(dur)) {
            dur = (root.totalDuration > 1) ? Math.round(root.totalDuration) : 0;
        }

        if (!songTitle) {
            root.isLoadingAnimatedArtwork = false;
            return;
        }

        var songAlbum = "";
        if (root.track) {
            if (root.track.album) {
                songAlbum = (typeof root.track.album === "string") ? root.track.album : (root.track.album.name || "");
            } else if (root.track.albumName) {
                songAlbum = root.track.albumName;
            }
        }

        root.isLoadingAnimatedArtwork = true;
        amArtworkProc.running = false;
        amArtworkProc.command = [
            "python3", "-u",
            root.appDir + "/backend/ytmusic_helper.py",
            "animated_artwork",
            songTitle,
            songArtist,
            String(dur),
            songAlbum,
            root.canvasPreference || "apple_first"
        ];
        amArtworkProc.running = true;
    }

    function updateActiveLyric(forceScroll) {
        if (!root.visible || !activeLyrics || activeLyrics.length === 0) {
            currentLyricIndex = -1;
            return;
        }
        var cur = root.currentTime;
        // 1:1 Mochy-Music line lead-in (LineLeadInMs = 300L): line becomes active 300ms before start,
        // allowing interlude dots to collapse smoothly in step with the recenter scroll!
        var leadIn = 0.3;
        var pos = cur + leadIn;
        var found = -1;
        for (var i = 0; i < activeLyrics.length; i++) {
            if (activeLyrics[i].time > pos) {
                found = i - 1;
                break;
            }
        }
        if (found === -1) {
            found = activeLyrics.length - 1;
        }
        if (found < 0) {
            found = 0;
        }
        if (found !== -1) {
            currentLyricIndex = found;
            if (forceScroll && lyricsView) {
                root.followPlayback = true;
                userScrollTimer.stop();
                root.recenterToCurrentLyric(false);
            }
        }
    }


    function fetchMoodChips() {
        if (!root.moodChipsEnabled) return;
        if (!root.track) {
            root.moodChips = [];
            root.selectedMoodIndex = 0;
            return;
        }
        var vid = root.track.videoId || "";
        if (!vid && root.track.path && root.track.path.startsWith("ytdl://")) {
            vid = root.track.path.replace("ytdl://", "");
        }
        if (!vid) {
            root.moodChips = [];
            root.selectedMoodIndex = 0;
            return;
        }
        if (vid === lastMoodChipsVid && root.moodChips.length > 0 && root.queueTracks && root.queueTracks.length > 1) return;

        lastMoodChipsVid = vid;
        isLoadingMoodChips = true;
        selectedMoodIndex = 0;
        moodChipsProc.running = false;
        moodChipsProc.command = [
            "python3", "-u",
            root.appDir + "/backend/ytmusic_helper.py",
            "next_chips", vid
        ];
        moodChipsProc.running = true;
    }

    function selectMoodChip(index) {
        if (index === root.selectedMoodIndex || index < 0 || index >= root.moodChips.length) return;
        loadQueueForChipIndex(index);
    }

    function loadQueueForChipIndex(index) {
        if (index < 0 || index >= root.moodChips.length) return;

        // If currently at index 0 ("Tất cả") and playing an album/playlist,
        // ALWAYS snapshot the current queue before switching away to another mood!
        if (root.selectedMoodIndex === 0 && root.isAlbumOrPlaylistSource()) {
            if (root.queueTracks && root.queueTracks.length > 0) {
                root.originalAlbumQueue = root.queueTracks.slice();
                root.lastAlbumQueueTitle = root.playingPlaylistTitle;
            }
        }

        root.selectedMoodIndex = index;

        // If user clicks back to index 0 ("Tất cả" / "All") while playing an album/playlist:
        if (index === 0 && root.isAlbumOrPlaylistSource() && root.originalAlbumQueue && root.originalAlbumQueue.length > 0) {
            root.isLoadingMoodQueue = false;
            moodQueueProc.running = false;
            root.queueUpdated(root.originalAlbumQueue);
            if (typeof win !== "undefined" && win) {
                win.currentTracks = root.originalAlbumQueue;
            }
            return;
        }

        var chip = root.moodChips[index];
        if (!chip) return;

        var vid = root.track ? (root.track.videoId || "") : "";
        if (!vid && root.track && root.track.path && root.track.path.startsWith("ytdl://")) {
            vid = root.track.path.replace("ytdl://", "");
        }
        if (!vid) return;

        var plId = chip.playlistId || ("RDAMVM" + vid);
        var params = chip.params || "";

        root.isLoadingMoodQueue = true;
        moodQueueProc.running = false;
        moodQueueProc.command = [
            "python3", "-u",
            root.appDir + "/backend/ytmusic_helper.py",
            "filter_queue", vid, plId, params
        ];
        moodQueueProc.running = true;
    }

    Process {
        id: moodChipsProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (!data || data.trim() === "") return;
                try {
                    var arr = JSON.parse(data);
                    if (Array.isArray(arr) && arr.length > 0) {
                        root.moodChips = arr;
                        var selIdx = 0;
                        for (var i = 0; i < arr.length; ++i) {
                            if (arr[i].selected) {
                                selIdx = i;
                                break;
                            }
                        }
                        root.selectedMoodIndex = selIdx;
                        // Auto-load queue for the active chip ONLY if NOT playing an album/playlist!
                        if (!root.isAlbumOrPlaylistSource()) {
                            root.loadQueueForChipIndex(selIdx);
                        } else {
                            if (root.selectedMoodIndex === 0 && root.queueTracks && root.queueTracks.length > 0) {
                                root.originalAlbumQueue = root.queueTracks.slice();
                                root.lastAlbumQueueTitle = root.playingPlaylistTitle;
                            }
                        }
                    }
                    root.isLoadingMoodChips = false;
                } catch (e) {
                    root.isLoadingMoodChips = false;
                }
            }
        }
        onExited: (code, status) => {
            root.isLoadingMoodChips = false;
        }
    }

    Process {
        id: moodQueueProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (!data || data.trim() === "") return;
                try {
                    var arr = JSON.parse(data);
                    if (Array.isArray(arr) && arr.length > 0) {
                        var cur = root.track;
                        var filtered = arr.filter(function(t) {
                            if (!cur) return true;
                            if (cur.videoId && t.videoId && cur.videoId === t.videoId) return false;
                            if (cur.path && t.path && cur.path === t.path) return false;
                            return true;
                        });
                        var newQueue = cur ? [cur].concat(filtered) : filtered;
                        root.queueUpdated(newQueue);
                        if (typeof win !== "undefined" && win) {
                            win.currentTracks = newQueue;
                        }
                    }
                    root.isLoadingMoodQueue = false;
                } catch (e) {
                    root.isLoadingMoodQueue = false;
                }
            }
        }
        onExited: (code, status) => {
            root.isLoadingMoodQueue = false;
        }
    }

    // =========================================================================
    // MAIN AREA: left cluster (cover + info + controls) and the right panel (lyrics / up next).
    // Absolutely positioned so mode switches animate like Swiftify: the cluster glides between
    // centred and compact with an expressive spring curve, the panel slides in from the right.
    // =========================================================================
    Item {
        id: mainArea
        anchors.fill: parent
        z: 1
        anchors.leftMargin: root.width >= 1200 ? 48 : 24
        anchors.rightMargin: root.width >= 1200 ? 48 : 24
        anchors.topMargin: 12
        anchors.bottomMargin: 24

        readonly property real gap: root.width >= 1200 ? 48 : 28
        readonly property real compactLeftW: Math.round((width - gap) * 0.4)
        // 0 = artwork mode (cluster centred), 1 = panel mode (cluster compact on the left)
        property real panelT: root.isArtworkMode ? 0 : 1
        Behavior on panelT {
            NumberAnimation { duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0] }
        }

        // =====================================================================
        // LEFT CLUSTER: Big Artwork / Video + Song Title + Controls
        // =====================================================================
        ColumnLayout {
            id: leftColumn
            x: 0
            y: 0
            width: mainArea.width + (mainArea.compactLeftW - mainArea.width) * mainArea.panelT
            height: mainArea.height
            spacing: 16
            readonly property real blockWidth: coverArtworkWrapper.width

            // Central Media Display: Big Square Artwork (Clean HD Retina)
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignCenter
                // Keep the cover (and its halo) clear of the collapse button in the top-left corner.
                Layout.topMargin: 52

                Item {
                    id: coverArtworkWrapper
                    anchors.centerIn: parent
                    // Smaller than the slot so the glow halo has room to bloom around it.
                    width: Math.max(200, Math.min(parent.width - 96, parent.height - 72, 420 - 80 * Math.min(1, mainArea.panelT)))
                    height: width
                    // AutoMix stages the cover like an app switcher (see AutoMixBridge.qml)
                    transform: [
                        Scale {
                            origin.x: coverArtworkWrapper.width / 2
                            origin.y: coverArtworkWrapper.height / 2
                            xScale: autoMix.mainScale
                            yScale: autoMix.mainScale
                        },
                        Translate { x: autoMix.mainShift }
                    ]

                    // Halo: two soft rounded-rect shadows in the cover's own two main colours, slightly
                    // offset in opposite directions (the approach Swiftify uses). SDF shadows have no blur
                    // buffer to clip, so the glow is never cut into a square and costs nothing while still.
                    property color glowPrimary: Qt.rgba(1, 1, 1, 1)
                    property color glowSecondary: Qt.rgba(1, 1, 1, 1)
                    readonly property real glowRadius: 78
                    readonly property real glowIntensity: 0.8
                    Behavior on glowPrimary { ColorAnimation { duration: 600 } }
                    Behavior on glowSecondary { ColorAnimation { duration: 600 } }

                    RectangularShadow {
                        anchors.fill: coverSurface
                        z: -1
                        radius: 16
                        spread: 4
                        blur: coverArtworkWrapper.glowRadius
                        offset: Qt.vector2d(-0.22 * coverArtworkWrapper.glowRadius, 0.12 * coverArtworkWrapper.glowRadius)
                        color: Qt.rgba(coverArtworkWrapper.glowPrimary.r, coverArtworkWrapper.glowPrimary.g, coverArtworkWrapper.glowPrimary.b, coverArtworkWrapper.glowIntensity)
                    }
                    RectangularShadow {
                        anchors.fill: coverSurface
                        z: -1
                        radius: 16
                        spread: 4
                        blur: coverArtworkWrapper.glowRadius * 0.82
                        offset: Qt.vector2d(0.24 * coverArtworkWrapper.glowRadius, -0.08 * coverArtworkWrapper.glowRadius)
                        color: Qt.rgba(coverArtworkWrapper.glowSecondary.r, coverArtworkWrapper.glowSecondary.g, coverArtworkWrapper.glowSecondary.b, coverArtworkWrapper.glowIntensity * 0.72)
                    }

                    // Cover colour sampling: the cover is loaded again at 16x16 and drawn into a Canvas; the
                    // chroma-weighted average of its left and right halves gives the primary / secondary colours.
                    Canvas {
                        id: glowSampler
                        width: 16; height: 16
                        opacity: 0
                        enabled: false
                        property string src: coverSurface.coverSource ? coverSurface.coverSource.toString() : ""
                        onSrcChanged: { if (src !== "") { if (isImageLoaded(src)) requestPaint(); else loadImage(src); } }
                        onImageLoaded: requestPaint()
                        onAvailableChanged: if (available && src !== "") { if (isImageLoaded(src)) requestPaint(); else loadImage(src); }
                        onPaint: {
                            if (src === "" || !isImageLoaded(src)) return;
                            var ctx = getContext("2d");
                            ctx.clearRect(0, 0, 16, 16);
                            ctx.drawImage(src, 0, 0, 16, 16);
                            var d = ctx.getImageData(0, 0, 16, 16).data;
                            var acc = [[0, 0, 0, 0], [0, 0, 0, 0]];
                            for (var y = 0; y < 16; ++y) {
                                for (var x = 0; x < 16; ++x) {
                                    var o = (y * 16 + x) * 4;
                                    if (d[o + 3] < 128) continue;
                                    var r = d[o] / 255, g = d[o + 1] / 255, b = d[o + 2] / 255;
                                    var w = 0.15 + Math.max(r, g, b) - Math.min(r, g, b);
                                    var a = acc[x < 8 ? 0 : 1];
                                    a[0] += r * w; a[1] += g * w; a[2] += b * w; a[3] += w;
                                }
                            }
                            // Average colour -> HSL, then push saturation up and keep lightness in a glowing range
                            function vivid(a) {
                                if (a[3] <= 0) return null;
                                var r = a[0] / a[3], g = a[1] / a[3], b = a[2] / a[3];
                                var mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2, h = 0, sat = 0;
                                if (mx > mn) {
                                    var dd = mx - mn;
                                    sat = l > 0.5 ? dd / (2 - mx - mn) : dd / (mx + mn);
                                    if (mx === r) h = (g - b) / dd + (g < b ? 6 : 0);
                                    else if (mx === g) h = (b - r) / dd + 2;
                                    else h = (r - g) / dd + 4;
                                    h /= 6;
                                }
                                return Qt.hsla(h, Math.min(1, sat * 1.6 + 0.12), Math.max(0.45, Math.min(0.62, l)), 1);
                            }
                            var c0 = vivid(acc[0]), c1 = vivid(acc[1]);
                            if (!c0 || !c1) return;   // nothing drawn yet: keep the previous colours
                            coverArtworkWrapper.glowPrimary = c0;
                            coverArtworkWrapper.glowSecondary = c1;
                                }
                    }

                    MediaCoverSurface {
                        id: coverSurface
                        anchors.fill: parent
                        track: root.track
                        radius: 16
                        animatedCoverEnabled: root.animatedCoverEnabled
                        canvasPreference: root.canvasPreference
                        isPlaying: root.isPlaying
                        overrideImage: root.resolvedSquareImage
                        overrideAnimatedArtworkUrl: root.animatedArtworkUrl
                        appDir: root.appDir
                    }
                }

                // Decodes the next track's artwork ahead of time with the main cover's exact request
                // (same URL and size), so the switch reuses the cached pixmap instead of loading
                RoundedImage {
                    id: coverPreloader
                    visible: false
                    width: 1
                    height: 1
                    asynchronous: true
                    sourceSize: Qt.size(1200, 1200)
                    autoCropBlackBars: coverSurface.autoCropBlackBars
                }

                // AutoMix: the next track and the particle stream around the cover (artwork mode only)
                AutoMixBridge {
                    id: autoMix
                    anchors.fill: parent
                    z: 2
                    track: root.track
                    mixUpcoming: root.mixUpcoming
                    mixActive: root.mixActive
                    isPlaying: root.isPlaying
                    shown: mainArea.panelT < 0.5
                    coverSize: coverArtworkWrapper.width
                    coverRadius: coverSurface.radius
                    onPrefetchRequested: trk => root.prefetchCoverArt(trk)
                    mainReady: coverSurface.coverStatus === Image.Ready
                    mainSurface: coverSurface
                    prevImage: {
                        root.coverCacheRev;
                        var u = root.cachedCoverFor(autoMix.prevTrack);
                        return u ? coverSurface.formatImageUrl(u) : "";
                    }
                    nextImage: {
                        root.coverCacheRev;
                        var u = root.cachedCoverFor(autoMix.nextTrack);
                        return u ? coverSurface.formatImageUrl(u) : "";
                    }
                    mainColor: coverArtworkWrapper.glowPrimary
                    accentColor: root.accentColor
                }
            }

            // 3. Track Details (Swiftify-like, centred): title, then artist with an inline "more" button
            ColumnLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: leftColumn.blockWidth
                Layout.alignment: Qt.AlignHCenter
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.track ? (root.track.title || root.track.name || "") : I18n.pick("track.none", ["Chưa chọn bài hát", "Im ắng quá, chọn bài đi", "Loa đang ngồi chơi xơi nước", "Bài đâu rồi ta?", "Tai đang đói, cho ăn đi", "Chọn một bài cho đời thêm vui", "Sân khấu trống, mời bài lên"], ["No track playing", "Too quiet, pick a song", "The speakers are on a break", "Where's the song?", "Your ears are hungry, feed them", "Pick a song, brighten the day", "Empty stage, bring on a song"])
                    font.family: Theme.fontFamily
                    font.pixelSize: 26
                    font.bold: true
                    color: "#ffffff"
                    elide: Text.ElideRight
                }

                Row {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: leftColumn.blockWidth
                    spacing: 4

                    Text {
                        id: artistText
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, leftColumn.blockWidth - moreBtn.width - 8)
                        text: root.track ? (root.track.artist || I18n.tr("Nghệ sĩ chưa rõ", "Unknown Artist")) : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                        color: Qt.rgba(1, 1, 1, 0.65)
                        elide: Text.ElideRight

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.track && root.track.artist) {
                                    root.artistSelected(root.track.artist, root.track.channelId || "");
                                }
                            }
                        }
                    }

                    NowPlayingCtlButton {
                        id: moreBtn
                        anchors.verticalCenter: parent.verticalCenter
                        size: 32
                        iconScale: 0.7
                        icon: "../assets/icons/material/ms-more_vert.svg"
                        onClicked: {
                            if (root.track) {
                                var pt = moreBtn.mapToItem(null, 0, moreBtn.height + 4);
                                root.nowPlayingMenuRequested(root.track, pt.x, pt.y);
                            }
                        }
                    }
                }
            }

            NowPlayingControls {
                Layout.fillWidth: true
                Layout.maximumWidth: leftColumn.blockWidth
                Layout.alignment: Qt.AlignHCenter
                currentTime: root.currentTime
                totalDuration: root.totalDuration
                isPlaying: root.isPlaying
                isLoadingAudio: root.isLoadingAudio
                isShuffle: root.isShuffle
                repeatMode: root.repeatMode
                volume: root.volume
                qualityText: root.track ? root.audioQualityText : ""
                mixing: autoMix.mixing
                onSeekRequested: sec => root.seekRequested(sec)
                onPlayPauseClicked: root.playPauseRequested()
                onNextClicked: root.nextRequested()
                onPrevClicked: root.prevRequested()
                onShuffleClicked: root.shuffleToggleRequested()
                onRepeatClicked: root.repeatToggleRequested()
                onVolumeChangeRequested: v => root.volumeChangeRequested(v)
            }

            Item { Layout.preferredHeight: 4 }
        }

        // =====================================================================
        // RIGHT PANEL: [ UP NEXT | LYRICS ]; opacity / shift are driven by the panel animations
        // =====================================================================
        ColumnLayout {
            id: rightPanel
            property real shift: 1.0
            x: mainArea.compactLeftW + mainArea.gap + shift * 72
            y: 0
            width: mainArea.width - mainArea.compactLeftW - mainArea.gap
            height: mainArea.height
            opacity: 0.0
            visible: opacity > 0.001
            spacing: 12

            // Header room for the floating mode switcher (top-right)
            Item { Layout.fillWidth: true; Layout.preferredHeight: 52 }

            // 2. Tab Content Stack: [ UP NEXT | LYRICS | RELATED ]
            StackLayout {
                id: tabContentStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.shownPanel === "up_next" ? 0 : (root.shownPanel === "sleep" ? 2 : 1)

                // =============================================================
                // TAB 1 VIEW: UP NEXT (Playing Queue)
                // =============================================================
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8

                        Item { Layout.fillHeight: true }

                        ListView {
                            id: queueListView
                            Layout.fillWidth: true
                            Layout.maximumWidth: 640
                            // Swiftify-like: a compact window (about six rows) centred beside the cover
                            Layout.preferredHeight: Math.min(parent.height, 80 * 6.5 + topMargin + bottomMargin)
                            clip: true
                            spacing: 10
                            topMargin: 24
                            bottomMargin: 24
                            cacheBuffer: 420
                            opacity: root.isLoadingMoodQueue ? 0.45 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            model: root.queueTracks

                            function sameTrack(a, b) {
                                if (!a || !b) return false;
                                if (typeof win !== "undefined" && typeof win.isSameTrack === "function") return win.isSameTrack(a, b);
                                return (a.id && b.id && a.id === b.id) || (a.videoId && b.videoId && a.videoId === b.videoId)
                                    || (a.path && b.path && a.path === b.path)
                                    || (a.title && b.title && a.title === b.title && a.artist && b.artist && a.artist === b.artist);
                            }
                            readonly property int currentQueueIndex: {
                                var q = root.queueTracks;
                                if (!q || !root.track) return -1;
                                for (var i = 0; i < q.length; ++i) if (sameTrack(q[i], root.track)) return i;
                                return -1;
                            }
                            function focusCurrent() {
                                if (currentQueueIndex >= 0) positionViewAtIndex(currentQueueIndex, ListView.Beginning);
                            }
                            onCurrentQueueIndexChanged: if (!moving && root.shownPanel === "up_next") Qt.callLater(focusCurrent)

                            // Staggered rise-in of the rows below the current one each time the queue panel appears
                            property real introT: 1.0
                            NumberAnimation { id: queueIntroAnim; target: queueListView; property: "introT"; from: 0; to: 1; duration: 780 }
                            Connections {
                                target: root
                                function onShownPanelChanged() {
                                    if (root.shownPanel === "up_next") {
                                        Qt.callLater(queueListView.focusCurrent);
                                        queueIntroAnim.restart();
                                    }
                                }
                            }

                            // Rows dissolve into the top / bottom edges while scrolling (own edge_fade shader)
                            readonly property real fadePx: 56
                            layer.enabled: contentHeight > height
                            layer.effect: ShaderEffect {
                                property variant source
                                property real u_top: queueListView.atYBeginning ? 0.0 : Math.min(0.45, queueListView.fadePx / Math.max(1, queueListView.height))
                                property real u_bottom: queueListView.atYEnd ? 0.0 : Math.min(0.45, queueListView.fadePx / Math.max(1, queueListView.height))
                                Behavior on u_top { NumberAnimation { duration: 180 } }
                                Behavior on u_bottom { NumberAnimation { duration: 180 } }
                                fragmentShader: Qt.resolvedUrl("../assets/shaders/edge_fade.frag.qsb")
                            }

                            delegate: Column {
                                id: delegateCol
                                width: queueListView.width
                                spacing: 10

                                readonly property bool isCurrent: index === queueListView.currentQueueIndex
                                // Intro progress: 30 ms step per row after the current one, 420 ms settle each
                                readonly property real introE: {
                                    var rel = Math.max(0, Math.min(12, index - Math.max(0, queueListView.currentQueueIndex)));
                                    var p = Math.max(0, Math.min(1, (queueListView.introT * 780 - rel * 30) / 420));
                                    return 1 - Math.pow(1 - p, 3);
                                }
                                opacity: introE
                                transform: Translate { y: 12 * (1 - delegateCol.introE) }

                                Rectangle {
                                    id: qRow
                                    width: delegateCol.width
                                    height: 70
                                    radius: 14
                                    readonly property bool isCurrent: delegateCol.isCurrent
                                    color: Qt.rgba(1, 1, 1, isCurrent ? 0.07 : (qRowMouse.containsMouse ? 0.04 : 0.0))
                                    Behavior on color { ColorAnimation { duration: 140 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 12
                                        spacing: 14

                                        RoundedImage {
                                            Layout.preferredWidth: 54
                                            Layout.preferredHeight: 54
                                            radius: 8
                                            source: modelData.image || ""
                                            fillMode: Image.PreserveAspectCrop
                                            fallbackIcon: "../assets/icons/material/ms-music_note.svg"
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 3

                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.title || modelData.name || I18n.tr("Không xác định", "Unknown")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                                font.weight: qRow.isCurrent ? Font.Bold : Font.DemiBold
                                                color: "#ffffff"
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.artist || I18n.tr("Nghệ sĩ chưa rõ", "Unknown Artist")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 13
                                                font.weight: Font.Medium
                                                color: Qt.rgba(1, 1, 1, 0.6)
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Item {
                                            Layout.preferredWidth: 40
                                            Layout.preferredHeight: 40

                                            // Current row: speaker glyph in the accent colour
                                            AppIcon {
                                                anchors.centerIn: parent
                                                visible: qRow.isCurrent && !qRowMouse.containsMouse
                                                source: "../assets/icons/material/ms-volume_up-fill.svg"
                                                iconSize: 22
                                                color: root.accentColor
                                                opacity: root.isPlaying ? 1.0 : 0.55
                                                Behavior on opacity { NumberAnimation { duration: 160 } }
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                visible: !qRow.isCurrent && !qRowMouse.containsMouse && text.length > 0
                                                text: (modelData && modelData.duration && modelData.duration !== "--:--") ? modelData.duration : ""
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                font.weight: Font.Medium
                                                font.features: { "tnum": 1 }
                                                color: Qt.rgba(1, 1, 1, 0.45)
                                            }

                                            NowPlayingCtlButton {
                                                id: qMoreBtn
                                                anchors.centerIn: parent
                                                visible: qRowMouse.containsMouse
                                                size: 36
                                                icon: "../assets/icons/material/ms-more_horiz.svg"
                                                onClicked: {
                                                    var gPos = qMoreBtn.mapToItem(root, 0, qMoreBtn.height + 4);
                                                    root.trackContextMenuRequested(modelData, gPos.x, gPos.y, true);
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: qRowMouse
                                        anchors.fill: parent
                                        z: -1
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: mouse => {
                                            if (mouse.button === Qt.RightButton) {
                                                var gPos = mapToItem(root, mouse.x, mouse.y);
                                                root.trackContextMenuRequested(modelData, gPos.x, gPos.y, true);
                                            } else {
                                                root.playTrackRequested(modelData, index);
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }

                    EmptyState {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 30
                        width: Math.min(parent.width - 40, 320)
                        visible: (!root.queueTracks || root.queueTracks.length === 0) && !root.isLoadingMoodQueue
                        icon: "../assets/icons/material/ms-queue_music.svg"
                        shape: "clover"
                        accentColor: root.accentColor
                        title: I18n.pick("queue.empty", ["Hàng đợi trống", "Chưa ai xếp hàng cả", "Vắng như chợ chiều", "Hàng đợi đang ngồi chơi", "Thêm bài đi, kẻo nhạc hết giữa chừng", "Trống trơn, xếp vài bài vào nhé", "Hàng đợi khum có ai"], ["Queue is empty", "Nobody's in line", "Empty as a market at closing time", "The queue is taking a break", "Add songs before the music runs out", "All empty, line up a few songs", "Not a soul in the queue"])
                        description: I18n.tr("Phát một bài hát hoặc danh sách để xem các bài tiếp theo.", "Play a song or a playlist to see what comes next.")
                    }
                }

                // =============================================================
                // TAB 2 VIEW: LYRICS (Seamless Full-Height Kinetic Bokeh Stream)
                // =============================================================
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    ListView {
                        id: lyricsView
                        anchors.fill: parent
                        readonly property bool isUserScrolling: dragging || flicking || moving || !root.followPlayback
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        clip: false
                        spacing: 22
                        topMargin: 72
                        bottomMargin: Math.round(height * 0.65)
                        currentIndex: -1
                        highlightFollowsCurrentItem: false
                        highlightRangeMode: ListView.NoHighlightRange
                        highlightMoveDuration: 0
                        cacheBuffer: 300
                        model: root.activeLyrics

                        // Lyrics credit after the last line (Mochy-like): fades in once the final line is reached
                        footer: Item {
                            width: lyricsView.width
                            height: root.lyricsCreditText.length > 0 ? 96 : 0
                            readonly property real lastLineTime: {
                                var l = root.activeLyrics;
                                if (!l || l.length === 0) return 0;
                                var t = l[l.length - 1].time;
                                return (t !== undefined && isFinite(t)) ? t : 0;
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.topMargin: 28
                                text: root.lyricsCreditText
                                wrapMode: Text.WordWrap
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                color: Qt.rgba(1, 1, 1, 0.5)
                                opacity: root.currentTime >= parent.lastLineTime - 1.5 ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                            }
                        }

                        onMovementStarted: {
                            smoothRecenterAnim.stop();
                            root.followPlayback = false;
                            userScrollTimer.stop();
                        }
                        onMovementEnded: {
                            smoothRecenterAnim.stop();
                            root.followPlayback = false;
                            userScrollTimer.restart();
                        }
                        onDragStarted: {
                            smoothRecenterAnim.stop();
                            root.followPlayback = false;
                            userScrollTimer.stop();
                        }
                        onDragEnded: {
                            smoothRecenterAnim.stop();
                            root.followPlayback = false;
                            userScrollTimer.restart();
                        }
                        onFlickStarted: {
                            smoothRecenterAnim.stop();
                            root.followPlayback = false;
                            userScrollTimer.stop();
                        }
                        onFlickEnded: {
                            smoothRecenterAnim.stop();
                            root.followPlayback = false;
                            userScrollTimer.restart();
                        }


                        delegate: Item {
                            id: lyricRow
                            width: Math.max(100, lyricsView.width - 24)
                            height: isDuetInterlude ? (isCurrent ? 48 : 0) : Math.max(48, lyricContentItem.implicitHeight + 16)
                            visible: isDuetInterlude ? (height > 0.5) : true
                            clip: isDuetInterlude && height < 47.5

                            readonly property int signedDist: {
                                if (root.currentLyricIndex < 0) return index - root.currentLyricIndex;
                                if (index < root.anchorLyricIndex) return index - root.anchorLyricIndex;
                                if (index > root.currentLyricIndex) return index - root.currentLyricIndex;
                                return 0;
                            }
                            readonly property int dist: Math.abs(signedDist)
                            // 1:1 Mochy-Music multi-active range: All lines in [anchorLyricIndex .. currentLyricIndex] are active simultaneously
                            readonly property bool isCurrent: dist === 0
                            readonly property real lineStartTime: (modelData && modelData.time !== undefined) ? modelData.time : 0.0
                            readonly property real lineEndTime: (modelData && modelData.endTime && modelData.endTime > lineStartTime)
                                ? modelData.endTime
                                : ((index + 1 < root.activeLyrics.length) ? root.activeLyrics[index + 1].time : (lineStartTime + 5.0))
                            readonly property real duration: Math.max(0.6, lineEndTime - lineStartTime)
                            readonly property real lineProgress: isCurrent ? Math.min(1.0, Math.max(0.0, (root.currentTime - lineStartTime) / duration)) : 0.0

                            // Backing vocal separation (1:1 Mochy-Music splitBackingVocal)
                            readonly property var lineParts: root.splitBackingVocal(modelData ? (modelData.text || "") : "", (modelData && modelData.words) ? modelData.words : null)
                            readonly property string leadText: lineParts ? lineParts.lead : (modelData ? (modelData.text || "") : "")
                            readonly property var leadWords: lineParts ? lineParts.leadWords : ((modelData && modelData.words) ? modelData.words : [])
                            readonly property string backingText: lineParts ? lineParts.backing : ""
                            readonly property var backingWords: lineParts ? lineParts.backingWords : []
                            readonly property bool hasBackingVocal: !!backingText

                            // isHovered: chỉ TRUE khi đang NHẤN GIỮ chuột trái (pressed), KHÔNG phải hover.
                            readonly property bool isHovered: rowMouse.pressed && !isCurrent

                            readonly property bool isPlainLine: !modelData.hasWords || modelData.isSynthetic || !leadWords || leadWords.length === 0
                            readonly property real targetBlur: (isCurrent || lyricsView.isUserScrolling || isHovered) ? 0.0 : (dist === 1 ? 0.20 : (dist === 2 ? 0.42 : (dist === 3 ? 0.65 : 0.85)))

                            // 1:1 Mochy-Music state scale & alpha transitions (LyricsGlowLine.kt)
                            // Strictly NO dynamic font resizing (Footgun #217: causes layout reflows and stutter)
                            readonly property real restingAlpha: isCurrent ? 1.0 : (lyricsView.isUserScrolling ? 0.85 : (isHovered ? 0.90 : (signedDist < 0 ? 0.24 : (dist === 1 ? 0.50 : 0.30))))
                            readonly property real restingScale: isPlainLine ? 1.0 : (isCurrent ? 1.06 : (signedDist < 0 ? 0.93 : (dist === 1 ? 0.98 : 0.93)))

                            // Duet vocal layout & agent classification (1:1 Mochy-Music & Apple Music)
                            readonly property bool isDuetInterlude: !!(modelData && modelData.isInterlude)
                            readonly property var nextLyricEntry: (isDuetInterlude && (index + 1 < root.activeLyrics.length)) ? root.activeLyrics[index + 1] : null
                            readonly property string effectiveAgent: isDuetInterlude ? (nextLyricEntry ? (nextLyricEntry.agent || "v1") : "v1") : (modelData ? (modelData.agent || "v1") : "v1")
                            readonly property bool isBackgroundVocal: !!(modelData && modelData.isBackground)
                            readonly property bool isEnsembleVoice: root.hasDuetVoices && ((effectiveAgent === "v1000" || effectiveAgent === "v3") || (isBackgroundVocal && !isDuetInterlude))
                            readonly property bool isAnsweringVoice: root.hasDuetVoices && !isEnsembleVoice && (effectiveAgent === "v2" || (effectiveAgent && effectiveAgent.indexOf("v2") === 0))

                            opacity: isDuetInterlude ? (isCurrent ? 1.0 : 0.0) : restingAlpha
                            transformOrigin: lyricRow.isAnsweringVoice ? Item.Right : (lyricRow.isEnsembleVoice ? Item.Center : Item.Left)
                            scale: restingScale

                            Behavior on height {
                                enabled: lyricRow.isDuetInterlude
                                NumberAnimation {
                                    duration: 950
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.42, 0.0, 0.16, 1.0, 1.0, 1.0]
                                }
                            }
                            Behavior on scale {
                                NumberAnimation {
                                    duration: 950
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.42, 0.0, 0.16, 1.0, 1.0, 1.0]
                                }
                            }
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 850
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.42, 0.0, 0.16, 1.0, 1.0, 1.0]
                                }
                            }

                            // 1:1 Mochy-Music / Apple Music Camera DoF Optical Blur (LyricsScreen.kt LineLook)
                            // Continuously blurs all distant lines (dist >= 1) with zero pop-back to sharp text.
                            layer.enabled: !lyricsView.isUserScrolling && !lyricRow.isHovered && (lyricRow.dist >= 1) && !lyricRow.isDuetInterlude
                            layer.effect: MultiEffect {
                                blurEnabled: true
                                blur: lyricRow.dist === 1 ? 0.35 : 0.75
                                blurMax: 16
                                autoPaddingEnabled: true
                            }


                            Column {
                                id: lyricContentItem
                                width: parent.width
                                anchors.top: parent.top
                                anchors.topMargin: lyricRow.isDuetInterlude ? 10 : 8
                                spacing: 3

                                Item {
                                    width: parent.width
                                    height: implicitHeight
                                    implicitHeight: lyricRow.isDuetInterlude ? 28 : ((lyricRow.leadText.length === 0) ? 0 : Math.max(36, (appleMusicFlowLoader.visible && appleMusicFlowLoader.item)
                                        ? appleMusicFlowLoader.item.implicitHeight
                                        : staticLineTxt.implicitHeight))
                                    visible: lyricRow.isDuetInterlude ? (lyricRow.height > 0.5) : (lyricRow.leadText.length > 0)

                                    // 1. SimpMusic / Apple Music Interlude Countdown Beads (• • •) (1:1 Mochy-Music LyricsInterludeDots.kt)
                                    // Dynamic Lifecycle: Grows on spring/bezier when gap begins, collapses to 0px in step with recenter scroll!
                                    Row {
                                        id: interludeBeadsRow
                                        visible: !!(modelData && modelData.isInterlude) && (lyricRow.height > 0.5)
                                        spacing: 16
                                        anchors.left: (!lyricRow.isAnsweringVoice && !lyricRow.isEnsembleVoice) ? parent.left : undefined
                                        anchors.leftMargin: 0
                                        anchors.right: lyricRow.isAnsweringVoice ? parent.right : undefined
                                        anchors.rightMargin: 0
                                        anchors.horizontalCenter: lyricRow.isEnsembleVoice ? parent.horizontalCenter : undefined
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

                                        // Finale Swell (at 88% of gap): All 3 dots swell together before the next line starts
                                        readonly property real finaleNow: (gapProgress >= 0.88) ? smoothstep((gapProgress - 0.88) / 0.12) : 0.0

                                        Repeater {
                                            model: 3

                                            delegate: Item {
                                                id: dotItem
                                                width: 10
                                                height: 10

                                                readonly property real sliceStart: index / 3.0
                                                // DotFadeFraction = 0.55 in Mochy: How long a dot takes from unlit to lit
                                                readonly property real within: (interludeBeadsRow.gapProgress - sliceStart) * 3.0 / 0.55
                                                readonly property real fill: interludeBeadsRow.smoothstep(within)

                                                // Glow rides the fill up while lighting, then lets go slowly once lit (flare, not constant halo)
                                                readonly property real litAt: sliceStart + 0.55 / 3.0
                                                readonly property real glow: (interludeBeadsRow.gapProgress < litAt)
                                                    ? fill
                                                    : Math.exp(-((interludeBeadsRow.gapProgress - litAt) * interludeBeadsRow.gapSpan) / 0.9)
                                                readonly property real effectiveGlow: Math.max(glow, Math.sin(Math.PI * interludeBeadsRow.finaleNow) * 0.7)

                                                // Stagger pop-in when row becomes active
                                                property real pop: lyricRow.isCurrent ? 1.0 : 0.0
                                                Behavior on pop {
                                                    NumberAnimation {
                                                        duration: 320
                                                        easing.type: Easing.OutBack
                                                    }
                                                }

                                                // Scale: RestScale(0.8) + (LitScale(1.1) - RestScale(0.8)) * fill + 0.14 * finaleNow
                                                scale: (0.8 + 0.3 * fill + 0.14 * interludeBeadsRow.finaleNow) * pop
                                                // Alpha: RestAlpha(0.3) + (1.0 - RestAlpha(0.3)) * max(fill, finaleNow)
                                                opacity: (0.3 + 0.7 * Math.max(fill, interludeBeadsRow.finaleNow)) * pop

                                                // Idle bobbing: one slow breath up and down (BobPeriodMs = 2600ms, BobHeight = 1.8px, BobPhaseStep = 0.9)
                                                readonly property real bobPhase: (root.currentTime / 2.6) * 2.0 * Math.PI - index * 0.9
                                                readonly property real bobY: lyricRow.isCurrent ? (Math.sin(bobPhase) * 1.8) : 0.0

                                                transform: Translate {
                                                    y: dotItem.bobY
                                                }

                                                // Layer 1: Perfect 360-degree Organic Radial Halo (Zero FBO truncation, zero box artifacts)
                                                Image {
                                                    id: auraImg
                                                    source: "file://" + root.appDir + "/assets/icons/dot-radial-glow.svg"
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
                                                    colorizationColor: root.accentColor || "#38bdf8"
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

                                    // 2. Apple Music Word Flow: Progressive character sweep + MultiEffect Gaussian bloom
                                    // Active only on current/adjacent line and only visible for the current singing line
                                    Loader {
                                        id: appleMusicFlowLoader
                                        active: !interludeBeadsRow.visible && lyricRow.dist <= 1 && modelData.hasWords && !modelData.isSynthetic && lyricRow.leadWords && lyricRow.leadWords.length > 0
                                        visible: active && (lyricRow.isCurrent ||
                                                 (lyricRow.signedDist === -1 && appleMusicFlowLoader.item !== null && appleMusicFlowLoader.item.hasActiveHeldWord))
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        sourceComponent: Component {
                                            AppleMusicWordFlow {
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                words: (modelData.hasWords && !modelData.isSynthetic && lyricRow.leadWords) ? lyricRow.leadWords : []
                                                currentTime: root.currentTime
                                                isLineActive: lyricRow.isCurrent
                                                fontSize: 28
                                                accentColor: "#ffffff"
                                                isAnsweringVoice: lyricRow.isAnsweringVoice
                                                isEnsembleVoice: lyricRow.isEnsembleVoice
                                            }
                                        }
                                    }

                                    // 3. Unified Static Typography: Used for plain LRC lines and distant unmaterialized lines
                                    Text {
                                        id: staticLineTxt
                                        visible: !interludeBeadsRow.visible && !appleMusicFlowLoader.visible && lyricRow.leadText.length > 0
                                        anchors.left: (!lyricRow.isAnsweringVoice && !lyricRow.isEnsembleVoice) ? parent.left : undefined
                                        anchors.right: lyricRow.isAnsweringVoice ? parent.right : undefined
                                        anchors.horizontalCenter: lyricRow.isEnsembleVoice ? parent.horizontalCenter : undefined
                                        width: Math.min(parent.width * (lyricRow.isAnsweringVoice ? 0.82 : 0.88), implicitWidth)
                                        horizontalAlignment: lyricRow.isAnsweringVoice ? Text.AlignRight : (lyricRow.isEnsembleVoice ? Text.AlignHCenter : Text.AlignLeft)
                                        textFormat: Text.PlainText
                                        text: lyricRow.leadText
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 28
                                        font.weight: Font.Bold
                                        font.italic: lyricRow.isBackgroundVocal
                                        color: "#ffffff"
                                        wrapMode: Text.Wrap
                                        lineHeight: 1.28
                                    }
                                }

                                // 1:1 Mochy-Music Backing Vocal Line: expands & collapses with smoothstep Hermite curve
                                BackingVocalLine {
                                    id: backingVocalLine
                                    visible: lyricRow.hasBackingVocal && (smoothExpand > 0.001)
                                    text: lyricRow.backingText
                                    words: lyricRow.backingWords
                                    currentTime: root.currentTime
                                    lineIsActive: lyricRow.isCurrent
                                    slide: lyricRow.leadText.length > 0
                                    isAnsweringVoice: lyricRow.isAnsweringVoice
                                    isEnsembleVoice: lyricRow.isEnsembleVoice
                                }


                                // Secondary Romanization Row (Romaji / Romaja / Pinyin)
                                Text {
                                    id: romanizedLineTxt
                                    visible: !modelData.isInterlude && root.lyricsRomanizationEnabled && !!(modelData && modelData.romanized && modelData.romanized.trim() !== "")
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
                                    color: lyricRow.isCurrent ? Qt.rgba(255, 255, 255, 0.82) : Qt.rgba(196, 200, 212, 0.50)
                                    wrapMode: Text.Wrap
                                    lineHeight: 1.18

                                    Behavior on color {
                                        ColorAnimation { duration: 180 }
                                    }
                                }
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData && modelData.time !== undefined) {
                                        root.seekRequested(modelData.time);
                                        root.followPlayback = true;
                                        userScrollTimer.stop();
                                        Qt.callLater(function() {
                                            root.recenterToCurrentLyric(true);
                                        });
                                    }
                                }
                            }
                        }
                    }

                    ShapeLoader {
                        anchors.centerIn: parent
                        visible: root.isLoadingLyrics && !root.hasLyrics
                        size: 52
                        color: Qt.rgba(1, 1, 1, 0.85)
                    }

                    EmptyState {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 40, 340)
                        visible: root.track !== null && !root.hasLyrics && !root.isLoadingLyrics
                        icon: "../assets/icons/material/ms-lyrics-fill.svg"
                        shape: "cookie"
                        accentColor: root.accentColor
                        title: I18n.pick("lyrics.none", ["Không có lời bài hát", "Lời đi chơi chưa về", "Bài này chưa ai chép lời", "Không lời, cứ ngân nga theo", "Lời trốn mất rồi", "Không có lời thì tự bịa lời đi", "Chỉ có nhạc thôi, thả hồn đi"], ["Lyrics unavailable", "The lyrics went out and never came back", "Nobody wrote these lyrics down yet", "No words, just hum along", "The lyrics are hiding", "No lyrics? Make some up", "Just the music, let it carry you"])
                        description: I18n.tr("Chưa tìm thấy lời cho bài này.", "We couldn't find lyrics for this song.")
                    }
                }

                // =============================================================
                // TAB 3 VIEW: SLEEP TIMER
                // =============================================================
                SleepTimerPanel {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    accentColor: root.accentColor
                    isActive: root.isSleepTimerActive
                    remainingSeconds: root.sleepTimerRemainingSeconds
                    totalSeconds: root.sleepTimerTotalSeconds
                    mode: root.sleepTimerMode
                    fade: root.sleepTimerFade
                    onStartRequested: (seconds, fade) => root.sleepTimerStartRequested(seconds, fade)
                    onEndOfTrackRequested: root.sleepTimerEndOfTrackRequested()
                    onCancelRequested: root.sleepTimerCancelRequested()
                }
            }
        }
    }

    // =========================================================================
    // TOP CHROME: collapse (top-left) + mode switcher pill (top-right, Swiftify-like)
    // =========================================================================

    Rectangle {
        id: collapseBtn
        z: 5
        visible: !root.chromeInNotch
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: root.width >= 1200 ? 40 : 18
        anchors.topMargin: 14
        width: 40; height: 40; radius: 20
        color: Qt.rgba(1, 1, 1, collapseH.hovered ? 0.16 : 0.08)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.10)
        Behavior on color { ColorAnimation { duration: 140 } }
        HoverHandler { id: collapseH }
        ToolTip.visible: collapseH.hovered
        ToolTip.text: I18n.tr("Thu nhỏ", "Collapse")
        ToolTip.delay: 400
        AppIcon {
            anchors.centerIn: parent
            source: "../assets/icons/material/ms-expand_more.svg"
            iconSize: 24
            color: "#ffffff"
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.collapseRequested() }
    }

    Rectangle {
        id: modeSwitcher
        z: 5
        readonly property bool inNotch: root.chromeInNotch && root.notchHost !== null
        parent: inNotch ? root.notchHost : root
        anchors.right: inNotch ? undefined : parent.right
        anchors.top: inNotch ? undefined : parent.top
        anchors.rightMargin: root.width >= 1200 ? 40 : 18
        anchors.topMargin: 14
        x: 0; y: 0
        width: modeRow.implicitWidth + (inNotch ? 0 : 10)
        height: inNotch ? 26 : 46
        radius: height / 2
        // Swiftify-like frosted pill: light translucent fill + hairline, no dark accent tint;
        // in the notch the notch's own glass is the pill
        color: inNotch ? "transparent" : Qt.rgba(1, 1, 1, 0.10)
        border.width: inNotch ? 0 : 1
        border.color: Qt.rgba(1, 1, 1, 0.14)
        Row {
            id: modeRow
            anchors.centerIn: parent
            spacing: modeSwitcher.inNotch ? 2 : 4
            NowPlayingModeButton {
                compact: modeSwitcher.inNotch
                icon: "../assets/icons/material/ms-image-fill.svg"; tip: I18n.tr("Ảnh bìa", "Artwork")
                active: root.activeTab === "artwork"; accent: root.accentColor
                onClicked: root.activeTab = "artwork"
            }
            NowPlayingModeButton {
                compact: modeSwitcher.inNotch
                icon: "../assets/icons/material/ms-lyrics-fill.svg"; tip: I18n.tr("Lời bài hát", "Lyrics")
                active: root.activeTab === "lyrics"; accent: root.accentColor
                onClicked: root.activeTab = "lyrics"
            }
            NowPlayingModeButton {
                compact: modeSwitcher.inNotch
                icon: "../assets/icons/material/ms-queue_music.svg"; tip: I18n.tr("Tiếp theo", "Up next")
                active: root.activeTab === "up_next"; accent: root.accentColor
                onClicked: root.activeTab = "up_next"
            }
            NowPlayingModeButton {
                compact: modeSwitcher.inNotch
                id: sleepModeBtn
                icon: "../assets/icons/material/ms-bedtime.svg"
                badge: root.isSleepTimerActive
                tip: {
                    if (!root.isSleepTimerActive) return I18n.tr("Hẹn giờ tắt nhạc", "Sleep timer");
                    var sec = Math.max(0, root.sleepTimerRemainingSeconds);
                    if (sec <= 0) return I18n.tr("Tắt sau khi hết bài", "Stops after this track");
                    var m = Math.floor(sec / 60), r = sec % 60;
                    return I18n.tr("Tắt nhạc sau ", "Stops in ") + m + ":" + (r < 10 ? "0" : "") + r;
                }
                active: root.activeTab === "sleep"; accent: root.accentColor
                onClicked: root.activeTab = "sleep"
            }
        }
    }
}


