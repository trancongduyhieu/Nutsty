import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Io
import "."

Item {
    id: root

    // =========================================================================
    // Interface (Minimal, Leverage-Heavy Seam)
    // =========================================================================
    property var track: null
    property real radius: 16
    property bool animatedCoverEnabled: true
    property string canvasPreference: "apple_first"
    property bool isPlaying: false
    property bool autoCropBlackBars: true
    property bool showShadow: true
    property string overrideImage: ""
    property string overrideAnimatedArtworkUrl: ""
    property color borderColor: Qt.rgba(1, 1, 1, 0.16)
    property real borderWidth: 1.0
    property string appDir: (typeof win !== "undefined" && win && win.appDir) ? win.appDir : (Quickshell.env("NUTSTY_APP_DIR") || (Quickshell.env("HOME") + "/Applications/FrostifyLocal"))

    // Internal state
    property string resolvedSquareImage: ""
    property bool squareImageFailed: false
    property bool highResFailed: false
    property string animatedArtworkUrl: ""
    property bool isLoadingAnimatedArtwork: false

    readonly property string effectiveAnimatedUrl: {
        if (!root.visible || !root.animatedCoverEnabled || root.canvasPreference === "off") return "";
        if (root.overrideAnimatedArtworkUrl !== "") return root.overrideAnimatedArtworkUrl;
        return root.animatedArtworkUrl;
    }

    onTrackChanged: {
        squareImageFailed = false;
        highResFailed = false;
        resolveSquareCover();
        fetchAnimatedArtwork();
    }

    onCanvasPreferenceChanged: {
        if (animatedCoverEnabled && canvasPreference !== "off") {
            fetchAnimatedArtwork();
        } else {
            animatedArtworkUrl = "";
        }
    }

    onAnimatedCoverEnabledChanged: {
        if (animatedCoverEnabled && canvasPreference !== "off") {
            fetchAnimatedArtwork();
        } else {
            animatedArtworkUrl = "";
        }
    }

    // =========================================================================
    // High-Resolution & Square Cover Image Resolvers
    // =========================================================================
    function getRawTrackImage(trk) {
        if (!trk) return "";
        var img = trk.image || trk.cover || trk.thumbnail || trk.artUrl || "";
        if (!img && trk.videoId) {
            img = "https://i.ytimg.com/vi/" + trk.videoId + "/hqdefault.jpg";
        }
        return img;
    }

    function formatImageUrl(urlStr) {
        if (!urlStr) return "";
        var s = String(urlStr).trim();
        if (s.startsWith("http://") || s.startsWith("https://") || s.startsWith("file://") || s.startsWith("qrc:")) {
            return s;
        }
        var clean = s.replace(/\\/g, "/");
        if (clean.startsWith("/")) {
            return "file://" + clean;
        }
        if (/^[a-zA-Z]:\//.test(clean)) {
            return "file:///" + clean;
        }
        return clean;
    }

    function getHighResImage(raw) {
        if (!raw || typeof raw !== "string") return "";
        if (raw.indexOf("googleusercontent.com") !== -1 || raw.indexOf("ggpht.com") !== -1) {
            if (/=w\d+-h\d+/.test(raw)) {
                return raw.replace(/=w\d+-h\d+[^=]*$/, "=w1200-h1200-l90-rj");
            } else if (raw.indexOf("=") !== -1) {
                return raw.split("=")[0] + "=w1200-h1200-l90-rj";
            } else {
                return raw + "=w1200-h1200-l90-rj";
            }
        }
        if (raw.indexOf("mzstatic.com") !== -1) {
            return raw.replace(/\d+x\d+bb/, "1200x1200bb");
        }
        if (raw.indexOf("i.ytimg.com") !== -1) {
            return raw.replace(/(hqdefault|mqdefault|default|sddefault)\.jpg/, "maxresdefault.jpg");
        }
        return raw;
    }

    function resolveSquareCover() {
        if (!root.track) {
            root.resolvedSquareImage = "";
            return;
        }
        var vid = root.track.videoId || (root.track.path && root.track.path.startsWith("ytdl://") ? root.track.path.replace("ytdl://", "") : "");
        var title = root.track.title || root.track.name || "";
        var artist = root.track.artist || "";
        if (!vid && !title) {
            root.resolvedSquareImage = "";
            return;
        }
        squareCoverProc.running = false;
        squareCoverProc.command = [
            "python3", "-u",
            root.appDir + "/backend/ytmusic_helper.py",
            "resolve_cover",
            title, artist, vid
        ];
        squareCoverProc.running = true;
    }

    Process {
        id: squareCoverProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (!data || data.trim() === "") return;
                try {
                    var parsed = JSON.parse(data);
                    if (parsed && (parsed.url || parsed.square_image)) {
                        root.resolvedSquareImage = parsed.url || parsed.square_image;
                    }
                } catch(e) {}
            }
        }
    }

    // =========================================================================
    // Animated Artwork Fetcher (Apple Music / Spotify Canvas)
    // =========================================================================
    function fetchAnimatedArtwork() {
        root.animatedArtworkUrl = "";
        if (root.overrideAnimatedArtworkUrl !== "") {
            root.isLoadingAnimatedArtwork = false;
            return;
        }
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
        }

        if (!songTitle) {
            root.isLoadingAnimatedArtwork = false;
            return;
        }

        var songAlbum = (root.track && root.track.album) ? ((typeof root.track.album === "string") ? root.track.album : (root.track.album.name || "")) : "";

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

    Process {
        id: amArtworkProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (!data || data.trim() === "") return;
                try {
                    var parsed = JSON.parse(data);
                    var vidUrl = parsed ? (parsed.video_url || parsed.animated_artwork_url || "") : "";
                    if (parsed && (parsed.found || vidUrl !== "") && vidUrl !== "") {
                        root.animatedArtworkUrl = vidUrl;
                    } else {
                        root.animatedArtworkUrl = "";
                    }
                } catch(e) {
                    root.animatedArtworkUrl = "";
                }
                root.isLoadingAnimatedArtwork = false;
            }
        }
        onExited: (code, status) => {
            root.isLoadingAnimatedArtwork = false;
        }
    }

    // =========================================================================
    // Visual Layer: Drop Shadow, Rounded Artwork, Video Output, Mask, Border
    // =========================================================================

    // 1. Soft Drop Shadow
    Rectangle {
        id: coverShadow
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: -4
        radius: root.radius
        color: Qt.rgba(0, 0, 0, 0.40)
        visible: root.showShadow
        z: 0
    }

    // 2. Matte Charcoal Surface Container
    Rectangle {
        id: coverSurface
        anchors.fill: parent
        radius: root.radius
        color: "#202024"
        z: 1

        // Static Cover Image
        RoundedImage {
            id: bigCoverImg
            anchors.fill: parent
            radius: root.radius
            source: {
                if (root.overrideImage !== "") {
                    return root.formatImageUrl(root.overrideImage);
                }
                if (root.resolvedSquareImage !== "" && !root.squareImageFailed) {
                    return root.formatImageUrl(root.resolvedSquareImage);
                }
                var raw = root.getRawTrackImage(root.track);
                if (!raw) return "";
                var targetImg = root.highResFailed ? raw : root.getHighResImage(raw);
                return root.formatImageUrl(targetImg);
            }
            fillMode: Image.PreserveAspectCrop
            autoCropBlackBars: root.autoCropBlackBars
            asynchronous: true
            sourceSize: Qt.size(1000, 1000)
            useInitialsFallback: false
            fallbackIcon: "../assets/icons/media-optical-audio-symbolic.svg"
            fallbackIconSize: 48
            fallbackIconColor: Theme.textMuted
            onStatusChanged: {
                if (status === Image.Error) {
                    if (root.resolvedSquareImage !== "" && !root.squareImageFailed) {
                        root.squareImageFailed = true;
                    } else if (!root.highResFailed) {
                        root.highResFailed = true;
                    }
                }
            }
        }

        // Mask for Animated Video Output (zero leak into 4 corners, 0 FBO overhead when idle)
        Rectangle {
            id: coverVideoMask
            anchors.fill: parent
            radius: root.radius
            color: "#ffffff"
            visible: false
            layer.enabled: true
        }

        // Animated Cover Player
        MediaPlayer {
            id: amPlayer
            videoOutput: amVideoOutput
            source: root.effectiveAnimatedUrl
            audioOutput: null
            loops: MediaPlayer.Infinite
            Component.onCompleted: {
                if (source !== "" && root.visible && root.isPlaying) play();
            }
            onSourceChanged: {
                if (source !== "" && root.visible && root.isPlaying) play();
                else stop();
            }
        }

        Connections {
            target: root
            function onIsPlayingChanged() {
                if (amPlayer.source !== "") {
                    if (root.isPlaying && root.visible) {
                        if (amPlayer.playbackState !== MediaPlayer.PlayingState) amPlayer.play();
                    } else {
                        if (amPlayer.playbackState === MediaPlayer.PlayingState) amPlayer.pause();
                    }
                }
            }
            function onVisibleChanged() {
                if (amPlayer.source !== "") {
                    if (root.isPlaying && root.visible) {
                        if (amPlayer.playbackState !== MediaPlayer.PlayingState) amPlayer.play();
                    } else {
                        if (amPlayer.playbackState === MediaPlayer.PlayingState) amPlayer.pause();
                    }
                }
            }
        }

        // Video Output with MultiEffect Mask (0 lag, zero corner leakage)
        VideoOutput {
            id: amVideoOutput
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectCrop
            visible: opacity > 0.01
            opacity: (root.animatedCoverEnabled && root.effectiveAnimatedUrl !== "" && (amPlayer.playbackState === MediaPlayer.PlayingState || amPlayer.playbackState === MediaPlayer.PausedState)) ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutQuad } }
            z: 1

            layer.enabled: opacity > 0.01
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: coverVideoMask
                autoPaddingEnabled: false
            }
        }

        // Fallback Audio Icon when image not ready
        Rectangle {
            anchors.fill: parent
            visible: bigCoverImg.status !== Image.Ready && (!root.animatedCoverEnabled || root.effectiveAnimatedUrl === "")
            color: Qt.rgba(0.08, 0.08, 0.10, 0.85)
            AppIcon {
                anchors.centerIn: parent
                source: "../assets/icons/media-optical-audio-symbolic.svg"
                iconSize: 48
                color: Theme.textMuted
            }
        }
    }

    // 3. Hairline Anti-aliased Border
    Rectangle {
        id: borderRect
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.color: root.borderColor
        border.width: root.borderWidth
        visible: root.borderWidth > 0 && root.borderColor.a > 0
        z: 2
    }
}
