import QtQuick
import Quickshell

// PlaylistStore (ADR-0007): the one owner of custom playlists, favorite playlists and the open playlist.
// Writes go one at a time as POST /api/playlists/<op> (nutsty-daemon on Linux, auth_server on Windows).
// Each write patches the lists at once (optimistic patch), then the playlist write result from the backend
// replaces them. Declared once in shell.qml as `playlistStore`; `win` binds to it and keeps 1-line delegates.
QtObject {
    id: store

    property string apiUrl: "http://127.0.0.1:17890"
    // One daemon serves every profile window, so each request names its profile
    property string profile: (Quickshell.env("NUTSTY_PROFILE") || "").toLowerCase()

    property var customPlaylists: []
    property var favoritePlaylists: []
    property string selectedId: ""
    // Object shown while selectedId is not in customPlaylists yet (e.g. opened before the first load)
    property var selectedFallback: null
    readonly property var selected: {
        var pid = store.selectedId;
        if (!pid) return null;
        var list = store.customPlaylists || [];
        for (var i = 0; i < list.length; i++) {
            if (list[i] && (list[i].id === pid || list[i].playlistId === pid)) return list[i];
        }
        var fb = store.selectedFallback;
        return (fb && (fb.id === pid || fb.playlistId === pid)) ? fb : null;
    }
    property bool loaded: false
    readonly property bool busy: store._inFlight || store._queue.length > 0

    // A write did not reach disk. `error` is the backend code ("busy", "Playlist not found", ...) or "offline".
    signal writeFailed(string op, string error)

    property var _queue: []
    property bool _inFlight: false
    property var _lastResult: null
    property int _reloadAttempts: 0

    property Timer _retryTimer: Timer {
        interval: 1000
        repeat: false
        onTriggered: store.reload()
    }

    // --- Reads ---------------------------------------------------------------------------------------

    function playlistId(pl) {
        return pl ? String(pl.id || pl.playlistId || pl.browseId || "") : "";
    }

    // Single definition of custom playlist (GLOSSARY): flags like isCustom/isLocal are data, not a type.
    // Local albums (local_alb_*) also carry isLocal.
    function isCustom(pl) {
        var pid = (typeof pl === "string") ? pl : store.playlistId(pl);
        return pid.indexOf("custom_pl_") === 0;
    }

    function find(pid) {
        var list = store.customPlaylists || [];
        for (var i = 0; i < list.length; i++) {
            if (list[i] && (list[i].id === pid || list[i].playlistId === pid)) return list[i];
        }
        return null;
    }

    function isFavorite(plOrId) {
        var pid = (typeof plOrId === "string") ? plOrId : store.playlistId(plOrId);
        if (!pid) return false;
        return (store.favoritePlaylists || []).some(p => store.playlistId(p) === pid
            || String(p.playlistId || "") === pid || String(p.browseId || "") === pid);
    }

    // Same rule as playlist_manager.get_track_unique_key, so optimistic dedup matches the backend
    function trackKey(t) {
        if (!t) return "";
        if (typeof t === "string") return t.indexOf("ytdl://") === 0 ? "yt_" + t.substring(7) : "local_" + t;
        if (t.videoId) return "yt_" + t.videoId;
        if (t.path) return String(t.path).indexOf("ytdl://") === 0 ? "yt_" + String(t.path).substring(7) : "local_" + t.path;
        if (t.id) return "id_" + t.id;
        return t.title || "";
    }

    function select(pid, fallbackObj) {
        store.selectedFallback = fallbackObj || store.find(pid) || null;
        store.selectedId = pid || "";
    }

    function reload() {
        store._enqueue("list", {}, null, null);
    }

    // --- Writes --------------------------------------------------------------------------------------
    // onDone(result) runs only when the write reached disk (result.success).

    function create(title, desc, cover, tracks, onDone) {
        store._enqueue("create", {
            title: title || "", description: desc || "", cover: cover || "", tracks: tracks || []
        }, null, onDone);
    }

    function update(pid, title, desc, cover, onDone) {
        if (!pid) return;
        var body = { id: pid, title: title || "", description: desc || "" };
        if (cover !== undefined) body.cover = cover || "";
        store._enqueue("rename", body, function() {
            store._patch(pid, function(pl) {
                if (title && String(title).trim()) { pl.title = String(title).trim(); pl.name = pl.title; }
                pl.description = desc || "";
                if (cover !== undefined) {
                    pl.customCover = cover || "";
                    pl.image = pl.customCover || (pl.tracks && pl.tracks[0] ? (pl.tracks[0].image || "") : "");
                }
            });
        }, onDone);
    }

    function addTracks(pid, tracks, onDone) {
        if (!pid || !tracks || tracks.length === 0) return;
        store._enqueue("add", { id: pid, tracks: tracks }, function() {
            store._patch(pid, function(pl) {
                var trks = (pl.tracks || []).slice();
                var have = {};
                trks.forEach(t => { have[store.trackKey(t)] = true; });
                tracks.forEach(t => {
                    var k = store.trackKey(t);
                    if (k && !have[k]) { trks.push(t); have[k] = true; }
                });
                pl.tracks = trks;
                pl.trackCount = trks.length;
                if (!pl.image && trks[0]) pl.image = trks[0].image || trks[0].cover || "";
            });
        }, onDone);
    }

    function removeTrack(pid, track, onDone) {
        var ident = track ? String(track.path || track.videoId || "") : "";
        if (!pid || !ident) return;
        store._enqueue("remove", { id: pid, track: ident }, function() {
            store._patch(pid, function(pl) {
                pl.tracks = (pl.tracks || []).filter(t => t.path !== ident && t.videoId !== ident);
                pl.trackCount = pl.tracks.length;
                if (!pl.customCover) pl.image = pl.tracks[0] ? (pl.tracks[0].image || "") : "";
            });
        }, onDone);
    }

    function reorder(pid, fromIdx, toIdx, onDone) {
        if (!pid || fromIdx < 0 || toIdx < 0) return;
        store._enqueue("reorder", { id: pid, from: fromIdx, to: toIdx }, function() {
            store._patch(pid, function(pl) {
                var trks = (pl.tracks || []).slice();
                if (fromIdx >= trks.length || toIdx >= trks.length) return;
                trks.splice(toIdx, 0, trks.splice(fromIdx, 1)[0]);
                pl.tracks = trks;
                if (!pl.customCover && trks[0]) pl.image = trks[0].image || "";
            });
        }, onDone);
    }

    function remove(pid, onDone) {
        if (!pid) return;
        store._enqueue("delete", { id: pid }, function() {
            store.customPlaylists = (store.customPlaylists || []).filter(p => store.playlistId(p) !== pid);
            store.favoritePlaylists = (store.favoritePlaylists || []).filter(p => store.playlistId(p) !== pid);
            if (store.selectedId === pid) store.select("", null);
        }, onDone);
    }

    // `entry` is the normalized favorite (built by the caller, which knows how to resolve cover URLs)
    function toggleFavorite(entry, onDone) {
        var pid = store.playlistId(entry);
        if (!pid) return;
        var wasFav = store.isFavorite(pid);
        store._enqueue("toggle_favorite", { playlist: entry }, function() {
            if (wasFav) {
                store.favoritePlaylists = (store.favoritePlaylists || []).filter(p => store.playlistId(p) !== pid);
            } else {
                store.favoritePlaylists = [entry].concat(store.favoritePlaylists || []);
            }
        }, onDone);
    }

    // --- Queue ---------------------------------------------------------------------------------------

    function _patch(pid, mutate) {
        var list = (store.customPlaylists || []).slice();
        for (var i = 0; i < list.length; i++) {
            if (list[i] && (list[i].id === pid || list[i].playlistId === pid)) {
                var copy = Object.assign({}, list[i]);
                mutate(copy);
                list[i] = copy;
                store.customPlaylists = list;
                return;
            }
        }
        // Not loaded yet (opened from a fallback object): patch the fallback so the open view still updates
        var fb = store.selectedFallback;
        if (fb && (fb.id === pid || fb.playlistId === pid)) {
            var fcopy = Object.assign({}, fb);
            mutate(fcopy);
            store.selectedFallback = fcopy;
        }
    }

    function _enqueue(op, body, optimistic, onDone) {
        if (optimistic) optimistic();
        body.profile = store.profile;
        store._queue = store._queue.concat([{ op: op, body: body, onDone: onDone || null }]);
        store._pump();
    }

    function _pump() {
        if (store._inFlight || store._queue.length === 0) return;
        var job = store._queue[0];
        store._queue = store._queue.slice(1);
        store._inFlight = true;

        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            var res = null;
            try { res = xhr.responseText ? JSON.parse(xhr.responseText) : null; } catch (e) { res = null; }
            store._finish(job, xhr.status, res);
        };
        xhr.open("POST", store.apiUrl + "/api/playlists/" + job.op, true);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(JSON.stringify(job.body));
    }

    function _finish(job, status, res) {
        var hasState = res && Array.isArray(res.playlists) && Array.isArray(res.favorites);
        if (hasState) store._lastResult = res;
        var ok = status === 200 && res && res.success === true;
        store._inFlight = false;

        if (job.op === "list") {
            if (!hasState) {
                // Backend not up yet (startup) or gone: try again a few times, keep what is shown
                store._lastResult = null;
                if (store._reloadAttempts < 10) {
                    store._reloadAttempts++;
                    store._retryTimer.restart();
                }
            } else {
                store._reloadAttempts = 0;
                store.loaded = true;
            }
        } else if (!ok) {
            store.writeFailed(job.op, (res && res.error) ? String(res.error) : "offline");
        }

        if (store._queue.length === 0) {
            // Writes run in order, so the last result is the state on disk after all of them.
            // While more writes are queued their optimistic patches stay on screen instead.
            if (store._lastResult) {
                store.customPlaylists = store._lastResult.playlists;
                store.favoritePlaylists = store._lastResult.favorites;
                store._lastResult = null;
            } else if (job.op !== "list") {
                store.reload();
            }
        }

        if (ok && job.onDone) {
            try { job.onDone(res); } catch (e) { console.log("PlaylistStore onDone error:", e); }
        }
        store._pump();
    }
}
