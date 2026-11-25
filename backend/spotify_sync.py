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


# ---------------------------------------------------------------------------
# Write-back (spec 5.6): only what changed in Nutsty after the switch went on reaches Spotify
# ---------------------------------------------------------------------------
REVERSE_THRESHOLD = 50
PUSH_CAP = 30          # tracks written per cycle; the rest waits for the next cycle
PUSH_BATCH = 10        # tracks per write call
PUSH_GAP_SEC = 3.0     # pause between write calls
_SWITCH_KEYS = ("enabled", "writeBack", "writeBackSince", "localBaseline", "writeBackAbsent")


def _importer():
    try:
        from . import spotify_importer
    except (ImportError, ValueError):
        import spotify_importer
    return spotify_importer


def reverse_match(track, client, cache, now=None):
    """Nutsty track -> Spotify id via search, scored like the importer; None below the threshold.
    A miss is cached under rev:<track key> and retried after the usual window."""
    now = time.time() if now is None else now
    vid = track.get("videoId")
    if not vid:
        return None
    sid = cache.find_by_video(vid)
    if sid:
        return sid
    key = "rev:" + pm.get_track_unique_key(track)
    if not cache.should_retry(key, now):
        return None
    title = str(track.get("title") or track.get("name") or "").strip()
    artist = str(track.get("artist") or "").strip()
    if not title:
        return None
    si = _importer()
    wanted = {"name": title, "artist": artist,
              "duration_ms": int(si.parse_duration_to_seconds(track.get("duration") or 0) * 1000)}
    best, best_score = None, None
    for c in client.search_tracks(title, artist):
        if not c.get("spotifyId"):
            continue
        score = si.calculate_track_match_score(
            wanted, {"title": c.get("name"), "artist": c.get("artist"), "durationMs": c.get("duration_ms") or 0})
        if score >= REVERSE_THRESHOLD and (best_score is None or score > best_score):
            best, best_score = c["spotifyId"], score
    if not best:
        cache.put(key, None, now=now)
        return None
    hit = cache.get(best)
    if not hit or hit.get("unmatched"):
        cache.put(best, dict(track, spotifyId=best), now=now)
    return best


def _wb_on(st, info):
    return bool(st.get("writeBack")) and bool(info.get("owned")) and not info.get("spotifyMade")


def _needs_reverse(track, keys):
    return (isinstance(track, dict) and not track.get("spotifyId") and bool(track.get("videoId"))
            and pm.get_track_unique_key(track) not in keys)


def _wb_local(pairs, base, remote, keys):
    """Spotify ids Nutsty holds, minus tracks that were already there at switch-on and Spotify
    never had: those are never pushed. `pairs` is (spotifyId, track)."""
    out = []
    for sid, track in pairs:
        if sid and (pm.get_track_unique_key(track) not in keys or sid in base or sid in remote):
            out.append(sid)
    return out


def _push_pending(rec, st, pid):
    """True when the linked playlist has Nutsty-side changes to push, so it is read even when
    Spotify's revision did not move."""
    link = rec.get("spotifyLink") or {}
    base = set(link.get("base") or [])
    keys = set((st.get("localBaseline") or {}).get(pid) or [])
    absent = set((st.get("writeBackAbsent") or {}).get(pid) or [])
    tracks = [t for t in rec.get("tracks") or [] if isinstance(t, dict)]
    if any(_needs_reverse(t, keys) for t in tracks):
        return True
    local = set(_wb_local([(t.get("spotifyId"), t) for t in tracks], base, base, keys))
    return bool(local - base) or bool(base - local - absent)


def _fetch(st, client, match, cache, now, playlists_snapshot):
    """Network phase: read everything first so a failure never leaves a half-written file.
    Returns (library, fetched {pid: (info, remote)}, liked_remote, reverse {(list, key): sid}, error_code)."""
    fetched, liked_remote, reverse = {}, None, {}
    baseline = st.get("localBaseline") or {}
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
            wb = bool(rec) and _wb_on(st, info)
            if (rec and info.get("revision") and link.get("libRevision") == info["revision"]
                    and not link.get("unmatched") and pid not in force
                    and not (wb and _push_pending(rec, st, pid))):
                continue
            remote = client.playlist_items(pid)
            if not merge.remote_is_valid(remote):
                continue
            base = set(link.get("base") or [])
            for item in remote.items:
                if item["spotifyId"] not in base:
                    match_item(item, match, cache, now)
            if wb:
                keys = set(baseline.get(pid) or [])
                for t in rec.get("tracks") or []:
                    if _needs_reverse(t, keys):
                        found = reverse_match(t, client, cache, now)
                        if found:
                            reverse[(pid, pm.get_track_unique_key(t))] = found
            fetched[pid] = (info, remote)
        if st.get("likedSelected"):
            remote = client.liked_items()
            if merge.remote_is_valid(remote):
                base = set(st.get("likedBase") or [])
                for item in remote.items:
                    if item["spotifyId"] not in base:
                        match_item(item, match, cache, now)
                if st.get("writeBack") and st.get("likedBase") is not None:
                    keys = set(baseline.get("liked") or [])
                    liked = pm._read_json(pm._liked_file(), {})
                    for v in (liked.values() if isinstance(liked, dict) else []):
                        if _needs_reverse(v, keys):
                            found = reverse_match(v, client, cache, now)
                            if found:
                                reverse[("liked", pm.get_track_unique_key(v))] = found
                liked_remote = remote
    except sw.SpotifyError as e:
        error = e.code
    return library, fetched, liked_remote, reverse, error


def _learn(cache, tracks, now):
    """A Nutsty track that already carries a Spotify id is that id's match: record it, so the id is
    not reported unmatched (and kept out of base) once write-back has put it on Spotify."""
    for t in tracks:
        sid = t.get("spotifyId") if isinstance(t, dict) else None
        if sid and t.get("videoId") and not cache.get(sid):
            cache.put(sid, t, now=now)


def _matched_map(remote, cache):
    out, unmatched = {}, set()
    for item in remote.items:
        hit = cache.get(item["spotifyId"])
        if hit and not hit.get("unmatched"):
            out[item["spotifyId"]] = dict(hit, spotifyId=item["spotifyId"])
        else:
            unmatched.add(item["spotifyId"])
    return out, unmatched


def _apply_playlist(playlists, info, remote, st, cache, now, blocked, reverse=None, jobs=None):
    pid = info["id"]
    rec = _find_linked(playlists, pid)
    if rec is not None:
        _learn(cache, rec.get("tracks") or [], now)
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
        base = link.get("base") or []
        tracks = [dict(t) if isinstance(t, dict) else t for t in rec.get("tracks") or []]
        wb = _wb_on(st, info)
        if wb:
            keys = set((st.get("localBaseline") or {}).get(pid) or [])
            for t in tracks:
                if _needs_reverse(t, keys):
                    found = (reverse or {}).get((pid, pm.get_track_unique_key(t)))
                    if found:
                        t["spotifyId"] = found
            local = _wb_local([(t.get("spotifyId"), t) for t in tracks if isinstance(t, dict)],
                              set(base), set(remote_ids), keys)
        else:
            local = [t.get("spotifyId") for t in tracks if isinstance(t, dict) and t.get("spotifyId")]
        r = merge.three_way(base, remote_ids, local, wb, unmatched)
        absent = set((st.get("writeBackAbsent") or {}).get(pid) or [])
        push_remove = [s for s in r.push_remove if s not in absent]
        force = st.get("forceApply") or []
        if (merge.mass_delete_blocked(len(base), len(r.pull_remove))
                or merge.mass_delete_blocked(len(base), len(push_remove))) and pid not in force:
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
        # Base holds only what Spotify has now; each push that lands is added afterwards (_patch_bases),
        # so a crash or a failed write leaves the change pending instead of deleting it next cycle.
        new_base = [s for s in merge._dedupe(remote_ids) if s not in unmatched]
        if wb and (r.push_add or push_remove) and jobs is not None:
            jobs.append({"list": pid, "add": list(r.push_add), "remove": push_remove})
    rec["trackCount"] = len(rec["tracks"])
    rec["spotifyLink"] = {"id": pid, "owned": bool(info.get("owned")), "spotifyMade": bool(info.get("spotifyMade")),
                          "base": new_base, "revision": remote.revision or "",
                          "libRevision": info.get("revision") or "",
                          "syncedAt": now, "unmatched": len(unmatched)}
    return True


def _apply_liked(remote, st, cache, now, blocked, reverse=None, jobs=None):
    """Merge Spotify liked songs into Nutsty liked songs. Returns True when the file changed."""
    liked = pm._read_json(pm._liked_file(), {})
    if not isinstance(liked, dict):
        liked = {}
    _learn(cache, liked.values(), now)
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
        wb = bool(st.get("writeBack"))
        local = list(local_of)
        if wb:
            keys = set((st.get("localBaseline") or {}).get("liked") or [])
            for key, v in liked.items():
                if _needs_reverse(v, keys):
                    found = (reverse or {}).get(("liked", pm.get_track_unique_key(v)))
                    if found and local_of.get(found, key) == key:
                        v["spotifyId"] = found
                        local_of[found] = key
                        changed = True
            local = _wb_local([(sid, liked[key]) for sid, key in local_of.items()],
                              set(base), set(remote_ids), keys)
        r = merge.three_way(base, remote_ids, local, wb, unmatched)
        absent = set((st.get("writeBackAbsent") or {}).get("liked") or [])
        push_remove = [s for s in r.push_remove if s not in absent]
        force = st.get("forceApply") or []
        if (merge.mass_delete_blocked(len(base), len(r.pull_remove))
                or merge.mass_delete_blocked(len(base), len(push_remove))) and "liked" not in force:
            blocked.append("liked")
            return False
        if "liked" in force:
            st["forceApply"] = [x for x in force if x != "liked"]
        pull_add, pull_remove = r.pull_add, r.pull_remove
        new_base = [s for s in merge._dedupe(remote_ids) if s not in unmatched]
        if wb and (r.push_add or push_remove) and jobs is not None:
            jobs.append({"list": "liked", "add": list(r.push_add), "remove": push_remove})
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


def _push(client, jobs, sleep):
    """Send the queued writes slowly: fresh read first (skip what Spotify already has, find uids),
    at most PUSH_CAP tracks, PUSH_GAP_SEC between calls. Stops at the first error or when the switch
    is turned off. Returns ({list: (added, removed)}, error_code)."""
    done, budget, calls = {}, PUSH_CAP, 0
    for job in jobs:
        if budget <= 0:
            break
        lid = job["list"]
        try:
            fresh = client.liked_items() if lid == "liked" else client.playlist_items(lid)
        except sw.SpotifyError as e:
            return done, e.code
        if not merge.remote_is_valid(fresh):
            continue
        uids = {}
        for item in fresh.items:
            uids.setdefault(item["spotifyId"], []).append(item.get("uid"))
        added = [s for s in job["add"] if s in uids]
        removed = [s for s in job["remove"] if s not in uids]
        done[lid] = (added, removed)
        for kind, ids in (("add", [s for s in job["add"] if s not in uids]),
                          ("remove", [s for s in job["remove"] if s in uids])):
            while ids and budget > 0:
                batch, ids = ids[:min(PUSH_BATCH, budget)], ids[min(PUSH_BATCH, budget):]
                if calls:
                    sleep(PUSH_GAP_SEC)
                if not sstate.load_state().get("writeBack"):
                    return done, ""
                calls += 1
                uris = [f"spotify:track:{s}" for s in batch]
                try:
                    if lid == "liked":
                        (client.add_to_library if kind == "add" else client.remove_from_library)(uris)
                    elif kind == "add":
                        client.add_to_playlist(lid, uris)
                    else:
                        client.remove_from_playlist(lid, [u for s in batch for u in uids[s] if u])
                except sw.SpotifyError as e:
                    return done, e.code
                budget -= len(batch)
                (added if kind == "add" else removed).extend(batch)
    return done, ""


def _patch_bases(st, done):
    """Fold the writes that landed into each base (liked base lives in state, saved by sync_once)."""
    def patch(base, added, removed):
        gone = set(removed)
        out = [s for s in base or [] if s not in gone]
        return out + [s for s in added if s not in set(out)]

    if not any(a or r for a, r in done.values()):
        return
    with pm.locked():
        playlists = pm.load_playlists()
        dirty = False
        for lid, (added, removed) in done.items():
            if not added and not removed:
                continue
            if lid == "liked":
                st["likedBase"] = patch(st.get("likedBase"), added, removed)
                continue
            rec = _find_linked(playlists, lid)
            if rec and rec.get("spotifyLink"):
                rec["spotifyLink"]["base"] = patch(rec["spotifyLink"].get("base"), added, removed)
                dirty = True
        if dirty:
            pm.save_playlists(playlists)


def _cycle(st, client, match, cache, now, sleep=time.sleep):
    snapshot = pm.load_playlists()
    try:
        _library, fetched, liked_remote, reverse, error = _fetch(st, client, match, cache, now, snapshot)
    except sw.SpotifyError as e:
        return _result(False, e.code)
    blocked, changed, jobs = [], {"playlists": False, "liked": False}, []
    unmatched = 0
    with pm.locked():
        playlists = pm.load_playlists()
        before = len(playlists)
        playlists = migrate_legacy_imports(playlists, {pid: r for pid, (_i, r) in fetched.items()}, match, cache, now)
        for pid, (info, remote) in fetched.items():
            if _apply_playlist(playlists, info, remote, st, cache, now, blocked, reverse, jobs):
                changed["playlists"] = True
            unmatched += _matched_map(remote, cache)[1].__len__()
        if changed["playlists"] or len(playlists) != before:
            pm.save_playlists(playlists)
        if liked_remote is not None:
            changed["liked"] = _apply_liked(liked_remote, st, cache, now, blocked, reverse, jobs)
            unmatched += len(_matched_map(liked_remote, cache)[1])
    pushed = 0
    if jobs and not error:
        done, error = _push(client, jobs, sleep)
        _patch_bases(st, done)
        pushed = sum(len(a) + len(r) for a, r in done.values())
    return _result(not error, error, changed=changed, blocked=blocked, unmatched=unmatched, pushed=pushed)


def _keep_switches(st):
    """The user may flip a switch while a run is in flight; the run must not write the old value back."""
    disk = sstate.load_state()
    for k in _SWITCH_KEYS:
        st[k] = disk[k]


def sync_once(profile="", client=None, matcher=None, now=None, sleep=None):
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
                res = _cycle(st, client, matcher or _default_matcher(), cache, now, sleep or time.sleep)
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
            _keep_switches(st)
            sstate.save_state(st)
            return res
    finally:
        _RUN_LOCK.release()


# ---------------------------------------------------------------------------
# Backlog: "push earlier likes" (spec 5.6) - likes Nutsty held before write-back went on
# ---------------------------------------------------------------------------
BACKLOG_ROUND = PUSH_CAP      # tracks per round, then a longer rest, so a big library goes up slowly
BACKLOG_REST_SEC = 60.0
_BACKLOG_CANCEL = threading.Event()
_BACKLOG_ACTIVE = set()


def _backlog_progress(**kw):
    st = sstate.load_state()
    st["backlog"] = {"done": 0, "total": 0, "unmatched": 0, **(st.get("backlog") or {}), **kw}
    sstate.save_state(st)


def _backlog_commit(pairs):
    """Record pushed (key, sid) pairs: liked entries get their id, base gains it, baseline loses the key."""
    keys = {k for k, _s in pairs}
    with pm.locked():
        liked = pm._read_json(pm._liked_file(), {})
        if isinstance(liked, dict):
            dirty = False
            for key, sid in pairs:
                for k, v in liked.items():
                    if isinstance(v, dict) and pm.get_track_unique_key(v) == key and v.get("spotifyId") != sid:
                        v["spotifyId"] = sid
                        dirty = True
            if dirty:
                pm._write_json(pm._liked_file(), liked)
        st = sstate.load_state()
        base = list(st.get("likedBase") or [])
        base += [sid for _k, sid in pairs if sid not in set(base)]
        st["likedBase"] = base
        lb = dict(st.get("localBaseline") or {})
        lb["liked"] = [k for k in lb.get("liked") or [] if k not in keys]
        st["localBaseline"] = lb
        sstate.save_state(st)


def _backlog_run(client, sleep, now):
    cache = sstate.MatchCache()
    try:
        fresh = client.liked_items()
        if not merge.remote_is_valid(fresh):
            raise sw.SpotifyNetworkError("liked songs read incomplete")
        have = {i["spotifyId"] for i in fresh.items}
        st = sstate.load_state()
        keys = set((st.get("localBaseline") or {}).get("liked") or [])
        liked = pm._read_json(pm._liked_file(), {})
        queue, already, unmatched = [], [], 0
        for v in (liked.values() if isinstance(liked, dict) else []):
            if not isinstance(v, dict):
                continue
            key = pm.get_track_unique_key(v)
            if key not in keys:
                continue
            sid = v.get("spotifyId") or reverse_match(v, client, cache, now)
            if not sid:
                unmatched += 1
            elif sid in have:
                already.append((key, sid))
            elif sid not in {q for _k, q in queue}:
                queue.append((key, sid))
        if already:
            _backlog_commit(already)
        _backlog_progress(running=True, done=0, total=len(queue), unmatched=unmatched, error="")
        done, calls, in_round = 0, 0, 0
        while queue:
            if in_round >= BACKLOG_ROUND:
                sleep(BACKLOG_REST_SEC)
                in_round = 0
            elif calls:
                sleep(PUSH_GAP_SEC)
            if _BACKLOG_CANCEL.is_set() or not sstate.load_state().get("writeBack"):
                break
            batch, queue = queue[:PUSH_BATCH], queue[PUSH_BATCH:]
            client.add_to_library([f"spotify:track:{sid}" for _k, sid in batch])
            calls += 1
            in_round += len(batch)
            done += len(batch)
            _backlog_commit(batch)
            _backlog_progress(done=done)
        _backlog_progress(running=False)
    except sw.SpotifyError as e:
        _backlog_progress(running=False, error=e.code)
    finally:
        if cache.dirty:
            cache.save()


def start_backlog(profile="", client=None, sleep=None, now=None, background=True):
    """Push likes that were in Nutsty before write-back went on. Holds the sync lock while it runs,
    so a sync cycle never interleaves with it; cancel_backlog stops it between writes."""
    with pm.profile_scope(profile):
        if not sstate.load_state().get("writeBack"):
            return dict(status(profile), success=False, error="write_back_off")
    if not _RUN_LOCK.acquire(blocking=False):
        return dict(status(profile), success=False, error="busy")
    _BACKLOG_CANCEL.clear()
    _BACKLOG_ACTIVE.add(profile)

    def work():
        try:
            with pm.profile_scope(profile):
                try:
                    c = client or _default_client()
                except sw.SpotifyError as e:
                    _backlog_progress(running=False, error=e.code)
                    return
                _backlog_run(c, sleep or time.sleep, time.time() if now is None else now)
        except Exception as e:  # never let the backlog take the daemon down
            sys.stderr.write(f"[spotify_sync] backlog failed: {e}\n")
        finally:
            _BACKLOG_ACTIVE.discard(profile)
            _RUN_LOCK.release()

    if background:
        threading.Thread(target=work, name="spotify-backlog", daemon=True).start()
    else:
        work()
    return dict(status(profile), success=True)


def cancel_backlog(profile=""):
    _BACKLOG_CANCEL.set()
    return dict(status(profile), success=True)


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


def set_write_back(profile, on, now=None):
    """On: note what Nutsty already holds, so only later changes are pushed (spec 5.6). Off: forget it."""
    with pm.profile_scope(profile):
        st = sstate.load_state()
        if not on:
            st.update(writeBack=False, writeBackSince=0.0, localBaseline={}, writeBackAbsent={})
            sstate.save_state(st)
            return status(profile)
        cache = sstate.MatchCache()
        baseline, absent = {}, {}
        for pl in pm.load_playlists():
            link = (pl.get("spotifyLink") or {}) if isinstance(pl, dict) else {}
            if not link.get("id") or not link.get("owned") or link.get("spotifyMade"):
                continue
            tracks = [t for t in pl.get("tracks") or [] if isinstance(t, dict)]
            baseline[link["id"]] = [pm.get_track_unique_key(t) for t in tracks]
            have = {t.get("spotifyId") for t in tracks}
            absent[link["id"]] = [s for s in link.get("base") or [] if s not in have]
        liked = pm._read_json(pm._liked_file(), {})
        liked = liked if isinstance(liked, dict) else {}
        baseline["liked"] = [pm.get_track_unique_key(v) for v in liked.values() if isinstance(v, dict)]
        have = {v.get("spotifyId") or cache.find_by_video(v.get("videoId") or k)
                for k, v in liked.items() if isinstance(v, dict)}
        absent["liked"] = [s for s in st.get("likedBase") or [] if s not in have]
        st.update(writeBack=True, writeBackSince=time.time() if now is None else now,
                  localBaseline=baseline, writeBackAbsent=absent)
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
        backlog = {"done": 0, "total": 0, "unmatched": 0, "error": "", **(st.get("backlog") or {})}
        backlog["running"] = profile in _BACKLOG_ACTIVE
        return {k: st.get(k) for k in ("enabled", "selectionConfirmed", "likedSelected", "writeBack",
                                       "lastSync", "lastError", "blocked", "unmatchedCount")} | {
            "backlog": backlog,
            "selectedCount": len(st.get("selected") or []), "running": _RUN_LOCK.locked(),
            "blockedNames": _blocked_names(st.get("blocked") or [])}


def _blocked_names(blocked):
    """Playlist title per blocked Spotify id, "" for Liked Songs or a list Nutsty no longer has."""
    if not blocked:
        return {}
    titles = {p.get("id"): p.get("title") or "" for p in pm.load_playlists() if isinstance(p, dict)}
    return {pid: ("" if pid == "liked" else titles.get(linked_id(pid), "")) for pid in blocked}


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
        elif op == "set_write_back":
            res = set_write_back(profile, bool(body.get("on")))
        elif op == "backlog_start":
            res = start_backlog(profile)
        elif op == "backlog_cancel":
            res = cancel_backlog(profile)
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
