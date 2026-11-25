#!/usr/bin/env python3
"""
Two-way Spotify sync (docs/superpowers/specs/2026-11-25-spotify-two-way-sync-design.md).

Pull: the user's chosen Spotify playlists and liked songs flow into Nutsty, three-way merged
so a song removed in Nutsty is never re-added and an incomplete read never deletes anything.
Linked playlists keep a fixed id `custom_pl_spotify_{pid}` and a `spotifyLink` record that
account_sync carries to the user's other devices. The switch and liked-songs base are per device.
"""
import time

try:
    from . import playlist_manager as pm
except (ImportError, ValueError):
    import playlist_manager as pm

LINK_PREFIX = "custom_pl_spotify_"


def linked_id(pid):
    return f"{LINK_PREFIX}{pid}"


def match_item(item, match, cache, now=None):
    """Spotify item -> Nutsty track (with spotifyId) via the cache, calling `match` at most
    once per retry window. Returns None while the track stays unmatched."""
    now = time.time() if now is None else now
    sid = item.get("spotifyId")
    if not sid:
        return None
    hit = cache.get(sid)
    if hit and not hit.get("unmatched"):
        return dict(hit, spotifyId=sid)
    if not cache.should_retry(sid, now):
        return None
    try:
        found = match(item)
    except Exception:
        found = None
    if found and found.get("videoId"):
        found = dict(found, spotifyId=sid)
        cache.put(sid, found, now=now)
        return dict(found)
    cache.put(sid, None, now=now)
    return None


def migrate_legacy_imports(playlists, remote_by_pid, match, cache, now=None):
    """Turn the newest one-shot import of each Spotify playlist into a linked playlist (spec 5.1).
    Older duplicates stay as they are. Already linked pids and pids without a remote are skipped."""
    now = time.time() if now is None else now
    linked = {p.get("id") for p in playlists if isinstance(p, dict)}
    newest = {}
    for idx, pl in enumerate(playlists):
        if not isinstance(pl, dict) or pl.get("source") != "spotify_import" or pl.get("spotifyLink"):
            continue
        pid = pl.get("spotifyId")
        if not pid or pid not in remote_by_pid or linked_id(pid) in linked:
            continue
        if pid not in newest or (pl.get("createdAt") or 0) > (playlists[newest[pid]].get("createdAt") or 0):
            newest[pid] = idx

    for pid, idx in newest.items():
        pl = playlists[idx]
        remote = remote_by_pid[pid]
        tracks = list(pl.get("tracks") or [])
        by_video = {t.get("videoId"): t for t in tracks if isinstance(t, dict) and t.get("videoId")}
        base = []
        for item in remote.items:
            m = match_item(item, match, cache, now)
            if not m:
                continue
            base.append(item["spotifyId"])
            existing = by_video.get(m["videoId"])
            if existing is not None:
                existing["spotifyId"] = item["spotifyId"]
            else:
                tracks.append(m)
                by_video[m["videoId"]] = m
        new_id = linked_id(pid)
        pl.update({
            "id": new_id, "playlistId": new_id, "tracks": tracks, "trackCount": len(tracks),
            "spotifyLink": {"id": pid, "owned": False, "spotifyMade": False, "base": base,
                            "revision": remote.revision or "", "syncedAt": now, "unmatched": 0},
        })
    return playlists


# ---------------------------------------------------------------------------
# Pull orchestration (spec 5.3-5.5, 5.7, 5.8)
# ---------------------------------------------------------------------------
import sys
import threading

try:
    from . import spotify_sync_merge as merge
    from . import spotify_sync_state as sstate
    from . import spotify_web as sw
except (ImportError, ValueError):
    import spotify_sync_merge as merge
    import spotify_sync_state as sstate
    import spotify_web as sw

_RUN_LOCK = threading.Lock()


def _result(success, error="", **kw):
    out = {"success": success, "error": error, "changed": {"playlists": False, "liked": False},
           "blocked": [], "unmatched": 0}
    out.update(kw)
    return out


def _default_client():
    try:
        from . import lyrics_helper
    except (ImportError, ValueError):
        import lyrics_helper
    spdc = lyrics_helper.get_spotify_spdc()
    if not spdc:
        raise sw.SpotifyAuthError("no Spotify cookie", code="no_cookie")
    return sw.SpotifyWebClient(spdc)


def _default_matcher():
    try:
        from . import spotify_importer
    except (ImportError, ValueError):
        import spotify_importer
    return spotify_importer.match_spotify_track_to_ytmusic


def _find_linked(playlists, pid):
    lid = linked_id(pid)
    return next((p for p in playlists if isinstance(p, dict) and p.get("id") == lid), None)


def _liked_entry(track, now):
    vid = track["videoId"]
    img = track.get("image") or f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg"
    title = track.get("title") or ""
    return {"videoId": vid, "title": title, "name": title, "artist": track.get("artist") or "",
            "image": img, "cover": img, "artUrl": img, "path": track.get("path") or f"ytdl://{vid}",
            "duration": track.get("duration") or "", "timestamp": int(now * 1000),
            "spotifyId": track.get("spotifyId", "")}


def _fetch(st, client, match, cache, now, playlists_snapshot):
    """Network phase: read everything first so a failure never leaves a half-written file.
    Returns (library, fetched {pid: (info, remote)}, liked_remote, error_code)."""
    fetched, liked_remote = {}, None
    library = client.library_playlists()
    seen = set(st.get("seen") or [])
    selected = list(st.get("selected") or [])
    for info in library:
        if info["id"] not in seen:
            seen.add(info["id"])
            if info.get("owned") and not info.get("spotifyMade") and info["id"] not in selected:
                selected.append(info["id"])
    st["seen"], st["selected"] = sorted(seen), selected

    force = set(st.get("forceApply") or [])
    error = ""
    try:
        for info in library:
            pid = info["id"]
            if pid not in selected:
                continue
            rec = _find_linked(playlists_snapshot, pid)
            link = (rec or {}).get("spotifyLink") or {}
            if (rec and info.get("revision") and link.get("libRevision") == info["revision"]
                    and not link.get("unmatched") and pid not in force):
                continue
            remote = client.playlist_items(pid)
            if not merge.remote_is_valid(remote):
                continue
            base = set(link.get("base") or [])
            for item in remote.items:
                if item["spotifyId"] not in base:
                    match_item(item, match, cache, now)
            fetched[pid] = (info, remote)
        if st.get("likedSelected"):
            remote = client.liked_items()
            if merge.remote_is_valid(remote):
                base = set(st.get("likedBase") or [])
                for item in remote.items:
                    if item["spotifyId"] not in base:
                        match_item(item, match, cache, now)
                liked_remote = remote
    except sw.SpotifyError as e:
        error = e.code
    return library, fetched, liked_remote, error


def _matched_map(remote, cache):
    out, unmatched = {}, set()
    for item in remote.items:
        hit = cache.get(item["spotifyId"])
        if hit and not hit.get("unmatched"):
            out[item["spotifyId"]] = dict(hit, spotifyId=item["spotifyId"])
        else:
            unmatched.add(item["spotifyId"])
    return out, unmatched


def _apply_playlist(playlists, info, remote, st, cache, now, blocked):
    pid = info["id"]
    rec = _find_linked(playlists, pid)
    matched, unmatched = _matched_map(remote, cache)
    remote_ids = [i["spotifyId"] for i in remote.items]
    ordered = [dict(matched[s]) for s in remote_ids if s in matched]
    if rec is None:
        lid = linked_id(pid)
        cover = info.get("image") or (ordered[0].get("image") if ordered else "")
        rec = {"id": lid, "playlistId": lid, "title": info.get("title") or "Spotify", "name": info.get("title") or "Spotify",
               "description": "", "image": cover, "customCover": cover, "tracks": ordered,
               "source": "spotify_sync", "isCustom": True, "isLocal": True, "type": "custom",
               "createdAt": int(now * 1000)}
        playlists.insert(0, rec)
        new_base = [s for s in remote_ids if s in matched]
    elif info.get("spotifyMade"):
        rec["tracks"] = ordered
        new_base = [s for s in remote_ids if s in matched]
    else:
        link = rec.get("spotifyLink") or {}
        tracks = list(rec.get("tracks") or [])
        local = [t.get("spotifyId") for t in tracks if isinstance(t, dict) and t.get("spotifyId")]
        r = merge.three_way(link.get("base") or [], remote_ids, local, False, unmatched)
        force = st.get("forceApply") or []
        if merge.mass_delete_blocked(len(link.get("base") or []), len(r.pull_remove)) and pid not in force:
            blocked.append(pid)
            return False
        if pid in force:
            st["forceApply"] = [x for x in force if x != pid]
        gone = set(r.pull_remove)
        tracks = [t for t in tracks if not (isinstance(t, dict) and t.get("spotifyId") in gone)]
        by_video = {t.get("videoId"): t for t in tracks if isinstance(t, dict) and t.get("videoId")}
        for sid in r.pull_add:
            m = matched.get(sid)
            if not m:
                continue
            if m["videoId"] in by_video:
                by_video[m["videoId"]]["spotifyId"] = sid
            else:
                tracks.append(dict(m))
                by_video[m["videoId"]] = tracks[-1]
        rec["tracks"] = tracks
        new_base = r.new_base
    rec["trackCount"] = len(rec["tracks"])
    rec["spotifyLink"] = {"id": pid, "owned": bool(info.get("owned")), "spotifyMade": bool(info.get("spotifyMade")),
                          "base": new_base, "revision": remote.revision or "",
                          "libRevision": info.get("revision") or "",
                          "syncedAt": now, "unmatched": len(unmatched)}
    return True


def _apply_liked(remote, st, cache, now, blocked):
    """Merge Spotify liked songs into Nutsty liked songs. Returns True when the file changed."""
    liked = pm._read_json(pm._liked_file(), {})
    if not isinstance(liked, dict):
        liked = {}
    matched, unmatched = _matched_map(remote, cache)
    remote_ids = [i["spotifyId"] for i in remote.items]
    local_of = {}
    for key, v in liked.items():
        if not isinstance(v, dict):
            continue
        sid = v.get("spotifyId") or cache.find_by_video(v.get("videoId") or key)
        if sid:
            local_of[sid] = key
    base = st.get("likedBase")
    changed = False
    if base is None:
        pull_add = [s for s in remote_ids if s not in local_of]
        pull_remove, new_base = [], [s for s in remote_ids if s not in unmatched]
    else:
        r = merge.three_way(base, remote_ids, list(local_of), False, unmatched)
        force = st.get("forceApply") or []
        if merge.mass_delete_blocked(len(base), len(r.pull_remove)) and "liked" not in force:
            blocked.append("liked")
            return False
        if "liked" in force:
            st["forceApply"] = [x for x in force if x != "liked"]
        pull_add, pull_remove, new_base = r.pull_add, r.pull_remove, r.new_base
    for sid in pull_remove:
        key = local_of.get(sid)
        if key in liked:
            del liked[key]
            changed = True
    for sid, key in local_of.items():
        if sid in matched and not liked.get(key, {}).get("spotifyId"):
            liked[key]["spotifyId"] = sid
            changed = True
    for sid in pull_add:
        m = matched.get(sid)
        if not m:
            continue
        vid = m["videoId"]
        if vid in liked:
            if liked[vid].get("spotifyId") != sid:
                liked[vid]["spotifyId"] = sid
                changed = True
            continue
        liked[vid] = _liked_entry(m, now)
        changed = True
    st["likedBase"] = new_base
    if changed:
        pm._write_json(pm._liked_file(), liked)
    return changed


def _cycle(st, client, match, cache, now):
    snapshot = pm.load_playlists()
    try:
        _library, fetched, liked_remote, error = _fetch(st, client, match, cache, now, snapshot)
    except sw.SpotifyError as e:
        return _result(False, e.code)
    blocked, changed = [], {"playlists": False, "liked": False}
    unmatched = 0
    with pm.locked():
        playlists = pm.load_playlists()
        before = len(playlists)
        playlists = migrate_legacy_imports(playlists, {pid: r for pid, (_i, r) in fetched.items()}, match, cache, now)
        for pid, (info, remote) in fetched.items():
            if _apply_playlist(playlists, info, remote, st, cache, now, blocked):
                changed["playlists"] = True
            unmatched += _matched_map(remote, cache)[1].__len__()
        if changed["playlists"] or len(playlists) != before:
            pm.save_playlists(playlists)
        if liked_remote is not None:
            changed["liked"] = _apply_liked(liked_remote, st, cache, now, blocked)
            unmatched += len(_matched_map(liked_remote, cache)[1])
    return _result(not error, error, changed=changed, blocked=blocked, unmatched=unmatched)


def sync_once(profile="", client=None, matcher=None, now=None):
    if not _RUN_LOCK.acquire(blocking=False):
        return _result(False, "busy")
    try:
        with pm.profile_scope(profile):
            st = sstate.load_state()
            if not st.get("enabled") or not st.get("selectionConfirmed"):
                return _result(False, "disabled")
            now = time.time() if now is None else now
            cache = sstate.MatchCache()
            try:
                client = client or _default_client()
                res = _cycle(st, client, matcher or _default_matcher(), cache, now)
            except sw.SpotifyError as e:
                res = _result(False, e.code)
            except Exception as e:  # never let a sync bug take the daemon down
                sys.stderr.write(f"[spotify_sync] cycle failed: {e}\n")
                res = _result(False, "internal")
            if cache.dirty:
                cache.save()
            st["lastError"] = res["error"]
            if res["success"] or res["error"] not in ("disabled", "busy"):
                st["lastSync"] = now if res["success"] else st.get("lastSync", 0)
            if res["error"] in ("", "rate_limited", "network") or res["success"]:
                st["blocked"] = res["blocked"]
                st["unmatchedCount"] = res["unmatched"]
            sstate.save_state(st)
            return res
    finally:
        _RUN_LOCK.release()


def list_choices(profile="", client=None):
    with pm.profile_scope(profile):
        st = sstate.load_state()
        client = client or _default_client()
        library = client.library_playlists()
        chosen = set(st.get("selected") or [])
        out = []
        for info in library:
            if st.get("selectionConfirmed"):
                sel = info["id"] in chosen
            else:
                sel = bool(info.get("owned")) and not info.get("spotifyMade")
            out.append(dict(info, selected=sel))
        st["seen"] = sorted(set(st.get("seen") or []) | {p["id"] for p in library})
        sstate.save_state(st)
        return {"playlists": out, "liked": bool(st.get("likedSelected"))}


def set_selection(profile, ids, liked):
    with pm.profile_scope(profile):
        st = sstate.load_state()
        st.update(selected=[str(i) for i in ids], likedSelected=bool(liked), selectionConfirmed=True)
        st["seen"] = sorted(set(st.get("seen") or []) | set(st["selected"]))
        sstate.save_state(st)
        return status(profile)


def set_enabled(profile, enabled):
    with pm.profile_scope(profile):
        st = sstate.load_state()
        st["enabled"] = bool(enabled)
        sstate.save_state(st)
        return status(profile)


def force_apply(profile, pid):
    with pm.profile_scope(profile):
        st = sstate.load_state()
        if pid not in st["forceApply"]:
            st["forceApply"].append(pid)
        sstate.save_state(st)
        return status(profile)


def status(profile=""):
    with pm.profile_scope(profile):
        st = sstate.load_state()
        return {k: st.get(k) for k in ("enabled", "selectionConfirmed", "likedSelected", "writeBack",
                                       "lastSync", "lastError", "blocked", "unmatchedCount", "backlog")} | {
            "selectedCount": len(st.get("selected") or []), "running": _RUN_LOCK.locked()}


# ---------------------------------------------------------------------------
# HTTP: POST /api/spotify/sync/<op>  (route_dispatcher on Linux, auth_server fallback on Windows)
# ---------------------------------------------------------------------------
_last_run = {}


def _run_background(profile):
    def worker():
        try:
            _last_run[profile] = sync_once(profile)
        except Exception as e:
            sys.stderr.write(f"[spotify_sync] background run failed: {e}\n")
    threading.Thread(target=worker, name="spotify-sync", daemon=True).start()


def handle_http_path(handler, path, body):
    op = path.rstrip("/").rsplit("/", 1)[-1]
    body = body if isinstance(body, dict) else {}
    profile = str(body.get("profile") or "")
    try:
        if op == "run":
            if _RUN_LOCK.locked():
                res = {"success": False, "error": "busy"}
            else:
                _run_background(profile)
                res = {"success": True, "started": True}
        elif op == "status":
            res = dict(status(profile), last=_last_run.get(profile))
        elif op == "choices":
            res = dict(list_choices(profile), success=True)
        elif op == "set_selection":
            res = set_selection(profile, body.get("ids") or [], body.get("liked", True))
        elif op == "set_enabled":
            res = set_enabled(profile, body.get("enabled"))
        elif op == "force_apply":
            res = force_apply(profile, str(body.get("id") or ""))
        else:
            handler._send_json({"success": False, "error": f"unknown_op: {op}"}, 404)
            return
    except sw.SpotifyError as e:
        res = {"success": False, "error": e.code}
    except Exception as e:
        sys.stderr.write(f"[spotify_sync] {op} failed: {e}\n")
        res = {"success": False, "error": "internal"}
    handler._send_json(res, 200)
