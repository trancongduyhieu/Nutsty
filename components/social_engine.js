// Nutsty Social Engine (Co-Listening, Ephemeral Chat, 24h Notes, Friends & Profile SSOT)
// Extracted from shell.qml for CodeGraph AST indexing while preserving 100% QML scope compatibility.

/**
 * SSOT #3: Canonical Peer / Friend / Co-Listener normalizer.
 * Guarantees { user_id, tag, email, name, avatar } on any peer object.
 */
function normalizePeer(raw) {
    if (!raw || typeof raw !== "object") {
        return { user_id: "", tag: "", email: "", name: "User", avatar: "" };
    }
    var uid = String(raw.user_id || raw.id || raw.from_id || "").trim();
    var tag = String(raw.tag || raw.nutsty_tag || raw.user_email || raw.email || raw.from_email || "").trim();
    var email = String(raw.email || raw.user_email || tag || uid).trim();
    var name = String(raw.name || raw.user_name || raw.username || raw.from_name || (tag ? tag.split("#")[0] : "User")).trim();
    var avatar = String(raw.avatar || raw.avatar_url || raw.from_avatar || "").trim();
    return {
        user_id: uid,
        id: uid,
        tag: tag || email,
        nutsty_tag: tag || email,
        email: email || tag,
        user_email: email || tag,
        name: name || "User",
        user_name: name || "User",
        username: name || "User",
        avatar: avatar,
        avatar_url: avatar
    };
}

function sendSocialEventFast(win, ev_type, to_email, extra_data) {
    if (!to_email) return;
    var profile = (Quickshell.env("NUTSTY_PROFILE") || "").toLowerCase();
    var myEmail = win.getCurrentUserEmail();
    var myName = win.getCurrentUserName();
    var myAvatar = win.getCurrentUserAvatar() || "";
    if (!myAvatar && win.myLatestNote && win.myLatestNote.avatar_url) {
        myAvatar = win.myLatestNote.avatar_url;
    }

    var resolvedEmail = String(to_email).trim();
    var resolvedUserId = resolvedEmail.startsWith("usr_") ? resolvedEmail : "";
    var lowerTarget = resolvedEmail.toLowerCase();
    if (win.activeCoListenersDetails && Array.isArray(win.activeCoListenersDetails)) {
        for (var cli = 0; cli < win.activeCoListenersDetails.length; cli++) {
            var cld = win.activeCoListenersDetails[cli];
            if (!cld) continue;
            var cldEm = String(cld.email || cld.tag || "").trim();
            var cldId = String(cld.user_id || cld.id || "").trim();
            var cldName = String(cld.name || "").trim();
            if (cldEm.toLowerCase() === lowerTarget || cldId.toLowerCase() === lowerTarget || (cldName && cldName.toLowerCase() === lowerTarget)) {
                if (cldEm) resolvedEmail = cldEm;
                if (cldId) resolvedUserId = cldId;
                break;
            }
        }
    }
    if (!resolvedUserId && win.friendsDetails && Array.isArray(win.friendsDetails)) {
        for (var fi = 0; fi < win.friendsDetails.length; fi++) {
            var fd = win.friendsDetails[fi];
            if (!fd) continue;
            var fdTag = String(fd.tag || fd.email || "").trim();
            var fdId = String(fd.user_id || fd.id || "").trim();
            var fdName = String(fd.name || fd.username || "").trim();
            if (fdTag.toLowerCase() === lowerTarget || fdId.toLowerCase() === lowerTarget || (fdName && fdName.toLowerCase() === lowerTarget)) {
                if (fdTag) resolvedEmail = fdTag;
                if (fdId) resolvedUserId = fdId;
                break;
            }
        }
    }
    if (!resolvedUserId && win.friendsNotes && Array.isArray(win.friendsNotes)) {
        for (var ni = 0; ni < win.friendsNotes.length; ni++) {
            var fn = win.friendsNotes[ni];
            if (!fn) continue;
            var fnTag = String(fn.tag || fn.user_email || "").trim();
            var fnId = String(fn.user_id || "").trim();
            var fnName = String(fn.user_name || "").trim();
            if (fnTag.toLowerCase() === lowerTarget || fnId.toLowerCase() === lowerTarget || (fnName && fnName.toLowerCase() === lowerTarget)) {
                if (fnTag) resolvedEmail = fnTag;
                if (fnId) resolvedUserId = fnId;
                break;
            }
        }
    }

    var payload = {
        profile: profile,
        event: ev_type,
        from_email: myEmail,
        from_name: myName,
        from_avatar: myAvatar,
        to_email: resolvedEmail,
        to_user_id: resolvedUserId,
        data: extra_data || null
    };
    var xhr = new XMLHttpRequest();
    xhr.open("POST", (win.notesApiUrl || "http://127.0.0.1:17890") + "/api/notes/events", true);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.send(JSON.stringify(payload));
}

function sendOfflineSignal(win) {
    Quickshell.execDetached(["python3", win.appDir + "/backend/social_notes.py", "offline"]);
}

function syncNowPlaying(win, force) {
    var now = Date.now();
    if (!force && (now - win.lastNowPlayingSyncTime < 4000)) return;

    var email = win.getCurrentUserEmail();
    var profile = (Quickshell.env("NUTSTY_PROFILE") || "").toLowerCase();
    if (!email) return;

    if (win.listeningAlongFriend) {
        var hostEm = String(win.listeningAlongFriend.user_email || win.listeningAlongFriend.tag || "").trim().toLowerCase();
        if (hostEm && hostEm === String(email).trim().toLowerCase()) {
            return;
        }
        if (win.isLoadingAudio || win.pendingListenAlongSeekPosition > 0) {
            return;
        }
    }

    win.lastNowPlayingSyncTime = now;

    var cur = win.currentTrack;
    var npData = null;
    if (cur) {
        var rawVid = cur.videoId || cur.id || (cur.path && typeof cur.path === "string" && cur.path.startsWith("ytdl://") ? cur.path.replace("ytdl://", "") : "");
        var vid = rawVid ? String(rawVid) : "";
        if (vid && vid.startsWith("yt_")) vid = vid.replace(/^yt_/, "");
        var cov = win.getTrackCoverUrl(cur);
        var reportPos = (win.pendingListenAlongSeekPosition > 0) ? win.pendingListenAlongSeekPosition : (win.currentTime || 0);
        npData = {
            id: vid,
            videoId: vid,
            path: cur.path || (vid ? ("ytdl://" + vid) : ""),
            title: cur.title || cur.name || "Track",
            artist: cur.artist || "Artist",
            cover: cov,
            image: cov,
            accent_color: win.songAccentColor ? win.songAccentColor.toString() : "",
            position: reportPos,
            duration: win.totalDuration || cur.duration || 0,
            is_playing: win.isPlaying,
            allow_control: Boolean(win.allowCoListenerControl),
            timestamp: Date.now() / 1000.0
        };
    }

    var xhr = new XMLHttpRequest();
    xhr.open("POST", (win.notesApiUrl || "http://127.0.0.1:17890") + "/api/now_playing", true);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.send(JSON.stringify({
        profile: profile,
        user_email: email,
        user_name: win.getCurrentUserName() || "",
        avatar_url: win.getCurrentUserAvatar() || "",
        now_playing: npData
    }));
}

function fetchCurrentUserProfile(win) {
    var email = win.getCurrentUserEmail();
    var profile = (Quickshell.env("NUTSTY_PROFILE") || "").toLowerCase();
    var preferredName = (!win.currentUserName && win.authAccountName) ? win.authAccountName : "";
    var apiUrl = (win.notesApiUrl || "http://127.0.0.1:17890") + "/api/users/me?user_email=" + encodeURIComponent(email) + "&profile=" + encodeURIComponent(profile) + "&name=" + encodeURIComponent(preferredName);
    var xhr = new XMLHttpRequest();
    xhr.open("GET", apiUrl, true);
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
            try {
                var res = JSON.parse(xhr.responseText);
                if (res && res.success && res.profile) {
                    win.currentUserPin = res.profile.discriminator || res.profile.pin_code || "";
                    win.currentUserCloudId = res.profile.user_id || res.profile.id || "";
                    if (res.profile.username && !res.profile.username.toLowerCase().includes("shiraori") && res.profile.username !== "Nutsty User") {
                        win.currentUserName = res.profile.username;
                        win.currentUserTag = res.profile.tag || (res.profile.username + "#" + win.currentUserPin);
                    } else if (win.authAccountName) {
                        win.currentUserName = win.authAccountName;
                        win.currentUserTag = win.authAccountName + "#" + win.currentUserPin;
                    }
                }
            } catch(e) {}
        }
    };
    xhr.send();
}

function updateUserProfile(win, newUsername, newDiscriminator, callback) {
    var email = win.getCurrentUserEmail();
    var profile = (Quickshell.env("NUTSTY_PROFILE") || "").toLowerCase();
    var apiUrl = (win.notesApiUrl || "http://127.0.0.1:17890") + "/api/users/update_profile";
    var xhr = new XMLHttpRequest();
    xhr.open("POST", apiUrl, true);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            var res = null;
            try {
                res = JSON.parse(xhr.responseText);
            } catch(e) {}
            if (xhr.status === 200 && res && res.success && res.user) {
                try {
                    win.currentUserPin = res.user.discriminator || "";
                    win.currentUserTag = res.user.tag || "";
                    win.currentUserName = res.user.username || "";
                    win.showToast(I18n.tr("Đã cập nhật: " + res.user.tag, "Updated: " + res.user.tag));
                } catch(err) {
                    console.error("[updateUserProfile error]", err);
                }
                if (typeof callback === "function") callback(true, res);
            } else {
                var err = (res && res.error) ? res.error : "Failed";
                if (res && res.suggested_tag) {
                    err += " (" + I18n.tr("Gợi ý: ", "Suggested: ") + res.suggested_tag + ")";
                }
                win.showToast(err);
                if (typeof callback === "function") callback(false, res);
            }
        }
    };
    xhr.send(JSON.stringify({
        user_email: email,
        profile: profile,
        new_username: newUsername,
        new_discriminator: newDiscriminator
    }));
}

function regenerateUserPin(win) {
    var email = win.getCurrentUserEmail();
    var profile = (Quickshell.env("NUTSTY_PROFILE") || "").toLowerCase();
    var apiUrl = (win.notesApiUrl || "http://127.0.0.1:17890") + "/api/users/regenerate_pin";
    var xhr = new XMLHttpRequest();
    xhr.open("POST", apiUrl, true);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
            try {
                var res = JSON.parse(xhr.responseText);
                if (res && res.success && res.pin_code) {
                    win.currentUserPin = res.pin_code;
                    if (res.nutsty_tag) win.currentUserTag = res.nutsty_tag;
                    win.showToast(I18n.tr("Đã tạo Tag mới: #" + res.pin_code, "New Tag generated: #" + res.pin_code));
                }
            } catch(e) {}
        }
    };
    xhr.send(JSON.stringify({ user_email: email, profile: profile }));
}

function fetchFriendsDataFast(win, callback) {
    var email = win.getCurrentUserEmail();
    var profile = (Quickshell.env("NUTSTY_PROFILE") || "").toLowerCase();
    var apiUrl = (win.notesApiUrl || "http://127.0.0.1:17890") + "/api/friends?user_email=" + encodeURIComponent(email) + (profile ? ("&profile=" + encodeURIComponent(profile)) : "");

    var xhr = new XMLHttpRequest();
    xhr.open("GET", apiUrl, true);
    xhr.timeout = 8000;
    xhr.ontimeout = function() {
        if (typeof callback === "function") callback();
    };
    xhr.onerror = function() {
        if (typeof callback === "function") callback();
    };
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                try {
                    var parsed = JSON.parse(xhr.responseText);
                    if (parsed && typeof parsed === "object") {
                        if (Array.isArray(parsed.friends)) {
                            win.friendsDetails = parsed.friends;
                            win.friendsList = parsed.friends.map(function(f) { return f.email || f.tag; });
                        }
                        if (Array.isArray(parsed.incoming_requests)) {
                            win.pendingFriendRequests = parsed.incoming_requests;
                            win.unreadFriendRequestsCount = parsed.incoming_requests.length;
                        }
                    }
                } catch(e) {}
            }
            if (typeof callback === "function") callback();
        }
    };
    xhr.send();
}

function fetchFriendsNotesFast(win) {
    if (win.isFetchingNotesFast) return;
    win.isFetchingNotesFast = true;

    var email = win.getCurrentUserEmail();
    var profile = (Quickshell.env("NUTSTY_PROFILE") || "").toLowerCase();
    var friendsParam = (win.friendsList && win.friendsList.length > 0)
        ? win.friendsList.join(",")
        : "";
    var url = (win.notesApiUrl || "http://127.0.0.1:17890") + "/api/notes?friends=" + encodeURIComponent(friendsParam) + (email ? ("&user_email=" + encodeURIComponent(email)) : "") + (profile ? ("&profile=" + encodeURIComponent(profile)) : "");

    var xhr = new XMLHttpRequest();
    xhr.open("GET", url, true);
    xhr.timeout = 8000;
    xhr.ontimeout = function() {
        win.isFetchingNotesFast = false;
    };
    xhr.onerror = function() {
        win.isFetchingNotesFast = false;
    };
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            win.isFetchingNotesFast = false;
            if (xhr.status === 200) {
                try {
                    var parsed = JSON.parse(xhr.responseText);
                    if (parsed && typeof parsed === "object") {
                        if (Array.isArray(parsed.notes)) {
                            win.friendsNotes = parsed.notes;
                        }
                        if (parsed.my_note !== undefined) {
                            win.myLatestNote = parsed.my_note;
                        }

                        if (win.listeningAlongFriend && (!win.activeCoListeners || win.activeCoListeners.length === 0)) {
                            var nowHb = Date.now();
                            if (nowHb - win.lastJoinHeartbeatTimestamp > 10000) {
                                win.lastJoinHeartbeatTimestamp = nowHb;
                                var hbTarget = win.listeningAlongFriend.tag || win.listeningAlongFriend.user_id || win.listeningAlongFriend.user_email || "";
                                if (hbTarget) {
                                    win.sendSocialEventFast("join", hbTarget, { heartbeat: true });
                                }
                            }
                        }

                        if (win.listeningAlongFriend && (!win.activeCoListeners || win.activeCoListeners.length === 0) && Array.isArray(parsed.notes)) {
                            var targetEmail = (win.listeningAlongFriend.user_email || win.listeningAlongFriend.tag || "").toLowerCase();
                            var targetUserId = (win.listeningAlongFriend.user_id || win.listeningAlongFriend.id || "");
                            var targetName = win.listeningAlongFriend.user_name;
                            var updated = parsed.notes.find(function(f) {
                                var fEm = (f.user_email || f.tag || "").toLowerCase();
                                var fUid = f.user_id || f.id || "";
                                return (targetUserId && fUid && fUid === targetUserId) ||
                                       (targetEmail && fEm === targetEmail) ||
                                       (targetName && f.user_name === targetName);
                            });
                            if (updated && updated.now_playing) {
                                var np = updated.now_playing;
                                if (np.allow_control !== undefined) {
                                    win.guestCanControlHost = Boolean(np.allow_control);
                                }
                                if (win.guestCanControlHost && ((Date.now() - win.lastTrackSwitchTimestamp < 5000) || (Date.now() - win.lastLocalActionTimestamp < 5000))) {
                                    return;
                                }
                                win.listeningAlongFriend = updated;
                                var npVid = np.videoId || np.id || "";
                                if (npVid.startsWith("yt_")) npVid = npVid.replace(/^yt_/, "");
                                var curVid = win.currentTrack ? (win.currentTrack.videoId || win.currentTrack.id || "") : "";
                                if (curVid.startsWith("yt_")) curVid = curVid.replace(/^yt_/, "");

                                if (npVid && npVid !== curVid) {
                                    win.isSyncingFromFriend = true;
                                    win.startListeningAlong(updated);
                                    win.isSyncingFromFriend = false;
                                } else if (npVid && curVid && npVid === curVid) {
                                    win.isSyncingFromFriend = true;

                                    if (np.is_playing === false && win.isPlaying === true) {
                                        win.isPlaying = false;
                                        win.isLoadingAudio = false;
                                        Quickshell.execDetached(["python3", win.appDir + "/backend/player_daemon.py", "pause"]);
                                    } else if (np.is_playing === true && win.isPlaying === false) {
                                        win.isPlaying = true;
                                        Quickshell.execDetached(["python3", win.appDir + "/backend/player_daemon.py", "resume", win.currentTrack.path || ""]);
                                    }

                                    var expectedPos = Number(np.position || 0);
                                    if (np.is_playing === true && np.timestamp) {
                                        var nowSec = Date.now() / 1000.0;
                                        var recordSec = (np.timestamp > 1000000000000) ? (np.timestamp / 1000.0) : Number(np.timestamp);
                                        var elapsed = nowSec - recordSec;
                                        if (elapsed > 0 && elapsed < (win.totalDuration || 600)) {
                                            expectedPos += elapsed;
                                        }
                                    }
                                    if (win.isLoadingAudio) {
                                        win.pendingListenAlongSeekPosition = expectedPos;
                                    } else {
                                        var drift = Math.abs(win.currentTime - expectedPos);
                                        if (drift > 3.5 && expectedPos >= 0) {
                                            win.seekLocalOnly(expectedPos);
                                        }
                                    }

                                    win.isSyncingFromFriend = false;
                                }
                            }
                        }
                    }
                } catch(e) {}
            }
        }
    };
    xhr.send();
}

function setAllowCoListenerControl(win, allowed) {
    win.allowCoListenerControl = Boolean(allowed);
    win.syncNowPlaying(true);
    var sentPermTargets = {};
    function sendPermOnce(peerObjOrKey) {
        if (!peerObjOrKey) return;
        var peer = normalizePeer(peerObjOrKey);
        var bestKey = peer.user_id || peer.tag || peer.email || String(peerObjOrKey).trim();
        if (!bestKey) return;
        var aliases = [peer.user_id, peer.tag, peer.email, peer.name, bestKey];
        for (var a = 0; a < aliases.length; a++) {
            var al = String(aliases[a] || "").trim().toLowerCase();
            if (al && sentPermTargets[al]) return;
        }
        for (var b = 0; b < aliases.length; b++) {
            var al2 = String(aliases[b] || "").trim().toLowerCase();
            if (al2) sentPermTargets[al2] = true;
        }
        win.sendSocialEventFast("permission_update", bestKey, { allow_control: win.allowCoListenerControl });
    }
    if (win.activeCoListenersDetails && win.activeCoListenersDetails.length > 0) {
        for (var di = 0; di < win.activeCoListenersDetails.length; di++) {
            sendPermOnce(win.activeCoListenersDetails[di]);
        }
    }
    if (win.activeCoListeners && win.activeCoListeners.length > 0) {
        for (var i = 0; i < win.activeCoListeners.length; i++) {
            sendPermOnce(win.activeCoListeners[i]);
        }
    }
    win.showToast(win.allowCoListenerControl
        ? I18n.tr("Đã bật quyền điều khiển chung (Pause, Tua, Đổi bài)", "Enabled shared control (Pause, Seek, Change track)")
        : I18n.tr("Đã khóa quyền điều khiển chung (Chỉ Host điều khiển)", "Disabled shared control (Host only)"));
}

function ensureCoListenerRegistered(win, ev, showJoinToast) {
    if (!ev) return false;
    if (win.listeningAlongFriend) {
        var hostTagLow = String(win.listeningAlongFriend.tag || win.listeningAlongFriend.user_email || "").trim().toLowerCase();
        var fromTagLow = String(ev.from_email || "").trim().toLowerCase();
        if (hostTagLow && fromTagLow && hostTagLow === fromTagLow && ev.event !== "join") {
            return false;
        }
    }

    var peer = normalizePeer(ev);
    var rawEmail = peer.tag || peer.email || peer.user_id;
    var rawUserId = peer.user_id;
    var jEmail = rawEmail.toLowerCase();
    if (!jEmail) return false;

    if (ev.event === "join") {
        win.listeningAlongFriend = null;
        win.pendingListenAlongSeekPosition = 0.0;
    }

    var existing = win.activeCoListeners ? win.activeCoListeners.slice(0) : [];
    var isNewListener = (existing.findIndex(function(e) { return String(e || "").toLowerCase() === jEmail; }) === -1);
    if (isNewListener) {
        existing.push(rawEmail);
        win.activeCoListeners = existing;
    }
    var jName = peer.name || rawEmail;
    var jAvatar = peer.avatar || "";
    if (win.friendsNotes && Array.isArray(win.friendsNotes)) {
        var matchNote = win.friendsNotes.find(function(n) {
            return (n.user_email && n.user_email.toLowerCase() === jEmail) ||
                   (n.tag && n.tag.toLowerCase() === jEmail) ||
                   (rawUserId && n.user_id && n.user_id === rawUserId) ||
                   (n.user_name && n.user_name === jName);
        });
        if (matchNote) {
            if (!jAvatar) jAvatar = matchNote.avatar_url || "";
            if (!rawUserId && matchNote.user_id) rawUserId = matchNote.user_id;
            if ((!ev.from_name || ev.from_name === "User") && matchNote.user_name) jName = matchNote.user_name;
        }
    }
    var curDetails = win.activeCoListenersDetails ? win.activeCoListenersDetails.slice(0) : [];
    var existIdx = curDetails.findIndex(function(d) {
        return String(d.email || "").toLowerCase() === jEmail || (rawUserId && d.user_id === rawUserId);
    });
    var detailObj = normalizePeer({ email: rawEmail, tag: rawEmail, user_id: rawUserId, name: jName, avatar: jAvatar });
    if (existIdx === -1) {
        curDetails.push(detailObj);
    } else {
        curDetails[existIdx] = detailObj;
    }
    win.activeCoListenersDetails = curDetails;

    if (isNewListener && showJoinToast) {
        win.showToast(I18n.tr(jName + " đang nghe cùng bạn", jName + " is listening along with you"));
        win.sendSocialEventFast("permission_update", rawEmail, { allow_control: win.allowCoListenerControl });
    }
    return isNewListener;
}

function pollSocialEventsFast(win) {
    if (win.isPollingSocialEventsFast) return;
    var email = win.getCurrentUserEmail();
    if (!email) return;
    var profile = (Quickshell.env("NUTSTY_PROFILE") || "").toLowerCase();
    win.isPollingSocialEventsFast = true;

    var evUrl = (win.notesApiUrl || "http://127.0.0.1:17890") + "/api/notes/events?user_email=" + encodeURIComponent(email) + (profile ? ("&profile=" + encodeURIComponent(profile)) : "");
    var evXhr = new XMLHttpRequest();
    evXhr.open("GET", evUrl, true);
    evXhr.onreadystatechange = function() {
        if (evXhr.readyState === XMLHttpRequest.DONE) {
            win.isPollingSocialEventsFast = false;
            if (evXhr.status === 200) {
                try {
                    var evData = JSON.parse(evXhr.responseText);
                    var events = (evData && Array.isArray(evData.events)) ? evData.events : [];
                    for (var i = 0; i < events.length; i++) {
                        var ev = events[i];
                        if (!ev) continue;
                        if (ev.event === "join") {
                            var isNew = win.ensureCoListenerRegistered(ev, true);
                            var isHb = (ev.data && ev.data.heartbeat === true);
                            if (isNew || !isHb) {
                                win.lastLocalActionTimestamp = Date.now();
                                win.syncNowPlaying(true);
                                var targetSender = ev.from_email || ev.from_id || "";
                                if (win.currentTrack && targetSender) {
                                    win.sendSocialEventFast(win.isPlaying ? "play" : "pause", targetSender);
                                    win.sendSocialEventFast("seek", targetSender, { position: win.currentTime });
                                    win.sendSocialEventFast("permission_update", targetSender, { allow_control: win.allowCoListenerControl });
                                    hostFollowupSyncTimer.targetListenerEmail = targetSender;
                                    hostFollowupSyncTimer.restart();
                                }
                            }
                        } else if (ev.event === "permission_update") {
                            if (ev.data && ev.data.allow_control !== undefined) {
                                win.guestCanControlHost = Boolean(ev.data.allow_control);
                                var hNamePerm = ev.from_name || I18n.tr("Host", "Host");
                                win.showToast(win.guestCanControlHost
                                    ? I18n.tr(hNamePerm + " đã bật quyền điều khiển chung", hNamePerm + " enabled shared control")
                                    : I18n.tr(hNamePerm + " đã khóa quyền điều khiển chung", hNamePerm + " disabled shared control"));
                            }
                        } else if (ev.event === "leave" || ev.event === "kick") {
                            var lEmail = (ev.from_email || "").trim().toLowerCase();
                            if (lEmail) {
                                if (win.activeCoListeners) {
                                    win.activeCoListeners = win.activeCoListeners.filter(function(e) { return (e || "").toLowerCase() !== lEmail; });
                                }
                                if (win.activeCoListenersDetails) {
                                    win.activeCoListenersDetails = win.activeCoListenersDetails.filter(function(d) { return (d.email || "").toLowerCase() !== lEmail; });
                                }
                                if (coListenersPopover.visible) {
                                    coListenersPopover.openAt(win.activeCoListenersDetails);
                                }
                            }
                            var fromName = ev.from_name || ev.from_email || I18n.tr("Bạn bè", "Friend");
                            if (win.listeningAlongFriend && (((win.listeningAlongFriend.user_email || "").toLowerCase() === lEmail) || win.listeningAlongFriend.user_name === ev.from_name)) {
                                win.listeningAlongFriend = null;
                                var leaveMsg = (ev.event === "kick")
                                    ? I18n.tr("Bạn đã bị mời ra khỏi phòng nghe cùng", "You were removed from the co-listening session")
                                    : I18n.tr(fromName + " đã dừng phát cùng bạn", fromName + " stopped co-listening with you");
                                win.showToast(leaveMsg);
                            } else {
                                win.showToast(I18n.tr(fromName + " đã dừng nghe cùng bạn", fromName + " stopped listening along with you"));
                            }
                        } else if (ev.event === "pause") {
                            win.ensureCoListenerRegistered(ev, true);
                            if (!win.listeningAlongFriend && !win.allowCoListenerControl) {
                                _forceResyncUnauthorizedGuest(win, ev);
                                continue;
                            }
                            win.lastLocalActionTimestamp = Date.now();
                            if (win.isPlaying) {
                                win.isSyncingFromFriend = true;
                                win.isPlaying = false;
                                win.isLoadingAudio = false;
                                Quickshell.execDetached(["python3", win.appDir + "/backend/player_daemon.py", "pause"]);
                                win.syncNowPlaying(true);
                                win.isSyncingFromFriend = false;
                            }
                            var pName = ev.from_name || I18n.tr("Bạn bè", "Friend");
                            win.showToast(I18n.tr(pName + " đã tạm dừng bài hát", pName + " paused playback"));
                        } else if (ev.event === "play" || ev.event === "resume") {
                            win.ensureCoListenerRegistered(ev, true);
                            if (!win.listeningAlongFriend && !win.allowCoListenerControl) {
                                _forceResyncUnauthorizedGuest(win, ev);
                                continue;
                            }
                            win.lastLocalActionTimestamp = Date.now();
                            if (!win.isPlaying && win.currentTrack) {
                                win.isSyncingFromFriend = true;
                                win.isPlaying = true;
                                Quickshell.execDetached(["python3", win.appDir + "/backend/player_daemon.py", "resume", win.currentTrack.path || ""]);
                                win.syncNowPlaying(true);
                                win.isSyncingFromFriend = false;
                            }
                            var rName = ev.from_name || I18n.tr("Bạn bè", "Friend");
                            win.showToast(I18n.tr(rName + " đã tiếp tục phát bài hát", rName + " resumed playback"));
                        } else if (ev.event === "seek") {
                            win.ensureCoListenerRegistered(ev, true);
                            if (!win.listeningAlongFriend && !win.allowCoListenerControl) {
                                _forceResyncUnauthorizedGuest(win, ev);
                                continue;
                            }
                            var sPos = (ev.data && ev.data.position !== undefined) ? Number(ev.data.position) : (ev.position !== undefined ? Number(ev.position) : -1);
                            if (sPos >= 0) {
                                win.lastLocalActionTimestamp = Date.now();
                                win.isSyncingFromFriend = true;
                                if (win.isLoadingAudio) {
                                    win.pendingListenAlongSeekPosition = sPos;
                                } else {
                                    win.seekLocalOnly(sPos);
                                    listenAlongSeekSafetyTimer.targetPos = sPos;
                                    listenAlongSeekSafetyTimer.restart();
                                }
                                win.syncNowPlaying(true);
                                win.isSyncingFromFriend = false;
                                var skName = ev.from_name || I18n.tr("Bạn bè", "Friend");
                                var timeStr = win.formatPlaybackTime(sPos);
                                win.showToast(I18n.tr(skName + " đã tua đến " + timeStr, skName + " seeked to " + timeStr));
                            }
                        } else if (ev.event === "track_change") {
                            win.ensureCoListenerRegistered(ev, true);
                            var canAcceptTrackChange = (win.listeningAlongFriend !== null) || win.allowCoListenerControl;
                            if (!canAcceptTrackChange) {
                                _forceResyncUnauthorizedGuest(win, ev);
                                continue;
                            }
                            if (ev.data && ev.data.track && canAcceptTrackChange) {
                                var newTrk = ev.data.track;
                                var newVid = newTrk.videoId || newTrk.id || "";
                                if (newVid.startsWith("yt_")) newVid = newVid.replace(/^yt_/, "");
                                var myVid = win.currentTrack ? (win.currentTrack.videoId || win.currentTrack.id || "") : "";
                                if (myVid.startsWith("yt_")) myVid = myVid.replace(/^yt_/, "");
                                if (newVid !== myVid) {
                                    win.isSyncingFromFriend = true;
                                    win.pendingListenAlongSeekPosition = 0;
                                    win.lastTrackSwitchTimestamp = Date.now();
                                    win.lastLocalActionTimestamp = Date.now();
                                    if ((newTrk.path && newTrk.path.startsWith("ytdl://")) || newTrk.videoId) {
                                        win.playOnlineTrack(newTrk, false);
                                    } else {
                                        win.playTrack(newTrk);
                                    }
                                    win.syncNowPlaying(true);
                                    win.isSyncingFromFriend = false;
                                    var tcName = ev.from_name || I18n.tr("Bạn bè", "Friend");
                                    win.showToast(I18n.tr(tcName + " đã chuyển bài hát", tcName + " changed track"));
                                }
                            }
                        } else if (ev.event === "track_suggest") {
                            win.ensureCoListenerRegistered(ev, true);
                            if (ev.data && ev.data.track) {
                                var sFrom = ev.from_name || I18n.tr("Bạn bè", "Friend");
                                var sAvatar = ev.from_avatar || "";
                                if (!sAvatar && win.friendsNotes && Array.isArray(win.friendsNotes)) {
                                    var matchS = win.friendsNotes.find(function(n) {
                                        return (ev.from_email && n.user_email && n.user_email.toLowerCase() === ev.from_email.toLowerCase()) ||
                                               (n.user_name && n.user_name === sFrom);
                                    });
                                    if (matchS) sAvatar = matchS.avatar_url || "";
                                }
                                suggestTrackToast.showSuggestion(sFrom, sAvatar, ev.data.track);
                            }
                        } else if (ev.event === "chat_message") {
                            win.ensureCoListenerRegistered(ev, true);
                            var cFrom = ev.from_name || I18n.tr("Bạn bè", "Friend");
                            var cAvatar = ev.from_avatar || "";
                            var cText = (ev.data && ev.data.text) ? ev.data.text : (ev.data && ev.data.message ? ev.data.message : "");
                            var cMsgId = (ev.data && ev.data.msg_id) ? String(ev.data.msg_id) : "";
                            if (!cAvatar && win.friendsNotes && Array.isArray(win.friendsNotes)) {
                                var matchC = win.friendsNotes.find(function(n) {
                                    return (ev.from_email && n.user_email && n.user_email.toLowerCase() === ev.from_email.toLowerCase()) ||
                                           (n.user_name && n.user_name === cFrom);
                                });
                                if (matchC) cAvatar = matchC.avatar_url || "";
                            }
                            if (cText && !_isDuplicateIncomingChat(ev, cFrom, cText, cMsgId)) {
                                floatingChatContainer.spawnBubble(cFrom, cAvatar, cText);
                            }
                        } else if (ev.event === "friend_request") {
                            win.fetchFriendsDataFast();
                            var frName = ev.from_name || ev.from_email || I18n.tr("Ai đó", "Someone");
                            win.showToast(I18n.tr(frName + " đã gửi lời mời kết bạn", frName + " sent a friend request"));
                        } else if (ev.event === "friend_accepted") {
                            win.fetchFriendsDataFast();
                            win.fetchFriendsNotesFast();
                            var faName = ev.from_name || ev.from_email || I18n.tr("Bạn bè", "Friend");
                            win.showToast(I18n.tr(faName + " đã chấp nhận lời mời kết bạn", faName + " accepted friend request"));
                        } else if (ev.event === "friend_removed") {
                            win.fetchFriendsDataFast();
                            win.fetchFriendsNotesFast();
                        }
                    }
                } catch(e) {}
            }
        }
    };
    evXhr.send();
}

function postDailyNote(win, text, track) {
    var cleanText = text ? String(text).replace(/[\r\n]+/g, " ").trim() : "";
    if (!cleanText && !track) return;

    var rId = track ? (track.videoId || track.id || (track.path && track.path.startsWith("ytdl://") ? track.path.replace("ytdl://", "") : "")) : "";
    if (rId && rId.startsWith("yt_")) {
        rId = rId.replace(/^yt_/, "");
    }
    var tCov = track ? win.getTrackCoverUrl(track) : "";
    var tAccent = (track && track.accent_color && String(track.accent_color).trim() !== "")
        ? track.accent_color
        : (win.songAccentColor && win.songAccentColor !== win.wallpaperAccentColor ? win.songAccentColor.toString() : "");

    var trackObj = track ? {
        id: rId,
        videoId: rId,
        path: (rId ? ("ytdl://" + rId) : (track.path || "")),
        title: track.title || track.name || "",
        artist: track.artist || "",
        cover: tCov,
        image: tCov,
        accent_color: tAccent
    } : null;

    var myNp = (win.currentTrack && win.songAccentColor) ? {
        title: win.currentTrack.title || win.currentTrack.name || "",
        artist: win.currentTrack.artist || "",
        cover: win.getTrackCoverUrl(win.currentTrack),
        accent_color: win.songAccentColor ? win.songAccentColor.toString() : ""
    } : null;

    win.myLatestNote = {
        note_text: cleanText,
        track: trackObj,
        accent_color: tAccent,
        now_playing: myNp,
        created_at: new Date().toISOString()
    };

    var profile = (Quickshell.env("NUTSTY_PROFILE") || "").toLowerCase();
    var email = win.getCurrentUserEmail();
    var apiUrl = (win.notesApiUrl || "http://127.0.0.1:17890") + "/api/notes";

    var payload = {
        profile: profile,
        user_email: email,
        user_name: win.getCurrentUserName(),
        avatar_url: win.getCurrentUserAvatar(),
        note_text: cleanText,
        track: trackObj,
        now_playing: myNp
    };

    var xhr = new XMLHttpRequest();
    xhr.open("POST", apiUrl, true);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                try {
                    var res = JSON.parse(xhr.responseText);
                    if (res && res.note) {
                        win.myLatestNote = res.note;
                    }
                } catch(e) {}
            }
            win.fetchFriendsNotesFast();
            if (typeof win.fetchFriendsList === "function") win.fetchFriendsList();
        }
    };
    xhr.send(JSON.stringify(payload));
    win.syncNowPlaying(true);
    Qt.callLater(function() { win.fetchFriendsNotesFast(); });
}

function deleteMyNote(win) {
    win.myLatestNote = null;
    var profile = (Quickshell.env("NUTSTY_PROFILE") || "").toLowerCase();
    var email = win.getCurrentUserEmail();
    var apiUrl = (win.notesApiUrl || "http://127.0.0.1:17890") + "/api/notes/delete";

    var xhr = new XMLHttpRequest();
    xhr.open("POST", apiUrl, true);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            win.fetchFriendsNotesFast();
            if (typeof win.fetchFriendsList === "function") win.fetchFriendsList();
        }
    };
    xhr.send(JSON.stringify({ profile: profile, user_email: email }));
    Qt.callLater(function() { win.fetchFriendsNotesFast(); });
    win.showToast(I18n.tr("Đã xóa ghi chú", "Note deleted"));
}

function sendFriendRequest(win, targetEmail) {
    var fromEmail = win.getCurrentUserEmail();
    var fromName = win.getCurrentUserName();
    var fromAvatar = win.getCurrentUserAvatar();
    var apiUrl = (win.notesApiUrl || "http://127.0.0.1:17890") + "/api/friends/request";

    var xhr = new XMLHttpRequest();
    xhr.open("POST", apiUrl, true);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                try {
                    var res = JSON.parse(xhr.responseText);
                    if (res.accepted || res.status === "accepted") {
                        win.showToast(I18n.tr("Hai bạn đã trở thành bạn bè!", "You are now friends!"));
                        win.fetchFriendsDataFast();
                        win.fetchFriendsNotesFast();
                    } else {
                        win.showToast(I18n.tr("Đã gửi lời mời kết bạn", "Friend request sent"));
                    }
                } catch(e) {
                    win.showToast(I18n.tr("Đã gửi lời mời kết bạn", "Friend request sent"));
                }
            } else {
                try {
                    var errRes = JSON.parse(xhr.responseText);
                    win.showToast(errRes.error || I18n.tr("Không thể gửi lời mời", "Failed to send request"));
                } catch(e) {
                    win.showToast(I18n.tr("Lỗi khi gửi lời mời", "Error sending request"));
                }
            }
        }
    };
    var profile = (Quickshell.env("NUTSTY_PROFILE") || "").toLowerCase();
    xhr.send(JSON.stringify({
        profile: profile,
        from_email: fromEmail,
        from_name: fromName,
        from_avatar: fromAvatar,
        to_email: targetEmail
    }));
}

function respondFriendRequest(win, requestId, fromEmail, action) {
    var userEmail = win.getCurrentUserEmail();
    var profile = (Quickshell.env("NUTSTY_PROFILE") || "").toLowerCase();
    var apiUrl = (win.notesApiUrl || "http://127.0.0.1:17890") + "/api/friends/respond";

    if (win.pendingFriendRequests && Array.isArray(win.pendingFriendRequests)) {
        win.pendingFriendRequests = win.pendingFriendRequests.filter(function(r) {
            var rid = String(r.id || "");
            var targetId = String(requestId || "");
            var rem = (r.from_email || r.from_tag || "").toLowerCase();
            var targetEm = (fromEmail || "").toLowerCase();
            return rid !== targetId && (!targetEm || rem !== targetEm);
        });
        win.unreadFriendRequestsCount = win.pendingFriendRequests.length;
        if (friendRequestsPopover && friendRequestsPopover.isOpen) {
            friendRequestsPopover.requests = win.pendingFriendRequests;
        }
    }

    var xhr = new XMLHttpRequest();
    xhr.open("POST", apiUrl, true);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                if (action === "accept") {
                    win.showToast(I18n.tr("Đã kết bạn thành công!", "Friend request accepted!"));
                } else {
                    win.showToast(I18n.tr("Đã từ chối lời mời", "Friend request declined"));
                }
                win.fetchFriendsDataFast(function() {
                    win.fetchFriendsNotesFast();
                });
            } else {
                win.fetchFriendsDataFast();
            }
        }
    };
    xhr.send(JSON.stringify({
        user_email: userEmail,
        profile: profile,
        request_id: requestId,
        action: action
    }));
}

function unfriendUser(win, targetEmail) {
    if (!targetEmail) return;
    var userEmail = win.getCurrentUserEmail();
    var targetLower = targetEmail.trim().toLowerCase();

    if (win.friendsList && Array.isArray(win.friendsList)) {
        win.friendsList = win.friendsList.filter(function(e) {
            return (e || "").trim().toLowerCase() !== targetLower;
        });
    }
    if (win.friendsDetails && Array.isArray(win.friendsDetails)) {
        win.friendsDetails = win.friendsDetails.filter(function(f) {
            return (f.email || "").trim().toLowerCase() !== targetLower;
        });
    }
    if (win.friendsNotes && Array.isArray(win.friendsNotes)) {
        win.friendsNotes = win.friendsNotes.filter(function(n) {
            return (n.user_email || "").trim().toLowerCase() !== targetLower;
        });
    }

    var apiUrl = (win.notesApiUrl || "http://127.0.0.1:17890") + "/api/friends/remove";
    var xhr = new XMLHttpRequest();
    xhr.open("POST", apiUrl, true);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                win.showToast(I18n.tr("Đã hủy kết bạn", "Unfriended"));
                win.fetchFriendsDataFast();
                win.fetchFriendsNotesFast();
            }
        }
    };
    xhr.send(JSON.stringify({
        user_email: userEmail,
        target_email: targetEmail
    }));
}

function startListeningAlong(win, friend) {
    if (!friend) return;
    var wasAlreadyListening = (win.listeningAlongFriend !== null && win.listeningAlongFriend !== undefined &&
        ((win.listeningAlongFriend.user_email && friend.user_email && win.listeningAlongFriend.user_email.toLowerCase() === friend.user_email.toLowerCase()) ||
         (win.listeningAlongFriend.user_name && friend.user_name && win.listeningAlongFriend.user_name === friend.user_name)));

    win.listeningAlongFriend = friend;
    win.activeCoListeners = [];
    win.activeCoListenersDetails = [];
    win.lastLocalActionTimestamp = Date.now();
    var activeTrackObj = null;
    if (friend.now_playing && (friend.now_playing.title || friend.now_playing.name) && friend.now_playing.is_playing !== false) {
        activeTrackObj = friend.now_playing;
    } else if (friend.track && (friend.track.title || friend.track.name)) {
        activeTrackObj = friend.track;
    } else if (friend.now_playing && (friend.now_playing.title || friend.now_playing.name)) {
        activeTrackObj = friend.now_playing;
    }
    if (activeTrackObj) {
        var vid = activeTrackObj.videoId || activeTrackObj.id || activeTrackObj.video_id || "";
        if (vid && vid.startsWith("yt_")) vid = vid.replace(/^yt_/, "");
        var path = activeTrackObj.path || (vid ? ("ytdl://" + vid) : "");
        var trk = {
            id: vid || ("social_" + Date.now()),
            videoId: vid,
            title: activeTrackObj.title || activeTrackObj.name || "Track",
            artist: activeTrackObj.artist || friend.user_name || "Artist",
            image: activeTrackObj.cover || activeTrackObj.image || activeTrackObj.cover_url || activeTrackObj.thumbnail || "",
            cover: activeTrackObj.cover || activeTrackObj.image || activeTrackObj.cover_url || activeTrackObj.thumbnail || "",
            duration: activeTrackObj.duration || 0,
            path: path
        };

        var targetPos = 0;
        if (activeTrackObj.position !== undefined && activeTrackObj.position !== null) {
            targetPos = Number(activeTrackObj.position);
        } else if (friend.progress_seconds !== undefined) {
            targetPos = Number(friend.progress_seconds);
        }
        var ts = activeTrackObj.timestamp || friend.updated_at_ts || friend.last_updated || 0;
        if (ts > 0 && activeTrackObj.is_playing !== false) {
            var nowSec = Date.now() / 1000.0;
            var recordSec = (ts > 1000000000000) ? (ts / 1000.0) : Number(ts);
            var elapsed = nowSec - recordSec;
            if (elapsed > 0 && elapsed < (trk.duration || 600)) {
                targetPos += elapsed;
            }
        }

        if (win.currentTrack && win.isSameTrack(win.currentTrack, trk)) {
            if (targetPos > 0 && Math.abs(win.currentTime - targetPos) > 3.0) {
                if (!win.isLoadingAudio) {
                    win.seekLocalOnly(targetPos);
                } else {
                    win.pendingListenAlongSeekPosition = targetPos;
                }
            }
            if (!win.isPlaying) win.togglePlay();
        } else {
            win.pendingListenAlongSeekPosition = targetPos;
            win.isSyncingFromFriend = true;
            win.playOnlineTrack(trk, false);
            win.isSyncingFromFriend = false;
        }
    }
    win.isNowPlayingOpen = true;
    if (friend.now_playing && friend.now_playing.allow_control !== undefined) {
        win.guestCanControlHost = Boolean(friend.now_playing.allow_control);
    } else if (!wasAlreadyListening) {
        win.guestCanControlHost = true;
    }
    if (!wasAlreadyListening) {
        var friendName = friend.user_name || I18n.tr("Bạn bè", "Friend");
        win.showToast(I18n.tr("Đang nghe cùng " + friendName, "Listening along with " + friendName));
        var joinTarget = friend.tag || friend.user_id || friend.user_email || "";
        if (joinTarget) {
            win.lastJoinHeartbeatTimestamp = Date.now();
            win.sendSocialEventFast("join", joinTarget);
        }
    }
}

function exitListeningAlong(win) {
    if (!win.listeningAlongFriend) return;
    var friend = win.listeningAlongFriend;
    var friendEmail = friend.tag || friend.user_id || friend.user_email || "";
    var friendName = friend.user_name || I18n.tr("Bạn bè", "Friend");
    win.listeningAlongFriend = null;
    win.showToast(I18n.tr("Đã rời chế độ nghe cùng với " + friendName, "Left listen along with " + friendName));
    if (friendEmail) {
        win.sendSocialEventFast("leave", friendEmail);
    }
}

function stopAllCoListening(win) {
    if (win.activeCoListeners && win.activeCoListeners.length > 0) {
        for (var i = 0; i < win.activeCoListeners.length; i++) {
            win.sendSocialEventFast("leave", win.activeCoListeners[i]);
        }
    }
    win.activeCoListeners = [];
    win.activeCoListenersDetails = [];
    win.showToast(I18n.tr("Đã dừng phát cùng tất cả bạn bè", "Ended co-listening session with all friends"));
}

function kickCoListener(win, kEmail, kName) {
    if (!kEmail) return;
    var cleanEmail = kEmail.toLowerCase().trim();
    if (win.activeCoListeners) {
        win.activeCoListeners = win.activeCoListeners.filter(function(e) { return (e || "").toLowerCase() !== cleanEmail; });
    }
    if (win.activeCoListenersDetails) {
        win.activeCoListenersDetails = win.activeCoListenersDetails.filter(function(d) { return (d.email || "").toLowerCase() !== cleanEmail; });
    }
    win.sendSocialEventFast("kick", kEmail);
    win.sendSocialEventFast("leave", kEmail);
    if (coListenersPopover.visible) {
        coListenersPopover.openAt(win.activeCoListenersDetails);
    }
    var displayName = kName || kEmail;
    win.showToast(I18n.tr("Đã mời " + displayName + " ra khỏi phiên nghe cùng", "Removed " + displayName + " from co-listening session"));
}

function suggestTrackToHost(win, trk) {
    if (!win.listeningAlongFriend) return;
    var hostEmail = win.listeningAlongFriend.tag || win.listeningAlongFriend.user_id || win.listeningAlongFriend.user_email || "";
    if (!hostEmail) return;
    var hostName = win.listeningAlongFriend.user_name || I18n.tr("Host", "Host");
    win.sendSocialEventFast("track_suggest", hostEmail, { track: trk });
    win.showToast(I18n.tr("Host đã khóa quyền chuyển bài — Đã gửi đề xuất cho " + hostName, "Host locked track change — Suggested track to " + hostName));
}

var _recentChatDedupe = {};

function _isDuplicateIncomingChat(ev, senderName, text, msgId) {
    var now = Date.now();
    for (var k in _recentChatDedupe) {
        if (now - _recentChatDedupe[k] > 3500) {
            delete _recentChatDedupe[k];
        }
    }
    var fromKey = String((ev && (ev.from_id || ev.from_email || ev.from_name)) || senderName || "").trim().toLowerCase();
    var textKey = fromKey + "|" + String(text || "").trim();
    if (msgId && _recentChatDedupe["id:" + msgId]) {
        return true;
    }
    if (_recentChatDedupe["txt:" + textKey] && (now - _recentChatDedupe["txt:" + textKey] < 3000)) {
        return true;
    }
    if (msgId) _recentChatDedupe["id:" + msgId] = now;
    _recentChatDedupe["txt:" + textKey] = now;
    return false;
}

function _forceResyncUnauthorizedGuest(win, ev) {
    if (!ev) return;
    var senderTarget = ev.from_id || ev.from_email || "";
    if (!senderTarget) return;
    win.sendSocialEventFast("permission_update", senderTarget, { allow_control: false });
    if (win.currentTrack) {
        win.sendSocialEventFast("track_change", senderTarget, { track: win.currentTrack });
        win.sendSocialEventFast(win.isPlaying ? "play" : "pause", senderTarget);
        win.sendSocialEventFast("seek", senderTarget, { position: win.currentTime });
    }
}

function sendChatMessage(win, text) {
    if (!text || text.trim() === "") return;
    var cleanText = text.trim();
    var myName = win.getCurrentUserName() || I18n.tr("Tôi", "Me");
    var myAvatar = win.getCurrentUserAvatar() || "";
    if (!myAvatar && win.myLatestNote && win.myLatestNote.avatar_url) {
        myAvatar = win.myLatestNote.avatar_url;
    }

    var msgId = "msg_" + Date.now() + "_" + Math.floor(Math.random() * 10000);
    var sentTargets = {};

    function collectPeerAliases(candidate) {
        var peer = normalizePeer(candidate);
        var keys = [];
        function addK(v) {
            var s = String(v || "").trim().toLowerCase();
            if (s && keys.indexOf(s) === -1) keys.push(s);
        }
        addK(peer.user_id);
        addK(peer.tag);
        addK(peer.email);
        addK(peer.name);
        if (typeof candidate === "string") addK(candidate);
        if (win.activeCoListenersDetails && Array.isArray(win.activeCoListenersDetails)) {
            for (var i = 0; i < win.activeCoListenersDetails.length; i++) {
                var d = normalizePeer(win.activeCoListenersDetails[i]);
                if ((d.user_id && keys.indexOf(d.user_id.toLowerCase()) !== -1) ||
                    (d.tag && keys.indexOf(d.tag.toLowerCase()) !== -1) ||
                    (d.email && keys.indexOf(d.email.toLowerCase()) !== -1) ||
                    (d.name && keys.indexOf(d.name.toLowerCase()) !== -1)) {
                    addK(d.user_id);
                    addK(d.tag);
                    addK(d.email);
                    addK(d.name);
                }
            }
        }
        if (win.friendsNotes && Array.isArray(win.friendsNotes)) {
            for (var j = 0; j < win.friendsNotes.length; j++) {
                var fn = normalizePeer(win.friendsNotes[j]);
                if ((fn.user_id && keys.indexOf(fn.user_id.toLowerCase()) !== -1) ||
                    (fn.tag && keys.indexOf(fn.tag.toLowerCase()) !== -1) ||
                    (fn.email && keys.indexOf(fn.email.toLowerCase()) !== -1) ||
                    (fn.name && keys.indexOf(fn.name.toLowerCase()) !== -1)) {
                    addK(fn.user_id);
                    addK(fn.tag);
                    addK(fn.email);
                    addK(fn.name);
                }
            }
        }
        return { peer: peer, keys: keys };
    }

    function sendOnceToPeer(candidate) {
        if (!candidate) return;
        var info = collectPeerAliases(candidate);
        var bestTarget = info.peer.user_id || info.peer.tag || info.peer.email || (typeof candidate === "string" ? candidate.trim() : "");
        if (!bestTarget) return;
        for (var k = 0; k < info.keys.length; k++) {
            if (sentTargets[info.keys[k]]) return;
        }
        for (var m = 0; m < info.keys.length; m++) {
            sentTargets[info.keys[m]] = true;
        }
        win.sendSocialEventFast("chat_message", String(bestTarget).trim(), { text: cleanText, msg_id: msgId });
    }

    if (win.listeningAlongFriend) {
        sendOnceToPeer(win.listeningAlongFriend);
    }

    if (win.activeCoListenersDetails && win.activeCoListenersDetails.length > 0) {
        for (var di = 0; di < win.activeCoListenersDetails.length; di++) {
            sendOnceToPeer(win.activeCoListenersDetails[di]);
        }
    }
    if (win.activeCoListeners && win.activeCoListeners.length > 0) {
        for (var ci = 0; ci < win.activeCoListeners.length; ci++) {
            sendOnceToPeer(win.activeCoListeners[ci]);
        }
    }

    if (Object.keys(sentTargets).length === 0 && win.friendsNotes && win.friendsNotes.length > 0) {
        for (var fi = 0; fi < win.friendsNotes.length; fi++) {
            var fn = win.friendsNotes[fi];
            if (fn && (fn.is_online || win.friendsNotes.length === 1)) {
                sendOnceToPeer(fn);
            }
        }
    }

    floatingChatContainer.spawnBubble(myName, myAvatar, cleanText);
}
