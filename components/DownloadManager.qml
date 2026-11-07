import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property var downloadTasks: ({}) // videoId -> task object
    property var tasksList: []
    onDownloadTasksChanged: root.tasksList = root.getTasksList()
    
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

    function isDownloaded(videoId) {
        if (!videoId || !root.downloadTasks) return false;
        var t = root.downloadTasks[videoId];
        return t && t.state === 3;
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

        var title = trk.title || trk.name || "Track";
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

        Quickshell.execDetached([
            "python3", win.appDir + "/backend/download_manager.py", "add",
            vid, title, artist, thumb, (win.downloadQuality || "high_opus")
        ]);
    }

    property var cancelledTimestamps: ({})

    function cancel(videoId) {
        if (!videoId) return;
        var cts = Object.assign({}, root.cancelledTimestamps || {});
        cts[videoId] = Date.now();
        root.cancelledTimestamps = cts;

        var updated = Object.assign({}, root.downloadTasks);
        delete updated[videoId];
        root.downloadTasks = updated;
        root.tasksList = root.getTasksList();

        Quickshell.execDetached([
            "python3", win.appDir + "/backend/download_manager.py", "cancel",
            videoId
        ]);
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

        // Find file path in win.allTracks if not set yet
        if ((!filePath || filePath.startsWith("ytdl://")) && typeof win !== "undefined" && win && win.allTracks) {
            var tName = (songTitle || "").toLowerCase().trim();
            for (var i = 0; i < win.allTracks.length; ++i) {
                var at = win.allTracks[i];
                if ((videoId && at.image && at.image.indexOf(videoId) !== -1) || 
                    (tName && (at.title || at.name || "").toLowerCase().trim() === tName)) {
                    filePath = at.path || "";
                    if (!songTitle) songTitle = at.title || at.name || "";
                    break;
                }
            }
        }

        // 1. Instantly update in-memory state for 0ms UI reactivity
        if (videoId && updated[videoId]) {
            delete updated[videoId];
            root.downloadTasks = updated;
            root.tasksList = root.getTasksList();
        }

        if (typeof win !== "undefined" && win && win.allTracks) {
            win.allTracks = win.allTracks.filter(function(item) {
                if (filePath && item.path === filePath) return false;
                if (videoId && item.image && item.image.indexOf(videoId) !== -1) return false;
                var iname = (item.title || item.name || "").toLowerCase().trim();
                if (songTitle && iname && iname === (songTitle || "").toLowerCase().trim()) return false;
                return true;
            });
        }

        // 2. Call nutsty-library to delete file, .lrc and update library.json
        Quickshell.execDetached([
            win.appDir + "/bin/nutsty-library", "delete",
            filePath, "", songTitle
        ]);

        // 3. Remove task from download_manager daemon
        if (videoId) {
            Quickshell.execDetached([
                "python3", win.appDir + "/backend/download_manager.py", "remove",
                videoId
            ]);
        }

        // 4. Reload library model if available
        if (typeof libLoader !== "undefined" && libLoader && libLoader.reload) {
            libLoader.reload();
        }

        // 5. Desktop notification
        Quickshell.execDetached([
            "notify-send", "Nutsty",
            "Đã xóa bài hát khỏi thư viện tải về: " + songTitle,
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
                var filteredTasks = {};

                for (var vid in tasks) {
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
                if (data.batch_total !== undefined) root.batchTotal = data.batch_total;
                root.taskStarted(existing);
            }
            else if (evt === "task_progress") {
                var vid = data.videoId;
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
                root.taskFailed(vid, data.title || "", data.error || "");
            }
            else if (evt === "status_dump") {
                if (data.tasks) {
                    root.downloadTasks = Object.assign({}, data.tasks);
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
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            statusFileView.reload();
            root.syncFromStatusFile();
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
}
