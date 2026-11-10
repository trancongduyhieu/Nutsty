import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property var downloadTasks: ({}) // videoId -> task object
    property var tasksList: []
    property int revision: 0
    property var deletedIds: ({})
    property var deletedPaths: ({})
    property var deletedTitles: ({})
    onDownloadTasksChanged: {
        root.tasksList = root.getTasksList();
        root.revision++;
    }
    
    readonly property int activeTasksCount: {
        var cnt = 0;
        if (root.downloadTasks) {
            for (var k in root.downloadTasks) {
                var st = root.downloadTasks[k].state;
                if (st === 1 || st === 2) cnt++;
            }
        }
        return cnt;
    }

    property int activeDownloadsCount: activeTasksCount
    property int batchTotal: 0
    property int batchCompleted: 0
    property var activeQueue: []
    property var lastTaskStates: ({})

    signal taskEnqueued(var task)
    signal taskStarted(var task)
    signal taskProgress(string videoId, real progress, string speed, string eta)
    signal taskCompleted(string videoId, string title, string path)
    signal taskFailed(string videoId, string title, string error)

    function isDownloading(videoId) {
        if (!videoId || !root.downloadTasks) return false;
        var t = root.downloadTasks[videoId];
        return t && (t.state === 1 || t.state === 2);
    }

    function isDownloaded(videoId, trk) {
        if (!videoId && trk) {
            videoId = trk.videoId || "";
            if (!videoId && trk.path && trk.path.startsWith("ytdl://")) {
                videoId = trk.path.replace("ytdl://", "");
            }
        }
        if (videoId && root.deletedIds && root.deletedIds[videoId]) return false;
        var trkPath = trk ? (trk.path || "") : "";
        if (trkPath && root.deletedPaths && root.deletedPaths[trkPath]) return false;
        var trkTitle = trk ? (trk.title || trk.name || "") : "";
        if (trkTitle && root.deletedTitles && root.deletedTitles[trkTitle.toLowerCase().trim()]) return false;

        if (videoId && root.downloadTasks && root.downloadTasks[videoId]) {
            var t = root.downloadTasks[videoId];
            if (t.state === 3) return true;
            if (t.state === 1 || t.state === 2) return false;
        }

        if (trkPath && !trkPath.startsWith("ytdl://") && !trkPath.startsWith("http")) {
            return true;
        }

        if (typeof win !== "undefined" && win && win.allTracks) {
            var rawT = trkTitle.toLowerCase().trim();
            var cT = root.cleanTitle(trkTitle);
            for (var i = 0; i < win.allTracks.length; ++i) {
                var at = win.allTracks[i];
                if (videoId && at.videoId && at.videoId === videoId) return true;
                if (videoId && at.image && at.image.indexOf(videoId) !== -1) return true;
                var atRaw = (at.title || at.name || "").toLowerCase().trim();
                var atClean = root.cleanTitle(at.title || at.name || "");
                if (rawT && atRaw && rawT === atRaw) return true;
                if (cT && atClean && (cT === atClean || atClean.indexOf(cT) !== -1 || cT.indexOf(atClean) !== -1)) return true;
            }
        }
        return false;
    }

    function getProgress(videoId) {
        if (!videoId || !root.downloadTasks) return -1;
        var t = root.downloadTasks[videoId];
        return t ? t.progress : -1;
    }

    function enqueue(trk) {
        if (!trk) return;
        var vid = trk.videoId || "";
        if (!vid && trk.path && trk.path.startsWith("ytdl://")) {
            vid = trk.path.replace("ytdl://", "");
        } else if (!vid && trk.path && trk.path.includes("watch?v=")) {
            var match = trk.path.match(/v=([a-zA-Z0-9_-]+)/);
            if (match) vid = match[1];
        }
        if (!vid) return;

        // Clear any previous deleted flags for this track
        if (root.deletedIds && root.deletedIds[vid]) {
            var dIds = Object.assign({}, root.deletedIds);
            delete dIds[vid];
            root.deletedIds = dIds;
        }
        var songTitle = trk.title || trk.name || "Track";
        var normTitle = songTitle.toLowerCase().trim();
        if (root.deletedTitles && root.deletedTitles[normTitle]) {
            var dTitles = Object.assign({}, root.deletedTitles);
            delete dTitles[normTitle];
            root.deletedTitles = dTitles;
        }
        if (trk.path && root.deletedPaths && root.deletedPaths[trk.path]) {
            var dPaths = Object.assign({}, root.deletedPaths);
            delete dPaths[trk.path];
            root.deletedPaths = dPaths;
        }

        var title = songTitle;
        var artist = trk.artist || "Artist";
        var thumb = trk.image || "";

        // Immediately reflect in local state for 0ms visual feedback
        var updated = Object.assign({}, root.downloadTasks);
        updated[vid] = {
            videoId: vid,
            title: title,
            artist: artist,
            thumbnail: thumb,
            state: 1, // PREPARING
            progress: 0.0,
            speed: "--",
            eta: "--"
        };
        root.downloadTasks = updated;
        root.tasksList = root.getTasksList();
        root.revision++;

        Quickshell.execDetached([
            "python3", win.appDir + "/backend/download_manager.py", "add",
            vid, title, artist, thumb, (win.downloadQuality || "high_opus")
        ]);
    }

    property var cancelledTimestamps: ({})

    function isPathDeleted(p) {
        if (!p) return false;
        return !!(root.deletedPaths && root.deletedPaths[p]);
    }

    function isIdDeleted(vid) {
        if (!vid) return false;
        return !!(root.deletedIds && root.deletedIds[vid]);
    }

    function isTitleDeleted(t) {
        if (!t) return false;
        var raw = (t || "").toLowerCase().trim();
        if (root.deletedTitles && root.deletedTitles[raw]) return true;
        var clean = root.cleanTitle(t);
        if (clean && root.deletedTitles && root.deletedTitles[clean]) return true;
        return false;
    }

    function markPathDeleted(p) {
        if (!p) return;
        var dPaths = Object.assign({}, root.deletedPaths || {});
        dPaths[p] = true;
        root.deletedPaths = dPaths;
    }

    function markIdDeleted(vid) {
        if (!vid) return;
        var dIds = Object.assign({}, root.deletedIds || {});
        dIds[vid] = true;
        root.deletedIds = dIds;
    }

    function markTitleDeleted(t) {
        if (!t) return;
        var dTitles = Object.assign({}, root.deletedTitles || {});
        dTitles[t.toLowerCase().trim()] = true;
        var c = root.cleanTitle(t);
        if (c) dTitles[c] = true;
        root.deletedTitles = dTitles;
    }

    function cancel(videoId) {
        if (!videoId) return;
        var cts = Object.assign({}, root.cancelledTimestamps || {});
        cts[videoId] = Date.now();
        root.cancelledTimestamps = cts;

        var dIds = Object.assign({}, root.deletedIds || {});
        dIds[videoId] = true;
        root.deletedIds = dIds;

        var updated = Object.assign({}, root.downloadTasks);
        delete updated[videoId];
        root.downloadTasks = updated;
        root.tasksList = root.getTasksList();
        root.revision++;

        Quickshell.execDetached([
            "python3", win.appDir + "/backend/download_manager.py", "cancel",
            videoId
        ]);
    }

    function cleanTitle(s) {
        if (!s) return "";
        return String(s)
            .toLowerCase()
            .replace(/\(feat\.?[^\)]*\)/gi, "")
            .replace(/\[feat\.?[^\]]*\]/gi, "")
            .replace(/\(ft\.?[^\)]*\)/gi, "")
            .replace(/\[ft\.?[^\]]*\]/gi, "")
            .replace(/\(official[^\)]*\)/gi, "")
            .replace(/\[official[^\]]*\]/gi, "")
            .replace(/\(mv[^\)]*\)/gi, "")
            .replace(/\[mv[^\]]*\]/gi, "")
            .replace(/\(audio[^\)]*\)/gi, "")
            .replace(/\[audio[^\]]*\]/gi, "")
            .replace(/\(lyric[^\)]*\)/gi, "")
            .replace(/\[lyric[^\]]*\]/gi, "")
            .replace(/[-–—_]/g, " ")
            .replace(/\s+/g, " ")
            .trim();
    }

    function deleteDownloaded(videoId, trk) {
        if (!videoId && trk) {
            videoId = trk.videoId || "";
            if (!videoId && trk.path && trk.path.startsWith("ytdl://")) {
                videoId = trk.path.replace("ytdl://", "");
            }
        }
        if (!videoId && (!trk || !(trk.title || trk.name))) return;

        var updated = Object.assign({}, root.downloadTasks);
        var task = updated[videoId];
        var filePath = (task && task.path) ? task.path : "";
        if (!filePath && trk && trk.path && !trk.path.startsWith("ytdl://")) {
            filePath = trk.path;
        }

        var songTitle = (trk && (trk.title || trk.name)) ? (trk.title || trk.name) : (task ? task.title : "");

        // 1. Try reading status file if path not found yet
        if (!filePath && videoId) {
            try {
                var sTxt = statusFileView.text();
                if (sTxt) {
                    var sData = JSON.parse(sTxt);
                    if (sData && sData.tasks && sData.tasks[videoId] && sData.tasks[videoId].path) {
                        filePath = sData.tasks[videoId].path;
                        if (!songTitle && sData.tasks[videoId].title) songTitle = sData.tasks[videoId].title;
                    }
                }
            } catch(e) {}
        }

        // 2. Fuzzy match in win.allTracks using exact and cleanTitle
        var matchedTitle = songTitle;
        var matchedFn = "";
        if ((!filePath || filePath.startsWith("ytdl://")) && typeof win !== "undefined" && win && win.allTracks) {
            var rawT = (songTitle || "").toLowerCase().trim();
            var cT = root.cleanTitle(songTitle);
            for (var i = 0; i < win.allTracks.length; ++i) {
                var at = win.allTracks[i];
                var atRaw = (at.title || at.name || "").toLowerCase().trim();
                var atClean = root.cleanTitle(at.title || at.name || "");
                var isMatch = false;
                if (videoId && at.videoId && at.videoId === videoId) isMatch = true;
                else if (videoId && at.image && at.image.indexOf(videoId) !== -1) isMatch = true;
                else if (rawT && atRaw && rawT === atRaw) isMatch = true;
                else if (cT && atClean && (cT === atClean || atClean.indexOf(cT) !== -1 || cT.indexOf(atClean) !== -1)) isMatch = true;

                if (isMatch) {
                    filePath = at.path || "";
                    matchedTitle = at.title || at.name || songTitle;
                    matchedFn = at.filename || "";
                    break;
                }
            }
        }

        // Instantly mark in deleted cache for 0ms UI reactivity
        if (videoId) {
            var dIds = Object.assign({}, root.deletedIds || {});
            dIds[videoId] = true;
            root.deletedIds = dIds;

            var cts = Object.assign({}, root.cancelledTimestamps || {});
            cts[videoId] = Date.now();
            root.cancelledTimestamps = cts;
        }
        if (filePath) {
            var dPaths = Object.assign({}, root.deletedPaths || {});
            dPaths[filePath] = true;
            root.deletedPaths = dPaths;
        }
        if (songTitle) {
            var dTitles = Object.assign({}, root.deletedTitles || {});
            dTitles[songTitle.toLowerCase().trim()] = true;
            var cTitle = root.cleanTitle(songTitle);
            if (cTitle) dTitles[cTitle] = true;
            if (matchedTitle) {
                dTitles[matchedTitle.toLowerCase().trim()] = true;
                var cmTitle = root.cleanTitle(matchedTitle);
                if (cmTitle) dTitles[cmTitle] = true;
            }
            root.deletedTitles = dTitles;
        }

        // 3. Instantly update in-memory state for 0ms UI reactivity
        if (videoId && updated[videoId]) {
            delete updated[videoId];
            root.downloadTasks = updated;
        }

        // Update active track in win if this is the playing track
        if (typeof win !== "undefined" && win && win.currentTrack) {
            var ct = win.currentTrack;
            var isCurr = false;
            if (videoId && ct.videoId === videoId) isCurr = true;
            if (filePath && ct.path === filePath) isCurr = true;
            var ctName = (ct.title || ct.name || "").toLowerCase().trim();
            if (songTitle && ctName === songTitle.toLowerCase().trim()) isCurr = true;
            if (matchedTitle && ctName === matchedTitle.toLowerCase().trim()) isCurr = true;
            if (isCurr) {
                if (videoId) {
                    ct.path = "ytdl://" + videoId;
                }
                ct.isLocal = false;
            }
        }

        // 4. Immediately filter win.allTracks and win.browsingTracks
        if (typeof win !== "undefined" && win && win.allTracks) {
            var delRaw = (matchedTitle || songTitle || "").toLowerCase().trim();
            var delClean = root.cleanTitle(matchedTitle || songTitle);
            win.allTracks = win.allTracks.filter(function(item) {
                if (filePath && item.path === filePath) return false;
                if (videoId && ((item.videoId && item.videoId === videoId) || (item.image && item.image.indexOf(videoId) !== -1))) return false;
                var iname = (item.title || item.name || "").toLowerCase().trim();
                var iclean = root.cleanTitle(item.title || item.name || "");
                if (delRaw && iname && iname === delRaw) return false;
                if (delClean && iclean && (iclean === delClean || iclean.indexOf(delClean) !== -1 || delClean.indexOf(iclean) !== -1)) return false;
                return true;
            });
            if (win.currentView === "library") {
                win.browsingTracks = win.allTracks;
            }
        }

        root.tasksList = root.getTasksList();
        root.revision++;

        // 5. Call nutsty-library to delete file, .lrc and update library.json
        Quickshell.execDetached([
            win.appDir + "/bin/nutsty-library", "delete",
            filePath, matchedFn, matchedTitle || songTitle
        ]);

        // Direct rm fallback in case path is known
        if (filePath && filePath.startsWith("/")) {
            Quickshell.execDetached(["rm", "-f", filePath, filePath.replace(/\.[^.]+$/, ".lrc")]);
        }

        // 6. Remove task from download_manager daemon
        if (videoId) {
            Quickshell.execDetached([
                "python3", win.appDir + "/backend/download_manager.py", "remove",
                videoId
            ]);
        }

        // 7. Schedule debounced library reload once nutsty-library finishes writing
        libReloadDebounceTimer.restart();

        // 8. Desktop notification
        Quickshell.execDetached([
            "notify-send", "Nutsty",
            "Đã xóa bài hát khỏi thư viện tải về: " + (matchedTitle || songTitle),
            "-a", "Nutsty"
        ]);
    }

    function getTasksList() {
        if (!root.downloadTasks) return [];
        var arr = [];
        for (var k in root.downloadTasks) {
            arr.push(root.downloadTasks[k]);
        }
        return arr;
    }

    function clearCompleted() {
        Quickshell.execDetached([
            "python3", win.appDir + "/backend/download_manager.py", "clear_completed"
        ]);
        var updated = {};
        for (var k in root.downloadTasks) {
            var t = root.downloadTasks[k];
            if (t.state === 1 || t.state === 2) {
                updated[k] = t;
            }
        }
        root.downloadTasks = updated;
        root.tasksList = root.getTasksList();
        root.revision++;
    }

    function syncFromStatusFile() {
        var txt = statusFileView.text();
        if (!txt || txt.trim() === "") return;
        try {
            var data = JSON.parse(txt);
            if (!data) return;

            if (data.tasks) {
                var prevStates = root.lastTaskStates || {};
                var newStates = {};
                var tasks = data.tasks;

                var nowMs = Date.now();
                var cts = root.cancelledTimestamps || {};
                var dIds = root.deletedIds || {};
                var filteredTasks = {};

                for (var vid in tasks) {
                    if (dIds[vid]) {
                        continue;
                    }
                    if (cts[vid] && (nowMs - cts[vid]) < 5000) {
                        continue;
                    }
                    var t = tasks[vid];
                    var prevState = prevStates[vid];
                    newStates[vid] = t.state;

                    // Detect completion event
                    if (t.state === 3 && prevState !== 3) {
                        root.taskCompleted(vid, t.title || "", t.path || "");
                    } else if (t.state === 4 && prevState !== 4) {
                        root.taskFailed(vid, t.title || "", t.error || "");
                    }
                    filteredTasks[vid] = t;
                }

                root.lastTaskStates = newStates;
                root.downloadTasks = filteredTasks;
                root.tasksList = root.getTasksList();
                root.revision++;
            }

            if (data.batch_total !== undefined) {
                root.batchTotal = data.batch_total;
            }
            if (data.batch_completed !== undefined) {
                root.batchCompleted = data.batch_completed;
            }
        } catch(e) {}
    }

    function handleEvent(line) {
        if (!line || line.trim() === "") return;
        try {
            var data = JSON.parse(line.trim());
            var evt = data.event;

            if (evt === "task_enqueued" || evt === "task_started") {
                var vid = data.videoId;
                if (root.deletedIds && root.deletedIds[vid]) return;
                var updated = Object.assign({}, root.downloadTasks);
                var existing = updated[vid] || {};
                existing.videoId = vid;
                existing.title = data.title || existing.title || "Track";
                existing.artist = data.artist || existing.artist || "Artist";
                existing.thumbnail = data.thumbnail || existing.thumbnail || "";
                existing.state = 2; // DOWNLOADING
                if (data.progress !== undefined) existing.progress = data.progress;
                updated[vid] = existing;
                root.downloadTasks = updated;
                root.tasksList = root.getTasksList();
                root.revision++;
                if (data.batch_total !== undefined) root.batchTotal = data.batch_total;
                root.taskStarted(existing);
            }
            else if (evt === "task_progress") {
                var vid = data.videoId;
                if (root.deletedIds && root.deletedIds[vid]) return;
                if (root.downloadTasks[vid]) {
                    var updated = Object.assign({}, root.downloadTasks);
                    updated[vid].progress = data.progress;
                    updated[vid].speed = data.speed;
                    updated[vid].eta = data.eta;
                    updated[vid].state = 2;
                    root.downloadTasks = updated;
                    root.taskProgress(vid, data.progress, data.speed, data.eta);
                }
            }
            else if (evt === "task_completed") {
                var vid = data.videoId;
                if (root.deletedIds && root.deletedIds[vid]) return;
                var updated = Object.assign({}, root.downloadTasks);
                if (updated[vid]) {
                    updated[vid].state = 3; // DOWNLOADED
                    updated[vid].progress = 100.0;
                    updated[vid].path = data.path || "";
                } else {
                    updated[vid] = {
                        videoId: vid,
                        title: data.title,
                        state: 3,
                        progress: 100.0,
                        path: data.path || ""
                    };
                }
                root.downloadTasks = updated;
                root.tasksList = root.getTasksList();
                root.revision++;
                root.taskCompleted(vid, data.title || "", data.path || "");
            }
            else if (evt === "task_failed") {
                var vid = data.videoId;
                var updated = Object.assign({}, root.downloadTasks);
                if (updated[vid]) {
                    updated[vid].state = 4; // FAILED
                    updated[vid].error = data.error || "Failed";
                }
                root.downloadTasks = updated;
                root.tasksList = root.getTasksList();
                root.revision++;
                root.taskFailed(vid, data.title || "", data.error || "");
            }
            else if (evt === "task_cancelled" || evt === "task_removed") {
                var vid = data.videoId;
                if (root.downloadTasks && root.downloadTasks[vid]) {
                    var updated = Object.assign({}, root.downloadTasks);
                    delete updated[vid];
                    root.downloadTasks = updated;
                    root.tasksList = root.getTasksList();
                    root.revision++;
                }
            }
            else if (evt === "status_dump" || evt === "completed_cleared") {
                if (data.tasks) {
                    var tasks = data.tasks;
                    var dIds = root.deletedIds || {};
                    var filtered = {};
                    for (var k in tasks) {
                        if (!dIds[k]) filtered[k] = tasks[k];
                    }
                    root.downloadTasks = filtered;
                    root.tasksList = root.getTasksList();
                    root.revision++;
                }
            }
        } catch(e) {}
    }

    FileView {
        id: statusFileView
        path: "/tmp/nutsty_download_status" + (Quickshell.env("NUTSTY_PROFILE") ? ("_" + Quickshell.env("NUTSTY_PROFILE").toLowerCase()) : "") + ".json"
        watchChanges: true
        onFileChanged: {
            reload();
            root.syncFromStatusFile();
        }
    }

    Timer {
        id: statusPollTimer
        interval: root.activeTasksCount > 0 ? 250 : 5000
        repeat: true
        running: true
        onTriggered: {
            if (root.activeTasksCount > 0 || statusFileView.exists) {
                statusFileView.reload();
                root.syncFromStatusFile();
            }
        }
    }

    Process {
        id: downloadDaemonProc
        command: ["python3", "-u", win.appDir + "/backend/download_manager.py", "daemon"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root.handleEvent(data)
        }
    }

    Timer {
        id: libReloadDebounceTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (typeof libLoader !== "undefined" && libLoader && libLoader.reload) {
                libLoader.reload();
            }
        }
    }
}
