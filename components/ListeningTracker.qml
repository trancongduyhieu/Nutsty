import QtQuick

// Counts real listening time per play and reports it to the local backend.
// A play is counted by the backend once it reaches 30s; later reports with the same playId
// only extend its listened time. A new play starts when the track changes, or when the same
// track restarts from the top after it already counted (repeat one).
QtObject {
    id: root

    property var track: null
    property string trackKey: ""
    property bool playing: false
    property bool buffering: false
    property real position: 0
    property real duration: 0
    property string apiUrl: "http://127.0.0.1:17890"

    readonly property real threshold: 30
    readonly property real reportEvery: 30

    property string playId: ""
    property real listened: 0
    property real lastReported: 0
    property var playTrack: null
    property string playKey: ""
    property real playDuration: 0
    property double lastTick: 0
    property real lastPosition: 0

    signal playCounted()

    function newPlayId() {
        return Date.now().toString(36) + "-" + Math.floor(Math.random() * 0xffffffff).toString(36);
    }

    function report(force) {
        if (!root.playId || root.listened < root.threshold) return;
        if (!force && root.listened - root.lastReported < root.reportEvery && root.lastReported > 0) return;
        var firstCount = root.lastReported < root.threshold;
        root.lastReported = root.listened;
        var t = root.playTrack || {};
        var payload = {
            play_id: root.playId,
            track: {
                id: root.playKey,
                title: t.title || t.name || "",
                artist: t.artist || t.author || "",
                album: t.album || "",
                image: t.image || t.cover || t.thumbnail || ""
            },
            listened_seconds: root.listened,
            total_seconds: root.playDuration
        };
        var xhr = new XMLHttpRequest();
        xhr.open("POST", root.apiUrl + "/api/listening/play", true);
        xhr.setRequestHeader("Content-Type", "application/json");
        if (firstCount) {
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200) return;
                try {
                    var res = JSON.parse(xhr.responseText);
                    if (res && res.counted) root.playCounted();
                } catch (e) {}
            };
        }
        xhr.send(JSON.stringify(payload));
    }

    function startPlay() {
        root.report(true);
        root.playId = root.trackKey ? root.newPlayId() : "";
        root.listened = 0;
        root.lastReported = 0;
        root.playTrack = root.track;
        root.playKey = root.trackKey;
        root.playDuration = root.duration;
        root.lastTick = 0;
        root.lastPosition = root.position;
    }

    onTrackKeyChanged: startPlay()
    onDurationChanged: if (root.duration > root.playDuration) root.playDuration = root.duration
    onPlayingChanged: {
        root.lastTick = 0;
        if (!root.playing) root.report(true);
    }

    property Timer ticker: Timer {
        interval: 1000
        repeat: true
        running: root.playing && !root.buffering && root.playId !== ""
        onRunningChanged: root.lastTick = 0
        onTriggered: {
            var now = Date.now();
            var pos = root.position;
            // Same track restarted from the top after it already counted: a new play
            if (root.listened >= root.threshold && pos < 3 && root.lastPosition > pos + 10) {
                root.startPlay();
                root.lastTick = now;
                return;
            }
            if (root.lastTick > 0) {
                // Wall-clock delta, capped so a suspended machine does not add hours
                root.listened += Math.min(2.0, (now - root.lastTick) / 1000.0);
            }
            root.lastTick = now;
            root.lastPosition = pos;
            root.report(false);
        }
    }
}
