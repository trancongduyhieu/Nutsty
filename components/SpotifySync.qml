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
    property var backlog: ({})

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
        sp.backlog = s.backlog || ({});
        sp.running = !!s.running;
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
            if (last && last.changed && (last.changed.playlists || last.changed.liked)) sp.remoteChanged(last.changed);
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
            if (!sp.backlogRunning) backlogTimer.stop();
        })
    }

    // First run shortly after start, then every 3 hours
    property Timer firstTimer: Timer {
        interval: 20000
        running: sp.hasCookie && sp.enabled && sp.selectionConfirmed
        onTriggered: sp.run()
    }

    property Timer periodicTimer: Timer {
        interval: 3 * 3600 * 1000
        repeat: true
        running: sp.hasCookie && sp.enabled && sp.selectionConfirmed
        onTriggered: sp.run()
    }
}
