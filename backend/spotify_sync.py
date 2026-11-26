#!/usr/bin/env python3
"""
Two-way Spotify sync (docs/superpowers/specs/2026-11-25-spotify-two-way-sync-design.md).

Pull: the user's chosen Spotify playlists and liked songs flow into Nutsty, three-way merged
so a song removed in Nutsty is never re-added and an incomplete read never deletes anything.
Linked playlists keep a fixed id `custom_pl_spotify_{pid}` and a `spotifyLink` record that
account_sync carries to the user's other devices. The switch and liked-songs base are per device.
"""
import re
import time

try:
    from . import playlist_manager as pm
except (ImportError, ValueError):
    import playlist_manager as pm

LINK_PREFIX = "custom_pl_spotify_"


def linked_id(pid):
    return f"{LINK_PREFIX}{pid}"


def track_ids(track):
    """Every Spotify id a Nutsty track stands for. Two Spotify versions of one song (a remaster)
    can match the same YouTube video: the first is `spotifyId`, the others `spotifyIds`."""
    if not isinstance(track, dict):
        return []
    out = [track["spotifyId"]] if track.get("spotifyId") else []
    return out + [s for s in track.get("spotifyIds") or [] if s and s not in out]


def add_track_id(track, sid):
    """Record that `track` also stands for `sid`, never replacing an id it already has."""
    if not sid or sid in track_ids(track):
        return False
    if not track.get("spotifyId"):
        track["spotifyId"] = sid
    else:
        track["spotifyIds"] = [s for s in track_ids(track)[1:]] + [sid]
    return True


def drop_track_ids(track, gone):
    """Forget the ids Spotify removed. Returns False when the track stands for nothing left."""
    ids = track_ids(track)
    keep = [s for s in ids if s not in gone]
    if len(keep) == len(ids):
        return True
    if not keep:
        return False
    track["spotifyId"] = keep[0]
    if keep[1:]:
        track["spotifyIds"] = keep[1:]
    else:
        track.pop("spotifyIds", None)
    return True


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
        return None  # offline or search failed: try again next cycle, do not cache "unmatched"
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
                add_track_id(existing, item["spotifyId"])
            else:
                tracks.append(m)
                by_video[m["videoId"]] = m
        new_id = linked_id(pid)
        pl.update({
            "id": new_id, "playlistId": new_id, "tracks": tracks, "trackCount": len(tracks),
            # its name came from Spotify at import: agreed, so a later Spotify rename is pulled, not overwritten
            "spotifyLink": {"id": pid, "owned": False, "spotifyMade": False, "base": base,
                            "revision": remote.revision or "", "syncedAt": now, "unmatched": 0,
                            "title": str(pl.get("title") or pl.get("name") or "").strip()},
        })
    return playlists


# ---------------------------------------------------------------------------
# Pull orchestration (spec 5.3-5.5, 5.7, 5.8)
# ---------------------------------------------------------------------------
import copy
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
    # the profile this request runs for, not the daemon's own (one daemon serves every profile window)
    spdc = lyrics_helper.get_spotify_spdc(suffix=pm._ACTIVE_SUFFIX.get())
    if not spdc:
        raise sw.SpotifyAuthError("no Spotify cookie", code="no_cookie")
    return sw.SpotifyWebClient(spdc)


def _default_matcher():
    try:
        from . import spotify_importer
    except (ImportError, ValueError):
        import spotify_importer
    return lambda item: spotify_importer.match_spotify_track_to_ytmusic(item, strict=True)


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
            "spotifyId": track.get("spotifyId", ""), "spotifySynced": True}


# ---------------------------------------------------------------------------
# Write-back (spec 5.6): only what changed in Nutsty after the switch went on reaches Spotify
# ---------------------------------------------------------------------------
REVERSE_THRESHOLD = 50
PUSH_CAP = 30          # tracks written per cycle; the rest waits for the next cycle
PUSH_BATCH = 10        # tracks per write call
PUSH_GAP_SEC = 3.0     # pause between write calls
# Keys a route may change while a run is in flight: the user's change wins over the run's copy
_USER_KEYS = ("enabled", "writeBack", "writeBackSince", "localBaseline", "writeBackAbsent",
              "selected", "likedSelected", "selectionConfirmed", "linked")


def _importer():
    try:
        from . import spotify_importer
    except (ImportError, ValueError):
        import spotify_importer
    return spotify_importer


def _artist_agrees(candidate, track):
    """One of the Spotify artists is named in the Nutsty track's artist or title. YouTube titles are
    long ("05 (Không Phai) | @tangduytan x T.R.I x Phong Max"), so a short Spotify title ("PHONG")
    alone matches by accident; the artist is what tells them apart."""
    def words(text):  # every word, one letter too: "T.R.I" is t, r, i
        return set(re.findall(r"\w+", str(text).lower()))

    have = words(f"{track.get('artist') or ''} {track.get('title') or track.get('name') or ''}")
    for name in str(candidate.get("artist") or "").split(","):
        toks = words(name)
        if toks and toks <= have:
            return True
    return False


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
        if not c.get("spotifyId") or not _artist_agrees(c, track):
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


def _absent_ids(tracks, base):
    """Base ids Nutsty no longer holds: removed before write-back noted them, so never pushed."""
    have = {sid for t in tracks for sid in track_ids(t)}
    return [s for s in base or [] if s not in have]


def _note_baseline(st, pid, tracks, base):
    tracks = [t for t in tracks if isinstance(t, dict)]
    st["localBaseline"] = dict(st.get("localBaseline") or {}, **{pid: [pm.get_track_unique_key(t) for t in tracks]})
    st["writeBackAbsent"] = dict(st.get("writeBackAbsent") or {}, **{pid: _absent_ids(tracks, base)})


def _editable(info):
    """The user may change this list on Spotify: owns it, or is a collaborator."""
    return bool(info.get("editable", info.get("owned"))) and not info.get("spotifyMade")


def _wb_on(st, info):
    return bool(st.get("writeBack")) and _editable(info)


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
    local = set(_wb_local([(sid, t) for t in tracks for sid in track_ids(t)], base, base, keys))
    return bool(local - base) or bool(base - local - absent)


def _library(client):
    """Playlists, then saved albums. Albums are an extra: if Spotify changes their query, the
    playlists still sync."""
    return _library_read(client)[0]


def _library_read(client):
    """(library, complete): complete is False when the albums could not be read, so a missing album
    there says nothing about whether the user removed it."""
    library = client.library_playlists()
    try:
        albums = client.library_albums()
    except sw.SpotifyError as e:
        if e.code not in _SKIP_ONE + ("query_changed",):
            raise
        sys.stderr.write(f"[spotify_sync] saved albums skipped: {e.code}\n")
        return library, False
    return library + albums, True


def _fetch(st, client, match, cache, now, playlists_snapshot):
    """Network phase: read everything first so a failure never leaves a half-written file.
    Returns (library, fetched {pid: (info, remote)}, liked_remote, reverse {(list, key): sid}, error_code)."""
    fetched, liked_remote, reverse = {}, None, {}
    baseline = st.get("localBaseline") or {}
    library, complete = _library_read(client)
    seen = set(st.get("seen") or [])
    selected = list(st.get("selected") or [])
    for info in library:
        if info["id"] not in seen:
            seen.add(info["id"])
            if info.get("owned") and not info.get("spotifyMade") and info["id"] not in selected:
                selected.append(info["id"])
    # A linked playlist the user deleted in Nutsty stays deleted: unlink it instead of re-creating it
    linked = set(st.get("linked") or [])
    present = {pid for pid in selected if _find_linked(playlists_snapshot, pid)}
    selected = [pid for pid in selected if pid in present or pid not in linked]
    st["seen"], st["selected"], st["linked"] = sorted(seen), selected, sorted((linked & set(selected)) | present)
    gone = _gone_on_spotify(st, client, library, complete, selected, linked, present)

    force = set(st.get("forceApply") or [])
    error = ""
    try:
        for info in library:
            pid = info["id"]
            if pid not in selected:
                continue
            try:
                _fetch_one(st, info, client, match, cache, now, playlists_snapshot, force, baseline, fetched, reverse)
            except sw.SpotifyError as e:
                if e.code not in _SKIP_ONE:
                    raise
                sys.stderr.write(f"[spotify_sync] playlist {pid} skipped: {e.code}\n")
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
        _note_error(st, e, now)
        error = e.code
    return library, fetched, liked_remote, reverse, error, gone


# A linked list absent from the library this many runs in a row was deleted (or removed) on Spotify
MISSING_RUNS = 2


def _gone_on_spotify(st, client, library, complete, selected, linked, present):
    """Linked lists the user deleted on Spotify: absent from a complete library read twice running,
    read as the account the links were made with. Returns their Spotify ids."""
    account = client.me()["id"]
    if not st.get("account"):
        st["account"] = account
    if st["account"] != account or not complete:
        return []
    ids = {info["id"] for info in library}
    missing, gone = {}, []
    for pid in selected:
        if pid in linked and pid in present and pid not in ids:
            runs = int((st.get("missing") or {}).get(pid) or 0) + 1
            if runs >= MISSING_RUNS:
                gone.append(pid)
            else:
                missing[pid] = runs
    st["missing"] = missing
    return gone


def _drop_gone(playlists, st, gone):
    """Delete the Nutsty copy of each list deleted on Spotify, and forget its sync state."""
    gone = set(gone)
    keep = [p for p in playlists if not (isinstance(p, dict) and ((p.get("spotifyLink") or {}).get("id") in gone))]
    _forget_ids(st, gone)
    return keep


def _forget_ids(st, ids):
    st["selected"] = [p for p in st.get("selected") or [] if p not in ids]
    st["linked"] = [p for p in st.get("linked") or [] if p not in ids]
    for key in ("localBaseline", "writeBackAbsent", "missing"):
        st[key] = {k: v for k, v in (st.get(key) or {}).items() if k not in ids}


def _push_deletes(client, library, st):
    """Remove from Spotify the lists the user deleted in Nutsty with write-back on. One that is no longer
    in the library is already gone; a failed call stays queued for the next run."""
    kinds = {info["id"]: info.get("kind") for info in library}
    queue = list(st.get("deleteRemote") or [])
    for pid in list(queue):
        if pid in kinds:
            try:
                if kinds[pid] == "album":
                    client.remove_from_library([f"spotify:album:{pid}"])
                else:
                    client.remove_playlist(pid)
            except sw.SpotifyError as e:
                st["deleteRemote"] = queue
                return e.code
        queue.remove(pid)
    st["deleteRemote"] = queue
    return ""


def _note_error(st, e, now):
    if isinstance(e, sw.SpotifyRateLimited):
        st["retryAt"] = now + max(1.0, float(e.retry_after or 60.0))


# One playlist that cannot be read (deleted by its owner, made private) is skipped; anything that
# means the whole account is unreachable (auth, rate limit, network, query change) stops the cycle.
_SKIP_ONE = ("not_found", "http_error", "graphql_error")


def _fetch_one(st, info, client, match, cache, now, playlists_snapshot, force, baseline, fetched, reverse):
    pid = info["id"]
    rec = _find_linked(playlists_snapshot, pid)
    link = (rec or {}).get("spotifyLink") or {}
    wb = bool(rec) and _wb_on(st, info) and pid in baseline
    if (rec and info.get("revision") and link.get("libRevision") == info["revision"]
            and not link.get("unmatched") and pid not in force
            and not (wb and _push_pending(rec, st, pid))):
        return
    remote = client.album_items(pid) if info.get("kind") == "album" else client.playlist_items(pid)
    if not merge.remote_is_valid(remote):
        return
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


def _learn(cache, tracks, now):
    """A Nutsty track that already carries a Spotify id is that id's match: record it, so the id is
    not reported unmatched (and kept out of base) once write-back has put it on Spotify."""
    for t in tracks:
        if not isinstance(t, dict) or not t.get("videoId"):
            continue
        for sid in track_ids(t):
            hit = cache.get(sid)
            if not hit or hit.get("unmatched"):
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
    before = None
    if rec is not None:
        _learn(cache, rec.get("tracks") or [], now)
        before = [dict(t) if isinstance(t, dict) else t for t in rec.get("tracks") or []]
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
        if _wb_on(st, info):
            # Two-way already on: the copy is exactly Spotify's, so anything added here from now on is
            # the user's own edit. Noting it later would swallow the edits made in between.
            _note_baseline(st, pid, ordered, new_base)
    elif info.get("spotifyMade"):
        rec["tracks"] = ordered
        new_base = [s for s in remote_ids if s in matched]
    else:
        link = rec.get("spotifyLink") or {}
        base = link.get("base") or []
        tracks = [dict(t) if isinstance(t, dict) else t for t in rec.get("tracks") or []]
        wb = _wb_on(st, info)
        if wb and pid not in (st.get("localBaseline") or {}):
            # Linked after write-back went on (picked later, migrated, or carried in from another
            # device): note what it holds now, as switch-on does, and push nothing this cycle.
            _note_baseline(st, pid, tracks, base)
            wb = False
        if wb:
            keys = set((st.get("localBaseline") or {}).get(pid) or [])
            for t in tracks:
                if _needs_reverse(t, keys):
                    found = (reverse or {}).get((pid, pm.get_track_unique_key(t)))
                    if found:
                        t["spotifyId"] = found
            local = _wb_local([(sid, t) for t in tracks for sid in track_ids(t)],
                              set(base), set(remote_ids), keys)
        else:
            local = [sid for t in tracks for sid in track_ids(t)]
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
        tracks = [t for t in tracks if not isinstance(t, dict) or drop_track_ids(t, gone)]
        by_video = {t.get("videoId"): t for t in tracks if isinstance(t, dict) and t.get("videoId")}
        for sid in r.pull_add:
            m = matched.get(sid)
            if not m:
                continue
            if m["videoId"] in by_video:
                add_track_id(by_video[m["videoId"]], sid)
            else:
                tracks.append(dict(m))
                by_video[m["videoId"]] = tracks[-1]
        rec["tracks"] = tracks
        # Base holds only what Spotify has now; each push that lands is added afterwards (_patch_bases),
        # so a crash or a failed write leaves the change pending instead of deleting it next cycle.
        new_base = [s for s in merge._dedupe(remote_ids) if s not in unmatched]
        if wb and (r.push_add or push_remove) and jobs is not None:
            jobs.append({"list": pid, "add": list(r.push_add), "remove": push_remove})
    old_link = rec.get("spotifyLink") or {}
    old_count = rec.get("trackCount")
    rec["trackCount"] = len(rec["tracks"])
    link = {"id": pid, "owned": bool(info.get("owned")), "editable": _editable(info),
            "spotifyMade": bool(info.get("spotifyMade")),
            "base": new_base, "revision": remote.revision or "",
            "libRevision": info.get("revision") or "", "syncedAt": now, "unmatched": len(unmatched)}
    if info.get("kind") == "album":
        link["kind"] = "album"              # the page says Spotify does not let anyone edit it
    if "title" in old_link:
        link["title"] = old_link["title"]   # the agreed name, kept by _merge_titles
    if (before is not None and rec["tracks"] == before and old_count == rec["trackCount"]
            and dict(old_link, syncedAt=now) == link):
        # Nothing moved: leave the record byte-identical, so account_sync does not see a fresh
        # edit that would win over another device's newer change.
        return False
    rec["spotifyLink"] = link
    return True


def _merge_titles(playlists, library, st, renames):
    """Names merge like tracks, against the last agreed name kept in spotifyLink.title: a Spotify
    rename is pulled; a Nutsty rename is queued in `renames` when write-back may touch the list,
    else it stays local. Both renamed: Spotify wins. A link from before names were tracked takes
    Spotify's name as agreed, so a name the user gave in Nutsty is kept. Returns True on a change."""
    changed = False
    for info in library:
        rec = _find_linked(playlists, info["id"])
        link = (rec or {}).get("spotifyLink")
        remote = str(info.get("title") or "").strip()
        if not link or not remote:
            continue
        base = link.get("title") or remote
        local = str(rec.get("title") or "").strip()
        if remote != base or not local:
            if rec.get("title") != remote or rec.get("name") != remote:
                rec["title"] = rec["name"] = remote
                changed = True
            agreed = remote
        else:
            agreed = base
            if local != base and _wb_on(st, info):
                renames.append((info["id"], local))
        if link.get("title") != agreed:
            link["title"] = agreed
            changed = True
    return changed


def _push_renames(client, renames, st, now):
    """Rename on Spotify, then record the name as agreed. Stops at the first error: the rename is
    still pending (agreed name unchanged) and goes again next cycle."""
    for pid, name in renames:
        if not sstate.load_state().get("writeBack"):
            return ""
        try:
            client.rename_playlist(pid, name)
        except sw.SpotifyError as e:
            _note_error(st, e, now)
            return e.code
        with pm.locked():
            playlists = pm.load_playlists()
            rec = _find_linked(playlists, pid)
            if rec and rec.get("spotifyLink"):
                rec["spotifyLink"]["title"] = name
                pm.save_playlists(playlists)
    return ""


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
        ids = track_ids(v) or [cache.find_by_video(v.get("videoId") or key)]
        for sid in ids:
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
        # A like that has been on Spotify and is gone there now was unliked on Spotify; this device
        # only missed it (its base came later, the entry over account sync). Never like it again.
        r.push_add = [s for s in r.push_add if not liked.get(local_of.get(s), {}).get("spotifySynced")]
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
    gone = set(pull_remove)
    for sid in pull_remove:
        key = local_of.get(sid)
        if key in liked and not drop_track_ids(liked[key], gone):
            del liked[key]
            changed = True
        elif key in liked:
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
            changed = add_track_id(liked[vid], sid) or changed
            continue
        liked[vid] = _liked_entry(m, now)
        changed = True
    remote_set = set(remote_ids)
    for v in liked.values():
        if isinstance(v, dict) and not v.get("spotifySynced") and remote_set.intersection(track_ids(v)):
            v["spotifySynced"] = True
            changed = True
    st["likedBase"] = new_base
    if changed:
        pm._write_json(pm._liked_file(), liked)
    return changed


def _push(client, jobs, sleep, st=None, now=0.0):
    """Send the queued writes slowly: fresh read first (skip what Spotify already has, find uids),
    at most PUSH_CAP tracks, PUSH_GAP_SEC between calls. Stops at the first error or when the switch
    is turned off. Returns ({list: (added, removed)}, error_code)."""
    done, budget, calls, written = {}, PUSH_CAP, 0, 0

    def read(lid):
        return client.liked_items() if lid == "liked" else client.playlist_items(lid)

    for job in jobs:
        if budget <= 0:
            break
        lid = job["list"]
        try:
            fresh = read(lid)
        except sw.SpotifyError as e:
            if st is not None:
                _note_error(st, e, now)
            return done, e.code, written
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
            sent = 0
            while ids and budget > 0:
                if calls:
                    sleep(PUSH_GAP_SEC)
                if not sstate.load_state().get("writeBack"):
                    return done, "", written
                if kind == "add" and sent:
                    # another device may have added some meanwhile: look again before each later batch
                    try:
                        again = read(lid)
                    except sw.SpotifyError as e:
                        if st is not None:
                            _note_error(st, e, now)
                        return done, e.code, written
                    if not merge.remote_is_valid(again):
                        break
                    have = {i["spotifyId"] for i in again.items}
                    added.extend(s for s in ids if s in have)
                    ids = [s for s in ids if s not in have]
                    if not ids:
                        break
                batch, ids = ids[:min(PUSH_BATCH, budget)], ids[min(PUSH_BATCH, budget):]
                calls += 1
                sent += 1
                uris = [f"spotify:track:{s}" for s in batch]
                try:
                    if lid == "liked":
                        (client.add_to_library if kind == "add" else client.remove_from_library)(uris)
                    elif kind == "add":
                        client.add_to_playlist(lid, uris)
                    else:
                        client.remove_from_playlist(lid, [u for s in batch for u in uids[s] if u])
                except sw.SpotifyError as e:
                    if st is not None:
                        _note_error(st, e, now)
                    return done, e.code, written
                budget -= len(batch)
                written += len(batch)
                (added if kind == "add" else removed).extend(batch)
    return done, "", written


def _mark_synced(sids):
    """Liked entries standing for `sids` are on Spotify now (see spotifySynced in _apply_liked)."""
    sids = set(sids)
    if not sids:
        return
    liked = pm._read_json(pm._liked_file(), {})
    if not isinstance(liked, dict):
        return
    dirty = False
    for v in liked.values():
        if isinstance(v, dict) and not v.get("spotifySynced") and sids.intersection(track_ids(v)):
            v["spotifySynced"] = True
            dirty = True
    if dirty:
        pm._write_json(pm._liked_file(), liked)


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
                _mark_synced(added)
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
        library, fetched, liked_remote, reverse, error, gone = _fetch(st, client, match, cache, now, snapshot)
    except sw.SpotifyError as e:
        _note_error(st, e, now)
        return _result(False, e.code)
    blocked, changed, jobs = [], {"playlists": False, "liked": False}, []
    unmatched = 0
    with pm.locked():
        playlists = pm.load_playlists()
        before = [p.get("id") if isinstance(p, dict) else None for p in playlists]
        playlists = migrate_legacy_imports(playlists, {pid: r for pid, (_i, r) in fetched.items()}, match, cache, now)
        for pid, (info, remote) in fetched.items():
            if _apply_playlist(playlists, info, remote, st, cache, now, blocked, reverse, jobs):
                changed["playlists"] = True
            unmatched += _matched_map(remote, cache)[1].__len__()
        if gone:
            playlists = _drop_gone(playlists, st, gone)
            fetched = {pid: v for pid, v in fetched.items() if pid not in gone}
        renames = []
        if _merge_titles(playlists, library, st, renames):
            changed["playlists"] = True
        if changed["playlists"] or [p.get("id") if isinstance(p, dict) else None for p in playlists] != before:
            pm.save_playlists(playlists)
        st["linked"] = sorted(set(st.get("linked") or []) | {pid for pid in fetched if _find_linked(playlists, pid)})
        if liked_remote is not None:
            changed["liked"] = _apply_liked(liked_remote, st, cache, now, blocked, reverse, jobs)
            unmatched += len(_matched_map(liked_remote, cache)[1])
    pushed = 0
    if jobs and not error:
        done, error, pushed = _push(client, jobs, sleep, st, now)
        _patch_bases(st, done)
    if renames and not error:
        error = _push_renames(client, renames, st, now)
    if st.get("deleteRemote") and not error:
        error = _push_deletes(client, library, st)
    return _result(not error, error, changed=changed, blocked=blocked, unmatched=unmatched, pushed=pushed)


def _keep_user_changes(st, orig):
    """The user may flip a switch or change the selection while a run is in flight: whatever a
    route changed on disk since the run loaded the state wins over the run's copy. Call under STATE_LOCK."""
    disk = sstate.load_state()
    for k in _USER_KEYS:
        if disk.get(k) != orig.get(k):
            st[k] = disk[k]
    consumed = set(orig.get("forceApply") or []) - set(st.get("forceApply") or [])
    st["forceApply"] = [p for p in disk.get("forceApply") or [] if p not in consumed]
    sent = set(orig.get("deleteRemote") or []) - set(st.get("deleteRemote") or [])
    st["deleteRemote"] = [p for p in disk.get("deleteRemote") or [] if p not in sent]
    st["seen"] = sorted(set(st.get("seen") or []) | set(disk.get("seen") or []))
    st["backlog"] = disk.get("backlog") or {}


def sync_once(profile="", client=None, matcher=None, now=None, sleep=None):
    if not _RUN_LOCK.acquire(blocking=False):
        return _result(False, "busy")
    try:
        with pm.profile_scope(profile):
            st = sstate.load_state()
            orig = copy.deepcopy(st)
            if not st.get("enabled") or not st.get("selectionConfirmed"):
                return _result(False, "disabled")
            now = time.time() if now is None else now
            if now < float(st.get("retryAt") or 0):
                return _result(False, "rate_limited")
            cache = sstate.MatchCache()
            try:
                client = client or _default_client()
                res = _cycle(st, client, matcher or _default_matcher(), cache, now, sleep or time.sleep)
            except sw.SpotifyError as e:
                _note_error(st, e, now)
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
            with sstate.STATE_LOCK:
                _keep_user_changes(st, orig)
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
    with sstate.edit_state() as st:
        st["backlog"] = {"done": 0, "total": 0, "unmatched": 0, **(st.get("backlog") or {}), **kw}


def _backlog_commit(pairs):
    """Record pushed (key, sid) pairs: liked entries get their id, base gains it, baseline loses the key."""
    keys = {k for k, _s in pairs}
    with pm.locked():
        liked = pm._read_json(pm._liked_file(), {})
        if isinstance(liked, dict):
            dirty = False
            for key, sid in pairs:
                for k, v in liked.items():
                    if isinstance(v, dict) and pm.get_track_unique_key(v) == key:
                        if add_track_id(v, sid) or not v.get("spotifySynced"):
                            v["spotifySynced"] = True
                            dirty = True
            if dirty:
                pm._write_json(pm._liked_file(), liked)
        with sstate.edit_state() as st:
            base = list(st.get("likedBase") or [])
            base += [sid for _k, sid in pairs if sid not in set(base)]
            st["likedBase"] = base
            lb = dict(st.get("localBaseline") or {})
            lb["liked"] = [k for k in lb.get("liked") or [] if k not in keys]
            st["localBaseline"] = lb


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
            elif v.get("spotifySynced") and sid not in have:
                continue  # was on Spotify and unliked there: not an earlier like to push
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
        library = _library(client)
        chosen = set(st.get("selected") or [])
        out = []
        for info in library:
            if st.get("selectionConfirmed"):
                sel = info["id"] in chosen
            else:
                sel = bool(info.get("owned")) and not info.get("spotifyMade")
            out.append(dict(info, selected=sel))
        # merge only what this call learned: the network call above may have outlived a route's change
        with sstate.edit_state() as disk:
            disk["seen"] = sorted(set(disk.get("seen") or []) | {p["id"] for p in library})
        return {"playlists": out, "liked": bool(st.get("likedSelected"))}


def set_selection(profile, ids, liked):
    with pm.profile_scope(profile):
        with sstate.edit_state() as st:
            st.update(selected=[str(i) for i in ids], likedSelected=bool(liked), selectionConfirmed=True)
            st["seen"] = sorted(set(st.get("seen") or []) | set(st["selected"]))
            # picking a list again after deleting its copy brings it back
            st["linked"] = [p for p in st.get("linked") or [] if p not in set(st["selected"])]
        return status(profile)


def set_enabled(profile, enabled):
    with pm.profile_scope(profile):
        with sstate.edit_state() as st:
            st["enabled"] = bool(enabled)
        return status(profile)


def set_write_back(profile, on, now=None):
    """On: note what Nutsty already holds, so only later changes are pushed (spec 5.6). Off: forget it."""
    with pm.profile_scope(profile), sstate.STATE_LOCK:
        st = sstate.load_state()
        if not on:
            st.update(writeBack=False, writeBackSince=0.0, localBaseline={}, writeBackAbsent={})
            sstate.save_state(st)
            return status(profile)
        if st.get("writeBack"):
            return status(profile)  # already on: keep the baseline taken at switch-on
        cache = sstate.MatchCache()
        baseline, absent = {}, {}
        for pl in pm.load_playlists():
            link = (pl.get("spotifyLink") or {}) if isinstance(pl, dict) else {}
            if not link.get("id") or not _editable(link):
                continue
            tracks = [t for t in pl.get("tracks") or [] if isinstance(t, dict)]
            baseline[link["id"]] = [pm.get_track_unique_key(t) for t in tracks]
            absent[link["id"]] = _absent_ids(tracks, link.get("base"))
        liked = pm._read_json(pm._liked_file(), {})
        liked = liked if isinstance(liked, dict) else {}
        baseline["liked"] = [pm.get_track_unique_key(v) for v in liked.values() if isinstance(v, dict)]
        have = set()
        for k, v in liked.items():
            if isinstance(v, dict):
                have.update(track_ids(v) or [cache.find_by_video(v.get("videoId") or k)])
        absent["liked"] = [s for s in st.get("likedBase") or [] if s not in have]
        # backlog {} = the earlier-likes push of this switch-on has not run yet (the app starts it)
        st.update(writeBack=True, writeBackSince=time.time() if now is None else now,
                  localBaseline=baseline, writeBackAbsent=absent, backlog={})
        sstate.save_state(st)
        return status(profile)


def forget_playlist(profile, pid):
    """The user deleted a linked list in Nutsty, after the delete dialog said what happens: stop syncing
    it now, and with write-back on queue its removal from Spotify for the next run."""
    with pm.profile_scope(profile):
        with sstate.edit_state() as st:
            known = pid in (st.get("linked") or []) or pid in (st.get("selected") or [])
            queued = bool(known and st.get("enabled") and st.get("writeBack"))
            if queued and pid not in st["deleteRemote"]:
                st["deleteRemote"].append(pid)
            if known:
                _forget_ids(st, {pid})
        return dict(status(profile), queued=queued)


def force_apply(profile, pid):
    with pm.profile_scope(profile):
        with sstate.edit_state() as st:
            if pid not in st["forceApply"]:
                st["forceApply"].append(pid)
        return status(profile)


def status(profile=""):
    with pm.profile_scope(profile):
        st = sstate.load_state()
        backlog = {"done": 0, "total": 0, "unmatched": 0, "error": "", **(st.get("backlog") or {})}
        backlog["running"] = profile in _BACKLOG_ACTIVE
        return {k: st.get(k) for k in ("enabled", "selectionConfirmed", "likedSelected", "writeBack",
                                       "lastSync", "lastError", "blocked", "unmatchedCount")} | {
            "backlog": backlog, "backlogRan": bool(st.get("backlog")),
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
        elif op == "forget":
            res = forget_playlist(profile, str(body.get("id") or ""))
        else:
            handler._send_json({"success": False, "error": f"unknown_op: {op}"}, 404)
            return
    except sw.SpotifyError as e:
        res = {"success": False, "error": e.code}
    except Exception as e:
        sys.stderr.write(f"[spotify_sync] {op} failed: {e}\n")
        res = {"success": False, "error": "internal"}
    handler._send_json(res, 200)
