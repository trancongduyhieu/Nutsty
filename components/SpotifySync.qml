import QtQuick
import Quickshell

// SpotifySync: two-way sync between the user's own Spotify library and Nutsty playlists / liked songs
// (backend/spotify_sync.py over POST /api/spotify/sync/<op>, nutsty-daemon on Linux, auth_server on Windows).
// Per device: only the device where it is switched on talks to Spotify; others get the result through
// account sync. Declared once in shell.qml as `spotifySync`; shell.qml reloads the stores on `remoteChanged`.
QtObject {
    id: sp

    property string apiUrl: "http://127.0.0.1:17890"
    property string profile: (Quickshell.env("NUTSTY_PROFILE") || "").toLowerCase()
    // A Spotify cookie is saved: without it nothing here can run
    property bool hasCookie: false

    property bool enabled: false
    property bool selectionConfirmed: false
    property bool running: false
    property double lastSync: 0          // seconds since epoch, 0 = never
    property string lastError: ""        // "", auth_expired, rate_limited, query_changed, network, internal
    property var blocked: []             // Spotify playlist ids or "liked" held back by the mass-delete guard
    property var blockedNames: ({})
    property int unmatched: 0
    property var choices: []             // [{id, title, image, owned, spotifyMade, selected}]
    property bool likedChoice: true
    property bool choicesLoading: false
    property string choicesError: ""
    property bool writeBack: false
    property bool likedSelected: false
    property var backlog: ({})
    // The earlier-likes push of this switch-on has run (or runs): the app starts it once on its own
    property bool backlogRan: true

    signal remoteChanged(var changed)

    Component.onCompleted: sp.refreshStatus()

    function _post(op, body, cb) {
        var xhr = new XMLHttpRequest();
        xhr.open("POST", sp.apiUrl + "/api/spotify/sync/" + op, true);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.timeout = 120000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            var res = null;
            try { res = JSON.parse(xhr.responseText); } catch (e) {}
            if (cb) cb(res || { success: false, error: "network" });
        };
        var payload = body || {};
        payload.profile = sp.profile;
        xhr.send(JSON.stringify(payload));
    }

    function _applyStatus(s) {
        if (!s || s.enabled === undefined) return;
        sp.enabled = !!s.enabled;
        sp.selectionConfirmed = !!s.selectionConfirmed;
        sp.lastSync = s.lastSync || 0;
        sp.lastError = (s.lastError === "disabled" || s.lastError === "busy") ? "" : (s.lastError || "");
        sp.blocked = s.blocked || [];
        sp.blockedNames = s.blockedNames || ({});
        sp.unmatched = s.unmatchedCount || 0;
        sp.writeBack = !!s.writeBack;
        sp.likedSelected = !!s.likedSelected;
        sp.backlog = s.backlog || ({});
        sp.backlogRan = s.backlogRan !== false;
        sp.running = !!s.running;
        sp._autoBacklog();
    }

    // Two-way with Liked Songs picked: likes Nutsty held before the switch go up once, slowly, without a button
    function _autoBacklog() {
        if (sp.hasCookie && sp.enabled && sp.writeBack && sp.likedSelected && !sp.backlogRan
                && !sp.backlogRunning && !sp.running) {
            sp.backlogRan = true;   // not twice while the start call is in flight
            sp.pushBacklog();
        }
    }

    // ---- Automatic runs ----------------------------------------------------------------------
    // Two-way: a change made in Nutsty (playlist edit, like, rename) goes up shortly after, one run
    // for a burst of changes. One way pulls only, so local changes wait for the regular check.
    property int soonDelay: 20000
    readonly property int periodMinutes: 15
    // A sync's own reload of the stores looks like a local change: ignore those until this time (ms)
    property double quietUntil: 0

    function schedule() {
        if (!sp.hasCookie || !sp.enabled || !sp.selectionConfirmed || !sp.writeBack) return;
        if (Date.now() < sp.quietUntil) return;
        soonTimer.restart();
    }

    // Back at the window after a while: Spotify may have changed meanwhile
    function windowActivated() {
        if (Date.now() / 1000 - sp.lastSync > 120) sp.run();
    }

    property Timer soonTimer: Timer {
        interval: sp.soonDelay
        onTriggered: sp.run()
    }

    function refreshStatus() {
        sp._post("status", {}, function(res) {
            sp._applyStatus(res);
            if (sp.running && !pollTimer.running) pollTimer.start();
            if (sp.backlogRunning && !backlogTimer.running) backlogTimer.start();
        });
    }

    // The run happens in the background on the backend; poll status until it ends
    function run() {
        if (!sp.hasCookie || !sp.enabled || !sp.selectionConfirmed || sp.running) return;
        sp.running = true;
        sp._post("run", {}, function(res) {
            if (!res.success && res.error !== "busy") { sp.running = false; sp.lastError = res.error || "network"; return; }
            pollTimer.start();
        });
    }

    property Timer pollTimer: Timer {
        interval: 2000
        repeat: true
        onTriggered: sp._post("status", {}, function(res) {
            if (!res || res.running) return;
            pollTimer.stop();
            sp._applyStatus(res);
            var last = res.last;
            if (last && last.changed && (last.changed.playlists || last.changed.liked)) {
                sp.quietUntil = Date.now() + 10000;
                sp.remoteChanged(last.changed);
            }
        })
    }

    function loadChoices() {
        sp.choicesLoading = true;
        sp.choicesError = "";
        sp._post("choices", {}, function(res) {
            sp.choicesLoading = false;
            if (!res.success) { sp.choicesError = res.error || "network"; return; }
            sp.choices = res.playlists || [];
            sp.likedChoice = res.liked !== false;
        });
    }

    function confirmSelection(ids, liked) {
        sp._post("set_selection", { ids: ids, liked: liked }, function(res) {
            if (res && res.success !== false) {
                // The counts in Settings read `choices`: mark the new picks now, not on the next loadChoices
                var next = [];
                var list = sp.choices || [];
                for (var i = 0; i < list.length; i++)
                    next.push(Object.assign({}, list[i], { selected: ids.indexOf(list[i].id) >= 0 }));
                sp.likedChoice = !!liked;   // before choices: the picker re-seeds from both on choicesChanged
                sp.choices = next;
            }
            sp._applyStatus(res);
            if (sp.selectionConfirmed) {
                if (!sp.enabled) sp.setEnabled(true);
                else sp.run();
            }
        });
    }

    function setEnabled(on) {
        sp._post("set_enabled", { enabled: on }, function(res) {
            sp._applyStatus(res);
            if (sp.enabled) sp.run();
        });
    }

    // A linked list deleted in Nutsty: stop syncing it, and with two-way on remove it from Spotify soon
    function forget(pid) {
        if (!pid) return;
        sp._post("forget", { id: pid }, function(res) {
            sp._applyStatus(res);
            if (res && res.queued) sp.schedule();
        });
    }

    function forceApply(pid) {
        sp._post("force_apply", { id: pid }, function(res) {
            sp._applyStatus(res);
            sp.run();
        });
    }

    function setWriteBack(on) {
        sp._post("set_write_back", { on: on }, function(res) { sp._applyStatus(res); });
    }

    // "Push earlier likes" runs in the background on the backend, paced; poll its progress until it ends
    readonly property bool backlogRunning: !!(sp.backlog && sp.backlog.running)

    function pushBacklog() {
        if (!sp.writeBack || sp.backlogRunning) return;
        sp._post("backlog_start", {}, function(res) {
            sp._applyStatus(res);
            if (!res.success) sp.backlog = Object.assign({}, sp.backlog, { error: res.error || "network" });
            if (sp.backlogRunning) backlogTimer.start();
        });
    }

    function cancelBacklog() {
        sp._post("backlog_cancel", {}, function(res) { sp._applyStatus(res); });
    }

    property Timer backlogTimer: Timer {
        interval: 2000
        repeat: true
        onTriggered: sp._post("status", {}, function(res) {
            sp._applyStatus(res);
            if (!sp.backlogRunning) {
                backlogTimer.stop();
                // its likes landed in the liked file: let the stores pick them up
                sp.quietUntil = Date.now() + 10000;
                sp.remoteChanged({ liked: true });
            }
        })
    }

    // First run shortly after start, then every periodMinutes
    property Timer firstTimer: Timer {
        interval: 20000
        running: sp.hasCookie && sp.enabled && sp.selectionConfirmed
        onTriggered: sp.run()
    }

    property Timer periodicTimer: Timer {
        interval: sp.periodMinutes * 60 * 1000
        repeat: true
        running: sp.hasCookie && sp.enabled && sp.selectionConfirmed
        onTriggered: sp.run()
    }
}
