import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Io
import "."

Item {
    id: root

    property var track: null
    property real currentTime: 0.0
    property real totalDuration: 1.0
    property bool isPlaying: false
    property var queueTracks: []
    property string playingPlaylistTitle: I18n.tr("Hàng đợi", "Queue")
    property color accentColor: (typeof win !== "undefined" && win.accentColor) ? win.accentColor : Theme.accent
    property Item backgroundSourceItem: null
    property string appDir: (typeof win !== "undefined" && win && win.appDir) ? win.appDir : (Quickshell.env("NUTSTY_APP_DIR") || (Quickshell.env("HOME") + "/Applications/FrostifyLocal"))

    property string activeTab: "lyrics" // "up_next" | "lyrics" | "related"
    onActiveTabChanged: {
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
    function sanitizeWordList(wList) {
        if (!wList || wList.length === 0) return [];
        var res = [];
        var lastStart = -1.0;
        for (var i = 0; i < wList.length; i++) {
            var w = wList[i];
            var s = (w.start !== undefined) ? Number(w.start) : 0.0;
            var e = (w.end !== undefined) ? Number(w.end) : (s + 0.2);
            if (lastStart >= 0 && s < lastStart) {
                s = lastStart;
            }
            if (e < s + 0.05) {
                e = s + 0.05;
            }
            lastStart = s;
            res.push({
                text: w.text || "",
                start: s,
                end: e,
                duration: Math.max(0.05, e - s),
                hasSpace: (w.hasSpace !== false),
                isHeld: !!w.isHeld
            });
        }
        return res;
    }

    // 1:1 Mochy-Music splitBackingVocal: separates lead text and bracketed backing vocal
    function splitBackingVocal(text, words) {
        if (!text || (text.indexOf('(') < 0 && text.indexOf('[') < 0)) {
            return { lead: text || "", backing: "", leadWords: sanitizeWordList(words || []), backingWords: [] };
        }

        var leadChars = [];
        var backingChars = [];
        var inBracket = new Array(text.length);
        var depth = 0;

        for (var i = 0; i < text.length; i++) {
            var ch = text.charAt(i);
            if (ch === '(' || ch === '[') {
                depth++;
                inBracket[i] = true;
            } else if ((ch === ')' || ch === ']') && depth > 0) {
                depth--;
                inBracket[i] = true;
                if (depth === 0) backingChars.push(' ');
            } else if (depth > 0) {
                inBracket[i] = true;
                backingChars.push(ch);
            } else {
                inBracket[i] = false;
                leadChars.push(ch);
            }
        }

        if (depth !== 0) {
            return { lead: text, backing: "", leadWords: sanitizeWordList(words || []), backingWords: [] };
        }

        var leadText = leadChars.join('').replace(/\s{2,}/g, ' ').trim();
        var backingText = backingChars.join('').replace(/\s{2,}/g, ' ').trim();

        if (!backingText) {
            return { lead: text, backing: "", leadWords: sanitizeWordList(words || []), backingWords: [] };
        }

        var leadWords = [];
        var backingWords = [];
        if (words && words.length > 0) {
            var searchFrom = 0;
            for (var j = 0; j < words.length; j++) {
                var w = words[j];
                var trimmed = (w.text || "").trim();
                if (!trimmed) continue;
                var start = text.indexOf(trimmed, searchFrom);
                if (start < 0) continue;
                searchFrom = start + trimmed.length;

                var bare = (w.text || "").replace(/[\(\)\[\]]/g, '');
                var cleanWord = {
                    text: bare,
                    start: w.start,
                    end: w.end,
                    duration: w.duration,
                    hasSpace: w.hasSpace,
                    isHeld: w.isHeld
                };

                if (start < inBracket.length && inBracket[start]) {
                    backingWords.push(cleanWord);
                } else {
                    leadWords.push(cleanWord);
                }
            }
        }

        return {
            lead: leadText,
            backing: backingText,
            leadWords: sanitizeWordList(leadWords),
            backingWords: sanitizeWordList(backingWords)
        };
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

    readonly property string audioQualityText: {
        if (!root.track) return "";
        if (root.audioSpecs) {
            var c = (root.audioSpecs.codec || "AAC").toUpperCase();
            var b = root.audioSpecs.bitrate_str || "";
            if (!b && root.audioSpecs.bitrate) b = root.audioSpecs.bitrate + " kbps";
            if (c === "FLAC") {
                return "FLAC • " + (root.audioSpecs.sample_rate_str || "Lossless");
            }
            if (b) return c + " • " + b;
            return c;
        }
        if (root.track.path && (root.track.path.endsWith(".flac") || root.track.path.endsWith(".FLAC"))) return "FLAC • Lossless";
        if (root.track.path && (root.track.path.endsWith(".mp3") || root.track.path.endsWith(".MP3"))) return "MP3 • 320 kbps";
        return "AAC • 128 kbps";
    }

    readonly property string trackMetaSummary: {
        if (!root.track) return "";
        var parts = [];
        if (root.audioQualityText && root.audioQualityText.trim() !== "") {
            parts.push(root.audioQualityText.trim());
        }
        if (root.hasLyrics) {
            var rawSrc = root.lyricsSource;
            if (!rawSrc) {
                rawSrc = root.isLyricsWordByWord ? "Spotify" : "LRCLIB";
            }
            var srcName = formatLyricSourceName(rawSrc);
            if (srcName) {
                if (root.isLyricsWordByWord) {
                    parts.push(I18n.tr("Từng từ một được cung cấp bởi ", "Word-by-word lyrics provided by ") + srcName);
                } else {
                    parts.push(I18n.tr("Lời bài hát được cung cấp bởi ", "Lyrics provided by ") + srcName);
                }
            }
        }
        return parts.join(" • ");
    }

    property var relatedData: null
    property bool isLoadingRelated: false
    property string lastRelatedTrackId: ""

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
    signal playlistSelected(var pl)
    signal artistSelected(string name, string channelId)
    signal collapseRequested()
    signal rateSongRequested(string videoId, string rating)
    signal songDisliked(var trk)
    signal downloadRequested(var trk)
    signal queueUpdated(var newTracks)
    signal exitListeningAlongRequested()

    property var listeningAlongFriend: null

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
        fetchRelatedContent();
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

    function resolveCoverArt(trk) {
        if (!trk) {
            root.resolvedSquareImage = "";
            root.resolvedIsSquare = false;
            root.squareImageFailed = false;
            root.highResFailed = false;
            root.lastResolvedCoverKey = "";
            return;
        }

        var tTitle = (trk.title || trk.name || "").trim();
        var tArtist = (trk.artist || "").trim();
        var tVid = trk.videoId || (trk.path && trk.path.startsWith("ytdl://") ? trk.path.replace("ytdl://", "") : "");
        var tImg = root.getRawTrackImage(trk);

        // If videoId is missing, extract it directly from YouTube image URL
        if (!tVid && tImg && tImg.indexOf("i.ytimg.com") !== -1) {
            var m = tImg.match(/vi\/([a-zA-Z0-9_-]{11})\//);
            if (m && m[1]) {
                tVid = m[1];
            }
        }

        var coverKey = (tVid ? tVid : (tTitle + "_" + tArtist));

        if (root.lastResolvedCoverKey === coverKey && (root.resolvedSquareImage !== "" || root.resolvedIsSquare)) {
            return;
        }
        root.lastResolvedCoverKey = coverKey;
        root.squareImageFailed = false;
        root.highResFailed = false;

        // Tier 0: Already native square Google CDN image
        if (tImg && (tImg.indexOf("googleusercontent.com") !== -1 || tImg.indexOf("ggpht.com") !== -1)) {
            var up = root.getHighResImage(tImg);
            root.resolvedSquareImage = up;
            root.resolvedIsSquare = true;
            root.squareCoverResolved(up, true);
            return;
        }

        // Local embedded artwork file (extracted jpg/png in local filesystem)
        if (tImg && (tImg.startsWith("/") || tImg.startsWith("file://"))) {
            root.resolvedSquareImage = tImg;
            root.resolvedIsSquare = true;
            root.squareCoverResolved(tImg, true);
            return;
        }

        // Tier 1: Query resident HTTP daemon /api/resolve_cover for official 1:1 square artwork
        var apiUrl = "http://127.0.0.1:17890/api/resolve_cover?" +
                     "title=" + encodeURIComponent(tTitle) +
                     "&artist=" + encodeURIComponent(tArtist) +
                     "&videoId=" + encodeURIComponent(tVid) +
                     "&current=" + encodeURIComponent(tImg);

        var xhr = new XMLHttpRequest();
        xhr.open("GET", apiUrl);
        xhr.timeout = 8000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var res = JSON.parse(xhr.responseText);
                        if (root.lastResolvedCoverKey === coverKey) {
                            if (res && res.url && res.is_square === true) {
                                var resUrl = root.getHighResImage(res.url);
                                root.resolvedSquareImage = resUrl;
                                root.resolvedIsSquare = true;
                                root.squareCoverResolved(resUrl, true);
                            } else if (res && res.url) {
                                var fallbackUrl = root.getHighResImage(res.url);
                                root.resolvedSquareImage = fallbackUrl;
                                root.resolvedIsSquare = false;
                                root.squareCoverResolved(fallbackUrl, false);
                            } else {
                                root.resolvedSquareImage = "";
                                root.resolvedIsSquare = false;
                                root.squareCoverResolved(tImg, false);
                            }
                        }
                    } catch (e) {
                        if (root.lastResolvedCoverKey === coverKey) {
                            root.resolvedSquareImage = "";
                            root.resolvedIsSquare = false;
                            root.squareCoverResolved(tImg, false);
                        }
                    }
                } else {
                    if (root.lastResolvedCoverKey === coverKey) {
                        root.resolvedSquareImage = "";
                        root.resolvedIsSquare = false;
                        root.squareCoverResolved(tImg, false);
                    }
                }
            }
        };
        xhr.ontimeout = function() {
            if (root.lastResolvedCoverKey === coverKey) {
                root.resolvedSquareImage = "";
                root.resolvedIsSquare = false;
                root.squareCoverResolved(tImg, false);
            }
        };
        xhr.send();
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
            var songDur = root.totalDuration > 1 ? String(Math.round(root.totalDuration)) : "";
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
            if (activeTab === "lyrics") activeTab = "up_next";
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
                        if (root.activeTab !== "up_next" && root.activeTab !== "related") {
                            root.activeTab = "lyrics";
                        }
                    } else {
                        root.activeLyrics = [];
                        root.hasLyrics = false;
                        root.lyricsSource = "";
                        root.isLoadingLyrics = false;
                        if (root.activeTab === "lyrics") {
                            root.activeTab = "up_next";
                        }
                    }
                } catch (e) {
                    root.activeLyrics = [];
                    root.hasLyrics = false;
                    root.lyricsSource = "";
                    root.isLoadingLyrics = false;
                    if (root.activeTab === "lyrics") {
                        root.activeTab = "up_next";
                    }
                }
            }
        }
        onExited: (code, status) => {
            root.isLoadingLyrics = false;
            if (!root.hasLyrics && root.activeTab === "lyrics") {
                root.activeTab = "up_next";
            }
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


    function fetchRelatedContent() {
        if (!track) return;
        var vid = track.videoId || "";
        var title = track.title || track.name || "";
        var artist = track.artist || "";
        var tId = vid || (title + "_" + artist);
        if (tId === lastRelatedTrackId && relatedData) return;

        lastRelatedTrackId = tId;
        isLoadingRelated = true;
        relatedProc.running = false;
        relatedProc.command = [
            "python3", "-u",
            root.appDir + "/backend/ytmusic_helper.py",
            "song_related", vid, title, artist
        ];
        relatedProc.running = true;
    }

    Process {
        id: relatedProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (!data || data.trim() === "") return;
                try {
                    var parsed = JSON.parse(data);
                    root.relatedData = parsed;
                    root.isLoadingRelated = false;
                } catch (e) {
                    root.isLoadingRelated = false;
                }
            }
        }
        onExited: (code, status) => {
            root.isLoadingRelated = false;
        }
    }

    function fetchMoodChips() {
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
    // MAIN 2-COLUMN SPLIT SCREEN (50% Left Artwork/Video | 50% Right Tabs)
    // =========================================================================
    RowLayout {
        anchors.fill: parent
        z: 1
        anchors.leftMargin: root.width >= 1200 ? 48 : 24
        anchors.rightMargin: root.width >= 1200 ? 48 : 24
        anchors.topMargin: 12
        anchors.bottomMargin: 84
        spacing: root.width >= 1200 ? 48 : 28

        // =====================================================================
        // COLUMN 1: LEFT AREA (Mode Switcher + Big Artwork / Video + Song Title)
        // =====================================================================
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: parent.width * 0.46
            spacing: 16
            Layout.alignment: Qt.AlignHCenter

            // Central Media Display: Big Square Artwork (Clean HD Retina)
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignCenter

                Item {
                    id: coverArtworkWrapper
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 24, Math.min(parent.height - 24, 460))
                    height: width

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
            }

            // 3. Track Details Row (Title, Artist, Like / Action Buttons)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: 460
                Layout.alignment: Qt.AlignHCenter
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: root.track ? (root.track.title || root.track.name || "") : I18n.tr("Chưa chọn bài hát", "No track playing")
                    font.family: Theme.fontFamily
                    font.pixelSize: 22
                    font.bold: true
                    color: "#ffffff"
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: root.track ? (root.track.artist || I18n.tr("Nghệ sĩ chưa rõ", "Unknown Artist")) : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
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

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 14

                        // 1. Like Pure Frameless Button
                        Rectangle {
                            id: likeBtn
                            width: 36; height: 36
                            radius: 18
                            color: likeH.hovered ? Qt.rgba(1.0, 1.0, 1.0, 0.08) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            HoverHandler { id: likeH }

                            AppIcon {
                                anchors.centerIn: parent
                                source: "../assets/icons/thumb-up-symbolic.svg"
                                iconSize: 18
                                scale: likeH.hovered ? 1.10 : 1.0
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                                color: root.currentLikeStatus === "LIKE" ? root.accentColor : (likeH.hovered ? "#ffffff" : Theme.textSecondary)
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleLike()
                            }
                        }

                        // 2. Dislike Pure Frameless Button
                        Rectangle {
                            id: dislikeBtn
                            width: 36; height: 36
                            radius: 18
                            color: dislikeH.hovered ? Qt.rgba(1.0, 1.0, 1.0, 0.08) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            HoverHandler { id: dislikeH }

                            AppIcon {
                                anchors.centerIn: parent
                                source: "../assets/icons/thumb-down-symbolic.svg"
                                iconSize: 18
                                scale: dislikeH.hovered ? 1.10 : 1.0
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                                color: root.currentLikeStatus === "DISLIKE" ? "#ff5252" : (dislikeH.hovered ? "#ffffff" : Theme.textSecondary)
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.dislikeCurrentTrack()
                            }
                        }

                        // 3. Download Pure Frameless Button
                        Rectangle {
                            id: dlBtn
                            width: 36; height: 36
                            radius: 18
                            color: dlH.hovered ? Qt.rgba(1.0, 1.0, 1.0, 0.08) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            property string vid: {
                                if (!root.track) return "";
                                if (root.track.videoId) return root.track.videoId;
                                if (root.track.path && root.track.path.startsWith("ytdl://")) return root.track.path.replace("ytdl://", "");
                                return "";
                            }
                            property int dlRev: (typeof downloadManager !== "undefined" && downloadManager) ? downloadManager.revision : 0
                            property bool isDl: (dlRev >= 0 && typeof downloadManager !== "undefined" && downloadManager && vid) ? Boolean(downloadManager.isDownloading(vid)) : false
                            property real dlProg: (dlRev >= 0 && typeof downloadManager !== "undefined" && downloadManager && vid && downloadManager.getProgress(vid) !== undefined) ? downloadManager.getProgress(vid) : -1
                            property bool isDone: (dlRev >= 0 && typeof downloadManager !== "undefined" && downloadManager) ? Boolean(downloadManager.isDownloaded(vid, root.track)) : false

                            HoverHandler { id: dlH }

                            ToolTip.visible: dlH.hovered
                            ToolTip.text: parent.isDl
                                ? I18n.tr("Hủy tải xuống", "Cancel download")
                                : (parent.isDone
                                    ? I18n.tr("Xóa khỏi thư viện tải về", "Remove downloaded track")
                                    : I18n.tr("Tải bài hát", "Download track"))
                            ToolTip.delay: 350

                            DownloadingSpinner {
                                anchors.centerIn: parent
                                visible: parent.isDl
                                running: parent.isDl
                                iconSize: 18
                                progress: parent.dlProg
                                color: root.accentColor
                            }

                            AppIcon {
                                anchors.centerIn: parent
                                visible: !parent.isDl && parent.isDone
                                source: "../assets/icons/emblem-ok-symbolic.svg"
                                iconSize: 18
                                scale: dlH.hovered ? 1.10 : 1.0
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                                color: root.accentColor
                            }

                            AppIcon {
                                anchors.centerIn: parent
                                visible: !parent.isDl && !parent.isDone
                                source: "../assets/icons/download-symbolic.svg"
                                iconSize: 18
                                scale: dlH.hovered ? 1.10 : 1.0
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                                color: dlH.hovered ? "#ffffff" : Theme.textSecondary
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (parent.isDl) {
                                        if (typeof downloadManager !== "undefined" && downloadManager) {
                                            downloadManager.cancel(parent.vid);
                                        }
                                    } else if (parent.isDone) {
                                        if (typeof downloadManager !== "undefined" && downloadManager) {
                                            downloadManager.deleteDownloaded(parent.vid, root.track);
                                        }
                                    } else {
                                        root.downloadCurrentTrack();
                                    }
                                }
                            }
                        }

                        // 4. Plus (+) Add to Playlist / Queue Pure Frameless Button
                        Rectangle {
                            id: plusBtn
                            width: 36; height: 36
                            radius: 18
                            color: plusH.hovered ? Qt.rgba(1.0, 1.0, 1.0, 0.08) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            HoverHandler { id: plusH }

                            AppIcon {
                                anchors.centerIn: parent
                                source: "../assets/icons/list-add-symbolic.svg"
                                iconSize: 18
                                scale: plusH.hovered ? 1.10 : 1.0
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                                color: plusH.hovered ? "#ffffff" : Theme.textSecondary
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.track) {
                                        var pt = plusBtn.mapToItem(null, 0, plusBtn.height + 4);
                                        root.trackContextMenuRequested(root.track, pt.x, pt.y, false);
                                    }
                                }
                            }
                        }
                    }
                }

                // 3. Audio Quality & Lyrics Source Meta Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: root.track !== null && metaSummaryText.text.length > 0

                    Text {
                        id: metaSummaryText
                        Layout.fillWidth: true
                        text: root.trackMetaSummary
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        color: Qt.rgba(1.0, 1.0, 1.0, 0.45)
                        elide: Text.ElideRight
                    }
                }
            }

            Item { Layout.preferredHeight: 4 }
        }

        // =====================================================================
        // COLUMN 2: RIGHT AREA (Tabs Bar: [ UP NEXT | LYRICS | RELATED ])
        // =====================================================================
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: parent.width * 0.54
            spacing: 12

            // 1. YouTube Music Tab Switcher Bar
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 44

                Row {
                    id: tabsRow
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 28

                    // TAB 1: UP NEXT
                    Item {
                        id: upNextTabItem
                        height: 36
                        width: upNextTxt.implicitWidth + 8

                        Text {
                            id: upNextTxt
                            anchors.centerIn: parent
                            text: I18n.tr("TIẾP THEO", "UP NEXT")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            font.letterSpacing: 0.6
                            color: root.activeTab === "up_next" ? "#ffffff" : (upNextMouse.containsMouse ? "#ffffff" : Theme.textSecondary)
                        }

                        MouseArea {
                            id: upNextMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activeTab = "up_next"
                        }
                    }

                    // TAB 2: LYRICS
                    Item {
                        id: lyricsTabItem
                        height: 36
                        width: lyricsRow.implicitWidth + 8
                        opacity: root.hasLyrics ? 1.0 : (root.isLoadingLyrics ? 0.7 : 0.35)
                        enabled: root.hasLyrics || root.isLoadingLyrics

                        Row {
                            id: lyricsRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                id: lyricsTxt
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("LỜI BÀI HÁT", "LYRICS")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                font.letterSpacing: 0.6
                                color: root.activeTab === "lyrics" ? "#ffffff" : (lyricsMouse.containsMouse ? "#ffffff" : Theme.textSecondary)
                            }

                            CircularSpinner {
                                anchors.verticalCenter: parent.verticalCenter
                                size: 10
                                strokeWidth: 1.5
                                color: root.accentColor
                                running: root.isLoadingLyrics
                                visible: root.isLoadingLyrics
                            }
                        }

                        MouseArea {
                            id: lyricsMouse
                            anchors.fill: parent
                            hoverEnabled: root.hasLyrics || root.isLoadingLyrics
                            cursorShape: (root.hasLyrics || root.isLoadingLyrics) ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (root.hasLyrics || root.isLoadingLyrics) {
                                    root.activeTab = "lyrics";
                                }
                            }
                        }
                    }

                    // TAB 3: RELATED
                    Item {
                        id: relatedTabItem
                        height: 36
                        width: relatedTxt.implicitWidth + 8

                        Text {
                            id: relatedTxt
                            anchors.centerIn: parent
                            text: I18n.tr("LIÊN QUAN", "RELATED")
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            font.letterSpacing: 0.6
                            color: root.activeTab === "related" ? "#ffffff" : (relatedMouse.containsMouse ? "#ffffff" : Theme.textSecondary)
                        }

                        MouseArea {
                            id: relatedMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.activeTab = "related";
                                if (!root.relatedData) {
                                    root.fetchRelatedContent();
                                }
                            }
                        }
                    }
                }


                // Active Tab Sliding Indicator Bar
                Rectangle {
                    id: tabIndicator
                    anchors.bottom: parent.bottom
                    height: 2.5
                    radius: 1.25
                    color: root.accentColor

                    readonly property var currentTabObj: {
                        if (root.activeTab === "up_next") return upNextTabItem;
                        if (root.activeTab === "lyrics") return lyricsTabItem;
                        return relatedTabItem;
                    }

                    x: currentTabObj ? currentTabObj.x : 0
                    width: currentTabObj ? currentTabObj.width : 50

                    Behavior on color { ColorAnimation { duration: 450; easing.type: Easing.OutQuad } }
                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
            }

            // 2. Tab Content Stack: [ UP NEXT | LYRICS | RELATED ]
            StackLayout {
                id: tabContentStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.activeTab === "up_next" ? 0 : (root.activeTab === "lyrics" ? 1 : 2)

                // =============================================================
                // TAB 1 VIEW: UP NEXT (Playing Queue)
                // =============================================================
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: I18n.tr("Phát từ", "Playing from")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.textMuted
                                }

                                Text {
                                    text: root.playingPlaylistTitle || I18n.tr("Hàng đợi tự động", "Automix Queue")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                    font.bold: true
                                    color: "#ffffff"
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // Mood Filter Chips (YouTube Music Up Next Pills - Separated Capsules with Sliding Liquid Glass Lens)
                        Item {
                            id: moodChipsContainer
                            Layout.fillWidth: true
                            implicitHeight: (root.moodChips.length > 0 || root.isLoadingMoodChips) ? 38 : 0
                            visible: implicitHeight > 0

                            // Auto-scroll continuous timers
                            Timer {
                                id: leftScrollTimer
                                interval: 16
                                repeat: true
                                running: false
                                onTriggered: {
                                    moodFlickable.contentX = Math.max(0, moodFlickable.contentX - 6);
                                    if (moodFlickable.contentX <= 0) running = false;
                                }
                            }

                            Timer {
                                id: rightScrollTimer
                                interval: 16
                                repeat: true
                                running: false
                                onTriggered: {
                                    var maxScroll = Math.max(0, moodFlickable.contentWidth - moodFlickable.width);
                                    moodFlickable.contentX = Math.min(maxScroll, moodFlickable.contentX + 6);
                                    if (moodFlickable.contentX >= maxScroll) running = false;
                                }
                            }

                            // Horizontal Scrollable Chips
                            Flickable {
                                id: moodFlickable
                                anchors.fill: parent
                                contentWidth: moodChipsRow.width + 16
                                contentHeight: height
                                boundsBehavior: Flickable.StopAtBounds
                                flickableDirection: Flickable.HorizontalFlick
                                pixelAligned: true
                                clip: true

                                DragHandler {
                                    target: null
                                    xAxis.enabled: true
                                    yAxis.enabled: false
                                    cursorShape: Qt.OpenHandCursor
                                    property real startContentX: 0
                                    onActiveChanged: {
                                        if (active) {
                                            startContentX = moodFlickable.contentX;
                                        }
                                    }
                                    onTranslationChanged: {
                                        if (active) {
                                            var maxScroll = Math.max(0, moodFlickable.contentWidth - moodFlickable.width);
                                            moodFlickable.contentX = Math.max(0, Math.min(maxScroll, startContentX - translation.x));
                                        }
                                    }
                                }

                                WheelHandler {
                                    target: moodFlickable
                                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                    onWheel: event => {
                                        var delta = (event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x);
                                        moodFlickable.contentX = Math.max(0, Math.min(moodFlickable.contentWidth - moodFlickable.width, moodFlickable.contentX - delta));
                                    }
                                }

                                readonly property real accentLuminance: (0.299 * root.accentColor.r + 0.587 * root.accentColor.g + 0.114 * root.accentColor.b)

                                // Ambient drop shadow for the sliding active Keo 502 gel capsule
                                Rectangle {
                                    x: activeChipIndicator.x
                                    y: activeChipIndicator.y + 2
                                    width: activeChipIndicator.width
                                    height: activeChipIndicator.height
                                    radius: activeChipIndicator.radius
                                    color: "#50000000"
                                    visible: activeChipIndicator.width > 0
                                    z: 1
                                }

                                // Sliding Keo 502 Glossy Gel Capsule (Fluid Meniscus, Rich Solid-Glass Contrast, ZERO glare streaks!)
                                Rectangle {
                                    id: activeChipIndicator
                                    height: 28
                                    radius: 14
                                    y: (moodFlickable.height - height) / 2
                                    z: 2
                                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.90)
                                    border.color: Qt.rgba(root.accentColor.r * 1.15, root.accentColor.g * 1.15, root.accentColor.b * 1.15, 0.95)
                                    border.width: 1
                                    visible: width > 0

                                    // Inner Meniscus Specular Rim (Tension highlight without bleaching text)
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        radius: 13
                                        color: "transparent"
                                        border.color: Qt.rgba(1.0, 1.0, 1.0, moodFlickable.accentLuminance > 0.55 ? 0.35 : 0.22)
                                        border.width: 1
                                    }

                                    Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                                    Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Behavior on border.color { ColorAnimation { duration: 200 } }
                                }

                                // Separated Mood Chips Row
                                Row {
                                    id: moodChipsRow
                                    spacing: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    z: 5
                                    onWidthChanged: Qt.callLater(moodFlickable.updateActiveIndicator)

                                    Repeater {
                                        id: chipRepeater
                                        model: root.moodChips
                                        delegate: Item {
                                            id: chipItem
                                            height: 28
                                            width: chipLabel.implicitWidth + 24
                                            readonly property bool isSelected: index === root.selectedMoodIndex
                                            readonly property bool isHovered: chipMouse.containsMouse

                                            onXChanged: {
                                                if (isSelected) activeChipIndicator.x = chipItem.x;
                                            }
                                            onWidthChanged: {
                                                if (isSelected) activeChipIndicator.width = chipItem.width;
                                            }
                                            onIsSelectedChanged: {
                                                if (isSelected) {
                                                    activeChipIndicator.x = chipItem.x;
                                                    activeChipIndicator.width = chipItem.width;
                                                }
                                            }
                                            Component.onCompleted: {
                                                if (isSelected) {
                                                    activeChipIndicator.x = chipItem.x;
                                                    activeChipIndicator.width = chipItem.width;
                                                }
                                            }

                                            // Standalone Inactive Dark Glass Capsule (Zero white glare streaks, clean optical glass)
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 14
                                                color: chipItem.isHovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16) : Qt.rgba(1.0, 1.0, 1.0, 0.06)
                                                border.width: 1
                                                border.color: chipItem.isHovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35) : Qt.rgba(1.0, 1.0, 1.0, 0.10)
                                                opacity: chipItem.isSelected ? 0.0 : 1.0
                                                scale: (chipItem.isHovered && !chipItem.isSelected) ? 1.03 : 1.0

                                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                                Behavior on scale { NumberAnimation { duration: 120 } }
                                            }

                                            Text {
                                                id: chipLabel
                                                anchors.centerIn: parent
                                                text: I18n.formatMoodChipTitle(modelData.title || "")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                font.weight: chipItem.isSelected ? Font.Bold : Font.DemiBold
                                                color: chipItem.isSelected 
                                                       ? (moodFlickable.accentLuminance > 0.55 ? "#0f0f11" : "#ffffff") 
                                                       : (chipItem.isHovered ? "#ffffff" : Qt.rgba(1.0, 1.0, 1.0, 0.70))
                                                Behavior on color { ColorAnimation { duration: 120 } }
                                            }

                                            MouseArea {
                                                id: chipMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.selectMoodChip(index)
                                            }
                                        }
                                    }

                                    // Skeleton loading pills when fetching chips
                                    Repeater {
                                        model: (root.isLoadingMoodChips && root.moodChips.length === 0) ? [50, 75, 65, 80] : 0
                                        delegate: Rectangle {
                                            height: 28
                                            width: modelData + 20
                                            radius: 14
                                            color: Qt.rgba(1.0, 1.0, 1.0, 0.08)
                                            border.color: Qt.rgba(1.0, 1.0, 1.0, 0.06)
                                            border.width: 1

                                            SequentialAnimation on opacity {
                                                loops: Animation.Infinite
                                                running: root.visible && root.isLoadingMoodChips
                                                NumberAnimation { from: 0.35; to: 0.75; duration: 650; easing.type: Easing.InOutQuad }
                                                NumberAnimation { from: 0.75; to: 0.35; duration: 650; easing.type: Easing.InOutQuad }
                                            }
                                        }
                                    }
                                }

                                function updateActiveIndicator() {
                                    var itm = chipRepeater.itemAt(root.selectedMoodIndex);
                                    if (itm) {
                                        activeChipIndicator.x = itm.x;
                                        activeChipIndicator.width = itm.width;
                                        return;
                                    }
                                    for (var i = 0; i < chipRepeater.count; ++i) {
                                        var candidate = chipRepeater.itemAt(i);
                                        if (candidate && candidate.isSelected) {
                                            activeChipIndicator.x = candidate.x;
                                            activeChipIndicator.width = candidate.width;
                                            break;
                                        }
                                    }
                                }

                                Component.onCompleted: Qt.callLater(updateActiveIndicator)
                            }

                            Connections {
                                target: root
                                function onSelectedMoodIndexChanged() {
                                    moodFlickable.updateActiveIndicator();
                                }
                                function onMoodChipsChanged() {
                                    Qt.callLater(moodFlickable.updateActiveIndicator);
                                }
                            }

                            Connections {
                                target: I18n
                                function onLocaleChanged() {
                                    Qt.callLater(moodFlickable.updateActiveIndicator);
                                }
                            }

                            // Left Edge Hover-to-scroll Zone (Clean, Invisible)
                            Item {
                                id: leftMoodScrim
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 28
                                z: 30
                                visible: moodFlickable.contentX > 4

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    propagateComposedEvents: true
                                    onEntered: leftScrollTimer.running = true
                                    onExited: leftScrollTimer.running = false
                                    onPressed: (mouse) => { mouse.accepted = false; }
                                }
                            }

                            // Right Edge Hover-to-scroll Zone (Clean, Invisible)
                            Item {
                                id: rightMoodScrim
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 28
                                z: 30
                                visible: moodFlickable.contentWidth > moodFlickable.width && moodFlickable.contentX < moodFlickable.contentWidth - moodFlickable.width - 4

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    propagateComposedEvents: true
                                    onEntered: rightScrollTimer.running = true
                                    onExited: rightScrollTimer.running = false
                                    onPressed: (mouse) => { mouse.accepted = false; }
                                }
                            }
                        }

                        ListView {
                            id: queueListView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 4
                            opacity: root.isLoadingMoodQueue ? 0.45 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            model: root.queueTracks

                            delegate: Column {
                                id: delegateCol
                                width: queueListView.width
                                spacing: 4

                                // Section Header: Gợi ý tiếp theo (Radio Suggestions Separator - Complaint #5)
                                Item {
                                    width: delegateCol.width
                                    height: 34
                                    visible: Boolean(modelData && modelData.isRadioSuggestion && (index === 0 || (root.queueTracks && root.queueTracks[index - 1] && !root.queueTracks[index - 1].isRadioSuggestion)))

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 10
                                        spacing: 10

                                        Text {
                                            text: I18n.tr("Gợi ý tiếp theo (Radio)", "Up Next (Radio Suggestions)")
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.bold: true
                                            color: root.accentColor
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 1
                                            color: Qt.rgba(255, 255, 255, 0.12)
                                        }
                                    }
                                }

                                Rectangle {
                                    id: qRow
                                    width: delegateCol.width
                                    height: 48
                                    radius: 8
                                    readonly property bool isCurrent: Boolean(root.track && modelData && (
                                        (typeof win !== "undefined" && typeof win.isSameTrack === "function") 
                                            ? win.isSameTrack(modelData, root.track)
                                            : (
                                                (modelData.id && root.track.id && modelData.id === root.track.id) ||
                                                (modelData.videoId && root.track.videoId && modelData.videoId === root.track.videoId) ||
                                                (modelData.path && root.track.path && modelData.path === root.track.path) ||
                                                (modelData.title && root.track.title && modelData.title === root.track.title && modelData.artist && root.track.artist && modelData.artist === root.track.artist)
                                            )
                                    ))
                                    color: isCurrent 
                                           ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18) 
                                           : (qRowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                                    border.width: 0

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    Item {
                                        Layout.preferredWidth: 36
                                        Layout.preferredHeight: 36

                                        RoundedImage {
                                            anchors.fill: parent
                                            radius: 6
                                            source: modelData.image || ""
                                            fillMode: Image.PreserveAspectCrop
                                            fallbackIcon: "../assets/icons/media-optical-audio-symbolic.svg"
                                        }

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 6
                                                color: Qt.rgba(0, 0, 0, 0.55)
                                                visible: qRow.isCurrent && root.isPlaying

                                                Row {
                                                    anchors.centerIn: parent
                                                    spacing: 2
                                                    Repeater {
                                                        model: 3
                                                        Rectangle {
                                                            width: 2.5
                                                            height: 10 + (index % 2) * 5
                                                            radius: 1.2
                                                            color: root.accentColor
                                                            SequentialAnimation on height {
                                                                running: root.visible && root.activeTab === "up_next" && qRow.isCurrent && root.isPlaying
                                                                loops: Animation.Infinite
                                                                NumberAnimation { from: 4; to: 14; duration: 320 + index * 120; easing.type: Easing.InOutQuad }
                                                                NumberAnimation { from: 14; to: 4; duration: 320 + index * 120; easing.type: Easing.InOutQuad }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // 1px Hairline Border Overlay on top of cover image
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 6
                                                color: "transparent"
                                                border.color: Qt.rgba(1.0, 1.0, 1.0, 0.12)
                                                border.width: 1
                                                z: 2
                                            }
                                        }

                                        ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.title || modelData.name || I18n.tr("Không xác định", "Unknown")
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13
                                            font.bold: true
                                            color: qRow.isCurrent ? root.accentColor : "#ffffff"
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.artist || I18n.tr("Nghệ sĩ chưa rõ", "Unknown Artist")
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            color: Theme.textSecondary
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Text {
                                        text: {
                                            if (modelData && modelData.duration && modelData.duration !== "--:--") return modelData.duration;
                                            if (qRow.isCurrent && root.totalDuration > 1.0) {
                                                var m = Math.floor(root.totalDuration / 60);
                                                var s = Math.floor(root.totalDuration % 60);
                                                return m + ":" + (s < 10 ? "0" : "") + s;
                                            }
                                            return "";
                                        }
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Theme.textMuted
                                    }
                                }

                                MouseArea {
                                    id: qRowMouse
                                    anchors.fill: parent
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
                }

                // =============================================================
                // TAB 3 VIEW: RELATED (You Might Also Like + Recommended Playlists)
                // =============================================================
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: relatedContentCol.implicitHeight + 40
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: relatedContentCol
                        width: parent.width
                        spacing: 24

                        // Section 1: You might also like
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Text {
                                text: I18n.tr("Có thể bạn sẽ thích", "You might also like")
                                font.family: Theme.fontFamily
                                font.pixelSize: 16
                                font.bold: true
                                color: "#ffffff"
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: (root.relatedData && root.relatedData.you_might_also_like) ? root.relatedData.you_might_also_like.slice(0, 6) : 0

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 50
                                        radius: 8
                                        color: relTrackMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                                        border.width: 0

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 12
                                            spacing: 10

                                            RoundedImage {
                                                Layout.preferredWidth: 36
                                                Layout.preferredHeight: 36
                                                radius: 6
                                                source: modelData.image || ""
                                                sourceSize: Qt.size(72, 72)
                                                asynchronous: true
                                                fillMode: Image.PreserveAspectCrop
                                                autoCropBlackBars: true
                                                fallbackIcon: "../assets/icons/media-optical-audio-symbolic.svg"
                                                fallbackIconSize: 16
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.title || modelData.name || ""
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    font.bold: true
                                                    color: "#ffffff"
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.artist || ""
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 11
                                                    color: Theme.textSecondary
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            Text {
                                                text: modelData.duration || ""
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                color: Theme.textMuted
                                            }
                                        }

                                        MouseArea {
                                            id: relTrackMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.playTrackRequested(modelData, -1);
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Section 2: Recommended playlists (Horizontal Carousel)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            visible: root.relatedData && root.relatedData.recommended_playlists && root.relatedData.recommended_playlists.length > 0

                            Text {
                                text: I18n.tr("Danh sách phát đề xuất", "Recommended playlists")
                                font.family: Theme.fontFamily
                                font.pixelSize: 16
                                font.bold: true
                                color: "#ffffff"
                            }

                            Item {
                                id: recPlContainer
                                Layout.fillWidth: true
                                height: 180
                                clip: true

                                // Auto-scroll continuous timers
                                Timer {
                                    id: leftRecPlScrollTimer
                                    interval: 16
                                    repeat: true
                                    running: false
                                    onTriggered: {
                                        recPlFlickable.contentX = Math.max(0, recPlFlickable.contentX - 8);
                                        if (recPlFlickable.contentX <= 0) running = false;
                                    }
                                }

                                Timer {
                                    id: rightRecPlScrollTimer
                                    interval: 16
                                    repeat: true
                                    running: false
                                    onTriggered: {
                                        var maxScroll = recPlFlickable.contentWidth - recPlFlickable.width;
                                        recPlFlickable.contentX = Math.min(maxScroll, recPlFlickable.contentX + 8);
                                        if (recPlFlickable.contentX >= maxScroll) running = false;
                                    }
                                }

                                // Left Edge Hover-to-scroll Zone (Clean, Invisible)
                                Item {
                                    id: leftRecPlScrim
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 36
                                    z: 10
                                    visible: recPlFlickable.contentX > 4

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        propagateComposedEvents: true
                                        onEntered: leftRecPlScrollTimer.running = true
                                        onExited: leftRecPlScrollTimer.running = false
                                        onPressed: (mouse) => { mouse.accepted = false; }
                                    }
                                }

                                // Right Edge Hover-to-scroll Zone (Clean, Invisible)
                                Item {
                                    id: rightRecPlScrim
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 36
                                    z: 10
                                    visible: recPlFlickable.contentWidth > recPlFlickable.width && recPlFlickable.contentX < recPlFlickable.contentWidth - recPlFlickable.width - 4

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        propagateComposedEvents: true
                                        onEntered: rightRecPlScrollTimer.running = true
                                        onExited: rightRecPlScrollTimer.running = false
                                        onPressed: (mouse) => { mouse.accepted = false; }
                                    }
                                }

                                Flickable {
                                    id: recPlFlickable
                                    anchors.fill: parent
                                    contentWidth: recPlRow.implicitWidth + 24
                                    contentHeight: height
                                    flickableDirection: Flickable.HorizontalFlick
                                    boundsBehavior: Flickable.StopAtBounds
                                    clip: true

                                    DragHandler {
                                        target: null
                                        xAxis.enabled: true
                                        yAxis.enabled: false
                                        cursorShape: Qt.OpenHandCursor
                                        property real startContentX: 0
                                        onActiveChanged: {
                                            if (active) {
                                                startContentX = recPlFlickable.contentX;
                                            }
                                        }
                                        onTranslationChanged: {
                                            if (active) {
                                                var maxScroll = Math.max(0, recPlFlickable.contentWidth - recPlFlickable.width);
                                                recPlFlickable.contentX = Math.max(0, Math.min(maxScroll, startContentX - translation.x));
                                            }
                                        }
                                    }

                                    WheelHandler {
                                        target: recPlFlickable
                                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                        onWheel: event => {
                                            var delta = (event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x);
                                            recPlFlickable.contentX = Math.max(0, Math.min(recPlFlickable.contentWidth - recPlFlickable.width, recPlFlickable.contentX - delta));
                                        }
                                    }

                                    RowLayout {
                                        id: recPlRow
                                        spacing: 14
                                        anchors.verticalCenter: parent.verticalCenter

                                        Repeater {
                                            model: (root.relatedData && root.relatedData.recommended_playlists) ? root.relatedData.recommended_playlists : []

                                            Rectangle {
                                                Layout.preferredWidth: 130
                                                Layout.preferredHeight: 175
                                                radius: 10
                                                color: recPlMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.03)
                                                border.color: Qt.rgba(1, 1, 1, 0.08)
                                                border.width: 1

                                                ColumnLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 8
                                                    spacing: 6

                                                    RoundedImage {
                                                        Layout.preferredWidth: 114
                                                        Layout.preferredHeight: 114
                                                        radius: 8
                                                        source: modelData.image || ""
                                                        sourceSize: Qt.size(240, 240)
                                                        asynchronous: true
                                                        fillMode: Image.PreserveAspectCrop
                                                        autoCropBlackBars: true
                                                        fallbackIcon: "../assets/icons/folder-music-symbolic.svg"
                                                        fallbackIconSize: 32
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.title || ""
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 12
                                                        font.bold: true
                                                        color: "#ffffff"
                                                        elide: Text.ElideRight
                                                        maximumLineCount: 2
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.description || I18n.tr("Danh sách phát", "Playlist")
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                        color: Theme.textMuted
                                                        elide: Text.ElideRight
                                                    }
                                                }

                                                MouseArea {
                                                    id: recPlMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.playlistSelected(modelData)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Section 3: Similar artists
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            visible: root.relatedData && root.relatedData.similar_artists && root.relatedData.similar_artists.length > 0

                            Text {
                                text: I18n.tr("Nghệ sĩ tương tự", "Similar artists")
                                font.family: Theme.fontFamily
                                font.pixelSize: 16
                                font.bold: true
                                color: "#ffffff"
                            }

                            Item {
                                id: simArtContainer
                                Layout.fillWidth: true
                                height: 130
                                clip: true

                                // Auto-scroll continuous timers
                                Timer {
                                    id: leftArtScrollTimer
                                    interval: 16
                                    repeat: true
                                    running: false
                                    onTriggered: {
                                        artFlickable.contentX = Math.max(0, artFlickable.contentX - 8);
                                        if (artFlickable.contentX <= 0) running = false;
                                    }
                                }

                                Timer {
                                    id: rightArtScrollTimer
                                    interval: 16
                                    repeat: true
                                    running: false
                                    onTriggered: {
                                        var maxScroll = artFlickable.contentWidth - artFlickable.width;
                                        artFlickable.contentX = Math.min(maxScroll, artFlickable.contentX + 8);
                                        if (artFlickable.contentX >= maxScroll) running = false;
                                    }
                                }

                                // Left Edge Hover-to-scroll Zone (Clean, Invisible)
                                Item {
                                    id: leftArtScrim
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 36
                                    z: 10
                                    visible: artFlickable.contentX > 4

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        propagateComposedEvents: true
                                        onEntered: leftArtScrollTimer.running = true
                                        onExited: leftArtScrollTimer.running = false
                                        onPressed: (mouse) => { mouse.accepted = false; }
                                    }
                                }

                                // Right Edge Hover-to-scroll Zone (Clean, Invisible)
                                Item {
                                    id: rightArtScrim
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 36
                                    z: 10
                                    visible: artFlickable.contentWidth > artFlickable.width && artFlickable.contentX < artFlickable.contentWidth - artFlickable.width - 4

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        propagateComposedEvents: true
                                        onEntered: rightArtScrollTimer.running = true
                                        onExited: rightArtScrollTimer.running = false
                                        onPressed: (mouse) => { mouse.accepted = false; }
                                    }
                                }

                                Flickable {
                                    id: artFlickable
                                    anchors.fill: parent
                                    contentWidth: artRow.implicitWidth + 24
                                    contentHeight: height
                                    flickableDirection: Flickable.HorizontalFlick
                                    boundsBehavior: Flickable.StopAtBounds
                                    clip: true

                                    DragHandler {
                                        target: null
                                        xAxis.enabled: true
                                        yAxis.enabled: false
                                        cursorShape: Qt.OpenHandCursor
                                        property real startContentX: 0
                                        onActiveChanged: {
                                            if (active) {
                                                startContentX = artFlickable.contentX;
                                            }
                                        }
                                        onTranslationChanged: {
                                            if (active) {
                                                var maxScroll = Math.max(0, artFlickable.contentWidth - artFlickable.width);
                                                artFlickable.contentX = Math.max(0, Math.min(maxScroll, startContentX - translation.x));
                                            }
                                        }
                                    }

                                    WheelHandler {
                                        target: artFlickable
                                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                        onWheel: event => {
                                            var delta = (event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x);
                                            artFlickable.contentX = Math.max(0, Math.min(artFlickable.contentWidth - artFlickable.width, artFlickable.contentX - delta));
                                        }
                                    }

                                    RowLayout {
                                        id: artRow
                                        spacing: 16
                                        anchors.verticalCenter: parent.verticalCenter

                                        Repeater {
                                            model: (root.relatedData && root.relatedData.similar_artists) ? root.relatedData.similar_artists : []

                                            Item {
                                                width: 90
                                                height: 120

                                                ColumnLayout {
                                                    anchors.fill: parent
                                                    spacing: 6

                                                    Item {
                                                        Layout.preferredWidth: 76
                                                        Layout.preferredHeight: 76
                                                        Layout.alignment: Qt.AlignHCenter

                                                        RoundedImage {
                                                            anchors.fill: parent
                                                            radius: 38
                                                            source: modelData.image || ""
                                                            fillMode: Image.PreserveAspectCrop
                                                            initialsText: modelData.name || modelData.title || ""
                                                        }

                                                        Rectangle {
                                                            anchors.fill: parent
                                                            radius: 38
                                                            color: "transparent"
                                                            border.color: simArtMouse.containsMouse ? root.accentColor : Qt.rgba(1, 1, 1, 0.15)
                                                            border.width: 1.5
                                                        }
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.name || ""
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 11
                                                        font.bold: true
                                                        color: simArtMouse.containsMouse ? root.accentColor : "#ffffff"
                                                        elide: Text.ElideRight
                                                        horizontalAlignment: Text.AlignHCenter
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.subscribers || I18n.tr("Nghệ sĩ", "Artist")
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                        color: Theme.textMuted
                                                        elide: Text.ElideRight
                                                        horizontalAlignment: Text.AlignHCenter
                                                    }
                                                }

                                                MouseArea {
                                                    id: simArtMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.artistSelected(modelData.name, modelData.channelId || "")
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


