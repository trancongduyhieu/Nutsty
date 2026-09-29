// Nutsty Playback & Browse Engine (Playback Execution, Queue Lifecycle, Radio & MPV Status Handlers)
// Deep frontend module consolidating all audio playback state machines, IPC triggers, and queue mutators.

function isSameTrack(a, b) {
    if (!a || !b) return false;
    if (a.path && b.path && a.path === b.path) return true;
    var vidA = a.videoId || (a.path && a.path.startsWith("ytdl://") ? a.path.replace("ytdl://", "") : "");
    var vidB = b.videoId || (b.path && b.path.startsWith("ytdl://") ? b.path.replace("ytdl://", "") : "");
    if (vidA && vidB && vidA === vidB) return true;
    var nameA = a.title || a.name || "";
    var nameB = b.title || b.name || "";
    if (nameA && nameB && nameA === nameB && a.artist && b.artist && a.artist === b.artist) return true;
    return false;
}

function findLocalDownloadedTrack(win, trk) {
    if (!trk) return null;
    var rVid = trk.videoId || trk.id || (trk.path && trk.path.startsWith("ytdl://") ? trk.path.replace("ytdl://", "") : "");
    if (rVid && String(rVid).startsWith("yt_")) rVid = String(rVid).replace(/^yt_/, "");

    if (trk.path && win.isLocalPathExisting(trk.path)) {
        return trk;
    }

    var dlRef = (typeof downloadManager !== "undefined" && downloadManager) ? downloadManager : ((typeof DownloadManager !== "undefined") ? DownloadManager : null);
    if (rVid && dlRef && dlRef.downloadTasks) {
        var dTask = dlRef.downloadTasks[rVid];
        if (dTask && (dTask.state === 3 || dTask.status === "completed") && dTask.path && win.isLocalPathExisting(dTask.path)) {
            return {
                path: dTask.path,
                videoId: rVid,
                title: dTask.title || trk.title || trk.name || "",
                name: dTask.title || trk.title || trk.name || "",
                artist: dTask.artist || trk.artist || "",
                image: trk.image || trk.cover || dTask.thumbnail || ""
            };
        }
    }

    var tName = String(trk.title || trk.name || "").toLowerCase().trim();
    var tArtist = String(trk.artist || "").toLowerCase().trim();
    if (win.allTracks && win.allTracks.length > 0) {
        for (var i = 0; i < win.allTracks.length; i++) {
            var lt = win.allTracks[i];
            if (!lt || !lt.path || !win.isLocalPathExisting(lt.path)) continue;
            var ltVid = lt.videoId || "";
            if (rVid && (ltVid === rVid || (lt.image && String(lt.image).indexOf(rVid) !== -1))) {
                return lt;
            }
            var ltName = String(lt.title || lt.name || "").toLowerCase().trim();
            var ltArtist = String(lt.artist || "").toLowerCase().trim();
            if (tName && ltName === tName && (!tArtist || !ltArtist || ltArtist.indexOf(tArtist) !== -1 || tArtist.indexOf(ltArtist) !== -1)) {
                return lt;
            }
        }
    }
    return null;
}

function playOnlineTrack(win, trk, startRadio, radioProc, prewarmTimer, pollTimer) {
    if (!trk) return;
    if (win.listeningAlongFriend && !win.isSyncingFromFriend && !win.guestCanControlHost) {
        win.suggestTrackToHost(trk);
        return;
    }
    if (!win.isSyncingFromFriend) {
        win.pendingListenAlongSeekPosition = 0.0;
        win.lastTrackSwitchTimestamp = Date.now();
        win.lastLocalActionTimestamp = Date.now();
    }
    var rVid = trk.videoId || trk.id || (trk.path && trk.path.startsWith("ytdl://") ? trk.path.replace("ytdl://", "") : "");
    if (rVid && rVid.startsWith("yt_")) {
        rVid = rVid.replace(/^yt_/, "");
    }
    if (!rVid) {
        if (trk.path && !trk.path.startsWith("ytdl://")) {
            win.playTrack(trk);
            return;
        }
        if (trk.title) {
            var searchQuery = trk.title + (trk.artist ? (" " + trk.artist) : "");
            var xhr = new XMLHttpRequest();
            var searchUrl = "http://127.0.0.1:17890/api/filter_search?q=" + encodeURIComponent(searchQuery) + "&filter=songs";
            xhr.open("GET", searchUrl, true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                    try {
                        var res = JSON.parse(xhr.responseText);
                        if (Array.isArray(res) && res.length > 0 && (res[0].videoId || res[0].id)) {
                            win.playOnlineTrack(res[0], startRadio);
                        }
                    } catch(e) {
                        console.warn("Nutsty: fallback search parse error", e);
                    }
                }
            };
            xhr.send();
            return;
        }
        console.warn("Nutsty: playOnlineTrack called without valid videoId or local path", JSON.stringify(trk));
        return;
    }
    if (!trk.videoId && rVid) {
        trk.videoId = rVid;
    }
    if (!trk.path && rVid) {
        trk.path = "ytdl://" + rVid;
    }
    if (!trk.image && trk.cover) {
        trk.image = trk.cover;
    }
    if (win.isLoadingAudio && win.currentTrack && win.isSameTrack(win.currentTrack, trk)) {
        return;
    }
    if (startRadio === undefined) startRadio = false;

    var localMatch = win.findLocalDownloadedTrack(trk);
    var hasLocalFile = Boolean(localMatch && localMatch.path);

    win.trackChangeTimestamp = Date.now();
    win.postLoadGraceTimestamp = Date.now();
    win.currentTrack = trk;
    win.currentTime = 0.0;
    win.lastSyncTime = 0.0;
    win.lastSyncTimestamp = Date.now();
    win.isLoadingAudio = !hasLocalFile;
    win.totalDuration = 0.0;
    win.isPlaying = true;
    if (win.currentView !== "search") {
        win.showAmberolDetails = true;
    } else {
        win.showAmberolDetails = false;
    }

    if (win.syncHistoryToGoogle) {
        win.trackPlayback(trk);
    }

    if (startRadio || !win.currentTracks || win.currentTracks.length === 0) {
        win.currentTracks = [trk];
    } else {
        var foundIdx = -1;
        for (var qi = 0; qi < win.currentTracks.length; qi++) {
            if (win.isSameTrack(win.currentTracks[qi], trk)) {
                foundIdx = qi;
                break;
            }
        }
        if (foundIdx === -1) {
            win.currentTracks = [trk];
        }
    }

    var streamPath = hasLocalFile ? localMatch.path : ("ytdl://" + rVid);
    var tTitle = trk.title || trk.name || (localMatch ? (localMatch.title || localMatch.name || "") : "");
    var tArtist = trk.artist || (localMatch ? (localMatch.artist || "") : "");
    var tImage = trk.image || trk.cover || (localMatch ? (localMatch.image || "") : "");
    Quickshell.execDetached(["python3", win.appDir + "/backend/player_daemon.py", "play", streamPath, tTitle, tArtist, tImage]);
    win.syncNowPlaying(true);
    if (!win.isSyncingFromFriend) {
        if (win.activeCoListeners && win.activeCoListeners.length > 0) {
            for (var cli = 0; cli < win.activeCoListeners.length; cli++) {
                win.sendSocialEventFast("track_change", win.activeCoListeners[cli], { track: trk });
            }
        }
        if (win.listeningAlongFriend && win.guestCanControlHost) {
            var hostTarget = win.listeningAlongFriend.tag || win.listeningAlongFriend.user_id || win.listeningAlongFriend.user_email || "";
            if (hostTarget) {
                win.sendSocialEventFast("track_change", hostTarget, { track: trk });
            }
        }
    }

    if (win.currentTracks && win.currentTracks.length > 1 && prewarmTimer) {
        var curIdx = -1;
        for (var ci = 0; ci < win.currentTracks.length; ci++) {
            if (win.isSameTrack(win.currentTracks[ci], trk)) {
                curIdx = ci;
                break;
            }
        }
        var nextIdx = (curIdx !== -1 && curIdx + 1 < win.currentTracks.length) ? (curIdx + 1) : 0;
        var nextTrk = win.currentTracks[nextIdx];
        var nextVid = (nextTrk && (nextTrk.videoId || (nextTrk.path && nextTrk.path.startsWith("ytdl://"))))
            ? (nextTrk.videoId || nextTrk.path.replace("ytdl://", ""))
            : "";
        if (nextVid) {
            prewarmTimer.targetVid = nextVid;
            prewarmTimer.restart();
        }
    }

    if ((startRadio || (!win.playingPlaylistId && (!win.currentTracks || win.currentTracks.length <= 1))) && rVid && radioProc) {
        radioProc.running = false;
        radioProc.command = ["python3", "-u", win.appDir + "/backend/ytmusic_helper.py", "radio", rVid];
        radioProc.running = true;
    }
    if (pollTimer) pollTimer.restart();
}

function playTrack(win, trk, pollTimer) {
    if (!trk) return;
    if (win.listeningAlongFriend && !win.isSyncingFromFriend && !win.guestCanControlHost) {
        win.suggestTrackToHost(trk);
        return;
    }
    if (!win.isSyncingFromFriend) {
        win.pendingListenAlongSeekPosition = 0.0;
        win.lastTrackSwitchTimestamp = Date.now();
        win.lastLocalActionTimestamp = Date.now();
    }
    if (win.currentTrack && win.isSameTrack(win.currentTrack, trk) && win.isPlaying) {
        return;
    }
    win.trackChangeTimestamp = Date.now();
    win.postLoadGraceTimestamp = Date.now();
    win.currentTrack = trk;
    win.currentTime = 0.0;
    win.lastSyncTime = 0.0;
    win.lastSyncTimestamp = Date.now();
    win.isLoadingAudio = false;
    win.totalDuration = (trk.durationMs || 0) / 1000.0;
    win.isPlaying = true;
    if (win.currentView !== "search") {
        win.isNowPlayingOpen = true;
    } else {
        win.isNowPlayingOpen = false;
    }

    if (win.syncHistoryToGoogle) {
        win.trackPlayback(trk);
    }

    var tTitle = trk.title || trk.name || "";
    var tArtist = trk.artist || "";
    var tImage = trk.image || "";
    Quickshell.execDetached(["python3", win.appDir + "/backend/player_daemon.py", "play", trk.path, tTitle, tArtist, tImage]);
    win.syncNowPlaying(true);
    if (!win.isSyncingFromFriend) {
        if (win.activeCoListeners && win.activeCoListeners.length > 0) {
            for (var cli2 = 0; cli2 < win.activeCoListeners.length; cli2++) {
                win.sendSocialEventFast("track_change", win.activeCoListeners[cli2], { track: trk });
            }
        }
        if (win.listeningAlongFriend && win.guestCanControlHost) {
            var hostTarget2 = win.listeningAlongFriend.tag || win.listeningAlongFriend.user_id || win.listeningAlongFriend.user_email || "";
            if (hostTarget2) {
                win.sendSocialEventFast("track_change", hostTarget2, { track: trk });
            }
        }
    }
    if (pollTimer) pollTimer.restart();
}

function togglePlay(win, pollTimer) {
    if (!win.currentTrack) return;
    if (win.listeningAlongFriend && !win.isSyncingFromFriend && !win.guestCanControlHost) {
        win.showToast(I18n.tr("Host đã khóa quyền điều khiển chung", "Host disabled shared control"));
        return;
    }
    var targetPath = win.currentTrack.path || "";
    var isOnline = (targetPath && targetPath.startsWith("ytdl://")) || win.currentTrack.videoId;

    if (win.isLoadingAudio) {
        win.isLoadingAudio = false;
        win.isPlaying = false;
        win.lastSyncTimestamp = 0;
        Quickshell.execDetached(["python3", win.appDir + "/backend/player_daemon.py", "pause"]);
        if (pollTimer) pollTimer.restart();
        win.syncNowPlaying(true);
        return;
    }

    if (!win.isPlaying) {
        win.postLoadGraceTimestamp = Date.now();
        if (isOnline && (win.currentTime === 0.0 || win.totalDuration === 0.0)) {
            win.isLoadingAudio = true;
            win.trackChangeTimestamp = Date.now();
        }
        win.isPlaying = true;
        win.lastSyncTime = win.currentTime;
        win.lastSyncTimestamp = Date.now();
        Quickshell.execDetached(["python3", win.appDir + "/backend/player_daemon.py", "resume", targetPath]);
    } else {
        win.isPlaying = false;
        win.isLoadingAudio = false;
        win.lastSyncTimestamp = 0;
        Quickshell.execDetached(["python3", win.appDir + "/backend/player_daemon.py", "pause"]);
    }

    win.lastLocalActionTimestamp = Date.now();
    win.syncNowPlaying(true);

    if (!win.isSyncingFromFriend) {
        var evType = win.isPlaying ? "play" : "pause";
        if (win.listeningAlongFriend && win.guestCanControlHost) {
            var hostPlayTarget = win.listeningAlongFriend.tag || win.listeningAlongFriend.user_id || win.listeningAlongFriend.user_email || "";
            if (hostPlayTarget) {
                win.sendSocialEventFast(evType, hostPlayTarget);
            }
        }
        if (win.activeCoListeners && win.activeCoListeners.length > 0) {
            for (var li = 0; li < win.activeCoListeners.length; li++) {
                win.sendSocialEventFast(evType, win.activeCoListeners[li]);
            }
        }
    }

    if (pollTimer) pollTimer.restart();
}

function playNext(win) {
    if (win.listeningAlongFriend && !win.isSyncingFromFriend && !win.guestCanControlHost) {
        win.showToast(I18n.tr("Host đã khóa quyền chuyển bài hát", "Host disabled track skipping"));
        return;
    }
    if (win.isSleepTimerActive && win.sleepTimerMode === "end_of_track") {
        win.isSleepTimerActive = false;
        win.sleepTimerFadeTriggered = false;
        win.sleepTimerMode = "";
        win.sleepTimerRemainingSeconds = 0;
        win.isPlaying = false;
        Quickshell.execDetached(["python3", win.appDir + "/backend/player_daemon.py", "pause"]);
        return;
    }
    if (!win.currentTrack || !win.currentTracks || win.currentTracks.length === 0) return;
    var curIdx = win.currentTracks.findIndex(t => win.isSameTrack(t, win.currentTrack));
    if (curIdx === -1) return;
    var nextIdx = 0;
    if (win.isShuffle && win.currentTracks.length > 1) {
        nextIdx = curIdx;
        while (nextIdx === curIdx) {
            nextIdx = Math.floor(Math.random() * win.currentTracks.length);
        }
    } else {
        nextIdx = curIdx + 1;
        if (nextIdx >= win.currentTracks.length) {
            nextIdx = 0;
        }
    }
    var nextTrk = win.currentTracks[nextIdx];
    if (nextTrk) {
        if ((nextTrk.path && nextTrk.path.startsWith("ytdl://")) || nextTrk.videoId) {
            win.playOnlineTrack(nextTrk, false);
        } else {
            win.playTrack(nextTrk);
        }
    }
}

function playPrev(win) {
    if (win.listeningAlongFriend && !win.isSyncingFromFriend && !win.guestCanControlHost) {
        win.showToast(I18n.tr("Host đã khóa quyền chuyển bài hát", "Host disabled track skipping"));
        return;
    }
    if (!win.currentTrack || !win.currentTracks || win.currentTracks.length === 0) return;
    if (win.currentTime > 3.0) {
        win.seekAudio(0.0);
        return;
    }
    var curIdx = win.currentTracks.findIndex(t => win.isSameTrack(t, win.currentTrack));
    if (curIdx === -1) return;
    var prevIdx = (curIdx - 1 + win.currentTracks.length) % win.currentTracks.length;
    var prevTrk = win.currentTracks[prevIdx];
    if (prevTrk) {
        if ((prevTrk.path && prevTrk.path.startsWith("ytdl://")) || prevTrk.videoId) {
            win.playOnlineTrack(prevTrk, false);
        } else {
            win.playTrack(prevTrk);
        }
    }
}

function seekLocalOnly(win, sec) {
    win.currentTime = sec;
    win.lastSyncTime = sec;
    win.lastSyncTimestamp = Date.now();
    Quickshell.execDetached(["python3", win.appDir + "/backend/player_daemon.py", "seek", String(sec)]);
}

function seekAudio(win, sec) {
    if (win.listeningAlongFriend && !win.isSyncingFromFriend && !win.guestCanControlHost) {
        win.showToast(I18n.tr("Host đã khóa quyền tua bài hát", "Host disabled seeking"));
        return;
    }
    win.lastLocalActionTimestamp = Date.now();
    win.currentTime = sec;
    win.lastSyncTime = sec;
    win.lastSyncTimestamp = Date.now();
    Quickshell.execDetached(["python3", win.appDir + "/backend/player_daemon.py", "seek", String(sec)]);
    win.syncNowPlaying(true);
    if (!win.isSyncingFromFriend) {
        if (win.listeningAlongFriend && win.guestCanControlHost) {
            var hostSeekTarget = win.listeningAlongFriend.tag || win.listeningAlongFriend.user_id || win.listeningAlongFriend.user_email || "";
            if (hostSeekTarget) {
                win.sendSocialEventFast("seek", hostSeekTarget, { position: sec });
            }
        }
        if (win.activeCoListeners && win.activeCoListeners.length > 0) {
            for (var si = 0; si < win.activeCoListeners.length; si++) {
                win.sendSocialEventFast("seek", win.activeCoListeners[si], { position: sec });
            }
        }
    }
}

function setVolume(win, vol) {
    win.volume = vol;
    Quickshell.execDetached(["python3", win.appDir + "/backend/player_daemon.py", "volume", String(vol)]);
}

function startSleepTimer(win, seconds, mode) {
    win.sleepTimerMode = mode;
    if (mode === "end_of_track") {
        win.sleepTimerRemainingSeconds = Math.max(0, Math.round(win.totalDuration - win.currentTime));
    } else {
        win.sleepTimerRemainingSeconds = seconds;
    }
    win.sleepTimerFadeTriggered = false;
    win.isSleepTimerActive = true;
}

function cancelSleepTimer(win) {
    win.isSleepTimerActive = false;
    win.sleepTimerFadeTriggered = false;
    win.sleepTimerRemainingSeconds = 0;
    win.sleepTimerMode = "";
    Quickshell.execDetached(["python3", win.appDir + "/backend/player_daemon.py", "cancel_fade"]);
}

function rateSong(win, vid, rating) {
    if (!vid) return;
    Quickshell.execDetached([
        "python3",
        win.appDir + "/backend/ytmusic_helper.py",
        "rate_song", vid, rating
    ]);
}

function handleDislikedTrack(win, trk) {
    if (!trk) return;
    var vid = trk.videoId || (trk.path && trk.path.startsWith("ytdl://") ? trk.path.replace("ytdl://", "") : "");
    if (vid) {
        win.rateSong(vid, "DISLIKE");
    }
    var newQueue = [];
    for (var i = 0; i < win.currentTracks.length; i++) {
        var t = win.currentTracks[i];
        var tVid = t.videoId || (t.path && t.path.startsWith("ytdl://") ? t.path.replace("ytdl://", "") : "");
        if (tVid !== vid) {
            newQueue.push(t);
        }
    }
    win.currentTracks = newQueue;

    var newBrowse = [];
    for (var j = 0; j < win.browsingTracks.length; j++) {
        var bt = win.browsingTracks[j];
        var bVid = bt.videoId || (bt.path && bt.path.startsWith("ytdl://") ? bt.path.replace("ytdl://", "") : "");
        if (bVid !== vid) {
            newBrowse.push(bt);
        }
    }
    win.browsingTracks = newBrowse;
    win.playNext();
}

function insertTrackPlayNext(win, trk) {
    if (!trk) return;
    if (win.isSameTrack(trk, win.currentTrack)) {
        return;
    }
    if (!win.currentTracks || win.currentTracks.length === 0) {
        if (win.currentTrack) {
            win.currentTracks = [win.currentTrack, trk];
        } else {
            win.currentTracks = [trk];
            if ((trk.path && trk.path.startsWith("ytdl://")) || trk.videoId) win.playOnlineTrack(trk, false);
            else win.playTrack(trk);
        }
        return;
    }

    var curIdx = win.currentTracks.findIndex(t => win.isSameTrack(t, win.currentTrack));
    var insertAt = (curIdx >= 0) ? (curIdx + 1) : 1;
    var updated = win.currentTracks.slice();
    var dupIdx = updated.findIndex(t => win.isSameTrack(t, trk));
    if (dupIdx >= 0) {
        updated.splice(dupIdx, 1);
        if (dupIdx < insertAt) insertAt--;
    }
    updated.splice(insertAt, 0, trk);
    win.currentTracks = updated;
}

function appendTrackToQueue(win, trk) {
    if (!trk) return;
    if (!win.currentTracks || win.currentTracks.length === 0) {
        if (win.currentTrack) {
            win.currentTracks = [win.currentTrack, trk];
        } else {
            win.currentTracks = [trk];
            if ((trk.path && trk.path.startsWith("ytdl://")) || trk.videoId) win.playOnlineTrack(trk, false);
            else win.playTrack(trk);
        }
        return;
    }
    var updated = win.currentTracks.slice();
    var dupIdx = updated.findIndex(t => win.isSameTrack(t, trk));
    if (dupIdx >= 0) {
        updated.splice(dupIdx, 1);
    }
    updated.push(trk);
    win.currentTracks = updated;
}

function removeTrackFromQueue(win, trk) {
    if (!trk || !win.currentTracks) return;
    var idx = win.currentTracks.findIndex(t => win.isSameTrack(t, trk));
    if (idx >= 0) {
        var updated = win.currentTracks.slice();
        updated.splice(idx, 1);
        win.currentTracks = updated;
    }
}

function deleteLocalTrack(win, trk) {
    if (!trk) return;
    var p = trk.path || "";
    var fn = trk.filename || "";
    var title = trk.title || trk.name || "";

    var wasPlaying = win.isPlaying;
    var isCurrent = win.isSameTrack(win.currentTrack, trk);

    win.currentTracks = win.currentTracks.filter(t => !win.isSameTrack(t, trk));
    win.allTracks = win.allTracks.filter(t => !win.isSameTrack(t, trk));
    win.browsingTracks = win.browsingTracks.filter(t => !win.isSameTrack(t, trk));

    if (isCurrent) {
        if (wasPlaying && win.currentTracks && win.currentTracks.length > 0) {
            win.playNext();
        } else {
            win.isPlaying = false;
            win.currentTrack = null;
            win.currentTime = 0.0;
            Quickshell.execDetached(["python3", win.appDir + "/backend/player_daemon.py", "stop"]);
        }
    }

    if (!p.startsWith("ytdl://") && (p || fn || title)) {
        Quickshell.execDetached([
            "python3", win.appDir + "/backend/library.py", "delete",
            p, fn, title
        ]);
    }
}

function batchDeleteTracks(win, paths) {
    if (!paths || paths.length === 0) return;
    var pathSet = {};
    for (var i = 0; i < paths.length; i++) {
        pathSet[paths[i]] = true;
    }

    var currentDeleted = win.currentTrack && pathSet[win.currentTrack.path];

    win.currentTracks = win.currentTracks.filter(t => !pathSet[t.path]);
    win.allTracks = win.allTracks.filter(t => !pathSet[t.path]);
    win.browsingTracks = win.browsingTracks.filter(t => !pathSet[t.path]);

    if (currentDeleted) {
        if (win.isPlaying && win.currentTracks.length > 0) {
            win.playNext();
        } else {
            win.isPlaying = false;
            win.currentTrack = null;
            win.currentTime = 0.0;
            Quickshell.execDetached(["python3", win.appDir + "/backend/player_daemon.py", "stop"]);
        }
    }

    Quickshell.execDetached([
        "python3", win.appDir + "/backend/library.py", "batch_delete",
        JSON.stringify(paths)
    ]);
}

function shufflePlayBrowsing(win) {
    var sourceTracks = (win.browsingTracks && win.browsingTracks.length > 0) ? win.browsingTracks : win.allTracks;
    if (!sourceTracks || sourceTracks.length === 0) return;
    var shuffled = sourceTracks.slice();
    for (var i = shuffled.length - 1; i > 0; i--) {
        var j = Math.floor(Math.random() * (i + 1));
        var temp = shuffled[i];
        shuffled[i] = shuffled[j];
        shuffled[j] = temp;
    }
    win.currentTracks = shuffled;
    if (win.currentView === "playlist") {
        win.playingPlaylistId = win.activePlaylistId;
        win.playingSourceTitle = win.mainSectionTitle;
    } else {
        win.playingPlaylistId = "";
        win.playingSourceTitle = "";
    }
    var firstTrk = shuffled[0];
    if (firstTrk && ((firstTrk.path && firstTrk.path.startsWith("ytdl://")) || firstTrk.videoId)) {
        win.playOnlineTrack(firstTrk, false);
    } else {
        win.playTrack(firstTrk);
    }
}

function trackPlayback(win, trk, playbackTrackingProc) {
    if (!win.syncHistoryToGoogle || !trk) return;
    var vid = trk.videoId || trk.path || "";
    var title = trk.title || trk.name || "";
    var artist = trk.artist || "";
    if (playbackTrackingProc) {
        playbackTrackingProc.running = false;
        playbackTrackingProc.command = [
            "python3", "-u", win.appDir + "/backend/ytmusic_helper.py",
            "track_playback", vid, title, artist
        ];
        playbackTrackingProc.running = true;
    }
}

function handlePlayerStatus(win, data, listenAlongSeekSafetyTimer, sessionFileView) {
    try {
        var s = JSON.parse(data);
        var elapsed = Date.now() - win.trackChangeTimestamp;

        if (win.isLoadingAudio) {
            if (elapsed > 20000) {
                win.isLoadingAudio = false;
                win.isPlaying = false;
                return;
            }
            var hasStarted = (!s.is_loading || (s.time_pos && s.time_pos > 0.5) || s.is_playing) && (s.is_playing || (s.time_pos && s.time_pos > 0) || (s.duration && s.duration > 0));
            if (!hasStarted) {
                win.currentTime = 0.0;
                return;
            }
            win.isLoadingAudio = false;
            win.postLoadGraceTimestamp = Date.now();
            win.isPlaying = true;
            win.currentTime = s.time_pos || 0.0;
            win.lastSyncTime = s.time_pos || 0.0;
            win.lastSyncTimestamp = Date.now();
            if (s.duration !== undefined && s.duration > 0) win.totalDuration = s.duration;
            if (win.pendingListenAlongSeekPosition > 0) {
                var p = win.pendingListenAlongSeekPosition;
                win.pendingListenAlongSeekPosition = 0;
                win.seekLocalOnly(p);
                if (listenAlongSeekSafetyTimer) {
                    listenAlongSeekSafetyTimer.targetPos = p;
                    listenAlongSeekSafetyTimer.restart();
                }
            }
        } else {
            if (s.is_loading) {
                win.isLoadingAudio = true;
                win.trackChangeTimestamp = Date.now();
                return;
            }
            if (s.is_playing) {
                win.isPlaying = true;
            } else if (s.is_paused) {
                if (Date.now() - win.postLoadGraceTimestamp < 2500) {
                    Quickshell.execDetached(["python3", win.appDir + "/backend/player_daemon.py", "resume"]);
                } else {
                    win.isPlaying = false;
                    win.lastSyncTimestamp = 0;
                }
            }
            if (s.time_pos !== undefined && s.time_pos > 0) {
                if (Math.abs(win.currentTime - s.time_pos) > 0.45) {
                    win.currentTime = s.time_pos;
                }
                win.lastSyncTime = s.time_pos;
                if (win.isPlaying) {
                    win.lastSyncTimestamp = Date.now();
                }
            }
            if (s.duration !== undefined && s.duration > 0) win.totalDuration = s.duration;
            if (win.pendingListenAlongSeekPosition > 0 && (s.is_playing || s.is_paused)) {
                var p2 = win.pendingListenAlongSeekPosition;
                win.pendingListenAlongSeekPosition = 0;
                win.seekLocalOnly(p2);
                if (listenAlongSeekSafetyTimer) {
                    listenAlongSeekSafetyTimer.targetPos = p2;
                    listenAlongSeekSafetyTimer.restart();
                }
            }
        }

        // Cold-start recovery
        if (!win.currentTrack && (s.is_playing || s.is_paused || (s.time_pos && s.time_pos > 0))) {
            if (s.filename && win.allTracks && win.allTracks.length > 0) {
                var matched = win.allTracks.find(t => t.path && t.path.endsWith(s.filename));
                if (matched) win.currentTrack = matched;
            }
            if (!win.currentTrack && sessionFileView && sessionFileView.loaded && sessionFileView.text()) {
                try {
                    var sTrack = JSON.parse(sessionFileView.text());
                    if (sTrack && (sTrack.title || sTrack.name)) {
                        if (!sTrack.image && sTrack.artUrl) sTrack.image = sTrack.artUrl;
                        if (!sTrack.cover && sTrack.artUrl) sTrack.cover = sTrack.artUrl;
                        win.currentTrack = sTrack;
                    }
                } catch(e) {}
            }
        }

        // High-precision fade trigger cho sleep timer
        if (win.isSleepTimerActive && win.sleepTimerMode === "end_of_track" && win.totalDuration > 5) {
            var remToEnd = win.totalDuration - win.currentTime;
            if (remToEnd <= 5.0 && remToEnd > 0.6 && !win.sleepTimerFadeTriggered) {
                win.sleepTimerFadeTriggered = true;
                Quickshell.execDetached(["python3", win.appDir + "/backend/player_daemon.py", "fade_out_and_pause", String(Math.max(1.0, remToEnd))]);
            }
        }

        // Auto-advance / Repeat khi het bai
        if (!win.isLoadingAudio && win.isPlaying && win.totalDuration > 3 && win.currentTime >= win.totalDuration - 0.5) {
            if (win.isSleepTimerActive && win.sleepTimerMode === "end_of_track") {
                win.isSleepTimerActive = false;
                win.sleepTimerFadeTriggered = false;
                win.sleepTimerMode = "";
                win.sleepTimerRemainingSeconds = 0;
                win.isPlaying = false;
                Quickshell.execDetached(["python3", win.appDir + "/backend/player_daemon.py", "pause"]);
            } else if (win.isRepeat) {
                win.seekAudio(0.0);
            } else {
                win.playNext();
            }
        }
    } catch(e) {
        console.warn("Nutsty PlaybackEngine: handlePlayerStatus error", e);
    }
}

function handleRadioResponse(win, data) {
    try {
        var arr = JSON.parse(data);
        if (Array.isArray(arr) && arr.length > 0) {
            var userQueued = [];
            var curIdx = win.currentTracks.findIndex(t => win.isSameTrack(t, win.currentTrack));
            if (curIdx >= 0 && curIdx < win.currentTracks.length - 1) {
                userQueued = win.currentTracks.slice(curIdx + 1);
            }
            var filteredRadio = arr.filter(rt => !win.isSameTrack(rt, win.currentTrack) && !userQueued.some(uq => win.isSameTrack(uq, rt)));
            var taggedRadio = filteredRadio.map(function(item) {
                var copy = Object.assign({}, item);
                copy.isRadioSuggestion = true;
                return copy;
            });

            if (win.playingPlaylistId) {
                var plTracks = win.currentTracks.filter(function(t) { return !t.isRadioSuggestion; });
                win.currentTracks = plTracks.concat(taggedRadio);
            } else {
                var base = win.currentTrack ? [win.currentTrack] : [];
                win.currentTracks = base.concat(userQueued).concat(taggedRadio);
            }
        }
    } catch(e) {
        console.warn("Nutsty PlaybackEngine: handleRadioResponse error", e);
    }
}

function startRadioFromTrack(win, trk) {
    if (!trk) return;
    if (win.listeningAlongFriend && !win.isSyncingFromFriend && !win.guestCanControlHost) {
        win.suggestTrackToHost(trk);
        return;
    }
    var rVid = trk.videoId || (trk.path && trk.path.startsWith("ytdl://") ? trk.path.replace("ytdl://", "") : "");
    if (!rVid) {
        console.warn("Nutsty: startRadioFromTrack called without valid videoId", JSON.stringify(trk));
        return;
    }
    win.currentTracks = [trk];
    win.playingPlaylistId = "";
    win.playingSourceTitle = "";
    win.playOnlineTrack(trk, true);
}

function playFriendTrack(win, trk) {
    if (!trk) return;
    if (win.listeningAlongFriend && !win.isSyncingFromFriend && !win.guestCanControlHost) {
        win.suggestTrackToHost(trk);
        return;
    }
    var rVid = trk.id || trk.videoId || (trk.path && trk.path.startsWith("ytdl://") ? trk.path.replace("ytdl://", "") : "");
    if (rVid) {
        win.currentTracks = [trk];
        win.playingPlaylistId = "";
        win.playingSourceTitle = I18n.tr("Nghe cùng bạn bè", "Listening with friend");
        win.playOnlineTrack(trk, true);
    } else {
        var q = (trk.title || "") + " " + (trk.artist || "");
        if (q.trim()) {
            win.executeSearch(q.trim());
        }
    }
}

function playArtistShuffle(win, artistItem, candidateTracks) {
    if (!artistItem) return;
    if (win.listeningAlongFriend && !win.isSyncingFromFriend && !win.guestCanControlHost) {
        win.showToast(I18n.tr("Host đã khóa quyền chuyển bài hát", "Host disabled track skipping"));
        return;
    }
    var aName = artistItem.name || artistItem.title || artistItem.artist || "";
    var bId = artistItem.browseId || artistItem.channelId || "";
    win.mainSectionTitle = aName;

    var pool = [];
    if (candidateTracks && Array.isArray(candidateTracks) && candidateTracks.length > 0) {
        pool = candidateTracks.slice();
    } else if (artistItem.top_tracks && Array.isArray(artistItem.top_tracks) && artistItem.top_tracks.length > 0) {
        pool = artistItem.top_tracks.slice();
    } else if (artistItem.popular && Array.isArray(artistItem.popular) && artistItem.popular.length > 0) {
        pool = artistItem.popular.slice();
    }

    pool = pool.filter(function(t) {
        if (!t) return false;
        var vid = t.videoId || (t.path && t.path.startsWith("ytdl://") ? t.path.replace("ytdl://", "") : "");
        return (typeof ytNowPlayingView !== "undefined" && ytNowPlayingView) ? !ytNowPlayingView.isTrackDisliked(vid) : true;
    });

    if (pool.length > 0) {
        var randIdx = Math.floor(Math.random() * pool.length);
        var chosen = pool[randIdx];
        var rest = pool.filter(function(_, idx) { return idx !== randIdx; });
        for (var i = rest.length - 1; i > 0; i--) {
            var j = Math.floor(Math.random() * (i + 1));
            var tmp = rest[i];
            rest[i] = rest[j];
            rest[j] = tmp;
        }
        win.currentTracks = [chosen].concat(rest);
        win.playingPlaylistId = "";
        win.playingSourceTitle = aName;
        win.playOnlineTrack(chosen, false);
    }

    win.isNowPlayingOpen = true;
    if (typeof ytNowPlayingView !== "undefined" && ytNowPlayingView) {
        ytNowPlayingView.activeTab = "up_next";
    }

    var xhr = new XMLHttpRequest();
    var url = "http://127.0.0.1:17890/api/artist_shuffle?name=" + encodeURIComponent(aName) + "&browseId=" + encodeURIComponent(bId);
    xhr.open("GET", url, true);
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
            try {
                var res = JSON.parse(xhr.responseText);
                var fullTracks = (res && res.tracks) ? res.tracks : (Array.isArray(res) ? res : []);
                if (fullTracks && fullTracks.length > 0) {
                    var cur = win.currentTrack;
                    if (cur) {
                        var curVid = cur.videoId || (cur.path && cur.path.startsWith("ytdl://") ? cur.path.replace("ytdl://", "") : "");
                        var filtered = fullTracks.filter(function(t) {
                            if (!t) return false;
                            var tVid = t.videoId || (t.path && t.path.startsWith("ytdl://") ? t.path.replace("ytdl://", "") : "");
                            if (curVid && tVid && curVid === tVid) return false;
                            return (typeof ytNowPlayingView !== "undefined" && ytNowPlayingView) ? !ytNowPlayingView.isTrackDisliked(tVid) : true;
                        });
                        win.currentTracks = [cur].concat(filtered);
                    } else {
                        var rIdx = Math.floor(Math.random() * fullTracks.length);
                        var ch = fullTracks[rIdx];
                        var rRest = fullTracks.filter(function(_, idx) { return idx !== rIdx; });
                        win.currentTracks = [ch].concat(rRest);
                        win.playingPlaylistId = "";
                        win.playOnlineTrack(ch, false);
                    }
                }
            } catch (e) {
                console.warn("Nutsty: parse error in artist_shuffle", e);
            }
        }
    };
    xhr.send();
}

function addTracksToQueue(win, tracks) {
    if (!tracks || tracks.length === 0) return;
    var cur = win.currentTracks ? win.currentTracks.slice() : [];
    for (var i = 0; i < tracks.length; i++) {
        cur.push(tracks[i]);
    }
    win.currentTracks = cur;
}

function downloadEntireAlbum(win, tracks) {
    if (!tracks || tracks.length === 0) return;
    for (var i = 0; i < tracks.length; i++) {
        var t = tracks[i];
        if (typeof downloadManager !== "undefined" && downloadManager) {
            downloadManager.enqueueDownload(t);
        }
    }
    var albumTitle = (win.albumMetadata && win.albumMetadata.title) ? win.albumMetadata.title : (tracks[0] ? (tracks[0].album || tracks[0].title) : "");
    var albumCover = (win.albumMetadata && (win.albumMetadata.cover || win.albumMetadata.image)) ? (win.albumMetadata.cover || win.albumMetadata.image) : (tracks[0] ? (tracks[0].image || tracks[0].cover || "") : "");
    var albumDesc = (win.albumMetadata && win.albumMetadata.artist) ? ("Album by " + win.albumMetadata.artist) : (tracks[0] && tracks[0].artist ? ("By " + tracks[0].artist) : "");
    if (albumTitle && typeof win.createCustomPlaylist === "function") {
        win.createCustomPlaylist(albumTitle, albumDesc, albumCover, tracks);
    }
}

function loadArtistDetails(win, artistNameOrId) {
    if (!artistNameOrId) return;
    var artTarget = String(artistNameOrId).trim();
    if (!artTarget) return;

    if (win.currentView !== "artist") {
        win.artistHistoryStack = [{ view: win.currentView, artist: null }];
    } else if (win.currentArtistData && win.currentArtistData.metadata) {
        win.artistHistoryStack.push({ view: "artist", artist: win.currentArtistData });
    }

    win.previousView = (win.currentView !== "artist") ? win.currentView : win.previousView;
    win.currentView = "artist";
    win.isLoadingArtist = true;
    win.currentArtistData = null;

    artistDetailsProc.running = false;
    artistDetailsProc.targetArtist = artTarget;
    artistDetailsProc.command = ["python3", "-u", win.appDir + "/backend/ytmusic_helper.py", "artist", artTarget];
    artistDetailsProc.running = true;
}

function goBackFromArtist(win) {
    if (win.artistHistoryStack && win.artistHistoryStack.length > 0) {
        var prev = win.artistHistoryStack.pop();
        if (prev && prev.view === "artist" && prev.artist) {
            win.currentArtistData = prev.artist;
            win.currentView = "artist";
            return;
        } else if (prev && prev.view) {
            win.currentView = prev.view;
            return;
        }
    }
    win.currentView = win.previousView || "home";
}

function loadAlbumDetails(win, alb) {
    if (!alb) return;
    if (typeof alb === "string") alb = { browseId: alb };
    var albId = alb.browseId || alb.playlistId || alb.id || "";
    win.activePlaylistId = albId;
    if (win.currentView !== "search" && win.currentView !== "playlist") {
        win.previousView = win.currentView;
    }
    win.currentView = "playlist";
    win.mainSectionTitle = alb.title || alb.name || "Album";
    mainGrid.sectionTitle = win.mainSectionTitle;

    if (alb.isLocal || (alb.tracks && alb.tracks.length > 0 && String(albId).startsWith("local_alb_"))) {
        win.currentAlbumMetadata = alb;
        mainGrid.albumMetadata = alb;
        win.browsingTracks = alb.tracks || [];
        win.isSearchingYT = false;
        return;
    }

    win.currentAlbumMetadata = null;
    mainGrid.albumMetadata = null;
    win.browsingTracks = [];
    win.isSearchingYT = true;

    albumDetailsProc.running = false;
    albumDetailsProc.targetTitle = alb.title || alb.name || "Album";
    albumDetailsProc.command = ["python3", "-u", win.appDir + "/backend/ytmusic_helper.py", "album", albId];
    albumDetailsProc.running = true;
}

function loadPlaylistTracks(win, pl) {
    if (!pl) return;
    var pid = pl.playlistId || pl.id || pl.browseId || "";
    if (!pid) return;

    if (pl.type === "artist" || String(pid).startsWith("UC") || String(pid).startsWith("FEmusic_library_privately_owned_artist_detail")) {
        win.loadArtistDetails(pid || pl.name || pl.title);
        return;
    }

    if (String(pid).startsWith("MPREb_") || pl.type === "album" || (pl.isLocal && String(pid).startsWith("local_alb_"))) {
        win.loadAlbumDetails(pl);
        return;
    }

    win.currentAlbumMetadata = null;
    mainGrid.albumMetadata = null;
    win.activePlaylistId = pid;
    if (win.currentView !== "search" && win.currentView !== "playlist") {
        win.previousView = win.currentView;
    }
    win.currentView = "playlist";
    win.mainSectionTitle = pl.title || pl.name || "Playlist";
    mainGrid.sectionTitle = pl.title || pl.name || "Playlist";

    var isCustomPl = !!pl.isCustom || String(pid).startsWith("custom_") || pl.source === "spotify_import" || (pl.tracks && pl.tracks.length >= 0 && pl.isLocal);
    if (isCustomPl) {
        var foundTracks = pl.tracks || [];
        if (win.customPlaylists) {
            for (var i = 0; i < win.customPlaylists.length; i++) {
                if (win.customPlaylists[i].id === pid) {
                    foundTracks = win.customPlaylists[i].tracks || [];
                    break;
                }
            }
        }
        win.browsingTracks = foundTracks;
        win.isSearchingYT = false;
        return;
    }

    win.browsingTracks = [];
    win.isSearchingYT = true;
    playlistTracksProc.running = false;
    playlistTracksProc.targetTitle = pl.title || "Playlist";
    playlistTracksProc.command = ["python3", "-u", win.appDir + "/backend/ytmusic_helper.py", "playlist", pid];
    playlistTracksProc.running = true;
}

function deleteCustomPlaylist(win, plId) {
    if (!plId) return;
    Quickshell.execDetached([
        "python3", win.appDir + "/backend/playlist_manager.py", "delete", plId
    ]);
    refreshPlaylistsTimer.restart();
    if (win.activePlaylistId === plId && win.currentView === "playlist") {
        win.currentView = "home";
    }
}
