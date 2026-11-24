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

// What this device reports as now playing, or undefined when it should not report right now (a
// guest still loading the host's song or waiting for its seek would send a stale position).
function _presenceNowPlaying(win) {
    var email = win.getCurrentUserEmail();
    if (!email) return undefined;
    if (win.listeningAlongFriend) {
        var hostEm = String(win.listeningAlongFriend.user_email || win.listeningAlongFriend.tag || "").trim().toLowerCase();
        if (hostEm && hostEm === String(email).trim().toLowerCase()) return undefined;
        if (win.isLoadingAudio || win.pendingListenAlongSeekPosition > 0) return undefined;
    }
    var cur = win.currentTrack;
    if (!cur) return null;
    var rawVid = cur.videoId || cur.id || (cur.path && typeof cur.path === "string" && cur.path.startsWith("ytdl://") ? cur.path.replace("ytdl://", "") : "");
    var vid = rawVid ? String(rawVid) : "";
    if (vid && vid.startsWith("yt_")) vid = vid.replace(/^yt_/, "");
    var cov = win.getTrackCoverUrl(cur);
    var reportPos = (win.pendingListenAlongSeekPosition > 0) ? win.pendingListenAlongSeekPosition : (win.currentTime || 0);
    return {
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

// Fields whose change makes the next tick report presence at once (position alone does not:
// listeners extrapolate it from the timestamp, and play/pause/seek also go out as events)
function _presenceKey(np) {
    return np ? [np.videoId, np.is_playing, np.allow_control].join("|") : "none";
}

// Immediate presence report (song change, play/pause, a listener joined). The periodic heartbeat
// rides on socialTick instead.
function syncNowPlaying(win, force) {
    var now = Date.now();
    if (!force && (now - win.lastNowPlayingSyncTime < 4000)) return;
    var npData = _presenceNowPlaying(win);
    if (npData === undefined) return;

    win.lastNowPlayingSyncTime = now;
    _tick.presenceAt = now;
    _tick.presenceKey = _presenceKey(npData);

    var xhr = new XMLHttpRequest();
    xhr.open("POST", (win.notesApiUrl || "http://127.0.0.1:17890") + "/api/now_playing", true);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.send(JSON.stringify({
        profile: (Quickshell.env("NUTSTY_PROFILE") || "").toLowerCase(),
        user_email: win.getCurrentUserEmail(),
        user_name: win.getCurrentUserName() || "",
        avatar_url: win.getCurrentUserAvatar() || "",
        now_playing: npData
    }));
}

// ---------------------------------------------------------------------------------------------
// One social poll (POST /api/social/tick): unread events every tick, presence when it changed or
// every PRESENCE_HEARTBEAT_MS (under the relay's 25 s online window), the notes feed every
// notesEveryMs, and the Listen Along host's presence every tick while listening along.
// One relay request per tick instead of three (Cloudflare free plan: 100k requests a day).
// ---------------------------------------------------------------------------------------------
var PRESENCE_HEARTBEAT_MS = 18000;
var GUEST_HEARTBEAT_MS = 15000;
var _tick = { inFlight: false, startedAt: 0, presenceAt: 0, presenceKey: "", notesAt: 0, notesHash: "", notesNow: false };

function _isGuest(win) {
    return Boolean(win.listeningAlongFriend) && (!win.activeCoListeners || win.activeCoListeners.length === 0);
}

function socialTick(win, notesEveryMs) {
    var now = Date.now();
    if (_tick.inFlight && now - _tick.startedAt < 15000) return;
    var email = win.getCurrentUserEmail();
    if (!email) return;

    var body = {
        profile: (Quickshell.env("NUTSTY_PROFILE") || "").toLowerCase(),
        user_email: email
    };
    var np = _presenceNowPlaying(win);
    var npKey = _presenceKey(np);
    var sendPresence = np !== undefined && (npKey !== _tick.presenceKey || now - _tick.presenceAt >= PRESENCE_HEARTBEAT_MS);
    if (sendPresence) body.now_playing = np;
    var wantNotes = _tick.notesNow || now - _tick.notesAt >= (notesEveryMs || 20000);
    if (wantNotes) {
        body.notes = true;
        body.notes_hash = _tick.notesHash;
    }
    var guest = _isGuest(win);
    var hostId = guest ? String(win.listeningAlongFriend.user_id || win.listeningAlongFriend.id || "") : "";
    if (hostId) body.watch = hostId;

    // The host drops a listener it has not heard from in LISTENER_TIMEOUT_MS
    if (guest && now - win.lastJoinHeartbeatTimestamp > GUEST_HEARTBEAT_MS) {
        win.lastJoinHeartbeatTimestamp = now;
        var hbTarget = win.listeningAlongFriend.tag || win.listeningAlongFriend.user_id || win.listeningAlongFriend.user_email || "";
        if (hbTarget) win.sendSocialEventFast("join", hbTarget, { heartbeat: true });
    }

    _tick.inFlight = true;
    _tick.startedAt = now;
    var seqAtStart = _noteMutationSeq;
    var xhr = new XMLHttpRequest();
    xhr.open("POST", (win.notesApiUrl || "http://127.0.0.1:17890") + "/api/social/tick", true);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.timeout = 10000;
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        _tick.inFlight = false;
        if (xhr.status === 404) {
            // A backend started before this build has no /api/social/tick yet: poll the old way
            pollSocialEventsFast(win);
            if (wantNotes) { _tick.notesAt = now; _tick.notesNow = false; fetchFriendsNotesFast(win); }
            if (sendPresence) syncNowPlaying(win, true);
            return;
        }
        if (xhr.status !== 200) return;
        var res = null;
        try { res = JSON.parse(xhr.responseText); } catch (e) { return; }
        if (!res || !res.success) return;
        if (sendPresence) {
            _tick.presenceAt = now;
            _tick.presenceKey = npKey;
            win.lastNowPlayingSyncTime = now;
        }
        if (wantNotes && res.notes_hash !== undefined) {
            _tick.notesAt = now;
            _tick.notesNow = false;
            if (!res.notes_unchanged) {
                _tick.notesHash = res.notes_hash;
                try { applyNotesFeed(win, res, seqAtStart, Boolean(hostId && res.watch)); } catch (e1) {}
            }
        }
        try { handleSocialEvents(win, Array.isArray(res.events) ? res.events : []); } catch (e2) {}
        if (hostId && res.watch && _isGuest(win)) {
            try { syncWithHostPeer(win, res.watch); } catch (e3) {}
        }
    };
    xhr.send(JSON.stringify(body));
}

function fetchCurrentUserProfile(win) {
    var profile = (Quickshell.env("NUTSTY_PROFILE") || "").toLowerCase();
    // Before the account is known getCurrentUserEmail() falls back to a placeholder, and the
    // relay answers that with a different (stray) profile whose name then flashes on screen.
    // The auth status check calls this again once the real account is in.
    if (!win.authAccountEmail && !profile) return;
    var email = win.getCurrentUserEmail();
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
                    var joined = Number(res.profile.created_at || 0);
                    // Cloud stores seconds; QML dates want milliseconds
                    if (joined > 0) win.currentUserJoinedAt = joined < 100000000000 ? joined * 1000 : joined;
                    if (res.profile.username && res.profile.username !== "Nutsty User") {
                        win.currentUserName = res.profile.username;
                        win.currentUserTag = res.profile.tag || (res.profile.username + "#" + win.currentUserPin);
                    } else if (win.authAccountName) {
                        win.currentUserName = win.authAccountName;
                        win.currentUserTag = win.authAccountName + "#" + win.currentUserPin;
                    }
                }
            } catch(e) {}
        }
        // answered or failed: either way the welcome card stops waiting for a name
        if (xhr.readyState === XMLHttpRequest.DONE && typeof win.markIdentitySettled === "function")
            win.markIdentitySettled();
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

// A post/delete of my own note bumps _noteMutationSeq. A notes fetch that started before the
// mutation finished carries the old my_note and must not overwrite the optimistic value.
var _noteMutationSeq = 0;
var _noteMutationsInFlight = 0;
var _notesRefetchQueued = false;

function _finishNoteMutation(win) {
    _noteMutationSeq++;
    _noteMutationsInFlight = Math.max(0, _noteMutationsInFlight - 1);
    fetchFriendsNotesFast(win);
}

function fetchFriendsNotesFast(win) {
    if (win.isFetchingNotesFast) {
        _notesRefetchQueued = true;
        return;
    }
    win.isFetchingNotesFast = true;
    _notesRefetchQueued = false;
    var seqAtStart = _noteMutationSeq;
    var _finished = false;
    var _done = function() {
        if (_finished) return;
        _finished = true;
        win.isFetchingNotesFast = false;
        if (_notesRefetchQueued) Qt.callLater(function() { fetchFriendsNotesFast(win); });
    };

    var email = win.getCurrentUserEmail();
    var profile = (Quickshell.env("NUTSTY_PROFILE") || "").toLowerCase();
    var friendsParam = (win.friendsList && win.friendsList.length > 0)
        ? win.friendsList.join(",")
        : "";
    var url = (win.notesApiUrl || "http://127.0.0.1:17890") + "/api/notes?friends=" + encodeURIComponent(friendsParam) + (email ? ("&user_email=" + encodeURIComponent(email)) : "") + (profile ? ("&profile=" + encodeURIComponent(profile)) : "");

    var xhr = new XMLHttpRequest();
    xhr.open("GET", url, true);
    xhr.timeout = 8000;
    xhr.ontimeout = _done;
    xhr.onerror = _done;
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            _done();
            if (xhr.status === 200) {
                try {
                    var parsed = JSON.parse(xhr.responseText);
                    applyNotesFeed(win, parsed, seqAtStart, false);
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

// Who sent a playback event, relative to the current listen-along session:
// "host" (the friend I listen along with), "listener" (someone listening along with me) or "".
// Only "join" may add a listener; anything else from outside the session is stale and ignored,
// otherwise a late seek/pause from an old host turns it into a phantom listener that controls us.
function sessionRole(win, ev) {
    if (!ev) return "";
    var keys = {};
    [ev.from_id, ev.from_email, ev.from_tag, ev.user_id, ev.tag].forEach(function(k) {
        var s = String(k || "").trim().toLowerCase();
        if (s) keys[s] = true;
    });
    function matches(obj) {
        if (!obj) return false;
        if (typeof obj !== "object") return !!keys[String(obj).trim().toLowerCase()];
        var cand = [obj.user_id, obj.id, obj.tag, obj.email, obj.user_email];
        for (var i = 0; i < cand.length; i++) {
            var c = String(cand[i] || "").trim().toLowerCase();
            if (c && keys[c]) return true;
        }
        return false;
    }
    if (win.listeningAlongFriend && matches(win.listeningAlongFriend)) return "host";
    var lists = [win.activeCoListeners || [], win.activeCoListenersDetails || []];
    for (var l = 0; l < lists.length; l++) {
        for (var j = 0; j < lists[l].length; j++) {
            if (matches(lists[l][j])) return "listener";
        }
    }
    return "";
}

// Guests send a join heartbeat every ~10 s while listening along. A listener that has been silent
// for LISTENER_TIMEOUT_MS closed the app or lost the connection without sending "leave".
var LISTENER_TIMEOUT_MS = 35000;
var _listenerSeenAt = {};

function _touchListener(win, ev) {
    if (sessionRole(win, ev) !== "listener") return;
    var list = win.activeCoListeners || [];
    var keys = [ev.from_id, ev.from_email, ev.from_tag].map(function(k) { return String(k || "").trim().toLowerCase(); });
    for (var i = 0; i < list.length; i++) {
        var entry = String(list[i] || "").trim().toLowerCase();
        if (entry && keys.indexOf(entry) !== -1) _listenerSeenAt[entry] = Date.now();
    }
}

function _pruneSilentListeners(win) {
    var list = win.activeCoListeners || [];
    if (list.length === 0) return;
    var now = Date.now();
    var gone = [];
    for (var i = 0; i < list.length; i++) {
        var entry = String(list[i] || "").trim().toLowerCase();
        if (!_listenerSeenAt[entry]) _listenerSeenAt[entry] = now;
        else if (now - _listenerSeenAt[entry] > LISTENER_TIMEOUT_MS) gone.push(entry);
    }
    if (gone.length === 0) return;
    win.activeCoListeners = list.filter(function(e) { return gone.indexOf(String(e || "").trim().toLowerCase()) === -1; });
    var removedNames = [];
    win.activeCoListenersDetails = (win.activeCoListenersDetails || []).filter(function(d) {
        var em = String(d.email || d.tag || "").trim().toLowerCase();
        if (gone.indexOf(em) !== -1) { removedNames.push(d.name || em); return false; }
        return true;
    });
    for (var g = 0; g < gone.length; g++) delete _listenerSeenAt[gone[g]];
    if (coListenersPopover.visible) coListenersPopover.openAt(win.activeCoListenersDetails);
    var who = removedNames.length > 0 ? removedNames.join(", ") : I18n.tr("Bạn bè", "Friend");
    win.notify("listen", I18n.tr(who + " đã mất kết nối khỏi phòng nghe cùng", who + " dropped out of the listening session"));
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
    _listenerSeenAt[jEmail] = Date.now();

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
        win.notify("listen", I18n.tr(jName + " đang nghe cùng bạn", jName + " is listening along with you"));
        win.sendSocialEventFast("permission_update", rawEmail, { allow_control: win.allowCoListenerControl });
    }
    return isNewListener;
}

// Applies a notes feed (friends' notes + presence, my note). Unless skipHostSync, a guest also
// follows the Listen Along host's now_playing found in it (the tick sends that as `watch` instead).
function applyNotesFeed(win, parsed, seqAtStart, skipHostSync) {
    if (parsed && typeof parsed === "object") {
        if (Array.isArray(parsed.notes)) {
            win.friendsNotes = parsed.notes;
        }
        if (parsed.my_note !== undefined && _noteMutationsInFlight === 0 && seqAtStart === _noteMutationSeq) {
            win.myLatestNote = parsed.my_note;
        }

        if (!skipHostSync && win.listeningAlongFriend && (!win.activeCoListeners || win.activeCoListeners.length === 0) && Array.isArray(parsed.notes)) {
            var targetEmail = (win.listeningAlongFriend.user_email || win.listeningAlongFriend.tag || "").toLowerCase();
            var targetUserId = (win.listeningAlongFriend.user_id || win.listeningAlongFriend.id || "");
            var targetName = win.listeningAlongFriend.user_name;
            syncWithHostPeer(win, parsed.notes.find(function(f) {
                var fEm = (f.user_email || f.tag || "").toLowerCase();
                var fUid = f.user_id || f.id || "";
                return (targetUserId && fUid && fUid === targetUserId) ||
                       (targetEmail && fEm === targetEmail) ||
                       (targetName && f.user_name === targetName);
            }));
        }
    }
}

// Guest side of Listen Along: follow the host's reported song, play state and position
// (position moved on by the time since the host stamped it, so a slow poll still lands on time).
function syncWithHostPeer(win, updated) {
    if (!updated || !updated.now_playing || !win.listeningAlongFriend) return;
    var targetEmail = (win.listeningAlongFriend.user_email || win.listeningAlongFriend.tag || "").toLowerCase();
    var targetUserId = (win.listeningAlongFriend.user_id || win.listeningAlongFriend.id || "");
    var targetName = win.listeningAlongFriend.user_name;
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
        var npAge = np.timestamp ? hostStampAgeSec(targetUserId || targetEmail || targetName || "", np.timestamp, win.totalDuration || 600) : 0;
        if (np.is_playing === true) expectedPos += npAge;
        if (win.isLoadingAudio) {
            win.pendingListenAlongSeekPosition = expectedPos;
        } else {
            var drift = Math.abs(win.currentTime - expectedPos);
            if (drift > DRIFT_TOLERANCE_SEC && expectedPos >= 0) {
                win.seekLocalOnly(expectedPos);
            }
        }

        win.isSyncingFromFriend = false;
    }
}

// Drift beyond this between host and guest is corrected with a seek
var DRIFT_TOLERANCE_SEC = 2.0;

function _vidOf(trk) {
    if (!trk) return "";
    var v = String(trk.videoId || trk.id || (trk.path && String(trk.path).startsWith("ytdl://") ? String(trk.path).replace("ytdl://", "") : "") || "");
    return v.replace(/^yt_/, "");
}

function listenSyncData(win, position) {
    return { videoId: _vidOf(win.currentTrack), position: Number(position !== undefined ? position : win.currentTime) || 0 };
}

// play/pause/seek name the song they were sent for (older builds send none: accept those)
function _eventIsForOtherTrack(win, ev) {
    var evVid = ev && ev.data && ev.data.videoId ? String(ev.data.videoId).replace(/^yt_/, "") : "";
    var myVid = _vidOf(win.currentTrack);
    return Boolean(evVid && myVid && evVid !== myVid);
}

function _eventPositionForMe(win, ev) {
    if (!ev || !ev.data || ev.data.position === undefined || _eventIsForOtherTrack(win, ev)) return -1;
    if (!ev.data.videoId || win.isLoadingAudio) return -1;
    var p = Number(ev.data.position);
    return isNaN(p) ? -1 : p;
}

// The host stamps now_playing with its own clock, and the guest's clock can be seconds apart.
// Each time a new stamp shows up, (guest now - stamp) = clock offset + delivery delay; the smallest
// of the recent ones is the offset plus the shortest delay, so subtracting it removes the offset
// (Cristian / NTP style minimum filter).
var _hostClock = { key: "", lastStamp: 0, samples: [] };

function hostStampAgeSec(hostKey, stamp, maxSec) {
    var stampMs = Number(stamp) > 1000000000000 ? Number(stamp) : Number(stamp) * 1000.0;
    if (!(stampMs > 0)) return 0;
    var raw = Date.now() - stampMs;
    if (_hostClock.key !== hostKey) _hostClock = { key: hostKey, lastStamp: 0, samples: [] };
    if (stampMs !== _hostClock.lastStamp) {
        _hostClock.lastStamp = stampMs;
        _hostClock.samples.push(raw);
        if (_hostClock.samples.length > 20) _hostClock.samples.shift();
    }
    var age = raw;
    if (_hostClock.samples.length >= 3) age = raw - Math.min.apply(null, _hostClock.samples);
    var limit = (maxSec > 0 ? maxSec : 600) * 1000;
    return (age > 0 && age < limit) ? age / 1000.0 : 0;
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
                    handleSocialEvents(win, (evData && Array.isArray(evData.events)) ? evData.events : []);
                } catch(e) {}
            }
        }
    };
    evXhr.send();
}

// Applies events from /api/notes/events or /api/social/tick (join, play/pause/seek, chat, ...)
function handleSocialEvents(win, events) {
    for (var i = 0; i < events.length; i++) {
        var ev = events[i];
        if (!ev) continue;
        _touchListener(win, ev);
        if (ev.event === "join") {
            var isNew = win.ensureCoListenerRegistered(ev, true);
            var isHb = (ev.data && ev.data.heartbeat === true);
            if (isNew || !isHb) {
                win.lastLocalActionTimestamp = Date.now();
                win.syncNowPlaying(true);
                var targetSender = ev.from_email || ev.from_id || "";
                if (win.currentTrack && targetSender) {
                    win.sendSocialEventFast(win.isPlaying ? "play" : "pause", targetSender, listenSyncData(win));
                    win.sendSocialEventFast("seek", targetSender, listenSyncData(win));
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
                win.notify("listen", leaveMsg);
            } else {
                win.notify("listen", I18n.tr(fromName + " đã dừng nghe cùng bạn", fromName + " stopped listening along with you"));
            }
        } else if (ev.event === "pause") {
            var role = sessionRole(win, ev);
            if (!role) continue;
            if (role === "listener" && !win.allowCoListenerControl) {
                _forceResyncUnauthorizedGuest(win, ev);
                continue;
            }
            win.lastLocalActionTimestamp = Date.now();
            // Read before the pause below clears isLoadingAudio (no seek into a song still loading)
            var pPos = _eventPositionForMe(win, ev);
            if (win.isPlaying) {
                win.isSyncingFromFriend = true;
                win.isPlaying = false;
                win.isLoadingAudio = false;
                Quickshell.execDetached(["python3", win.appDir + "/backend/player_daemon.py", "pause"]);
                win.syncNowPlaying(true);
                win.isSyncingFromFriend = false;
            }
            // Stop on the sender's spot so the next play starts both from one place
            if (pPos >= 0 && Math.abs(win.currentTime - pPos) > 0.3) {
                win.seekLocalOnly(pPos);
            }
            var pName = ev.from_name || I18n.tr("Bạn bè", "Friend");
            win.showToast(I18n.tr(pName + " đã tạm dừng bài hát", pName + " paused playback"));
        } else if (ev.event === "play" || ev.event === "resume") {
            var role = sessionRole(win, ev);
            if (!role) continue;
            if (role === "listener" && !win.allowCoListenerControl) {
                _forceResyncUnauthorizedGuest(win, ev);
                continue;
            }
            if (_eventIsForOtherTrack(win, ev)) continue;
            win.lastLocalActionTimestamp = Date.now();
            var plPos = _eventPositionForMe(win, ev);
            if (plPos >= 0 && Math.abs(win.currentTime - plPos) > DRIFT_TOLERANCE_SEC) {
                win.seekLocalOnly(plPos);
            }
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
            var role = sessionRole(win, ev);
            if (!role) continue;
            if (role === "listener" && !win.allowCoListenerControl) {
                _forceResyncUnauthorizedGuest(win, ev);
                continue;
            }
            // A seek made on the previous song, arriving after the switch
            if (_eventIsForOtherTrack(win, ev)) continue;
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
            var tcRole = sessionRole(win, ev);
            if (!tcRole) continue;
            var canAcceptTrackChange = tcRole === "host" || win.allowCoListenerControl;
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
                var sTitle = ev.data.track.title || ev.data.track.name || "";
                win.notificationStore.add("listen", I18n.tr(sFrom + " gợi ý bài " + sTitle, sFrom + " suggested " + sTitle));
                suggestTrackToast.showSuggestion(sFrom, sAvatar, ev.data.track);
            }
        } else if (ev.event === "listen_invite") {
            handleListenInvite(win, ev);
        } else if (ev.event === "chat_message") {
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
            win.notify("friend", I18n.tr(frName + " đã gửi lời mời kết bạn", frName + " sent a friend request"));
        } else if (ev.event === "friend_accepted") {
            win.fetchFriendsDataFast();
            win.fetchFriendsNotesFast();
            var faName = ev.from_name || ev.from_email || I18n.tr("Bạn bè", "Friend");
            win.notify("friend", I18n.tr(faName + " đã chấp nhận lời mời kết bạn", faName + " accepted friend request"));
        } else if (ev.event === "friend_removed") {
            win.fetchFriendsDataFast();
            win.fetchFriendsNotesFast();
        }
    }
    _pruneSilentListeners(win);
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

    _noteMutationsInFlight++;
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
            _finishNoteMutation(win);
            if (typeof win.fetchFriendsList === "function") win.fetchFriendsList();
        }
    };
    xhr.send(JSON.stringify(payload));
    win.syncNowPlaying(true);
}

function deleteMyNote(win) {
    _noteMutationsInFlight++;
    win.myLatestNote = null;
    var profile = (Quickshell.env("NUTSTY_PROFILE") || "").toLowerCase();
    var email = win.getCurrentUserEmail();
    var apiUrl = (win.notesApiUrl || "http://127.0.0.1:17890") + "/api/notes/delete";

    var xhr = new XMLHttpRequest();
    xhr.open("POST", apiUrl, true);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            _finishNoteMutation(win);
            if (typeof win.fetchFriendsList === "function") win.fetchFriendsList();
        }
    };
    xhr.send(JSON.stringify({ profile: profile, user_email: email }));
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
                        win.notify("friend", I18n.tr("Hai bạn đã trở thành bạn bè!", "You are now friends!"));
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
            var hostKey = friend.user_id || friend.id || (friend.user_email || friend.tag || "").toLowerCase() || friend.user_name || "";
            targetPos += hostStampAgeSec(hostKey, ts, trk.duration || 600);
        }

        if (win.currentTrack && win.isSameTrack(win.currentTrack, trk)) {
            if (targetPos > 0 && Math.abs(win.currentTime - targetPos) > DRIFT_TOLERANCE_SEC) {
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
        win.showToast(I18n.tr("Đang nghe cùng " + friendName, "Listening along with " + friendName), "listen");
        var joinTarget = friend.tag || friend.user_id || friend.user_email || "";
        if (joinTarget) {
            win.lastJoinHeartbeatTimestamp = Date.now();
            win.sendSocialEventFast("join", joinTarget);
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Listen-along invites: the host sends "listen_invite" with its current track; the friend gets a
// toast and joins through the normal startListeningAlong path, so the host syncs it on "join".
// ---------------------------------------------------------------------------------------------
var INVITE_COOLDOWN_MS = 30000;
var INVITE_MAX_AGE_SEC = 120;
var _inviteSentAt = {};

function _friendKey(f) {
    return String((f && (f.tag || f.user_id || f.user_email || f.email)) || "").trim();
}

function canInviteToListen(win) {
    return Boolean(win.currentTrack) && !win.listeningAlongFriend;
}

function sendListenInvite(win, friend) {
    var target = _friendKey(friend);
    var name = (friend && (friend.user_name || friend.name)) || I18n.tr("Bạn bè", "Friend");
    if (!target) return false;
    if (!canInviteToListen(win)) {
        win.showToast(I18n.tr("Hãy phát một bài hát trước khi mời", "Play a track before inviting"));
        return false;
    }
    var key = target.toLowerCase();
    var now = Date.now();
    if (_inviteSentAt[key] && now - _inviteSentAt[key] < INVITE_COOLDOWN_MS) {
        win.showToast(I18n.tr("Vừa mời " + name + ", chờ một chút rồi mời lại nhé", "You just invited " + name + ", try again in a moment"));
        return false;
    }
    _inviteSentAt[key] = now;
    var t = win.currentTrack;
    var vid = String(t.videoId || t.id || "").replace(/^yt_/, "");
    var path = t.path || (vid ? ("ytdl://" + vid) : "");
    win.sendSocialEventFast("listen_invite", target, {
        track: {
            title: t.title || t.name || "",
            artist: t.artist || "",
            cover: win.getTrackCoverUrl(t) || "",
            videoId: vid,
            path: path,
            duration: win.totalDuration || t.duration || 0,
            position: win.currentTime || 0,
            timestamp: now / 1000.0,
            is_playing: Boolean(win.isPlaying),
            allow_control: Boolean(win.allowCoListenerControl)
        }
    });
    win.showToast(I18n.tr("Đã mời " + name + " nghe cùng", "Invited " + name + " to listen along"), "listen");
    return true;
}

function _sameSender(f, ev) {
    if (!f) return false;
    var keys = [ev.from_id, ev.from_email].map(function(k) { return String(k || "").trim().toLowerCase(); }).filter(function(k) { return k !== ""; });
    var fk = [f.user_id, f.id, f.tag, f.user_email, f.email].map(function(k) { return String(k || "").trim().toLowerCase(); });
    for (var i = 0; i < fk.length; i++) if (fk[i] && keys.indexOf(fk[i]) !== -1) return true;
    return false;
}

function handleListenInvite(win, ev) {
    var tsSec = Number(ev.timestamp || 0);
    if (tsSec > 0 && Date.now() / 1000.0 - tsSec > INVITE_MAX_AGE_SEC) return;
    if (win.listeningAlongFriend && _sameSender(win.listeningAlongFriend, ev)) return;
    var friend = null;
    var list = win.mergedFriendsList || [];
    for (var i = 0; i < list.length; i++) {
        if (_sameSender(list[i], ev)) { friend = list[i]; break; }
    }
    var trk = (ev.data && ev.data.track) ? ev.data.track : null;
    var invite = {
        user_id: ev.from_id || (friend ? friend.user_id : "") || "",
        tag: ev.from_email || (friend ? (friend.tag || friend.user_email) : "") || "",
        user_email: ev.from_email || (friend ? (friend.user_email || friend.tag) : "") || "",
        user_name: ev.from_name || (friend ? friend.user_name : "") || I18n.tr("Bạn bè", "Friend"),
        avatar_url: ev.from_avatar || (friend ? (friend.avatar_url || friend.avatar) : "") || "",
        is_online: true,
        now_playing: trk,
        received_at: Date.now()
    };
    var busy = Boolean(win.listeningAlongFriend) || (win.activeCoListeners && win.activeCoListeners.length > 0);
    win.notificationStore.add("listen", I18n.tr(invite.user_name + " mời bạn nghe cùng", invite.user_name + " invited you to listen along"));
    listenInviteToast.showInvite(invite, busy);
}

function acceptListenInvite(win, invite) {
    if (!invite) return;
    // The track snapshot ages while the toast is open: startListeningAlong adds the elapsed time
    if (win.listeningAlongFriend && !_sameSender(win.listeningAlongFriend, { from_id: invite.user_id, from_email: invite.tag })) {
        exitListeningAlong(win);
    }
    if (win.activeCoListeners && win.activeCoListeners.length > 0) stopAllCoListening(win);
    startListeningAlong(win, invite);
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
        win.sendSocialEventFast(win.isPlaying ? "play" : "pause", senderTarget, listenSyncData(win));
        win.sendSocialEventFast("seek", senderTarget, listenSyncData(win));
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
