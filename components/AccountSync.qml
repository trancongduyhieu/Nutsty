import QtQuick
import Quickshell

// AccountSync: keeps playlists, liked songs, plays and listening progress the same on every device of one
// Nutsty account (backend/account_sync.py over POST /api/sync/<op>, nutsty-daemon on Linux, auth_server on Windows).
// Runs on start, every 5 minutes and a few seconds after a local change. Declared once in shell.qml as
// `accountSync`; shell.qml reloads the stores when `remoteChanged` fires.
QtObject {
    id: sync

    property string apiUrl: "http://127.0.0.1:17890"
    property string profile: (Quickshell.env("NUTSTY_PROFILE") || "").toLowerCase()

    property bool running: false
    property double lastSync: 0
    property string lastError: ""
    property int pending: 0
    // Code shown on this device for another one to type (6 letters, 10 minutes)
    property string linkCode: ""
    property double linkCodeExpiresAt: 0
    property bool linkBusy: false
    property string linkError: ""
    // Off: this device keeps everything and syncs nothing until turned on again (backend remembers it)
    property bool enabled: true
    // Another device shares this account. Off: there is nothing to turn off or detach from
    property bool linkedToOthers: false
    property bool detachBusy: false
    property string detachError: ""

    signal remoteChanged(var changed)
    signal resumeOffered(var progress)
    signal linked(string tag)
    signal detached(string tag)

    Component.onCompleted: sync.refreshStatus()

    function _post(op, body, cb) {
        var xhr = new XMLHttpRequest();
        xhr.open("POST", sync.apiUrl + "/api/sync/" + op, true);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.timeout = 60000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            var res = null;
            try { res = JSON.parse(xhr.responseText); } catch (e) {}
            if (cb) cb(res || { success: false, error: "offline" });
        };
        var payload = body || {};
        payload.profile = sync.profile;
        xhr.send(JSON.stringify(payload));
    }

    function run() {
        if (!sync.enabled) return;
        if (sync.running) { sync._again = true; return; }
        sync.running = true;
        sync._post("run", {}, function(res) {
            sync.running = false;
            if (res.error === "disabled") { sync.enabled = false; sync.lastError = ""; return; }
            sync.lastError = res.success ? "" : (res.error || "offline");
            if (res.last_sync) sync.lastSync = res.last_sync;
            if (res.changed && (res.changed.playlists || res.changed.favorites || res.changed.liked || res.plays_added > 0)) {
                var c = res.changed;
                c.plays = res.plays_added || 0;
                sync.remoteChanged(c);
            }
            if (res.resume && res.resume.track) sync.resumeOffered(res.resume);
            sync.refreshStatus();
            if (sync._again) { sync._again = false; soonTimer.restart(); }
        });
    }

    // A local change: sync a moment later so a burst of edits goes out in one round
    function schedule() { soonTimer.restart(); }

    function refreshStatus() {
        sync._post("status", {}, function(res) {
            if (!res.success) return;
            sync.enabled = res.enabled !== false;
            var wasLinked = sync.linkedToOthers;
            sync.linkedToOthers = res.linked === true;
            // The code on screen was used: the new device showed up, so the code box can go
            if (!wasLinked && sync.linkedToOthers) sync.linkCode = "";
            sync.pending = res.pending || 0;
            if (res.last_sync) sync.lastSync = res.last_sync;
        });
    }

    function reportProgress(track, position, duration, playing) {
        if (!track || !sync.enabled) return;
        sync._post("progress", { track: track, position: position, duration: duration, playing: playing }, null);
    }

    function dismissResume(progress) {
        sync._post("dismiss_resume", { updated_at: progress ? progress.updated_at : 0 }, null);
    }

    function createLinkCode() {
        sync.linkBusy = true;
        sync.linkError = "";
        sync._post("link_code", {}, function(res) {
            sync.linkBusy = false;
            if (res.success && res.code) {
                sync.linkCode = res.code;
                sync.linkCodeExpiresAt = res.expires_at || (Date.now() + 600000);
            } else {
                sync.linkError = res.error || "offline";
            }
        });
    }

    function claimLinkCode(code) {
        sync.linkBusy = true;
        sync.linkError = "";
        sync._post("link_claim", { code: code }, function(res) {
            sync.linkBusy = false;
            if (res.success) {
                sync.enabled = true;   // the backend turns sync on when a code is typed
                sync.linked(res.tag || "");
                sync.run();
            } else {
                sync.linkError = res.error || "offline";
            }
        });
    }

    function setEnabled(on) {
        sync.enabled = Boolean(on);
        sync.lastError = "";
        sync._post("set_enabled", { enabled: sync.enabled }, function(res) {
            if (res.success && sync.enabled) sync.run();
        });
    }

    // This device gets an account of its own and keeps its data; the other devices keep the old one
    function detach() {
        if (sync.detachBusy) return;
        sync.detachBusy = true;
        sync.detachError = "";
        sync._post("detach", {}, function(res) {
            sync.detachBusy = false;
            if (res.success) {
                sync.linkCode = "";
                sync.linkedToOthers = false;
                sync.detached(res.tag || "");
                sync.run();
            } else {
                sync.detachError = res.error || "offline";
            }
        });
    }

    property bool _again: false

    property Timer soonTimer: Timer {
        interval: 4000
        repeat: false
        onTriggered: sync.run()
    }

    property Timer periodicTimer: Timer {
        interval: 300000
        repeat: true
        running: true
        onTriggered: sync.run()
    }

    property Timer startTimer: Timer {
        interval: 6000
        repeat: false
        running: true
        onTriggered: sync.run()
    }

    // While a code is on screen, check often so the new device shows up here within seconds
    property Timer codeWatchTimer: Timer {
        interval: 5000
        repeat: true
        running: sync.linkCode !== "" && sync.enabled
        onTriggered: sync.run()
    }

    property Timer codeExpiryTimer: Timer {
        interval: 1000
        repeat: true
        running: sync.linkCode !== ""
        onTriggered: if (Date.now() >= sync.linkCodeExpiresAt) sync.linkCode = ""
    }
}
